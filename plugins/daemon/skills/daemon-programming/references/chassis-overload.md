# Chassis — Overload Protection

과부하는 재시도와 대기열을 타고 연쇄 장애로 번진다. Nygard (Release It!: timeout, circuit breaker, bulkhead, 부하 차단), Google SRE (handling overload, cascading failures), AWS Builders' Library 가 모두 이를 핵심 주제로 다룬다. 여기는 그 상세다.

## 1. Timeouts & Deadlines

- 모든 원격 호출 (같은 호스트의 IPC 포함) 에 연결 timeout 과 요청 timeout 을 둔다
- 값은 추측이 아니라 허용 가능한 오탐 timeout 비율에서 정한다 (예: 하위 서비스 p99.9 지연) ([AWS](https://builder.aws.com/content/3EumjoZascWd1oZiEgL8ORlv3qE/timeouts-retries-and-backoff-with-jitter))
- Accept 형: 남은 deadline 을 하위 호출로 전파하고, 클라이언트가 이미 포기한 요청은 처리하지 않고 버린다 ([SRE](https://sre.google/sre-book/addressing-cascading-failures/))

## 2. 재시도 예산

- 여러 계층에서 재시도하면 곱해진다 (AWS 예: 5계층 × 시도 3회 = 243배). **재시도는 거절한 계층의 바로 위 (그 계층을 직접 부른 쪽) 한 곳에서만** 한다
- 재시도량에 상한을 둔다: 토큰 버킷 또는 요청 대비 비율 (예: 10% 이하)
- 하위 서비스가 "과부하, 재시도 말 것" 을 알리면 재시도하지 않는다 ([SRE](https://sre.google/sre-book/handling-overload/))
- 지수 백오프에 지터를 더한다. 주기 타이머에도 지터를 둔다
- 재시도율을 지표로 내보내고 급증에 경보를 건다 (`chassis-observability.md`)
- AWS 의 견해: circuit breaker 는 동작 모드가 갈려 테스트하기 어렵고 복구를 늦출 수 있어 토큰 버킷을 선호한다 ([AWS](https://builder.aws.com/content/3EumjoZascWd1oZiEgL8ORlv3qE/timeouts-retries-and-backoff-with-jitter))

## 3. 부하 차단·승인 제어

Accept 형 기준이다. Pull 형의 대응물은 Backpressure (Source 일시 정지) 이며 `io.md` §1 (브로커별 Backpressure 수단) 과 SKILL.md 처리 루프에 있다. 디스크 버퍼가 찼을 때의 정책은 `io.md` §3.

- 포화 **전에** 싸게 거절한다. 포화된 뒤에는 거절 자체가 비싸다 ([AWS](https://builder.aws.com/content/3Eun1EEyX6p2e3VYNyRLSJzLuMV/using-load-shedding-to-avoid-overload))
- 헬스 체크와 진행 중인 작업을 끝내는 요청을 우선한다
- 대기열에서 기다릴 수 있는 시간에 상한을 두고, 너무 오래 기다린 요청은 버린다 (LIFO, CoDel 방식) ([SRE](https://sre.google/sre-book/addressing-cascading-failures/))
- 숨은 큐 (스레드 풀, 소켓 accept backlog) 도 한도에 포함한다
- 한계점을 넘기는 부하 시험으로 확인한다 (`verification.md`)
- Accept 서버 상세: `io.md` §5

## 4. Bulkheads·테넌트 격리

- 워크로드·테넌트별로 동시성 상한과 풀을 나눠, 한 테넌트의 적체가 전체를 막지 않게 한다 (noisy neighbor) ([AWS](https://builder.aws.com/content/3EuRcgkTP1MI0c7zM8W6HL3WIqA/avoiding-insurmountable-queue-backlogs))
- 테넌트별 속도 제한을 두고 넘친 분량은 별도 spillover 큐로 보낸다
- shuffle sharding 으로 장애 영향 범위를 줄인다 ([AWS](https://builder.aws.com/content/3F06NpJ8YeoIGP8VHTw4n81pFn8/workload-isolation-using-shuffle-sharding))
- 우선순위가 높은 데이터는 큐·작업을 분리한다 ([SRE workbook](https://sre.google/workbook/data-processing/))
- 관리형 선택지: SQS fair queues (`io.md` §1)
