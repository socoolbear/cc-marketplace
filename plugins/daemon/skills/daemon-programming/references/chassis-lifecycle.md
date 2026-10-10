# Chassis — Lifecycle · Recovery · Configuration (플랫폼·런타임별)

Lifecycle (시작·종료·신호), Recovery (재시작·복구), Configuration (설정·자격 증명 재적재) 을 플랫폼·런타임별로 다룬다. Resource Limits 가 쓰는 런타임별 메모리 상한은 §4 에 있다 (그 밖의 상한·Steady State 는 `chassis-resources.md`).

## 1. Kubernetes

### 종료 순서 ([pod lifecycle](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/), [lifecycle hooks](https://kubernetes.io/docs/concepts/containers/container-lifecycle-hooks/))

1. 삭제 요청 → API 서버에 삭제 기한 기록. **유예 시간 카운트다운이 여기서 시작**
2. kubelet 이 preStop 실행 (동기). 동시에 컨트롤 플레인이 EndpointSlice 에서 파드를 빼기 시작
3. preStop 이 끝나면 각 컨테이너 PID 1 에 SIGTERM (컨테이너 간 순서 없음)
4. 유예 시간 (`terminationGracePeriodSeconds`, 기본 30s) 이 끝나면 SIGKILL. preStop 이 유예 시간을 넘기면 2s 를 한 번 더 준다
5. sidecar (restartPolicy Always 인 init container) 는 메인 컨테이너가 모두 끝난 뒤 정의 역순으로 SIGTERM

- **preStop 과 SIGTERM 이후 처리가 같은 유예 시간을 나눠 쓴다.** 연장 수단은 없다
- **엔드포인트 제거 경쟁**: EndpointSlice 갱신과 kubelet 종료가 동시에 진행돼 SIGTERM 뒤에도 잠시 요청이 들어온다. 트래픽을 받는 서버는 preStop 에 내장 sleep 액션 (`lifecycle.preStop.sleep.seconds`, 수 초) 을 두거나 SIGTERM 뒤 수신을 몇 초 더 유지한다. sleep 액션은 `sleep` 바이너리가 없는 distroless 이미지에서도 동작한다 (v1.34 Stable, [KEP-3960](https://www.kubernetes.dev/resources/keps/3960/)). 0초 값도 허용된다 (v1.34, KEP-4818). 트래픽을 받지 않는 소비자·워커는 이 문제가 거의 없다
- 종료 대기만을 위해 readiness 를 둘 필요는 없다 (terminating 엔드포인트는 자동으로 `ready=false`). 다만 terminating 엔드포인트는 EndpointSlice 의 `serving` 조건으로 아직 요청을 받을 수 있는지 드러내므로, Accept 형의 drain 중에도 `serving=true` 인 동안은 요청을 처리해야 한다
- **sidecar 시간도 같은 유예 시간 안**: sidecar 는 메인 컨테이너가 끝난 뒤에 멈추지만 같은 유예 시간을 쓰고, 유예 시간이 끝나면 남은 컨테이너가 짧은 유예만 받고 함께 SIGKILL 된다. 종료 예산에 sidecar 정지 시간을 포함한다
- **롤링 배포 중 버전 공존**: 옛 버전과 새 버전이 같은 Source 를 동시에 읽는다. 형식·멱등 키 호환 규칙은 `contract.md` §5

### 노드 종료 ([node shutdown](https://kubernetes.io/docs/concepts/cluster-administration/node-shutdown/))

- 노드가 꺼질 때는 kubelet 의 `shutdownGracePeriod` / `shutdownGracePeriodCriticalPods` 가 일반 파드와 critical 파드에 시간을 나눠 준다. 실제 예산이 `terminationGracePeriodSeconds` 보다 짧을 수 있으므로, 예산이 빠듯한 데몬은 짧아져도 Recovery 로 안전해야 한다

### 시작 순서와 워밍업 ([cascading failures](https://sre.google/sre-book/addressing-cascading-failures/))

- 의존 서비스의 시작 순서에 기대지 않는다. 연결은 백오프 재시도로 맺고, 설정 오류만 즉시 exit ≠ 0 한다 (의존 장애로 죽으면 재시작 폭주)
- 새 인스턴스에는 부하를 천천히 올린다. 캐시가 빈 상태 (cold cache) 에서도 버텨야 한다 — 워밍업 구간에는 동시성·요청 한도를 낮춘다

### 프로브 ([probes 개념](https://kubernetes.io/docs/concepts/configuration/liveness-readiness-startup-probes/))

| 프로브 | 무엇을 보나 | 하지 말 것 |
|---|---|---|
| startupProbe | 시작·복구 구간이 끝났나. 성공 전에는 liveness·readiness 가 돌지 않는다 | 복구가 오래 걸리는데 생략 (liveness 가 복구 중인 프로세스를 죽인다) |
| liveness | 복구 불가능한 내부 고장 (데드락, 루프 정지) 만 | DB·브로커 연결 확인을 넣기 (의존 장애 → 전체 재시작 폭주) |
| readiness | 지금 일을 받을 수 있나. 의존 확인은 여기에만 | 트래픽을 받지 않는 워커에 의미 없이 두기 |

- 스스로 crash 하는 프로세스라면 liveness 가 없어도 된다
- liveness 구현: 메인 루프가 매 회차 `lastTick` 을 갱신하고, 핸들러는 `now - lastTick < 임계` 만 본다

### 재시작

- CrashLoopBackOff: 10s → 20s → 40s … 상한까지 두 배씩, 10분 정상 동작하면 초기화. 상한은 기본 300s, 노드 설정으로 줄일 수 있다 (kubelet `crashLoopBackOff.maxContainerRestartPeriod` 1s~300s, `KubeletCrashLoopBackOffMax` v1.35 Beta 기본 켜짐). 더 짧게 시작하는 `ReduceDefaultCrashLoopBackOffDecay` (1s 시작, 60s 상한) 는 v1.33 Alpha 로 기본 꺼짐. **포기하지 않고 계속 재시도**하므로 "반복 재시작" 은 경보로 따로 잡는다 (`kube_pod_container_status_restarts_total` 증가율) ([pod lifecycle](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/))
- 종료 코드별 재시작 규칙 (`restartPolicyRules`, 기능 `ContainerRestartRules`, v1.35 Beta 기본 켜짐): 컨테이너마다 종료 코드에 따라 재시작 여부를 가른다. Fatal 을 나눌 때 쓴다 — 예: 설정 오류 전용 종료 코드는 재시작하지 않는다

### PID 1

- 컨테이너 안 PID 1 은 기본 동작인 신호를 무시한다. 핸들러가 없으면 SIGTERM 으로 죽지 않고 유예 시간 뒤 SIGKILL 된다 ([docker run](https://docs.docker.com/reference/cli/docker/container/run/))
- exec form `CMD ["node", "dist/main.js"]` 로 앱을 PID 1 로. `CMD node dist/main.js` (shell form) 나 `npm start` 래퍼는 신호를 앱에 넘기지 않을 수 있다
- 자식 프로세스를 띄우는 앱은 [tini](https://github.com/krallin/tini) 로 좀비 회수·신호 전달
- `shareProcessNamespace: true` 면 앱이 PID 1 이 아니다

## 2. systemd ([daemon(7)](https://www.freedesktop.org/software/systemd/man/latest/daemon.html), [systemd.service(5)](https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html), [sd_notify(3)](https://www.freedesktop.org/software/systemd/man/latest/sd_notify.html))

new-style 데몬 규칙: fork·setsid·PID 파일·권한 낮추기를 직접 하지 않는다 (systemd 가 깨끗한 환경을 준다). 로그는 stderr (레벨은 `<4>` 같은 접두사). 자원 제한은 unit 설정에 맡긴다.

```ini
[Service]
Type=notify-reload          # READY=1 을 받아야 시작 완료. reload 는 SIGHUP (ReloadSignal=) + 완료 알림. v253~
ExecStart=/usr/bin/app run
Restart=on-failure
RestartSec=2                # 기본값은 100ms
RestartSteps=5              # 재시작 간격을 RestartSec → RestartMaxDelaySec 로 이 단계 수만큼 지수 증가 (v254~)
RestartMaxDelaySec=60       # CrashLoopBackOff 의 systemd 쪽 대응
WatchdogSec=30              # 이 안에 WATCHDOG=1 이 없으면 SIGABRT 로 죽이고 재시작
TimeoutStopSec=45           # SIGTERM 후 이 시간 지나면 SIGKILL
KillMode=mixed              # SIGTERM 은 메인에만. 메인이 먼저 끝나면 나머지는 TimeoutStopSec 를 기다리지 않고 즉시 SIGKILL
LimitNOFILE=65536
[Unit]
StartLimitIntervalSec=60
StartLimitBurst=5           # 60초 안에 5번 넘게 재시작하면 포기 (OTP restart intensity 와 같은 뜻)
```

| sd_notify | 의미 |
|---|---|
| `READY=1` | 시작 또는 reload 완료 |
| `RELOADING=1` + `MONOTONIC_USEC=` | reload 시작. 끝나면 `READY=1` |
| `STOPPING=1` | 종료 시작. v259~ 최종 상태 — 이후 정지 타임아웃 안에 끝나지 않으면 남은 프로세스를 죽인다 ([sd_notify](https://github.com/systemd/systemd/blob/main/man/sd_notify.xml)) |
| `WATCHDOG=1` | keep-alive. 간격은 `WATCHDOG_USEC` 환경변수의 절반 정도로 |
| `EXTEND_TIMEOUT_USEC=` | 현재 단계 (시작·실행 중 `RuntimeMaxSec`·종료) 타임아웃 연장. k8s 에는 없는 기능 |
| `STATUS=` | 사람이 읽는 상태 문자열 (`systemctl status` 에 표시) |

`KillMode=process`·`none` 은 쓰지 않는다. `KillMode=mixed` 에서는 메인이 끝나는 순간 자식이 SIGKILL 되므로 **메인 프로세스가 자기 자식을 직접 정리하고 끝낸다**.

`Type=notify-reload` 는 v259 부터 첫 `READY=1` 시점에 메인 프로세스가 reload 신호 (기본 SIGHUP) 핸들러를 갖는지 확인하고, 없으면 시작을 중단한다 ([systemd.service](https://github.com/systemd/systemd/blob/main/man/systemd.service.xml)). 규칙: **`READY=1` 보다 먼저 SIGHUP 핸들러를 설치한다**.

소켓을 직접 listen 하는 Accept 형은 socket activation 과 `FDSTORE=1` 로 listen 소켓을 재시작 사이에 보존한다 ([daemon(7)](https://man7.org/linux/man-pages/man7/daemon.7.html)).

## 3. k8s 와 systemd 의 차이

| 항목 | Kubernetes | systemd |
|---|---|---|
| 건강 확인 | kubelet 이 묻는다 (pull: probe) | 프로세스가 알린다 (push: `READY`·`WATCHDOG`) |
| 종료 시간 연장 | 불가 | `EXTEND_TIMEOUT_USEC` |
| 재시작 간격 | CrashLoopBackOff: 10s 에서 두 배씩, 기본 상한 300s (노드 설정으로 축소) | 기본 `RestartSec` 100ms. `RestartSteps=`·`RestartMaxDelaySec=` 로 지수 증가 |
| 재시작 포기 | 안 함 (상한 간격으로 무한) | `StartLimitBurst` 넘으면 포기 |
| 설정 재적재 | 보내는 주체 없음 → 파일 감시 또는 롤링 재시작 | `Type=notify-reload` + SIGHUP |

두 환경을 다 지원하려면 내부 heartbeat 하나를 두 경로 (HTTP `/healthz` 와 `WATCHDOG=1`) 로 내보낸다.

## 4. 런타임별 종료 관용구

### Go

```go
ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
defer stop()
g, gctx := errgroup.WithContext(ctx)          // 하나가 실패하면 모두 취소 (OTP one_for_all 과 비슷)
g.Go(func() error { return consumer.Run(gctx) })
g.Go(func() error {                           // /healthz /readyz /metrics
    // Shutdown 직후 ErrServerClosed 가 즉시 반환된다. 그대로 넘기면 정상 SIGTERM 도 exit 1
    if err := adminServer.ListenAndServe(); !errors.Is(err, http.ErrServerClosed) {
        return err
    }
    return nil
})
g.Go(func() error {
    <-gctx.Done()
    sctx, cancel := context.WithTimeout(context.Background(), drainBudget)
    defer cancel()
    return adminServer.Shutdown(sctx)        // 기한 없으면 무기한 대기
})
if err := g.Wait(); err != nil && !errors.Is(err, context.Canceled) { os.Exit(1) }
```

- `GOMEMLIMIT` 은 컨테이너 limit 의 90~95% ([GC guide](https://go.dev/doc/gc-guide)). 관례값이다
- Go 1.25 부터 `GOMAXPROCS` 가 컨테이너를 인식한다: Linux 에서 cgroup CPU limit 을 따르고 주기적으로 다시 계산하며, CPU request 는 무시한다 ([Go 1.25](https://go.dev/doc/go1.25)). 1.24 이하는 직접 설정한다 (`automaxprocs` 등)
- `net/http` 의 `ListenAndServe` 는 `Shutdown` 뒤 `http.ErrServerClosed` 를 반환한다 ([net/http](https://pkg.go.dev/net/http))
- 종료 순서가 여럿이면 `oklog/run` 의 역순 종료나 명시적 단계 함수를 쓴다

### Node.js / NestJS ([lifecycle events](https://docs.nestjs.com/fundamentals/lifecycle-events))

- `app.enableShutdownHooks()` 를 **반드시** 부른다. 기본은 꺼져 있어 SIGTERM 에 훅이 돌지 않는다
- 훅 순서: `onModuleDestroy` → `beforeApplicationShutdown(signal)` → 연결 종료 → `onApplicationShutdown(signal)`. Promise 는 기다린다
  - 입력 중단·drain 은 `beforeApplicationShutdown` 에, 연결 정리는 `onApplicationShutdown` 에
- request-scoped 프로바이더에서는 훅이 돌지 않는다
- `app.close()` 는 프로세스를 끝내지 않는다. 남은 interval·타이머가 있으면 계속 산다 → 종료 경로 끝에서 타이머를 정리하거나 명시적으로 `process.exit`
- unhandled rejection 은 v15 부터 기본 `throw` → 프로세스 종료. `uncaughtException` 뒤에 계속 도는 것은 안전하지 않다 ([process](https://nodejs.org/api/process.html)) — 동기 정리만 하고 exit ≠ 0
- 힙 상한은 `--max-old-space-size` 를 컨테이너 limit 의 75~85% 로 (힙 밖 메모리 여유, 관례값). v24.6.0·v22.21.0 LTS 부터 `--max-old-space-size-percentage=N` 이 있다: 기준은 cgroup 제한 메모리 (없으면 전체 메모리) 이고 `--max-old-space-size` 보다 우선한다 ([CLI](https://nodejs.org/api/cli.html), [PR](https://github.com/nodejs/node/pull/59082))
- 이벤트 루프를 막는 CPU 작업은 heartbeat·poll 을 멈춰 리밸런스를 부른다 → worker_threads 로 빼거나 잘게 나눈다

### JVM / Spring Boot

- shutdown hook 은 짧게. 다른 서비스도 종료 중일 수 있다 ([Runtime](https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/lang/Runtime.html))
- `-XX:MaxRAMPercentage` 기본 25% → 컨테이너에서는 70~80% 로 올린다 (관례값, 공식 권장 수치는 없다)
- Spring Boot ([3.4 릴리스 노트](https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-3.4-Release-Notes), [graceful shutdown](https://docs.spring.io/spring-boot/reference/web/graceful-shutdown.html)): 3.4 부터 `server.shutdown=graceful` 이 기본이다 (끄려면 `immediate`). `spring.lifecycle.timeout-per-shutdown-phase` 기본 30s. 웹 서버 graceful 종료는 `SmartLifecycle` 정지 단계 중 가장 앞에서 돌고, 웹이 아닌 워커는 `SmartLifecycle.stop(callback)` 에서 drain

### Python

- 주기적 `gc.collect()` 는 누수를 가릴 뿐이다. 누수는 `tracemalloc` 로 찾는다 ([gc](https://docs.python.org/3/library/gc.html))
- 메모리 상한 설정이 없으므로 cgroup limit + 처리 N 건마다 자기 재시작 (`max-requests` 류) 으로 대신한다
- `signal.signal` 핸들러는 메인 스레드에서만 실행된다. asyncio 면 `loop.add_signal_handler`

## 5. 설정 재적재

| 방법 | 언제 | 주의 |
|---|---|---|
| 롤링 재시작 | **기본값** (k8s). ConfigMap 해시를 파드 annotation 에 넣어 변경 시 자동 재시작 | 가장 단순하고 시작 = 복구 경로를 그대로 탄다 |
| SIGHUP + `notify-reload` | systemd | 검증 실패 시 이전 설정 유지 + 경보 |
| 파일 감시 | k8s 에서 재시작 비용이 클 때 | ConfigMap 볼륨은 `..data` 심링크를 원자적으로 바꾼다 → **부모 디렉토리**를 감시하고 이름으로 거른다. **subPath 마운트와 env 주입은 갱신되지 않는다** ([ConfigMap](https://kubernetes.io/docs/concepts/configuration/configmap/), [fsnotify](https://pkg.go.dev/github.com/fsnotify/fsnotify)) |

공통: `파싱 → 검증 → 새 객체 생성 → 원자 교체 (포인터 swap)`. 진행 중 작업은 옛 설정으로 끝낸다.

**자격 증명**: 오래 도는 프로세스는 토큰·인증서 만료를 만난다. 설정 재적재와 같은 경로 (`파싱 → 검증 → 원자 교체`) 로 다시 읽어 교체한다. 권한 낮추기·자원 제한·접근 제한은 프로세스가 하지 않고 감독자에게 맡긴다 (systemd.exec 설정, k8s `securityContext`) ([daemon(7)](https://man7.org/linux/man-pages/man7/daemon.7.html), [microservice chassis](https://microservices.io/patterns/microservice-chassis.html)).

## 6. 데몬화 (daemonize) — SysV 15단계와 그 이유 ([daemon(7)](https://www.freedesktop.org/software/systemd/man/latest/daemon.html))

감독자 없이 직접 띄워야 하는 드문 경우 (임베디드, 감독자 없는 레거시 호스트) 에만 참고한다. 이때도 BSD `daemon()` 은 일부만 구현하므로 쓰지 않는다.

| # | 단계 | 이유 |
|---|---|---|
| 1 | 0·1·2 외 fd 전부 닫기 | 실수로 물려받은 fd 정리 |
| 2 | 신호 핸들러를 SIG_DFL 로 | 부모가 바꾼 처리 방식을 물려받지 않음 |
| 3 | `sigprocmask()` 로 마스크 초기화 | 막힌 신호 해제 |
| 4 | 해로운 환경변수 정리 | 실행 환경 오염 방지 |
| 5 | `fork()` | 백그라운드로 |
| 6 | `setsid()` | 터미널에서 떼고 새 세션 |
| 7 | 다시 `fork()` | 세션 리더가 아니게 해 TTY 를 다시 얻지 못하게 |
| 8 | 첫 자식 `exit()` | 데몬이 init 에 입양되게 |
| 9 | stdin·stdout·stderr → `/dev/null` | 터미널 I/O 끊기 |
| 10 | `umask(0)` | 넘긴 파일 모드가 그대로 적용되게 |
| 11 | `chdir("/")` | 마운트를 붙잡지 않게 |
| 12 | PID 파일을 경쟁 없이 기록 | 중복 실행 방지 |
| 13 | 권한 낮추기 | 최소 권한 |
| 14 | 첫 fork 전 만든 pipe 로 "초기화 완료" 알림 | 호출자가 준비 완료를 알게 |
| 15 | 원래 프로세스 `exit()` | 호출자 반환 |

지금은 이 모든 것을 감독자가 대신하고 (`sd_notify READY=1` 이 14·15 를, unit 설정이 1~4·9~13 을), 프로세스는 아무것도 하지 않는 것이 규칙이다.
