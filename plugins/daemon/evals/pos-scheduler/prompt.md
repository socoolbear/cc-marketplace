---
max_turns: 4
timeout_seconds: 240
allowed_tools: [Skill, Read, Glob, Grep]
---

5분마다 외부 환율 API 를 호출해서 DB 에 저장하는 작업을 만들어줘. 이 앱은 파드가 3개 떠.
