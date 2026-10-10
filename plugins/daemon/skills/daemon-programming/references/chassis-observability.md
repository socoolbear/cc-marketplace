# Chassis — Observability · Admin Processes

헬스체크 프로브 (liveness·readiness·startupProbe) 는 플랫폼에 묶여 있어 `chassis-lifecycle.md` §1 에 있다. 경보는 Observability 의 일부이며 별도 구성 요소가 아니다.

## 1. 지표

| 묶음 | 지표 | 왜 |
|---|---|---|
| RED (작업) | 처리량, 오류율, 처리 시간 히스토그램 | 처리 품질 |
| USE (자원) | 큐·버퍼 사용률, 포화 (pause 횟수·시간), 메모리 RSS, fd 수, 스레드·goroutine 수 | Backpressure·누수 |
| 진행 | **가장 오래된 미처리 항목의 나이**, Source lag, 마지막 성공 시각 (`*_last_success_timestamp_seconds`) | lag 보다 SLO 에 가깝다. 멈춤 감지 |
| 실패 | 재시도 수·재시도율, DLQ 적재 수, 버린 항목 수 (사유별) | 조용한 유실 방지 |
| 상태 | `<app>_state{state}`, 재시작 횟수, 리더 여부 | Lifecycle 상태 기계 노출 |

Prometheus 지침: 단계마다 in / in-progress / 마지막 처리 시각 / out 을 내고, 파이프라인 전체에 heartbeat 더미 항목을 흘려 전파 지연을 잰다 (조용한 구간이 없는 파이프라인이면 더미 항목은 필요 없다). 15분보다 자주 도는 배치는 데몬으로 바꾸라고 권한다 ([instrumentation](https://prometheus.io/docs/practices/instrumentation/))

## 2. 경보

경보는 프로세스 밖 (Prometheus·Alertmanager 등) 이 낸다. 죽은 프로세스는 스스로 경보를 못 낸다.

| 경보 | 식 (예) |
|---|---|
| 정체 | `oldest_unprocessed_age_seconds > SLO` |
| 멈춤 | `time() - last_success_timestamp_seconds > 3 * 주기` |
| 사라짐 | `up{job="x"} == 0` **와** `absent(up{job="x"})` 둘 다 |
| 유실 위험 | `increase(dlq_total[10m]) > 0`, `increase(dropped_total[10m]) > 0` |
| 재시도 급증 | 재시도율 (`rate(retry_total[5m]) / rate(processed_total[5m])`) 이 평소 대비 급증. 재시도 예산은 `chassis-overload.md` §2 |
| 재시작 반복 | `increase(kube_pod_container_status_restarts_total[30m]) > 3` |
| 경보 경로 생존 | 항상 울리는 Watchdog 경보 → 끊기면 외부 dead man's switch 가 알림 ([Watchdog runbook](https://runbooks.prometheus-operator.dev/runbooks/general/watchdog/)) |

- 사라짐: 대상이 목록에 남아 있는데 프로세스만 죽으면 scrape 가 실패해 `up == 0` 이 된다. 이때 `absent(up{job="x"})` 는 거짓이라 못 잡는다. 서비스 디스커버리에서 대상 자체가 빠진 경우만 `absent` 가 잡는다 ([jobs·instances](https://prometheus.io/docs/concepts/jobs_instances/), [absent](https://prometheus.io/docs/prometheus/latest/querying/functions/#absent))
- 고정 임계값 (가장 오래된 항목의 나이 등) 외에 처리 성공률·지연은 SLO 기반 multi-window multi-burn-rate 경보 (예: 1h/6h 창) 로 건다. 짧은 창은 빠른 감지, 긴 창은 오탐 억제 ([Alerting on SLOs](https://sre.google/workbook/alerting-on-slos/))
- 경보는 상태 변화 (정상→이상, 이상→복구) 에 보내고 같은 원인은 묶는다 (Alertmanager grouping·inhibition·silence). 단 Alertmanager 는 firing 경보를 `repeat_interval` (기본 4h) 마다 다시 보낸다. 복구 알림은 `send_resolved` 가 필요하고 기본값이 수신기마다 다르다 (webhook 은 true, email·Slack 은 false). 묶음 기본값은 `group_wait` 30s, `group_interval` 5m ([설정](https://prometheus.io/docs/alerting/latest/configuration/))

## 3. 로그

- stdout 구조화 로그 (JSON). 파일 로테이트는 플랫폼 몫
- 필드: `role`, `state`, `source`, `partition`, `offset`, `key`, `attempt`, `trace_id`, `duration_ms`
- 항목 단위 성공 로그는 샘플링하거나 지표로 대신한다. 실패·DLQ·상태 전이는 전부 남긴다

## 4. trace 전파

OpenTelemetry messaging 시맨틱 규약 ([messaging spans](https://opentelemetry.io/docs/specs/semconv/messaging/messaging-spans/)):

- 생산자는 생성 시점의 trace context 를 메시지 헤더에 주입한다. 소비자는 그것을 parent 가 아니라 **span link** 로 건다. 배치 처리는 link 만 쓴다
- span kind: 발행 (Create) = `PRODUCER`, 처리 (Process) = `CONSUMER`
- 속성: `messaging.system` 필수, `messaging.operation.type`·`messaging.destination.name` 조건부 필수
- 규약 상태가 Development 다. 쓰려면 `OTEL_SEMCONV_STABILITY_OPT_IN=messaging` 으로 옵트인한다
- DLQ 로 보낼 때 `traceparent` 헤더를 보존한다 (`chassis-failure.md` §1). 재투입 후에도 원 trace 와 이어진다

## 5. 관리 포트

- 업무 포트와 관리 포트를 분리한다. 관리 포트에 `/healthz` `/readyz` `/metrics` 를 둔다
- pprof·heap dump 엔드포인트는 관리 포트 + 내부 접근만
- 로그 레벨을 재시작 없이 바꾸는 것이 데몬의 "제어 인터페이스" (control interface, systemd [daemon(7)](https://man7.org/linux/man-pages/man7/daemon.7.html) 용어) 다. 장애 대응이 빨라진다

## 6. Admin Processes

12-Factor XII: 일회성 관리 작업은 데몬과 **같은 릴리스, 같은 설정**으로 실행한다 ([Admin processes](https://12factor.net/admin-processes)). 별도 스크립트·다른 빌드로 돌리면 코드·스키마가 어긋난다.

- DLQ 재투입: `<app> dlq requeue`
- Position 되감기·재처리: `<app> replay`. 되감기 절차에는 멱등 상태 (Dedup Window) 초기화 여부를 같이 적는다 (`contract.md` §2)
