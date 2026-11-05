---
type: llm
criteria: "처리 전에 delete_message 를 호출해 handle 실패·크래시 시 메시지가 유실되는 문제를 최고 심각도로 지적하고, 성공 후 삭제 + 실패 메시지의 DLQ 경로로 고치는가?"
---
현재 코드는 삭제 후 처리하므로 예외·OOM·Pod 종료 시 작업이 영구히 사라지고, except 가 로그만 남겨 실패가 묻힌다. 통과: 삭제를 handle 성공 뒤로 옮기고 실패 시 삭제하지 않아 visibility timeout 뒤 재전달되게 하며, 무한 재시도를 막기 위해 redrive policy(`maxReceiveCount`) 로 DLQ 를 두는 것까지 제시한다(실패 시 `ChangeMessageVisibility` 로 재시도 간격을 조정하는 것도 통과). 실패: 이 문제를 놓치거나 낮은 심각도로 두는 경우, 또는 성공 후 삭제로만 바꾸고 독성 메시지가 무한 재전달되는 문제를 다루지 않는 경우.
