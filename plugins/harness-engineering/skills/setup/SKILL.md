---
name: harness-engineering
description: "프로젝트에 하네스 엔지니어링 인프라를 구축하는 스킬. OpenAI/Anthropic 의 하네스 엔지니어링 방법론을 적용하여 (1) 지식 아키텍처 재구성 (AGENTS.md 를 지도로, docs/ 를 시스템 오브 레코드로), (2) 아키텍처 불변 조건의 기계적 강제 (레이어 경계 검사, Hook, 린트), (3) 4단계 파이프라인 (설계→구현→자기리뷰→QA 평가), (4) 품질 점수 추적, (5) 실패 방지 메커니즘을 설정한다. '하네스 엔지니어링 적용', '프로젝트에 하네스 구축', '4단계 파이프라인 설정', '레이어 경계 강제', '품질 추적 설정', 'OpenAI/Anthropic 하네스 방법론 적용' 요청 시 사용. 기존 harness 스킬(에이전트 팀 설계)과 다름 — 이 스킬은 프로젝트 인프라 구축에 초점."
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
| 생성과 평가의 분리 | Anthropic | 자기 평가 편향 제거. 구현→자기 리뷰→QA 평가를 별도 컨텍스트로 분리 |
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
- 에이전트 정의 (`.agents/`, `harness` 스킬 산출물, 커스텀 에이전트 등)

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
- 아키텍처 결정 이력 → `docs/adr/README.md`
- Phase 실행 테이블 → `docs/phases/phase-N-*.md`
- 교훈 요약 → `docs/references/*.md`
- 아키텍처 강제 도구 → `scripts/`
- 문서 지도 (전체 문서 디렉터리 인덱스)

**2-2. docs/ 구조 생성:**

```
docs/
  architecture.md              # 아키텍처 규칙 (현재 스냅샷, 권위적 원천)
  adr/                         # 아키텍처 결정 이력 (ADR)
    README.md                  # 인덱스
    TEMPLATE.md                # 새 ADR 작성용 템플릿
    0001-*.md
    ...
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

**2-6. ADR 인프라 생성:**

아키텍처 결정 이력을 관리할 디렉터리와 템플릿/인덱스를 생성한다.
`docs/architecture.md` 가 "현재 아키텍처는 이렇다"의 스냅샷이라면, `docs/adr/` 는 "왜 이렇게 결정했나"의 이력이다.
두 문서는 상호 보완적이며, ADR 은 전략적 결정 발생 시점에 추가된다.

상세 패턴 → `references/adr-pattern.md`

`docs/adr/TEMPLATE.md` 생성:

```markdown
# ADR-NNNN: [결정 제목]

## 상태
- **Proposed** | Accepted | Deprecated | Superseded by [ADR-NNNN](NNNN-...)
- 결정일: YYYY-MM-DD
- Phase: N (해당하는 경우)

## 맥락 (Context)
왜 이 결정이 필요한가?
- 문제 상황
- 기존 접근의 한계
- 제약 조건

## 결정 (Decision)
어떻게 하기로 했는가? (선택한 방안 + 구체적인 규칙/구조)

## 대안 (Alternatives)
- 대안 A — 기각 이유
- 대안 B — 기각 이유

## 결과 (Consequences)
- 긍정적: 얻는 것
- 부정적: 감수하는 것
- 중립적: 파생 작업

## 관련
- Phase: `docs/phases/phase-N-*.md`
- 규칙: `docs/architecture.md#섹션`
- 후속 ADR: (있다면)
```

`docs/adr/README.md` 생성 (빈 인덱스):

```markdown
# Architecture Decision Records

이 프로젝트의 아키텍처 결정 이력.
새 결정이 발생하면 `TEMPLATE.md` 를 복사하여 `NNNN-title.md` 로 작성한다.
번호는 4자리 zero-padded, 재사용 금지.

| 번호 | 제목 | 상태 | Phase | 결정일 |
|------|------|------|-------|--------|
| (첫 결정이 기록되면 여기에 추가) | | | | |

## 작성 규칙
- 전략적 결정만 기록 (레이어 구조, 타입 경계, 핵심 의존성, 금지 패턴 등)
- 기존 ADR 은 사후 수정 금지 — 번복 시 새 ADR 작성 후 기존 ADR 을 `Superseded` 로 변경
- 상세 기준: `skill 의 references/adr-pattern.md` 참조
```

**기존 아키텍처 결정의 ADR 회고 작성 (선택):**

프로젝트에 이미 명시적 아키텍처 결정이 존재한다면 (레이어 구조가 이미 정해져 있거나, `docs/architecture.md` 에 핵심 규칙이 정의되어 있는 경우), 해당 결정들을 ADR 로 회고하여 기록한다:
- `0001-layer-structure.md` — 레이어 구조 도입 결정
- `0002-type-boundary.md` — 타입 경계 결정
- 기타 현재 아키텍처의 핵심 규칙들

회고 ADR 은 상태를 `Accepted` 로, 결정일은 추정 가능하면 추정, 아니면 하네스 적용일로 기록한다.

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

4단계 파이프라인과 품질 추적 시스템의 **구체적인 파일**을 생성한다.
파이프라인의 각 단계는 역할에 맞는 에이전트를 사용한다 — 빌트인 Agent 또는 프로젝트에 정의된 커스텀 에이전트.
**프롬프트 템플릿**, **문서 템플릿**, **초기 상태 파일**을 생성한다.

상세 프로토콜 → `references/phase-execution-protocol.md`
품질 추적 스키마 → `references/quality-tracking.md`
실패 방지 → `references/failure-prevention.md`

**4-1. `_workspace/` 초기 상태 생성:**

다음 파일을 생성한다.

`_workspace/current-phase.md`:

```markdown
# 현재 Phase

Phase: 0
이름: (Phase 스펙에서 도출)
상태: not_started
시작일: (미정)
스프린트: (미정)
```

**4-2. `_workspace/templates/` 문서 템플릿 생성:**

파이프라인 실행 중 반복 사용할 문서 양식을 생성한다.

`_workspace/templates/sprint-contract.md`:

```markdown
# Phase {N} 스프린트 계약서

## 목표
(Phase 스펙에서 가져온 목표 — 1-2줄)

## 성공 기준
(자동 검증 가능한 체크리스트)
- [ ] 타입 에러 0
- [ ] 모든 테스트 통과
- [ ] 레이어 위반 0
- [ ] [도메인 특화 기준]

## 아키텍처 불변 조건
(이 Phase 에서 검증할 규칙)

## 관련 ADR
(이 Phase 가 전제로 하는 아키텍처 결정들 — `docs/adr/README.md` 에서 링크)
- [ADR-NNNN](../../docs/adr/NNNN-...) — 결정 요약

## 예상 ADR 후보
(이 Phase 에서 새 아키텍처 결정이 발생할 가능성이 있는 항목)
- (예: 외부 API 통합 방식 선택, 새 레이어 도입 등)

## 산출물
(생성/수정할 구체적인 파일 목록)

## 필요 Fixture/데이터
(테스트에 필요한 데이터)

## 알려진 위험
(이전 실패에서 배운 것 + 예상 위험)

## 부정 기준 (하지 않을 것)
(제약 조건)

## 종료 기준
(Evaluator 가 확인할 항목)
```

`_workspace/templates/self-review.md`:

```markdown
# Phase {N} 자기 리뷰

## 리뷰 대상
(이 스프린트에서 생성/수정한 파일 목록)

## 체크리스트
- [ ] 스프린트 계약서의 성공 기준을 모두 충족하는가
- [ ] 아키텍처 불변 조건을 위반하지 않는가
- [ ] 부정 기준을 위반하지 않는가
- [ ] 테스트가 모든 산출물을 커버하는가
- [ ] 빌드/타입체크/린트가 통과하는가

## 발견 이슈
(자기 리뷰에서 발견한 문제 — 수정 완료 여부 표시)

## 미해결 사항
(직접 수정하지 못한 이슈 — 사람에게 보고 필요 여부 표시)
```

`_workspace/templates/completion-record.md`:

```markdown
# Phase {N} 완료 기록

## 구현 내용 요약
(이 Phase 에서 생성/수정된 주요 파일과 기능)

## 품질 점수
- 테스트: X pass / Y fail
- 타입 에러: 0
- 린트 에러: 0
- 레이어 위반: 0
- 커버리지: (레이어별)

## 아키텍처 결정 (ADR 후보)
(이 Phase 에서 발생한 전략적 결정 — 레이어 구조, 타입 경계, 핵심 의존성, 금지 패턴 등)
- 결정 1: (한 줄 요약) → ADR 작성 필요 여부: [ ] Yes / [ ] No (이유)
- 결정 2: ...

**판단 기준**: "6개월 뒤 새 팀원이 이 결정을 보고 '왜?'라고 물을 것 같은가?"
**아무 결정도 발생하지 않았다면 "없음" 으로 명시한다.**

## 발행된 ADR
(이 Phase 에서 실제로 발행한 ADR 링크)
- [ADR-NNNN](../docs/adr/NNNN-...) — 제목

## 번복된 ADR
(이 Phase 에서 Supersede 한 ADR)
- [ADR-NNNN](../docs/adr/NNNN-...) → Superseded by [ADR-MMMM](../docs/adr/MMMM-...)

## 알려진 제한
(이 Phase 에서 해결하지 못한 이슈)

## 다음 Phase 주의사항
(다음 Phase 가 시작하기 전에 알아야 할 것)
```

`_workspace/templates/fix-directive.md`:

```markdown
# Phase {N} 수정 지시서 (시도 {M}/3)

## FAIL 판정 이유
(구체적인 실패 항목)

## 이슈 목록
1. [파일:행] 설명 — 기대 동작 vs 실제 동작

## 미달 성공 기준
- [ ] (아직 미충족인 기준)

## 힌트
(Evaluator 가 발견한 패턴이나 방향)
```

**4-3. `_workspace/prompts/` 파이프라인 프롬프트 생성:**

4단계 파이프라인의 각 단계에서 사용할 프롬프트를 생성한다.
프로젝트의 실제 경로, 명령어, 레이어 구조를 Phase 1 분석 결과로 치환하여 작성한다.

**플레이스홀더 치환 규칙**: 프롬프트 내 `{빌드 명령어}`, `{테스트 명령어}` 등을 Phase 1 에서 파악한 실제 명령어로 치환한다. 해당 도구가 프로젝트에 없으면 (예: 레이어 검사가 불필요한 프로젝트) 해당 작업 항목을 프롬프트에서 제거한다.

**에이전트 선택**: 각 프롬프트는 역할(읽기 전용 분석, 설계, 구현, 리뷰, 검증)만 정의한다.
실행 시점에 프로젝트에서 해당 역할에 맞는 에이전트를 탐색하여 사용한다:
- 커스텀 에이전트 (`.agents/`, `harness` 스킬 산출물 등) 가 있으면 우선 사용
- 없으면 빌트인 Agent 사용 (Explore, Plan, general-purpose 등)

```
4단계 파이프라인:

사전 분석 (읽기 전용)               ← 실패 기록이 있을 때만
    ↓ PASS
① 설계: Planner (읽기 전용)        → 스프린트 계약서
    ↓
② 구현: Generator                  → 코드 + 테스트
    ↓
③ 자기 리뷰: Self-Reviewer (별도 컨텍스트)
    ↓                               → 자기 리뷰 결과 + 이슈 수정
④ QA 평가: Evaluator
    ↓ PASS → 완료 기록
    ↓ FAIL → 수정 지시서 → ② 구현 (최대 3회)
```

`_workspace/prompts/pre-analysis.md`:

```markdown
# 사전 분석 프롬프트

역할: 읽기 전용 분석. 코드를 수정하지 않는다.

Phase {N} 실행 전 사전 분석.

## 입력 파일
- `docs/phases/phase-{N}-*.md` — Phase 스펙
- `_workspace/phase-{N-1}-completion.md` — 이전 Phase 완료 기록 (있는 경우)
- `docs/references/failure-lessons.md` — 실패 교훈

## 작업
1. 위 입력 파일에서 위험 요소를 수집한다
2. 현재 코드베이스에서 각 위험이 존재하는지 분석한다
3. 각 위험에 PASS/FAIL 판정을 내린다

## 출력
`_workspace/phase-{N}-reference-analysis.md` 를 작성한다:
- 각 위험 항목: 출처, 현재 상태 (PASS/FAIL), 분석 내용, 필요 조치
- 종합 판정: PASS → 다음 단계 진행 / FAIL → 사람에게 보고
```

`_workspace/prompts/planner.md`:

```markdown
# ① 설계 프롬프트

역할: 읽기 전용 설계. 코드를 수정하지 않는다.

Phase {N} 의 스프린트 계약서를 작성한다.

## 입력 파일
- `docs/phases/phase-{N}-*.md` — Phase 스펙
- `_workspace/phase-{N-1}-completion.md` — 이전 Phase 완료 기록 (있는 경우)
- `_workspace/phase-{N}-reference-analysis.md` — 사전 분석 결과 (있는 경우)
- `docs/quality/scores.json` — 현재 품질 점수
- `docs/architecture.md` — 아키텍처 규칙 (현재 스냅샷)
- `docs/adr/README.md` — 아키텍처 결정 이력 인덱스
- `docs/references/*.md` — 관련 레퍼런스

## 작업
1. Phase 스펙의 목표와 산출물을 확인한다
2. 이전 Phase 완료 기록에서 주의사항을 확인한다
3. 사전 분석 결과가 있으면 위험 항목을 반영한다
4. `docs/adr/README.md` 에서 이 Phase 와 관련된 ADR 을 선별하여 **관련 ADR** 섹션에 링크한다
5. 이 Phase 에서 새 아키텍처 결정이 발생할 가능성이 있으면 **예상 ADR 후보** 섹션에 기록한다
6. 측정 가능한 성공 기준을 정의한다 (주관적 기준 금지)
7. `_workspace/templates/sprint-contract.md` 양식으로 계약서를 작성한다

## 출력
`_workspace/phase-{N}-contract.md`

## 원칙
- 모든 성공 기준은 자동 검증 가능 (예: "타입 에러 0", "레이어 위반 0")
- "코드 품질이 좋아야 함" 같은 주관적 기준 금지
- Phase 스펙의 레이어 범위를 벗어나는 작업 포함 금지
- 기존 ADR 의 결정을 번복할 계획이라면 계약서에 명시 (Evaluator 가 번복 ADR 발행 준비)
```

`_workspace/prompts/generator.md`:

```markdown
# ② 구현 프롬프트

역할: 코드 구현 및 테스트 작성.

Phase {N} 의 스프린트 계약서에 따라 코드를 구현한다.

## 입력 파일
- `_workspace/phase-{N}-contract.md` — 스프린트 계약서
- `docs/phases/phase-{N}-*.md` — Phase 스펙
- `docs/architecture.md` — 아키텍처 규칙
- (수정 루프 시) `_workspace/phase-{N}-fix-directive-{M}.md` — 수정 지시서

## 작업
1. 스프린트 계약서의 성공 기준을 확인한다
2. 산출물 목록에 따라 코드를 구현한다
3. 각 구현에 대한 테스트를 작성한다
4. `{빌드 명령어}` 로 빌드 확인
5. `{테스트 명령어}` 로 테스트 실행
6. `{레이어 검사 명령어}` 로 레이어 위반 확인

## 수정 루프 시 (FAIL 재진입)
- Evaluator 가 전달한 **수정 지시서**만 확인한다 (eval.md 를 직접 보지 않는다)
- 수정 지시서의 미달 성공 기준을 우선 해결한다

## 원칙
- 스프린트 계약서의 부정 기준을 위반하지 않는다
- docs/architecture.md 의 레이어 규칙을 준수한다
- Evaluator 의 평가 기준 상세를 보지 않는다 (편향 방지)
```

`_workspace/prompts/self-reviewer.md`:

```markdown
# ③ 자기 리뷰 프롬프트

역할: 코드 리뷰 및 이슈 수정. Generator 와 **별도 컨텍스트**에서 실행.

Generator 가 구현한 코드를 독립적으로 리뷰한다.
Generator 의 추론 과정을 보지 않고, 코드와 계약서만 보고 판단한다.

## 입력 파일
- `_workspace/phase-{N}-contract.md` — 스프린트 계약서
- `docs/architecture.md` — 아키텍처 규칙
- 구현된 소스 코드 (src/ 하위)

## 작업
1. `{빌드 명령어}` 실행하여 빌드 확인
2. `{타입체크 명령어}` 실행
3. `{테스트 명령어}` 실행
4. `{레이어 검사 명령어}` 실행
5. 스프린트 계약서의 성공 기준 체크리스트를 하나씩 점검
6. 발견한 이슈를 **직접 수정**한다
7. `_workspace/templates/self-review.md` 양식으로 리뷰 결과를 작성한다

## 출력
`_workspace/phase-{N}-self-review.md`
(수정 루프 M회차: `_workspace/phase-{N}-self-review-retry-{M}.md`)

## 원칙
- Generator 와 별도 컨텍스트에서 실행 — Generator 의 추론을 보지 않는다
- 발견한 이슈는 가능한 한 직접 수정한 뒤 QA 에 넘긴다
- 리뷰 결과는 Evaluator 에게 전달하지 않는다 (독립 평가 보장)
```

`_workspace/prompts/evaluator.md`:

```markdown
# ④ QA 평가 프롬프트

역할: 독립 검증 및 품질 채점.

Phase {N} 의 구현 결과를 독립적으로 검증하고 품질을 채점한다.
Self-Reviewer 의 리뷰 결과를 보지 않고, 코드만 보고 평가한다.

## 입력 파일
- `_workspace/phase-{N}-contract.md` — 스프린트 계약서 (관련 ADR / 예상 ADR 후보 포함)
- `docs/architecture.md` — 아키텍처 규칙 (현재 스냅샷)
- `docs/adr/` — 아키텍처 결정 이력
- `docs/quality/scores.json` — 이전 품질 점수 (회귀 비교용)
- 구현된 소스 코드 (src/ 하위)

## 작업 — 다음 순서로 검증한다:
1. `{타입체크 명령어}` 실행
2. `{린트 명령어}` 실행
3. `{테스트 명령어}` 실행
4. `{레이어 검사 명령어}` 실행
5. 스프린트 계약서의 성공 기준 체크리스트를 하나씩 점검
6. 이전 Phase 대비 회귀가 있는지 확인
7. **아키텍처 결정 점검**: 계약서의 "예상 ADR 후보" 와 실제 구현을 비교하여, 전략적 결정이 발생했는지 판단한다 (상세 기준: `skill 의 references/adr-pattern.md`)

## 판정
- **PASS**: 모든 성공 기준 충족 + 회귀 없음
- **FAIL**: 하나라도 미충족 → 수정 지시서 작성

## PASS 시 출력
1. `_workspace/phase-{N}-eval.md` 작성 (PASS + 품질 점수)
   (수정 루프 M회차에서 PASS 시: `_workspace/phase-{N}-eval-retry-{M}.md`)
2. `docs/quality/scores.json` 갱신
3. `docs/quality/quality-log.md` 에 항목 추가 (형식: `references/quality-tracking.md` 참조)
4. **ADR 발행 (아키텍처 결정이 발생한 경우):**
   - `docs/adr/README.md` 에서 다음 번호 확인 (기존 최대 번호 + 1, 4자리 zero-padded)
   - `docs/adr/TEMPLATE.md` 를 복사하여 `docs/adr/NNNN-title.md` 로 초안 작성
   - 초기 상태: 이미 구현되었으면 `Accepted`, 논의가 필요하면 `Proposed`
   - 기존 ADR 을 번복하는 경우: 새 ADR 의 상태는 `Accepted`, 기존 ADR 의 상태를 `Superseded by [ADR-NNNN](NNNN-...)` 로 변경 (기존 ADR 본문은 수정 금지)
   - `docs/adr/README.md` 의 인덱스 테이블에 항목 추가
5. `_workspace/phase-{N}-completion.md` 작성 (`_workspace/templates/completion-record.md` 양식)
   - **아키텍처 결정** 섹션과 **발행된 ADR** 섹션을 반드시 채운다 (결정 없음이면 "없음" 명시)
6. `_workspace/current-phase.md` 갱신 (다음 Phase 로)

## FAIL 시 출력
1. `_workspace/phase-{N}-eval.md` 작성 (FAIL + 이슈 목록)
   (수정 루프 M회차: `_workspace/phase-{N}-eval-retry-{M}.md`)
2. `_workspace/phase-{N}-fix-directive-{M}.md` 작성 (`_workspace/templates/fix-directive.md` 양식)
3. ② 구현 단계로 수정 지시서 파일 경로만 전달 (최대 3회)
4. 3회 연속 FAIL 이면 사람에게 보고

## 원칙
- Self-Reviewer 의 리뷰 결과를 보지 않는다 (독립 평가)
- Generator 의 추론 과정을 보지 않는다
- 모든 검증은 도구 실행으로 확인 (주관적 판단 최소화)
```

**4-4. AGENTS.md 에 파이프라인 실행 가이드 추가:**

Phase 2 에서 작성한 AGENTS.md 에 다음 섹션을 추가한다:

```markdown
## Phase 실행 — 4단계 파이프라인

Phase 를 실행할 때는 다음 파이프라인을 따른다.
각 단계의 프롬프트 파일에 역할이 정의되어 있으며,
해당 역할에 맞는 에이전트를 프로젝트에서 탐색하여 사용한다.
(커스텀 에이전트가 있으면 우선 사용, 없으면 빌트인 Agent)

### 실행 순서
0. **사전 분석** (실패 기록이 있을 때만) → `_workspace/prompts/pre-analysis.md`
1. **설계** → `_workspace/prompts/planner.md` (읽기 전용)
2. **구현** → `_workspace/prompts/generator.md`
3. **자기 리뷰** → `_workspace/prompts/self-reviewer.md` (별도 컨텍스트)
4. **QA 평가** → `_workspace/prompts/evaluator.md`

### 정보 격벽
- Generator 는 Evaluator 의 평가 기준 상세를 보지 않는다
- Self-Reviewer 는 Generator 의 추론을 보지 않는다 (코드만)
- Evaluator 는 Self-Reviewer 의 리뷰 결과를 보지 않는다 (독립 평가)
- Phase 간 컨텍스트 리셋 — `_workspace/` 파일로만 인수인계

### 파일 구조
- 현재 상태: `_workspace/current-phase.md`
- 프롬프트: `_workspace/prompts/`
- 문서 양식: `_workspace/templates/`
- 실행 산출물: `_workspace/phase-N-*.md`
- 품질 추적: `docs/quality/`
```

**4-5. 품질 추적 파일 생성:**

Phase 1 분석 결과를 반영하여 다음 파일을 생성한다.

`docs/quality/scores.json` — 초기 상태:

```json
{
  "lastUpdated": "{오늘 날짜}",
  "currentPhase": 0,
  "phases": {}
}
```

프로젝트에 Phase 스펙이 이미 존재하면, 해당 Phase 들을 `phases` 에 pending 상태로 추가한다.
점수 스키마 상세 → `references/quality-tracking.md`

`docs/quality/quality-log.md`:

```markdown
# 품질 추적 로그

(Phase 평가 완료 시 최신 항목을 상단에 추가한다)
(형식: references/quality-tracking.md 참조)
```

**4-6. 실패 방지 초기 설정:**

이전 실패 기록이 있는 프로젝트:
- `docs/references/` 에서 기존 실패 교훈을 수집하여 `docs/references/failure-lessons.md` 로 통합한다
- Phase 스펙의 "위험 요소" 섹션에 실패 교훈 링크를 추가한다
- 사전 분석 프롬프트 (`_workspace/prompts/pre-analysis.md`) 에 구체적 검증 항목을 추가한다

이전 실패 기록이 없는 프로젝트:
- `docs/references/failure-lessons.md` 를 다음 내용으로 생성한다:

```markdown
# 실패 교훈

(Phase 실행 중 FAIL 이 발생하면 여기에 기록한다)
(형식: 증상 → 원인 → 해결 규칙)
(상세: references/failure-prevention.md 참조)
```

### Phase 5: 검증

생성된 인프라가 정상 동작하는지 확인한다.

**5-1. 구조 검증:**
- AGENTS.md 가 ~100줄이고 모든 포인터가 유효한지 (ADR 인덱스 링크 포함)
- docs/phases/ 의 모든 파일이 성공 기준을 포함하는지
- docs/adr/ 에 `README.md`, `TEMPLATE.md` 가 존재하는지
- docs/adr/TEMPLATE.md 가 상태/맥락/결정/대안/결과 섹션을 포함하는지
- docs/adr/README.md 가 인덱스 테이블을 포함하는지
- docs/quality/scores.json 이 유효한 JSON 인지

**5-2. 기계적 강제 검증 (레이어 구조가 있는 프로젝트만):**
- `scripts/check-layer-import.js` 가 의도적 위반에서 에러를 내는지
- Hook 이 설정되어 있는지 (`.claude/settings.local.json`)

**5-3. 파이프라인 검증:**
- `_workspace/current-phase.md` 가 존재하는지
- `_workspace/prompts/` 에 5개 프롬프트 파일이 존재하는지 (pre-analysis, planner, generator, self-reviewer, evaluator)
- `_workspace/templates/` 에 4개 템플릿 파일이 존재하는지 (sprint-contract, self-review, completion-record, fix-directive)
- 각 프롬프트의 플레이스홀더 (`{빌드 명령어}` 등) 가 실제 명령어로 치환되었는지
- 첫 Phase 의 스프린트 계약서를 작성할 수 있는 상태인지

## 산출물 체크리스트

Phase 2~4 완료 후 프로젝트에 존재해야 하는 파일:

- [ ] `AGENTS.md` — 지도 형태 (~100줄, 파이프라인 실행 가이드 포함)
- [ ] `docs/architecture.md` — 아키텍처 규칙 (현재 스냅샷, 권위적 원천)
- [ ] `docs/adr/README.md` — ADR 인덱스 (테이블 형식)
- [ ] `docs/adr/TEMPLATE.md` — ADR 작성 템플릿
- [ ] `docs/adr/NNNN-*.md` — 기존 아키텍처 결정의 회고 ADR (프로젝트에 이미 결정이 있는 경우)
- [ ] `docs/phases/phase-N-*.md` — Phase 별 스펙 (성공 기준 포함)
- [ ] `docs/references/*.md` — 핵심 레퍼런스 (실패 교훈, 타입 계약 등)
- [ ] `docs/references/failure-lessons.md` — 실패 교훈 초기 파일
- [ ] `docs/quality/scores.json` — 품질 점수 초기 상태
- [ ] `docs/quality/quality-log.md` — 품질 추적 로그
- [ ] `scripts/check-layer-import.js` — 레이어 경계 검사 스크립트 (레이어 구조가 있는 경우)
- [ ] `.claude/settings.local.json` — PostToolUse Hook (레이어 구조가 있는 경우)
- [ ] `_workspace/current-phase.md` — 현재 Phase 상태
- [ ] `_workspace/prompts/*.md` — 파이프라인 프롬프트 (5개: pre-analysis, planner, generator, self-reviewer, evaluator)
- [ ] `_workspace/templates/*.md` — 문서 템플릿 (4개: sprint-contract, self-review, completion-record, fix-directive)

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
- Phase 4-6 의 실패 방지 메커니즘을 간소화. 스프린트 계약의 "알려진 위험" 섹션을 "예상 위험"으로 대체

**모노레포 내 패키지:**
- 명령어에 `--filter` 를 포함. 의존성 정책에 모노레포 내 다른 패키지 경계를 명시

## 참고

- 지식 아키텍처 패턴: `references/knowledge-architecture.md`
- ADR 패턴 (언제/어떻게 작성하나): `references/adr-pattern.md`
- 기계적 강제 패턴: `references/mechanical-enforcement.md`
- 4단계 파이프라인 상세: `references/phase-execution-protocol.md`
- 품질 추적 스키마: `references/quality-tracking.md`
- 실패 방지 메커니즘: `references/failure-prevention.md`
