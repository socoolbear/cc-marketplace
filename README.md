# cc-marketplace

개인용 Claude Code 플러그인 마켓플레이스.

## 설치

```bash
/plugin marketplace add socoolbear/cc-marketplace
```

## 플러그인 목록

| 플러그인 | 스킬 | 설명 | 출처 |
|---------|------|------|------|
| harness | `/harness:harness` | 경량 하네스 — 에이전트용 지속 지식 문서 (AGENTS.md 지도 + harness/ 의 ARCHITECTURE·ADR·GLOSSARY·LESSONS) 와 선택적 레이어 검사 (hook + CI) 를 단일 진입점으로 관리. 상태 자동 감지로 setup (0→1 구축) / maintain (버전 동기화 + 문서 낡음 점검) / reflect (세션 학습 승격) 분기 | |
| documents | `/documents:resume` | 경력기술서, 이력서를 MD 파일로 작성 | [@devninja03](https://www.threads.com/@devninja03/post/DWQtpYXAers) |
| snippets | `/snippets:extract` | 코드베이스 → 재사용 가능한 snippet 추출 (보안 스캐닝, README 자동 생성, local/gist/push 출력) | |

## 플러그인 설치

```bash
/plugin install harness@cc-marketplace
/plugin install documents@cc-marketplace
/plugin install snippets@cc-marketplace
```
