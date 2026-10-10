# I/O — 유형별 상세

유형 = Input 방향 (Pull / Accept) × Source × Output (Send / Store). §1~4 는 Pull, §5 는 Accept.

Input 방향은 **누가 처리 속도를 정하고 Position 을 갖는가** 로 가른다. 연결을 누가 먼저 여는지가 기준이 아니다. 데몬이 속도와 Position 을 쥐면 Pull, 보내는 쪽이 속도를 정하고 데몬은 받아서 확인 응답하면 Accept 다. 예: RabbitMQ consume 은 선 위에서는 브로커 push 지만 데몬이 prefetch 로 속도를 정하므로 Pull 이다. 흔한 대응어 (pull/push, TCP active/passive open — [RFC 9293](https://www.rfc-editor.org/rfc/rfc9293.html)) 와 겹치지만 같지 않다.

독성 입력·DLQ 처리 원칙은 `chassis-failure.md`, 멱등 쓰기는 `contract.md`.

## 1. 큐·스트림 소비자

### 브로커 비교

| 브로커 | 확인 응답 단위 | 재전달 조건 | 브로커 중복 제거 | Backpressure 수단 | DLQ |
|---|---|---|---|---|---|
| Kafka | 파티션별 offset (누적) | 커밋 전 리밸런스·crash | 없음 (EOS 는 Kafka 안에서만) | `pause()`/`resume()`, `max.poll.records` | 직접 구현 (재시도·DLT 토픽) |
| SQS standard | 메시지별 `DeleteMessage` | visibility timeout 만료 | 없음 (중복 수신 가능) | 수신 중단, `MaxNumberOfMessages` | `RedrivePolicy.maxReceiveCount` |
| SQS FIFO | 메시지별 (그룹 순서) | visibility timeout 만료 (그룹이 막힘) | 5분 (`MessageDeduplicationId`) | 그룹 수, 수신 중단 | 동일 (FIFO DLQ) |
| Kafka share group (4.2+) | 레코드별 (accept·release·reject, `RENEW` 로 락 연장) | 락 만료·release | 없음 | `record_limit` + `max.poll.records` 로 받는 양을 줄인다 (`pause()` 없음. 상세 아래 절). 오래 멈출 때는 쥔 레코드를 RELEASE 한 뒤 `close()` | 직접 구현 (한도 초과 시 archive = 폐기) |
| RabbitMQ quorum | 메시지별 ack (`multiple` 가능) | nack·reject·채널 끊김 | 없음 | prefetch (`basic.qos`) | `delivery-limit` (기본 20) + DLX |
| PostgreSQL 큐 | 행 상태 갱신·삭제 (트랜잭션) | lease 만료, 롤백 | UNIQUE 로 직접 | `LIMIT n`, 워커 수 | `attempts` 컬럼 → failed 상태 |

### SinkDown (Sink 전체 장애) 중 쥔 메시지

- SinkDown 동안에는 수신을 멈추고 쥔 메시지를 반환하지 말고 연장하며 들고 있는다. 반환하면 다시 받을 때 전달 횟수가 올라 긴 장애 동안 정상 메시지가 DLQ·failed 로 간다 (SQS receive count → `maxReceiveCount`, PG `attempts`, RabbitMQ `delivery-count`, share group delivery count). 연장 상한 (SQS 는 최초 수신부터 12h) 전에는 반환하고, 전달 한도는 장애 중 반환 횟수를 감안해 여유 있게 잡는다. 판정은 SKILL.md 의 SinkDown 판정

### Kafka

- `enable.auto.commit=false` (또는 librdkafka 계열은 `enable.auto.offset.store=false` 로 처리한 offset 만 store) — 처리를 마친 offset 만 커밋
  - librdkafka 는 `enable.auto.commit=true` + `enable.auto.offset.store=false` 도 된다. 처리 끝난 offset 만 store 하면 주기 커밋 (기본 5s) 이 그 지점까지만 커밋한다. 재처리 구간이 주기만큼 넓어지고, revoke 때는 store 한 offset 을 동기 커밋해야 한다
  - offset 을 직접 지정하는 API (Java `commitSync(Map)`, `rd_kafka_offsets_store`, KafkaJS `commitOffsets`) 는 처리한 offset **+1** 을 넘긴다
  - 메시지를 넘기는 API (confluent-kafka `store_offsets(message=...)`, Go `StoreMessage`) 는 라이브러리가 +1 하므로 더하지 않는다 ([rdkafka.h](https://github.com/confluentinc/librdkafka/blob/master/src/rdkafka.h))
- librdkafka 는 2.4.0+ 를 쓴다. 그 미만은 멈추지 않은 파티션 resume 때 중복 (#4686), 1.9.0 미만은 seek→pause→resume 이 seek 위치를 덮어써 유실 (#3471) ([CHANGELOG](https://github.com/confluentinc/librdkafka/blob/master/CHANGELOG.md))
- `max.poll.interval.ms` (기본 5분) 안에 다음 poll 이 없으면 그룹에서 쫓겨나 리밸런스 → 그 뒤 커밋은 실패하고 같은 배치를 다시 처리. 긴 처리는 `pause()` 상태로 poll 을 계속 부르거나 `max.poll.records` 를 줄인다
- 리밸런스: classic 프로토콜이면 `cooperative-sticky` (바뀌는 파티션만 넘김). **Kafka 4.0+ 의 새 프로토콜 (KIP-848) 은 클라이언트가 `group.protocol=consumer` 로 opt-in** 한다 (classic 이 아직 기본). `session.timeout.ms`·`heartbeat.interval.ms` 는 서버 설정 (`group.consumer.*`) 으로 옮겨 가고, assignor 는 `group.remote.assignor` 로 서버 목록 `group.consumer.assignors` 안에서만 고른다 (`partition.assignment.strategy` 불가) ([rebalance protocol](https://kafka.apache.org/43/operations/consumer-rebalance-protocol/))
- revoke 콜백: 그 파티션의 진행 중 작업을 끝내고 (또는 버리고) **동기 커밋** 후 넘긴다. lost 콜백: 이미 소유권을 잃었으므로 커밋하지 말고 버린다
- 바뀌지 않은 구독을 매번 다시 걸면 리밸런스가 끝없이 돈다 (OpenMeter 주석). 한 그룹 안에서 인스턴스마다 구독 토픽이 다르면 리밸런스가 계속 돈다 (사내 소비자 코드 주석)
- static membership (`group.instance.id` = 파드 이름) 은 롤링 재시작 때 세션 타임아웃 안에 돌아오면 리밸런스를 생략한다
- 파티션 키 = 순서·중복 판정이 필요한 단위 (같은 키는 같은 파티션)
- 병렬 처리: 파티션당 하나의 실행 흐름이 단순하다. 파티션 안 병렬이면 "빈틈 없이 끝난 offset" 추적이 필요하다. **처음 실패한 offset 앞까지만 커밋하되, 건너뛴 항목은 seek back 하거나 재시도 큐로 보내야** 한다 (안 그러면 다음 커밋이 넘어가며 유실 — Lago 사례)

### Kafka share group (KIP-932, "Queues for Kafka")

- 4.2 에서 production-ready. 파티션 소유 대신 레코드 단위로 락을 걸어 가져가므로 **소비자 수가 파티션 수를 넘어도 된다**. 순서 보장은 포기한다
- **4.2.1 이상을 쓴다** (share group 데드락 수정 KAFKA-20505)
- 확인 응답
  - 레코드별 accept·release·reject. `share.acknowledgement.mode=explicit` 를 쓴다
  - 기본 implicit 은 다음 `poll()` 이 직전 배치를 모두 ACCEPT 하므로 처리 전에 poll 하면 유실된다
  - commit 실패는 두 모드 모두 poll 경로에서 예외가 없다 → `commitSync()` 반환 Map 이나 `setAcknowledgementCommitCallback` 으로 확인한다. explicit 에서 전부 확인 응답하지 않고 poll 하면 IllegalStateException
  - 근거: [KafkaShareConsumer](https://kafka.apache.org/43/javadoc/org/apache/kafka/clients/consumer/KafkaShareConsumer.html)
- 락 연장 (`RENEW`)
  - 처리가 길면 `RENEW` 로 락을 연장한다. explicit 에서만 되며 poll 반복마다 다시 보낸다
  - RENEW 한 레코드는 다음 poll 이 다시 돌려준다 → (topic, partition, offset) 키의 처리 중 집합으로 걸러 새로 시작하지 않는다. javadoc 예제처럼 offset 만 키로 쓰면 파티션끼리 겹친다
  - 연장 주기는 `acquisitionLockTimeoutMs()` 의 절반
- RELEASE
  - RELEASE 는 지연 없이 다시 전달 가능 상태가 되고, 다음 획득 때 전달 횟수가 1 오른다 (이미 한도면 RELEASE 즉시 archive). 재전달 지연 설정은 없다 ([SharePartition](https://github.com/apache/kafka/blob/4.3.0/core/src/main/java/kafka/server/share/SharePartition.java))
  - SinkDown 에 RELEASE 를 반복하면 기본 한도 5회를 금방 다 써서 archive (폐기) 된다 → 쥔 레코드를 RENEW 하며 프로세스 안에서 백오프하고, 장애가 길면 RELEASE 후 `close()` 로 소비를 멈춘다 (§1 SinkDown 절)
  - 메시지 단위 Transient (Sink 는 건강한데 그 메시지만 실패) 는 RENEW 하며 프로세스 안에서 백오프하고, N 회 뒤 DLQ 토픽에 쓴 다음 reject 한다
  - RELEASE 는 (a) 다른 소비자가 처리하면 성공할 실패, (b) 장기 장애로 소비를 멈출 때 쥔 레코드 반환에만 쓴다
  - (b) 뒤 재개는 다시 가져갈 때마다 전달 횟수를 쓰므로 Sink 회복을 확인한 뒤에 한다 (close → 재개를 반복하면 기본 5회 뒤 archive)
- Backpressure
  - `share.acquire.mode=record_limit` + `max.poll.records` 로 받는 양을 줄인다. 기본 `batch_optimized` 는 상한을 넘겨 반환하고 prefetch 하며, prefetch 된 레코드도 락이 걸려 있다
  - 오래 멈출 때는 쥔 레코드를 RELEASE 한 뒤 `close()` (남은 acquired 레코드를 반환). 쥔 채 멈추면 락 만료가 전달 횟수를 소모한다
  - 근거: [consumer configs](https://kafka.apache.org/43/configuration/consumer-configs/)
- 시작 위치
  - 그룹 설정 `share.auto.offset.reset` (기본 latest, kafka-configs 로 설정) 이다
  - 기존 적체를 처리하려면 그룹을 쓰기 전에 earliest 또는 by_duration 으로 설정한다
  - 근거: [group configs](https://kafka.apache.org/43/configuration/group-configs/)
- 독성 처리: 브로커 `group.share.delivery.count.limit` (기본 5) 가 전달 횟수를 제한한다 (4.3+ 는 그룹 설정 `share.delivery.count.limit` 로 덮어쓴다). 한도를 넘은 레코드는 DLQ 가 아니라 archive (폐기) 된다. DLQ (KIP-1191) 는 아직 미출시
  - 락 만료 (`group.share.record.lock.duration.ms` 기본 30s) 도 전달 1회로 센다 → 긴 처리는 `RENEW`
  - Poison 은 소비자가 직접 DLQ 토픽에 쓴 뒤 reject 한다
- 근거: [4.2.0 릴리스 공지](https://kafka.apache.org/blog/2026/02/17/apache-kafka-4.2.0-release-announcement/)

### SQS

- visibility timeout 기본 30s. 처리 중에는 heartbeat 로 `ChangeMessageVisibility` 를 반복 연장 (최초 수신부터 12h 상한). 포기할 때는 0 으로 바꿔 즉시 반환. SinkDown 중에는 반환하지 않고 연장한다 (§1 SinkDown 절. 반환마다 receive count 가 올라 `maxReceiveCount` 에 닿으면 DLQ 로 간다) ([visibility timeout](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-visibility-timeout.html))
- long polling `WaitTimeSeconds=20`
- `DeleteMessageBatch` 는 일부 실패해도 HTTP 200 → `Failed[]` 를 반드시 확인
- in-flight 상한 (standard 약 12만) 에 닿으면 long polling 은 에러 없이 빈 응답, short polling 은 `OverLimit` 에러. FIFO 상한은 활성 메시지 그룹 수에 따라 달라진다
- fair queues (2025-07): standard 큐 메시지에 `MessageGroupId` 를 붙이면 시끄러운 테넌트의 우선순위가 내려간다. 소비자 코드 변경 없음. 멀티 테넌트 워커면 쓴다 ([fair queues](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-fair-queues.html)). 테넌트 격리 일반론은 `chassis-overload.md` §4

### RabbitMQ

- 수동 ack + `basic.qos(prefetch)` 가 Backpressure. prefetch 무제한은 메모리 폭주
- 4.3 부터 카운터가 둘로 갈렸다. `acquired-count` 는 재큐잉마다, `delivery-count` 는 실패일 때만 올라가며 delivery-limit 은 `delivery-count` 를 본다
  - 올림: `basic.reject`, 클라이언트 crash·연결 끊김
  - 안 올림: `basic.nack`, consumer timeout (AMQP 1.0 의 released·`modified(delivery-failed=false)` 도)
  - 결과: `basic.nack(requeue=true)` 만 쓰는 소비자는 독성 메시지를 무한 반복하고 DLQ 에 닿지 않는다 → `basic.reject` 를 쓰거나 `requeue=false` 로 DLX 에 보낸다
- SinkDown 중에는 수신을 멈추고 prefetch 로 쥔 메시지를 reject·크래시로 반환하지 않는다 (§1 SinkDown 절). ack 를 미루고 들고 있되 consumer timeout (기본 30분, 큐별 `x-consumer-timeout`) 안에서만 된다. 장애가 그보다 길면 4.3+ 는 `nack(requeue=true)` 로 돌려주고 소비를 멈춘다 (`delivery-count` 를 올리지 않는다). 4.2 이하는 어떤 반환이든 `delivery-count` 를 올리므로 consumer timeout 을 장애 예상 시간보다 길게 잡는다 ([consumers](https://www.rabbitmq.com/docs/consumers))
- 4.3 Delayed Retries: 큐 안에서 브로커가 지연시키므로 재발행이 없어 중복이 생기지 않는다. `x-delayed-retry-type` = `all`|`returned`|`failed`, `x-delayed-retry-min`/`max`, 지연 = min(min × delivery-count, max) (선형)
- 근거: [quorum queues](https://www.rabbitmq.com/docs/quorum-queues), [4.3 릴리스](https://www.rabbitmq.com/blog/2026/04/23/rabbitmq-4.3-release)

### PostgreSQL 을 큐로

```sql
-- 가져가기 (lease)
WITH picked AS (
  SELECT idx FROM jobs
  WHERE status = 'pending' AND attempts < $max
    AND (locked_until IS NULL OR locked_until < now())
  ORDER BY idx LIMIT $n
  FOR UPDATE SKIP LOCKED)
UPDATE jobs SET locked_by = $worker, locked_until = now() + interval '60 seconds', attempts = attempts + 1
FROM picked WHERE jobs.idx = picked.idx
RETURNING jobs.*;

-- 완료·연장·실패 UPDATE 는 모두 이 조건을 단다
-- WHERE idx = $id AND locked_by = $worker AND attempts = $attempts_seen
```

- 완료·연장·실패 UPDATE 가 0 rows 면 lease 를 잃은 것이다 → 결과를 버린다 (다른 워커가 이미 가져갔다). 결과 쓰기를 완료 UPDATE 와 같은 트랜잭션에 넣으면 0 rows 일 때 롤백한다. 외부 Sink 면 이미 반영됐으므로 멱등 Sink 로 흡수한다
- 한도 (`attempts >= $max`) 에 닿은 행은 가져가기에서 빠지므로 `failed` 상태로 옮긴다. 별도 쿼리는 `status = 'pending' AND attempts >= $max AND (locked_until IS NULL OR locked_until < now())` 인 행만 옮긴다. 또는 실패 UPDATE 에서 `status = CASE WHEN attempts >= $max THEN 'failed' ELSE 'pending' END` 로 바로 옮긴다

- SinkDown 중에는 새로 가져가지 않고, 쥔 행은 `locked_until` 을 연장하며 들고 있는다. 만료시켜 놓으면 다시 가져갈 때 `attempts` 가 올라 정상 행이 `failed` 로 간다 (§1 SinkDown 절)
- 긴 작업은 트랜잭션을 잡고 있지 말고 lease 컬럼으로. 처리 중 `locked_until` 연장 (heartbeat), 만료된 lease 는 다른 워커가 가져간다
- `LISTEN/NOTIFY` 는 깨우는 신호로만. 연결이 끊기면 알림이 사라지므로 주기 폴링을 같이 둔다 ([NOTIFY](https://www.postgresql.org/docs/current/sql-notify.html))
  - 알림은 트랜잭션 사이에서만 전달된다. 같은 트랜잭션 안의 동일 channel+payload 는 하나로 합쳐진다
  - 알림 큐 (기본 8GB) 가 차면 NOTIFY 한 트랜잭션이 커밋에서 실패한다. LISTEN 세션이 긴 트랜잭션에 있으면 큐 정리가 막힌다 → `pg_notification_queue_usage()` 감시
  - NOTIFY 한 트랜잭션은 커밋 때 인스턴스 전역 락 (모든 DB 공통) 을 잡아, NOTIFY 하는 커밋끼리 직렬화된다 (NOTIFY 없는 커밋은 영향 없음) → 쓰기가 많은 경로에서는 NOTIFY 를 빼고 짧은 주기 폴링, 또는 묶어서 드물게 보낸다
- 라이브러리: River (Go), pg-boss (Node), pgmq (확장)

### 오토스케일

- KEDA: Kafka `lagThreshold`, SQS `queueLength`, RabbitMQ `QueueLength|MessageRate`, PostgreSQL `query` + `targetQueryValue` ([KEDA](https://keda.sh/docs/2.21/scalers/))
- Kafka 소비자 그룹은 소비자 수가 파티션 수를 넘어도 놀기만 한다 (share group 은 해당 없음)

### 적체 회복

적체가 한 번 쌓이면 새 메시지까지 늦어져 스스로 못 빠져나온다 ([Avoiding insurmountable queue backlogs](https://builder.aws.com/content/3EuRcgkTP1MI0c7zM8W6HL3WIqA/avoiding-insurmountable-queue-backlogs)).

- 쌓인 오래된 메시지는 별도 backlog 큐로 옮기고 신선한 메시지를 먼저 처리한다
- 주기적 전체 동기화가 있으면 오래된 delta 는 버린다
- 나이는 **첫 시도 시각** 기준으로 잰다 (재시도로 갱신된 시각 제외)
- 테넌트별 속도 제한 + 넘치는 분량은 spillover 큐로 → `chassis-overload.md` §4

## 2. 수집 에이전트 (파일 tailer)

| 항목 | 지금 기준 |
|---|---|
| 파일 식별 | **fingerprint (앞부분 N 바이트 해시)** 가 기본 추세. inode 는 재사용·device ID 변경으로 중복·누락 (Vector `checksum`, Filebeat 9.0+ `fingerprint`, OTel `fingerprint_size`). Vector `checksum` 은 `ignored_header_bytes` 다음 앞 `lines` 줄 (기본 1줄) 기준이라 첫 줄이 같은 파일끼리 충돌한다 → 고정 헤더가 있으면 `ignored_header_bytes`·`lines` 를 늘린다 ([file.rs](https://github.com/vectordotdev/vector/blob/master/src/sources/file.rs)) |
| 로테이트 | rename 방식이 안전. copytruncate 는 복사와 truncate 사이 유실 가능 → 쓰면 ① 파일 크기 < 저장 offset 이면 truncate 로 보고 offset 을 0 으로 되돌린다 (inode·경로 식별에서는 확인 주기 사이에 저장 offset 을 넘게 다시 쓰이면 truncate 를 감지하지 못해 앞부분을 잃는다 → copytruncate 면 fingerprint 식별을 쓴다. fingerprint 는 파일 내용을 따라가 copytruncate 로테이트를 스스로 감지한다) ② 첫 로테이트 파일을 읽기 대상에 넣는 것은 fingerprint 식별일 때만 한다 (inode·경로 식별이면 복사본을 새 파일로 보고 전부 다시 읽는다. Filebeat 는 inode 식별이면 `rotation.external.strategy.copytruncate` + `suffix_regex`) ③ `delaycompress` 를 켠다 ([filestream](https://www.elastic.co/docs/reference/beats/filebeat/filebeat-input-filestream)) |
| 회전된 파일 | 끝까지 읽은 뒤 넘어간다. Backpressure 로 멈춘 사이 회전 대기 시간 (Fluent Bit `Rotate_Wait` 기본 5s) 이 지나면 놓친다 |
| 체크포인트 | 읽기 성공마다 Position 기록. 파일이면 임시 파일 → `fsync` → `rename`. SQLite 면 WAL. 저장소를 안 정하면 메모리에만 있어 재시작 때 잃는다 (OTel `storage` 미지정) |
| 처음 보는 파일 | 시작 Position 기본값이 도구마다 다르다 (OTel `end`, Vector `beginning`) → 명시 |
| 오래된 상태 정리 | 정리 주기가 "무시 기준 + 확인 주기" 보다 길어야 한다 (Filebeat `clean_inactive` > `ignore_older` + `prospector.scanner.check_interval`). 9.2+ 는 어기면 **시작을 거부**한다 ([filestream](https://www.elastic.co/docs/reference/beats/filebeat/filebeat-input-filestream)) |
| 동시 열린 파일 | 상한 (OTel `max_concurrent_files` 1024) + fd 지표 |

체크포인트를 해도 **하류에서 버려지는 것은 막지 못한다** → 3절의 디스크 버퍼와 종단 간 확인 응답이 함께 필요하다.

## 3. store-and-forward (로컬 디스크 버퍼)

- 버퍼는 WAL 형태 + checksum 으로 손상 감지. **크기 상한 필수**
- 가득 찼을 때 정책을 명시
  - `block` (Vector 기본): 상류로 Backpressure 전파. Pull 형 Source 에는 안전, Accept 형 (push) Source 는 송신자 재시도에 기대야 함
  - `drop_newest` (Vector) / drop oldest (Fluent Bit `storage.total_limit_size`) / 거부 (OTel `block_on_overflow=false` 기본)
- fsync: 잃으면 안 되는 데이터는 매 쓰기 또는 group commit, 로그·지표는 간격 fsync 에 "최대 N ms 유실" 을 명시 (Vector 기본 500ms, OTel `file_storage` 는 기본 fsync 없음 → 잃으면 안 되면 `fsync: true`, [README](https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/extension/storage/filestorage/README.md))
- 종단 간 확인 응답: Source 에 대한 확인 응답은 Sink 전송 성공 **또는** 디스크 버퍼 기록 뒤에 ([Vector guarantees](https://vector.dev/docs/architecture/guarantees/))
- 디스크 쓰기 실패 시 스스로 멈추는 것이 조용히 버리는 것보다 낫다
- 손상된 버퍼를 자동으로 새로 만드는 옵션 (OTel `recreate`) 은 유실·중복을 낳는다 → 쓰면 경보

## 4. 폴러·스케줄러

- **k8s CronJob** ([문서](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/)): `concurrencyPolicy: Forbid` (겹침 방지), `startingDeadlineSeconds` (놓친 회차 중 최근 1회를 늦게라도 실행할 기한). Job 이 두 번 생기거나 안 생길 수 있으므로 작업은 멱등이어야 한다
  - `Forbid` 는 Job 단위로만 막는다. Job 기본 `podReplacementPolicy=TerminatingOrFailed` 라 같은 Job 의 Pod 둘이 겹칠 수 있다 → `podReplacementPolicy: Failed` (podFailurePolicy 가 있으면 기본). 그래도 멱등·Coordination 으로 막는다
  - 컨트롤러는 마지막 스케줄 이후 놓친 회차를 센다. 100 개를 넘으면 `TooManyMissedTimes` 경고 이벤트를 남긴다. 공식 문서는 Job 을 만들지 않는다고 적지만 현재 컨트롤러는 경고 후 최근 1회를 실행한다 → 긴 장애 뒤에도 실행될 수 있다고 가정한다
  - 놓친 회차는 몇 개든 가장 최근 1회만 실행되고 나머지는 건너뛴다 ([mostRecentScheduleTime](https://github.com/kubernetes/kubernetes/blob/master/pkg/controller/cronjob/utils.go)) → 처리 구간을 예정 시각이 아니라 '마지막 성공 Position ~ 지금' 으로 잡거나 놓친 구간을 따로 메운다
  - `startingDeadlineSeconds` 가 있으면 그 구간 안만 센다 (예: 200s 면 약 3 개만 세므로 실행됨). 10s 미만은 컨트롤러 확인 주기 (10s) 때문에 영영 안 돌 수 있다
  - `Forbid` 로 건너뛴 회차도 놓친 회차로 센다. 앞 Job 이 끝난 뒤 `startingDeadlineSeconds` 안이면 늦게 실행된다 → 늦은 실행이 해로우면 데드라인을 짧게 둔다
  - v1.32+ 의 Job 에는 어노테이션 `batch.kubernetes.io/cronjob-scheduled-timestamp` (예정 시각, RFC3339) 가 붙는다. 회차별 멱등 키로 쓴다 (Source 에서 결정되는 값이므로 SKILL 규칙에 맞는다). 값은 CronJob `timeZone` (없으면 controller-manager 로컬) 기준으로 표기되므로 UTC instant 로 정규화해 키로 쓰고, `.spec.timeZone` 을 명시한다
- **상주 폴러**: `주기 + 지터`. 지터는 순수 랜덤보다 호스트별 고정 오프셋 (결정적) 을 우선하거나 함께 써서 부하를 예측 가능하게 분산한다 ([지터 글](https://builder.aws.com/content/3EumjoZascWd1oZiEgL8ORlv3qE/timeouts-retries-and-backoff-with-jitter)). 처리가 늦으면 다음 tick 을 쌓지 말고 건너뛴다. 마지막 성공 시각을 지표로
- 하나만 돌아야 하면 Coordination (`chassis-coordination.md`)

## 5. 수집 서버·API 서버 (Accept: HTTP·gRPC·WebSocket·TCP)

- 종료: readiness false → (엔드포인트 제거 경쟁 대기) → listener 닫기 → 진행 중 요청 기한 내 완료 → 장기 연결은 종료 신호 (WebSocket close frame, gRPC GOAWAY) 후 기한 뒤 강제 종료
  - 종료 중인 EndpointSlice 엔드포인트는 `serving` 조건으로 구분된다 → `chassis-lifecycle.md` §1
  - gRPC graceful stop: 새 RPC 를 거부하고 진행 중 RPC 를 기다린다. 공식 가이드는 강제 종료 타이머를 병행하라고 권한다
- Go `http.Server.Shutdown` 은 hijacked 연결 (WebSocket) 을 기다리지 않는다 → 직접 추적해 닫는다
- 요청마다 타임아웃, 동시 연결 상한, 요청 크기 상한 (Resource Limits)
- 부하 차단·승인 제어·데드라인 전파: `chassis-overload.md` §1·§3
- 관리용 포트 (`/healthz`·`/readyz`·`/metrics`·pprof 분리) 는 `chassis-observability.md`

## 6. Concurrency·Throughput — 병렬 처리와 처리량 설계

범위는 병렬 모델과 처리량 설계까지다. 프로파일링·알고리즘·쿼리 튜닝 같은 일반 성능 최적화는 다루지 않는다.

### 병렬 단위

| 단위 | 순서 보장 | 병렬도 상한 | 커밋·Position | 예 |
|---|---|---|---|---|
| 파티션 | 파티션 안 전체 순서 | 파티션 수 | 단순 (파티션별 offset 하나) | Kafka consumer group 기본 |
| 키 | 같은 키 안에서만 | 동시에 활성인 키 수 (대략) | 파티션 안에서 병렬이라 빈틈 없이 끝난 지점까지만 추적해야 한다 (§1) | Confluent Parallel Consumer 의 KEY 순서 모드 (원 repo 는 유지보수 중단, 원작자 fork 가 활성) |
| 레코드 | 없음 | 소비자 수 × 소비자당 동시성 | 레코드별 확인 응답. Sink 는 멱등이어야 한다 | Kafka share group, SQS standard, RabbitMQ 경쟁 소비자 |

- 순서 요구가 정해지면 그 요구를 만족하는 **가장 큰 병렬 단위**를 고른다 (전체 순서 → 파티션, 키별 순서 → 키, 순서 불필요 → 레코드). share group 은 키 순서를 보장하지 않는다

### 동시성 산정

- Little's law: 동시 처리 수 = 목표 처리량 × 건당 처리 시간. 예: 2,000건/s × 50ms = 100 (평균값). 상한은 p99 처리 시간이나 여유율을 반영해 정한다
- 실제 상한은 하류가 정한다 (DB 연결 풀, 외부 API rate limit)
  - `최대 인스턴스 수 (HPA max + 롤링 배포 surge + 종료 유예 중인 파드) × 연결 풀 크기 ≤ DB 최대 연결 수에서 다른 클라이언트·예약 연결 (PG `superuser_reserved_connections` 등) 몫을 뺀 값`. 풀 크기는 인스턴스당 동시성 이상, 이 한도 이하. terminating 파드는 surge 계산에 들어가지 않으므로 여유분을 잡거나 drain 시작 때 풀을 줄인다 ([Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/))
  - 연결 풀 크기 ≥ 인스턴스당 동시성 (모자라면 풀 대기가 처리 시간을 늘려 산정이 틀어진다)
- 전체 동시성 상한 (`chassis-resources.md` §1) 이 하드 상한이다. Bulkhead 칸별 상한 (`chassis-overload.md` §4) 은 한 칸이 전체를 독점하지 못하게 하는 값이라 합이 전체를 넘어도 된다 (초과 예약). 칸 합이 전체보다 작으면 전체 상한은 쓰이지 않는다. 단 초과 예약이면 칸끼리 남는 용량을 다툰다. 반드시 보장해야 할 칸 (헬스체크·우선순위 작업) 은 전체 상한에서 예약분으로 따로 떼고, 나머지 칸만 초과 예약한다

### 배치 크기와 지연

- 큰 배치는 처리량이 오르고 지연과 실패 시 재처리 범위도 같이 커진다
- 배치 상한은 flush 조건 (건수·바이트·최대 대기 시간 중 먼저 닿는 것) 으로 정한다
- ClickHouse 처럼 작은 insert 가 많으면 part 가 폭증하는 Sink 는 배치를 키우거나 async insert 를 쓴다 (`contract.md` §1). 26.2 미만에서 async insert 를 쓰면 `async_insert_deduplicate=1` 을 켜야 dedup token 이 적용된다 (기본 0). 26.2+ 는 async insert 가 기본이다 ([dedup on retries](https://clickhouse.com/docs/guides/developer/deduplicating-inserts-on-retries)). async insert 는 `wait_for_async_insert=1` (기본) 을 유지한다. 0 이면 응답이 저장 확정이 아니다 (Contract 2 위반)

### CPU 작업과 I/O 작업

- I/O 위주면 비동기·동시성으로 늘린다
- CPU 위주면 동시성을 코어 수 근처로 제한하고 이벤트 루프·GIL 밖에서 돌린다 (Node `worker_threads`, Python 별도 프로세스 (3.14 의 free-threaded 빌드는 선택지지만 기본 빌드는 여전히 GIL), Go 는 `GOMAXPROCS`)
- 이벤트 루프를 막으면 heartbeat·liveness·poll 까지 멈춘다. 그래서 event loop lag 을 지표로 낸다

### 수평 확장

- consumer group 은 파티션 수가 상한이다 (파드가 파티션보다 많으면 놀기만 한다)
- 파티션 수를 늘리면 키 → 파티션 매핑이 바뀌어 전환 순간에 키 순서가 깨진다. 순서가 필요하면 처음부터 여유 있게 잡는다
- 지표 기반 자동 확장 (KEDA) 은 §1 오토스케일

### 병목 찾기

- 단계별 시간을 지표로 낸다: poll 대기, 처리, Sink 쓰기, 확인 응답
- lag 증가율 = 유입률 − 처리율. 양수면 지금 설정으로는 따라잡지 못한다
- 처리 시간이 Sink 쓰기에 몰려 있으면 동시성보다 배치를 키운다. poll 대기가 길면 Source 쪽이 병목이거나 인스턴스가 남는다

## 7. Server Execution Models — Accept 형 실행 모델

Accept 형 데몬이 연결·요청을 어떤 실행 단위 (프로세스·스레드·이벤트 루프·경량 스레드) 로 받는가. 대부분은 런타임을 고르면 모델이 따라오지만, 모델마다 종료 신호·상한·블로킹 함정이 다르다.

| 계열 | 모델 (대표 구현) |
|---|---|
| 프로세스·스레드 | Iterative (시험용), Process-per-connection (inetd, CGI), Pre-fork (Apache prefork, PHP-FPM, Gunicorn sync), Thread-per-connection (고전 서블릿), Thread pool (Tomcat, Apache worker) |
| 이벤트 기반 | Event loop + I/O multiplexing (epoll·kqueue·IOCP): Reactor (nginx, Node.js, Redis, Netty), Proactor (IOCP, Boost.Asio). Master-worker (nginx: master 가 worker 프로세스를 띄우고 각자 이벤트 루프), 단일 루프 + 스레드 풀 (Node.js libuv) |
| 하이브리드 | Multi-reactor (Netty boss/worker), Half-sync/half-async (이벤트 루프 + 업무 스레드 풀), Thread-per-core (Seastar), SO_REUSEPORT (listen 소켓을 여럿 열어 커널이 연결 분배, nginx `reuseport`) |
| 경량 동시성 | goroutine + netpoller (Go), Virtual thread (Java 21), Actor (Erlang/BEAM, Akka), async/await (tokio, asyncio) |

I/O 기법으로 io_uring 을 쓰려면: Docker·containerd 2.0+ 의 기본 seccomp (k8s `RuntimeDefault`) 에서 막혀 있다. k8s 파드는 seccompProfile 미지정·kubelet seccompDefault 꺼짐이면 Unconfined.

### 고르는 기준

대부분 런타임 선택이 곧 모델 선택이다: Go → goroutine, Node → event loop, Java → thread pool 또는 virtual thread.

| 요구 | 후보 |
|---|---|
| 장기 연결 대량 (WebSocket) | event loop, 경량 동시성 |
| 블로킹 라이브러리 의존 | thread pool, virtual thread |
| 짧은 CPU 위주 요청 | 코어 수 근처의 pool, pre-fork |
| 극저지연 | thread-per-core |

### 모델별 Chassis 함정

- **Event loop**: 블로킹 호출이나 CPU 작업 하나가 모든 연결과 heartbeat 를 멈춘다 (§6). 연결이 싸 보여도 동시 연결 수와 in-flight 상한을 명시한다
  - Node 는 fs·dns.lookup·crypto 일부가 기본 4개짜리 libuv 스레드 풀을 공유한다 (소켓 I/O 는 아님) → `UV_THREADPOOL_SIZE` (최대 1024) 를 조정하고 풀 대기를 숨은 큐로 본다 ([libuv threadpool](https://docs.libuv.org/en/v1.x/threadpool.html))
- **Thread-per-connection·thread pool**: 스레드마다 스택 메모리가 든다. 스레드 풀 크기는 동시 요청 처리 상한이다. 연결 수 상한 (Tomcat `maxConnections`)·OS backlog (`acceptCount`) 는 별개 값이고, 풀이 찬 동안 쌓이는 연결이 숨은 큐다 (`chassis-overload.md` §3). 세 값을 모두 명시한다 (thread-per-connection 이면 연결 상한 = 스레드 상한) ([Tomcat connector](https://tomcat.apache.org/tomcat-10.1-doc/config/http.html))
- **Pre-fork·master-worker**: 프로세스 안에 감독자 (master) 가 하나 더 있다. 신호는 master 가 받아 worker 에 전한다
  - nginx 는 SIGTERM 이 빠른 종료 (fast shutdown), graceful 은 SIGQUIT, 재적재는 SIGHUP (새 worker 를 띄우고 옛 worker 를 drain) 이다. k8s 에서는 preStop 으로 `nginx -s quit` 을 부르거나 `STOPSIGNAL` 을 SIGQUIT 으로 둔다. graceful 종료는 장기 연결을 무기한 기다리므로 `worker_shutdown_timeout` 을 유예 시간보다 짧게 둔다. 공식 nginx 이미지는 이미 `STOPSIGNAL SIGQUIT` 이다 ([control](https://nginx.org/en/docs/control.html), [worker_shutdown_timeout](https://nginx.org/en/docs/ngx_core_module.html#worker_shutdown_timeout))
  - Gunicorn 은 SIGTERM 이 graceful (`graceful_timeout` 기본 30s), SIGQUIT·SIGINT 는 즉시 종료다 (TERM·QUIT 의 의미가 nginx 와 반대. INT 는 둘 다 빠른 종료). `graceful_timeout` + preStop < `terminationGracePeriodSeconds` ([signals](https://gunicorn.org/signals/))
  - `worker 메모리 × worker 수 ≤ 컨테이너 메모리 limit`
  - 종료 순서와 런타임별 관용구: `chassis-lifecycle.md` §1·§4
- **Multi-reactor·thread-per-core**: 루프·스레드 수는 cgroup CPU limit 기준으로 정한다 (`chassis-lifecycle.md` §4). SO_REUSEPORT 는 Linux 기본값에서 닫힌 listener 의 accept 큐 연결이 버려진다. `net.ipv4.tcp_migrate_req=1` (5.14+) 이면 다른 listener 로 옮겨진다 ([ip-sysctl](https://docs.kernel.org/networking/ip-sysctl.html))
- **경량 동시성**: 연결당 비용이 싸서 상한을 잊기 쉽다 → semaphore 등으로 동시성 상한을 명시한다. Java virtual thread 는 `synchronized` 안에서 블로킹하면 carrier 스레드가 고정 (pinning) 된다 (JDK 24+ JEP 491 로 `synchronized` pinning 해소. 클래스 로딩·초기화 중 블로킹 (다른 스레드의 초기화 대기 포함), 네이티브 콜백 뒤 블로킹은 여전히 고정, [JEP 491](https://openjdk.org/jeps/491))
- **앞단 reverse proxy·LB**: 앱의 keep-alive idle timeout 을 프록시보다 길게 둔다. 반대면 프록시가 앱이 이미 닫은 연결을 재사용해 502 가 난다
