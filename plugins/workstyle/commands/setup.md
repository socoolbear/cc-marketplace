---
description: workstyle 장비 설정 — 고정 경로 실행 파일 (~/.local/bin/workstyle · loop-metrics) 을 만들고, 취향 규칙 폴더 (~/.claude/workstyle) 와 전역 지시 파일의 import 줄, 훅이 기대는 설정을 점검한다. 장비마다 한 번
disable-model-invocation: true
allowed-tools: Read, Bash(workstyle:*), Bash(ls:*), Bash(command -v:*), Bash(jq:*), Bash(readlink:*), Bash(grep:*), AskUserQuestion
---

workstyle 플러그인을 이 장비에 등록합니다. 아래 순서를 그대로 따르고, 단계마다 결과를 한 줄로 보고하세요.

## 1. 필요한 것 확인

```bash
command -v jq git md5 claude
```

하나라도 없으면 무엇이 없는지 알리고 멈춥니다 (`md5` 는 macOS 기본 명령입니다).

## 2. 실행 파일 등록

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/workstyle" install
ls -la ~/.local/bin/workstyle ~/.local/bin/loop-metrics
```

`~/.local/bin` 이 PATH 에 없으면 알립니다. 같은 이름의 다른 파일이 있어 건드리지 않았다는 안내가 나오면 그 파일을 어떻게 할지 사용자에게 묻습니다.

## 3. 훅이 기대는 설정 점검

```bash
jq '{plansDirectory, autoCompactWindow}' ~/.claude/settings.json
```

| 설정 | 기대는 훅 | 없을 때 |
|---|---|---|
| `plansDirectory` 가 `.claude/plan` 또는 `.claude/plans` | 계획 검증 훅 (프로젝트의 그 폴더에서 최신 계획서를 찾는다) | 계획서를 찾지 못해 첫 승인 요청만 막고 다시 요청하면 통과한다 |
| `autoCompactWindow` | 컨텍스트 알림 훅 (알림 기준을 정한다) | 기본 기준을 쓴다 |

없는 값은 알리기만 하고 설정 파일을 고치지 않습니다.

## 4. 취향 규칙 폴더 (`~/.claude/workstyle`)

```bash
ls -la ~/.claude/workstyle 2>&1 | head -5
```

취향 규칙 (이 플러그인의 `rules/`) 은 고정 폴더 `~/.claude/workstyle` 에 놓이고 전역 지시 파일이 거기서 불러옵니다. 상태에 따라 한 가지를 합니다.

| 상태 | 할 일 |
|---|---|
| 사본 (`.synced-copy` 파일이 있다) | 그대로 둔다 — 세션 시작 훅이 설치본 내용으로 맞춘다 |
| 플러그인 체크아웃으로 가는 심링크 | 그대로 둔다. 끊겼으면 아래 "개발 장비" 대로 다시 건다 |
| 없다 | 세션을 한 번 다시 열면 훅이 사본을 만든다. 이 장비에서 규칙을 직접 고칠 것인지 `AskUserQuestion` 으로 묻는다 |
| 그 밖의 폴더 | 내용을 보여 주고 어떻게 할지 묻는다 (지우거나 옮기는 것은 사용자 확인 뒤) |

**개발 장비** (이 플러그인 저장소의 체크아웃이 있고 거기서 규칙을 고치는 장비): 사용자가 체크아웃 경로를 알려 주면 고정 폴더를 `<체크아웃>/plugins/workstyle/rules` 로 가는 심링크로 겁니다. 명령을 보여 주고 확인받은 뒤 실행합니다. 규칙 글을 고치면 다음 세션에 바로 실리고, 훅 · 에이전트 · 명령은 push 뒤 플러그인 갱신으로 반영됩니다. 체크아웃은 기본 브랜치에 두고 작업은 worktree 에서 합니다 (체크아웃이 다른 브랜치에 있으면 그 내용이 모든 새 세션에 실립니다).

## 5. 전역 지시 파일 (`~/.claude/CLAUDE.md`)

```bash
ls -la ~/.claude/CLAUDE.md 2>&1; grep -n '^@' ~/.claude/CLAUDE.md 2>/dev/null
```

아래 줄이 있어야 취향 규칙이 모든 세션 (서브에이전트 포함) 에 실립니다. 경로는 홈 기준으로 씁니다 — 상대 경로는 파일이 심링크일 때 실제 위치 기준으로 풀려 빠질 수 있습니다.

```
@~/.claude/workstyle/AGENTS.md
@~/.claude/workstyle/workflow-table.md
@~/.claude/workstyle/coding-style.md
```

- 파일이 없으면 위 세 줄로 새로 만듭니다 (확인받은 뒤)
- 파일이 있으면 빠진 줄을 알리고, 넣을지 묻습니다. 파일이 다른 저장소로 가는 심링크면 직접 고치지 않고 그 저장소에서 고치라고 알립니다
- 배포 분류 표 (`@~/.config/claude/deploy-targets.md` — `deploy-guard` 플러그인) 와 장비 규칙 파일 (`@~/.config/claude/local-rules.md` — 공개 플러그인에 넣을 수 없는 이 장비 · 조직의 규칙) 을 쓰는 장비는 그 줄도 있는지 함께 알립니다

## 6. 결과 보고

만든 실행 파일, 없는 설정, 취향 규칙 폴더의 상태 (사본 / 심링크 / 없음), 전역 지시 파일의 import 줄 상태를 한 줄씩 보고합니다.
