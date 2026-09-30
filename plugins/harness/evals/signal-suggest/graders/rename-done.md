---
type: llm
---
src/a.js 의 함수 `getUser` 가 `fetchUser` 로 바뀌었고, src/b.js 의 import 와 호출부도 `fetchUser` 로 바뀌었다고 보고했으면 통과한다. 한쪽만 바꾸었거나 `getUser` 가 남았다고 보이면 실패다.
