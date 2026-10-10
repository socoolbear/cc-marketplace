아래 SQS 워커 코드를 운영에 올리기 전에 리뷰해줘. 작업 하나가 길면 5분까지 걸려. 문제를 심각도 순으로.

```python
import boto3, json, logging
sqs = boto3.client("sqs")
URL = "https://sqs.ap-northeast-2.amazonaws.com/123/jobs"   # visibility timeout 기본 30s

def handle(job):
    ...  # 외부 API 호출 + DB 쓰기, 최대 5분

while True:
    resp = sqs.receive_message(QueueUrl=URL, MaxNumberOfMessages=10, WaitTimeSeconds=20)
    for m in resp.get("Messages", []):
        sqs.delete_message(QueueUrl=URL, ReceiptHandle=m["ReceiptHandle"])
        try:
            handle(json.loads(m["Body"]))
        except Exception as e:
            logging.error("failed: %s", e)
```
