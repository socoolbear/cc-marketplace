# Chassis — Live Config · CLI Component · Utility

사람과 자동화가 서버를 바꾸고 조작하는 경로다. CLI Component 는 명령 표면 (파싱·출력·종료 코드), Utility 는 그 뒤의 작업 내용이다.

## 1. Live Config

### 방법

| 방법 | 언제 | 주의 |
|---|---|---|
| 롤링 재시작 | **기본값** (k8s). ConfigMap 해시를 파드 annotation 에 넣어 변경 시 자동 재시작 | 가장 단순하고 시작 = 복구 경로를 그대로 탄다. 장기 연결 서버는 재접속 폭주 비용을 계산한다 (`protocol.md` §8) |
| SIGHUP + `notify-reload` | systemd | 검증 실패 시 이전 설정 유지 + 경보 |
| 파일 감시 | k8s 에서 재시작 비용이 클 때 | ConfigMap 볼륨은 `..data` 심링크를 원자적으로 바꾼다 → **부모 디렉토리**를 감시하고 이름으로 거른다. **subPath 마운트와 env 주입은 갱신되지 않는다** ([ConfigMap](https://kubernetes.io/docs/concepts/configuration/configmap/), [fsnotify](https://pkg.go.dev/github.com/fsnotify/fsnotify)). NFS 등은 폴링 (Vector `--watch-config-method=poll`) |
| 제어 socket 의 reload 지시 | 호스트 데몬에서 결과를 받아야 할 때 | §2 제어 채널 |

### 규칙

공통: `파싱 → 검증 → 새 객체 생성 → 원자 교체 (포인터 swap)`. 진행 중 작업은 옛 설정으로 끝낸다.

- **전부 성공 아니면 무변경.** 실패하면 옛 설정으로 계속 돈다 (nginx 는 HUP 때 문법·파일·소켓까지 확인하고 실패하면 옛 설정 유지, [control](https://nginx.org/en/docs/control.html). Caddy `/load` 는 실패 시 이전 설정으로 롤백, [API](https://caddyserver.com/docs/api). Prometheus 도 미적용, [config](https://prometheus.io/docs/prometheus/latest/configuration/configuration/))
- **실패한 파일이 남으면 다음 재시작이 exit ≠ 0 이다.** 조용히 옛 설정으로 뜨지 않게 하는 의도된 동작이다. 재적재 실패 경보를 그래서 건다. 고치거나 직전 설정으로 되돌린 뒤 재시작한다
- **직전 설정을 남긴다.** 적용에 성공하면 그 설정을 마지막 정상 설정으로 시각과 함께 보관해 되돌릴 수 있게 한다. 설정이 Git·ConfigMap 에 있으면 그 이력이 이 역할을 한다. 없으면 호스트에 `<file>.bak-YYYYMMDDHHMMSS` 를 남기고 개수를 제한한다
- **검증만 하는 명령을 둔다** (`check-config`). 재적재와 같은 코드를 탄다 (`nginx -t`, `promtool check config`, `vector validate`, `otelcol validate`)
- **항목을 나눈다.** 재적재 가능 / 재시작 필요. 재시작 필요 항목이 바뀌면 조용히 무시하지 말고 거절한다 (Vector 는 reload 불가 전역 옵션 변경을 거부, [controller.rs](https://github.com/vectordotdev/vector/blob/master/src/topology/controller.rs))
- **두 단계로 나눈다.** 모든 컴포넌트가 `prepare` 에 성공한 뒤에만 `commit` 한다 (`components.md` §2). 하나라도 실패하면 준비한 것을 버려 전부 옛 설정으로 남는다. 새 인스턴스를 옛 것과 겹쳐 띄울 수 있으면 `prepare` 에서 띄우고 (Caddy 는 새 것을 먼저 시작한다. 포트·파일이 겹친다), 겹칠 수 없는 소켓·파일을 쥔 컴포넌트는 소켓을 넘기거나 재시작 필요 항목으로 둔다 (OTel Collector 는 전체 재적재 때 옛 구성을 멈추고 새 구성을 시작한다. 이것은 재시작과 같은 비용이다)
- **결과를 지표로 낸다.** `<app>_config_last_reload_successful`, `<app>_config_last_reload_success_timestamp_seconds`, 설정 해시 ([Prometheus 소스](https://github.com/prometheus/prometheus/blob/main/cmd/prometheus/main.go)). 실패 지속에 경보. 인스턴스끼리 설정 해시가 다르면 불완전 전개다
- **런타임 변경의 영속성을 정한다.** 관리 명령으로 바꾼 값은 재시작에 사라질 수 있다 (HAProxy Runtime API 는 메모리에만, [문서](https://www.haproxy.com/documentation/haproxy-runtime-api/)). 잠깐 쓰는 값 (로그 레벨) 만 런타임으로 바꾸고, 남아야 할 값은 설정 파일을 고친다
- 수신 확인과 적용 성공은 다르다 (Envoy ACK 는 리소스가 유효하다는 뜻이고 적용은 그 뒤에 실패할 수 있다, [xDS](https://www.envoyproxy.io/docs/envoy/latest/api-docs/xds_protocol)). 원격에서 밀어 넣는 설정이면 적용 결과를 지표로 확인한다

처리 결과에 영향을 주는 설정 (규칙·단가·매핑) 은 버전을 붙이고 제자리 수정하지 않는다.

**자격 증명**: 오래 도는 프로세스는 토큰·인증서 만료를 만난다. 설정 재적재와 같은 경로로 다시 읽어 교체한다 (인증서: `transfer.md` §4). 권한 낮추기·자원 제한·접근 제한은 프로세스가 하지 않고 감독자에게 맡긴다 (systemd.exec 설정, k8s `securityContext`) ([daemon(7)](https://man7.org/linux/man-pages/man7/daemon.7.html), [microservice chassis](https://microservices.io/patterns/microservice-chassis.html)).

## 2. CLI Component

데몬과 **같은 바이너리**의 하위 명령으로 둔다 (`vector top`·`vector validate`, `caddy reload`·`caddy validate`). 시작·정지·재시작은 감독자 몫이라 만들지 않는다 (`systemctl`, `kubectl`). 개발용 포그라운드 실행 `run` 만 둔다.

| 명령 | 작업 | 종류 |
|---|---|---|
| `<app> run` | 데몬 본체 (포그라운드) | 본체 |
| `<app> check-config` | 설정 검증 | 일회성 |
| `<app> status` | 상태 조회 (§3) | 제어 채널 |
| `<app> reload` | 재적재 지시 | 제어 채널 |
| `<app> log-level <level> [--for 10m]` | 로그 레벨 변경 | 제어 채널 |
| `<app> pause`·`resume` | 입력 멈춤·재개 (실시간 상태 변경) | 제어 채널 |
| `<app> recover` | 격리 항목 점검·재투입 (§3) | 상태 위치에 따라 |
| `<app> dlq requeue`, `<app> replay` | 재투입, 되감기 (§3) | 상태 위치에 따라 |
| `<app> version` | 빌드·프로토콜 버전 | 일회성 |

표면 규칙 ([clig.dev](https://clig.dev/)):

- 주 출력은 stdout, 로그·오류는 stderr. `--json` 을 둔다. 자동화가 파싱한다
- 상태를 바꾸는 명령은 `--dry-run` 을 둔다. 되돌리기 어려운 명령은 확인을 묻고, 비대화형이면 `--force` 를 요구한다
- 종료 코드: 0 성공, 64 사용법 오류, 78 설정 오류 ([sysexits](https://man.freebsd.org/cgi/man.cgi?query=sysexits&sektion=3), 표준은 아니지만 관례), `status` 는 0 실행 중, 3 정지 ([systemctl](https://www.freedesktop.org/software/systemd/man/latest/systemctl.html)). 감독자 재시작 제외와 맞춘다 (`chassis-failure.md` §2)
- `-v`·`--debug` 는 CLI 자신의 출력 수준이다. 데몬의 디버그 레벨은 `log-level` 로 바꾸고, 잊어도 돌아오게 만료 시간을 둔다 (Go `slog.LevelVar`, [slog](https://pkg.go.dev/log/slog), Spring `/actuator/loggers`, [loggers](https://docs.spring.io/spring-boot/api/rest/actuator/loggers.html))

### 제어 채널

**실행 중 프로세스**를 조작하는 경로는 Unix domain socket 하나를 기본으로 한다 (`/run/<app>/control.sock`, mode 0600 또는 0660). HAProxy stats socket, supervisord 가 같은 구조다 ([HAProxy](https://docs.haproxy.org/dev/management.html), [supervisord](https://supervisord.org/configuration.html)). k8s 에서도 컨테이너 안에서 `kubectl exec` 로 쓴다.

- HTTP 관리 포트는 읽기 전용이다 (`/healthz`·`/readyz`·`/metrics`). 프레임워크가 주는 변경 엔드포인트 (Spring Actuator) 를 쓰면 내부 접근 + 인증을 건다
- 인증 없는 제어 API 를 네트워크에 열지 않는다 (Vector API 는 인증이 없어 격리 환경에서만 켜라고 경고한다, [API](https://vector.dev/docs/reference/api/)). socket 접근권은 곧 root 급일 수 있다 (`docker` 그룹, [문서](https://docs.docker.com/engine/install/linux-postinstall/))
- 제어 명령은 Backlog 에 누가·무엇을 남긴다

## 3. Utility

12-Factor XII: 일회성 관리 작업은 데몬과 **같은 릴리스, 같은 설정**으로 실행한다 ([Admin processes](https://12factor.net/admin-processes)). 별도 스크립트·다른 빌드로 돌리면 코드·스키마가 어긋난다.

### 상태가 어디 있느냐로 나눈다

명령 이름이 아니라 **건드릴 상태의 위치**가 실행 방식을 정한다.

| 상태 위치 | 실행 방식 |
|---|---|
| 브로커·DB (Kafka offset, DLQ 토픽, 작업 테이블) | 별도 프로세스 (Job, 일회성 파드) |
| 로컬 (디스크 버퍼, 파일 체크포인트, 격리 폴더) | **쓰는 프로세스는 언제나 하나.** 명령은 먼저 상태 디렉토리 잠금 (`flock`) 을 시도한다. 잡히면 데몬이 없으므로 직접 처리하고, 못 잡으면 데몬이 살아 있으므로 제어 socket 으로 위임한다. 데몬도 시작 때 같은 잠금을 잡고, 못 잡으면 exit ≠ 0 (이중 기동 방지) |

k8s 에서 로컬 상태는 같은 컨테이너의 `kubectl exec` 로 처리한다. 시작 실패 반복으로 exec 를 쓸 수 없으면 레플리카를 0 으로 줄이고 같은 볼륨을 마운트한 유지보수 파드에서 처리한다 (잠금은 같다).

### 작업

- **상태 체크** (`status`): 살아 있는지가 아니라 일하는지를 답한다. 컴포넌트별 `health()`, Lifecycle 상태, 가장 오래된 미처리 항목 나이, 버퍼 사용량, 격리 항목 수, 마지막 재적재 결과
- **DLQ 재투입** (`dlq requeue`): 필터·건수 상한·`--dry-run` 을 둔다. 재투입 속도를 제한한다
- **되감기·재처리** (`replay`): 되감기 절차에는 멱등 상태 (Dedup Window) 초기화 여부를 같이 적는다 (`contract.md` §2). 파일 tailer 의 Position 처럼 로컬이면 위 표의 로컬 규칙을 따른다
- **수동 복구** (`recover`): 격리된 손상 항목을 점검해 재투입하거나 버린다. Position 저장소가 손상돼 시작이 막히면 복구할 시작점을 사람이 정한다. 평소 복구는 시작 경로가 자동으로 한다 (`chassis-lifecycle.md` §7). 이 명령이 평소 경로가 되면 설계가 틀린 것이다
- 운영 절차 (언제 무엇을 돌리나) 는 장애 대응표에 잇는다 (`chassis-failure.md` §4)
