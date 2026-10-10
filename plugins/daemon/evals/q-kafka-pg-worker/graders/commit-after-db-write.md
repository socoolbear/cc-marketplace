---
type: llm
criteria: "offset 커밋이 해당 레코드의 PostgreSQL 트랜잭션 커밋이 끝난 뒤에만 일어나도록 코드가 짜여 있는가?"
---
통과: `DisableAutoCommit` 후 DB 커밋 성공 뒤 `CommitRecords`/`CommitUncommittedOffsets` 를 호출하거나, `AutoCommitMarks` + DB 커밋 뒤 `MarkCommitRecords` 를 쓰거나, 기본 autocommit 을 쓰되 처리를 poll 루프 안에서 동기로 끝내 "이전에 poll 한 것만 커밋" 되는 성질에 기대는 이유를 밝힌 경우 모두 통과다. offset 을 같은 DB 트랜잭션에 저장하는 방식도 통과다. 실패: poll 직후 처리 전에 커밋하거나, 레코드를 고루틴·채널로 넘겨 비동기 처리하면서 기본 autocommit 을 그대로 두어 DB 쓰기 전에 커밋될 수 있는 코드, 또는 DB 오류가 나도 커밋으로 넘어가는 코드.
