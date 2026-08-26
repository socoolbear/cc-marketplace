---
description: claude-notify 진단 — 의존성·번들·config·중복 훅·로그를 점검하고 테스트 알림을 발송
disable-model-invocation: true
allowed-tools: Read, Bash(command -v:*), Bash(ls:*), Bash(cat:*), Bash(tail:*), Bash(node:*), Bash(python3:*), Bash(echo:*), Bash(curl:*)
---

claude-notify 가 제대로 붙어 있는지 6가지를 점검합니다. **중간에 멈추지 말고 6개를 모두 실행** 한 뒤, 마지막에 표로 한 번에 보고하세요. 실패한 항목에는 바로 실행할 수 있는 해결 명령을 붙입니다.

## 1. terminal-notifier 설치

```bash
command -v terminal-notifier || echo "MISSING"
```

없으면: `brew install terminal-notifier`. 없어도 모바일 푸시는 동작하지만 로컬 알림은 나가지 않습니다.

## 2. node 실행 가능 여부 + 번들 존재

```bash
command -v node || echo "MISSING"
node -v 2>/dev/null
ls -l "${CLAUDE_PLUGIN_ROOT}/bin/claude-notify.mjs" 2>/dev/null || echo "MISSING_BUNDLE"
```

- 번들은 Node 18+ 면 동작합니다. 파일 **크기가 0 이면 훅이 조용히 실패** 하므로 크기도 함께 확인하세요.
- 훅은 로그인 셸이 아닌 환경에서 실행됩니다. `command -v node` 결과가 `~/.local/share/mise/...` 나 `~/.nvm/...` 아래 **뿐** 이라면, 훅 실행 시점에 `node` 를 못 찾을 수 있습니다. 이 위험을 사용자에게 알리고 `brew install node` 로 `/opt/homebrew/bin/node` 를 함께 두는 것을 권하세요.

## 3. config 존재 + 파싱

```bash
cat ~/.config/claude-notify/config.json 2>/dev/null || echo "NO_CONFIG"
python3 -m json.tool ~/.config/claude-notify/config.json >/dev/null 2>&1 && echo "PARSE OK" || echo "PARSE FAIL"
```

판정 기준:

| 상태 | 의미 | 조치 |
|---|---|---|
| `NO_CONFIG` | ntfy 토픽에 **기본값이 없습니다.** 모바일 푸시가 아예 나가지 않고 로컬 알림만 옵니다 | `/claude-notify:notify-setup` |
| `ntfy.topic` 이 빈 문자열 | 위와 동일 | `/claude-notify:notify-setup` |
| `PARSE FAIL` | JSON 문법 오류 | 문제 줄을 짚어주고 고칠 방법 제시 |

**출력할 때 `ntfy.token` 값은 앞 4자만 남기고 마스킹** 하세요 (예: `tk_ab****`). 토픽 이름은 사용자가 휴대폰에 입력해야 하므로 마스킹하지 않습니다.

## 4. 구 버전 수동 훅 잔존 확인

플러그인 훅과 예전에 손으로 넣은 훅이 같이 있으면 **알림이 두 번** 갑니다.

```bash
python3 -c '
import json, os, sys
p = os.path.expanduser("~/.claude/settings.json")
if not os.path.exists(p):
    print("NO_SETTINGS"); sys.exit()
try:
    hooks = json.load(open(p)).get("hooks", {})
except Exception as e:
    print("PARSE_FAIL", e); sys.exit()
found = []
for event, groups in hooks.items():
    for gi, g in enumerate(groups or []):
        for hi, h in enumerate(g.get("hooks", []) or []):
            cmd = h.get("command", "")
            if "claude-notify" in cmd and "CLAUDE_PLUGIN_ROOT" not in cmd:
                found.append((event, gi, hi, cmd))
print("NONE" if not found else "\n".join(f"{e}[{gi}].hooks[{hi}]: {c}" for e, gi, hi, c in found))
'
```

`~/.local/bin/claude-notify` 를 가리키는 항목이 나오면, 해당 항목을 `~/.claude/settings.json` 에서 **지우라고 안내** 하세요. 출력에 찍힌 경로 (`Notification[0].hooks[0]` 형태) 를 그대로 알려주면 사용자가 찾기 쉽습니다. settings.json 은 사용자 소유 설정이므로 **직접 수정하지 말고 안내만** 합니다.

## 5. 최근 로그

```bash
tail -n 30 ~/.config/claude-notify/notify.log 2>/dev/null || echo "NO_LOG"
```

- 로그가 비활성이면 (`log.enabled: false`, 기본값) 파일이 없는 것이 정상입니다.
- 로그는 **실제로 발생한 일과 일치합니다.** 건너뛴 채널은 `sent via ...` 로 찍히지 않으니, 로그를 근거로 판정해도 됩니다.
- 자주 보게 될 줄:

| 로그 | 의미 |
|---|---|
| `[WARN] Ntfy: 토픽이 설정되지 않아 발송을 건너뜁니다` | 3번의 `NO_CONFIG` 와 같은 원인 → setup 필요 |
| `[ERROR] TerminalNotifier: terminal-notifier 를 실행할 수 없습니다` | 실행 파일 자체가 없음 → `brew install terminal-notifier` |
| `[ERROR] TerminalNotifier: ... exitCode=N` | 실행은 됐고 실패함. macOS 알림센터가 간헐적으로 0 이 아닌 코드를 돌려주는 사례가 있으니, **1회 실패만으로 고장으로 판정하지 말고** 6번 테스트를 2~3회 반복해 보세요 |

디버깅이 필요하면 config 의 `log` 를 `{"enabled": true, "level": "debug"}` 로 바꾸거나, 한 번만 볼 때는 6번처럼 환경변수로 켜세요.

## 6. 테스트 발송

먼저 **강제 모드** 로 두 이벤트를 각각 보냅니다. `CLAUDE_NOTIFY_FORCE=true` 는 터미널 활성 스킵과 채널 축소를 둘 다 무시하고 설정된 모든 채널로 발송하므로, 지금 터미널을 보고 있어도 알림이 실제로 나갑니다.

```bash
echo '{"hook_event_name":"Notification","notification_type":"permission_prompt","message":"notify-doctor 테스트"}' \
  | CLAUDE_NOTIFY_FORCE=true CLAUDE_NOTIFY_LOG=true CLAUDE_NOTIFY_LOG_LEVEL=debug node "${CLAUDE_PLUGIN_ROOT}/bin/claude-notify.mjs"
echo "exit=$?"
```

```bash
echo '{"hook_event_name":"Stop","session_id":"doctor-test","transcript_path":"/tmp/t","cwd":"/tmp","permission_mode":"auto","stop_hook_active":false}' \
  | CLAUDE_NOTIFY_FORCE=true CLAUDE_NOTIFY_LOG=true CLAUDE_NOTIFY_LOG_LEVEL=debug node "${CLAUDE_PLUGIN_ROOT}/bin/claude-notify.mjs"
echo "exit=$?"
```

이어서 **실제 훅과 같은 조건** (강제 모드 없이) 으로 한 번 더 돌립니다.

```bash
echo '{"hook_event_name":"Notification","notification_type":"permission_prompt","message":"평상시 조건 테스트"}' \
  | node "${CLAUDE_PLUGIN_ROOT}/bin/claude-notify.mjs"
echo "exit=$?"
```

**판정 기준을 먼저 사용자에게 알리세요.** 이 마지막 호출은 `skip_when_active` 가 `true` 이고 지금 터미널이 foreground 면 알림을 내보내지 않는 것이 **정상 동작** 입니다. 종료 코드가 0 이면 훅 자체는 살아 있습니다.

발송 직후 로그를 다시 읽어 어느 채널이 실제로 나갔는지 확인합니다.

```bash
tail -n 25 ~/.config/claude-notify/notify.log
```

ntfy 서버 도달만 따로 떼어 확인하려면 (토픽은 3번에서 읽은 값):

```bash
curl -fsS -H "Title: notify-doctor" -d "ntfy 직접 발송 테스트" "https://ntfy.sh/<토픽>"
```

## 보고 형식

| 항목 | 결과 | 조치 |
|---|---|---|
| terminal-notifier | ✅ / ❌ | |
| node + 번들 | ✅ / ❌ | |
| config | ✅ / ⚠️ 토픽 미설정 (ntfy 미동작) / ❌ 파싱 실패 | |
| 중복 훅 | ✅ 없음 / ⚠️ 발견 | |
| 로그 | 최근 N줄 / 꺼짐 | |
| 테스트 발송 | 강제 모드: 로컬 ✅ · 모바일 ✅ / 평상시 조건: exit=N | |

표 아래에 **가장 먼저 할 일 한 가지** 를 한 줄로 적으세요. 모두 정상이면 "이상 없습니다" 로 끝냅니다.
