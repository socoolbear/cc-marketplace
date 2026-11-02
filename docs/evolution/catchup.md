# catchup 진화 기록

최신이 위. 형식은 `.claude/skills/evolve/SKILL.md` 의 "결정 기록" 절.

## 2026-11-02 — 공식 "이전 대화 조회" 문구 검토 (1.0.0, 변경 없음)

자료: Claude Code CHANGELOG (https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md — "Added a warning on Pro and Max plans when resuming an inactive conversation … start a new conversation and Claude can look up the previous one if you refer to it"), 공식 문서 https://code.claude.com/docs/en/sessions.md · https://code.claude.com/docs/en/interactive-mode.md#session-recap. 정기 sweep 이 후보로 올림.

| 판정 | 항목 | 근거 | 재검토 조건 |
|---|---|---|---|
| 보류 | catchup deprecate | 공식 기능은 Pro·Max·Ultra 의 "Resume this conversation?" 다이얼로그 문구로만 나온다. 기능 이름·조회 방식·세션 선택 기준·요약 여부가 문서에 없고, 세션 도구 목록에도 과거 대화 조회 도구가 없다. sources.md 기준 (요금제 한정·미문서화) 상 보류 | 공식 문서에 독립 기능 (이름·조회 방식) 으로 실리거나, 세션 도구 목록에 과거 대화 조회 도구가 생기면 |
| 기각 | `/resume` 으로 대체 | `/resume` 은 이전 대화 전체를 다시 불러온다. 그 비용이 바로 이 다이얼로그가 경고하는 사용량 소모다. catchup 은 요약만 가져오므로 용도가 다르다 | `/resume` 에 요약만 불러오는 옵션이 생기면 |
| 기각 | transcript 파싱을 `claude -p --resume <id> "요약해줘"` 로 교체 | 공식 문서가 transcript JSONL 을 내부 형식 (버전마다 바뀔 수 있음) 이라고 명시해 파싱 위험은 있다. 하지만 이 경로도 전체 대화를 불러오는 비용이 같다 | 번들 스크립트가 형식 변경으로 파싱에 실패하면 |
| 기록 | eval 추가 안 함 | 플러그인 동작 변경 없음 | — |
