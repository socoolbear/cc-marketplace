# Contract (구간 계약, hop contract) — 전달 보장 · 확인 응답 순서 · 멱등 키 · 재전송 · 스키마 진화

at-least-once 데몬은 "Sink 쓰기 성공 → 확인 응답 전 crash" 구간에서 반드시 같은 입력을 다시 처리한다. 막는 방법은 둘뿐이다.

1. **데이터와 Position 을 같은 트랜잭션에 쓴다** (트랜잭션 체크포인트)
2. **결정적 키로 Sink 가 중복을 거부하게 한다** — 단, Sink 의 Dedup Window 안에서만

어느 쪽이든 **Dedup Window > 최대 재처리 지연** (DLQ 재투입·수동 replay 까지 포함) 이어야 한다.

## 1. Sink 별 기법

| Sink | 기법 | Dedup Window | 함정 |
|---|---|---|---|
| PostgreSQL | `UNIQUE(source, event_id)` + `ON CONFLICT DO NOTHING`. 또는 데이터와 `consumer_offsets(partition, offset)` 를 같은 트랜잭션에 쓰고 시작 시 그 offset 부터 읽기. 메시지 ID 로 거르면 inbox 패턴 (§4) | 키가 남아 있는 동안 | 파티션 테이블의 UNIQUE 는 파티션 키를 포함해야 한다 → 시간 파티션이면 이벤트 시각이 결정적이어야 한다. `DO UPDATE` 는 한 문장에서 같은 행을 두 번 건드리면 오류 → 배치 안 중복을 먼저 제거 ([INSERT](https://www.postgresql.org/docs/current/sql-insert.html), [partitioning](https://www.postgresql.org/docs/current/ddl-partitioning.html)) |
| MySQL | `INSERT … ON DUPLICATE KEY UPDATE` 또는 트랜잭션 체크포인트 | 키가 남아 있는 동안 | `INSERT IGNORE` 는 중복뿐 아니라 값 잘림·범위 초과·NULL 오류까지 경고로 바꿔 삼킨다 ([INSERT](https://dev.mysql.com/doc/refman/8.4/en/insert.html)) |
| ClickHouse | 배치마다 결정적 `insert_deduplication_token` | Replicated: 기본 1만 블록 / 3600초. **일반 MergeTree 는 기본 0 = 거르지 않음** (`non_replicated_deduplication_window`) | 재시도 사이에 다른 insert 가 Dedup Window 를 넘게 들어오면 실패. `insert_deduplication_token` 은 데이터 hash 보다 우선한다 → 토큰을 Source Position 만으로 만들면 **내용을 고쳐 다시 넣은 배치가 조용히 버려진다** (내용이 바뀔 수 있으면 토큰에 내용 버전을 넣는다). 문서에 명시는 없으나 `now()` 기본값 컬럼이 있으면 같은 배치도 hash 가 달라질 수 있다. 26.2 변경은 표 아래. `ReplacingMergeTree` 는 **eventual** (merge 때만) → 정확한 값은 `FINAL`·`argMax` 조회가 필요하고 큰 테이블에서 `FINAL` 은 비싸다 ([dedup on retries](https://clickhouse.com/docs/guides/developer/deduplicating-inserts-on-retries), [ReplacingMergeTree](https://clickhouse.com/docs/engines/table-engines/mergetree-family/replacingmergetree), [settings](https://clickhouse.com/docs/operations/settings/settings), [merge-tree settings](https://clickhouse.com/docs/operations/settings/merge-tree-settings)) |
| ClickHouse + MV 롤업 | 원본의 block_id 로 하위 MV 블록도 거른다 (`deduplicate_blocks_in_dependent_materialized_views`) | 원본과 같음 | 원본에서 중복이 새면 Summing·AggregatingMergeTree 롤업에 그대로 두 번 더해진다 |
| S3 등 객체 저장소 | 결정적 키 (`topic/partition/start-end`) + `PutObject If-None-Match: *` | 객체가 있는 동안 | 이미 있으면 412 → 성공으로 다룬다. 동시 삭제와 겹치면 409. versioning bucket 은 delete marker 뒤 재쓰기 허용. `If-Match` (ETag 비교) 도 PutObject·CompleteMultipartUpload·CopyObject 에서 지원. multipart upload 에서 409 를 받으면 CreateMultipartUpload 부터 다시 시작해야 한다 ([conditional writes](https://docs.aws.amazon.com/AmazonS3/latest/userguide/conditional-writes.html)) |
| 외부 HTTP API | `Idempotency-Key` 헤더 (Source 에서 결정적으로) | 제공자마다 다름. Stripe 는 24h 뒤 정리될 수 있음 ([Stripe](https://docs.stripe.com/api/idempotent_requests)) | 파라미터가 바뀌면 오류. 검증 실패·동시 충돌은 저장되지 않음. Stripe API v1 은 **500 응답도 저장**한다 → 같은 키로 재시도하면 작업을 다시 실행하지 않고 저장된 500 을 돌려준다 (API v2 는 실패한 작업을 다시 시도). 키는 최대 255자. Dedup Window 뒤 재처리는 못 막는다 |
| Redis | `SET key v NX PX ttl` | TTL | **표시를 먼저 하고 쓰기 전에 죽으면 유실.** TTL 이 지나면 중복 통과. 근거가 아니라 앞단 필터로만 ([SET](https://redis.io/docs/latest/commands/set/)) |
| Kafka 재발행 | 멱등 producer + 트랜잭션 (`sendOffsetsToTransaction`), 소비 쪽 `read_committed` | producer ID·sequence | 보장이 **Kafka 안에서만** 성립. 외부 Sink 는 "출력과 같은 곳에 offset 을 저장하라" 가 공식 권고 ([design](https://kafka.apache.org/43/design/design/#message-delivery-semantics)) |

**ClickHouse 26.2 이후 변경** ([dedup on retries](https://clickhouse.com/docs/guides/developer/deduplicating-inserts-on-retries), [settings](https://clickhouse.com/docs/operations/settings/settings))

- 새 설정 `deduplicate_insert` 기본값 `enable`. `async_insert` 기본값 1
- `insert_deduplicate = 0` 만으로는 더 이상 dedup 이 꺼지지 않는다 → `deduplicate_insert = disable`
- `async_insert_deduplicate` 는 legacy. 동기·비동기 insert 가 dedup 로그 하나를 공유하고 `replicated_deduplication_window` 가 둘 다 덮는다
- 비동기 insert 의 dedup 은 배치가 아니라 사용자 쿼리 단위다
- 비동기 insert 에서 MV 가 블록을 2개 이상 내보내면 NOT_IMPLEMENTED 오류
- `insert_select_deduplicate` 는 `deduplicate_insert_select` 로 대체

## 2. 범용 레시피

1. Source Position 으로 **결정적 배치 경계**를 만든다 (`partition + startOffset..endOffset`). 시간 기준으로 자르는 버퍼링은 재처리 때 경계가 달라져 배치 키가 깨진다
2. 항목마다 **결정적 ID** (`source + event_id`, 없으면 Source Position). 쓰기 시점에 `now()`·UUID 를 만들지 않는다
3. Sink 가 트랜잭션 DB 면 **트랜잭션 체크포인트**를 우선한다. 시작할 때 Sink 에 저장된 Position 부터 읽는다 (Source 쪽 커밋은 보조)
4. 아니면 배치 키·항목 키를 Sink 의 멱등 수단 (UNIQUE, dedup token, If-None-Match, Idempotency-Key) 에 넘긴다
5. Sink 쓰기가 성공하면 확인 응답. "이미 있음" 도 성공
6. Dedup Window 와 최대 재처리 지연을 비교해 설계 메모에 적는다
7. Position 을 수동으로 되감는 절차 (replay·reset) 에는 dedup 상태 초기화 여부를 같이 적는다
8. 최종 방어선으로 **대사 작업**: Source 건수·합계 vs Sink 건수·합계를 주기적으로 비교해 차이를 경보
9. dedup·inbox·outbox 테이블은 정리해야 한다 (Steady State, `chassis-resources.md` §2). 정리 TTL 은 Dedup Window 요구 (최대 재처리 지연, DLQ 재투입·replay 포함) 보다 길어야 한다

## 3. 재전송과 종단 간 확인 응답

데몬이 이어지면 (에이전트 → 수집 서버 → DB) 앞 데몬의 Sink 가 다음 데몬의 Source 다. 각 구간에 같은 계약을 건다.

- 보내는 쪽 (Send): 받는 쪽의 "저장 확정" 응답을 받은 뒤에만 Position 을 넘긴다. 그 전까지는 상한 있는 버퍼 (메모리 또는 디스크, `io.md` §3) 에 들고 백오프로 재전송한다
- 받는 쪽 (Accept): 자기 Sink 쓰기가 확정된 뒤에 "저장 확정" 을 응답한다. 같은 멱등 키가 다시 오면 "이미 있음" 을 성공으로 응답한다
- Source 에 대한 확인 응답은 Sink 전송 성공 **또는** 디스크 버퍼 기록 뒤에 ([Vector guarantees](https://vector.dev/docs/architecture/guarantees/))
- 재전송이 있는 한 중복은 반드시 생긴다 → 받는 쪽 멱등이 계약의 나머지 절반이다

## 4. 생산자 쪽: transactional outbox

데몬이 DB 변경과 메시지 발행을 함께 해야 하면 "DB 커밋 후 발행" 사이의 crash 로 유실·불일치가 생긴다.

- 같은 DB 트랜잭션에 업무 데이터와 `outbox` 행을 쓴다
- 별도 릴레이가 outbox 를 읽어 발행: polling publisher (`SELECT … FOR UPDATE SKIP LOCKED`) 또는 CDC ([Debezium outbox router](https://debezium.io/documentation/reference/stable/transformations/outbox-event-router.html))
- CDC 는 커밋 순서를 보존한다. 병렬 polling 은 순서를 깨므로 순서가 필요하면 집계 키 단위로 직렬화
- 릴레이도 at-least-once → 소비자 쪽은 위 레시피로 멱등
- Debezium outbox 는 이벤트 `id` 를 헤더에 실어 보낸다 ("to remove duplicate messages"). 소비자는 이 ID 로 거른다

**inbox 패턴 (outbox 의 짝)**: 소비자가 업무 데이터와 같은 트랜잭션에 `processed_messages(message_id)` 를 쓴다. 이미 있으면 건너뛴다. §1 의 PG UNIQUE 행과 같은 원리다.

## 5. 스키마 진화와 버전 공존

- 메시지마다 스키마 버전을 싣는다. 하위 호환·상위 호환 규칙을 정해 둔다
- 모르는 필드는 버리지 말고 그대로 통과시킨다. 호환 불가 버전은 Poison 으로 분류한다 (`chassis-failure.md`)
- 롤링 배포 중에는 옛 인스턴스와 새 인스턴스가 같은 Source 를 동시에 소비한다 → 출력 형식과 멱등 키 계산식이 두 버전에서 모두 유효해야 한다. 키 계산식을 중간에 바꾸면 dedup 이 깨진다
- 파이프라인 변경: 실데이터로 카나리를 dry run (쓰기 없음) 으로 돌린 뒤 1 → 10 → 50 → 100% 로 올린다
- 종단 간 대사: golden data, 발행 건수 vs 전달 건수 (`verification.md`)
- 사례: 새 필드를 옛 하류가 조용히 버린 사고 ([SRE workbook](https://sre.google/workbook/data-processing/))

## 6. 대안: durable execution

Temporal (그 밖에 Restate, DBOS) 같은 엔진은 이벤트 이력을 유지해 Recovery·Position·재처리를 대신 맡는다 ([Temporal](https://docs.temporal.io/workflows)).

- 비용: workflow 코드에 결정성 제약이 걸린다 (activity 밖에서 시계·난수·네트워크를 직접 쓰지 못한다)
- 외부 호출 (activity) 은 여전히 멱등이어야 한다 (일반적 이해, 문서 인용 아님)
- 판단 규칙: 부수 효과가 있는 다단계 작업에 긴 대기가 끼면 at-least-once + 체크포인트를 직접 짜기 전에 엔진을 먼저 검토한다
