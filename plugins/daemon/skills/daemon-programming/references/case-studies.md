# 사례 — 실제 코드에서 본 기법과 함정

조사일 2026-10-10. 외부는 소스 코드를 직접 읽었다 (OpenMeter `e00163c`, Lago `0527391`). 사내 코드는 같은 날 읽었고 이름·경로를 지워 패턴만 남겼다.

## OpenMeter sink worker (Go, Kafka → ClickHouse)

| 무엇 | 어떻게 | 평가 |
|---|---|---|
| flush 조건 | 건수 500 또는 2s 중 먼저. 타이머는 채널로 신호만 보내 에러가 메인 루프로 모인다 (`openmeter/sink/sink.go`) | 따라 할 것. 단 바이트 기준·버퍼 상한이 없다 |
| flush 순서 | mutex → 전체 파티션 pause → 배치 내 중복 제거 + Redis 확인 → ClickHouse insert → offset store → Redis 기록 → resume | 순서 자체는 Contract 의 확인 응답 순서에 맞다 |
| 커밋 | `enable.auto.commit=true` + `enable.auto.offset.store=false` — 처리한 offset 만 store 하고 실제 커밋은 librdkafka 주기 커밋 | 쓸 만한 절충. 주기 (기본 5s) 만큼 재처리 구간이 넓어진다 |
| insert↔커밋 사이 crash | 재처리 시 Redis 가 처음 본 이벤트로 판정 → **두 번 insert.** 일반 `MergeTree`, `insert_deduplication_token` 미사용, 조회에 `FINAL` 없음. 주석은 "exactly once" | 피할 것. 외부 캐시 사후 기록은 crash 구간을 못 막는다 → Sink 멱등 (Contract 의 멱등 키) |
| 리밸런스 | cooperative-sticky. revoke 시 flush 하지 않고 그 파티션 버퍼를 버림 (새 소유자가 재처리). 구독이 바뀔 때만 재구독 | 정합성은 Recovery (crash-only) 로 지켜진다. 재처리 비용과 맞바꾼 선택 |
| SIGTERM | `oklog/run` 역순 종료. 진행 중 flush 만 mutex 로 기다리고 남은 버퍼는 flush 하지 않음 | crash-only 와 일치 (남은 건 재처리) |
| 의존 장애 | Redis·ClickHouse 실패 = `Run` 에러 = 프로세스 종료 | 피할 것. crash-loop 를 Backpressure 대신 쓰는 셈 → degraded 상태 + pause + 백오프 |
| 잘못된 이벤트 | sink 는 DLQ 없이 버리고 커밋. 버린 로그도 기본 꺼짐 | 피할 것 (Failure Handling) |
| 다른 워커 | watermill router: 10회 재시도 (10ms→1s, 총 1분) 후 DLQ 토픽. **종료 중이면 DLQ 로 보내지 않고 NACK** | 따라 할 것 |
| health | `/healthz/live` 항상 ok. 종료 시 ready 를 끊고 3s 전파를 기다리는 장치는 API 서버에만 있고 sink-worker 는 체크 없음 | 서버형은 따라 할 것. 워커에 의미 없는 readiness 는 두지 말거나 상태를 반영 |

## Lago events-processor (Go, franz-go)

| 무엇 | 어떻게 | 평가 |
|---|---|---|
| 동시성 | 파티션마다 goroutine. `BlockRebalanceOnPoll` + 레코드를 넘긴 뒤 `AllowRebalance` | 따라 할 것. 리밸런스가 처리 도중에 끼어들지 않는다 |
| revoke | quit 신호 → 진행 중 배치가 끝날 때까지 `done` 대기 | 따라 할 것 |
| 커밋 | `DisableAutoCommit`. 배치 병렬 처리 후 **처음 실패한 offset 앞까지만** `CommitRecords` | 방향은 맞다. 그러나 건너뛴 레코드를 seek back 하지 않아 다음 배치 커밋이 넘어가면 사실상 유실 (franz-go 동작 기준 추정) |
| 재시도 | 재시도 가능한 실패는 수집 (`IngestedAt`) 후 12시간 이내면 커밋하지 않고 건너뜀 — seek back 이 없어 재시작·리밸런스 때만 다시 받는다 (코드 주석 "It will be consumed again" 과 실제 동작이 다르다). 12시간이 넘으면 DLQ. 파싱 불가는 즉시 커밋 | 분류 자체는 Failure Handling 에 맞다. 그러나 커밋 보류만으로는 Kafka 재시도가 되지 않는다 |
| 멱등 | Kafka key = 조직+거래 ID, ClickHouse `ReplacingMergeTree`, 조회 `FINAL` | Sink 쪽 멱등 (eventual + 조회 보정) |
| 종료 | ctx cancel → 파티션 goroutine 대기 → close. **종료 타임아웃 없음**, health 엔드포인트 없음, fetch 에러에 `panic` | 피할 것 (Lifecycle · Observability) |

## 사내 코드 (익명)

### 공용 NestJS Kafka 래퍼 패키지의 소비자 (kafkajs 기반)

- `eachMessage` 전체를 `try/catch` 로 감싸고 `console.log` 만 남긴다 → kafkajs 는 정상 처리로 보고 offset 을 커밋 → **처리 실패 메시지가 유실된다 (사실상 at-most-once)**
- autoCommit 설정을 열어 두지 않았고 DLQ·재시도 정책이 없다
- Avro 디코드 실패도 `onDecodeError` 를 넘기지 않으면 `console.error` 후 skip
- 교훈: Failure Handling 위반의 전형. 공용 소비자 라이브러리는 "실패 = 재시도 → DLQ" 를 기본값으로 가져야 한다

### 한 서비스의 자체 소비자 베이스 클래스 (NestJS)

- 위 문제를 주석으로 명시하고 `@confluentinc/kafka-javascript` 를 직접 써서 **처리 성공 뒤에만 커밋** (at-least-once)
- 3회 재시도 (0.5s → 1s → 2s) 후 알림을 올리고 커밋 (포기). 디코드 불가도 커밋. 무한 재시도가 파티션을 막는 것을 피한 선택
- 교훈: 따라 할 것. 다만 "알림 후 포기" 는 그 메시지를 되살릴 길이 없다 → 잃으면 안 되는 데이터면 DLQ + 재투입 명령까지

### 다른 서비스의 소비자 기동 처리 (NestJS)

- Kafka 연결·구독 실패를 잡아 로그만 남기고 앱은 계속 기동 (API 부팅을 깨지 않으려는) — 의도된 절충
- 교훈: 이런 부분 기동은 허용하되, "소비자 비활성" 을 지표·경보로 드러내야 한다 (SKILL 의 Observability). 지금은 로그 한 줄뿐이라 파드는 건강해 보인다

### NestJS 종료 훅

- 한 모노레포의 NestJS 앱 진입점 (`main.ts`) 중 `enableShutdownHooks()` 를 부르는 곳은 절반에 못 미쳤다 (2026-10-10 집계). 나머지는 SIGTERM 에 `onApplicationShutdown` (Kafka disconnect 등) 이 돌지 않을 수 있다 (다른 경로로 종료를 처리하는지는 앱별 확인 필요)

### 스케줄러 배치용 Redis 락 (Kotlin/Spring)

- `setIfAbsent(key, token, ttl)` 로 획득 — 올바름
- 해제가 `get` → 비교 → `delete` 로 **원자적이지 않다**: 그 사이 TTL 이 만료되고 다른 파드가 잡으면 남의 락을 지운다 → Lua compare-and-delete
- 작업 시간이 TTL 을 넘으면 두 파드가 겹쳐 돈다 (연장·펜싱 없음) → 작업 멱등 또는 TTL 연장
- Redis 장애 시 이번 회차를 건너뜀 — 효율 목적 락으로는 합리적
