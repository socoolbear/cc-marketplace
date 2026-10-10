---
type: llm
criteria: "processing 리스트나 미확인(pending) 항목에 남은 작업을 죽은 워커 대신 다시 큐로 돌려놓는 회수 경로와 그에 따른 중복 처리 대책을 제시하는가?"
---
BLMOVE 로 바꿔도 워커가 죽은 뒤 processing 리스트를 아무도 보지 않으면 작업은 큐에서 사라진 것과 같다. 통과: 워커별 processing 리스트(예: Pod 이름 포함 키) 를 시작 시 재큐잉하거나, 오래 머문 항목을 되돌리는 reaper, Streams 의 `XPENDING`/`XAUTOCLAIM` 같은 회수 경로를 제시하고, 재처리로 같은 작업이 두 번 실행될 수 있으니 멱등 처리를 함께 언급한다. 실패: processing 리스트로 옮기라고만 하고 회수 경로가 없거나, 회수는 있지만 Pod 이름이 바뀌는 Deployment 환경에서 이전 Pod 리스트를 아무도 회수하지 않는 설계, 또는 중복 실행 가능성을 다루지 않는 경우.
