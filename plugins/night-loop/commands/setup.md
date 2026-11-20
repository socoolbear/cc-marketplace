---
description: night-loop 장비 설정 — 실행 파일 (~/.local/bin/claude-loop) 과 launchd 예약 (01:30 night · 08:30 brief) 을 등록하고 장비 설정 파일을 만든다. 장비마다 한 번
disable-model-invocation: true
allowed-tools: Read, Bash(claude-loop:*), Bash(launchctl print:*), Bash(cat:*), Bash(ls:*), Bash(command -v:*), AskUserQuestion
---

night-loop 플러그인을 이 장비에 등록합니다. 아래 순서를 그대로 따르고, 단계마다 결과를 한 줄로 보고하세요.

## 1. 필요한 것 확인

```bash
command -v jq tmux claude gh
```

`jq` · `tmux` · `claude` 가 없으면 설치를 안내하고 멈춥니다. `gh` 가 없으면 아침 요약의 PR 절만 비게 됩니다.

## 2. 워크스페이스 경로 정하기

```bash
cat ~/.config/claude-loop/env
```

파일이 있으면 그 값을 그대로 씁니다 (3번에서 `--workspace` 를 빼고 실행). 없으면 사용자에게 태스크 워크스페이스 루트 (`<루트>/*/tasks/*/notes.md` 구조의 폴더) 를 묻습니다.

## 3. 등록

```bash
claude-loop install --workspace <2번에서 정한 경로>
```

## 4. 확인

```bash
launchctl print "gui/$(id -u)/com.socoolbear.claude-loop-night" | grep -E 'state|program|arguments' -A3
launchctl print "gui/$(id -u)/com.socoolbear.claude-loop-brief" | grep -E 'state|program|arguments' -A3
~/.local/bin/claude-loop list
CLAUDE_LOOP_DRY=1 CLAUDE_LOOP_FORCE=1 ~/.local/bin/claude-loop night
```

두 라벨이 등록돼 있고 `list` · dry night 가 오류 없이 끝나면 완료입니다.

## 5. 안내

- launchd 는 셸 설정을 읽지 않습니다. 아침 요약의 PR 절에 `gh` 인증이 필요하면 `~/.config/claude-loop/env` 에 토큰을 export 하는 줄 (또는 토큰을 export 하는 파일을 `source` 하는 줄) 을 사용자가 직접 넣어야 한다고 알립니다. 이 파일은 대신 고치지 않습니다
- 세션을 야간 루프에 넣는 방법 (태스크 `notes.md` 의 `## 루프` 절과 `claude-loop approve <세션>`) 은 플러그인 README 를 가리킵니다
