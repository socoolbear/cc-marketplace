# Chassis — Observability · Emergency Notification · Backlog

헬스체크 프로브 (liveness·readiness·startupProbe) 는 플랫폼에 묶여 있어 `chassis-lifecycle.md` §1 에 있다. §1·§4·§5 가 Observability, §2 가 Emergency Notification, §3 이 Backlog 다.

## 1. 지표

| 묶음 | 지표 | 왜 |
|---|---|---|
| RED (작업) | 처리량, 오류율, 처리 시간 히스토그램 | 처리 품질 |
| USE (자원) | 큐·버퍼 사용률, 포화 (pause 횟수·시간), 메모리 RSS, fd 수, 스레드·goroutine 수 | Backpressure·누수 |
| 진행 | **가장 오래된 미처리 항목의 나이**, Source lag, 마지막 성공 시각 (`*_last_success_timestamp_seconds`) | lag 보다 SLO 에 가깝다. 멈춤 감지 |
| 실패 | 재시도 수·재시도율, DLQ 적재 수, 버린 항목 수 (사유별) | 조용한 유실 방지 |
| 상태 | `<app>_state{state}`, 재시작 횟수, 리더 여부 | Lifecycle 상태 기계 노출 |

Prometheus 지침: 단계마다 in / in-progress / 마지막 처리 시각 / out 을 내고, 파이프라인 전체에 heartbeat 더미 항목을 흘려 전파 지연을 잰다 (조용한 구간이 없는 파이프라인이면 더미 항목은 필요 없다). 15분보다 자주 도는 배치는 데몬으로 바꾸라고 권한다 ([instrumentation](https://prometheus.io/docs/practices/instrumentation/))

## 2. Emergency Notification

죽은 프로세스는 스스로 경보를 못 낸다. 그래서 감지·발송 주체는 본체와 **완전히 별개**다. 자식 프로세스는 부모와 함께 죽을 수 있으므로 쓰지 않는다.

### 사건별 감지 주체

| 사건 | 호스트 (systemd) | Kubernetes |
|---|---|---|
| KILL·crash | `OnFailure=` 핸들러. `MONITOR_SERVICE_RESULT` = `signal`·`exit-code`·`core-dump` | `kube_pod_container_status_last_terminated_reason` + 재시작 증가율 |
| HANG | `WatchdogSec=` 초과 → failed + SIGABRT, 결과 `watchdog` | liveness 실패 → 재시작 → 재시작 경보. 입력은 있는데 진행이 없으면 가장 오래된 항목 나이 |
| OOM | 결과 `oom-kill` | `OOMKilled` (exit 137) |
| 재시작 포기 | 결과 `start-limit-hit` | 포기하지 않는다 → 재시작 반복 경보 |
| 호스트·노드째 사라짐 | **핸들러도 같이 죽는다** → 외부 dead man's switch (아래) | `up == 0`, `absent` |
| 업무 이상 (임계치 초과) | 본체가 지표·이벤트를 내고 규칙이 판단 (아래) | 같음 |

### systemd `OnFailure=`

```ini
# app.service
[Unit]
OnFailure=notify-failure@%n.service     # 템플릿으로 쓴다. 여러 서비스가 비템플릿 핸들러를 공유하면 MONITOR_* 가 전달되지 않는다
```

- 핸들러는 `MONITOR_SERVICE_RESULT`·`MONITOR_EXIT_CODE`·`MONITOR_EXIT_STATUS`·`MONITOR_UNIT` 을 받는다 ([systemd.exec](https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html))
- **기본 `RestartMode=normal` 이면 재시작이 예정돼 있어도 실패마다 핸들러가 돈다** (v254 에서 문서 정정, [systemd.service](https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html), [#33710](https://github.com/systemd/systemd/issues/33710)). 크래시 루프가 곧 알림 폭주다 → 핸들러에 폭주 제어를 둔다. `RestartMode=direct` 는 재시작 동안 건너뛰고 최종 실패 때만 돌지만 일시 장애를 알 수 없다. "잠깐 죽었다 살아난 것" 도 알아야 하면 normal + 폭주 제어다
- 핸들러 자체가 실패할 수 있다 → 발송은 재시도하고, 실패는 journal 에 남기고 외부 heartbeat 가 뒤를 받친다

### 외부 dead man's switch

본체나 호스트가 주기적으로 외부에 ping 하고, 끊기면 외부가 알린다 ([healthchecks](https://healthchecks.io/docs/): period·grace, `/fail` 로 즉시 실패 보고). 경보 경로 자체의 생존도 같은 방식으로 본다.

### 마지막 숨 (last-gasp)

프로세스 안의 "죽기 직전 알림" 은 보조다. SIGKILL·SIGSTOP 은 잡을 수 없고 ([signal(7)](https://man7.org/linux/man-pages/man7/signal.7.html)), 신호 핸들러 안에서 `malloc`·`printf`·`syslog` 를 쓸 수 없어 ([signal-safety(7)](https://man7.org/linux/man-pages/man7/signal-safety.7.html)) HTTP·TLS 클라이언트 호출은 안전하지 않다. 하려면 메인 흐름의 panic·uncaught 경로에서 짧은 기한으로 사유만 남긴다. k8s 는 `terminationMessagePath` (4096바이트) 에 쓰면 된다 ([문서](https://kubernetes.io/docs/tasks/debug/debug-application/determine-reason-pod-failure/)). k8s Event 는 best-effort 이고 기본 1시간 보존이라 알림 근거로 삼지 않는다.

### 업무 이상 알림

"임계치를 넘으면 사람에게" 는 데이터 경로에서 직접 메일을 보내지 않는다. 처리 루프는 카운터·이벤트만 내고 규칙이 판단한다. 지표 경보가 없으면 임계치 판단을 수집 서버 한 곳에서 해 호스트마다 따로 쏘지 않게 한다. 알림 발송 실패가 처리 루프를 막거나 재시도시키면 안 된다.

### 폭주 제어

- 상태 변화 (정상→이상, 이상→복구) 에 보내고, 같은 원인은 키로 묶는다 (PagerDuty `dedup_key`, [문서](https://docs.pagerduty.com/developer/send-alert-event), Alertmanager grouping·inhibition)
- 재알림 주기와 시간당 상한을 둔다. 상한에 닿으면 "N 건 억제됨" 요약 한 건을 보낸다
- 수신자 경로가 실패하면 재시도한다. Alertmanager 로 보내는 쪽은 firing 을 해소될 때까지 다시 보내야 한다 ([alerts API](https://github.com/prometheus/alertmanager/blob/main/docs/alerts_api.md)). PagerDuty 429 는 수 분 백오프
- 복구 시작·종료 (`chassis-lifecycle.md` §7) 는 사람이 기다리는 사건이면 보내고, 자동 복구가 일상이면 지표로만 둔다

### 지표 경보

Prometheus·Alertmanager 가 있으면 아래 경보를 건다.

| 경보 | 식 (예) |
|---|---|
| 정체 | `oldest_unprocessed_age_seconds > SLO` |
| 멈춤 | `time() - last_success_timestamp_seconds > 3 * 주기` — 주기 실행 (폴러·스케줄러) 이나 heartbeat 항목을 흘리는 파이프라인에만 건다. 입력이 끊길 수 있는 소비자는 가장 오래된 미처리 항목 나이로 대신한다 ([Prometheus](https://prometheus.io/docs/practices/instrumentation/)) |
| 사라짐 | `up{job="x"} == 0` **와** `absent(up{job="x"})` 둘 다 |
| 유실 위험 | `increase(dlq_total[10m]) > 0`, `increase(dropped_total[10m]) > 0` |
| 재시도 급증 | 재시도율 (`rate(retry_total[5m]) / rate(processed_total[5m])`) 이 평소 대비 급증. 재시도 예산은 `chassis-overload.md` §2 |
| 재시작 반복 | `increase(kube_pod_container_status_restarts_total[30m]) > 3` |
| 경보 경로 생존 | 항상 울리는 Watchdog 경보 → 끊기면 외부 dead man's switch 가 알림 ([Watchdog runbook](https://runbooks.prometheus-operator.dev/runbooks/general/watchdog/)) |

- 사라짐: 대상이 목록에 남아 있는데 프로세스만 죽으면 scrape 가 실패해 `up == 0` 이 된다. 이때 `absent(up{job="x"})` 는 거짓이라 못 잡는다. 서비스 디스커버리에서 대상 자체가 빠진 경우만 `absent` 가 잡는다 ([jobs·instances](https://prometheus.io/docs/concepts/jobs_instances/), [absent](https://prometheus.io/docs/prometheus/latest/querying/functions/#absent))
- 고정 임계값 (가장 오래된 항목의 나이 등) 외에 처리 성공률·지연은 SLO 기반 multi-window multi-burn-rate 경보로 건다. 경보마다 긴 창과 짧은 창 (긴 창의 1/12) 이 둘 다 임계 burn rate 를 넘을 때만 울린다. 30일 SLO 창 기준 권장값 (배수는 SLO 목표와 무관, 오류율 임계 = 배수 × (1−SLO)): page 1h/5m@14.4, page 6h/30m@6, ticket 3d/6h@1 ([Alerting on SLOs](https://sre.google/workbook/alerting-on-slos/))
- 경보는 상태 변화 (정상→이상, 이상→복구) 에 보내고 같은 원인은 묶는다 (Alertmanager grouping·inhibition·silence). 단 Alertmanager 는 firing 경보를 `repeat_interval` (기본 4h) 마다 다시 보낸다. 복구 알림은 `send_resolved` 가 필요하고 기본값이 수신기마다 다르다 (webhook 은 true, email·Slack 은 false). 묶음 기본값은 `group_wait` 30s, `group_interval` 5m ([설정](https://prometheus.io/docs/alerting/latest/configuration/))

## 3. Backlog

서버 자신이 남기는 기록이다 (큐 적체가 아니다). 장애 뒤에 무슨 일이 있었는지 재구성하는 근거가 된다.

- stdout 구조화 로그 (JSON). 파일 로테이트는 플랫폼 몫 ([12-factor](https://12factor.net/logs)). 감독자가 없는 호스트만 날짜별 파일 + 보관 기간을 직접 둔다
- **출처를 나눈다.** 서버 본체 로그는 상시, 플러그인이 내는 로그는 사건이 났을 때. `component`·`plugin` 필드로 구분하고 레벨을 컴포넌트별로 조절할 수 있게 한다
- **용도를 나눈다.** 운영 로그와 감사·거래 기록은 소비자·보관 기간이 다르다. 잃으면 안 되는 기록은 로그가 아니라 Sink 다 ([OWASP](https://cheatsheetseries.owasp.org/cheatsheets/Logging_Cheat_Sheet.html))
- **민감 정보**: 토큰·비밀번호·키·개인정보는 남기지 않거나 마스킹한다. 권한별로 가려 보여 줄 데이터면 저장 때 구분한다
- **로그 인젝션**: 외부 입력을 그대로 남기지 않는다. CR·LF 를 무력화하고 구조화 필드로 넣고 크기를 자른다 (OWASP). 프로토콜 서버는 수신 페이로드를 통째로 찍지 않는다
- **한도**: 플랫폼이 버릴 수 있다. journald 기본 30초 10000건 초과분은 버린다 ([journald.conf](https://www.freedesktop.org/software/systemd/man/latest/journald.conf.html)). kubelet 은 기본 10Mi × 5 파일이다 ([kubelet](https://kubernetes.io/docs/reference/config-api/kubelet-config.v1beta1/)). 장애 때 폭증하는 로그는 샘플링하거나 묶는다
- 필드: `role`, `state`, `component`, `plugin`, `source`, `partition`, `offset`, `key`, `attempt`, `trace_id`, `duration_ms`
- 항목 단위 성공 로그는 샘플링하거나 지표로 대신한다. 실패·DLQ·상태 전이는 전부 남긴다

## 4. trace 전파

OpenTelemetry messaging 시맨틱 규약 ([messaging spans](https://opentelemetry.io/docs/specs/semconv/messaging/messaging-spans/)):

- 생산자는 생성 시점의 trace context 를 메시지 헤더에 주입한다. 소비자는 creation context 에 **span link** 를 건다. 단일 메시지면 parent 로 써도 되지만 (MAY), 배치 처리는 link 만 쓴다
- span kind: Create = `PRODUCER`, Send = `PRODUCER` (그 context 를 creation context 로 쓸 때, 아니면 `CLIENT`), Receive = `CLIENT`, Process = `CONSUMER` ([messaging-spans](https://opentelemetry.io/docs/specs/semconv/messaging/messaging-spans/))
- 속성: `messaging.system`·`messaging.operation.name` 필수, `messaging.operation.type` (해당 시)·`messaging.destination.name` (단일 메시지거나 배치 전체가 같은 값일 때) 조건부 필수
- 규약 상태가 Development 다. `OTEL_SEMCONV_STABILITY_OPT_IN` (`messaging` = 새 규약만, `messaging/dup` = 둘 다) 은 기존 계측이 옛 규약에서 새 규약으로 넘어갈 때의 이행 장치다. 쓰는 계측 라이브러리가 지원하는지 확인한다
- DLQ 로 보낼 때 `traceparent` 헤더를 보존한다 (`chassis-failure.md` §1). 재투입 후에도 원 trace 와 이어진다

## 5. 관리 포트

- 업무 포트와 관리 포트를 분리한다. 관리 포트에 `/healthz` `/readyz` `/metrics` 를 둔다
- pprof·heap dump 엔드포인트는 관리 포트 + 내부 접근만
- 로그 레벨 변경 같은 제어 인터페이스 (systemd [daemon(7)](https://man7.org/linux/man-pages/man7/daemon.7.html) 용어) 는 제어 socket 으로 둔다 (`chassis-operations.md` §2)
