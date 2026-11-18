---
max_turns: 40
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, Write, Edit, Bash, Agent]
---

새로 시작하는 프로젝트야. 하네스를 셋업해줘. 코딩 관례도 하나 정했어: 조회 함수는 없으면 null 을 돌려주면 `find*`, 없으면 던지면 `get*` 로 이름 짓는다 (호출부가 null 처리 여부를 이름으로 알게). 스택은 TypeScript + Node 로 확정했고, 레이어는 `src/types`·`src/core`·`src/api` 세 개로 갈 거야 — types 는 다른 레이어를 import 하지 않고, core 는 types 만, api 는 core·types 를 import 해 (이것도 확정). 범위 확인 질문 없이 기본값으로 진행해.
