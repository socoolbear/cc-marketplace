---
type: llm
criteria: "기본 visibility timeout 30초가 최대 5분 처리 시간보다 짧아 처리 중 메시지가 다른 소비자에게 다시 전달되는 문제를 지적하고 고치는가?"
---
AWS 문서상 visibility timeout 은 메시지 수신 시점부터 흐르고 기본 30초, 최대 12시간이다. 통과: 큐의 visibility timeout 을 최대 처리 시간보다 여유 있게 늘리거나(`receive_message` 의 `VisibilityTimeout` 인자 포함), 처리 중 `ChangeMessageVisibility` 로 주기적으로 연장하는 heartbeat 를 둔다. 실패: 이 문제를 언급하지 않거나, 처리 전 삭제를 성공 후 삭제로 바꾸라고 하면서 30초 설정을 그대로 두어 중복 처리를 만드는 답변.
