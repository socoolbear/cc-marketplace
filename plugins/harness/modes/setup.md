# Harness — Setup 모드 (0 → 1 구축)

하네스가 없는 프로젝트에 경량 하네스 (지속 지식 문서 + 선택적 기계적 강제) 를 1회성으로 구축한다.

> **진입점**: 사용자는 `/harness` 만 호출한다. 라우터 (`../skills/harness/SKILL.md`) 가 본 모드로 분기한다.
>
> **사전 지식**: [`../CONTRACTS.md`](../CONTRACTS.md) (원칙·레이아웃·보호 규칙), [`../references/document-formats.md`](../references/document-formats.md) (문서 골격의 정답). 본 파일은 **셋업 행동**만 정의한다.

## 워크플로우

### Phase 0: 재실행 가드

- `harness/.harness.json` 존재, 또는 AGENTS.md + `harness/` 문서가 이미 존재 → **중단** + 안내: "이미 셋업되어 있습니다. `/harness` 재호출 시 라우터가 update/audit 으로 분기합니다."
- v1 흔적 (`docs/quality/.harness-version`) 감지 → **중단** + 안내: "v1 하네스입니다. setup 이 아니라 update 모드의 v1→v2 마이그레이션 소관입니다 — `/harness` 를 재호출하세요."
- 강제 재설치는 AskUserQuestion 재확인 후에만: 기존 `harness/` 와 AGENTS.md 를 `_archive/YYYY-MM-DD-before-reset/` 로 백업 후 진행.

### Phase 1: 프로젝트 분석 (읽기 전용)

Explore 서브에이전트로 병렬 조사한다. 어떤 파일도 수정하지 않는다.

**1-1. 구조**: 기존 문서 (README, docs/, AGENTS.md, CLAUDE.md), 소스 디렉토리, 설정 파일, 테스트 인프라. 모노레포 서브패키지면 앵커 = 현재 디렉토리 (CONTRACTS 3절).

**1-2. 검증 명령**: 빌드/테스트/린트/타입체크의 실제 명령을 확인하고 **실행해서 존재를 검증**한다 (AGENTS.md "검증 명령" 소절의 재료 — 없는 도구는 항목 제외).

**1-3. 아키텍처 불변 조건 후보**: 레이어 구조와 import 방향, 타입 경계, 금지 패턴. **현황 서술이 아니라 규칙만** 수집한다.

**1-4. 결정 이력 후보**: 이미 존재하는 명시적 아키텍처 결정 (회고 ADR 후보).

**1-5. 용어 후보 — 표기 불일치만**: 커밋 제목·문서·코드 간 한/영 혼용, 비자명 축약어, 도메인어↔코드명 불일치. **자명한 1:1 매핑은 수집하지 않는다** (document-formats 5절 등재 기준).

### Phase 2: 문서 생성

골격의 정답 → `../references/document-formats.md`. 각 문서에 실재하지 않는 내용을 채워 넣지 않는다 (빈 골격 허용).

**2-1. `AGENTS.md`** (1절 골격, ≤40줄): 검증 명령 / 지식 문서 포인터 4개 / 경계 (≤5줄) / 문서 유지 규칙 2줄. 기존 AGENTS.md 가 있으면 사용자 작성 섹션을 보존하고 관리 섹션만 재구성한다.

**2-2. `CLAUDE.md` 브리지** (2절): 부재 시 `@AGENTS.md` 한 줄 생성. 존재 시 보존 + import 부재 사실만 안내.

**2-3. `harness/ARCHITECTURE.md`** (3절): 1-3 의 불변 조건만. 레이어 구조가 없으면 실재하는 불변 조건 섹션만.

**2-4. `harness/ADR.md`** (4절): 골격 + 1-4 의 기존 결정을 회고 항목으로 (상태 `Accepted`, 결정일은 추정 가능하면 추정, 아니면 적용일).

**2-5. `harness/GLOSSARY.md`** (5절): 골격 + 1-5 에서 확인된 불일치 **최대 10행**. 행 목록을 AskUserQuestion 으로 확인받은 뒤 기록한다 (대량 사전화 금지 — 이후 축적은 reflect/수동 소관). 후보 0건이면 빈 골격.

**2-6. `harness/LESSONS.md`** (6절): 빈 골격. 기존 실패 기록 문서가 있으면 이관을 제안한다.

**2-7. `.gitignore` 정비** (git 저장소인 경우만): 다음 항목이 없으면 append 한다 (있으면 무변경, `.gitignore` 부재 시 생성):
- `.prompts/` — 프로젝트 로컬 프롬프트 모음 (머신 로컬, 커밋 금지)
- `.claude/settings.local.json` — 머신별 설정 (Phase 3 의 enforcement hook 포함)
- `.claude/worktrees/` — git worktree 생성 위치 (CONTRACTS 3절 worktree 규약)

기존 `.gitignore` 의 다른 항목은 절대 수정·삭제하지 않는다 (append 만).

**2-8. 탐색·검사 범위에서 worktree 제외 확인**: 린트/타입체크/테스트 설정이 전역 글롭 (예: `**/*.ts`) 을 쓰는 경우, `.claude/worktrees` 제외 누락 시 사용자 확인 후 추가한다 (예: tsconfig `exclude`, ESLint flat config `ignores`, vitest/jest `exclude`). rg·fd 등 gitignore 준수 도구는 2-7 만으로 충분하다. `src/` 등 좁은 include 만 쓰는 설정은 손대지 않는다.

### Phase 3: 기계적 강제 (선택)

1-3 에서 레이어 구조가 감지된 경우에만, AskUserQuestion 1건으로 적용 여부를 확인한다:

> 레이어 구조가 감지되었습니다. 레이어 경계를 코드로 강제할까요? (검사 스크립트 + 수정 시 자동 검사 hook + CI 연동)

- **Y**: `scripts/check-layer-import.js` 생성 (`../scripts/generate-layer-check.js` 활용, ARCHITECTURE.md 레이어 표와 DAG 동기화) + `.claude/settings.local.json` PostToolUse hook + `package.json` 에 `check:layers` 스크립트 등록 + CI 포함 안내. 상세 → `../references/mechanical-enforcement.md`
- **n** 또는 레이어 구조 없음: skip. AGENTS.md 의 "레이어 검사" 항목도 제외.

### Phase 4: 검증 + 마커

1. AGENTS.md 가 40줄 이내이고 포인터 4개가 유효한지
2. "검증 명령" 의 각 명령이 실제 실행 가능한지
3. `harness/` 문서 4종이 표준 골격 섹션을 갖추었는지
4. (enforcement 시) 의도적 위반 파일로 스크립트가 에러 메시지를 내는지 확인 후 원복
5. `harness/.harness.json` 생성: `{ "version": "{plugin.json 의 version}" }` (`lastReflect` 는 reflect 첫 실행 시 추가)

## 산출물 체크리스트

- [ ] `AGENTS.md` (≤40줄) / `CLAUDE.md` 브리지
- [ ] `harness/ARCHITECTURE.md` / `ADR.md` / `GLOSSARY.md` / `LESSONS.md`
- [ ] `harness/.harness.json`
- [ ] `.gitignore` 에 `.prompts/` + `.claude/settings.local.json` + `.claude/worktrees/` (git 저장소인 경우)
- [ ] (선택) `scripts/check-layer-import.js` + hook + `check:layers`

## 적용하지 않는 것

- 파이프라인 프롬프트/템플릿, 품질 점수, 로그 파일, phase 스펙 생성 — v2 에서 폐지 (내장 플랜 모드·태스크·코드 리뷰·auto-memory 소관, CONTRACTS 1절 원칙 5)
- 기존 문서 대량 재작성 — 이관·정리는 사용자 확인 후에만

## 참고

- 공유 규약: `../CONTRACTS.md` / 문서 골격: `../references/document-formats.md` / 기계적 강제: `../references/mechanical-enforcement.md`
