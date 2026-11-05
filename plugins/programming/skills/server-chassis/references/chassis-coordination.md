# Chassis — Coordination (단일 실행)

스케줄러·마감 작업처럼 "하나만 돌아야 하는 일" 에만 둔다. 스케줄 자체 (CronJob·상주 폴러) 는 `io.md` §4.

## 1. 분산 락

- **한계** ([Kleppmann](https://martin.kleppmann.com/2016/02/08/how-to-do-distributed-locking.html)): GC·멈춤 사이 TTL 이 만료되면 둘이 동시에 락을 쥔다
  - 효율 목적 (중복 실행해도 결과는 같고 낭비만 막음): 단일 Redis `SET key token NX PX ttl` + **원자적 해제**. Redis OSS 8.4+ 는 `DELEX key IFEQ <token>` (해제), `SET key <token> IFEQ <token> PX ttl` (TTL 연장), Valkey 8.1+ 는 `SET … IFEQ` (연장), 9.0+ 는 `DELIFEQ key <token>` (해제), 그 밖은 Lua ([DELEX](https://redis.io/docs/latest/commands/delex/), [8.4 commands](https://redis.io/docs/latest/commands/redis-8-4-commands/), [DELIFEQ](https://valkey.io/commands/delifeq/))
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
- 세션 수준 락은 앱 커넥션 풀 (pgx pool, HikariCP) 에서도 깨진다. 같은 세션의 재획득은 항상 성공 (중첩 카운트) 하고, 다른 커넥션에서 unlock 하면 false+경고로 락이 남고, 커넥션이 끊기면 락이 조용히 풀린다 ([functions-admin](https://www.postgresql.org/docs/current/functions-admin.html))
- 규칙: **전용 커넥션 하나를 고정**해 획득·감시·해제를 모두 그 커넥션에서 한다. 커넥션이 끊기면 락 상실로 보고 작업을 중단한다
  - 락 커넥션은 작업 내내 idle 이라 서버 `idle_session_timeout` 에 끊기면 락이 풀린다 → 그 role 에서 끄고, 락 커넥션으로 주기적 확인 쿼리를 보낸다 (주기 = 겹침 허용 시간) ([client](https://www.postgresql.org/docs/current/runtime-config-client.html))
  - 보유 호스트가 죽거나 반쯤 열린 연결이면 서버 TCP keepalive 가 끊김을 잡을 때까지 락이 남는다 (`tcp_keepalives_idle` 기본 0 = OS 기본값) → `tcp_keepalives_*`·`tcp_user_timeout` 을 짧게 ([connection](https://www.postgresql.org/docs/current/runtime-config-connection.html))
- 트랜잭션 수준 `pg_try_advisory_xact_lock` 은 작업 내내 트랜잭션을 열어야 해서 긴 작업이면 idle in transaction·vacuum 지연이 생기고, `idle_in_transaction_session_timeout` 에 걸리면 락을 잃는다. 짧은 작업에만 쓴다. 긴 작업은 PgBouncer 를 거치지 않는 직접 연결의 세션 락 (위 규칙) 이나 lease 행 + fencing 을 쓴다
- §1 과 같은 한계: 효율 목적에는 충분하지만 정확성에는 fencing·멱등이 필요하다
