---
type: llm
criteria: "CMD npm start 구성에서 SIGTERM 이 Node 프로세스에 제대로 전달·처리되지 않아 유예 시간 후 SIGKILL 로 진행 중 작업이 끊긴다는 점을 설명하고, 신호 경로와 핸들러를 모두 고치는가?"
---
Node.js 공식 Docker 모범 사례는 npm 이 SIGTERM/SIGINT 를 삼킬 수 있고 PID 1 로 뜬 Node 는 신호에 기본 반응하지 않는다고 하며 `CMD ["node", ...]` 와 `--init`/tini 를 권한다. 통과: CMD 를 `node` 직접 실행으로 바꾸거나 tini·dumb-init·`shareProcessNamespace` 같은 init 을 두는 것 중 하나와, `process.on('SIGTERM', ...)` 핸들러 추가를 함께 제시한다. 실패: 둘 중 하나만 고치거나(핸들러만 추가하고 npm start 유지 등) 신호 전달 문제를 언급하지 않는 경우.
