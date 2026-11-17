# sessions 진화 기록

최신이 위. 형식은 `.claude/skills/evolve/SKILL.md` 의 "결정 기록" 절.

## 2026-11-17 — child-session 스킬 추가 (1.3.0)

자료: 사용 흔적 — 업무 태스크 하나를 흐름 5개 (repo·worktree 가 서로 다름, 흐름마다 사용자 결정·운영 배포 확인) 로 나눠 손으로 새 세션을 띄우고 브리프 파일 하나로 맡긴 사례. 같은 날 겪은 문제: 같은 이름의 부모 세션 둘 (자식이 보고를 엉뚱한 부모에게 보냄), 여러 세션이 같은 기록 파일을 고침, 전역 규칙이 바뀌어도 떠 있는 세션은 옛 규칙으로 일함. side-task 스킬 (1.2.0) 의 분기 방식과 비교 (사용자 요청).

| 판정 | 항목 | 근거 | 재검토 조건 |
|---|---|---|---|
| 반영 | child-session 스킬 (새 세션 + 브리프 + 새 window + 보고 규약 + 전파 + 닫기 판단) | 몇 시간~며칠 가는 흐름에서는 분기의 장점 (인계 손실 없음) 보다 단점이 크다 — 부모만큼 찬 컨텍스트로 시작해 곧 compact, 매 턴 부모 대화를 함께 실음, 기록이 대화에만 남음. 브리프는 계약·compact 뒤 재시작 지점이 되고, 인계 손실은 브리프가 결정 로그를 가리키고 `[시작]` 계획 요약을 부모가 확인해 줄인다 | 공식 기능이 브리프를 받는 자식 세션 띄우기·보고를 제공하면 deprecate |
| 반영 | side-task 와 별도 스킬 (모드 추가 안 함) | 분기와 새 세션은 맞는 일·맥락·화면이 달라 한 스킬에 섞으면 설명이 복잡해진다 (사용자 결정). side-task description 에 child-session 으로 가는 경계를 적음 | — |
| 반영 | `[진행]` 태그 (단계가 끝날 때마다) | 긴 흐름은 부모가 상태를 볼 수 없다. 손으로 쓴 브리프에서 쓰던 규약 | 보고가 형식적으로만 쌓이면 빈도 조정 |
| 기각 | `[진행]` "늦어도 1시간마다"·부모의 "1시간 넘게 조용하면 묻기" | 대기 중인 세션은 시간을 재서 깨어날 수단이 없어 지켜질 수 없다 (리뷰 지적) | 세션이 스스로 정해진 시각에 깨어나는 공식 기능이 생기면 |
| 모순 해결 | side-task `spawn.sh` 의 첫 지시가 `--add-dir` 값으로 먹힘 | `--add-dir <directories...>` 는 값을 여러 개 받는다. `claude -p --add-dir /tmp "<지시>"` 가 "read as a value of --add-dir" 오류로 실패, `--` 를 넣으면 정상 (직접 확인). 두 스크립트 모두 첫 지시 앞에 `--` | — |
| 반영 | 첫 지시를 spawn.sh 가 조립 (`--parent-ref` 포함), `[시작]` 에 window id, 닫기 후보에 "window 에 pane 하나" | 첫 지시와 `--brief` 가 어긋날 수 없게, 같은 이름 부모가 둘일 때 보고가 엉뚱한 세션으로 가지 않게, 부모 compact 뒤에도 닫을 대상을 알게, 자식이 연 side-task 패널이 함께 닫히지 않게 (리뷰 지적) | — |
| 반영 | 규칙·결정 전파 절 (부모 → 자식) | 떠 있는 세션은 바뀐 CLAUDE.md·AGENTS.md 를 다시 읽지 않는다 (같은 날 확인) | 공식 기능이 실행 중 세션에 규칙 재로드를 지원하면 |
| 정리 | 자식 규약·닫기 판단이 side-task 와 비슷하지만 따로 둠 | repo 규칙: 스킬 자료는 스킬 디렉토리 안에만 둔다. 공유 reference 로 빼지 않음 | 두 규약이 세 번 이상 같이 바뀌면 공통화 방법 재검토 |
| 기록 | eval 추가 안 함 | side-task 와 같은 이유 (tmux 의 살아 있는 세션·메시지 왕복). 실제 자식 세션 스모크로 검증 — 띄우기 → `[시작]` → `[완료]` → `[닫기 확인]` → `닫아도 됨` → window 닫기. 처음 여는 디렉토리는 폴더 신뢰 확인 창에서 멈춤을 확인해 알려진 한계에 적음 | eval 이 tmux·세션 간 메시징을 지원하면 |
| 기록 | 설계 검증과 구현 검증을 한 라운드로 | 사용자가 판정 표 (대화 중 비교표) 를 보고 바로 승인해 구현 뒤 diff 로 함께 검증 | — |

## 2026-11-16 — side-task 스킬 추가 (1.2.0)

자료: 사용 흔적 — 업무 태스크 세션에서 곁가지 작업을 손으로 분기한 세션 (`<부모>-<접미사>` 이름, 같은 tmux window 의 패널) 이 잦고, 분기 세션이 부모와 같은 git checkout·같은 기록 파일을 써서 한 브랜치에 무관해 보이는 커밋이 함께 놓인 사례. `claude --help` 의 `--resume` + `--fork-session` + `-n`, 공식 `SendMessage`·`ListAgents`.

| 판정 | 항목 | 근거 | 재검토 조건 |
|---|---|---|---|
| 반영 | side-task 스킬 (fork + 옆 패널 + 보고 규약 + 닫기 판단) | 맥락을 이어받는 분기는 공식 `--fork-session`, 보고는 공식 `SendMessage` 로 되지만 패널 분할·git 분리·공유 기록 파일 단일 작성자·닫기 판단을 묶는 절차가 없다 | 공식 기능이 fork 세션을 패널로 띄우고 부모에게 보고하게 되면 deprecate |
| 반영 | 플러그인 위치 = sessions | "세션 관련 도구 묶음" 취지에 맞고 설치 목록이 늘지 않는다 (사용자 결정). 플러그인 전체 deprecated 표시를 떼고 crosstalk 소개에만 남김 (deprecation.md 2번 "일부만이면") | — |
| 반영 | 완료 후 패널은 남기고 부모가 닫기를 판단 | 사용자 결정. 부모가 남은 일·미답 질문·worktree 미커밋을 보고 후보를 정하고, 분기 세션이 `닫아도 됨` 이라고 답할 때만 닫는다 (분기 세션 진행 상태는 부모가 볼 수 없음) | 닫기 확인 왕복이 매번 형식적으로만 오가면 단순화 |
| 기각 | 분기 세션 worktree 기본 위치 (`<checkout>-<접미사>`) | 하위 디렉토리를 repo 로 세는 워크스페이스 (taskspace `tasks/<ID>/*/`) 에서 hold·resume·link 가 오동작. 워크스페이스 규칙 > 사용자에게 묻기 | — |
| 보류 | taskspace 에 곁가지 worktree 위치 규칙 추가 | 지금은 분기 세션이 묻는 것으로 충분 | 분기 세션이 taskspace 에서 위치를 반복해서 묻게 되면 |
| 기록 | crosstalk 삭제 재검토의 대상 | 앞 회차의 "deprecate 후 60일" 삭제는 이제 **crosstalk 스킬만** 대상이다. 플러그인은 side-task 때문에 남긴다 | — |
| 기록 | eval 추가 안 함 | tmux 안의 살아 있는 세션 두 개와 메시지 왕복이 필요해 eval 샌드박스로 재현할 수 없다. 구현 때 실제 분기 스모크 두 번 (맥락·이름·닫기 / git 분리·공유·질문·닫지 않음) 으로 검증 | eval 이 tmux·세션 간 메시징을 지원하면 |

## 2026-10-06 — crosstalk 를 공식 세션 간 메시징으로 대체 (1.1.0)

자료: Claude Code CHANGELOG (https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md — 2.1.224 cross-session `SendMessage`, 이후 provider 확장·`--restricted` 수정), 공식 문서 https://code.claude.com/docs/en/cross-session-messaging · https://code.claude.com/docs/en/settings-reference#crosssessioninbound, 로컬 세션의 `SendMessage`·`ListAgents` 도구 정의. 정기 sweep 첫 실행이 후보로 올림.

| crosstalk 기능 | 공식 기능 | 빠지는 것 |
|---|---|---|
| `recv --name` 이름 등록 (충돌 시 접미사) | `/rename`·`--name`, 자동 이름 | 없음 |
| Monitor 상주 수신 대기 | 수신함 기본 켜짐, 다음 도구 라운드에 전달 | 없음 |
| `send` (600자 넘으면 spool 파일) | `SendMessage`, 본문 전체 | 없음 |
| `list` (이름·cwd) | `ListAgents` (이름·cwd·상태) | 없음 |
| disconnect | `/config` "Messages from your other sessions" (v2.1.232+) | 끄는 범위가 세션이 아니라 사용자 전체 |
| `fyi:` 핑퐁 방지 규약 | 보낸 쪽별 제한·중복 제거·대기 상한 | 없음 |

| 판정 | 항목 | 근거 | 재검토 조건 |
|---|---|---|---|
| deprecate | crosstalk 스킬 | 이름 지정 (`/rename`)·보내기 (`SendMessage`, 본문 전체)·목록 (`ListAgents`)·수신 (기본 켜짐)·수신 끄기 (`/config` "Messages from your other sessions") 가 모두 공식 기능과 겹침. v2.1.224 이상이면 따로 켤 것 없음 | 삭제: deprecate 후 60일 + 그 기간 memory·이슈에 crosstalk 언급 없음 |
| 기각 | deprecate 연기 (권한 모드 차이) | 모드가 다른 세션끼리는 메시지마다 승인 창 (5분 뒤 버림) 이 뜨지만 `crossSessionInbound: "accept"` 로 풀리는 설정 차이 — 안내 문구에 남김 | `crossSessionInbound` 가 관리자 전용 설정으로 바뀌면 |
| 기각 | 이름 지정·수신 대기·`fyi:` 핑퐁 방지 규약 차이 | 공식 문서가 보낸 쪽별 제한·중복 제거·대기 상한으로 반복을 막음. 수신 끄기는 사용자 전체에 적용되는 차이만 남음 | 세션 하나만 수신을 끄는 일이 반복해서 필요해지면 |
| 기록 | eval 추가 안 함 | 동작 변경 없이 안내 문구·표시만 추가 | — |
