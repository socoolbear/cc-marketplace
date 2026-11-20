# workstyle

일하는 방식을 정하는 장치입니다. 켜 두면 모든 세션에서 훅이 돕니다 (상시 장치).

| 구성 | 하는 일 |
|---|---|
| 계획 검증 `hooks/enforce-plan-review.sh` (PreToolUse — ExitPlanMode) | 최신 계획서에 「적대적 검증」 절이 없으면 계획 승인 요청을 막는다 |
| 질문 전 점검 `hooks/ask-precheck.sh` (PreToolUse — AskUserQuestion) | 세션의 첫 질문과 실행 승인 질문을 막고 「꼭 묻는 목록」 으로 걸러내게 한다. 야간 모드에서는 매번 막는다. 통과한 질문은 `ask-classify.sh` 가 분류해 기록한다 |
| 멈춤 점검 `hooks/stop-gate.sh` (Stop) | 상태 꼬리표 (지금 / 사용자 몫 / 다음) · 본문 길이 · 묻는 말로 끝내기를 점검하고, 꼬리표를 상황판 파일로 남긴다 |
| 컨텍스트 알림 `hooks/context-guard.sh` (PostToolUse) · compact 복원 `hooks/compact-restore.sh` (SessionStart — compact) | 컨텍스트가 차면 진행 문서 (`.prompts/PROGRESS-<세션 앞 8자>.md`) 를 쓰게 알리고, compact 뒤 그 문서를 다시 싣는다 |
| 팀 정리 `hooks/team-cleanup-check.sh` (Stop) | 일이 끝난 팀이 남아 있으면 알린다 |
| 세션 표시 `hooks/mark-session.sh` (SessionStart) | 이 세션에 플러그인 훅이 실렸다는 표시를 `${TMPDIR}/claude-plugin-sessions/` 에 남긴다 — 같은 장치를 설정 파일의 훅으로 돌리던 장비가 옮겨 올 때 설정 쪽 훅이 이 표시를 보고 물러난다 |
| 에이전트 `workstyle:impl-dev` · `workstyle:qa-runner` | 프로젝트 전용 에이전트가 없을 때 쓰는 폴백 (구현 · 시험 실행) |
| 명령 `/workstyle:now` · `/workstyle:handoff` · `/workstyle:setup` | 진행 상황 보고 후 이어가기 · 인계 문서 작성 · 장비 설정 |
| 실행 파일 `workstyle board` · `workstyle metrics [days]` | 열려 있는 세션의 상태 꼬리표를 한 화면에 (상황판) · 사람 개입 지표 |

## 필요한 것

macOS (`md5` · `stat -f`), `jq`, `git`. 버전은 따로 올리지 않습니다 — `plugin.json` 에 `version` 이 없어 커밋이 버전입니다.

## 장비 설정

플러그인을 설치한 뒤 세션에서 `/workstyle:setup` 을 한 번 실행합니다. `~/.local/bin/workstyle` 과 `~/.local/bin/loop-metrics` (설치본을 찾아 부르는 작은 스크립트) 가 생깁니다.

## 훅이 기대는 것

| 대상 | 쓰는 훅 |
|---|---|
| 설정 `plansDirectory` (`.claude/plan` 또는 `.claude/plans`) | 계획 검증 — 프로젝트의 그 폴더만 본다. 설정이 없으면 계획서를 찾지 못해 다시 요청하면 통과한다 |
| 설정 `autoCompactWindow` | 컨텍스트 알림의 기준 |
| 문서 `~/.claude/workstyle/docs/workflow.md` · `work-split.md`, `~/.claude/workstyle/AGENTS.md` | 훅 안내문이 가리키는 기준 문서 |
| `AGENT_BOT=1` | 봇이 띄운 세션에서는 질문 · 멈춤 · 컨텍스트 훅이 건너뛴다 |

## 함께 쓰는 상태 (`~/.local/state/claude-loop/`)

`night-loop` 플러그인과 같은 폴더를 씁니다. 이름을 바꾸지 않습니다.

| 경로 | 쓰는 쪽 | 읽는 쪽 |
|---|---|---|
| `board/<세션 ID>.md` | 멈춤 점검 | `workstyle board` (`claude-loop board` 가 넘겨 부른다) |
| `stop-gate/{mode,owed-mode,next-mode,length-mode}` · `stop-gate/log.jsonl` | 사용자 · 멈춤 점검 | 멈춤 점검 · night-loop 의 아침 요약 |
| `ask-classify/{judge,log.jsonl}` | 사용자 · 질문 분류 | 질문 분류 · 지표 |
| `disabled` | 사용자 | 멈춤 점검 · night-loop (같은 끄기 스위치) |
| `night/…` | night-loop | 질문 전 점검 (야간 모드 판정) |

## 시험

```bash
bash tests/run.sh
```

`--legacy <폴더>` 는 옮기기 전 스크립트와 나란히 돌려 종료 코드 · 출력이 같은지, 파일 차이가 주석 · 문서 경로 · 훅끼리 부르는 경로뿐인지 봅니다.
