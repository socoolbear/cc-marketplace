# deploy-guard

운영 배포 앞의 확인 장치입니다. 켜 두면 모든 세션에서 훅 두 개가 돕니다 (상시 장치).

| 구성 | 하는 일 |
|---|---|
| 배포 점검 훅 `hooks/enforce-deploy-check.sh` (PreToolUse — Bash · GitHub MCP 머지) | 배포를 일으키는 push · 머지 · workflow 실행을 첫 실행에 점검 목록으로 막고, 다시 실행하면 운영 대상은 확인창을 띄운다 |
| QA 알림 훅 `hooks/remind-deploy-qa.sh` (PostToolUse — Bash) | 배포 명령 직후 "묻지 않고 직접 QA" 를 알린다 |
| 스킬 `deploy-guard:deploy` | 배포 절차 — 운영 배포 판단, 확인을 받는 것과 받지 않는 것, dev · 운영 점검 목록, 직접 QA, 훅 동작 |
| 명령 `/deploy-guard:setup` | 장비마다 한 번 — 정책 파일 자리 잡기 |

## 필요한 것

macOS (`md5`), `jq`, `git`, `gh`.

## 정책 파일 (저장소 밖)

어떤 repo 의 어떤 브랜치가 운영 배포인지는 플러그인에 들어 있지 않습니다. 장비의 비공개 파일에서 읽습니다.

| 파일 | 내용 | 형식 |
|---|---|---|
| `~/.config/claude/deploy-targets` | 훅이 읽는 대상 (`prod` · `dev` · `none` · `no-prod` · `dev-workflow` · `prod-command` 줄) | `skills/deploy/references/deploy-targets.example` |
| `~/.config/claude/deploy-targets.md` | 모델이 읽는 repo 별 분류 표 | `skills/deploy/references/deploy-targets.md.example` |
| `~/.config/claude/deploy-qa-patterns` | QA 알림 훅이 추가로 잡을 명령 (선택) | `skills/deploy/references/deploy-qa-patterns.example` |

대상 파일이 없거나 형식이 어긋난 줄이 있으면 훅은 `main` · `master` · `dev` 를 모두 운영으로 봅니다 — 모르면 운영입니다. 분류 표가 모델에 실리려면 전역 지시 파일에서 불러와야 합니다 (`@~/.config/claude/deploy-targets.md`).

## 판정에 쓰는 환경 변수 · 상태

| 조건 | 동작 |
|---|---|
| `AGENT_BOT=1` (봇 세션) | 운영 대상도 다시 실행하면 통과 — 메신저의 사용자 본인 요청을 확인으로 본다. `prod-command` 는 확인창 |
| `CLAUDE_DEPLOY_APPROVED_SESSION` 에 값이 있음 (봇이 쓰레드에 연결해 띄운 세션) | 위와 같다. repo 를 확정하지 못한 대상은 확인창 |
| 야간 모드 (`~/.local/state/claude-loop/night/<세션 ID>` 또는 `CLAUDE_NIGHT=1` — `night-loop` 플러그인과의 약속) | dev 를 포함해 처음부터 확인창 |
| `CLAUDE_DEPLOY_TARGETS` · `CLAUDE_DEPLOY_QA_PATTERNS` | 정책 파일 경로 재정의 (시험용) |

첫 실행을 기억하는 상태 파일은 `${TMPDIR}/claude-deploy-check/` 에 세션 · 대상별로 생깁니다.

## 한계

- 명령 문자열만 봅니다. 셸 래퍼 (`bash -c`) · `--all` · 브라우저로 하는 배포는 잡지 못합니다 — 그런 것은 분류 표대로 판단합니다
- 확인창에 답할 사람이 없는 실행 (`-p` 등) 에서는 확인창이 자동 거부됩니다
- 훅이 오류로 끝나면 (필요한 명령이 없는 장비 등) 명령을 막지 못할 수 있습니다

## 시험

```bash
bash tests/run.sh
```

격리한 `HOME` · `TMPDIR` 와 임시 git 저장소, 가짜 `gh` 로 판정을 확인합니다. `--legacy <폴더> [변수 이름]` 은 옮기기 전 스크립트에 같은 기대값을 돌리고, 플러그인 훅과의 차이가 주석 · 안내문 · 승인 위임 변수 한 줄뿐인지 봅니다.
