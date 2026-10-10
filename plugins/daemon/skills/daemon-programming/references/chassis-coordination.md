# Chassis — Coordination (단일 실행)

스케줄러·마감 작업처럼 "하나만 돌아야 하는 일" 에만 둔다. 스케줄 자체 (CronJob·상주 폴러) 는 `io.md` §4.

## 1. 분산 락

- **한계** ([Kleppmann](https://martin.kleppmann.com/2016/02/08/how-to-do-distributed-locking.html)): GC·멈춤 사이 TTL 이 만료되면 둘이 동시에 락을 쥔다
  - 효율 목적 (중복 실행해도 결과는 같고 낭비만 막음): 단일 Redis `SET key token NX PX ttl` + **원자적 해제**. Redis OSS 8.4+ 는 `DELEX key IFEQ <token>` (해제), `SET key <token> IFEQ <token> PX ttl` (TTL 연장), 그 이전은 Lua ([DELEX](https://redis.io/docs/latest/commands/delex/), [8.4 commands](https://redis.io/docs/latest/commands/redis-8-4-commands/)). Redis Cloud·Software 지원 여부는 문서마다 다르다
    ```lua
    if redis.call("get", KEYS[1]) == ARGV[1] then return redis.call("del", KEYS[1]) else return 0 end
    ```
    `get` 후 `delete` 를 따로 부르면 그 사이 만료·재획득된 남의 락을 지운다
  - 정확성 목적: 단조 증가 **fencing token** 을 발급하고 쓰기 대상이 더 낮은 토큰의 쓰기를 거부. 또는 작업 자체를 멱등으로
  - 작업 시간이 TTL 을 넘을 수 있으면 heartbeat 로 TTL 연장, 연장 실패 시 작업 중단

## 2. 리더 선출

- **리더 선출** (k8s Lease, client-go `leaderelection`): 코어 컴포넌트 관례값 LeaseDuration 15s / RenewDeadline 10s / RetryPeriod 2s. 문서는 "Core clients default this value to 15 seconds" 라고만 하고 `LeaderElectionConfig` 에는 기본값이 없다 → 직접 설정해야 한다. 라이브러리 문서가 **펜싱을 보장하지 않는다**고 명시 ("does not guarantee that only one client is acting as a leader (a.k.a. fencing)") → 리더를 잃는 콜백에서 즉시 작업 중단 + 쓰기 쪽 펜싱·멱등 ([leaderelection](https://pkg.go.dev/k8s.io/client-go/tools/leaderelection))
  - `OnStoppedLeading` 은 리더가 된 적이 없어도 항상 호출된다 → 콜백이 "리더였음" 을 가정하지 않게 한다
  - `ReleaseOnCancel` 을 쓰면 보호 대상 작업을 먼저 끝낸 뒤에 context 를 취소해야 한다
  - Coordinated Leader Election (KEP-4355) 은 컨트롤 플레인 전용이라 앱 데몬에는 해당하지 않는다

## 3. PostgreSQL advisory lock

- 이미 PG 를 쓰는 데몬이면 `pg_try_advisory_lock` 이 가장 쉬운 단일 실행 수단이다 ([advisory locks](https://www.postgresql.org/docs/current/explicit-locking.html#ADVISORY-LOCKS))
- 세션 수준 락은 PgBouncer transaction pooling 에서 깨질 수 있다 (주의). 트랜잭션 수준 `pg_try_advisory_xact_lock` 이나 직접 연결을 쓴다
- §1 과 같은 한계: 효율 목적에는 충분하지만 정확성에는 fencing·멱등이 필요하다
