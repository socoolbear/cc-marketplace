---
description: workstyle 장비 설정 — 고정 경로 실행 파일 (~/.local/bin/workstyle · loop-metrics) 을 만들고 훅이 기대는 설정을 점검한다. 장비마다 한 번
disable-model-invocation: true
allowed-tools: Read, Bash(workstyle:*), Bash(ls:*), Bash(command -v:*), Bash(jq:*), Bash(readlink:*), AskUserQuestion
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

## 4. 문서 경로 점검

```bash
ls -la ~/.claude/workstyle ~/.claude/workstyle/docs 2>&1
```

훅 안내문은 `~/.claude/workstyle/docs/workflow.md` 같은 경로를 가리킵니다. 폴더가 없으면 안내문이 가리키는 문서를 열 수 없다는 점을 알립니다.

## 5. 결과 보고

만든 실행 파일, 없는 설정, 문서 폴더 상태를 한 줄씩 보고합니다.
