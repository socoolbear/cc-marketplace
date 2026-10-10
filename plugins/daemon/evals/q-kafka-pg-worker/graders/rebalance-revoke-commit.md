---
type: llm
criteria: "파티션이 회수되는 리밸런스(배포·스케일 시 매번 발생) 때 처리 완료분 커밋과 회수된 파티션 레코드 처리를 올바르게 다루는가?"
---
k8s Deployment 롤링 배포마다 리밸런스가 일어나므로, 수동 커밋을 쓰면 회수 직전 처리분을 커밋하지 않으면 새 소유자가 대량 재처리하고, 회수 후 커밋하면 실패하거나 남의 진행을 덮는다. 통과: `BlockRebalanceOnPoll` + 처리 후 `AllowRebalance`, 또는 `OnPartitionsRevoked`(필요 시 `OnPartitionsLost` 구분) 콜백에서 처리 중인 것을 끝내고 동기 커밋하는 코드, 혹은 기본 autocommit 이 revoke 시 커밋한다는 점을 근거로 의도적으로 맡긴 설명. 실패: 수동 커밋을 쓰면서 리밸런스 처리를 전혀 하지 않거나 언급조차 없는 경우.
