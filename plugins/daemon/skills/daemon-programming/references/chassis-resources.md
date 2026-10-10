# Chassis — Resource Limits · Steady State

Resource Limits 는 프로세스 안의 상한, Steady State 는 프로세스 밖에 쌓이는 것의 정리 주기다. 런타임별 메모리 상한 설정값은 `chassis-lifecycle.md` §4 에 있다.

## 1. 상한

- 모든 버퍼·큐·동시성에 상한과 가득 찼을 때 정책 (block = Source 일시 정지 / drop) 을 명시한다. 상세: `io.md` §3
- 외부 개체 수 (고객, 테넌트, 키) 에 비례해 늘어나는 메모리 상태를 두지 않는다
- 런타임에 메모리 상한을 알린다 (`chassis-lifecycle.md` §4)

| 런타임 | 설정 |
|---|---|
| Go | `GOMEMLIMIT`. Go 1.25 부터 `GOMAXPROCS` 가 컨테이너 CPU 제한을 인식 |
| Node | `--max-old-space-size-percentage` 또는 `--max-old-space-size` |
| JVM | `MaxRAMPercentage` |

- 주기적 GC 호출로 누수를 가리지 않는다. 원인을 찾고 (tracemalloc, pprof) 장시간 부하 시험 (soak) 으로 메모리가 평탄한 것을 증명한다 (`verification.md`)
- fd 수와 연결 수에 상한을 두고 지표로 내보낸다 (`chassis-observability.md`)

## 2. Steady State

Nygard 의 steady state 패턴 (Release It! 2판, 2018) 과 SRE workbook 의 데이터 처리 장 (TTL, 주기적 정리) 에서 온 원칙이다 ([SRE workbook](https://sre.google/workbook/data-processing/)). **프로세스 밖에 쌓이는 것은 모두 TTL 또는 정리 주기가 필요하다.**

- DLQ
- 멱등 키 테이블, inbox/outbox 테이블, 처리 끝난 작업 행
- 디스크 버퍼, 체크포인트 파일
- 임시 저장소 (개인정보가 들어 있을 수 있다)
- 로컬 로그 파일

정리 TTL 은 Dedup Window 요구보다 길어야 한다. 기준은 최대 재처리 지연이며 DLQ 재투입·재생 (replay) 을 포함한다 (`contract.md`). 크기·행 수를 지표로 내보내고 증가에 경보를 건다 (`chassis-observability.md`).
