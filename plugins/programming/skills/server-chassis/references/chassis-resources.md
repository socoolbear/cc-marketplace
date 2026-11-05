# Chassis — Resource Limits · GC

Resource Limits 는 프로세스 안의 상한이다. GC 는 쌓인 것을 치우는 일로, §3 이 프로세스 안, §2 Steady State 가 프로세스 밖이다. 런타임별 메모리 상한 설정값은 `chassis-lifecycle.md` §4 에 있다.

## 1. 상한

- 모든 버퍼·큐·동시성에 상한과 가득 찼을 때 정책 (block = Source 일시 정지 / drop) 을 명시한다. 상세: `io.md` §3
- 외부 개체 수 (고객, 테넌트, 키) 에 비례해 늘어나는 메모리 상태를 두지 않는다

런타임별 설정 (Go `GOMEMLIMIT`·`GOMAXPROCS`, Node `--max-old-space-size[-percentage]`, JVM `MaxRAMPercentage`) 과 버전 조건은 `chassis-lifecycle.md` §4.

- 주기적 GC 호출로 누수를 가리지 않는다 (§3)
- fd 수와 연결 수에 상한을 두고 지표로 내보낸다 (`chassis-observability.md`)

## 2. Steady State

Nygard 의 steady state 패턴 (Release It! 2판, 2018) 과 SRE workbook 의 데이터 처리 장 (TTL, 주기적 정리) 에서 온 원칙이다 ([SRE workbook](https://sre.google/workbook/data-processing/)). **프로세스 밖에 쌓이는 것은 모두 TTL 또는 정리 주기가 필요하다.**

- DLQ
- 멱등 키 테이블, inbox/outbox 테이블, 처리 끝난 작업 행
- 디스크 버퍼, 체크포인트 파일 (확정된 것만 지운다. 미전송분을 TTL 로 지우면 유실이다. 미전송분은 크기 상한과 가득 찼을 때 정책으로 다룬다)
- 임시 저장소 (개인정보가 들어 있을 수 있다)
- 로컬 로그 파일

정리 TTL 은 Dedup Window 요구보다 길어야 한다. 기준은 최대 재처리 지연이며 DLQ 재투입·재생 (replay) 을 포함한다 (`contract.md`). 크기·행 수를 지표로 내보내고 증가에 경보를 건다 (`chassis-observability.md`).

## 3. GC — 프로세스 안 회수

오래 도는 프로세스의 메모리 대책은 순서가 있다. 앞 단계로 안 될 때만 다음으로 간다.

1. **상한을 알린다.** 런타임이 컨테이너 한도를 알게 한다 (`chassis-lifecycle.md` §4). Go `GOMEMLIMIT` 은 soft 라 5~10% 여유를 둔다 ([GC guide](https://go.dev/doc/gc-guide))
2. **누수를 고친다.** tracemalloc·pprof·heap dump 로 원인을 찾고, soak 로 평탄함을 증명한다 (`verification.md`)
3. **RSS 가 안 줄면 할당자를 본다.** 힙은 작은데 RSS 가 크면 누수가 아니라 단편화일 수 있다. glibc arena 는 많을수록 경합이 줄고 메모리는 는다 (`MALLOC_ARENA_MAX`, [mallopt(3)](https://man7.org/linux/man-pages/man3/mallopt.3.html)). jemalloc 은 decay 설정이 있다
4. **임시 완화: 워커 재활용.** 서드파티 누수처럼 당장 못 고칠 때만 쓴다. N 건 또는 RSS 기준으로 워커를 바꾼다 (Gunicorn `max_requests` + `max_requests_jitter`, [settings](https://gunicorn.org/reference/settings/), PHP-FPM `pm.max_requests`, uWSGI `reload-on-rss`). 지터가 없으면 워커가 동시에 재시작한다. 재활용 횟수를 지표로 내고 원인 수정 항목으로 남긴다

**명시적 GC 호출**은 기본이 금지다. Java 공식 가이드는 `System.gc()` 를 피하라고 하고 ([문서](https://docs.oracle.com/en/java/javase/25/gctuning/other-considerations.html)), Go `runtime.GC()` 는 호출자를 막고 프로그램 전체를 막을 수도 있다 ([runtime](https://pkg.go.dev/runtime#GC)). 예외는 측정으로 효과를 증명한 경우다. 소규모 서버에는 의미가 없고, 부하 구간에서 돌리면 지연을 만든다.

- Python 은 pre-fork 서버면 부모에서 `gc.disable()` → fork 직전 `gc.freeze()` → 자식에서 `gc.enable()` 로 copy-on-write 를 줄인다 ([gc](https://docs.python.org/3/library/gc.html))
- Python 3.14 의 증분 GC 는 메모리 압박 보고로 3.14.5 에서 세대별 GC 로 되돌려졌다 ([What's New](https://docs.python.org/3/whatsnew/3.14.html)). 3.14.0~3.14.4 에서 메모리가 늘면 올린다
