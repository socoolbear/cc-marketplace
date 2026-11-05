---
type: llm
criteria: "종료 신호가 앱 프로세스까지 전달되고, 앱이 작업을 끝낼 때까지 컨테이너의 주 프로세스가 살아 있는가?"
---
통과: Dockerfile 이 exec form 으로 시작 스크립트를 실행하고, 스크립트가 TERM 을 앱에 전달한 뒤 앱이 실제로 끝날 때까지 다시 기다리고 (trap 뒤 wait 재호출 또는 반복), 그 뒤 flush-metrics 를 실행해 앱의 종료 코드로 끝난다. 앱이 exec 로 주 프로세스가 되어 TERM 핸들러를 등록하고 flush-metrics 까지 직접 실행하는 구현도 통과다. 실패: shell form 으로 실행하거나, 스크립트가 앱을 전경 실행해 TERM 을 전달하지 않거나, trap 뒤 wait 를 한 번만 호출해 앱이 처리 중인데 flush-metrics 실행과 스크립트 종료로 넘어가거나, exec 때문에 flush-metrics 가 실행되지 않거나, tini -g 등으로 셸까지 TERM 을 받아 flush-metrics 없이 죽는다. 설명에만 있고 코드에 없으면 실패다.
