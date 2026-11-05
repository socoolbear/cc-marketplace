# Chassis — Daemonize (Lifecycle) · Recovery (플랫폼·런타임별)

Lifecycle (시작·종료·신호) 을 플랫폼·런타임별로 다루고, Recovery 는 §7 이다. Live Config 는 `chassis-operations.md` §1. Resource Limits 가 쓰는 런타임별 메모리 상한은 §4 에 있다 (그 밖의 상한·Steady State 는 `chassis-resources.md`).

## 1. Kubernetes

### 종료 순서 ([pod lifecycle](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/), [lifecycle hooks](https://kubernetes.io/docs/concepts/containers/container-lifecycle-hooks/))

1. 삭제 요청 → API 서버에 삭제 기한 기록. **유예 시간 카운트다운이 여기서 시작**
2. kubelet 이 preStop 실행 (동기). 동시에 EndpointSlice 의 해당 엔드포인트를 terminating (ready=false, serving 조건 유지) 으로 표시하고 LB·kube-proxy 가 반영하기 시작
3. preStop 이 끝나면 각 컨테이너 PID 1 에 SIGTERM (컨테이너 간 순서 없음)
4. 유예 시간 (`terminationGracePeriodSeconds`, 기본 30s) 이 끝나면 SIGKILL. preStop 이 유예 시간을 넘기면 2s 를 한 번 더 준다
5. sidecar (restartPolicy Always 인 init container) 는 메인 컨테이너가 모두 끝난 뒤 정의 역순으로 SIGTERM

- **preStop 과 SIGTERM 이후 처리가 같은 유예 시간을 나눠 쓴다.** 연장 수단은 없다
- **엔드포인트 제거 경쟁**: EndpointSlice 갱신과 kubelet 종료가 동시에 진행돼 SIGTERM 뒤에도 잠시 요청이 들어온다. 트래픽을 받는 서버는 preStop 에 내장 sleep 액션 (`lifecycle.preStop.sleep.seconds`, 수 초) 을 두거나 SIGTERM 뒤 수신을 몇 초 더 유지한다. sleep 액션은 `sleep` 바이너리가 없는 distroless 이미지에서도 동작한다 (v1.34 Stable, [KEP-3960](https://www.kubernetes.dev/resources/keps/3960/)). 0초 값도 허용된다 (v1.34, KEP-4818). 트래픽을 받지 않는 소비자·워커는 이 문제가 거의 없다
- 종료 대기만을 위해 readiness 를 둘 필요는 없다 (terminating 엔드포인트는 자동으로 `ready=false`). 다만 terminating 엔드포인트는 EndpointSlice 의 `serving` 조건으로 아직 요청을 받을 수 있는지 드러내므로, Accept 형은 drain 을 시작할 때 readiness 를 실패시켜 `serving=false` 로 만든 뒤 listener 를 닫는다
- **sidecar 시간도 같은 유예 시간 안**: sidecar 는 메인 컨테이너가 끝난 뒤에 멈추지만 같은 유예 시간을 쓰고, 유예 시간이 끝나면 남은 컨테이너가 짧은 유예만 받고 함께 SIGKILL 된다. 종료 예산에 sidecar 정지 시간을 포함한다
- **롤링 배포 중 버전 공존**: 옛 버전과 새 버전이 같은 Source 를 동시에 읽는다. 형식·멱등 키 호환 규칙은 `contract.md` §5

### 노드 종료 ([node shutdown](https://kubernetes.io/docs/concepts/cluster-administration/node-shutdown/))

- 노드가 꺼질 때는 kubelet 의 `shutdownGracePeriod` / `shutdownGracePeriodCriticalPods` 가 일반 파드와 critical 파드에 시간을 나눠 준다. 둘의 기본값은 0 이라 graceful node shutdown 이 꺼져 있다 → 노드 설정이 없으면 유예 없이 죽을 수 있다. 실제 예산이 `terminationGracePeriodSeconds` 보다 짧을 수 있으므로, 예산이 빠듯한 데몬은 짧아져도 Recovery 로 안전해야 한다

### 시작 순서와 워밍업 ([cascading failures](https://sre.google/sre-book/addressing-cascading-failures/))

- 의존 서비스의 시작 순서에 기대지 않는다. 연결은 백오프 재시도로 맺고, 복구할 수 없는 시작 오류 (설정, Position 손상, 상태 잠금 실패) 만 즉시 exit ≠ 0 한다 (의존 장애로 죽으면 재시작 폭주)
- 새 인스턴스에는 부하를 천천히 올린다. 캐시가 빈 상태 (cold cache) 에서도 버텨야 한다 — 워밍업 구간에는 동시성·요청 한도를 낮춘다

### 프로브 ([probes 개념](https://kubernetes.io/docs/concepts/configuration/liveness-readiness-startup-probes/))

| 프로브 | 무엇을 보나 | 하지 말 것 |
|---|---|---|
| startupProbe | 시작·복구 구간이 끝났나. 성공 전에는 liveness·readiness 가 돌지 않는다 | 복구가 오래 걸리는데 생략 (liveness 가 복구 중인 프로세스를 죽인다) |
| liveness | 복구 불가능한 내부 고장 (데드락, 루프 정지) 만 | DB·브로커 연결 확인을 넣기 (의존 장애 → 전체 재시작 폭주) |
| readiness | 지금 일을 받을 수 있나. 그 인스턴스만의 문제 (워밍업, 로컬 포화, draining) 에 쓴다 | 트래픽을 받지 않는 워커에 의미 없이 두기. Sink 같은 공유 의존 장애로 끄기 (모든 파드가 함께 빠져 엔드포인트가 0 이 된다. 대신 readiness 는 유지하고 요청을 503 + Retry-After 로 싸게 거절한다) |

- 스스로 crash 하는 프로세스라면 liveness 가 없어도 된다
- liveness 구현: 메인 루프가 매 회차 `lastTick` 을 갱신하고, 핸들러는 `now - lastTick < 임계` 만 본다

### 재시작

- CrashLoopBackOff: 10s → 20s → 40s … 상한까지 두 배씩, 10분 정상 동작하면 초기화. 상한은 기본 300s, 노드 설정으로 줄일 수 있다 (kubelet `crashLoopBackOff.maxContainerRestartPeriod` 1s~300s, `KubeletCrashLoopBackOffMax` v1.35 Beta 기본 켜짐). 더 짧게 시작하는 `ReduceDefaultCrashLoopBackOffDecay` (1s 시작, 60s 상한) 는 v1.33 Alpha 로 기본 꺼짐. **포기하지 않고 계속 재시도**하므로 "반복 재시작" 은 경보로 따로 잡는다 (`kube_pod_container_status_restarts_total` 증가율) ([pod lifecycle](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/))
- 종료 코드별 재시작 규칙 (`restartPolicyRules`) 은 Job·단발 Pod 용이다. **Deployment 데몬에는 쓰지 않는다** (Failed 파드가 백오프 없이 누적되거나 파드가 교체되지 않는다). 이유와 세부는 `chassis-failure.md` §2. Deployment 데몬은 재시작 + 재시작 반복 경보가 기본이고, 종료 코드별 재시작 제외는 systemd `RestartPreventExitStatus=` 로 한다

### PID 1

- 컨테이너 안 PID 1 은 기본 동작인 신호를 무시한다. 핸들러가 없으면 SIGTERM 으로 죽지 않고 유예 시간 뒤 SIGKILL 된다 ([docker run](https://docs.docker.com/reference/cli/docker/container/run/))
- exec form `CMD ["node", "dist/main.js"]` 로 앱을 PID 1 로. `CMD node dist/main.js` (shell form) 나 `npm start` 래퍼는 중간 `sh -c` 때문에 신호가 앱까지 닿지 않을 수 있다 (npm 자체는 SIGINT·SIGTERM 을 자식에게 넘기지만 좀비 회수는 없다)
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
StartLimitIntervalSec=120   # 빠른 crash 가 약 1분 이어지면 포기 (조건: chassis-failure.md §2). 무한 재시작이면 0
StartLimitBurst=5
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

`Type=notify-reload` 는 v262 부터 첫 `READY=1` 시점에 메인 프로세스가 reload 신호 (기본 SIGHUP) 를 처리할 준비가 됐는지 확인하고, 안 됐으면 시작을 중단한다. sigaction 핸들러와 신호 차단 후 signalfd 둘 다 통과한다 ([systemd.service](https://github.com/systemd/systemd/blob/main/man/systemd.service.xml), systemd NEWS 262). 규칙: **`READY=1` 보다 먼저 SIGHUP 처리 (핸들러 또는 차단 + signalfd) 를 준비한다**.

소켓을 직접 listen 하는 Accept 형은 socket activation 과 `FDSTORE=1` 로 listen 소켓을 재시작 사이에 보존한다 ([daemon(7)](https://man7.org/linux/man-pages/man7/daemon.7.html)).

## 3. k8s 와 systemd 의 차이

| 항목 | Kubernetes | systemd |
|---|---|---|
| 건강 확인 | kubelet 이 묻는다 (pull: probe) | 프로세스가 알린다 (push: `READY`·`WATCHDOG`) |
| 종료 시간 연장 | 불가 | `EXTEND_TIMEOUT_USEC` |
| 재시작 간격 | CrashLoopBackOff: 10s 에서 두 배씩, 기본 상한 300s (노드 설정으로 축소) | 기본 `RestartSec` 100ms. `RestartSteps=`·`RestartMaxDelaySec=` 로 지수 증가 |
| 재시작 포기 | 안 함 (상한 간격으로 무한) | 첫 시작부터 Burst+1 번째 시작까지 걸린 시간 (간격 합 + 실행 시간 합) 이 `StartLimitIntervalSec` 이하일 때 포기 (`chassis-failure.md`) |
| 설정 재적재 | 보내는 주체 없음 → 파일 감시 또는 롤링 재시작 | `Type=notify-reload` + SIGHUP |

두 환경을 다 지원하려면 내부 heartbeat 하나를 두 경로 (HTTP `/healthz` 와 `WATCHDOG=1`) 로 내보낸다.

## 4. 런타임별 종료 관용구

### Go

```go
ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
defer stop()
g, gctx := errgroup.WithContext(ctx)          // 하나가 실패하면 모두 취소 (OTP one_for_all 과 비슷)
// 루프 안 Sink 쓰기·drain·최종 커밋은 gctx 가 아니라 이 workCtx 하나를 쓰고, gctx 는 batch 사이 `stopping` 확인에만 쓴다.
// 기한은 종료 신호 시점부터 센다: 루프 시작 때 WithTimeout 을 걸면 기동 후 drainBudget 이 지나 모든 쓰기가 취소되고,
// drain 용 ctx 를 따로 만들면 기한이 겹쳐 예산이 최대 2배가 된다. 취소된 ctx 로 쓰기·커밋하면 즉시 실패해 배포마다 중복이 생긴다 (Go 1.21+)
workCtx, cancelWork := context.WithCancel(context.WithoutCancel(gctx))
defer cancelWork()
context.AfterFunc(gctx, func() { time.AfterFunc(drainBudget, cancelWork) })
consumerDone := make(chan struct{})
g.Go(func() error {
    defer close(consumerDone)
    if err := consumer.Run(gctx, workCtx); err != nil { return err }
    if gctx.Err() == nil { return errors.New("consumer exited") } // 종료 신호 없이 nil 로 끝남 (Source 닫힘 등) = 비정상. 안 그러면 admin 서버만 남아 "healthz 는 OK, 소비자는 죽음"
    return nil
})
g.Go(func() error {                           // /healthz /readyz /metrics
    // Shutdown 직후 ErrServerClosed 가 즉시 반환된다. 그대로 넘기면 정상 SIGTERM 도 exit 1
    if err := adminServer.ListenAndServe(); !errors.Is(err, http.ErrServerClosed) {
        return err
    }
    return nil
})
g.Go(func() error {
    select { case <-gctx.Done(): case <-consumerDone: }
    stop()                                   // 두 번째 신호는 즉시 종료 (signal.NotifyContext 문서 패턴)
    <-consumerDone                           // consumer 가 끝난 뒤에 닫는다: drain 동안 /metrics·/healthz 유지
    sctx, cancel := context.WithTimeout(context.Background(), 2*time.Second) // consumer 가 끝난 뒤라 짧게. preStop + drainBudget + 이 값 ≤ 유예 시간
    defer cancel()
    return adminServer.Shutdown(sctx)        // 기한 없으면 무기한 대기
})
if err := g.Wait(); err != nil && !errors.Is(err, context.Canceled) { os.Exit(1) }
```

- `GOMEMLIMIT` 은 컨테이너 limit 의 90~95% ([GC guide](https://go.dev/doc/gc-guide)). 관례값이다
- Go 1.25 부터 `GOMAXPROCS` 가 컨테이너를 인식한다: Linux 에서 cgroup CPU limit 을 따르고 주기적으로 다시 계산하며, CPU request 는 무시한다 ([Go 1.25](https://go.dev/doc/go1.25)). 1.24 이하는 직접 설정한다 (`automaxprocs` 등)
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
- Spring Boot ([3.4 릴리스 노트](https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-3.4-Release-Notes), [graceful shutdown](https://docs.spring.io/spring-boot/reference/web/graceful-shutdown.html)): 3.4 부터 `server.shutdown=graceful` 이 기본이다 (끄려면 `immediate`). `spring.lifecycle.timeout-per-shutdown-phase` 기본 30s. 웹 서버 graceful 종료의 phase 는 `SmartLifecycle.DEFAULT_PHASE - 1024` 다. 정지는 phase 가 높은 것부터라 기본 phase (`Integer.MAX_VALUE`) 의 사용자 `SmartLifecycle` 빈과 spring-kafka 리스너 컨테이너 (`MAX_VALUE - 100`) 가 웹 graceful 종료보다 먼저 멈춘다. `timeout-per-shutdown-phase` 는 phase 마다 적용되므로 (phase 수 × 값) 이 `terminationGracePeriodSeconds` 안인지 확인한다. 웹이 아닌 워커는 `SmartLifecycle.stop(callback)` 에서 drain 하고 phase 로 순서를 명시한다

### Python

- 주기적 `gc.collect()` 는 누수를 가릴 뿐이다. 누수는 `tracemalloc` 로 찾는다 ([gc](https://docs.python.org/3/library/gc.html))
- 메모리 상한 설정이 없으므로 cgroup limit + 처리 N 건마다 자기 재시작 (`max-requests` 류) 으로 대신한다
- `signal.signal` 핸들러는 메인 스레드에서만 실행된다. asyncio 면 `loop.add_signal_handler`

## 6. 데몬화 (daemonize) — SysV 15단계와 그 이유 ([daemon(7)](https://www.freedesktop.org/software/systemd/man/latest/daemon.html))

감독자 없이 직접 띄워야 하는 드문 경우 (임베디드, 감독자 없는 레거시 호스트) 에만 참고한다. 이때도 BSD `daemon()` 은 일부만 구현하므로 쓰지 않는다.

| 단계 | 이유 |
|---|---|
| 0·1·2 외 fd 닫기, 신호 핸들러를 SIG_DFL 로, `sigprocmask()` 초기화, 해로운 환경변수 정리 (1~4) | 부모에게서 물려받은 상태 제거 |
| `fork()` → `setsid()` → 다시 `fork()` → 첫 자식 `exit()` (5~8) | 백그라운드로, 터미널에서 떼고, 세션 리더가 아니게 해 TTY 를 다시 얻지 못하게, init 에 입양 |
| stdin·stdout·stderr → `/dev/null`, `umask(0)`, `chdir("/")` (9~11) | 터미널 I/O 끊기, 파일 모드 그대로 적용, 마운트를 붙잡지 않기 |
| PID 파일을 경쟁 없이 기록, 권한 낮추기 (12~13) | 중복 실행 방지, 최소 권한 |
| 첫 fork 전 만든 pipe 로 "초기화 완료" 알림, 원래 프로세스 `exit()` (14~15) | 호출자가 준비 완료를 알고 반환 |

지금은 이 모든 것을 감독자가 대신하고 (`sd_notify READY=1` 이 14·15 를, unit 설정이 1~4·9~13 을), 프로세스는 아무것도 하지 않는 것이 규칙이다.

## 7. Recovery

복구 코드를 따로 두지 않고 시작할 때마다 같은 경로를 탄다. 정상 종료와 `kill -9` 가 같은 결과가 되게 만든다.

### 시작 경로

| 단계 | 하는 일 | 실패하면 |
|---|---|---|
| recovering | 상태 디렉토리 잠금, Position 복원, 버퍼 열기 | Position 이 손상됐으면 exit ≠ 0 (시작점이 임의가 되면 안 된다. 사람이 정한다: `chassis-operations.md` §3). 잠금을 못 잡아도 exit ≠ 0. 원격 Position 저장소의 연결 실패는 §1 대로 백오프 재시도한다 (exit 하면 DB 장애가 재시작 폭주가 된다). startupProbe 가 연결 대기까지 기다리면 장애 동안 재시작되므로, 프로세스 기동과 로컬 복구까지만 startupProbe 로 보고 연결 대기는 지표·`health()` 로 드러낸다 (readiness 는 §1 규칙대로 유지하고 요청은 싸게 거절한다) |
| recovering | 손상된 데이터 항목을 격리 폴더로 옮기고 경보 | 격리하고 계속한다. 서버 전체가 멈추지 않게 한다. 손상을 조용히 버리거나 자동 재생성하지 않는다 (`io.md` §3) |
| ready | 버퍼에 남은 항목 전송은 **ready 뒤에 평소 경로로** 처리 | 남은 양이 많아도 readiness 를 끄지 않는다 (recovering 이 길어지면 서버가 빠진다) |

손상 처리 선례: Fluent Bit 는 손상 청크를 오류 로그 뒤 폐기하고 ([buffering](https://github.com/fluent/fluent-bit-docs/blob/master/pipeline/buffering.md)), Vector 는 복구 가능한 이벤트만 복구하고 지표를 낸다 ([buffering model](https://vector.dev/docs/architecture/buffering-model/)).

### 디스크 버퍼는 상시 경로다

연결이 끊겼을 때만 로컬에 백업하는 구조는 평소 타지 않는 경로라 장애 때 처음 실행된다 (`chassis-failure.md` §3). 모든 항목이 디스크 버퍼를 지나게 하면 "복구 데이터" 라는 별도 범주가 사라진다. 재시작은 버퍼의 남은 위치부터 이어 갈 뿐이다 (Vector disk buffer, OTel persistent queue, Fluent Bit filesystem storage). 수집 서버가 Sink 장애에 대비해 로컬 스풀을 둘 때도 같다. 스풀 기록 뒤 "저장 확정" 을 응답하면 스풀이 곧 Sink 이므로 그 디스크의 내구성이 계약이 된다 (k8s 면 PV).

### 남은 항목과 새 항목의 순서

**Sink 의 순서 제약으로 고른다.** 기본 규칙은 없다.

| Sink 요구 | 선택 | 근거 |
|---|---|---|
| 시간 순서 필수 | 오래된 것부터 (FIFO). 새 항목은 뒤에서 기다린다 | Prometheus remote write 는 시계열별 시간 순서 MUST ([규격](https://prometheus.io/docs/specs/prw/remote_write_spec_2_0/)). Loki 는 너무 오래된 항목을 `too_far_behind` 로 거부 ([설정](https://github.com/grafana/loki/blob/main/docs/sources/shared/configuration.md)) → 보관 기간이 Sink 수용 범위 안인지도 본다 |
| 신선도 우선 | 새 항목 먼저, 남은 것은 별도 큐로 낮은 속도 | 적체 회복 (`io.md` §1) |
| 순서 무관 | 병렬. 멱등만 지킨다 | OTel persistent queue 는 처리 중이던 항목을 큐 뒤로 보내고 소비자도 여럿이라 순서를 약속하지 않는다 ([소스](https://github.com/open-telemetry/opentelemetry-collector/blob/main/exporter/exporterhelper/internal/queue/persistent_queue.go)) |

순서를 약속했다면 쓰는 도구가 지키는지 확인한다 (Vector overflow 버퍼는 순서 보장이 없다).

### 복구 전송 속도

장애가 풀린 직후가 가장 위험하다. 최대 병렬도·속도에 상한을 두고 (Prometheus `max_shards`, [remote write](https://github.com/prometheus/docs/blob/main/docs/practices/remote_write.md)) 지터로 시작 시각을 흩는다 (`transfer.md` §5). 초과분을 버리는 제한기는 쓰지 않는다 (Filebeat `rate_limit` 은 버린다, [문서](https://www.elastic.co/docs/reference/beats/filebeat/rate-limit)).

### 복구를 드러낸다

복구 시작·종료를 이벤트로 남기고 재시작 횟수, 버퍼에 남은 양, 격리 항목 수, 복구 소요 시간을 지표로 낸다. 사람에게 알릴지는 Emergency Notification 규칙을 따른다 (`chassis-observability.md` §2). 복구가 길면 startupProbe 로 보호한다 (§1).
