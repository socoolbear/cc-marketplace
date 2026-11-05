---
name: server-chassis
description: 서버 프로세스 (XMPP·SNMP·WebSocket·MQTT·자체 TCP 같은 프로토콜 서버, 양방향·단방향 통신 서버, 수집 서버·수집 에이전트, 큐·스트림 소비자, 백그라운드 워커, 폴러·스케줄러) 를 새로 구축·리뷰할 때 CBD (컴포넌트 기반 개발) 로 조립하는 서버 프로그래밍 기법. Daemonize·Live Config·CLI Component·Utility·Backlog·Emergency Notification·Recovery·GC·Plugin Interface·Protocol Handler·Transfer·Storage 를 직접 구현 / 플랫폼 위임 / 불필요로 판정하고, Contract (전달 보장·확인 응답 순서·멱등 키·재전송) 로 구간을 잇는다. "프로토콜 서버 구현", "소켓 서버", "양방향 통신 서버", "푸시 서버", "trap 수신 서버", "플러그인 구조 서버", "데몬 만들어줘", "워커 구현", "컨슈머 구현", "에이전트 구현", "graceful shutdown", "SIGTERM 처리", "재시작 없이 설정 변경", "프로세스 죽으면 알림", "오프셋 커밋", "at-least-once", "중복 처리 방지", "재시작하면 데이터가 빠져", "크론 중복 실행 방지", "tail 구현", "역압", "DLQ", "재시도 폭주", "부하 차단", "큐 적체", "서버 실행 모델" 같은 요청이면 반드시 이 스킬을 사용할 것. 일반 HTTP 프레임워크 위에 API 엔드포인트·CRUD·업무 로직을 만드는 일, 일회성 배치·독립 CLI 도구, 쿼리·알고리즘 튜닝, 이미 만든 프로세스를 launchd·systemd 에 등록하는 운영 요청은 대상이 아니다.
---

# server-chassis — 서버를 컴포넌트로 조립하기

**서버**는 오래 떠서 바깥 입력을 받아 처리하고 바깥 상태를 바꾸는 프로세스 (데몬) 다. 프로토콜 서버, 수집 에이전트 (client), 큐 소비자, 폴러가 모두 서버다. 서버를 컴포넌트로 조립해 (CBD) **정합성** (언제 죽어도 데이터가 빠지거나 틀어지지 않는다), **가시성** (죽거나 멈추면 바깥이 알아챈다), **자기 회복** (다시 켜면 알아서 이어 간다) 을 갖추게 한다.

> 플랫폼이 주는 것은 만들지 않는다. 컴포넌트는 교체·시험·장애 범위의 경계다. 여러 단계에 걸쳐 부수효과를 내고 오래 기다리는 작업이면 먼저 **durable execution 엔진** (Temporal 등) 을 본다 → `references/contract.md` §6.

## 모델: 서버 = Chassis + I/O + Contract

```
┌───────────────────── Chassis (모든 서버 공통 컴포넌트) ─────────────────────┐
│ Daemonize · Live Config · CLI Component · Utility · Backlog · Observability │
│ Emergency Notification · Recovery · GC · Resource Limits                    │
│ Overload Protection · Failure Handling · (Coordination)                     │
└─────────────────────────────────────────────────────────────────────────────┘
          ┌───────────────── I/O (역할별 컴포넌트) ───────────────────┐
 Source ──▶│ Input (Protocol Handler) → Processing (Plugin Interface)  │──▶ Sink
          │  → Output (Transfer / Storage), 실행은 Task Handler        │
          └───────────────────────────────────────────────────────────┘
   ▲ Contract                                                  Contract ▲
   └─ 전달 보장 · 확인 응답 순서 · 멱등 키 · 재전송 · 스키마 진화 (구간마다) ─┘
```

**Chassis** 는 역할과 무관한 공통 골격, **I/O** 는 역할별 부분 (client 와 server 를 가르는 축은 **입력 방향 하나**: Pull / Accept), **Contract** (구간 계약) 는 구간 사이의 전달 약속이다. 앞 서버의 Sink 가 곧 다음 서버의 Source 다.

## 컴포넌트 카탈로그

새 서버는 코드를 쓰기 전에 모든 행을 **직접 구현 / 플랫폼 위임 / 불필요** 중 하나로 판정하고 행마다 이유를 쓴다 (적용표·수명 규약·조립 순서: `references/components.md`). 형태 열 (코드 / 프로세스 / 플랫폼 / 정책) 은 판정이 아니다. 정책 행도 셋 중 하나로 판정한다. 상세 열의 파일에 `핵심 규칙` 절이 있으면 § 보다 먼저 읽는다.

| 컴포넌트 | 책임 | 지금 기본값 | 형태 | 상세 |
|---|---|---|---|---|
| Daemonize (Lifecycle) | 시작·종료·신호 | 포그라운드 + 감독자. fork 하지 않는다 | 플랫폼 | `chassis-lifecycle.md` §1~§4·§6 |
| Live Config (Configuration) | 설정 검증·반영 | k8s 는 롤링 재시작, 호스트는 SIGHUP + 실패 시 옛 설정 유지 | 코드·플랫폼 | `chassis-operations.md` §1 |
| CLI Component | 명령 표면 | 같은 바이너리 하위 명령 + 제어 socket | 코드 | `chassis-operations.md` §2 |
| Utility | 상태 체크·수동 복구·재투입 | 같은 빌드·같은 설정의 일회성 명령 | 프로세스 | `chassis-operations.md` §3 |
| Backlog | 서버 자신의 로그 | stdout 구조화 로그 | 코드 | `chassis-observability.md` §3 |
| Observability | 지표·프로브·trace | 관리 포트 (읽기 전용) | 코드 | `chassis-observability.md` §1·§4·§5 |
| Emergency Notification | KILL·HANG·PANIC 즉시 알림 | 감독자·경보 시스템 + 외부 heartbeat | 프로세스 | `chassis-observability.md` §2 |
| Recovery | 재시작 뒤 이어 가기 | crash-only + 상시 디스크 버퍼 | 코드 | `chassis-lifecycle.md` §7 |
| GC | 쌓인 것 회수 | 안: 상한 + 누수 수정. 밖: Steady State | 정책 | `chassis-resources.md` §2·§3 |
| Resource Limits | 상한 | 모든 버퍼·큐·동시성에 상한 | 정책 | `chassis-resources.md` §1 |
| Overload Protection | 연쇄 장애 차단 | 타임아웃·재시도 예산·부하 차단 | 정책 | `chassis-overload.md` |
| Failure Handling | 실패 분류 | Transient·SinkDown·Poison·Fatal | 정책 | `chassis-failure.md` |
| Coordination | 단일 실행 | 필요할 때만. 펜싱·멱등 | 코드 | `chassis-coordination.md` |
| Input | 입력 받기 | tail·consume·poll·listen | 코드 | `io.md` §1~§5 |
| Protocol Handler | 프레이밍·코덱·연결·세션 | 표준이면 검증된 라이브러리. HTTP 프레임워크면 불필요 | 코드 | `protocol.md` |
| Plugin Interface | 처리 확장점 | 구현체가 둘 이상일 때만. 컴파일 시 등록 | 코드 | `plugin-interface.md` |
| Task Handler | 실행 단위·병렬 | 런타임이 정한다. 단계 사이 상한 있는 큐 | 코드 | `io.md` §6·§7 |
| Transfer | 다른 서버로 전송 (Send 구현) | 응용 계층 ack + TLS | 코드 | `transfer.md`, `components.md` §8 |
| Storage | 저장 (Store 구현) | Port 뒤의 멱등 쓰기 | 코드 | `contract.md`, `components.md` §4·§8 |

## 용어 (이 스킬 안에서 고정)

| 용어 | 뜻 |
|---|---|
| 감독자 (supervisor) | 프로세스를 띄우고 죽으면 다시 띄우는 바깥 주체 (kubelet, systemd) |
| Source / Sink | 서버가 읽는 곳 (Kafka 토픽, SQS 큐, PG 작업 테이블, 파일, 타이머, 들어오는 연결) / 쓰는 곳 (DB, 객체 저장소, 외부 API, 다른 데몬) |
| Position | Source 에서 어디까지 처리했는지 (offset, receipt handle, 행 상태, fingerprint+offset) |
| 확인 응답 (ack) | Source 에 "여기까지 처리했다" 고 알리는 것 (offset commit, ack, delete, 행 상태 변경) |
| 멱등 키 (idempotency key) | 같은 입력이면 항상 같은 값이 나오는 키. Sink 가 이 키로 중복을 거른다 |
| Dedup Window | Sink·브로커가 멱등 키를 기억하는 기간. Sink 별 값 (일반 MergeTree 는 0, PG UNIQUE 는 정리 TTL 이 곧 창) 은 `references/contract.md` §1 |
| Backpressure | 하류가 느릴 때 상류를 늦추는 것 |
| DLQ | 처리할 수 없는 항목을 따로 모아 두는 재처리 대기열 |
| Backlog | 서버 자신이 남기는 로그. 큐에 밀린 일은 **적체**, 소켓 대기열은 **accept backlog** 라 부른다 |
| Send / Store | Output 방식. Send 를 구현하는 컴포넌트가 Transfer, Store 를 구현하는 컴포넌트가 Storage |
| Port | 코어가 아는 인터페이스 (Source, Processor, Sink, Notifier) |

## 어기면 사고가 나는 규칙

Chassis 컴포넌트의 규칙은 각 reference 맨 앞의 `핵심 규칙` 에, 나머지는 해당 reference 에 있다. 아래는 판정과 무관하게 지킨다. 이 규칙이든 reference 의 규칙이든 어기면 그 이유를 코드 주석이나 설계 메모에 남긴다.

1. **수명은 감독자에게.** 포그라운드로 뜨고 fork·PID 파일·자체 재시작 루프를 두지 않는다. 시작 오류 중 설정·불변식·필수 플러그인·Position 손상·상태 잠금 실패만 exit ≠ 0 이고, 연결 실패는 백오프 재시도 + degraded 다
2. **시작 = 복구.** 정상 종료와 `kill -9` 가 같은 결과가 되게 하고, 잃으면 안 되는 상태는 프로세스 밖이나 상시 경로의 디스크 버퍼에 둔다
3. **모든 버퍼·큐·동시성에 상한.** 가득 찼을 때의 정책 (block / drop) 을 명시한다
4. **모든 원격 호출에 타임아웃, 재시도는 한 층에서만.** 재시도에는 예산을 둔다
5. **실패를 삼키지 않는다.** `catch` 해서 로그만 찍고 정상 반환하면 확인 응답이 나가 조용히 유실된다. 실패는 Transient·SinkDown·Poison·Fatal·종료 중 실패로 분류한다. Sink 전체 장애를 메시지 탓으로 세어 DLQ 로 보내지 않는다 (판정은 ping 이 아니라 실제 쓰기 경로 확인)
6. **건강과 경보는 바깥에서.** liveness 에 의존 서비스 장애를 넣지 않는다. 죽은 프로세스는 자기 죽음을 알리지 못하므로 경보는 본체와 별개인 주체가 낸다
7. **설정 변경은 전부 성공 아니면 무변경.** 검증 후 원자 교체하고, 실패하면 옛 설정으로 계속 돈다
8. **쌓이는 것은 치운다.** 프로세스 밖 누적물 (DLQ, 멱등 테이블, 디스크 버퍼) 에 정리 주기를 두고, 정리 TTL 은 Dedup Window 요구보다 길게 한다

## I/O — 역할별

Pull 과 Accept 를 가르는 기준은 누가 연결을 여느냐가 아니라 **누가 처리 속도를 정하고 Position 을 갖느냐** 다. RabbitMQ consume 은 브로커가 밀어 주지만 서버가 prefetch 로 속도를 정하므로 Pull 이다.

| 입력 방향 | 뜻 | Position | Backpressure | 종료 시 |
|---|---|---|---|---|
| **Pull** (client형) | 서버가 Source 에서 직접 가져온다 (consume, tail, poll, 타이머) | 데몬·Source 가 관리 | 읽기를 멈춘다 | 읽기 중단 |
| **Accept** (server형) | 들어오는 연결·요청을 받는다 (listen, HTTP·gRPC·TCP) | 없음 (세션 재개가 있으면 `references/protocol.md` §8) | 부하 차단, 연결·크기·시간 상한 | 새 연결을 받지 않고 기존 연결을 기한 내 마무리 |

| 유형 | Input | Source | Output | 대표 위험 | 상세 |
|---|---|---|---|---|---|
| 큐·스트림 소비자 | Pull | Kafka·SQS·RabbitMQ·PG 큐 | Store / Send | 처리 전 커밋, 리밸런스 중복, 독성 메시지, 적체 | `references/io.md` §1 |
| 수집 에이전트 (파일 tailer) | Pull | 로컬 파일 | Send | 로테이트 누락, inode 재사용, Backpressure 중 유실 | `io.md` §2 |
| store-and-forward | Pull | 내부 생성 데이터 → 디스크 버퍼 | Send | 버퍼 가득, fsync 간격만큼 유실 | `io.md` §3 |
| 폴러·스케줄러 | Pull | 타이머 | Store / Send | 중복 실행, 놓친 회차, 겹친 실행 | `io.md` §4 |
| 수집 서버 | Accept | 연결·요청 | Store (+ 응답) | 엔드포인트 제거 경쟁, 과부하 | `io.md` §5·§7 |
| 프로토콜 서버 (양방향·단방향) | Accept | 연결·데이터그램 | Send / Store | 부분 수신, 느린 수신자, 끊김 미감지, 재접속 폭주, 장기 연결 drain | `references/protocol.md`, `io.md` §5·§7 |

처리·출력 규칙은 `references/components.md` §8.

## Contract — 구간과 구간 사이

서버 하나는 `Source → 서버`, `서버 → Sink` 두 구간에 걸친다. 서버가 이어지면 모든 구간에 같은 계약이 적용된다. 상세와 Sink 별 멱등 방식은 `references/contract.md`.

1. **전달 보장**: 기본은 at-least-once + 멱등 Sink. 중복은 반드시 온다
2. **확인 응답 순서**: `읽기 → 처리 → Sink 쓰기 확정 → 확인 응답`. auto-commit·auto-ack 금지 (예외는 `references/contract.md` 핵심 규칙). 병렬 처리하면 빈틈 없이 끝난 지점까지만 확인 응답한다
3. **멱등 키**: Source 에서 결정적으로 만든다 (`now()`·쓰기 시점 UUID 금지). Dedup Window > 최대 재처리 지연
4. **재전송**: 상한 있는 버퍼 + 백오프. 받는 쪽의 "저장 확정" 응답 뒤에만 Position 을 넘긴다
5. **스키마 진화**: 메시지에 버전을 싣고, 호환되지 않는 버전은 Poison 으로 다룬다. 구버전과 신버전은 배포 중 공존한다

## 설계·구현 절차

새 서버를 만들거나 기존 서버를 고칠 때 이 순서로 정하고, 정한 내용을 설계 메모 (PR 본문 또는 README) 에 남긴다.

**형태 제안 (구현 전)**: 2단계의 형태 (Input 방향·유형, 실행 모델 (`references/io.md` §7), 병렬 단위·순서 요구, 런타임) 를 요청과 기존 코드로 정할 수 없고, 답에 따라 구조가 크게 달라지면 코드를 쓰기 전에 사용자에게 제안하고 확인받는다. 후보 2~3개에 trade-off 와 추천안을 붙인다. 런타임이 없는 새 프로젝트면 런타임 후보도 함께 낸다 (런타임이 실행 모델을 정한다). 정해지면 묻지 않고 설계 메모에만 남긴다.

1. **컴포넌트 적용표를 만든다**: 카탈로그의 모든 행을 판정하고 이유와 상태 (이번 버전 / 다음 버전) 를 적는다 (`references/components.md` §7)
2. **I/O 를 정한다**: Input 방향, 통신 형태와 프로토콜, Source, Output, Sink, 실행 환경 (Kubernetes 기본 / systemd / 둘 다), 병렬 단위·동시성 (`references/io.md` §6). 유형표에서 해당 행의 상세를 읽는다
3. **Contract 를 구간마다 정한다**: 전달 보장, 멱등 방식, Dedup Window 와 최대 재처리 지연 비교, 스키마 호환 규칙과 배포 순서
4. **Lifecycle 상태 기계를 그린다**: `starting → recovering → ready ⇄ degraded → draining → stopped`. 신호와 종료 예산도 정한다 (`references/chassis-lifecycle.md` 핵심 규칙)
5. **처리 루프를 짠다**: 유형표의 상세를 따른다. 큐·스트림 소비자의 기본형은 `references/io.md` §1
6. **Failure Handling 표를 이 서버에 맞게 채운다**: 어떤 오류가 어떤 분류인지, Fatal 의 종료 코드 (`references/chassis-failure.md`). 여러 서버가 이어지면 위치별 장애 대응표를 만든다 (§4)
7. **Overload Protection·Resource Limits·GC 를 정한다**: 타임아웃, 재시도 층과 예산, 부하 차단 기준, 테넌트 격리, 상한, 정리 주기
8. **운영 컴포넌트를 붙인다**: Backlog, 지표·trace, Emergency Notification, 관리 포트, 제어 socket, CLI·Utility, Live Config
9. **Verification 을 통과시킨다**: `references/verification.md` 의 최소 기준. 증명하기 전엔 완료가 아니다

## 답변 범위

요청한 범위만 답한다.

- **새 서버 전체를 설계·구현**: 컴포넌트 적용표를 먼저 낸다. 카탈로그의 행을 하나도 빼지 않고 행마다 판정과 이유를 한 줄로 쓴다 (프로세스가 둘 이상이면 프로세스별로). 구현은 표에서 고른 것만 한다. 코드를 쓰기 전에 불필요가 아닌 행의 `핵심 규칙` (또는 해당 reference) 과 `references/contract.md` 핵심 규칙을 읽는다
- **일부만 요청** (예: 처리 루프·확인 응답·종료): 코드를 쓰기 전에 요청한 컴포넌트와 Source·런타임에 해당하는 reference 의 `핵심 규칙` 과 해당 절을 읽고 그 부분을 쓴다. 요청하지 않은 컴포넌트 (경보·관리 포트·배포 매니페스트·검증 시험) 는 구현하지 않고 '운영 전 확인' 몇 줄로 남긴다
- **리뷰**: `references/review-checklist.md` 의 순서로 보고, 대상의 Source·런타임·컴포넌트 reference 의 `핵심 규칙` 과 해당 절도 읽는다. 심각도 높은 것부터 쓰고, 문제없는 항목을 나열하지 않는다

## references

컴포넌트별 상세는 카탈로그의 상세 열 (모두 `references/` 아래). 그 밖에 `components.md` (컴포넌트 규약), `contract.md` (Sink 별 멱등·재전송·outbox·스키마 진화), `verification.md` (시험 표), `review-checklist.md` (리뷰 순서), `case-studies.md` (사례, 옛 방식).
