---
type: llm
criteria: "SIGTERM 을 받으면 새 poll 을 멈추고 진행 중 배치의 DB 쓰기와 최종 커밋을 끝낸 뒤 그룹을 떠나 종료하며, 이 과정이 terminationGracePeriodSeconds 안에 끝나도록 설계됐는가?"
---
통과: `signal.NotifyContext` 등으로 SIGTERM 을 잡아 루프를 빠져나오고, 진행 중 레코드 처리·최종 커밋 후 `cl.Close()`(또는 `LeaveGroup`) 로 그룹을 떠나며, k8s 기본 유예 30초 안에 끝나도록 처리 시간 상한을 두거나 유예 시간을 늘린다. 미묘한 실패도 잡는다: 취소된 같은 ctx 를 DB 쓰기에 그대로 넘겨 진행 중 트랜잭션이 중간에 취소되는데 그 offset 을 커밋하는 코드, `log.Fatal`/`os.Exit` 로 즉시 종료, 신호 처리 없음, 커밋 없이 Close 만 하는 코드는 실패다.
