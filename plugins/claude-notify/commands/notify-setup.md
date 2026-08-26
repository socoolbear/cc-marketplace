---
description: claude-notify 초기 설정 — terminal-notifier 확인, ntfy 토픽 결정, config 생성, 테스트 발송
disable-model-invocation: true
allowed-tools: Read, Write, Bash(command -v:*), Bash(brew:*), Bash(mkdir:*), Bash(cat:*), Bash(curl:*), Bash(node:*), Bash(python3:*), Bash(echo:*), AskUserQuestion
---

claude-notify 플러그인의 초기 설정을 진행합니다. 아래 순서를 그대로 따르고, 각 단계 결과를 한국어로 짧게 보고하세요.

이름표 — 이 문서에서 쓰는 용어:
- **로컬 알림**: `terminal-notifier` 로 띄우는 macOS 알림 센터 알림
- **모바일 푸시**: `ntfy` 서버로 보내 휴대폰 ntfy 앱이 받는 알림
- **config**: `~/.config/claude-notify/config.json`

**이 설정의 핵심은 2단계입니다.** ntfy 토픽에는 기본값이 없어서, 설정하기 전까지 모바일 푸시는 아예 동작하지 않습니다 (로컬 알림만 옵니다).

## 1. terminal-notifier 설치 확인

```bash
command -v terminal-notifier
```

없으면 설치 명령을 안내하고, 사용자에게 설치할지 물어보세요.

```bash
brew install terminal-notifier
```

설치를 건너뛰어도 설정은 계속 진행합니다 (모바일 푸시는 terminal-notifier 없이도 동작합니다). 다만 로컬 알림이 나가지 않는다는 점을 알려주세요.

## 2. ntfy 토픽 결정

AskUserQuestion 으로 토픽 이름을 받으세요. 질문할 때 아래를 **반드시** 함께 안내합니다.

> ntfy.sh 의 공개 토픽은 **토픽 이름이 곧 비밀번호** 입니다. 토픽 이름을 아는 사람은 누구나 그 토픽을 구독해 알림 내용을 볼 수 있습니다. `claude`, `notify`, `<이름>-claude` 처럼 추측 가능한 이름은 쓰지 마세요. 예: `claude-a7f3k9x2mq`

사용자가 이름을 떠올리기 어려워하면 무작위 후보를 만들어 제시하세요.

```bash
node -e 'console.log("claude-" + [...crypto.getRandomValues(new Uint8Array(8))].map(b=>b.toString(36)).join("").slice(0,12))'
```

서버는 기본값 `https://ntfy.sh` 를 사용합니다. 사용자가 자체 호스팅 ntfy 서버를 쓴다고 하면 그 주소와 (필요하면) 토큰을 받으세요. 토큰이 없으면 config 의 `token` 키는 아예 넣지 마세요.

## 3. config 생성

먼저 기존 파일이 있는지 확인합니다.

```bash
cat ~/.config/claude-notify/config.json 2>/dev/null || echo "NO_CONFIG"
```

**이미 있으면 덮어쓰기 전에 반드시 사용자에게 확인** 을 받으세요. 이때 기존 내용을 보여주되 `token` 값은 앞 4자만 남기고 마스킹해서 출력합니다 (예: `tk_ab****`).

디렉토리를 만들고 파일을 씁니다.

```bash
mkdir -p ~/.config/claude-notify
```

`~/.config/claude-notify/config.json` 내용 (토픽·서버는 2단계에서 받은 값으로 치환):

```json
{
  "ntfy": {
    "server": "https://ntfy.sh",
    "topic": "<사용자가-정한-토픽>"
  },
  "terminal_notifier": { "enabled": true },
  "log": { "enabled": false, "level": "info" },
  "skip_when_active": true
}
```

각 키의 의미를 한 줄씩 설명해 주세요.

| 키 | 의미 |
|---|---|
| `ntfy.server` · `ntfy.topic` | 모바일 푸시를 보낼 서버와 토픽. **토픽이 비면 ntfy 채널은 동작하지 않습니다** |
| `ntfy.token` | 인증이 필요한 자체 호스팅 서버용. ntfy.sh 공개 토픽이면 생략 |
| `terminal_notifier.enabled` | 로컬 알림 사용 여부 |
| `log.enabled` · `log.level` | `~/.config/claude-notify/notify.log` 기록 여부와 수준 (`info` / `debug`) |
| `skip_when_active` | 터미널이 foreground 일 때 알림을 건너뜀 (보고 있는 화면에 중복 알림을 띄우지 않기 위함) |

쓴 뒤 JSON 이 유효한지 확인합니다.

```bash
python3 -m json.tool ~/.config/claude-notify/config.json >/dev/null && echo "CONFIG OK"
```

## 4. 테스트 발송

5단계 구독 안내를 **먼저** 하고, 사용자가 휴대폰에서 구독을 마쳤다고 답한 뒤에 발송하세요.

`CLAUDE_NOTIFY_FORCE=true` 는 터미널 활성 스킵과 채널 축소를 둘 다 무시하고 설정된 **모든 채널** 로 보냅니다. 이 한 번의 호출로 로컬 알림과 모바일 푸시가 동시에 나갑니다.

```bash
echo '{"hook_event_name":"Notification","notification_type":"permission_prompt","message":"claude-notify 설정 테스트"}' \
  | CLAUDE_NOTIFY_FORCE=true CLAUDE_NOTIFY_LOG=true CLAUDE_NOTIFY_LOG_LEVEL=debug node "${CLAUDE_PLUGIN_ROOT}/bin/claude-notify.mjs"
echo "exit=$?"
```

이어서 실제 훅과 같은 조건 (강제 모드 없이) 으로도 한 번 돌립니다.

```bash
echo '{"hook_event_name":"Stop","session_id":"setup-test","transcript_path":"/tmp/t","cwd":"/tmp","permission_mode":"auto","stop_hook_active":false}' \
  | node "${CLAUDE_PLUGIN_ROOT}/bin/claude-notify.mjs"
echo "exit=$?"
```

이 두 번째 호출은 `skip_when_active` 가 `true` 이고 지금 터미널이 foreground 면 **아무 알림도 내보내지 않는 것이 정상** 입니다. 사용자에게 이 점을 먼저 알리세요.

발송 결과는 로그로 확인합니다 (로그는 실제로 발생한 일과 일치합니다 — 건너뛴 채널은 `sent` 로 찍히지 않습니다).

```bash
tail -n 20 ~/.config/claude-notify/notify.log
```

사용자에게 **어느 쪽이 도착했는지** 물어보고, 안 온 채널이 있으면 `/claude-notify:notify-doctor` 로 넘기세요.

## 5. 모바일 구독 안내

- ntfy 앱 설치: iOS App Store / Android Play Store 에서 `ntfy`
- 앱에서 **Subscribe to topic** → 토픽 이름 입력 (자체 호스팅이면 서버 주소도 함께)
- 브라우저로도 확인 가능: `https://ntfy.sh/<토픽>`

토픽 이름은 비밀번호와 같으니 공유하지 말라고 한 번 더 짚어주세요.

## 6. 마무리

설정이 끝나면 아래를 한 줄씩 보고합니다.

- 만든 config 경로
- 선택한 토픽 (전체 이름 그대로 — 사용자가 휴대폰에 입력해야 하므로 마스킹하지 않습니다)
- terminal-notifier 설치 여부
- 테스트 결과 (모바일 푸시 / 로컬 알림 각각)
- 문제가 생기면 `/claude-notify:notify-doctor` 를 쓰라는 안내
