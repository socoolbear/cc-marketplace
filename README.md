# cc-marketplace

개인용 Claude Code 플러그인 마켓플레이스.

## 설치

```bash
/plugin marketplace add socoolbear/cc-marketplace
```

## 플러그인 목록

| 플러그인 | 진입점 | 설명 | 출처 |
|---------|--------|------|------|
| harness | `/harness:harness` | 경량 하네스 — 에이전트용 지속 지식 문서 (AGENTS.md 지도 + harness/ 의 ARCHITECTURE·ADR·GLOSSARY·LESSONS) 와 선택적 레이어 검사 (hook + CI) 를 단일 진입점으로 관리. 상태 자동 감지로 setup (0→1 구축) / maintain (버전 동기화 + 문서 낡음 점검) / reflect (세션 학습 승격) 분기 | |
| documents | `/documents:resume` | 경력기술서, 이력서를 MD 파일로 작성 | [@devninja03](https://www.threads.com/@devninja03/post/DWQtpYXAers) |
| snippets | `/snippets:extract` | 코드베이스 → 재사용 가능한 snippet 추출 (보안 스캐닝, README 자동 생성, local/gist/push 출력) | |
| sessions | `/sessions:crosstalk` | 같은 머신의 다른 Claude Code 세션과 UDS 로 메시지 송수신 (connect/send/list/disconnect) | |
| claude-notify | 훅 (자동) · `/claude-notify:notify-setup` · `/claude-notify:notify-doctor` | macOS 알림 훅 — 터미널 foreground / 화면 잠금 상태를 감지해 terminal-notifier (로컬) 와 ntfy (모바일 푸시) 중 알맞은 채널을 자동 선택 | |

## 플러그인 설치

```bash
/plugin install harness@socoolbear-cc-marketplace
/plugin install documents@socoolbear-cc-marketplace
/plugin install snippets@socoolbear-cc-marketplace
/plugin install sessions@socoolbear-cc-marketplace
/plugin install claude-notify@socoolbear-cc-marketplace
```

`@` 뒤는 `.claude-plugin/marketplace.json` 의 `name` 값 (`socoolbear-cc-marketplace`) 입니다.

`claude-notify` 는 설치하면 훅 (`Notification` · `Stop`) 이 자동으로 붙습니다. 설치 후 `/claude-notify:notify-setup` 을 한 번 실행해 ntfy 토픽을 정하세요.
