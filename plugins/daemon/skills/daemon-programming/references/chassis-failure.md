# Chassis — Failure Handling

분류 (Transient / SinkDown / Poison / Fatal / 종료 중 실패) 와 기본 동작은 SKILL.md 에 있다. 여기는 그 상세다.

## 1. 독성 입력과 DLQ

- 재시도 토픽 (지연 단계별, Source 파티션을 막지 않음, 순서 포기) vs 제자리 재시도 (순서 유지, 파티션이 막힘) 중 하나를 고른다
- DLQ 헤더: 에러, 시도 수, Source topic/partition/offset, 최초 실패 시각, `traceparent` (OTel trace context, `chassis-observability.md` §4), 원본 bytes
- 종료 (context 취소) 로 생긴 실패는 메시지 탓이 아니다. DLQ 로 보내지 말고 NACK·미커밋
- 재시도 가능한 오류 (연결 실패·타임아웃·429·503·락 충돌) 는 SKILL.md 의 SinkDown 판정을 먼저 거친다. SinkDown 이면 메시지별 시도 수·브로커 전달 횟수를 쓰지 않는다 (`io.md` §1 SinkDown 절). canary 쓰기가 성공하면 범위가 그 메시지뿐이다 — 429·503 은 `Retry-After` 만큼 미루되 시도 수를 세지 않고, 그 밖만 Transient 로 세어 N 회 뒤 DLQ 로 보낸다
- DLQ 는 버리는 곳이 아니라 재처리 대기열이다. 재투입 명령은 Admin Processes (`chassis-observability.md` §6)
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

graceful degradation (부하 때 요청당 일을 줄이기) 은 정기적으로 시험할 때만 둔다. 데몬의 저하 상태 (Source 를 멈추고 Position 유지, 백오프) 는 이 원칙과 맞는다. 출처: [Avoiding fallback](https://builder.aws.com/content/3EuS9Sakq7L3VLQIF3qzfMfke1Y/avoiding-fallback-in-distributed-systems), [Cascading failures](https://sre.google/sre-book/addressing-cascading-failures/)
