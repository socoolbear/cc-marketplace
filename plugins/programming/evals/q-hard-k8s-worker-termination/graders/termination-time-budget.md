---
type: llm
criteria: "코드 경로상 가장 늦게 시작할 수 있는 120초 작업이 끝나고 flush-metrics 까지 마칠 시간이 terminationGracePeriodSeconds 안에 있는가?"
---
통과: terminationGracePeriodSeconds 가 종료 전 대기 시간, 120초 작업, flush-metrics 5초를 모두 더한 값보다 크다. 대기 중에도 워커가 새 작업을 받는 구현이면 대기 시간을 120초에 더해야 한다. 대기 시작과 동시에 새 작업 수령을 멈추는 구현이면 그 시점 기준으로 계산해도 된다. 앱 안의 종료 제한 시간이 있다면 120초 이상이면서 남은 예산 안에 있어야 한다. 실패: 기본값 30초를 그대로 쓰거나, preStop 시간을 예산에서 빼먹어 합계가 grace 값을 넘거나, 앱의 종료 제한 시간이 120초보다 짧아 작업을 끊는다.
