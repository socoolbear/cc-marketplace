# Harness — Reflect 모드 (세션 학습 → 문서 승격)

세션 중 누적된 피드백·교정 사항을 팀 공유 아티팩트 (AGENTS.md, GLOSSARY.md, LESSONS.md 등) 로 승격한다.
개인·머신 로컬 학습은 auto-memory 가 담당하고, 본 모드는 그중 **repo 에 남길 가치가 있는 것**만 골라 올린다.

> **진입점**: 라우터가 `lastReflect` 이후 신규 학습 소스 존재 시 보조 옵션으로 노출하고, 사용자 선택 시 분기한다.
>
> **원칙: 자동 쓰기 없음.** 모든 승격은 분류 → **사용자 승인** → append. 완전 자동 반영은 하지 않는다.

## 워크플로우

### Phase 0: 사전 확인

- `harness/.harness.json` 존재 확인 (부재 시 종료 + setup 안내)
- 학습 소스 (둘 다 선택, 둘 다 없으면 종료):

| 소스 | 경로 | 포맷 |
|------|------|------|
| auto-memory feedback | `${CLAUDE_PROJECT_DIR}/memory/feedback_*.md` (없으면 `~/.claude/projects/<slug>/memory/`) | frontmatter + 본문 |
| 인라인 inbox (선택) | `harness/inbox.md` | `- REMEMBER: ...` / `- 규칙: ...` 접두사 줄 |

- 기준 시각: `.harness.json` 의 `lastReflect` (부재 = 전체 대상)

### Phase 1: 수집 + 중복 제거 (읽기 전용)

1. `lastReflect` 이후 feedback 파일 + inbox 마커 줄 수집, `{ source, signal, evidence }` 로 정규화
2. 이미 반영된 것 제거: AGENTS.md / `harness/*.md` / settings 를 rg 로 확인, 매칭 시 drop + 해당 feedback frontmatter 에 `applied: YYYY-MM-DD` 마킹
3. 잔존 0건이면 `lastReflect` 만 갱신 후 종료

### Phase 2: 분류

| 신호 패턴 | 목적지 | 처리 |
|----------|--------|------|
| 코딩 규칙·경계 ("항상 X", "절대 Y 금지") | AGENTS.md 관리 섹션 (경계 등) | append (승인 후) |
| 용어 정의·표기 교정 ("X 는 Y 라고 부른다", "A = B 로 통일") | `harness/GLOSSARY.md` 용어 표 | 행 append (승인 후, 등재 기준 → document-formats 5절) |
| 반복 실수의 교훈 | `harness/LESSONS.md` | **2회 규칙** 적용 — 첫 발생은 defer, 두 번째 발생만 등재 (document-formats 6절) |
| 자동 행동 요청 ("X 때마다 Y") / 반복 승인 패턴 | settings hooks / permissions | delegate — `/update-config` · `/fewer-permission-prompts` 안내만 |
| 도메인 특화 반복 조사 | 새 sub-agent | scaffold (`.claude/agents/<name>.md` TODO 헤더만, 승인 후) |
| 아키텍처 불변 조건·전략적 결정 | ARCHITECTURE.md / ADR.md | **manual 권고만** (직접 쓰기 X — 작업 에이전트/사람이 같은 커밋 원칙으로 반영) |
| 분류 모호 | — | defer (다음 reflect 재평가) |

### Phase 3: 승인 + 적용

1. 분류 결과를 채팅으로 보고 (보고서 파일 없음)
2. AskUserQuestion: direct-append 일괄/개별, scaffold 개별, delegate 는 통지만
3. 승인된 항목만 append (GLOSSARY 는 가나다 순 위치 삽입, 기존 행 수정 X)
4. 마무리: `.harness.json` 의 `lastReflect` 갱신 + 적용된 feedback frontmatter 에 `applied` 마킹

## 적용하지 않는 것

- settings hooks/permissions 직접 수정 (delegate), 새 skill 자동 생성 (`skill-creator` 안내만)
- ARCHITECTURE.md·ADR.md 직접 수정 (manual 권고만 — CONTRACTS 5절)
- sub-agent 본문 자동 작성 (scaffold 만)

## 참고

- 공유 규약: `../CONTRACTS.md` / 등재 기준: `../references/document-formats.md` 5~6절
- 위임 대상: `update-config` (hooks) · `fewer-permission-prompts` (permissions) · `skill-creator` (새 skill)
