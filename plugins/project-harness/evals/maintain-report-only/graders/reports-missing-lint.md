---
type: llm
---
package.json 에는 `lint` 스크립트 (`node --check src/index.js`) 가 있지만 AGENTS.md 검증 명령에는 없다. 최종 보고가 이 `lint` 스크립트 (또는 `npm run lint`) 를 AGENTS.md 에 빠진 검증 명령으로 짚었으면 통과한다. lint 를 언급하지 않거나, 이 스크립트와 무관한 린트 도구 (eslint 설정 부재 등) 만 언급했으면 실패다.
