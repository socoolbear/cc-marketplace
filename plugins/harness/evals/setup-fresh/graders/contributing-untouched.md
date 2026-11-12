---
type: llm
focus:
  source: file
  path: CONTRIBUTING.md
---
CONTRIBUTING.md 는 사람이 쓰는 기존 관례 문서라 setup 이 쓰면 안 된다. 파일에 원래 있던 두 관례 (`find*`/`get*` 네이밍, 한국어 문장 테스트 이름) 만 있고, 하네스 골격 기본 절 (`## 이름`·`## 예외`·`## 변환` 이나 전역 예외 처리·변환기 규칙) 이 추가되지 않았으면 통과한다. 추가됐으면 실패다.
