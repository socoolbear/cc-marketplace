# sessions 진화 기록

최신이 위. 형식은 `.claude/skills/evolve/SKILL.md` 의 "결정 기록" 절.

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
