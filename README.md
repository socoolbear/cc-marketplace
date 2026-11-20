# cc-marketplace

개인용 Claude Code 플러그인 마켓플레이스.

## 설치

```bash
/plugin marketplace add socoolbear/cc-marketplace
```

## 플러그인 목록

플러그인은 두 종류입니다. `marketplace.json` 에서 상시 장치는 `always-on` 태그로 구분합니다.

### 상시 장치

켜 두면 모든 세션의 동작이 바뀝니다 (훅이 동작을 막거나 지시를 넣습니다). 필요한 장비에서만 켭니다.

| 플러그인 | 진입점 | 설명 | 출처 |
|---------|--------|------|------|
| claude-notify | 훅 (자동) · `/claude-notify:notify-setup` · `/claude-notify:notify-doctor` | macOS 알림 훅 — 터미널 foreground / 화면 잠금 상태를 감지해 terminal-notifier (로컬) 와 ntfy (모바일 푸시) 중 알맞은 채널을 자동 선택 | |
| deploy-guard | 훅 (자동) · 스킬 `deploy` · `/deploy-guard:setup` | 배포 확인 장치 — 운영 배포를 일으키는 push · 머지 · workflow 실행을 첫 실행에 점검 목록으로 막고 다시 실행하면 확인창을 띄운다. 배포 뒤에는 직접 QA 를 알린다. 대상은 저장소 밖 비공개 파일에서 읽는다 | |
| night-loop | 훅 (자동) · `/night-loop:setup` · `claude-loop` | AI 야간 루프 — 밤 01:30 에 opt-in 한 태스크 세션에 일을 맡기고 08:30 에 아침 요약을 만든다. 야간 가드 훅이 그 세션의 위험 동작 (머지·보호 브랜치 push·외부 발송·지시 파일 수정 등) 을 확인창에서 멈추고, 검증 게이트 훅이 검증 명령이 실패한 채 끝내지 못하게 막는다. macOS · tmux 전용 | |

### 부르는 도구

스킬·명령을 부를 때만 일합니다 (훅이 있어도 안내만 합니다).

| 플러그인 | 진입점 | 설명 | 출처 |
|---------|--------|------|------|
| project-harness | `/project-harness:project-harness` | 프로젝트 단위 경량 하네스 — 에이전트용 지속 지식 문서 (AGENTS.md 지도 + harness/ 의 ARCHITECTURE·ADR·GLOSSARY·LESSONS, CONVENTIONS — 기존 관례 문서가 없을 때) 와 선택적 레이어 검사 (팀 공유 hook + CI) 를 단일 진입점으로 관리. 상태 자동 감지로 setup (최초 구축) / maintain (낡음 점검 + 세션 학습 승격) 분기. 세션 시작 훅이 점검할 거리를 감지하면 스스로 점검을 제안 | |
| documents | `/documents:resume` | 경력기술서, 이력서를 MD 파일로 작성 | [@devninja03](https://www.threads.com/@devninja03/post/DWQtpYXAers) |
| snippets | `/snippets:extract` | 코드베이스 → 재사용 가능한 snippet 추출 (보안 스캐닝, README 자동 생성, local/gist/push 출력) | |
| sessions | `/sessions:child-session` · `/sessions:side-task` · `/sessions:crosstalk` | child-session: 태스크를 흐름별로 나눠 브리프를 받아 일하는 새 세션을 부모 tmux window 의 pane 으로 (다른 pane 이 이미 3개면 새 window 로, tmux 밖의 Herdr 터미널에서는 부모 터미널에 딸린 Herdr 터미널로) 띄우고 시작·공유·질문·진행·완료를 보고받음 (규칙 전파·닫기는 부모가 판단). side-task: 지금 대화를 이어받은 분기 세션을 같은 자리 규칙으로 띄워 곁가지 작업을 맡기고 시작·공유·질문·완료를 SendMessage 로 보고받음 (닫기는 부모가 판단). 둘 다 닫기 전에 세션 기록을 남기고 후속 문의 때 그 기록으로 다시 엶. crosstalk: [deprecated → SendMessage/ListAgents] 같은 머신의 다른 Claude Code 세션과 UDS 로 메시지 송수신 | |
| catchup | `/catchup:catchup` | 이전 Claude Code 세션의 transcript 를 찾아 요약하고 현재 세션으로 이어받기 (HANDOFF.md 없이 세션 이어가기) | |
| site-audit | `/site-audit:site-audit` | 웹사이트의 기술적 성능 · SEO · AEO 를 Lighthouse 와 Playwright 로 종합 진단 | |
| worktrees | `/worktrees:worktree-setup` · `/worktrees:worktree-refresh` | git worktree 작업 공간 도구 — 여러 repo 에 걸친 작업의 브랜치·worktree 한 벌 준비 (BRIEF.md 출발 문서 포함), worktree 브랜치를 저장소 상태 판정으로 최신 main 에 맞추기 | |
| taskspace | 훅 (자동) · `/taskspace:taskspace` · `/taskspace:task-intake` | bare 중앙 저장소 + tasks/<TASK-ID>/ 격리 worktree + notes.md 를 워크스페이스 repo 로 추적 (init/add/new/link/migrate/sync/done/hold/abandon/resume/list/index/upgrade). 끝난 태스크는 archive/<TASK-ID>/ 로 이동, 플러그인 업데이트 반영은 upgrade — 세션 시작 훅이 워크스페이스 안에서 반영할 것이 남았으면 알린다. task-intake 는 오류·알림 원문과 Slack·Notion·Jira 링크를 맡을 태스크를 찾아 (없으면 새로 열어) 그 태스크의 Claude 세션 (현재 tmux 세션의 window) 에 전달 | |
| programming | `/programming:server-chassis` | 프로그래밍 기법 스킬 묶음. server-chassis: 프로토콜 서버 (양방향·단방향 통신), 수집 서버·에이전트, 큐 소비자, 워커를 CBD 컴포넌트 (Daemonize · Live Config · CLI · Utility · Backlog · Emergency Notification · Recovery · GC · Plugin Interface · Protocol Handler · Transfer · Storage) 로 조립하고 Contract 로 구간을 잇는 설계·구현·리뷰 | |

## 플러그인 설치

```bash
/plugin install project-harness@socoolbear-cc-marketplace
/plugin install documents@socoolbear-cc-marketplace
/plugin install snippets@socoolbear-cc-marketplace
/plugin install sessions@socoolbear-cc-marketplace
/plugin install claude-notify@socoolbear-cc-marketplace
/plugin install catchup@socoolbear-cc-marketplace
/plugin install site-audit@socoolbear-cc-marketplace
/plugin install worktrees@socoolbear-cc-marketplace
/plugin install taskspace@socoolbear-cc-marketplace
/plugin install programming@socoolbear-cc-marketplace
/plugin install night-loop@socoolbear-cc-marketplace
```

`@` 뒤는 `.claude-plugin/marketplace.json` 의 `name` 값 (`socoolbear-cc-marketplace`) 입니다.

`claude-notify` 는 설치하면 훅 (`Notification` · `Stop`) 이 자동으로 붙습니다. 설치 후 `/claude-notify:notify-setup` 을 한 번 실행해 ntfy 토픽을 정하세요.

`night-loop` 는 설치하면 야간 가드·검증 게이트 훅이 붙습니다 (야간 모드가 아닌 세션에서는 아무것도 하지 않습니다). 밤에 실제로 돌리려면 `/night-loop:setup` 을 한 번 실행해 launchd 예약과 실행 파일을 등록하세요.
