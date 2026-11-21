# workstyle

일하는 방식을 정하는 장치입니다. 켜 두면 모든 세션에서 훅이 돕니다 (상시 장치).

| 구성 | 하는 일 |
|---|---|
| 계획 검증 `hooks/enforce-plan-review.sh` (PreToolUse — ExitPlanMode) | 최신 계획서에 「적대적 검증」 절이 없으면 계획 승인 요청을 막는다 |
| 질문 전 점검 `hooks/ask-precheck.sh` (PreToolUse — AskUserQuestion) | 세션의 첫 질문과 실행 승인 질문을 막고 「꼭 묻는 목록」 으로 걸러내게 한다. 야간 모드에서는 매번 막는다. 통과한 질문은 `ask-classify.sh` 가 분류해 기록한다 |
| 멈춤 점검 `hooks/stop-gate.sh` (Stop) | 상태 꼬리표 (지금 / 사용자 몫 / 다음) · 본문 길이 · 묻는 말로 끝내기를 점검하고, 꼬리표를 상황판 파일로 남긴다 |
| 컨텍스트 알림 `hooks/context-guard.sh` (PostToolUse) · compact 복원 `hooks/compact-restore.sh` (SessionStart — compact) | 컨텍스트가 차면 진행 문서 (`.prompts/PROGRESS-<세션 앞 8자>.md`) 를 쓰게 알리고, compact 뒤 그 문서를 다시 싣는다 |
| 팀 정리 `hooks/team-cleanup-check.sh` (Stop) | 일이 끝난 팀이 남아 있으면 알린다 |
| 취향 규칙 `rules/` + 규칙 맞추기 `hooks/sync-rules.sh` (SessionStart) | 매 세션 실리는 지시문 (`AGENTS.md` · `workflow-table.md` · `coding-style.md`) 과 그것이 가리키는 문서 (`docs/`). 훅이 고정 폴더 `~/.claude/workstyle` 에 사본을 맞추고, 전역 지시 파일이 거기서 불러온다 |
| 에이전트 `workstyle:impl-dev` · `workstyle:qa-runner` | 프로젝트 전용 에이전트가 없을 때 쓰는 폴백 (구현 · 시험 실행) |
| 명령 `/workstyle:handoff` · `/workstyle:setup` | 인계 문서 작성 · 장비 설정 |
| 실행 파일 `workstyle board` · `workstyle metrics [days]` | 열려 있는 세션의 상태 꼬리표를 한 화면에 (상황판) · 사람 개입 지표 |
| 실행 파일 `workstyle backtest collect · judge · report` (`bin/ask-backtest`) | 질문 대조 — 과거 질문 창의 질문을 모델이 세 번 따로 고르게 하고 사용자의 실제 답과 견준다. 질문을 사람 대신 승인하는 판정 방식을 실제 질문에 붙이기 전에 재는 용도 (아래 「질문 대조」) |

## 필요한 것

macOS (`md5` · `stat -f`), `jq`, `git`. 버전은 따로 올리지 않습니다 — `plugin.json` 에 `version` 이 없어 커밋이 버전입니다.

## 장비 설정

플러그인을 설치한 뒤 세션에서 `/workstyle:setup` 을 한 번 실행합니다. `~/.local/bin/workstyle` 과 `~/.local/bin/loop-metrics` (설치본을 찾아 부르는 작은 스크립트) 가 생깁니다.

## 취향 규칙이 실리는 방법

플러그인은 지시문을 직접 실을 수 없고, 세션 시작 훅으로 넣은 글은 서브에이전트에 실리지 않습니다. 그래서 전역 지시 파일 `~/.claude/CLAUDE.md` 가 고정 폴더의 글을 불러옵니다 (`/workstyle:setup` 이 줄을 점검합니다).

```
@~/.claude/workstyle/AGENTS.md
@~/.claude/workstyle/workflow-table.md
@~/.claude/workstyle/coding-style.md
```

| 장비 | 고정 폴더 `~/.claude/workstyle` | 규칙을 고치면 |
|---|---|---|
| 일반 장비 | 세션 시작 훅이 맞추는 사본 (`.synced-copy` 표시) | 플러그인 갱신 뒤 세션을 열면 사본이 바뀐다 (그 세션은 옛 사본을 읽을 수 있다). 사본을 직접 고친 것은 사라진다 |
| 개발 장비 | 이 저장소 체크아웃의 `plugins/workstyle/rules` 로 가는 심링크 | 다음 세션에 바로 실린다. 훅 · 에이전트 · 명령은 push 뒤 플러그인 갱신으로 반영된다 |

버전 번호가 없어 옛 판에 머문 장비를 다른 곳에서 잡지 못하므로, 세션 시작 훅이 설치본과 그 장비의 마켓플레이스 사본의 내용을 견줘 다르면 갱신 명령을 알립니다 (마켓플레이스 사본이 갱신된 장비에서만 잡힙니다 — 자동 갱신을 켜 둡니다).

공개 플러그인에 넣을 수 없는 규칙 (회사 · 프로젝트 이름, 장비 경로가 든 것) 은 저장소 밖 파일 `~/.config/claude/local-rules.md` 에 두고 전역 지시 파일에서 함께 불러옵니다. Codex 는 `~/.codex/AGENTS.md` 가 고정 폴더의 `AGENTS.md` 를 가리키게 합니다.

## 훅이 기대는 것

| 대상 | 쓰는 훅 |
|---|---|
| 설정 `plansDirectory` (`.claude/plan` 또는 `.claude/plans`) | 계획 검증 — 프로젝트의 그 폴더만 본다. 설정이 없으면 계획서를 찾지 못해 다시 요청하면 통과한다 |
| 설정 `autoCompactWindow` | 컨텍스트 알림의 기준 |
| 문서 `~/.claude/workstyle/docs/workflow.md` · `work-split.md`, `~/.claude/workstyle/AGENTS.md` | 훅 안내문이 가리키는 기준 문서 |
| `AGENT_BOT=1` | 봇이 띄운 세션에서는 질문 · 멈춤 · 컨텍스트 훅이 건너뛴다 |

## 함께 쓰는 상태 (`~/.local/state/claude-loop/`)

폴더 이름은 야간 루프 (`night-loop` 플러그인, 2026-11-21 에 내림) 와 함께 쓰던 때의 것입니다. 이름을 바꾸지 않습니다.

| 경로 | 쓰는 쪽 | 읽는 쪽 |
|---|---|---|
| `board/<세션 ID>.md` | 멈춤 점검 | `workstyle board` |
| `stop-gate/{mode,owed-mode,next-mode,length-mode}` · `stop-gate/log.jsonl` | 사용자 · 멈춤 점검 | 멈춤 점검 |
| `ask-classify/{judge,log.jsonl}` | 사용자 · 질문 분류 | 질문 분류 · 지표 |
| `disabled` | 사용자 | 멈춤 점검 |
| `night/…` | 없음 (야간 루프를 내린 뒤로 쓰는 쪽이 없다) | 질문 전 점검 (야간 모드 판정 — 지금은 늘 낮으로 본다) |

## 질문 대조

질문을 사람 대신 승인하는 판정 방식 (자동 승인) 은 실제 질문에 붙이기 전에 과거 답으로 먼저 잽니다. 대화 기록에 남은 질문 창의 실제 답이 정답입니다.

```bash
workstyle backtest collect 30 > ~/asked.jsonl                               # 최근 30일의 답이 남은 질문
ASK_BACKTEST_MODEL=<상위 모델 별칭> workstyle backtest judge ~/asked.jsonl > ~/verdicts.jsonl   # 표본 100건을 세 번씩 판정
workstyle backtest report ~/verdicts.jsonl ~/asked.jsonl                    # 일치율 · 추천안 채택률 · 켜는 조건
```

- 판정은 추천 표시를 지우고 선택지 순서를 돌려서 보여주며, 세 번이 모두 추천안일 때만 자동 승인 대상으로 셉니다. 비교 기준은 추천안을 그냥 따를 때의 일치율 (추천안 채택률) 입니다
- 판정 방식을 바꿔 재려면 `ASK_BACKTEST_INSTRUCTIONS=<지시문 파일>`, 질문 직전 대화 글을 함께 주려면 `ASK_BACKTEST_CONTEXT=1` 을 붙입니다
- 모은 파일과 판정 파일에는 질문 글이 들어 있으므로 저장소 밖에 둡니다. 모델로 나가는 글은 주소 · 메일 · 긴 숫자 · 토큰 모양 문자열을 가리지만 사람 이름 · repo 이름은 가리지 못합니다
- 켜는 조건과 첫 측정 결과는 `~/.claude/workstyle/docs/workflow.md` §7 과 저장소의 `docs/evolution/workstyle.md` 에 있습니다

## 시험

```bash
bash tests/run.sh
```

`--legacy <폴더>` 는 옮기기 전 스크립트와 나란히 돌려 종료 코드 · 출력이 같은지, 파일 차이가 주석 · 문서 경로 · 훅끼리 부르는 경로뿐인지 봅니다.
