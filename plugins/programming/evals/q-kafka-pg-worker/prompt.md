Kafka 토픽 `orders` 의 주문 이벤트를 읽어 PostgreSQL `orders` 테이블에 적재하는 Go 워커를 만들려고 해. 라이브러리는 franz-go 를 쓰고 k8s Deployment 로 띄울 거야. 핵심 처리 루프, offset 커밋, 종료 처리 코드를 짜줘. 설명은 짧게, 코드 위주로.
