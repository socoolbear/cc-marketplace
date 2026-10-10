---
max_turns: 4
timeout_seconds: 240
allowed_tools: [Skill, Read, Glob, Grep]
---

SQS 큐에서 주문 이벤트를 받아서 Postgres 에 저장하는 워커를 Go 로 만들어줘.
