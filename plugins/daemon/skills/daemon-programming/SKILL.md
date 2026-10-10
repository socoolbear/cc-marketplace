---
name: daemon-programming
description: 데몬 (오래 떠서 입력을 받아 처리하는 프로세스 — 수집 에이전트, 큐·스트림 소비자, 백그라운드 워커, 폴러·스케줄러, 수집 서버, API 서버의 실행 측면) 을 설계·구현·리뷰하는 데몬 프로그래밍 기법. 데몬을 Chassis (Lifecycle·Recovery·Resource Limits·Overload Protection·Failure Handling·Observability·Configuration·Admin Processes·Coordination) + I/O (Source·Sink, Pull/Accept 입력, Send/Store 출력) + Contract (전달 보장·확인 응답 순서·멱등 키·재전송·스키마 진화) 로 나눠 다룬다. "데몬 만들어줘", "워커 구현", "컨슈머 구현", "에이전트 구현", "상주 프로세스", "graceful shutdown", "SIGTERM 처리", "오프셋 커밋", "at-least-once", "중복 처리 방지", "재시작하면 데이터가 빠져", "헬스체크 설계", "크론 중복 실행 방지", "tail 구현", "역압", "DLQ", "재시도 폭주", "타임아웃 설계", "부하 차단", "큐 적체" 같은 요청이면 반드시 이 스킬을 사용할 것. 일회성 배치·CLI, API 의 업무 로직·설계, 이미 만든 프로세스를 launchd·systemd 에 등록하거나 백그라운드로 띄우는 운영 요청은 대상이 아니다.
---

# daemon-programming — 데몬 프로그래밍

**데몬**은 오래 떠서 바깥 입력을 받아 처리하고 바깥 상태를 바꾸는 프로세스다. 로그 수집 에이전트 (client), 수집 서버 (server), 큐 소비자, 폴러가 모두 데몬이다. **데몬 프로그래밍**은 데몬이 다음 셋을 갖추게 만드는 일이다.

| 목표 | 뜻 |
|---|---|
| 정합성 | 언제 죽어도 데이터가 빠지거나 틀어지지 않는다 |
| 가시성 | 죽거나 멈추면 바깥이 알아챈다 |
| 자기 회복 | 다시 켜면 알아서 이어 간다 |

> **데몬화 (daemonize)** 는 데몬의 전부가 아니라 Lifecycle 의 한 부품이다. 옛 방식의 데몬화 (double fork·setsid·PID 파일) 는 이제 프로세스가 하지 않고 감독자가 대신한다. 각 단계가 무엇을 하고 지금 누가 대신하는지는 `references/chassis-lifecycle.md` §6.

> 여러 단계에 걸쳐 부수효과를 내고 오래 기다리는 작업이면, 손으로 at-least-once + 체크포인트를 짜기 전에 **durable execution 엔진** (Temporal 등) 으로 충분한지 먼저 본다. 판단 기준은 `references/contract.md` §6.

## 모델: 데몬 = Chassis + I/O + Contract

```
┌───────────────────────── Chassis (모든 데몬 공통) ─────────────────────────┐
│ Lifecycle · Recovery · Resource Limits · Overload Protection               │
│ Failure Handling · Observability · Configuration · Admin Processes         │
│ (Coordination)                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
          ┌────────────────────── I/O (역할별) ──────────────────────┐
 Source ──▶│ Input (Pull / Accept) → Processing → Output (Send / Store) │──▶ Sink
          └──────────────────────────────────────────────────────────┘
   ▲ Contract                                                  Contract ▲
   └─ 전달 보장 · 확인 응답 순서 · 멱등 키 · 재전송 · 스키마 진화 (구간마다) ─┘
```

- **Chassis**: 역할과 무관하게 모든 데몬에 공통인 골격
- **I/O**: 역할별 부분. client 와 server 를 가르는 축은 **입력 방향 하나** (Pull / Accept)
- **Contract** (구간 계약, hop contract): 구간과 구간 사이의 전달 약속. 데몬이 이어지면 앞 데몬의 Sink 가 곧 다음 데몬의 Source 다

## 용어 (이 스킬 안에서 고정)

| 용어 | 뜻 |
|---|---|
| 감독자 (supervisor) | 프로세스를 띄우고 죽으면 다시 띄우는 바깥 주체 (kubelet, systemd) |
| Source / Sink | 데몬이 읽는 곳 (Kafka 토픽, SQS 큐, PG 작업 테이블, 파일, 타이머, 들어오는 연결) / 쓰는 곳 (DB, 객체 저장소, 외부 API, 다른 데몬) |
| Position | Source 에서 어디까지 처리했는지 (offset, receipt handle, 행 상태, fingerprint+offset) |
| 확인 응답 (ack) | Source 에 "여기까지 처리했다" 고 알리는 것 (offset commit, ack, delete, 행 상태 변경) |
| 멱등 키 (idempotency key) | 같은 입력이면 항상 같은 값이 나오는 키. Sink 가 이 키로 중복을 거른다 |
| Dedup Window | Sink·브로커가 멱등 키를 기억하는 기간 (ClickHouse Replicated 1h/1만 블록·일반 MergeTree 0, Stripe 24h, SQS FIFO 5분, PG UNIQUE 무기한) |
| Backpressure | 하류가 느릴 때 상류를 늦추는 것 |
| DLQ | 처리할 수 없는 항목을 따로 모아 두는 재처리 대기열 |

## Chassis — 모든 데몬 공통

구현·리뷰 때 아래 규칙을 하나라도 어기면 그 이유를 코드 주석이나 설계 메모에 남긴다.

### Lifecycle — 시작·종료 순서, 신호, 종료 예산

- 포그라운드로 뜬다. fork·setsid·PID 파일·자체 재시작 루프를 만들지 않고 수명은 감독자에게 맡긴다. 로그는 stdout/stderr
- 컨테이너에서 앱이 PID 1 이면 신호 핸들러를 직접 달거나 `tini`/`--init` 을 쓴다 (셸 래퍼는 신호를 넘기지 않는다)
- 시작할 때 의존 서비스의 기동 순서에 기대지 않는다. 연결은 백오프로 재시도하고, Configuration 오류만 즉시 exit ≠ 0. 새로 뜬 인스턴스에는 부하를 천천히 올리고 빈 캐시로도 버티게 한다
- 종료는 `ready 끊기 → 입력 중단 → 진행 중 작업 마무리 (drain) → 확인 응답 → 출력 닫기 → exit 0` 순서. 전체가 감독자의 유예 시간 (k8s `terminationGracePeriodSeconds`, systemd `TimeoutStopSec`) 안에 끝나야 하고, 넘치면 남은 것은 버리고 나간다 (Recovery 덕분에 재시작이 다시 처리한다)
- 유예 시간은 sidecar 종료와 나눠 쓰고, 노드가 꺼질 때는 kubelet `shutdownGracePeriod` 때문에 더 짧아질 수 있다
- 롤링 배포 중에는 구버전과 신버전이 같은 Source 를 함께 소비한다 → 출력 형식과 멱등 키 계산식은 두 버전이 공존해도 깨지지 않아야 한다 (Contract 5)
- 상세: `references/chassis-lifecycle.md`

### Recovery — 시작 = 복구 (crash-only)

- 정상 종료와 `kill -9` 가 같은 결과가 되게 만든다. 복구 코드를 따로 두지 않고 시작할 때마다 복구 경로를 탄다
- 잃으면 안 되는 상태는 프로세스 밖 (Source·Sink·전용 저장소) 에 둔다
- 복구가 오래 걸리면 startupProbe 로 보호한다

### Resource Limits — 상한과 Steady State

- 모든 버퍼·큐·동시성에 상한을 두고, 가득 찼을 때 정책 (block = Source 읽기 멈춤 / drop = 버림) 을 명시한다
- 외부 엔티티 수 (고객·테넌트·키) 에 비례해 커지는 메모리 상태를 두지 않는다
- 런타임에 메모리·CPU 상한을 알린다 (`GOMEMLIMIT`, Node `--max-old-space-size-percentage`, JVM `MaxRAMPercentage`, Go 1.25+ 는 GOMAXPROCS 가 cgroup CPU limit 을 따른다). 주기적 GC 호출로 누수를 가리지 않는다
- **Steady State**: 프로세스 밖에 쌓이는 것 (DLQ, 멱등·inbox·outbox 테이블, 처리 완료 행, 디스크 버퍼, 체크포인트, 임시 파일) 에도 정리 주기를 둔다. 정리 TTL 은 Dedup Window 요구 (최대 재처리 지연) 보다 길어야 한다
- 상세: `references/chassis-resources.md` §1·§2

### Overload Protection — 과부하가 연쇄 장애로 번지지 않게

- **Timeouts & Deadlines**: 모든 원격 호출 (같은 호스트의 프로세스 간 호출 포함) 에 연결·요청 타임아웃을 둔다. 값은 하류 지연 분포 (예: p99.9) 로 정한다. Accept 형은 남은 데드라인을 하류로 넘기고, 클라이언트가 이미 포기한 요청은 버린다
- **재시도 예산**: 재시도는 한 층에서만 한다 (층마다 3회면 5층에서 243배). 토큰 버킷이나 비율 (예: 요청의 10% 이하) 로 상한을 두고, 하류가 "과부하, 재시도 금지" 를 알리면 따른다. 재시도율을 지표로 낸다
- **부하 차단 (load shedding)** (Accept 형): 포화된 뒤가 아니라 직전에 싸게 거절한다. 헬스체크와 진행 중 작업을 끝내는 요청을 먼저 받는다. 대기열에서 너무 오래 기다린 요청은 버리고, 스레드 풀·소켓 backlog 같은 숨은 큐도 상한에 넣는다. Pull 형의 대응은 Backpressure (Source pause)
- **Bulkheads·테넌트 격리**: 워크로드·테넌트별로 동시성 상한과 풀을 나눠 한 테넌트의 적체가 전체를 막지 않게 한다 (spillover 큐, shuffle sharding, SQS fair queues)
- 상세: `references/chassis-overload.md` §1~§4

### Failure Handling — 실패를 분류하고 절대 삼키지 않는다

| 분류 | 예 | 동작 | Position |
|---|---|---|---|
| Transient (일시) | Sink 일시 장애·타임아웃 | 재시도 예산 안에서 지수 백오프+지터 재시도 (한 층에서만), Source pause | 유지 |
| Poison (독성) | 역직렬화 실패, 스키마 위반, 호환되지 않는 메시지 버전, N 회 재시도 실패 | 원본·에러·시도 수·Source Position·`traceparent` 와 함께 DLQ, 다음 항목 진행 | 전진 |
| Fatal (복구 불가) | 설정 오류, 불변식 위반, uncaught exception | exit ≠ 0 → 감독자 재시작 (종료 코드로 재시작 여부를 나눌 수 있다) | 유지 (재시작 후 재처리) |
| 종료 중 실패 | — | DLQ 로 보내지 말고 NACK·미커밋 | 유지 |

- `catch` 해서 로그만 찍고 정상 반환하면 확인 응답이 나가 **조용히 유실**된다. DLQ 를 못 두는 환경이면 "알림 후 포기" 를 명시하고 그 손실을 감수하는 이유를 적는다
- 평소에 타지 않는 fallback 경로를 새로 만들지 않는다. 대신 호출자 재시도, 미리 밀어 둔 데이터, 상시 가동하는 failover 를 쓴다. degraded 상태 (Source pause + Position 유지 + 백오프) 는 이 원칙에 맞는다
- 상세 (DLQ 헤더, 재시도 토픽, fallback 대신 failover, 재시작 강도): `references/chassis-failure.md`

### Observability — 건강은 바깥에서 보고, 경보도 바깥이 낸다

- liveness = 프로세스 내부가 진행 중인가 (메인 루프 heartbeat) 만. 의존 서비스 장애를 liveness 에 넣지 않는다
- readiness = 지금 일을 받을 수 있나. 트래픽을 받지 않는 워커에 의미 없는 readiness 를 두지 않는다
- 필수 지표: 처리량·오류율·처리 시간 (RED), 큐·버퍼 사용률·포화 (USE), **가장 오래된 미처리 항목의 나이**, Source lag, 마지막 성공 시각, DLQ 적재 수, 재시도 수·재시도율, 현재 상태 (`<app>_state{state}`), 메모리·fd 수
- stdout 구조화 로그. 필드: `role`, `state`, `source`, `partition`, `offset`, `key`, `attempt`, `trace_id`. 큐를 건너 trace context 를 메시지 헤더로 넘긴다 (OTel messaging)
- 관리 포트를 업무 포트와 분리한다: `/healthz`·`/readyz`·`/metrics`, pprof·heap dump 는 내부 접근만. 로그 레벨 변경 같은 런타임 조작 (control interface) 도 여기에 둔다
- 기능을 일부러 꺼 둔 채 뜨는 경우 (예: 소비자 연결 실패를 무시하고 API 만 기동) 는 반드시 지표로 드러낸다. "파드는 건강한데 소비자는 죽어 있는" 상태를 만들지 않는다
- **경보**: 경보는 같은 프로세스가 아니라 바깥 (지표 + Alertmanager 등) 이 낸다. 죽은 프로세스는 자기 죽음을 알리지 못한다
  - 진행 지표에 건다: 가장 오래된 항목 나이 > SLO, `time() - last_success > 3×주기`, DLQ 증가, 재시도율 급증, 재시작 반복
  - 사라짐은 `up{job="x"} == 0` 과 `absent(up{job="x"})` 를 함께 건다 (absent 만으로는 scrape 실패를 놓친다)
  - 고정 임계값과 함께, 처리 성공률·지연의 SLO 에 다중 윈도 burn-rate 경보를 건다
  - 같은 원인은 묶는다 (grouping·inhibition). 울리는 중이면 `repeat_interval` 마다 다시 가고, 복구 알림은 receiver 의 `send_resolved` 를 켜야 나간다
  - 경보 경로 자체는 dead man's switch (항상 울리는 Watchdog 경보가 끊기면 외부가 알림) 로 감시한다
- 상세: `references/chassis-observability.md` §1~§5

### Configuration — 검증 후 원자 교체, 아니면 재시작

- 시작 시 검증하고 실패하면 즉시 exit ≠ 0
- 바꿀 때는 `파싱 → 검증 → 새 객체 → 원자 교체`. 검증 실패면 이전 설정 유지. 가장 단순한 길은 재적재 없이 롤링 재시작이다. systemd `Type=notify-reload` 면 SIGHUP 핸들러를 `READY=1` 전에 설치한다
- 처리 결과에 영향을 주는 설정 (규칙·단가·매핑) 은 버전을 붙이고 제자리 수정하지 않는다
- 토큰·인증서 같은 자격 증명은 만료된다 → 같은 원자 교체 경로로 다시 읽는다. 권한 낮추기·자원 제한은 프로세스가 아니라 감독자 (systemd unit, k8s securityContext) 에 맡긴다
- 상세: `references/chassis-lifecycle.md` §5

### Admin Processes — 사람이 개입하는 일회성 명령

- 12-Factor XII 의 admin processes: 데몬과 **같은 빌드·같은 설정** 으로 도는 일회성 명령을 같이 만든다
- DLQ 재투입 (`<app> dlq requeue`), Position 되감기·재처리 (`<app> replay`). 되감기 절차에는 멱등 상태 초기화 여부를 같이 적는다
- 상세: `references/chassis-observability.md` §6

### Coordination (선택) — 하나만 돌아야 하는 일

- 스케줄러·마감 작업처럼 단일 실행이 필요할 때만 둔다
- 리더 선출·분산 락은 둘이 동시에 리더가 되는 순간을 막지 못한다 → 쓰기 대상이 세대 번호 (fencing token) 를 검사하거나, 작업 자체를 멱등으로 만든다
- Redis 락이면 `SET NX PX` + **원자적 해제** (Redis 8.4+ `DELEX key IFEQ token`, 그 이전은 Lua compare-and-delete) + 작업 시간이 TTL 을 넘을 수 있으면 연장. PG 를 이미 쓰면 advisory lock 도 선택지다
- 상세: `references/chassis-coordination.md`

## I/O — 역할별

### Input: Pull / Accept

Pull 과 Accept 를 가르는 기준은 누가 연결을 여느냐가 아니라 **누가 처리 속도를 정하고 Position 을 갖느냐** 다 (흔히 pull / push, TCP active / passive open 이라 부른다). RabbitMQ consume 은 브로커가 밀어 주지만 데몬이 prefetch 로 속도를 정하므로 Pull 이다.

| 입력 방향 | 뜻 | Position | Backpressure | 종료 시 |
|---|---|---|---|---|
| **Pull** (client형) | 데몬이 Source 에서 직접 가져온다 (consume, tail, poll, 타이머) | 데몬·Source 가 관리 | 읽기를 멈춘다 (`pause()`, prefetch, 수신 중단) | 읽기 중단 |
| **Accept** (server형) | 들어오는 연결·요청을 받는다 (listen, HTTP·gRPC·TCP) | 없음 (요청 단위) | 부하 차단·대기 시간 상한, 동시 연결 상한, 요청 크기·시간 상한 (Overload Protection) | 새 연결을 받지 않고 기존 연결을 기한 내 마무리 |

### Processing

- 파싱·변환은 가능한 한 순수 함수로 둔다. 시계·sleep·네트워크는 인터페이스 뒤로 숨겨 주입한다 (Verification 에서 가짜로 바꾼다)
- 이벤트 시각 (발생) 과 처리 시각 (수신) 을 구분해 둘 다 남긴다

### Output: Send / Store

- **Send**: 다른 데몬이나 외부 API 로 보낸다. 받는 쪽이 "저장 확정" 을 응답할 때까지 상한 있는 버퍼에 들고 재전송한다
- **Store**: 저장소에 쓴다. 멱등 키나 트랜잭션 체크포인트로 중복을 흡수한다
- 배치로 쓰면 flush 조건은 **건수·바이트·최대 대기 시간 중 먼저 닿는 것**. 타이머는 flush 를 직접 부르지 말고 메인 루프에 신호만 보내 에러가 한 곳으로 모이게 한다

### 유형 = 입력 방향 × Source × Output

| 유형 | Input | Source | Output | 대표 위험 | 상세 |
|---|---|---|---|---|---|
| 큐·스트림 소비자 | Pull | Kafka (consumer group·share group)·SQS·RabbitMQ·PG 큐 | Store / Send | 처리 전 커밋, 리밸런스 중복, 독성 메시지, 적체 | `references/io.md` §1 |
| 수집 에이전트 (파일 tailer) | Pull | 로컬 파일 | Send | 로테이트 누락, inode 재사용, Backpressure 중 유실 | §2 |
| store-and-forward | Pull | 내부 생성 데이터 → 디스크 버퍼 | Send | 버퍼 가득, fsync 간격만큼 유실 | §3 |
| 폴러·스케줄러 | Pull | 타이머 | Store / Send | 중복 실행, 놓친 회차, 겹친 실행 | §4 |
| 수집 서버·API 서버 | Accept | 연결·요청 | Store (+ 응답) | 엔드포인트 제거 경쟁, 장기 연결 drain, 과부하 | §5 |

## Contract — 구간과 구간 사이

데몬 하나는 `Source → 데몬`, `데몬 → Sink` 두 구간에 걸친다. 에이전트 → 수집 서버 → DB 처럼 이어지면 모든 구간에 같은 계약이 적용된다.

1. **전달 보장**: 기본은 **at-least-once + 멱등 Sink**. 중복은 반드시 온다. at-most-once 를 고르면 "유실돼도 되는 이유" 를 적는다
2. **확인 응답 순서**: `읽기 → 처리 → Sink 쓰기 확정 → 확인 응답`. auto-commit·auto-ack 금지. 병렬 처리하면 **빈틈 없이 끝난 지점까지만** 확인 응답한다
3. **멱등 키**: Source 에서 결정적으로 만든다 (`now()`·쓰기 시점 UUID 금지). Redis 같은 TTL 캐시는 앞단 필터일 뿐 근거가 아니다. **Dedup Window > 최대 재처리 지연** (DLQ 재투입·수동 replay 포함) 을 확인한다
4. **재전송**: 보내는 쪽은 상한 있는 버퍼 + 백오프로 재전송한다. 받는 쪽은 "저장 확정" 을 응답하고, 보내는 쪽은 그 응답을 받은 뒤에만 Position 을 넘긴다 (종단 간 확인 응답)
5. **스키마 진화와 버전 공존**: 메시지에 스키마 버전을 싣고 호환 규칙을 정한다. 모르는 필드는 버리지 말고 통과시키고, 호환되지 않는 버전은 Poison 으로 다룬다. 롤링 배포 중 구버전·신버전이 함께 돌아도 출력 형식과 멱등 키 계산식이 깨지지 않아야 한다

Sink 별 멱등 방식은 셋 중 하나를 고른다 (상세 표: `references/contract.md` §1·§2, 재전송: §3, outbox·inbox: §4, 스키마 진화: §5).

1. **트랜잭션 체크포인트**: Sink 가 트랜잭션 DB 면 데이터와 Position 을 같은 트랜잭션에 쓰고, 시작할 때 Sink 에 저장된 Position 부터 읽는다 (가장 강함)
2. **결정적 키 + Sink 중복 거부**: UNIQUE + `ON CONFLICT DO NOTHING`, ClickHouse `insert_deduplication_token`, S3 `If-None-Match: *`, HTTP `Idempotency-Key`
3. **결정적 배치 경계**: 재처리해도 같은 경계로 잘리게 (`partition + startOffset..endOffset`) 하고 그 경계를 배치 키로

"이미 있음" 응답 (0 rows, 412, dedup skip) 은 **성공** 으로 다룬다. 단, 같은 키에 저장된 실패 응답까지 돌려주는 Sink (Stripe v1 의 500) 는 재시도가 재실행이 아니다.

## Verification — 증명하기 전엔 완료가 아니다

`references/verification.md` 의 시험을 CI 또는 PR 검증에 넣는다. 최소 기준:

- [ ] 크래시 지점 (Sink 쓰기 직전·직후, 확인 응답 직전) 마다 `kill -9` → 재시작 후 **누락 0**, 중복은 Sink 에서 흡수됨
- [ ] 처리 중 SIGTERM → 유예 시간 안에 exit 0, 진행 중 항목 손실 없음
- [ ] Sink 장애 주입 (Toxiproxy 등) → 메모리 상한 안에서 Backpressure, 복구 후 자동 재개
- [ ] 독성 입력 → DLQ 로 가고 뒤 항목은 계속 처리
- [ ] 한계를 넘는 부하 → 부하 차단이 싸게 거절하고, 받은 요청의 지연은 유지된다 (Accept 형)
- [ ] 롤링 배포 중 구버전·신버전 공존 → 누락 0, 중복 흡수
- [ ] 장시간 부하 → RSS·fd·goroutine/핸들 수와 프로세스 밖 누적물 (DLQ·멱등 테이블) 평탄

## 설계·구현 절차

새 데몬을 만들거나 기존 데몬을 고칠 때 이 순서로 정하고, 정한 내용을 설계 메모 (PR 본문 또는 README) 에 남긴다.

1. **I/O 를 정한다**: Input 방향 (Pull / Accept), Source, Output (Send / Store), Sink, 실행 환경 (Kubernetes 기본 / systemd / 둘 다). 위 유형표에서 해당 행의 상세를 읽는다
2. **Contract 를 구간마다 정한다**: 전달 보장, 멱등 방식, Dedup Window 와 최대 재처리 지연 비교, 메시지 스키마 버전과 호환 규칙
3. **Lifecycle 상태 기계를 그린다**

   ```
   starting ─▶ recovering ─▶ ready ⇄ degraded ─▶ draining ─▶ stopped
      │ 설정 검증 실패        │ 복구 실패                     │ 예산 초과
      └──────────────▶ exit≠0 ◀┘                              └▶ 남은 것 버리고 exit
   ```

   | 상태 | 하는 일 | readiness |
   |---|---|---|
   | starting | Configuration 검증 (실패면 exit), 의존 연결 (백오프 재시도) | false |
   | recovering | Position 복원, 미완료 작업 재생 | false |
   | ready | 정상 처리 | true |
   | degraded | Sink 장애: Source 읽기 멈추고 Position 유지, 백오프 재시도 | Pull 형은 true 유지 가능, Accept 형은 false |
   | draining | SIGTERM 이후 Lifecycle 종료 순서 | false |

4. **신호와 종료 예산을 정한다**

   | 신호 | 동작 |
   |---|---|
   | SIGTERM / SIGINT | draining |
   | SIGHUP | Configuration 재적재 (systemd `Type=notify-reload` 일 때만, 핸들러는 `READY=1` 전에 설치. k8s 는 롤링 재시작이 기본) |
   | SIGKILL·OOM·노드 장애 | 처리 불가 → Recovery 로 대비 |

   예산 (k8s): `preStop 시간 + 진행 중 배치 최대 처리 시간 + 확인 응답 + sidecar 종료 + 여유 < terminationGracePeriodSeconds`. **유예 시간 카운트다운은 preStop 전부터 시작하고, SIGTERM 은 preStop 이 끝난 뒤에 온다.** 노드 종료 때는 이보다 짧아질 수 있다. 런타임별 종료 관용구 (Go, NestJS/Node, JVM/Spring, Python) 와 런타임별 메모리 상한은 `references/chassis-lifecycle.md` §4

5. **처리 루프를 짠다** (Pull 형 기본형. Source 별 차이는 `references/io.md`)

   ```
   on SIGTERM:          stopping = true
   on revoke(parts):    drain(inflight[parts]); commitSync(done[parts])   # 소유권 넘기기 전에
   on lost(parts):      cancel(inflight[parts])                           # 이미 잃었으면 커밋 금지

   while not stopping:
     if inflight > HIGH:  pause()             # Backpressure: 다음 fetch 만 막는다
     elif inflight < LOW: resume()
     batch = poll(timeout)                    # pause 중에도 poll 을 불러 max.poll.interval 을 넘기지 않는다
     for msg in batch:                        # 이미 받은 레코드는 버리지 않고 반드시 처리한다
       lease = extendVisibility(msg)          # SQS·PG lease 연장 (필요한 Source 만)
       try:   sink.writeIdempotent(key(msg), transform(msg)); markDone(msg)
       except Transient:     retryLater(msg, backoff(msg.attempts))   # 재시도 예산 안에서
       except Poison|MaxTry: dlq.put(msg, error, attempts, origin, traceparent); markDone(msg)
       except Fatal:         raise            # 프로세스 종료 → 감독자 재시작
       finally: lease.stop()
     commit(contiguousDone())                 # 빈틈 없이 끝난 지점까지만
   drain(inflight, deadline); commitSync(); close()
   ```

6. **Failure Handling 표를 이 데몬에 맞게 채운다** (어떤 오류가 Transient·Poison·Fatal 인지, Fatal 의 종료 코드)
7. **Overload Protection 을 정한다**: 원격 호출마다 타임아웃, 재시도를 할 층 하나와 재시도 예산, Accept 형이면 부하 차단 기준, 테넌트 격리 단위
8. **Resource Limits·Steady State 를 정한다**: 버퍼·동시성 상한, 런타임 상한, 프로세스 밖 누적물의 정리 주기
9. **Observability·Admin Processes 를 붙인다**: 지표·경보·trace 전파, 관리 포트, DLQ 재투입·replay 명령
10. **Configuration·Coordination 을 정한다** (Coordination 은 단일 실행이 필요할 때만)
11. **Verification 을 통과시킨다**

## 리뷰 점검 목록

기존 데몬이나 PR 을 리뷰할 때 이 순서로 본다.

1. **Failure Handling**: 처리 콜백의 예외가 어디서 잡히는가 — 잡고 로그만 남긴 뒤 정상 반환하면 유실. RabbitMQ 에서 `nack` 만 쓰면 독성 메시지가 DLQ 로 가지 않고 무한히 돈다
2. **Contract — 확인 응답 순서**: auto-commit/auto-ack 인가, Sink 쓰기 뒤인가. 리밸런스·소유권 상실 시 처리. Backpressure 로 받아 온 batch 를 버리지 않는가
3. **Contract — 멱등 키**: Sink 쓰기가 멱등인가, 멱등 키가 결정적인가, Dedup Window 가 충분한가, 키 계산식이 버전 간에 같은가
4. **Overload Protection**: 모든 원격 호출에 타임아웃이 있는가, 재시도가 여러 층에서 겹치지 않는가, Accept 형이면 부하 차단이 있는가
5. **Lifecycle**: 종료 훅이 실제로 등록되는가 (NestJS `enableShutdownHooks()`, Go `signal.NotifyContext`, Spring Boot 3.4+ 는 graceful 이 기본이므로 `server.shutdown=immediate` 로 꺼 두지 않았는가, 웹이 아닌 워커는 `SmartLifecycle` 로 drain 하는가), 예산 안에 끝나는가
6. **Resource Limits**: 큐·배치·동시성 상한, 외부 엔티티 수에 비례하는 메모리, 프로세스 밖 누적물의 정리 주기
7. **Observability**: liveness 에 외부 의존이 섞였는가, 비활성 기능이 드러나는가, 사라짐 경보가 `up == 0` 도 잡는가
8. **Coordination**: 락 해제가 원자적인가, TTL < 작업 시간일 때 대책
9. **Verification**: 크래시 지점 시험이 있는가

사례: `references/case-studies.md` (OpenMeter·Lago 소스, 익명화한 사내 코드).

## references

| 파일 | 내용 |
|---|---|
| `references/chassis-lifecycle.md` | Lifecycle·Recovery·Configuration: k8s 종료 순서·프로브·재시작, PID 1, systemd unit·sd_notify, 런타임별 종료 관용구·메모리 상한, 설정 재적재·자격 증명, 데몬화 15단계와 그 이유 |
| `references/chassis-resources.md` | Resource Limits: 상한, Steady State (프로세스 밖 누적물 정리) |
| `references/chassis-overload.md` | Overload Protection: 타임아웃·데드라인, 재시도 예산, 부하 차단·승인 제어, bulkhead·테넌트 격리 |
| `references/chassis-failure.md` | Failure Handling: 독성 입력·DLQ·재시도 토픽, fallback 대신 failover, 감독 전략 (재시작 강도) |
| `references/chassis-observability.md` | Observability·Admin Processes: 지표·경보·로그·trace 전파, 관리 포트, 운영 명령 |
| `references/chassis-coordination.md` | Coordination: 분산 락의 한계·원자적 해제·펜싱, 리더 선출, advisory lock |
| `references/io.md` | I/O: 유형별 상세 (큐 소비자·적체 회복, 수집 에이전트, store-and-forward, 폴러·스케줄러, 수집 서버·API 서버) |
| `references/contract.md` | Contract: Sink 별 멱등 기법·Dedup Window·함정, 범용 레시피, 재전송과 종단 간 확인 응답, outbox·inbox, 스키마 진화와 버전 공존, durable execution |
| `references/verification.md` | Verification: 크래시 지점·종료·하류 장애·독성 입력·리밸런스·과부하·버전 공존·soak 시험, 결정적 시뮬레이션 |
| `references/case-studies.md` | 실제 코드에서 본 좋은 점·함정 |
