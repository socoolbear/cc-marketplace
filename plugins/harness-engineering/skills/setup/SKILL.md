---
name: harness-engineering
description: "프로젝트에 하네스 엔지니어링 인프라를 구축하는 스킬. OpenAI/Anthropic 의 하네스 엔지니어링 방법론을 적용하여 (1) 지식 아키텍처 재구성 (AGENTS.md 를 지도로, docs/ 를 시스템 오브 레코드로), (2) 아키텍처 불변 조건의 기계적 강제 (레이어 경계 검사, Hook, 린트), (3) 3-에이전트 파이프라인 (Planner→Generator→Evaluator), (4) 품질 점수 추적, (5) 실패 방지 메커니즘을 설정한다. '하네스 엔지니어링 적용', '프로젝트에 하네스 구축', '3-에이전트 파이프라인 설정', '레이어 경계 강제', '품질 추적 설정', 'OpenAI/Anthropic 하네스 방법론 적용' 요청 시 사용. 기존 harness 스킬(에이전트 팀 설계)과 다름 — 이 스킬은 프로젝트 인프라 구축에 초점."
---

# Harness Engineering — 프로젝트 인프라 구축

OpenAI 와 Anthropic 의 하네스 엔지니어링 방법론을 프로젝트에 적용하는 스킬.
에이전트가 대규모/장기 프로젝트를 안정적으로 실행할 수 있는 인프라를 구축한다.

**기존 `harness` 스킬과의 관계:**
- `harness` = 에이전트 팀 아키텍처 설계 (누가 무엇을 하는가)
- `harness-engineering` = 프로젝트에 하네스 인프라 구축 (지식, 강제, 추적, 프로토콜)
- 두 스킬은 보완적이다. `harness` 로 팀을 설계한 뒤, `harness-engineering` 으로 실행 인프라를 구축한다.

## 핵심 원칙 (출처)

| 원칙 | 출처 | 설명 |
|------|------|------|
| 지도, 백과사전 아님 | OpenAI | AGENTS.md 는 ~100줄의 포인터 모음. 상세는 docs/ 하위에 |
| 생성과 평가의 분리 | Anthropic | 자기 평가 편향 제거. Generator 와 Evaluator 를 별도 에이전트로 |
| 스프린트 계약 | Anthropic | 코딩 전에 측정 가능한 성공 기준 합의 |
| 기계적 강제 | OpenAI | 아키텍처 불변 조건은 문서가 아닌 코드/린트로 강제 |
| 컨텍스트 리셋 > 압축 | Anthropic | Phase 간 완전한 컨텍스트 리셋, 파일로만 인수인계 |
| 품질 점수 추적 | OpenAI | 레이어/Phase 별 점수를 기계 판독 가능한 형태로 시간순 추적 |
| 가비지 컬렉션 | OpenAI | 패턴 드리프트를 주기적으로 탐지하고 수정 |

## 워크플로우

### Phase 1: 프로젝트 분석

프로젝트의 현재 상태를 파악한다. Explore 에이전트로 병렬 조사:

**1-1. 구조 분석:**
- 기존 문서 목록 (`docs/`, `README.md`, `AGENTS.md`, `CLAUDE.md`)
- 소스 디렉터리 구조 (`src/` 하위 레이어 식별)
- 설정 파일 (package.json, tsconfig, eslint, etc.)
- 테스트 인프라 (vitest, jest, playwright, etc.)

**1-2. 아키텍처 식별:**
- 레이어 구조가 있는가? (있다면 레이어 이름과 import 방향)
- 타입 경계가 있는가? (외부 입력, 내부 상태, 저장 포맷 등)
- 의존성 정책이 있는가? (허용/금지 패키지)

**1-3. 이력 파악:**
- 이전 실패 기록이 있는가? (implementation log, postmortem)
- 알려진 위험 요소가 문서화되어 있는가?
- Phase/마일스톤 계획이 있는가?

**1-4. 현재 품질 상태:**
- 테스트 통과율
- 린트 에러 수
- 타입 에러 수

산출물: `_workspace/analysis-report.md`

### Phase 2: 지식 아키텍처 구축

프로젝트의 문서를 "지도 + 시스템 오브 레코드" 구조로 재편한다.

상세 패턴 → `references/knowledge-architecture.md`

**2-1. AGENTS.md 재작성 (지도 형태, ~100줄):**

모든 섹션이 심화 문서로 포인터를 제공한다:
- 프로젝트 개요 (5줄)
- 현재 상태 → `_workspace/current-phase.md`
- 명령어 (빌드, 테스트, 린트, 개발 서버)
- 아키텍처 요약 → `docs/architecture.md`
- Phase 실행 테이블 → `docs/phases/phase-N-*.md`
- 교훈 요약 → `docs/references/*.md`
- 아키텍처 강제 도구 → `scripts/`
- 문서 지도 (전체 문서 디렉터리 인덱스)

**2-2. docs/ 구조 생성:**

```
docs/
  architecture.md              # 아키텍처 규칙 (권위적 원천)
  phases/                      # Phase 별 스펙 + 성공 기준
    phase-0-*.md
    phase-1-*.md
    ...
  references/                  # 핵심 레퍼런스 (실패 교훈, 타입 계약 등)
  quality/                     # 품질 점수 + 추적 로그
    scores.json
    quality-log.md
  legacy-*/                    # 기존 문서 (동결, 읽기 전용)
```

**2-3. docs/architecture.md 생성:**

프로젝트의 아키텍처 규칙을 하나의 권위 문서로 통합:
- 레이어 구조 (이름, 책임, 제약, 허용 import)
- 타입 경계 (생산/소비 관계)
- 의존성 정책
- 파일 컨벤션
- 빌드/배포 방식

**2-4. Phase 스펙 생성:**

각 Phase 별 독립 파일. 필수 섹션:
- 목표 (1-2줄)
- 산출물 (구체적 파일/함수)
- 성공 기준 (측정 가능한 체크리스트)
- 위험 요소 (이전 실패 기록 반영)
- 의존성 (이전 Phase 결과)
- 레이어 범위

**2-5. 레퍼런스 추출:**

이전 실패 기록, 타입 계약, 핵심 도메인 지식을 독립 문서로 추출.
각 문서는 자기완결적이어야 한다 — 다른 문서 참조 없이 해당 주제를 완전히 이해할 수 있을 것.

### Phase 3: 기계적 강제 설정

아키텍처 규칙을 코드와 도구로 강제한다. 문서에만 의존하지 않는다.

상세 패턴 → `references/mechanical-enforcement.md`

**3-1. 레이어 경계 검사 스크립트:**

`scripts/check-layer-import.js` 생성 (또는 `scripts/generate-layer-check.js` 로 자동 생성).

기능:
- 프로젝트의 레이어 DAG 정의
- import/require 문 정적 분석
- 위반 시 **수정 방법이 포함된** 에러 메시지 출력
- 단일 파일 검사 + 전체 src/ 스캔 지원
- 금지 의존성 검사 (React in core, 외부 패키지 등)

에러 메시지 형식 (OpenAI 패턴 — 에이전트가 즉시 수정할 수 있도록):
```
ERROR: 레이어 위반 — src/types/foo.ts
       types/ 가 core/ 를 import 합니다.
       types/ 가 import 할 수 있는 레이어: (없음)
       수정: 공유 로직은 types/ 로 이동하세요.
       규칙: docs/architecture.md
```

**3-2. Claude Code Hook 설정:**

`.claude/settings.local.json` 에 PostToolUse Hook:
- Edit/Write 시 레이어 경계 검사 자동 실행
- src/ 하위 파일에만 적용
- `|| true` 로 경고만 (차단 아님 — 에이전트가 자발적으로 수정)

**3-3. 컨벤션 검사 (선택):**

프로젝트에 파일 컨벤션이 있다면 검사 스크립트 추가:
- 파일명 네이밍 규칙
- 배럴 export 존재 여부
- 테스트 파일 배치 규칙

### Phase 4: Phase 실행 인프라

3-에이전트 파이프라인과 품질 추적 시스템을 설정한다.

상세 프로토콜 → `references/phase-execution-protocol.md`
품질 추적 스키마 → `references/quality-tracking.md`
실패 방지 → `references/failure-prevention.md`

**4-1. _workspace/ 디렉터리:**

Phase 실행의 모든 중간 산출물을 저장:
```
_workspace/
  current-phase.md              # 현재 Phase + 상태
  phase-N-contract.md           # 스프린트 계약서 (Planner 산출물)
  phase-N-eval.md               # 평가 결과 (Evaluator 산출물)
  phase-N-completion.md         # 완료 기록 (다음 Phase 인수인계)
```

**4-2. 3-에이전트 파이프라인 설정:**

```
Planner (Plan, 읽기 전용) → 스프린트 계약서
    ↓
Generator (general-purpose) → 구현
    ↓
Evaluator (general-purpose) → 검증 + 품질 채점
    ↓ (FAIL: 수정 지시서 → Generator, 최대 3회)
완료 → _workspace/phase-N-completion.md
```

핵심 분리 원칙:
- Generator 는 Evaluator 의 평가 기준 상세를 못 봄
- Evaluator 는 Generator 의 추론을 못 봄
- Phase 간 컨텍스트 리셋 — 파일로만 인수인계

**4-3. 스프린트 계약서 템플릿:**

```markdown
# Phase N 스프린트 계약서

## 성공 기준
(측정 가능한 체크리스트)

## 아키텍처 불변 조건
(이 Phase 에서 검증할 규칙)

## 필요 Fixture/데이터
(테스트에 필요한 데이터)

## 알려진 위험
(이전 실패에서 배운 것)

## 종료 기준
(Evaluator 가 확인할 항목)
```

**4-4. 품질 추적 초기화:**

`docs/quality/scores.json` — 기계 판독 가능한 품질 점수:
- Phase 별 상태 (pending/completed)
- 레이어 별 커버리지, API 안정성, 문서 정합성
- 전체 테스트 수, 통과율, 타입 에러, 린트 에러, 레이어 위반

`docs/quality/quality-log.md` — 시간순 품질 추적 로그.

**4-5. 실패 방지 메커니즘:**

이전 실패 기록이 있는 Phase 에 대해:
- 사전 분석 에이전트 (읽기 전용) 를 코딩 전 실행
- 스프린트 계약에 실패 원인별 필수 검증 항목 포함
- E2E 테스트에 자동 검증 추가

### Phase 5: 검증

생성된 인프라가 정상 동작하는지 확인한다.

**5-1. 구조 검증:**
- AGENTS.md 가 ~100줄이고 모든 포인터가 유효한지
- docs/phases/ 의 모든 파일이 성공 기준을 포함하는지
- docs/quality/scores.json 이 유효한 JSON 인지

**5-2. 기계적 강제 검증:**
- `scripts/check-layer-import.js` 가 의도적 위반에서 에러를 내는지
- Hook 이 설정되어 있는지 (`.claude/settings.local.json`)

**5-3. 파이프라인 검증:**
- `_workspace/current-phase.md` 가 존재하는지
- 첫 Phase 의 스프린트 계약서를 작성할 수 있는 상태인지

## 산출물 체크리스트

Phase 2~4 완료 후 프로젝트에 존재해야 하는 파일:

- [ ] `AGENTS.md` — 지도 형태 (~100줄)
- [ ] `docs/architecture.md` — 아키텍처 규칙 (권위적 원천)
- [ ] `docs/phases/phase-N-*.md` — Phase 별 스펙 (성공 기준 포함)
- [ ] `docs/references/*.md` — 핵심 레퍼런스 (실패 교훈, 타입 계약 등)
- [ ] `docs/quality/scores.json` — 품질 점수 초기 상태
- [ ] `docs/quality/quality-log.md` — 품질 추적 로그
- [ ] `scripts/check-layer-import.js` — 레이어 경계 검사 스크립트
- [ ] `.claude/settings.local.json` — PostToolUse Hook
- [ ] `_workspace/current-phase.md` — 현재 Phase 상태

## 적용하지 않는 것

- 에이전트 팀 설계 → 기존 `harness` 스킬 사용
- 에이전트 정의 파일 생성 → 기존 `harness` 스킬 사용
- 스킬 생성 → `skill-creator` 스킬 사용
- CI/CD 파이프라인 설정 → 별도 도구 사용

## 프로젝트 유형별 조정

**레이어 구조가 없는 프로젝트:**
- Phase 3 의 레이어 경계 검사를 생략하거나, 디렉터리 기반이 아닌 모듈 기반 규칙으로 대체

**Phase/마일스톤 계획이 없는 프로젝트:**
- Phase 2-4 에서 Phase 스펙을 먼저 정의. 사용자에게 주요 마일스톤을 질문하여 Phase 구조를 도출

**이전 실패 기록이 없는 프로젝트:**
- Phase 4-5 의 실패 방지 메커니즘을 간소화. 스프린트 계약의 "알려진 위험" 섹션을 "예상 위험"으로 대체

**모노레포 내 패키지:**
- 명령어에 `--filter` 를 포함. 의존성 정책에 모노레포 내 다른 패키지 경계를 명시

## 참고

- 지식 아키텍처 패턴: `references/knowledge-architecture.md`
- 기계적 강제 패턴: `references/mechanical-enforcement.md`
- 3-에이전트 파이프라인 상세: `references/phase-execution-protocol.md`
- 품질 추적 스키마: `references/quality-tracking.md`
- 실패 방지 메커니즘: `references/failure-prevention.md`
