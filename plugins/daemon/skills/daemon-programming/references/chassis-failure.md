# Chassis — Failure Handling

분류 (Transient / Poison / Fatal) 와 기본 동작은 SKILL.md 에 있다. 여기는 그 상세다.

## 1. 독성 입력과 DLQ

- 재시도 토픽 (지연 단계별, Source 파티션을 막지 않음, 순서 포기) vs 제자리 재시도 (순서 유지, 파티션이 막힘) 중 하나를 고른다
- DLQ 헤더: 에러, 시도 수, Source topic/partition/offset, 최초 실패 시각, `traceparent` (OTel trace context, `chassis-observability.md` §4), 원본 bytes
- 종료 중 실패는 DLQ 로 보내지 말고 NACK·미커밋 (OpenMeter watermill router 동작)
- DLQ 는 버리는 곳이 아니라 재처리 대기열이다. 재투입 명령은 Admin Processes (`chassis-observability.md` §6)
- 브로커별 재전달 조건·DLQ 지원은 `io.md` §1 브로커 비교. RabbitMQ 에서 독성 감지는 reject/requeue=false 가 필요하다 (`io.md` §1)
- 백오프+지터 재시도는 재시도 예산이 다스린다. 재시도는 한 계층에서만 한다 (`chassis-overload.md` §2)
- 호환 불가능한 스키마 버전은 Poison 으로 분류한다 (`contract.md` §5)

## 2. 감독 전략 (재시작 강도)

Erlang/OTP supervisor: `one_for_one` / `one_for_all` / `rest_for_one`, **MaxT 초 안에 MaxR 회 넘게 재시작하면 포기하고 상위에 넘긴다** ([OTP](https://www.erlang.org/doc/system/sup_princ.html)). 같은 원인으로 무한히 죽는 것을 막는 장치다.

- 프로세스 안: errgroup 은 `one_for_all`. 하위 구성 요소 하나만 재시작하고 싶으면 그 구성 요소에 백오프 재시작 루프를 두되 **횟수 상한을 넘으면 프로세스를 죽여** 감독자에게 넘긴다
- 프로세스 밖: systemd `StartLimitBurst` (포기), k8s CrashLoopBackOff (포기 안 함 → 경보 필요)

기본값과 세부:

- OTP: intensity 1, period 5 (5초 안에 1회 넘게 재시작하면 포기)
- systemd: `DefaultStartLimitIntervalSec=10s`, `DefaultStartLimitBurst=5`. 수동 시작도 횟수에 든다. 지수 백오프는 `RestartSteps=`·`RestartMaxDelaySec=` (v254)
- k8s: CrashLoopBackOff 는 포기하지 않지만 상한은 1.35 부터 노드별로 설정할 수 있다. `restartPolicyRules` (1.35 Beta) 는 특정 종료 코드에서 재시작을 건너뛴다. 종료 코드로 Fatal 을 가를 수 있다 (`chassis-lifecycle.md`)
- 출처: [OTP](https://www.erlang.org/doc/system/sup_princ.html), [k8s Pod lifecycle](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)

## 3. fallback 대신 failover

드물게만 타는 fallback 경로는 만들지 않는다. 시험이 안 된 경로는 장애 때 처음 실행되고 그때 깨진다. 대안:

- 호출자 재시도
- 미리 밀어 둔 데이터 (pre-pushed)
- 항상 켜 둔 (active-active) failover

graceful degradation (부하 때 요청당 일을 줄이기) 은 정기적으로 시험할 때만 둔다. 데몬의 저하 상태 (Source 를 멈추고 Position 유지, 백오프) 는 이 원칙과 맞는다. 출처: [Avoiding fallback](https://builder.aws.com/content/3EuS9Sakq7L3VLQIF3qzfMfke1Y/avoiding-fallback-in-distributed-systems), [Cascading failures](https://sre.google/sre-book/addressing-cascading-failures/)
