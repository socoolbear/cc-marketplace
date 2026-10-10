---
type: llm
criteria: "재전달된 같은 주문 이벤트가 orders 테이블에 중복 행이나 잘못된 덮어쓰기를 만들지 않도록 쓰기가 멱등한가?"
---
Kafka 소비자 그룹은 커밋 전 크래시·리밸런스 때 같은 레코드를 다시 주므로 at-least-once 를 전제해야 한다. 통과: 주문 ID 같은 자연 키에 unique 제약을 두고 `INSERT ... ON CONFLICT DO NOTHING/DO UPDATE` 를 쓰거나, (topic, partition, offset) 을 같은 트랜잭션에 저장해 중복을 거르는 방식이며, 상태 갱신 이벤트라면 버전·이벤트 시각으로 오래된 이벤트가 최신 값을 덮지 않게 막으면 더 좋다. 실패: 중복 방지 없는 단순 `INSERT` 이거나 중복 가능성을 언급하지 않는 경우.
