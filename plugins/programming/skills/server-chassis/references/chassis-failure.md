# Chassis — Failure Handling

분류 (Transient / SinkDown / Poison / Fatal / 종료 중 실패) 와 기본 동작은 아래 핵심 규칙에 있다. 그 뒤는 상세다.

## 핵심 규칙

| 분류 | 예 | 동작 | Position |
|---|---|---|---|
| Transient (일시) | Sink 는 건강한데 그 항목만 실패 (락 충돌·특정 항목 타임아웃) | 재시도 예산 안에서 지수 백오프+지터 재시도 (한 층에서만), N 회 뒤 Poison | 유지 |
| Sink 전체 장애 (SinkDown) | 재시도할 만한 오류 (연결 실패·타임아웃·429·502·503·504) 가 났고 쓰기 경로 확인 (canary 쓰기) 도 실패 | 수신을 멈추고 백오프 (degraded, 429·503 은 `Retry-After` 를 하한으로). 메시지별 시도 수도 브로커 전달 횟수도 쓰지 않는다 (연장 상한까지) | 유지 |
| Poison (독성) | 역직렬화 실패, 스키마 위반, 호환되지 않는 메시지 버전, N 회 재시도 실패 | 원본·에러·시도 수·Source Position·`traceparent` 와 함께 DLQ, 다음 항목 진행 | 전진 |
| Fatal (복구 불가) | 설정 오류, 불변식 위반, uncaught exception | exit ≠ 0 → 감독자 재시작 (종료 코드별 재시작 제외는 systemd 만. k8s Deployment 는 재시작 반복 경보로 잡는다 — `chassis-failure.md` §2) | 유지 (재시작 후 재처리) |
| 종료 중 실패 | 종료 (context 취소) 로 생긴 실패 | 시도 수·DLQ 를 건드리지 않고 NACK·미커밋 | 유지 |

- `catch` 해서 로그만 찍고 정상 반환하면 확인 응답이 나가 **조용히 유실**된다. DLQ 를 못 두는 환경이면 "알림 후 포기" 를 명시하고 그 손실을 감수하는 이유를 적는다. 평소에 타지 않는 fallback 경로를 새로 만들지 않는다. 호출자 재시도, 미리 밀어 둔 데이터, 상시 가동 failover 를 쓴다. degraded 상태 (Source pause + Position 유지 + 백오프) 는 이 원칙에 맞는다

**SinkDown 판정**: Retryable 은 연결 실패·타임아웃·429·502·503·504·락 충돌이다. 기본은 업계 관행대로 Retryable 을 메시지 탓으로 세지 않고 미루는 것이다 (Vector·Logstash 출력, Kafka Connect `RetriableException`) — 장애 동안 정상 메시지가 DLQ 로 가지 않는다. 다만 이것만으로는 그 메시지만의 Retryable (락 충돌·그 메시지만 타임아웃) 이 파티션을 영원히 막는다. 그래서 세기 전에 **쓰기 경로 확인 (canary 쓰기)** 으로 범위를 가린다 — 실패한 쓰기와 같은 경로·샤드·테넌트·자격 증명의 작은 실제 쓰기다 (샤드×인스턴스마다 heartbeat 행 upsert). canary 도 실패하면 SinkDown 이다. 성공하면 범위가 그 메시지뿐이다: 429·503 은 `Retry-After` 만큼 그 메시지만 미루고 시도 수를 세지 않으며 (키·테넌트별 한도), 그 밖은 Transient 로 세어 N 회 뒤 DLQ 로 보낸다. 부작용 없는 쓰기가 없는 Sink (결제·메일 API) 는 검증·dry-run 호출을 쓰고, 그것도 없으면 기본으로 돌아가 `io.md` §1 처리 루프의 `e.overload` 분기처럼 다룬다 (메시지 단위 Source 는 반환하지 않고 연장하며 든다. 머리 정체는 '가장 오래된 미처리 항목 나이' 경보로 잡는다). ping·`SELECT 1` 같은 연결 확인으로는 안 된다 — 과부하·read-only·디스크 가득 참에서는 연결은 살아 있고 쓰기만 실패한다. circuit breaker 처럼 상태로 판정하거나 half-open 확인을 실제 메시지로 하면, 머리의 실패 메시지가 회로를 영영 닫지 못해 소비자 전체가 멈춘다.

## 1. 독성 입력과 DLQ

- 재시도 토픽 (지연 단계별, Source 파티션을 막지 않음, 순서 포기) vs 제자리 재시도 (순서 유지, 파티션이 막힘) 중 하나를 고른다
- DLQ 헤더: 에러, 시도 수, Source topic/partition/offset, 최초 실패 시각, `traceparent` (OTel trace context, `chassis-observability.md` §4), 원본 bytes
- 종료 (context 취소) 로 생긴 실패는 메시지 탓이 아니다. DLQ 로 보내지 말고 NACK·미커밋
- 재시도 가능한 오류 (연결 실패·타임아웃·429·502·503·504·락 충돌) 는 위 SinkDown 판정을 먼저 거친다. SinkDown 이면 메시지별 시도 수·브로커 전달 횟수를 쓰지 않는다 (`io.md` §1 SinkDown 절). canary 쓰기가 성공하면 범위가 그 메시지뿐이다 — 429·503 은 `Retry-After` 만큼 미루되 시도 수를 세지 않고, 그 밖만 Transient 로 세어 N 회 뒤 DLQ 로 보낸다
- DLQ 는 버리는 곳이 아니라 재처리 대기열이다. 재투입 명령은 Utility (`chassis-operations.md` §3)
- 브로커별 재전달 조건·DLQ 지원은 `io.md` §1 브로커 비교. RabbitMQ 에서 독성 감지는 reject/requeue=false 가 필요하다 (`io.md` §1)
- 호환 불가능한 스키마 버전은 Poison 으로 분류한다 (`contract.md` §5)

## 2. 감독 전략 (재시작 강도)

Erlang/OTP supervisor: `one_for_one` / `one_for_all` / `rest_for_one`, **MaxT 초 안에 MaxR 회 넘게 재시작하면 포기하고 상위에 넘긴다** ([OTP](https://www.erlang.org/doc/system/sup_princ.html)). 같은 원인으로 무한히 죽는 것을 막는 장치다.

- 프로세스 안: errgroup 은 `one_for_all`. 하위 구성 요소 하나만 재시작하고 싶으면 그 구성 요소에 백오프 재시작 루프를 두되 **횟수 상한을 넘으면 프로세스를 죽여** 감독자에게 넘긴다
- 프로세스 밖: systemd `StartLimitBurst` (첫 시작부터 Burst+1 번째 시작까지 걸린 시간이 창 이하일 때 포기 — 아래), k8s CrashLoopBackOff (포기 안 함 → 경보 필요)

기본값과 세부:

- OTP: intensity 1, period 5 (5초 안에 1회 넘게 재시작하면 포기)
- systemd: `DefaultStartLimitIntervalSec=10s`, `DefaultStartLimitBurst=5`. 수동 시작도 횟수에 든다. 기본 `RestartSec=100ms` 면 5회/10초 한도에 0.5초 만에 포기한다. 포기 조건은 첫 시작부터 (`StartLimitBurst`+1) 번째 시작까지 걸린 시간 (재시작 간격 합 + 각 실행 시간 합) 이 `StartLimitIntervalSec` 이하일 때다 (ratelimit.c: 경과 > interval 이면 창 초기화). 그래서 `RestartSec` 를 2s 이상으로 고정하면 실행 시간이 조금만 있어도 기본 한도 (5회/10초) 에 걸리지 않아 영원히 재시작하므로 재시작 반복 경보가 필요하다. `RestartSteps` 는 앞 단계 간격이 짧아 (`RestartSec` 부터 지수 증가) 기본 한도에 그대로 걸릴 수 있다. 의도 (포기 / 무한 재시작) 에 맞게 `StartLimitIntervalSec` 를 Burst+1 번째 시작까지 걸리는 시간과 비교해 정한다 ([service.c](https://raw.githubusercontent.com/systemd/systemd/main/src/core/service.c), [ratelimit.c](https://raw.githubusercontent.com/systemd/systemd/main/src/basic/ratelimit.c)). 지수 백오프는 `RestartSteps=`·`RestartMaxDelaySec=` (v254)
- k8s: CrashLoopBackOff 는 포기하지 않지만 상한은 1.35 부터 노드별로 설정할 수 있다. `restartPolicyRules` (1.35 Beta) 는 특정 종료 코드에서만 재시작시키는 규칙이다 (exitCodes 연산자는 `In`·`NotIn`, action 은 `Restart` 와 `RestartAllContainers` (v1.36 Beta), 컨테이너 `restartPolicy` 와 함께 지정). 이 규칙은 Job·단발 Pod 용이다. 컨테이너 `restartPolicy: Never` + `restartPolicyRules: [{action: Restart, exitCodes: {operator: NotIn, values: [78]}}]` 를 Deployment 에 쓰면 단일 컨테이너 파드는 Failed 가 되고 ReplicaSet 이 Failed 파드를 active 로 세지 않아 백오프 없이 새 파드를 계속 만든다 (Failed 파드 누적). 다중 컨테이너 파드는 NotReady 로 남아 교체되지 않는다 ([validation.go](https://raw.githubusercontent.com/kubernetes/kubernetes/master/pkg/apis/core/validation/validation.go), [pod-lifecycle](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/), [getPhase](https://github.com/kubernetes/kubernetes/blob/master/pkg/kubelet/kubelet_pods.go), [IsPodActive](https://github.com/kubernetes/kubernetes/blob/master/pkg/controller/controller_utils.go)). 그래서 Deployment 데몬은 재시작 + 재시작 반복 경보가 기본이다. 종료 코드별 재시작 제외는 systemd 는 `RestartPreventExitStatus=` (`chassis-lifecycle.md`)

## 3. fallback 대신 failover

드물게만 타는 fallback 경로는 만들지 않는다. 시험이 안 된 경로는 장애 때 처음 실행되고 그때 깨진다. 대안:

- 호출자 재시도
- 미리 밀어 둔 데이터 (pre-pushed)
- 항상 켜 둔 (active-active) failover

graceful degradation (부하 때 요청당 일을 줄이기) 은 정기적으로 시험할 때만 둔다. 데몬의 저하 상태 (Source 를 멈추고 Position 유지, 백오프) 는 이 원칙과 맞는다. 장애 때만 쓰는 로컬 백업이 아니라 상시 경로의 디스크 버퍼를 쓰는 것도 같은 이유다 (`chassis-lifecycle.md` §7). 출처: [Avoiding fallback](https://builder.aws.com/content/3EuS9Sakq7L3VLQIF3qzfMfke1Y/avoiding-fallback-in-distributed-systems), [Cascading failures](https://sre.google/sre-book/addressing-cascading-failures/)

## 4. 장애 대응표

여러 데몬이 이어진 시스템이면 위 오류 분류와 별개로 시스템 수준 표를 만든다. 위치별로 사고를 나열하고 대처와 시험을 잇는다. 대처가 사람의 손이면 Utility 명령과 절차까지 적는다. 표가 길어지면 장애 지점이 많다는 신호이니 구조를 줄인다.

| 위치 | 이슈 | 영향 | 대처 | 시험 |
|---|---|---|---|---|
| 에이전트 | 프로세스 사망 | 수집 공백 | 감독자 재시작 + Position 복원 | `kill -9` |
| 소비자 | 특정 메시지가 프로세스를 죽임 | 레플리카가 돌아가며 재시작 | 재시작 반복 경보 → `dlq quarantine` (`chassis-operations.md` §3) | 죽는 메시지 주입 |
| 에이전트 | 데몬이 죽은 사이 로그 로테이트 | 회전 파일 누락 | fingerprint 식별, 회전 파일 읽기 (`io.md` §2) | 정지 중 로테이트 |
| 에이전트 | 메모리 증가 | 호스트 본업 영향 | `MemoryHigh=`, 원인 수정 (`chassis-resources.md` §3) | soak |
| 에이전트 | 압축·암호화 CPU 과다 | 호스트 본업 영향 | 압축 수준 조정, `CPUWeight=` (`transfer.md` §3·§7) | 부하 |
| 에이전트 → 서버 | 서버 다운·응답 없음 | 전송 지연 | 상시 디스크 버퍼 + 재전송 | 연결 차단 |
| 서버 | 과다 수신 | 지연·OOM | 부하 차단, `Retry-After` | 재접속 폭주 |
| 서버 | 수신 뒤 저장 실패 | 유실 위험 | 저장 확정 전 응답 금지, 또는 스풀 | Sink 장애 주입 |
| 저장소 | 디스크 가득 | 쓰기 중단 | 보관 기간 정리, 사용률 경보, 스스로 멈춤 | 디스크 채우기 |
| 저장소 | I/O 포화 | 처리 지연 | Backpressure, 저장 매체 분리 | 부하 |
| 네트워크 | 방화벽 오설정 | 전 구간 차단 | 재전송 + Emergency Notification | 포트 차단 |
| 네트워크 | 부분 단절 | 일부 호스트만 침묵 | 호스트별 마지막 수신 시각 경보 | 일부 차단 |

디스크 분할·보관: 파일이 많은 저장소는 시간 단위 경로 (`YYYY/MM/WW/`) 로 나누고, 보관 기간이 지나면 아카이브하거나 지운다 (Steady State).
