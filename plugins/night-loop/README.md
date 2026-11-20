# night-loop

사람이 없는 밤에 태스크 세션에 일을 맡기고, 아침에 결과를 요약하는 장치입니다. macOS · tmux 전용입니다.

이름표 — **러너**: `claude-loop` 명령 (`bin/claude-loop`). **야간 모드**: 러너가 밤에 일을 맡긴 세션의 상태. **야간 가드** · **검증 게이트**: 야간 모드 세션에서만 일하는 훅 두 개.

## 무엇을 하는가

| 구성 | 하는 일 |
|---|---|
| `claude-loop night` (매일 01:30) | opt-in 한 태스크 세션이 열려 있고 쉬는 중이면 그 세션에 지시를 보내고, 없으면 tmux 새 window 로 연다. 지시문은 `prompts/night.md` |
| `claude-loop brief` (매일 08:30) | 야간 로그 · `[loop]` 커밋 · 내 열린 PR · 질문 대기열을 모아 아침 보고서를 만들고 야간 모드를 끝낸다. 지시문은 `prompts/brief.md` |
| 야간 가드 (`hooks/night-guard.sh`) | 야간 모드 세션의 위험 동작 — PR 머지·댓글, 보호 브랜치·강제 push, 워크플로 실행, 인프라·DB 명령, 외부로 보내는 요청, 쓰기 MCP, 지시·설정 파일 수정, 새 세션·팀메이트 띄우기 — 을 확인창에서 멈춘다. 사람이 그 세션에 입력하면 야간 모드를 푼다 |
| 검증 게이트 (`hooks/loop-verify-gate.sh`) | 야간 모드 세션이 턴을 끝낼 때 검증 명령을 돌려, 실패하면 끝내지 못하게 막는다 (세션당 3번까지) |

두 훅은 야간 모드가 아닌 세션에서는 아무것도 하지 않습니다.

## 설치

```bash
/plugin install night-loop@socoolbear-cc-marketplace
/night-loop:setup        # 장비마다 한 번 — claude-loop install 을 돌린다
```

`claude-loop install [--workspace <경로>]` 가 하는 일:

- `~/.local/bin/claude-loop` 실행 파일을 쓴다. launchd 와 단축키가 부르는 고정 경로다. 플러그인 설치본 경로는 버전마다 바뀌므로, 이 파일은 실행될 때마다 러너를 찾는다 — 장비 설정의 `CLAUDE_LOOP_ROOT`, 없으면 Claude Code 의 플러그인 설치 기록 순서
- launchd 예약 두 개 (`com.socoolbear.claude-loop-night` · `-brief`) 를 `~/Library/LaunchAgents/` 에 쓰고 등록한다
- 장비 설정 파일 `~/.config/claude-loop/env` 가 없으면 만든다 (있으면 건드리지 않는다)

되돌리기는 `claude-loop uninstall` (예약과 실행 파일을 지우고 장비 설정·상태는 남긴다).

### 장비 설정 — `~/.config/claude-loop/env`

셸 파일입니다. `night` · `brief` · `list` · `approve` 가 읽습니다.

```bash
CLAUDE_LOOP_WORKSPACE=<태스크 워크스페이스 루트>   # 필수. <루트>/*/tasks/*/notes.md 에서 opt-in 줄을 찾는다
# CLAUDE_LOOP_ROOT=<플러그인 폴더>                  # 선택. 설치본 대신 이 폴더의 러너를 쓴다 (플러그인을 고치는 장비)
# launchd 는 셸 설정을 읽지 않는다. gh 인증 토큰처럼 필요한 값은 여기서 export 한다
```

## 세션을 야간 루프에 넣기 (opt-in)

태스크 `notes.md` 에 아래 절을 두고, 사용자가 직접 승인합니다.

```markdown
## 루프
- 세션: <세션 이름> | 검증: <검증 명령>
```

```bash
claude-loop approve <세션 이름>    # 지금 적힌 검증 명령을 승인
claude-loop list                   # opt-in 줄과 승인 상태
```

승인한 뒤 누군가 그 줄의 검증 명령을 바꾸면 다시 승인할 때까지 그 세션을 건너뜁니다 — 에이전트가 고친 명령이 밤에 실행되는 길을 막으려는 것입니다.

## 명령

| 명령 | 하는 일 |
|---|---|
| `claude-loop night` · `brief` | launchd 가 부른다. `CLAUDE_LOOP_DRY=1` 은 판정만 출력, `CLAUDE_LOOP_FORCE=1` 은 실행 허용 구간 (night 00~06시, brief 07~11시) 을 무시 |
| `claude-loop end` | 야간 모드를 끝낸다 (상태 파일 정리). brief 가 끝에 부른다 |
| `claude-loop list` · `approve <세션>` | opt-in 목록 · 검증 명령 승인 |
| `claude-loop board` | 열려 있는 세션의 상태 꼬리표를 한 화면에 보여준다 (꼬리표 파일을 쓰는 멈춤 점검 훅이 따로 있어야 내용이 찬다) |
| `claude-loop install` · `uninstall` | 장비 등록 · 해제 |

끄기: `touch ~/.local/state/claude-loop/night.disabled` (night 만), `touch ~/.local/state/claude-loop/disabled` (night · brief 전부).

## 야간 모드 판정 (다른 훅과의 약속)

야간 모드 여부는 아래 파일과 환경 변수로 정해집니다. 다른 훅이 야간에 다르게 동작하려면 같은 조건을 읽으면 됩니다.

| 조건 | 뜻 |
|---|---|
| `~/.local/state/claude-loop/night/<세션 ID>` 파일이 있다 | 러너가 이미 열려 있던 세션에 일을 보냈다 (JSON: `name` · `verify` · `task_dir`) |
| 환경 변수 `CLAUDE_NIGHT=1` 이고 `night/active` 가 있고 `night/released/<세션 ID>` 가 없다 | 러너가 새로 연 세션이고, 밤이 끝나지 않았고, 사람이 돌아와 풀지 않았다 |

`brief` 가 끝나면 이 파일들을 모두 지웁니다.

## 이 플러그인이 하지 않는 것

- **야간 배포 차단과 야간 질문 차단** — 야간 모드에서 배포 명령을 확인창으로 돌리는 것과 `AskUserQuestion` 을 막는 것은 이 플러그인의 훅이 아닙니다. 위 판정 조건을 읽는 다른 훅이 맡습니다 — 배포는 `deploy-guard` 플러그인의 배포 점검 훅, 질문은 질문 점검 훅. 그 훅들이 없는 장비에서는 야간 가드가 잡는 동작 (push·머지·워크플로 실행 등) 까지만 막힙니다
- **아침 요약의 질문 지표** — PATH 에 `loop-metrics` 명령이 있으면 그 출력을 싣고, 없으면 그 절을 비웁니다
- 목록 방식의 한계: 야간 가드는 명령 문자열을 봅니다. 목록 밖의 새 위험 동작은 막지 못하므로 브랜치 보호와 아침 요약의 사후 검토로 보완합니다

## 시험

```bash
bash tests/run.sh
```

격리한 HOME 에서 훅에 시험 입력을 넣고, 가짜 `claude` · `tmux` · `launchctl` 로 러너를 돌립니다. 실제 세션 · launchd · 상태 폴더는 건드리지 않습니다.

실제로 실린 훅이 설치본인지 다른 폴더인지는 `claude --debug` 로그의 훅 명령 경로로 확인합니다.
