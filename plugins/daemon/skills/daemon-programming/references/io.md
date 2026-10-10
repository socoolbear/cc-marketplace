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
| Kafka share group (4.2+) | 레코드별 (accept·release·reject, `RENEW` 로 락 연장) | 락 만료·release | 없음 | poll 중단, 배치 크기 | `share.delivery.count.limit` (4.3) 로 독성 차단 |
| RabbitMQ quorum | 메시지별 ack (`multiple` 가능) | nack·reject·채널 끊김 | 없음 | prefetch (`basic.qos`) | `delivery-limit` (기본 20) + DLX |
| PostgreSQL 큐 | 행 상태 갱신·삭제 (트랜잭션) | lease 만료, 롤백 | UNIQUE 로 직접 | `LIMIT n`, 워커 수 | `attempts` 컬럼 → failed 상태 |

### Kafka

- `enable.auto.commit=false` (또는 librdkafka 계열은 `enable.auto.offset.store=false` 로 처리한 offset 만 store) — 처리를 마친 offset **+1** 을 커밋
- `max.poll.interval.ms` (기본 5분) 안에 다음 poll 이 없으면 그룹에서 쫓겨나 리밸런스 → 그 뒤 커밋은 실패하고 같은 배치를 다시 처리. 긴 처리는 `pause()` 상태로 poll 을 계속 부르거나 `max.poll.records` 를 줄인다
- 리밸런스: classic 프로토콜이면 `cooperative-sticky` (바뀌는 파티션만 넘김). **Kafka 4.0+ 의 새 프로토콜 (KIP-848) 은 클라이언트가 `group.protocol=consumer` 로 opt-in** 한다 (문서상 classic 이 아직 기본)
  - `session.timeout.ms` 와 `heartbeat.interval.ms` 둘 다 서버 설정 (`group.consumer.session.timeout.ms`·`group.consumer.heartbeat.interval.ms`) 으로 옮겨 간다
  - assignor 는 클라이언트가 `group.remote.assignor` 로 고르되 서버 목록 `group.consumer.assignors` (기본 uniform, range) 안에서만. `partition.assignment.strategy` 는 쓸 수 없다
  - 4.3 에서 `group.consumer.assignment.interval.ms` (기본 1s) 추가, `group.coordinator.rebalance.protocols` 는 deprecated (5.0 에서 제거)
  - 근거: [rebalance protocol](https://kafka.apache.org/43/operations/consumer-rebalance-protocol/), [librdkafka 설정](https://raw.githubusercontent.com/confluentinc/librdkafka/master/CONFIGURATION.md), [릴리스](https://kafka.apache.org/community/downloads/)·[업그레이드](https://kafka.apache.org/43/getting-started/upgrade/) (최신 4.3.1, 2026-06-25)
- revoke 콜백: 그 파티션의 진행 중 작업을 끝내고 (또는 버리고) **동기 커밋** 후 넘긴다. lost 콜백: 이미 소유권을 잃었으므로 커밋하지 말고 버린다
- 바뀌지 않은 구독을 매번 다시 걸면 리밸런스가 끝없이 돈다 (OpenMeter 주석). 한 그룹 안에서 인스턴스마다 구독 토픽이 다르면 리밸런스가 계속 돈다 (사내 소비자 코드 주석)
- static membership (`group.instance.id` = 파드 이름) 은 롤링 재시작 때 세션 타임아웃 안에 돌아오면 리밸런스를 생략한다
- 파티션 키 = 순서·중복 판정이 필요한 단위 (같은 키는 같은 파티션)
- 병렬 처리: 파티션당 하나의 실행 흐름이 단순하다. 파티션 안 병렬이면 "빈틈 없이 끝난 offset" 추적이 필요하다. **처음 실패한 offset 앞까지만 커밋하되, 건너뛴 항목은 seek back 하거나 재시도 큐로 보내야** 한다 (안 그러면 다음 커밋이 넘어가며 유실 — Lago 사례)

### Kafka share group (KIP-932, "Queues for Kafka")

- 4.2 에서 production-ready. 파티션 소유 대신 레코드 단위로 락을 걸어 가져가므로 **소비자 수가 파티션 수를 넘어도 된다**. 순서 보장은 포기한다
- 레코드별 확인 응답 (accept·release·reject). 처리가 길면 `RENEW` 로 락을 연장한다
- 독성 처리: `share.delivery.count.limit` (4.3) 로 전달 횟수를 제한
- **4.2.1 이상을 쓴다** (share group 데드락 수정 KAFKA-20505)
- 근거: [4.2.0 릴리스 공지](https://kafka.apache.org/blog/2026/02/17/apache-kafka-4.2.0-release-announcement/)

### SQS

- visibility timeout 기본 30s. 처리 중에는 heartbeat 로 `ChangeMessageVisibility` 를 반복 연장 (최초 수신부터 12h 상한). 포기할 때는 0 으로 바꿔 즉시 반환 ([visibility timeout](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-visibility-timeout.html))
- long polling `WaitTimeSeconds=20`
- `DeleteMessageBatch` 는 일부 실패해도 HTTP 200 → `Failed[]` 를 반드시 확인
- in-flight 상한 (standard 약 12만) 에 닿으면 long polling 은 에러 없이 빈 응답, short polling 은 `OverLimit` 에러. FIFO 상한은 활성 메시지 그룹 수에 따라 달라진다
- fair queues (2025-07): standard 큐 메시지에 `MessageGroupId` 를 붙이면 시끄러운 테넌트의 우선순위가 내려간다. 소비자 코드 변경 없음. 멀티 테넌트 워커면 쓴다 ([fair queues](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-fair-queues.html)). 테넌트 격리 일반론은 `chassis-overload.md` §4

### RabbitMQ

- 수동 ack + `basic.qos(prefetch)` 가 Backpressure. prefetch 무제한은 메모리 폭주
- 4.3 부터 카운터가 둘로 갈렸다. `acquired-count` 는 재큐잉마다, `delivery-count` 는 실패일 때만 올라가며 delivery-limit 은 `delivery-count` 를 본다
  - 올림: `basic.reject`, 클라이언트 crash, unacked 상태의 연결·채널 종료
  - 안 올림: `basic.nack`, consumer timeout (AMQP 1.0 의 released·`modified(delivery-failed=false)` 도)
  - 결과: `basic.nack(requeue=true)` 만 쓰는 소비자는 독성 메시지를 무한 반복하고 DLQ 에 닿지 않는다 → `basic.reject` 를 쓰거나 `requeue=false` 로 DLX 에 보낸다
- 4.3 Delayed Retries: 큐 안에서 브로커가 지연시키므로 재발행이 없어 중복이 생기지 않는다. `x-delayed-retry-type` = `all`|`returned`|`failed`, `x-delayed-retry-min`/`max`, 지연 = min(min × delivery-count, max) (선형)
- 근거: [quorum queues](https://www.rabbitmq.com/docs/quorum-queues), [4.3 릴리스](https://www.rabbitmq.com/blog/2026/04/23/rabbitmq-4.3-release)

### PostgreSQL 을 큐로

```sql
-- 가져가기 (lease)
UPDATE jobs SET locked_by = $worker, locked_until = now() + interval '60 seconds', attempts = attempts + 1
WHERE idx IN (
  SELECT idx FROM jobs
  WHERE status = 'pending' AND (locked_until IS NULL OR locked_until < now())
  ORDER BY idx LIMIT $n
  FOR UPDATE SKIP LOCKED)
RETURNING *;
```

- 긴 작업은 트랜잭션을 잡고 있지 말고 lease 컬럼으로. 처리 중 `locked_until` 연장 (heartbeat), 만료된 lease 는 다른 워커가 가져간다
- `LISTEN/NOTIFY` 는 깨우는 신호로만. 연결이 끊기면 알림이 사라지므로 주기 폴링을 같이 둔다 ([NOTIFY](https://www.postgresql.org/docs/current/sql-notify.html))
  - 알림은 트랜잭션 사이에서만 전달된다. 같은 트랜잭션 안의 동일 channel+payload 는 하나로 합쳐진다
  - 알림 큐 (기본 8GB) 가 차면 NOTIFY 한 트랜잭션이 커밋에서 실패한다. LISTEN 세션이 긴 트랜잭션에 있으면 큐 정리가 막힌다 → `pg_notification_queue_usage()` 감시
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
| 파일 식별 | **fingerprint (앞부분 N 바이트 해시)** 가 기본 추세. inode 는 재사용·device ID 변경으로 중복·누락 (Vector `checksum`, Filebeat 9.0+ `fingerprint`, OTel `fingerprint_size`) |
| 로테이트 | rename 방식이 안전. copytruncate 는 복사와 truncate 사이 유실 가능 → 쓰면 `delaycompress` + 첫 로테이트 파일을 읽기 대상에 포함 |
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
- fsync: 잃으면 안 되는 데이터는 매 쓰기 또는 group commit, 로그·지표는 간격 fsync 에 "최대 N ms 유실" 을 명시 (Vector 기본 500ms)
- 종단 간 확인 응답: Source 에 대한 확인 응답은 Sink 전송 성공 **또는** 디스크 버퍼 기록 뒤에 ([Vector guarantees](https://vector.dev/docs/architecture/guarantees/))
- 디스크 쓰기 실패 시 스스로 멈추는 것이 조용히 버리는 것보다 낫다
- 손상된 버퍼를 자동으로 새로 만드는 옵션 (OTel `recreate`) 은 유실·중복을 낳는다 → 쓰면 경보

## 4. 폴러·스케줄러

- **k8s CronJob** ([문서](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/)): `concurrencyPolicy: Forbid` (겹침 방지), `startingDeadlineSeconds` (놓친 회차 따라잡기 상한). Job 이 두 번 생기거나 안 생길 수 있으므로 작업은 멱등이어야 한다
  - 컨트롤러는 마지막 스케줄 이후 놓친 회차를 센다. 100 개를 넘으면 Job 을 만들지 않고 "too many missed start times" 를 남긴다 (따라잡기만 멈추고 CronJob 은 계속 동작)
  - `startingDeadlineSeconds` 가 있으면 그 구간 안만 센다 (예: 200s 면 약 3 개만 세므로 실행됨). 10s 미만은 컨트롤러 확인 주기 (10s) 때문에 영영 안 돌 수 있다
  - `Forbid` 로 건너뛴 회차도 놓친 회차로 센다
  - v1.32+ 의 Job 에는 어노테이션 `batch.kubernetes.io/cronjob-scheduled-timestamp` (예정 시각, RFC3339) 가 붙는다. 회차별 멱등 키로 쓴다 (Source 에서 결정되는 값이므로 SKILL 규칙에 맞는다)
- **상주 폴러**: `주기 + 지터`. 지터는 순수 랜덤보다 호스트별 고정 오프셋 (결정적) 을 우선하거나 함께 써서 부하를 예측 가능하게 분산한다 ([지터 글](https://builder.aws.com/content/3EumjoZascWd1oZiEgL8ORlv3qE/timeouts-retries-and-backoff-with-jitter)). 처리가 늦으면 다음 tick 을 쌓지 말고 건너뛴다. 마지막 성공 시각을 지표로
- 하나만 돌아야 하면 Coordination (`chassis-coordination.md`)

## 5. 수집 서버·API 서버 (Accept: HTTP·gRPC·WebSocket·TCP)

- 종료: readiness false → (엔드포인트 제거 경쟁 대기) → listener 닫기 → 진행 중 요청 기한 내 완료 → 장기 연결은 종료 신호 (WebSocket close frame, gRPC GOAWAY) 후 기한 뒤 강제 종료
  - 종료 중인 EndpointSlice 엔드포인트는 `serving` 조건으로 구분된다 → `chassis-lifecycle.md` §1
  - gRPC graceful stop: 새 RPC 를 거부하고 진행 중 RPC 를 기다린다. 공식 가이드는 강제 종료 타이머를 병행하라고 권한다
- Go `http.Server.Shutdown` 은 hijacked 연결 (WebSocket) 을 기다리지 않는다 → 직접 추적해 닫는다
- 요청마다 타임아웃, 동시 연결 상한, 요청 크기 상한 (Resource Limits)
- 부하 차단·승인 제어 (상세 `chassis-overload.md` §1·§3, [load shedding](https://builder.aws.com/content/3Eun1EEyX6p2e3VYNyRLSJzLuMV/using-load-shedding-to-avoid-overload))
  - 데드라인을 전파하고, 클라이언트가 이미 포기한 요청은 버린다
  - 포화되기 전에 싼 비용으로 거절한다. 헬스체크와 진행 중 요청의 완료를 우선한다
  - 큐 대기 시간에 상한을 둔다 (LIFO·CoDel). 숨은 큐 (스레드 풀, 소켓 backlog) 를 잊지 않는다
- 관리용 포트 (`/healthz`·`/readyz`·`/metrics`·pprof 분리) 는 `chassis-observability.md`
