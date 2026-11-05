# 컴포넌트 규약 — CBD 로 서버 조립하기

컴포넌트 목록은 SKILL.md 의 카탈로그에 있다. 여기는 컴포넌트를 나누고 잇는 규칙이다. 목적은 부품 수를 늘리는 것이 아니라 **교체·시험·장애 범위의 경계를 정하는 것** 이다. 컴포넌트 하나마다 장애 지점이 늘 수 있으므로 플랫폼이 주는 것은 만들지 않고, 레이어는 얇게 둔다.

## 1. 형태

컴포넌트가 다 코드는 아니다. 형태에 따라 만드는 방법이 다르다.

| 형태 | 뜻 | 예 |
|---|---|---|
| 코드 | 프로세스 안 부품. 아래 수명 규약을 따른다 | Protocol Handler, Transfer, Storage, Plugin Interface, Backlog |
| 별도 프로세스 | 본체가 죽어도 동작해야 한다 | Emergency Notification, 일회성 Utility 명령 |
| 플랫폼 | 감독자·오케스트레이터 설정으로 끝낸다 | Daemonize, 재시작, 권한, 자원 제한 |
| 정책 | 부품이 아니라 다른 컴포넌트가 지키는 규칙 | Failure Handling, Overload Protection, Resource Limits |

## 2. 수명 규약 (형태가 코드인 것)

```
validate(config)    # 부수 효과 없음. 실패면 시작·재적재를 거절한다
start(ctx)          # 설정·불변식·잠금 실패면 시작을 멈추고 이미 시작한 것을 역순으로 stop
stop(deadline)      # start 가 불리지 않았거나 실패했어도 안전해야 한다
prepare(config)     # 재적재를 지원할 때만. 새 상태를 만들되 아직 쓰지 않는다. 실패해도 된다
commit()            # 준비한 상태로 원자 교체. 실패할 수 없어야 한다
abort()             # 다른 컴포넌트의 prepare 가 실패하면 준비분을 버린다
health()            # 그 컴포넌트의 상태. 합쳐서 readiness·지표가 된다
```

같은 모양의 선례: OTel Collector `Start`·`Shutdown` (Shutdown 은 Start 없이 불려도 안전, [component.go](https://raw.githubusercontent.com/open-telemetry/opentelemetry-collector/main/component/component.go)), Caddy `Provision`·`Validate`·`Cleanup` ([extending](https://caddyserver.com/docs/extending-caddy)). 런타임에 수명 관리자가 있으면 그것을 쓴다 (Spring `SmartLifecycle`, NestJS 훅, Go `oklog/run`) — `chassis-lifecycle.md` §4.

연결 실패는 start 실패가 아니다. 의존 서비스는 백오프로 재시도하고 그동안 `health()` 로 드러낸다 (의존 장애로 exit 하면 재시작 폭주다). `prepare`·`commit` 이 없으면 재시작이 필요한 설정이고, `commit` 이 실패할 수 있는 일 (포트 재바인드 등) 도 재시작 항목이다.

## 3. 시작·종료 순서

**시작은 하류부터, 종료는 상류부터.** Sink 쪽 `start` 가 끝난 뒤에 입력을 연다. Sink 가 아직 연결 전이면 입력은 degraded 로 멈춰 있는다. 멈출 때는 입력을 먼저 닫아 뒤 컴포넌트가 비울 기회를 준다 ([OTel graph.go](https://raw.githubusercontent.com/open-telemetry/opentelemetry-collector/main/service/internal/graph/graph.go)).

```
main(args):
  config = load(args); validateAll(config)           # 실패면 exit 78
  stateLock = lockStateDir(config)                   # 로컬 상태가 있을 때만. 못 잡으면 exit≠0
  controlSocket.start()                              # 잠금 직후. 연결 대기 중에도 Utility 위임을 받는다 (chassis-operations.md §2)
  chain = [backlog, observability,                   # 공통 부품 먼저
           storage or transfer,                      # Sink 쪽
           taskHandler, plugins,                     # 처리
           input or protocolHandler]                 # 입력은 마지막
  for c in chain: c.start(ctx)                       # 실패면 시작한 것을 역순 stop 후 exit≠0
  waitSignal()                                       # SIGTERM → draining
  for c in reversed(chain): c.stop(remainingBudget)  # 입력부터 닫고 Backlog 는 마지막
```

## 4. 의존 방향과 교체

- 코어는 Port (인터페이스) 만 안다: Source, Processor, Sink, Notifier. 구현체는 조립 지점 한 곳에서 고른다
- 컴포넌트끼리 직접 부르지 않고 조립 지점이 잇는다. 공통 부품 (Backlog, 지표) 만 어디서나 의존해도 된다
- 상속보다 인터페이스와 합성을 쓴다. 공통 코드가 필요하면 기반 클래스가 아니라 도우미 함수로 준다
- 인터페이스는 구현체가 둘 이상이거나 시험에서 바꿔야 할 때 둔다. 구현체가 하나뿐인 층은 만들지 않는다

**Storage** 는 Sink 를 Port 로 둔 것이다. 매체를 바꿔도 코어가 안 바뀌게 하되, 멱등 수단·트랜잭션·Dedup Window 는 매체마다 달라 감출 수 없다 → Port 에 "이 구현이 주는 보장" 을 드러낸다 (`contract.md` §1). 공통 분모만 남긴 추상화가 멱등을 잃게 만들면 안 된다.

**Task Handler** 는 입력과 처리를 잇는 실행 단위다 (`io.md` §6·§7). 수신과 저장의 속도가 다르면 상한 있는 내부 큐로 단계를 나눈다. 이 단계 경계에서 프로세스를 나눌 수 있지만, 부하가 실제로 요구할 때만 나눈다 (Contract 구간이 하나 늘어난다).

## 5. 설정

컴포넌트마다 설정 섹션을 둔다. 공통 기본값 위에 섹션별로 덮어쓴다. `validate` 는 컴포넌트가 자기 섹션을 검사한다. 재적재 가능 여부도 항목별로 정한다 (`chassis-operations.md` §1).

```yaml
transfer: { endpoint: …, compression: zstd, tls: { … } }
plugins:
  - name: parser-a
    transfer: { compression: none }   # 플러그인별 덮어쓰기
notify: { route: … }
```

## 6. 디렉토리

| 용도 | 위치 | systemd |
|---|---|---|
| 설정 | `/etc/<app>` | `ConfigurationDirectory=` |
| 잃으면 안 되는 상태 (버퍼, 체크포인트, 격리 폴더) + 상태 잠금 파일 | `/var/lib/<app>` | `StateDirectory=` |
| 제어 socket | `/run/<app>` (정지 시 삭제) | `RuntimeDirectory=` |
| 로그 | stdout. 파일이면 `/var/log/<app>` | `LogsDirectory=` |

k8s 에서 상태 디렉토리는 PV 가 있어야 재시작 뒤 남는다. 소스는 `cmd/` (CLI 진입점), 코어, 공통 부품, 구현체 (`plugins/`·`transfers/`·`storages/`) 로 나눈다. 언어 관례가 있으면 따른다 ([systemd.exec](https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html)).

## 7. 적용표

새 서버는 코드를 쓰기 전에 카탈로그의 모든 행을 판정한다. 판정이 불필요면 이유를 한 줄 적는다. 예 (호스트 수집 에이전트 + k8s 수집 서버):

| 컴포넌트 | 에이전트 (systemd) | 수집 서버 (k8s) | 상태 |
|---|---|---|---|
| Daemonize | 위임: unit | 위임: Deployment | v1 |
| Live Config | 직접: SIGHUP + 롤백 | 위임: 롤링 재시작 | v1 |
| CLI Component | 직접 | 직접 (`check-config`, `status`) | v1 |
| Utility | 직접: `recover` | 직접: `dlq requeue` | v1 |
| Backlog | stdout → journald | stdout | v1 |
| Emergency Notification | 위임: `OnFailure=` + heartbeat | 위임: Alertmanager | v1 |
| Recovery | 직접: 상시 디스크 버퍼 | 요청 단위라 Position 없음. 불필요 (세션 재개가 있으면 직접) | v1 |
| GC | 위임: `MemoryHigh=` + 확정분 정리 | 위임: limit + DLQ TTL | v1 |
| Plugin Interface | 직접: 컴파일 시 등록 | 불필요: 파서가 하나 | v2 |
| Protocol Handler | 불필요: 파일 입력 | 직접 | v1 |
| Transfer | 직접: 응용 ack + mTLS | 불필요 | v1 |
| Storage | 불필요 | 직접 | v1 |

상태 열은 이번 버전과 다음 버전을 나눈다. 구현을 미룬 컴포넌트는 그동안의 위험을 같은 표에 적는다.
