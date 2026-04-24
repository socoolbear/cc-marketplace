# 표준 파일 매니페스트

update 스킬이 비교할 표준 파일 목록과 각 파일의 "정답" 출처.
정답은 `../../setup/SKILL.md` 의 해당 섹션에서 추출한다.

---

## 매니페스트 구조

각 파일은 다음 카테고리 중 하나에 속한다:

| 카테고리 | 설명 | 업데이트 대상? |
|----------|------|---------------|
| `protection` | 사용자 데이터 / 진행 이력 / 불변 이력 | ❌ 존재만 확인, 내용은 절대 건드리지 않음 |
| `stock-templates` | 스킬이 표준 제공하는 문서 템플릿 | ✅ PRISTINE/CUSTOMIZED 판정 |
| `stock-prompts` | 스킬이 표준 제공하는 파이프라인 프롬프트 | ✅ PRISTINE/CUSTOMIZED 판정 (플레이스홀더 치환 제외) |
| `structural` | 버전업 시 신설되는 파일/디렉터리 | ✅ MISSING 이면 생성 |
| `agents-md-sections` | AGENTS.md 안에서 스킬이 관리하는 섹션 | ✅ 섹션 단위 삽입/교체 |
| `scripts` | 스킬이 제공하는 스크립트 | ✅ PRISTINE/CUSTOMIZED 판정 |

---

## 1. 절대 보존 (protection)

사용자 데이터. update 는 이 파일들의 **존재만 확인**하고 **내용은 수정하지 않는다.**

| 파일 / 디렉터리 | 보호 이유 |
|----------------|-----------|
| `_workspace/current-phase.md` | 현재 진행 상태 (초기화 시 이력 소실) |
| `_workspace/phase-*-contract.md` | Phase 별 스프린트 계약서 (실행 산출물) |
| `_workspace/phase-*-completion.md` | Phase 완료 기록 (이력) |
| `_workspace/phase-*-eval.md` | Phase QA 평가 결과 (이력) |
| `_workspace/phase-*-self-review.md` | Phase 자기 리뷰 결과 (이력) |
| `_workspace/phase-*-reference-analysis.md` | 사전 분석 결과 (이력) |
| `_workspace/phase-*-fix-directive-*.md` | 수정 지시서 (이력) |
| `_workspace/phase-*-*-retry-*.md` | 수정 루프 산출물 (이력 — audit 대상) |
| `_workspace/analysis-report.md` | setup Phase 1 분석 결과 |
| `_workspace/audit-*.md` | audit 보고서 |
| `_workspace/update-plan-*.md` | update 플랜 (본인 이전 실행) |
| `docs/quality/scores.json` | 품질 점수 이력 (초기화 시 재앙) |
| `docs/quality/quality-log.md` | 평가 로그 (누적 이력) |
| `docs/quality/audit-log.md` | audit 실행 로그 |
| `docs/quality/update-log.md` | update 실행 로그 (본인이 append 만) |
| `docs/adr/NNNN-*.md` (발행된 ADR 본문) | ADR 불변 원칙 |
| `docs/references/failure-lessons.md` 의 본문 내용 | 누적 교훈 (섹션 추가는 가능, 본문 수정 금지) |
| `docs/legacy-*/` | 동결 정책 |
| `docs/phases/phase-*-*.md` | Phase 스펙 (프로젝트 고유) |
| `_archive/` | 과거 archive |
| `.claude/settings.local.json` | Hook/권한 설정 (사용자 직접 편집) |
| `docs/architecture.md` | 아키텍처 권위적 원천 (update 가 수정하지 않음) |

`docs/quality/.harness-version` 은 **예외** — update 가 Phase 5 에서 갱신 대상.

---

## 2. 표준 템플릿 (stock-templates)

정답 출처: `../../setup/SKILL.md` Phase 4-2

| 파일 | 정답 섹션 |
|------|-----------|
| `_workspace/templates/sprint-contract.md` | Phase 4-2 의 `sprint-contract.md` 코드 블록 |
| `_workspace/templates/self-review.md` | Phase 4-2 의 `self-review.md` 코드 블록 |
| `_workspace/templates/completion-record.md` | Phase 4-2 의 `completion-record.md` 코드 블록 |
| `_workspace/templates/fix-directive.md` | Phase 4-2 의 `fix-directive.md` 코드 블록 |

---

## 3. 표준 프롬프트 (stock-prompts)

정답 출처: `../../setup/SKILL.md` Phase 4-3

| 파일 | 정답 섹션 |
|------|-----------|
| `_workspace/prompts/pre-analysis.md` | Phase 4-3 의 `pre-analysis.md` 코드 블록 |
| `_workspace/prompts/planner.md` | Phase 4-3 의 `planner.md` 코드 블록 |
| `_workspace/prompts/generator.md` | Phase 4-3 의 `generator.md` 코드 블록 |
| `_workspace/prompts/self-reviewer.md` | Phase 4-3 의 `self-reviewer.md` 코드 블록 |
| `_workspace/prompts/evaluator.md` | Phase 4-3 의 `evaluator.md` 코드 블록 |

**플레이스홀더 주의**:
- 표준 내용에는 `{빌드 명령어}`, `{테스트 명령어}`, `{타입체크 명령어}`, `{린트 명령어}`, `{레이어 검사 명령어}` 가 포함되어 있다
- 프로젝트 파일은 setup 이 이미 치환한 상태 (예: `npm run build`)
- 비교 시 치환 위치의 차이는 **사용자 커스터마이징이 아님**

---

## 4. 구조 (structural — 신설 파일/디렉터리)

정답 출처: `../../setup/SKILL.md` Phase 2-6

| 파일 | 정답 섹션 | 기본 동작 |
|------|-----------|-----------|
| `docs/adr/TEMPLATE.md` | Phase 2-6 의 TEMPLATE 코드 블록 | 없으면 생성, 있으면 stock-template 로 처리 |
| `docs/adr/README.md` | Phase 2-6 의 README 코드 블록 | 없으면 빈 인덱스 생성. **있으면 인덱스 테이블 보존** + 상단 헤더/작성 규칙 섹션만 교체 대상 |

**주의 — `docs/adr/README.md` 특수 처리**:
- 이 파일은 빈 인덱스로 시작하지만 Evaluator 가 ADR 을 발행할 때마다 테이블에 행이 추가된다
- update 가 전체 교체하면 **발행된 ADR 인덱스가 리셋됨** — 재앙
- 대응: 상단 `# Architecture Decision Records` ~ `## 작성 규칙` 섹션만 교체 대상, 중간의 **테이블 전체는 보존**

---

## 5. AGENTS.md 관리 섹션 (agents-md-sections)

AGENTS.md 전체가 아닌 **특정 섹션**만 스킬이 관리한다.

| 섹션 | 정답 출처 | 식별 방법 |
|------|-----------|-----------|
| "Phase 실행 — 4단계 파이프라인" | `../../setup/SKILL.md` Phase 4-4 | `## Phase 실행 — 4단계 파이프라인` 마크다운 헤더 |
| 문서 지도의 ADR 포인터 | `../../setup/SKILL.md` Phase 2-1 | `아키텍처 결정 이력 → docs/adr/README.md` 라인 |

**원칙**:
- AGENTS.md 는 **전체 교체 금지**
- 관리 섹션이 없으면 **파일 끝에 append**
- 관리 섹션이 있으면 PRISTINE/CUSTOMIZED 판정 후 사용자 승인에 따라 해당 섹션만 교체

---

## 6. 스크립트 (scripts)

| 파일 | 처리 |
|------|------|
| `scripts/check-layer-import.js` | 프로젝트 특화 (레이어 DAG, 금지 의존성) 되어 있을 가능성 높음. 기본 **CUSTOMIZED 로 처리** (PRISTINE 이면 예외적으로 업데이트) |
| `scripts/generate-layer-check.js` | 프로젝트 특화 정도가 낮음. PRISTINE 이면 업데이트 |

---

## 7. 플레이스홀더 치환 감지

setup 이 치환하는 플레이스홀더:
- `{빌드 명령어}` → 예: `npm run build`, `pnpm build`, `yarn build`
- `{테스트 명령어}` → 예: `npm test`, `vitest`, `pytest`
- `{타입체크 명령어}` → 예: `tsc --noEmit`, `mypy`
- `{린트 명령어}` → 예: `eslint .`, `ruff check`
- `{레이어 검사 명령어}` → 예: `node scripts/check-layer-import.js`

**비교 알고리즘**:
1. 프로젝트 파일에서 플레이스홀더 위치에 들어있는 명령어를 추출
2. 표준 내용의 플레이스홀더 위치에 해당 명령어를 삽입
3. 삽입 후 정규화 비교 (공백 정규화)
4. 일치 → PRISTINE, 불일치 → CUSTOMIZED

---

## 8. 버전 간 차이 지도

update 가 참조할 "이 버전에서 무엇이 바뀌었는지" 요약.

### v1.0.0 → v1.1.0 (ADR 통합)

**신설 (MISSING 예상)**:
- `docs/adr/TEMPLATE.md`
- `docs/adr/README.md`
- `docs/quality/.harness-version`

**구조 변경** (기존 파일에 섹션 추가):
- `_workspace/templates/sprint-contract.md` — "관련 ADR" / "예상 ADR 후보" 섹션 추가
- `_workspace/templates/completion-record.md` — "아키텍처 결정" / "발행된 ADR" / "번복된 ADR" 섹션 추가
- `_workspace/prompts/planner.md` — 입력 파일에 `docs/adr/README.md` 추가, 작업 4-5 (ADR 링크/후보 판단) 추가
- `_workspace/prompts/evaluator.md` — 입력 파일에 `docs/adr/` 추가, 작업 7 (ADR 점검) 추가, PASS 출력 4 (ADR 발행) 추가
- `AGENTS.md` — 문서 지도에 "아키텍처 결정 이력 → docs/adr/README.md" 포인터 추가

향후 버전에서도 이 섹션을 확장하여 차이 지도를 유지한다.
