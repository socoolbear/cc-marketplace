# sessions 진화 기록

최신이 위. 형식은 `.claude/skills/evolve/SKILL.md` 의 "결정 기록" 절.

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
