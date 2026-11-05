---
type: llm
criteria: "파트너 장애 동안 소비를 멈추는 장치(서킷 브레이커 + 파티션 pause 등)를 두되, 대기 중에도 소비자 그룹에서 쫓겨나 리밸런스·중복이 나지 않게 하는가?"
---
통과: 서킷 브레이커가 열리면 `pause()`(Java·KafkaJS) / `PauseFetchPartitions`(franz-go) 등으로 fetch 를 멈추고 poll 은 계속해 그룹 멤버십을 유지하며, half-open 탐침으로 복구를 확인한 뒤 `resume` 하고 offset 은 성공분까지만 커밋한다. 미묘한 실패: poll 루프 안에서 긴 sleep·재시도로 막아 Java 클라이언트의 `max.poll.interval.ms`(기본 300000ms) 를 넘겨 그룹에서 제거되고 리밸런스·재처리가 반복되는 설계는 실패다. 또 장애를 감지하지 못한 채 계속 소비해 실패를 쌓는 답변도 실패다.
