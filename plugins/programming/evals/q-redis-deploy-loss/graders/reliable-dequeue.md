---
type: llm
criteria: "BRPOP 은 꺼내는 순간 리스트에서 지우므로 처리 중 프로세스가 죽으면 작업이 사라진다는 근본 원인을 짚고, 처리 완료 후 확인하는 구조로 바꾸라고 하는가?"
---
Redis 문서의 reliable queue 패턴대로 `BLMOVE`(구 `BRPOPLPUSH`) 로 processing 리스트에 옮긴 뒤 처리 완료 후 `LREM` 하는 방식, Redis Streams 의 `XREADGROUP`/`XACK`, 또는 이를 구현한 큐 라이브러리(BullMQ 등) 로의 전환이 모두 통과다. 실패: 신호 처리·graceful shutdown 만 추가하고 BRPOP 을 그대로 두는 답변 — OOMKill·노드 장애·SIGKILL 때는 여전히 유실되므로 근본 해결이 아니다.
