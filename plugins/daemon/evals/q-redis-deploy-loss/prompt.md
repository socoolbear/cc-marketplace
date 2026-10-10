Node.js 로 Redis 리스트 큐 (`BRPOP jobs`) 를 소비하는 워커를 k8s 에 배포했어. Dockerfile 은 `CMD ["npm", "start"]` 이고 따로 신호 처리는 안 했어. 배포할 때마다 작업 몇 개가 사라지는 것 같아. 원인과 수정 방법을 알려줘.
