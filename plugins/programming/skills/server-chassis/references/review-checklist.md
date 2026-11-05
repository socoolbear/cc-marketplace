# 리뷰 점검 목록

기존 서버나 PR 을 리뷰할 때 이 순서로 본다. 항목마다 카탈로그 상세 열의 reference 에서 `핵심 규칙` 과 해당 절을 함께 본다.

1. **Failure Handling**: 처리 콜백의 예외가 어디서 잡히는가 — 잡고 로그만 남긴 뒤 정상 반환하면 유실. RabbitMQ 4.3+ 에서 `nack(requeue=true)` 만 쓰면 독성 메시지가 DLQ 로 가지 않고 무한히 돈다. Sink 전체 장애 (SinkDown) 를 메시지별 실패로 세거나 메시지를 반환해 브로커 전달 횟수를 써서 DLQ 로 보내지 않는가
2. **Contract — 확인 응답 순서**: auto-commit/auto-ack 인가 (auto-commit 이면 offset store 를 수동으로 하는가, Kafka share group 이면 `share.acknowledgement.mode=explicit` 인가), Sink 쓰기 뒤인가. 리밸런스·소유권 상실 시 처리. Backpressure 로 받아 온 batch 를 버리지 않는가
3. **Contract — 멱등 키**: Sink 쓰기가 멱등인가, 멱등 키가 결정적인가, Dedup Window 가 충분한가, 키 계산식이 버전 간에 같은가, 스키마 호환 모드와 배포 순서가 맞는가
4. **Overload Protection**: 모든 원격 호출에 타임아웃이 있는가, 재시도가 여러 층에서 겹치지 않는가, Accept 형이면 부하 차단이 있는가 (실행 모델 함정: 이벤트 루프 블로킹, master-worker 신호, 프록시 idle timeout — `io.md` §7)
5. **Lifecycle**: 종료 훅이 실제로 등록되는가 (NestJS `enableShutdownHooks()`, Go `signal.NotifyContext`, Spring Boot 의 graceful 설정과 웹이 아닌 워커의 drain — `chassis-lifecycle.md` §4), 예산 안에 끝나는가
6. **Resource Limits**: 큐·배치·동시성 상한 (병렬 단위가 순서 요구와 맞는가, 최대 인스턴스 수 × 인스턴스당 연결 풀이 하류 허용치 안인가, 이벤트 루프를 막는 CPU 작업이 없는가), 외부 엔티티 수에 비례하는 메모리, 프로세스 밖 누적물의 정리 주기
7. **Observability**: liveness 에 외부 의존이 섞였는가, 비활성 기능이 드러나는가, 사라짐 경보가 `up == 0` 도 잡는가
8. **Coordination·Verification**: 락 해제가 원자적인가, TTL < 작업 시간일 때 대책. 크래시 지점 시험이 있는가
9. **컴포넌트 경계**: 플랫폼이 주는 것을 다시 만들지 않았는가, 구현체가 하나뿐인 층이 있는가, 플러그인이 확인 응답을 쥐거나 오류를 삼키는가, 재적재 실패에 옛 설정이 유지되는가, 경보가 본체 밖에서 나는가
10. **Protocol Handler**: read 경계를 메시지 경계로 가정하는가, 프레임 상한이 받기 전에 걸리는가, 느린 수신자가 전달 경로를 막는가, 응용 heartbeat 가 있는가
