# Verification — 시험

| 시험 | 방법 | 통과 기준 |
|---|---|---|
| 크래시 지점 | Sink 쓰기 직전·직후, 확인 응답 직전, 체크포인트 fsync 전에 `kill -9` (환경변수·실패 주입 훅으로 지점 지정) | 재시작 후 누락 0, 중복은 Sink 에서 흡수 (Sink 건수 = Source 고유 건수) |
| graceful shutdown | 처리 중 SIGTERM | 유예 시간 안에 exit 0, 진행 중 항목 손실 없음, 확인 응답 일치 |
| 하류 장애 | [Toxiproxy](https://github.com/Shopify/toxiproxy) 로 장애 주입 (down 은 `enabled=false`, toxic 이 아니다. toxic: latency, timeout, reset_peer, bandwidth, slow_close, slicer, limit_data. v2.12.0 기준 보관 안 됨) | 메모리 상한 안에서 Backpressure, 복구 후 자동 재개, 재시도 지표 증가 |
| 독성 입력 | 깨진 입력을 섞어 넣기 | DLQ 로 가고 뒤 항목은 계속 처리 |
| 리밸런스 | 처리 중 인스턴스 추가·제거 | 중복은 흡수, 누락 0 |
| 장시간 부하 (soak) | 수 시간 이상 부하 | RSS·fd·goroutine 평탄, 처리 시간 p99 안정 |
| 과부하 | 한계 이상 부하 | load shedding 이 싸게 거절, 받아들인 요청의 지연은 유계, 크래시 없음 (`chassis-overload.md` §3) |
| 버전 공존 | 스트림 중간에 신·구 인스턴스를 섞어 롤링 배포 | 누락 0, 중복은 흡수 (`contract.md` §5) |
| 종단 간 대사 | golden data, 발행 건수 vs 전달 건수 비교 | 건수·내용 일치 (`contract.md` §5) |
| 시작 = 복구 | 미완료 상태를 만들어 두고 시작 | startupProbe 구간 안에 복구 완료, 이후 정상 처리 |

- 시계·sleep·I/O 를 인터페이스로 빼 두면 가짜 시계로 타임아웃·백오프·lease 만료를 빠르게 시험할 수 있다. 결정적 시뮬레이션 (FoundationDB, TigerBeetle VOPR) 은 이 방향의 극단이다. [Antithesis](https://antithesis.com/docs/resources/deterministic_simulation_testing/) 는 결정적 하이퍼바이저로 블랙박스 상태에서 코드 수정 없이 같은 효과를 낸다. TigerBeetle 의 [protocol-aware DST](https://tigerbeetle.com/blog/2026-08-20-protocol-aware-dst) 글도 참고. 동시성 이력은 Jepsen 식 이력 검사 (Elle 등) 로 일관성 위반을 찾을 수 있다
- 크래시 지점 시험은 CI 에서 돌릴 수 있게 docker compose (Source + Sink + 데몬) 로 묶는다. 대안으로 [Testcontainers](https://testcontainers.com/) 를 쓰면 크래시 지점 시험을 테스트 코드 안에서 돌릴 수 있다
