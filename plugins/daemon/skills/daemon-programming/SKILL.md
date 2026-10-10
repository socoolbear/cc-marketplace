---
name: daemon-programming
description: 데몬 (오래 떠서 입력을 받아 처리하는 프로세스 — 수집 에이전트, 큐·스트림 소비자, 백그라운드 워커, 폴러·스케줄러, 수집 서버, API 서버의 실행 측면) 을 설계·구현·리뷰하는 데몬 프로그래밍 기법. 데몬을 Chassis (Lifecycle·Recovery·Resource Limits·Overload Protection·Failure Handling·Observability·Configuration·Admin Processes·Coordination) + I/O (Source·Sink, Pull/Accept 입력, Send/Store 출력) + Contract (전달 보장·확인 응답 순서·멱등 키·재전송·스키마 진화) 로 나눠 다룬다. "데몬 만들어줘", "워커 구현", "컨슈머 구현", "에이전트 구현", "상주 프로세스", "graceful shutdown", "SIGTERM 처리", "오프셋 커밋", "at-least-once", "중복 처리 방지", "재시작하면 데이터가 빠져", "헬스체크 설계", "크론 중복 실행 방지", "tail 구현", "역압", "DLQ", "재시도 폭주", "타임아웃 설계", "부하 차단", "큐 적체", "병렬 처리", "컨슈머 처리량", "lag 이 안 줄어", "서버 실행 모델", "pre-fork", "스레드 풀 vs 이벤트 루프 (서버)" 같은 요청이면 반드시 이 스킬을 사용할 것. 일회성 배치·CLI, API 의 업무 로직·설계, 쿼리·알고리즘 같은 일반 성능 튜닝, 이미 만든 프로세스를 launchd·systemd 에 등록하거나 백그라운드로 띄우는 운영 요청은 대상이 아니다.
---

# daemon-programming — 데몬 프로그래밍

**데몬**은 오래 떠서 바깥 입력을 받아 처리하고 바깥 상태를 바꾸는 프로세스다. 로그 수집 에이전트 (client), 수집 서버 (server), 큐 소비자, 폴러가 모두 데몬이다. **데몬 프로그래밍**은 데몬이 **정합성** (언제 죽어도 데이터가 빠지거나 틀어지지 않는다), **가시성** (죽거나 멈추면 바깥이 알아챈다), **자기 회복** (다시 켜면 알아서 이어 간다) 을 갖추게 만드는 일이다.

> **데몬화 (daemonize)** 는 Lifecycle 의 한 부품이다. 옛 방식 (double fork·setsid·PID 파일) 은 이제 감독자가 대신한다 → `references/chassis-lifecycle.md` §6. 여러 단계에 걸쳐 부수효과를 내고 오래 기다리는 작업이면 손으로 at-least-once + 체크포인트를 짜기 전에 **durable execution 엔진** (Temporal 등) 을 먼저 본다 → `references/contract.md` §6.

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

**Chassis** 는 역할과 무관한 공통 골격, **I/O** 는 역할별 부분 (client 와 server 를 가르는 축은 **입력 방향 하나**: Pull / Accept), **Contract** (구간 계약) 는 구간 사이의 전달 약속이다. 앞 데몬의 Sink 가 곧 다음 데몬의 Source 다.

## 용어 (이 스킬 안에서 고정)

| 용어 | 뜻 |
|---|---|
| 감독자 (supervisor) | 프로세스를 띄우고 죽으면 다시 띄우는 바깥 주체 (kubelet, systemd) |
| Source / Sink | 데몬이 읽는 곳 (Kafka 토픽, SQS 큐, PG 작업 테이블, 파일, 타이머, 들어오는 연결) / 쓰는 곳 (DB, 객체 저장소, 외부 API, 다른 데몬) |
| Position | Source 에서 어디까지 처리했는지 (offset, receipt handle, 행 상태, fingerprint+offset) |
| 확인 응답 (ack) | Source 에 "여기까지 처리했다" 고 알리는 것 (offset commit, ack, delete, 행 상태 변경) |
| 멱등 키 (idempotency key) | 같은 입력이면 항상 같은 값이 나오는 키. Sink 가 이 키로 중복을 거른다 |
| Dedup Window | Sink·브로커가 멱등 키를 기억하는 기간. Sink 별 값 (일반 MergeTree 는 0, PG UNIQUE 는 정리 TTL 이 곧 창) 은 `references/contract.md` §1 |
| Backpressure | 하류가 느릴 때 상류를 늦추는 것 |
| DLQ | 처리할 수 없는 항목을 따로 모아 두는 재처리 대기열 |

## Chassis — 모든 데몬 공통

구현·리뷰 때 아래 규칙을 하나라도 어기면 그 이유를 코드 주석이나 설계 메모에 남긴다.

### Lifecycle — 시작·종료 순서, 신호, 종료 예산 (`references/chassis-lifecycle.md`)

- 포그라운드로 뜬다. fork·setsid·PID 파일·자체 재시작 루프 없이 수명은 감독자에게 맡긴다. 로그는 stdout/stderr. 컨테이너에서 앱이 PID 1 이면 신호 핸들러를 직접 달거나 `tini`/`--init` 을 쓰고, 셸 래퍼·`npm start` 대신 exec form 으로 앱을 직접 띄운다 (신호가 앱까지 닿지 않을 수 있다)
- 시작할 때 의존 서비스의 기동 순서에 기대지 않는다. 연결은 백오프로 재시도하고, Configuration 오류만 즉시 exit ≠ 0. 새 인스턴스에는 부하를 천천히 올리고 빈 캐시로도 버티게 한다
- 종료는 `(k8s 밖 LB 뒤면 먼저 readiness false. k8s 는 terminating 엔드포인트를 자동 ready=false) → (Accept 형: 엔드포인트 제거가 퍼질 때까지 수 초 더 수신 — preStop sleep) → 입력 중단 → 진행 중 작업 마무리 (drain) → 확인 응답 → 출력 닫기 → exit 0` 순서. 전체가 감독자의 유예 시간 (k8s `terminationGracePeriodSeconds`, systemd `TimeoutStopSec`) 안에 끝나야 하고, 넘치면 남은 것은 버리고 나간다 (Recovery 가 재시작 뒤 다시 처리한다)
- 유예 시간은 sidecar 종료와 나눠 쓰고, 노드가 꺼질 때는 더 짧아지거나 유예 없이 죽을 수 있다. 롤링 배포 중에는 구버전과 신버전이 같은 Source 를 함께 소비한다 → 출력 형식과 멱등 키 계산식은 공존해도 깨지지 않아야 한다 (Contract 5)

### Recovery — 시작 = 복구 (crash-only)

- 정상 종료와 `kill -9` 가 같은 결과가 되게 만든다. 복구 코드를 따로 두지 않고 시작할 때마다 복구 경로를 탄다
- 잃으면 안 되는 상태는 프로세스 밖 (Source·Sink·전용 저장소) 에 둔다. 복구가 오래 걸리면 startupProbe 로 보호한다

### Resource Limits — 상한과 Steady State (`references/chassis-resources.md` §1·§2)

- 모든 버퍼·큐·동시성에 상한을 두고, 가득 찼을 때 정책 (block = Source 읽기 멈춤 / drop = 버림) 을 명시한다. 외부 엔티티 수 (고객·테넌트·키) 에 비례해 커지는 메모리 상태를 두지 않는다
- 런타임에 메모리·CPU 상한을 알린다 (런타임별 설정·버전 조건: `references/chassis-lifecycle.md` §4). 주기적 GC 호출로 누수를 가리지 않는다
- **Steady State**: 프로세스 밖에 쌓이는 것 (DLQ, 멱등·inbox·outbox 테이블, 처리 완료 행, 디스크 버퍼, 체크포인트, 임시 파일) 에도 정리 주기를 둔다. 정리 TTL 은 Dedup Window 요구 (최대 재처리 지연) 보다 길어야 한다

### Overload Protection — 과부하가 연쇄 장애로 번지지 않게 (`references/chassis-overload.md` §1~§4)

- **Timeouts & Deadlines**: 모든 원격 호출 (같은 호스트의 프로세스 간 호출 포함) 에 연결·요청 타임아웃을 둔다. 값은 하류 지연 분포 (예: p99.9) 로 정한다. Accept 형은 남은 데드라인을 하류로 넘기고, 클라이언트가 이미 포기한 요청은 버린다
- **재시도 예산**: 재시도는 거절한 계층의 바로 위 (그 계층을 직접 부른 쪽) 한 곳에서만 한다 (5계층 × 3회 = 243배). 토큰 버킷이나 비율 (예: 요청의 10% 이하) 로 상한을 두고, 하류가 "재시도 금지" 를 알리면 따른다. 재시도율을 지표로 낸다
- **부하 차단 (load shedding)** (Accept 형): 포화된 뒤가 아니라 직전에 싸게 거절한다. 헬스체크와 진행 중 작업을 끝내는 요청을 먼저 받는다. 오래 기다린 요청은 버리고, 스레드 풀·소켓 backlog 같은 숨은 큐도 상한에 넣는다. Pull 형의 대응은 Backpressure (Source pause)
- **Bulkheads·테넌트 격리**: 워크로드·테넌트별로 동시성 상한과 풀을 나눠 한 테넌트의 적체가 전체를 막지 않게 한다

### Failure Handling — 실패를 분류하고 절대 삼키지 않는다 (`references/chassis-failure.md`)

| 분류 | 예 | 동작 | Position |
|---|---|---|---|
| Transient (일시) | Sink 는 건강한데 그 항목만 실패 (락 충돌·특정 항목 타임아웃) | 재시도 예산 안에서 지수 백오프+지터 재시도 (한 층에서만), N 회 뒤 Poison | 유지 |
| Sink 전체 장애 (SinkDown) | 재시도할 만한 오류 (연결 실패·타임아웃·429·503) 가 났고 쓰기 경로 확인 (canary 쓰기) 도 실패 | 수신을 멈추고 백오프 (degraded, 429·503 은 `Retry-After` 를 하한으로). 메시지별 시도 수도 브로커 전달 횟수도 쓰지 않는다 (연장 상한까지) | 유지 |
| Poison (독성) | 역직렬화 실패, 스키마 위반, 호환되지 않는 메시지 버전, N 회 재시도 실패 | 원본·에러·시도 수·Source Position·`traceparent` 와 함께 DLQ, 다음 항목 진행 | 전진 |
| Fatal (복구 불가) | 설정 오류, 불변식 위반, uncaught exception | exit ≠ 0 → 감독자 재시작 (종료 코드별 재시작 제외는 systemd 만. k8s Deployment 는 재시작 반복 경보로 잡는다 — `references/chassis-failure.md` §2) | 유지 (재시작 후 재처리) |
| 종료 중 실패 | 종료 (context 취소) 로 생긴 실패 | 시도 수·DLQ 를 건드리지 않고 NACK·미커밋 | 유지 |

- `catch` 해서 로그만 찍고 정상 반환하면 확인 응답이 나가 **조용히 유실**된다. DLQ 를 못 두는 환경이면 "알림 후 포기" 를 명시하고 그 손실을 감수하는 이유를 적는다. 평소에 타지 않는 fallback 경로를 새로 만들지 않는다. 호출자 재시도, 미리 밀어 둔 데이터, 상시 가동 failover 를 쓴다. degraded 상태 (Source pause + Position 유지 + 백오프) 는 이 원칙에 맞는다

### Observability — 건강은 바깥에서 보고, 경보도 바깥이 낸다 (`references/chassis-observability.md` §1~§5)

- liveness = 프로세스 내부가 진행 중인가 (메인 루프 heartbeat) 만. 의존 서비스 장애를 liveness 에 넣지 않는다. readiness = 지금 일을 받을 수 있나. 그 인스턴스만의 문제 (워밍업, 로컬 포화, draining) 에 쓴다. Sink 같은 공유 의존 장애로 끄면 모든 파드가 빠져 엔드포인트가 0 이 된다. 트래픽을 받지 않는 워커에 의미 없는 readiness 를 두지 않는다
- 필수 지표: 처리량·오류율·처리 시간 (RED), 큐·버퍼 사용률·포화 (USE), **가장 오래된 미처리 항목의 나이**, Source lag, 마지막 성공 시각, DLQ 적재 수, 재시도 수·재시도율, 현재 상태 (`<app>_state{state}`), 메모리·fd 수
- stdout 구조화 로그 (`role`, `state`, `source`, `partition`, `offset`, `key`, `attempt`, `trace_id`). 큐를 건너 trace context 를 메시지 헤더로 넘긴다 (OTel messaging). 관리 포트를 업무 포트와 분리한다: `/healthz`·`/readyz`·`/metrics`, pprof·heap dump·로그 레벨 변경은 내부 접근만
- 기능을 일부러 꺼 둔 채 뜨는 경우 (예: 소비자 연결 실패를 무시하고 API 만 기동) 는 반드시 지표로 드러낸다. "파드는 건강한데 소비자는 죽어 있는" 상태를 만들지 않는다
- **경보**는 같은 프로세스가 아니라 바깥 (지표 + Alertmanager 등) 이 낸다. 죽은 프로세스는 자기 죽음을 알리지 못한다
  - 진행 지표에 건다: 가장 오래된 항목 나이 > SLO, DLQ 증가, 재시도율 급증, 재시작 반복. `time() - last_success > 3×주기` 는 주기 실행·heartbeat 파이프라인에만 (입력이 끊길 수 있는 소비자는 가장 오래된 미처리 항목 나이로)
  - 사라짐은 `up{job="x"} == 0` 과 `absent(up{job="x"})` 를 함께 건다 (absent 만으로는 scrape 실패를 놓친다). 성공률·지연은 SLO burn-rate 경보, 경보 경로는 dead man's switch (Watchdog) 로 감시한다

### Configuration — 검증 후 원자 교체, 아니면 재시작 (`references/chassis-lifecycle.md` §5)

- 시작 시 검증하고 실패하면 즉시 exit ≠ 0
- 바꿀 때는 `파싱 → 검증 → 새 객체 → 원자 교체`. 검증 실패면 이전 설정 유지. 가장 단순한 길은 재적재 없이 롤링 재시작이다. systemd `Type=notify-reload` 면 SIGHUP 처리를 `READY=1` 전에 준비한다 (미준비 시 시작이 중단되는 버전이 있다)
- 처리 결과에 영향을 주는 설정 (규칙·단가·매핑) 은 버전을 붙이고 제자리 수정하지 않는다. 만료되는 자격 증명 (토큰·인증서) 은 같은 원자 교체 경로로 다시 읽는다. 권한 낮추기·자원 제한은 감독자 (systemd unit, k8s securityContext) 에 맡긴다

### Admin Processes — 사람이 개입하는 일회성 명령 (`references/chassis-observability.md` §6)

- 데몬과 **같은 빌드·같은 설정** 으로 도는 일회성 명령을 같이 만든다: DLQ 재투입 (`<app> dlq requeue`), Position 되감기·재처리 (`<app> replay`). 되감기 절차에는 멱등 상태 초기화 여부를 같이 적는다

### Coordination (선택) — 하나만 돌아야 하는 일 (`references/chassis-coordination.md`)

- 스케줄러·마감 작업처럼 단일 실행이 필요할 때만 둔다. 리더 선출·분산 락은 둘이 동시에 리더가 되는 순간을 막지 못한다 → 쓰기 대상이 세대 번호 (fencing token) 를 검사하거나, 작업 자체를 멱등으로 만든다
- Redis 락이면 `SET NX PX` + **원자적 해제** (compare-and-delete, 명령은 상세 참조) + 작업이 TTL 을 넘을 수 있으면 연장. PG 를 이미 쓰면 advisory lock (전용 커넥션 고정)

## I/O — 역할별

### Input: Pull / Accept

Pull 과 Accept 를 가르는 기준은 누가 연결을 여느냐가 아니라 **누가 처리 속도를 정하고 Position 을 갖느냐** 다. RabbitMQ consume 은 브로커가 밀어 주지만 데몬이 prefetch 로 속도를 정하므로 Pull 이다.

| 입력 방향 | 뜻 | Position | Backpressure | 종료 시 |
|---|---|---|---|---|
| **Pull** (client형) | 데몬이 Source 에서 직접 가져온다 (consume, tail, poll, 타이머) | 데몬·Source 가 관리 | 읽기를 멈춘다 (`pause()`, prefetch, 수신 중단) | 읽기 중단 |
| **Accept** (server형) | 들어오는 연결·요청을 받는다 (listen, HTTP·gRPC·TCP) | 없음 (요청 단위) | 부하 차단·대기 시간 상한, 동시 연결 상한, 요청 크기·시간 상한 (Overload Protection) | 새 연결을 받지 않고 기존 연결을 기한 내 마무리 |

Accept 형은 실행 모델 (pre-fork·thread pool·event loop·경량 동시성) 에 따라 종료 신호·상한·블로킹 함정이 다르다 → `references/io.md` §7

### Processing·Output

- 파싱·변환은 가능한 한 순수 함수로 둔다. 시계·sleep·네트워크는 인터페이스 뒤로 숨겨 주입한다 (Verification 에서 가짜로 바꾼다). 이벤트 시각 (발생) 과 처리 시각 (수신) 은 둘 다 남긴다
- **Concurrency·Throughput**: 병렬 단위 (파티션·키·레코드) 는 순서 요구로 고른다. 동시성 = 목표 처리량 × 건당 처리 시간이고, 하류 한도가 상한이다: `최대 인스턴스 수 (HPA max + 배포 surge + 종료 유예 중인 파드) × 인스턴스당 연결 풀 ≤ 하류 허용치`. CPU 작업은 이벤트 루프 밖에서 돌린다 → `references/io.md` §6
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
| 수집 서버·API 서버 | Accept | 연결·요청 | Store (+ 응답) | 엔드포인트 제거 경쟁, 장기 연결 drain, 과부하 | §5·§7 |

## Contract — 구간과 구간 사이

데몬 하나는 `Source → 데몬`, `데몬 → Sink` 두 구간에 걸친다. 에이전트 → 수집 서버 → DB 처럼 이어지면 모든 구간에 같은 계약이 적용된다.

1. **전달 보장**: 기본은 **at-least-once + 멱등 Sink**. 중복은 반드시 온다. at-most-once 를 고르면 "유실돼도 되는 이유" 를 적는다
2. **확인 응답 순서**: `읽기 → 처리 → Sink 쓰기 확정 → 확인 응답`. auto-commit·auto-ack 금지 (예외: librdkafka `enable.auto.offset.store=false` + 처리 끝난 offset 만 store 하는 주기 커밋 — `references/io.md` §1). 병렬 처리하면 **빈틈 없이 끝난 지점까지만** 확인 응답한다
3. **멱등 키**: Source 에서 결정적으로 만든다 (`now()`·쓰기 시점 UUID 금지). Redis 같은 TTL 캐시는 앞단 필터일 뿐 근거가 아니다. **Dedup Window > 최대 재처리 지연** (DLQ 재투입·수동 replay 포함) 을 확인한다
4. **재전송**: 보내는 쪽은 상한 있는 버퍼 + 백오프로 재전송한다. 받는 쪽은 "저장 확정" 을 응답하고, 보내는 쪽은 그 응답을 받은 뒤에만 Position 을 넘긴다 (종단 간 확인 응답)
5. **스키마 진화와 버전 공존**: 메시지에 스키마 버전을 싣고 호환 규칙을 정한다. 모르는 필드는 버리지 말고 통과시키고 (Avro 는 reader schema 로 decode 하면 사라진다), 호환되지 않는 버전은 Poison 으로 다룬다. Schema Registry 를 쓰면 호환 모드가 배포 순서를 정한다 (기본 `BACKWARD` 는 소비자 먼저) → `references/contract.md` §5

Sink 별 멱등 방식은 셋 중 하나를 고른다 (표: `references/contract.md` §1·§2, 재전송: §3, outbox·inbox: §4).

1. **트랜잭션 체크포인트**: Sink 가 트랜잭션 DB 면 데이터와 Position 을 같은 트랜잭션에 쓰고, 시작할 때, consumer group 이면 파티션 할당 콜백 (`onPartitionsAssigned`) 마다 Sink 에 저장된 Position 으로 seek 한다. offset 은 조건부 upsert (`… ON CONFLICT DO UPDATE … WHERE next_offset = :start`, `:start` = 할당 때 Sink 에서 읽은 저장값, 이후는 직전 배치의 `:end`) 로 쓴다. 0 rows 면 롤백하고, revoke·lost 를 받았으면 멈추고, 아니면 저장값을 다시 읽어 seek 한 뒤 계속한다 (소유권을 잃은 인스턴스가 먼저 커밋한 경우이고, 데이터와 offset 이 한 트랜잭션이라 중복은 없다). 같은 파티션에서 반복되면 경보한다. 늦은 커밋 자체를 막으려면 행에 소유 세대 (generation·member epoch) 를 두고 조건에 넣는다. seek 위치가 저장값과 다르면 (retention 으로 지워져 reset) 그 사이는 유실이다 → 경보 후 사람이 판단해 맞춘다. 이 조건이 있을 때 가장 강하다
2. **결정적 키 + Sink 중복 거부**: UNIQUE + `ON CONFLICT DO NOTHING`, ClickHouse `insert_deduplication_token`, S3 `If-None-Match: *`, HTTP `Idempotency-Key`
3. **결정적 배치 경계**: 재처리해도 같은 경계로 잘리게 (`partition + startOffset..endOffset`) 하고 그 경계를 배치 키로

"이미 있음" 응답 (데이터 INSERT 의 `ON CONFLICT DO NOTHING` 0 rows, 412, dedup skip) 은 **성공** 으로 다룬다. offset 조건부 upsert·lease UPDATE 의 0 rows 는 소유권 문제다 (위 1번, `references/io.md` §1). 단, 같은 키에 저장된 실패 응답까지 돌려주는 Sink (Stripe v1 의 500) 는 재시도가 재실행이 아니다.

## Verification — 증명하기 전엔 완료가 아니다

`references/verification.md` 의 시험을 CI 또는 PR 검증에 넣는다. 최소 기준:

- [ ] 크래시 지점 (Sink 쓰기 직전·직후, 확인 응답 직전) 마다 `kill -9` → 재시작 후 **누락 0**, 중복은 Sink 에서 흡수됨
- [ ] 처리 중 SIGTERM → 유예 시간 안에 exit 0, 진행 중 항목 손실 없음. 독성 입력 → DLQ 로 가고 뒤 항목은 계속 처리
- [ ] Sink 장애 주입 (연결 차단, 그리고 연결은 되는데 쓰기만 실패·429) → 메모리 상한 안에서 Backpressure, 장애 동안 DLQ 적재 0·브로커 전달 횟수 미소모 (연장 상한 안의 장애 기준), 복구 후 자동 재개
- [ ] 한계를 넘는 부하 → 부하 차단이 싸게 거절하고, 받은 요청의 지연은 유지된다 (Accept 형). 롤링 배포 중 구버전·신버전 공존 → 누락 0, 중복 흡수
- [ ] 목표보다 높은 부하로 적체를 만든 뒤 → lag 이 줄어들고, 그동안 Sink 오류율·메모리·하류 연결 수가 유계
- [ ] 장시간 부하 → RSS·fd·goroutine/핸들 수와 프로세스 밖 누적물 (DLQ·멱등 테이블) 평탄

## 설계·구현 절차

새 데몬을 만들거나 기존 데몬을 고칠 때 이 순서로 정하고, 정한 내용을 설계 메모 (PR 본문 또는 README) 에 남긴다.

**형태 제안 (구현 전)**: 1단계의 형태 (Input 방향·유형, 실행 모델 (`references/io.md` §7), 병렬 단위·순서 요구, 런타임) 를 요청과 기존 코드로 정할 수 없고, 답에 따라 구조가 크게 달라지면 코드를 쓰기 전에 사용자에게 제안하고 확인받는다. 후보 2~3개에 trade-off 와 추천안을 붙인다. 런타임이 없는 새 프로젝트면 런타임 후보도 함께 낸다 (런타임이 실행 모델을 정한다). 정해지면 묻지 않고 설계 메모에만 남긴다.

1. **I/O 를 정한다**: Input 방향 (Pull / Accept), Source, Output (Send / Store), Sink, 실행 환경 (Kubernetes 기본 / systemd / 둘 다). 위 유형표에서 해당 행의 상세를 읽는다. 목표 처리량·순서 요구로 병렬 단위·동시성을 정한다 (`references/io.md` §6)
2. **Contract 를 구간마다 정한다**: 전달 보장, 멱등 방식, Dedup Window 와 최대 재처리 지연 비교, 메시지 스키마 버전과 호환 규칙, Schema Registry 호환 모드와 그에 따른 배포 순서
3. **Lifecycle 상태 기계를 그린다**

   ```
   starting ─▶ recovering ─▶ ready ⇄ degraded ─▶ draining ─▶ stopped
      │ 설정 검증 실패        │ 복구 실패                     │ 예산 초과
      └──────────────▶ exit≠0 ◀┘                              └▶ 남은 것 버리고 exit
   ```

   - starting: Configuration 검증 (실패면 exit), 의존 연결 (백오프 재시도). recovering: Position 복원, 미완료 작업 재생. draining: SIGTERM 이후 Lifecycle 종료 순서. 이 셋은 readiness false, ready 는 true
   - degraded: Sink 장애로 Source 읽기를 멈추고 Position 을 유지한 채 백오프 재시도. Pull 형은 readiness true 유지 가능하고, Accept 형도 공유 의존 (Sink) 장애로 끄지 않고 503 + Retry-After 로 싸게 거절한다

4. **신호와 종료 예산을 정한다**

   - SIGTERM / SIGINT → draining. SIGHUP → Configuration 재적재 (systemd `Type=notify-reload` 일 때만, 처리를 `READY=1` 전에 준비. k8s 는 롤링 재시작이 기본). SIGKILL·OOM·노드 장애 → 처리 불가이므로 Recovery 로 대비

   예산 (k8s): `preStop 시간 + 진행 중 배치 최대 처리 시간 + 확인 응답 + sidecar 종료 + 여유 < terminationGracePeriodSeconds`. **유예 시간 카운트다운은 preStop 전부터 시작하고, SIGTERM 은 preStop 이 끝난 뒤에 온다.** 노드 종료 때는 이보다 짧아질 수 있다. 런타임별 종료 관용구와 메모리 상한은 `references/chassis-lifecycle.md` §4

5. **처리 루프를 짠다** (Pull 형 기본형. Source 별 차이는 `references/io.md`)

   ```
   on SIGTERM:          stopping = true
   on revoke(parts):    drain(inflight[parts], deadline); cancel(inflight[parts]); commitSync(contiguousDone(parts)); forget(parts)
                        # deadline = 종료 중이면 남은 예산, 아니면 max.poll.interval.ms 보다 짧게 (넘기면 fenced)
                        # forget 이후 도착한 완료·markDone 은 버린다 — commit 은 지금 소유한 파티션만
   on lost(parts):      cancel(inflight[parts]); forget(parts)                                            # 이미 잃었으면 커밋 금지
   on assigned(parts):  seekToSinkPosition(parts)                                                         # 트랜잭션 체크포인트일 때만 (Contract)
   # forget(parts): 그 파티션의 tries·backoff·done 상태를 지운다 (새로 할당된 파티션은 pause 없이 시작한다)

   while not stopping:
     if inflight > HIGH:  overloaded = true; pause(assigned)   # Backpressure — 처리를 비동기 워커로 넘길 때의 형태.
     elif inflight < LOW: overloaded = false                   #   동기 처리면 이 분기 대신 max.poll.records 로 조절
     if not overloaded:   resume(paused() - backoff.paused())  # 실제로 멈춘 파티션 중 백오프가 끝난 것만 연다
     batch = poll(timeout)                                     # pause 중에도 poll 을 불러 max.poll.interval 을 넘기지 않는다
     failed = {}
     for msg in batch:                                         # 받은 레코드는 버리지 않는다
       if partition(msg) in failed:                            # 멈춘 파티션의 뒤 레코드는 건너뛴다
         seekOnce(msg); continue                               #   그 파티션에서 처음 건너뛰는 위치로 한 번만 seek → 다시 온다
       try:   sink.writeIdempotent(key(msg), transform(msg)); markDone(msg); tries.remove(pos(msg))
       except Cancelled:                                       # 종료 중 실패: tries·DLQ 를 건드리지 않는다
         failed |= assigned; seekOnce(msg)
       except Retryable as e if not sink.canaryWrite(e):       # SinkDown: 실패한 쓰기와 같은 샤드·테넌트로 canary 쓰기도 실패
         failed |= assigned; seekOnce(msg)                     #   시도 수를 세지 않는다 (판정은 매번 다시 한다)
         backoff.pause(assigned, atLeast=e.retryAfter)          #   전체를 멈추고 백오프 뒤 같은 위치부터
       except Retryable as e if e.overload:                    # 이 키·테넌트만 429·503: 그 파티션만 멈추고 시도 수는 세지 않는다
         failed.add(partition(msg)); seekOnce(msg); backoff.pause(partition(msg), atLeast=e.retryAfter)
       except Retryable if tries.inc(pos(msg)) < MAX:          # Sink 는 건강한데 이 메시지만 실패: 시도 수를 센다 ((partition, offset) 키)
         failed.add(partition(msg)); seekOnce(msg); backoff.pause(partition(msg))
       except Retryable|Poison: dlq.put(msg, error, tries, origin, traceparent); markDone(msg); tries.remove(pos(msg))
       except Fatal:  raise                                    # 프로세스 종료 → 감독자 재시작
     commit(contiguousDone())                                  # 빈틈 없이 끝난 지점까지만
   drain(inflight, deadline); commitSync(contiguousDone()); close()
   # 인자 없는 commitSync() 는 poll 이 돌려준 위치까지 커밋해 못 끝낸 레코드를 잃는다. librdkafka 는 enable.auto.offset.store=false
   ```

   의사코드는 파티션·offset Source (Kafka consumer group) 기준이다. `Retryable` 은 재시도할 만한 오류 (연결 실패·타임아웃·429·503·락 충돌) 다.

   **SinkDown 판정**: 기본은 업계 관행대로 Retryable 을 메시지 탓으로 세지 않고 미루는 것이다 (Vector·Logstash 출력, Kafka Connect `RetriableException`) — 장애 동안 정상 메시지가 DLQ 로 가지 않는다. 다만 이것만으로는 그 메시지만의 Retryable (락 충돌·그 메시지만 타임아웃) 이 파티션을 영원히 막는다. 그래서 세기 전에 **쓰기 경로 확인 (canary 쓰기)** 으로 범위를 가린다 — 실패한 쓰기와 같은 경로·샤드·테넌트·자격 증명의 작은 실제 쓰기다 (샤드×인스턴스마다 heartbeat 행 upsert). canary 도 실패하면 SinkDown 이다. 성공하면 범위가 그 메시지뿐이다: 429·503 은 `Retry-After` 만큼 그 메시지만 미루고 시도 수를 세지 않으며 (키·테넌트별 한도), 그 밖은 Transient 로 세어 N 회 뒤 DLQ 로 보낸다. 부작용 없는 쓰기가 없는 Sink (결제·메일 API) 는 검증·dry-run 호출을 쓰고, 그것도 없으면 기본으로 돌아가 overload 분기처럼 다룬다 (메시지 단위 Source 는 반환하지 않고 연장하며 든다. 머리 정체는 '가장 오래된 미처리 항목 나이' 경보로 잡는다). ping·`SELECT 1` 같은 연결 확인으로는 안 된다 — 과부하·read-only·디스크 가득 참에서는 연결은 살아 있고 쓰기만 실패한다. circuit breaker 처럼 상태로 판정하거나 half-open 확인을 실제 메시지로 하면, 머리의 실패 메시지가 회로를 영영 닫지 못해 소비자 전체가 멈춘다.

   **메시지 단위 Source** (SQS, PG 작업 테이블, RabbitMQ, Kafka share group) 는 같은 분류를 메시지 단위로 적용한다 (상세 `references/io.md` §1).
   - 받은 순간부터 배치 전체의 visibility·lease 연장을 시작하고, 메시지가 끝나면 그 연장만 멈춘다
   - Transient: 그 메시지만 지연 후 반환한다 (SQS `ChangeMessageVisibility`, PG `locked_until` 을 미래로, RabbitMQ 4.3+ 는 `x-delayed-retry-type=failed` 를 켠 뒤 reject, 4.2 이하는 프로세스 안에서 지연한 뒤 반환). 브로커 전달 횟수 (`maxReceiveCount`, PG `attempts`, RabbitMQ `delivery-limit` — 4.3+ 는 `basic.reject` 로 반환해야 오른다) 가 곧 N 이다. share group 은 예외다: 한도에 닿으면 DLQ 가 아니라 폐기되므로 프로세스 안에서 시도 수를 세고 N 회 뒤 DLQ 토픽에 쓴 다음 reject 한다. share group 은 RELEASE 가 지연 없이 재전달되므로 RENEW 하며 프로세스 안에서 백오프한다
   - 429·503 인데 canary 는 성공: 그 메시지만 `Retry-After` 이상 미루되 반환하지 말고 연장하며 들고, 수신은 계속한다. 쥔 메시지가 prefetch·inflight 상한의 절반에 닿으면 그 뒤 것은 지연 반환한다 (안 그러면 상한이 차서 건강한 테넌트까지 멈춘다. 반환은 전달 횟수를 쓰므로 한도를 여유 있게 잡는다)
   - SinkDown: 판정은 위와 같다 (canary 쓰기 실패). `Retry-After` 를 백오프 하한으로 수신을 멈추고 (share group 은 RENEW 가 poll 때 나가므로 poll 은 계속한다), 쥔 메시지는 반환하지 말고 연장하며 들고 있다가 Sink 가 회복되면 이어서 처리한다. 반환하면 다시 받을 때 브로커 전달 횟수가 올라 긴 장애 동안 정상 메시지가 DLQ 로 간다. 연장 상한이 있으면 (SQS 는 최초 수신부터 12h) 그 전에 반환하고, 전달 한도는 장애 중 반환 횟수를 감안해 여유 있게 잡는다
   - Kafka share group 은 `share.acknowledgement.mode=explicit` 로 쓴다 (기본 implicit 은 다음 poll 이 직전 배치를 모두 확정한다)

   tries 는 프로세스 메모리라 리밸런스·재시작에 초기화된다 → 머리 메시지 정체는 '가장 오래된 미처리 항목 나이' 경보로 잡고, 필요하면 시도 수를 외부에 남긴다. librdkafka 는 파티션 resume·seek 버그가 있는 구버전을 피한다 (최소 버전: `references/io.md` §1).

6. **Failure Handling 표를 이 데몬에 맞게 채운다** (어떤 오류가 Transient·Poison·Fatal 인지, Fatal 의 종료 코드)
7. **Overload Protection·Resource Limits 를 정한다**: 원격 호출마다 타임아웃, 재시도를 할 층 하나와 예산, 부하 차단 기준 (Accept 형), 테넌트 격리 단위, 버퍼·동시성·런타임 상한, 프로세스 밖 누적물의 정리 주기
8. **Observability·Admin Processes·Configuration 을 붙인다**: 지표·경보·trace 전파, 관리 포트, DLQ 재투입·replay 명령, 설정 재적재 (Coordination 은 단일 실행이 필요할 때만)
9. **Verification 을 통과시킨다**

## 리뷰 점검 목록

기존 데몬이나 PR 을 리뷰할 때 이 순서로 본다.

1. **Failure Handling**: 처리 콜백의 예외가 어디서 잡히는가 — 잡고 로그만 남긴 뒤 정상 반환하면 유실. RabbitMQ 4.3+ 에서 `nack(requeue=true)` 만 쓰면 독성 메시지가 DLQ 로 가지 않고 무한히 돈다. Sink 전체 장애 (SinkDown) 를 메시지별 실패로 세거나 메시지를 반환해 브로커 전달 횟수를 써서 DLQ 로 보내지 않는가
2. **Contract — 확인 응답 순서**: auto-commit/auto-ack 인가 (auto-commit 이면 offset store 를 수동으로 하는가, Kafka share group 이면 `share.acknowledgement.mode=explicit` 인가), Sink 쓰기 뒤인가. 리밸런스·소유권 상실 시 처리. Backpressure 로 받아 온 batch 를 버리지 않는가
3. **Contract — 멱등 키**: Sink 쓰기가 멱등인가, 멱등 키가 결정적인가, Dedup Window 가 충분한가, 키 계산식이 버전 간에 같은가, 스키마 호환 모드와 배포 순서가 맞는가
4. **Overload Protection**: 모든 원격 호출에 타임아웃이 있는가, 재시도가 여러 층에서 겹치지 않는가, Accept 형이면 부하 차단이 있는가 (실행 모델 함정: 이벤트 루프 블로킹, master-worker 신호, 프록시 idle timeout — `references/io.md` §7)
5. **Lifecycle**: 종료 훅이 실제로 등록되는가 (NestJS `enableShutdownHooks()`, Go `signal.NotifyContext`, Spring Boot 의 graceful 설정과 웹이 아닌 워커의 drain — `references/chassis-lifecycle.md` §4), 예산 안에 끝나는가
6. **Resource Limits**: 큐·배치·동시성 상한 (병렬 단위가 순서 요구와 맞는가, 최대 인스턴스 수 × 인스턴스당 연결 풀이 하류 허용치 안인가, 이벤트 루프를 막는 CPU 작업이 없는가), 외부 엔티티 수에 비례하는 메모리, 프로세스 밖 누적물의 정리 주기
7. **Observability**: liveness 에 외부 의존이 섞였는가, 비활성 기능이 드러나는가, 사라짐 경보가 `up == 0` 도 잡는가
8. **Coordination·Verification**: 락 해제가 원자적인가, TTL < 작업 시간일 때 대책. 크래시 지점 시험이 있는가

사례: `references/case-studies.md` (OpenMeter·Lago 소스, 익명화한 사내 코드).

## 답변 범위

요청한 범위만 답한다. references 는 과제의 Source·런타임에 해당하는 절만 읽는다 (보통 1~2개). 코드를 요청받으면 요청한 부분 (예: 처리 루프·확인 응답·종료) 을 쓰고, 요청하지 않은 Chassis 항목 (경보·관리 포트·배포 매니페스트·검증 시험) 은 구현하지 않고 '운영 전 확인' 몇 줄로 남긴다. 리뷰는 심각도 높은 것부터 쓰고, 문제없는 항목을 나열하지 않는다.

## references

| 파일 | 내용 |
|---|---|
| `references/chassis-lifecycle.md` | Lifecycle·Recovery·Configuration: k8s 종료 순서·프로브·재시작, PID 1, systemd, 런타임별 종료 관용구·메모리 상한, 설정 재적재, 데몬화 15단계 |
| `references/chassis-resources.md` | Resource Limits: 상한, Steady State |
| `references/chassis-overload.md` | Overload Protection: 타임아웃·데드라인, 재시도 예산, 부하 차단, bulkhead·테넌트 격리 |
| `references/chassis-failure.md` | Failure Handling: 독성 입력·DLQ, 감독 전략 (재시작 강도), fallback 대신 failover |
| `references/chassis-observability.md` | Observability·Admin Processes: 지표·경보·로그·trace 전파, 관리 포트, 운영 명령 |
| `references/chassis-coordination.md` | Coordination: 분산 락·원자적 해제·펜싱, 리더 선출, advisory lock |
| `references/io.md` | I/O: 유형별 상세 (큐 소비자·적체 회복, 수집 에이전트, store-and-forward, 폴러, 서버, 병렬·처리량, 서버 실행 모델) |
| `references/contract.md` | Contract: Sink 별 멱등 기법·Dedup Window, 재전송, outbox·inbox, 스키마 진화, durable execution |
| `references/verification.md` | Verification: 시험 표, 결정적 시뮬레이션 |
| `references/case-studies.md` | 실제 코드에서 본 좋은 점·함정 |
