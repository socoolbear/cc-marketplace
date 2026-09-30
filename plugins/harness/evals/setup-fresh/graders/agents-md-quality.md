---
type: llm
focus:
  source: file
  path: AGENTS.md
---
AGENTS.md 가 다음을 모두 만족하면 통과한다.
1. 전체가 40줄 이하다 (빈 줄 포함해 줄 수를 직접 센다).
2. 검증 명령 (테스트·빌드·린트 실행 명령) 을 적었다면, 그 명령은 모두 이 프로젝트의 package.json 에 실제로 있는 스크립트 (`test` 뿐이며 값은 `node --test`) 에서 나온 것이다. `npm run lint`, `npm run build` 처럼 package.json 에 없는 명령을 적었으면 실패다. 검증 명령을 아예 적지 않은 것은 허용한다.
