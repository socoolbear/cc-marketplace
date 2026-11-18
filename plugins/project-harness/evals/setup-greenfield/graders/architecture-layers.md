---
type: llm
focus:
  source: file
  path: harness/ARCHITECTURE.md
---
ARCHITECTURE.md 가 레이어 규칙으로 `types` → `core` → `api` 의 의존 방향 (types 는 아무것도 import 하지 않고, core 는 types 만, api 는 core·types 를 import) 을 적었으면 통과한다. 세 레이어 중 하나라도 빠졌거나 방향이 다르면 실패다.
