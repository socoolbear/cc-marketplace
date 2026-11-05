---
type: llm
criteria: "SQS 의 at-least-once 전달 때문에 같은 작업이 두 번 실행될 수 있음을 전제로 handle 의 외부 API 호출과 DB 쓰기를 멱등하게 만들라고 하는가?"
---
AWS 문서상 표준 큐는 visibility timeout 안에서도 중복 전달을 보장하지 않으며, 성공 후 삭제로 바꾸면 삭제 직전 크래시·삭제 실패 때도 재실행된다. 통과: 메시지 ID나 작업 ID 기반 처리 이력 테이블·unique 제약, 외부 API 에 idempotency key 전달, 또는 FIFO 큐 중복 제거는 5분 창에 한정됨을 밝히고 애플리케이션 멱등성을 함께 두는 방식. 실패: 중복 가능성을 다루지 않거나 FIFO 전환만으로 중복이 해결된다고 하는 경우.
