---
type: llm
focus:
  source: file
  path: AGENTS.md
---
AGENTS.md 가 코딩 관례 문서로 `CONTRIBUTING.md` 를 가리키는 포인터 줄을 갖고 있으면 통과한다. 포인터 줄에 "네이밍"·"테스트 이름" 같은 주제어를 언급하는 것은 허용한다. 포인터가 없거나, `CONTRIBUTING.md` 의 규칙 문장 자체 (예: null 이면 `find*`, 예외면 `get*`) 를 AGENTS.md 에 옮겨 적었으면 실패다.
