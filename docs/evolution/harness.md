# harness 진화 기록

최신이 위. 형식은 `.claude/skills/evolve/SKILL.md` 의 "결정 기록" 절.

## 2026-10-06 — 규칙 수명 관리 도입 (4.2.0, 4.1.0 포함)

자료: Notion "에이전트 하네스 규칙의 수명 관리" (prime-agent `/refine` + 세대별 GC 각색), `PrimeIntellect-ai/prime-agent`.

| 판정 | 항목 | 근거 | 재검토 조건 |
|---|---|---|---|
| 기각 | harness 를 prime-agent `/refine` 로 대체 | `/refine` 은 prime-agent 런타임 내장 (Claude Code 에서 실행 불가). 대상도 개인 보조 프롬프트로, 팀 문서·레이어 강제를 다루지 않음 | Claude Code 에 같은 기능이 공식 출시되면 |
| 반영 | memory `발생:` 날짜로 재발 횟수, 서로 다른 날 2회부터 LESSONS (4.1.0) | 기존 "2회 규칙" 은 판정 수단이 없었고 보류 건이 다시 수집되지 않았음 | — |
| 반영 | 사용자 명시 지시는 1회라도 등재 후보, 스스로 알아챈 실수만 2회 규칙 | 사용자 결정 | — |
| 반영 | 근거 필터 (feedback 한정), 검사 우선 (이미 검사가 잡는 것만 제외) | Notion "다른 방법으로 알 수 있는 사실은 프롬프트에 넣지 않는다" | — |
| 반영 | 신호 스크립트가 `metadata.modified` 와 mtime 중 늦은 쪽 사용 (4.1.0) | 실측: memory 42개 중 6개가 본문 수정 후 `modified` 미갱신 | — |
| 반영 | changelog 알림, 검증 명령 재감지 ⑦ (4.2.0) | minor 변경을 알릴 길이 없었고, 새 검증 도구를 감지하지 못했음 | — |
| 반영 | 승격 시각을 memory 디렉토리 `.harness-reflect.json` 으로 이동, 기준값 없으면 전체 수집 (4.2.0) | 커밋된 `lastReflect` 때문에 다른 머신의 학습이 빠짐. 마커 mtime 은 pull 로 바뀌어 기준 불가 | — |
| 반영 | 등재 후 재발 N회 보고 (4.2.0) | 승격된 규칙의 효과를 측정할 수단이 없었음 | — |
| 기각 | 원장·rollback·cold 상태 도입 | git 과 기존 보호 규칙 (본문 삭제 금지) 이 이미 맡음 | — |
| 보류 | LESSONS 템플릿 (`document-formats.md`) 에 "서로 다른 날"·사용자 지시 예외 반영 | 골격 변경 = major bump + 기존 설치본에 구버전 잔재 보고 | 다음 major 릴리스 때 함께 |
| 보류 | 팀원 여럿의 같은 실수 합산 | 1회 관찰을 repo 에 커밋해야 해 골격 변경 + 2회 규칙 취지 약화 | 팀 공유 memory 같은 공식 기능이 나오면 |
| 보류 | 학습 승격·changelog 알림·⑦ 의 eval 케이스 | 범위 초과로 매번 미룸 — 모델 동작 변경이 검증되지 않은 상태 | 다음 harness evolve 때 우선 처리 |
