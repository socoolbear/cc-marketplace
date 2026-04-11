# Phase 실행 프로토콜 — 3-에이전트 파이프라인

Phase 를 실행하는 3-에이전트 파이프라인의 상세 프로토콜.
Planner, Generator, Evaluator 가 각자의 역할을 수행하며,
정보 격벽과 컨텍스트 리셋으로 자기 평가 편향을 제거한다.

---

## 1. 파이프라인 개요

```
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│  Planner (Plan, 읽기 전용)                                   │
│    입력: Phase 스펙 + 이전 Phase 완료 기록 + 품질 점수        │
│    출력: 스프린트 계약서                                      │
│                                                              │
│         ┌──────────────┐                                     │
│         │ 스프린트 계약서 │                                    │
│         └──────┬───────┘                                     │
│                ▼                                             │
│  Generator (general-purpose)                                 │
│    입력: 스프린트 계약서 + Phase 스펙                          │
│    출력: 구현된 코드 + 테스트                                  │
│                                                              │
│         ┌──────────────┐                                     │
│         │ 코드 + 테스트  │                                    │
│         └──────┬───────┘                                     │
│                ▼                                             │
│  Evaluator (general-purpose)                                 │
│    입력: 스프린트 계약서 + src/ + 테스트 출력                   │
│    출력: PASS/FAIL + 이슈 목록 + 품질 점수                     │
│                                                              │
│         ┌──────────────┐    FAIL (최대 3회)                   │
│         │ 수정 지시서    │──────────────┐                      │
│         └──────────────┘              │                      │
│                                       ▼                      │
│                              Generator (재실행)               │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

---

## 2. 에이전트별 상세

### 2-1. Planner (Plan 모드, 읽기 전용)

**역할:** Phase 의 실행 계획을 수립하고 측정 가능한 성공 기준을 정의한다.

**입력:**
- `docs/phases/phase-N-*.md` — 해당 Phase 스펙
- `_workspace/phase-(N-1)-completion.md` — 이전 Phase 완료 기록 (있는 경우)
- `docs/quality/scores.json` — 현재 품질 점수
- `docs/references/*.md` — 관련 레퍼런스 (실패 교훈 등)

**출력:**
- `_workspace/phase-N-contract.md` — 스프린트 계약서

**원칙:**
- **읽기 전용**: 코드를 수정하지 않는다. 분석과 계획만 수행한다.
- **측정 가능한 기준**: 모든 성공 기준은 자동 검증이 가능해야 한다.
  - 좋은 예: "타입 에러 0", "core/ 에서 React import 0건"
  - 나쁜 예: "코드 품질이 좋아야 함", "적절한 추상화"
- **위험 명시**: 이전 실패 교훈 + 이번 Phase 의 예상 위험을 명시한다.
- **범위 제한**: Phase 스펙에서 정의한 레이어 범위를 벗어나는 작업을 포함하지 않는다.

### 2-2. Generator (general-purpose)

**역할:** 스프린트 계약서에 따라 코드를 구현하고 테스트를 작성한다.

**입력:**
- `_workspace/phase-N-contract.md` — 스프린트 계약서
- `docs/phases/phase-N-*.md` — Phase 스펙
- `docs/architecture.md` — 아키텍처 규칙
- (수정 루프 시) 이전 Evaluator 의 이슈 목록

**출력:**
- 구현된 코드 (src/ 하위)
- 테스트 코드
- 필요 시 Fixture 데이터

**원칙:**
- **Evaluator 기준 비공개**: Generator 는 Evaluator 의 평가 기준 상세를 볼 수 없다.
  이렇게 해야 "시험에 맞춰 가르치기 (teaching to the test)" 를 방지할 수 있다.
- **계약서 준수**: 스프린트 계약서의 성공 기준을 모두 충족하는 것이 목표다.
- **아키텍처 준수**: `docs/architecture.md` 의 규칙을 따른다.
  레이어 경계 검사 Hook 이 위반을 즉시 알려준다.

### 2-3. Evaluator (general-purpose)

**역할:** 구현 결과를 검증하고 품질을 채점한다.

**입력:**
- `_workspace/phase-N-contract.md` — 스프린트 계약서
- `src/` — 구현된 코드 (읽기 전용으로 분석)
- 테스트 실행 결과, 타입 체크 결과, 린트 결과

**출력:**
- `_workspace/phase-N-eval.md` — 평가 결과 (PASS/FAIL + 이슈 목록)
- `docs/quality/scores.json` 갱신
- `docs/quality/quality-log.md` 에 항목 추가

**원칙:**
- **Generator 추론 비공개**: Evaluator 는 Generator 의 추론 과정을 볼 수 없다.
  코드 자체만 보고 평가한다. 이렇게 해야 자기 평가 편향이 제거된다.
- **실행 순서**: 반드시 다음 순서로 검증한다:
  1. 타입 체크 (`tsc --noEmit` 또는 프로젝트 설정에 따라)
  2. 린트 (`eslint` 또는 프로젝트 린터)
  3. 단위 테스트 (`vitest` / `jest` 등)
  4. E2E 테스트 (있는 경우)
  5. 아키텍처 검증 (`scripts/check-layer-import.js`)
  6. 계약서 대비 리뷰 (성공 기준 체크리스트 점검)

---

## 3. 수정 루프

### FAIL 시 처리

Evaluator 가 FAIL 판정을 내리면:

1. **이슈 목록만 전달**: Evaluator 의 이슈 목록을 Generator 에게 전달한다.
   Generator 는 새로운 컨텍스트에서 시작하며, 이전 자신의 추론은 보지 않는다.
2. **최대 3회 반복**: FAIL → 수정 → 재평가를 최대 3회 반복한다.
3. **3회 실패 시 사람 개입**: 3회 연속 FAIL 이면 자동 수정을 중단하고,
   문제의 원인과 시도한 해결책을 정리하여 사람에게 보고한다.

### 수정 지시서 형식

```markdown
# Phase N 수정 지시서 (시도 M/3)

## FAIL 판정 이유
(구체적인 실패 항목)

## 이슈 목록
1. [파일:행] 설명 — 기대 동작 vs 실제 동작
2. ...

## 미달 성공 기준
- [ ] (아직 미충족인 기준)

## 힌트
(있다면 — Evaluator 가 발견한 패턴이나 방향)
```

---

## 4. Phase 간 인수인계

### 컨텍스트 리셋 원칙

**Anthropic: "Phase 간 완전한 컨텍스트 리셋. 파일로만 인수인계."**

각 Phase 는 이전 Phase 의 에이전트 대화를 전혀 보지 못한다.
오직 `_workspace/phase-N-completion.md` 파일만 참조한다.

이유:
- 컨텍스트 윈도우가 무한하지 않다. 이전 Phase 의 대화를 모두 넣으면 공간이 부족하다.
- 파일로 인수인계하면 **핵심 정보만 전달** 된다 (노이즈 제거).
- 다음 Phase 의 에이전트가 **선입견 없이** 코드를 본다.

### completion.md 필수 섹션

```markdown
# Phase N 완료 기록

## 구현 내용 요약
(이 Phase 에서 생성/수정된 주요 파일과 기능)

## 품질 점수
- 테스트: X pass / Y fail
- 타입 에러: 0
- 린트 에러: 0
- 레이어 위반: 0
- 커버리지: core 87%, adapters 72%

## 알려진 제한
(이 Phase 에서 해결하지 못한 이슈)

## 다음 Phase 주의사항
(다음 Phase 가 시작하기 전에 알아야 할 것)
- 구조적 결정 사항
- 남아있는 TODO
- 의존성 변경 사항
```

---

## 5. 스프린트 계약서 상세 템플릿

Planner 가 작성하는 스프린트 계약서의 전체 형식:

```markdown
# Phase N 스프린트 계약서

## 목표
(Phase 스펙에서 가져온 목표 — 1-2줄)

## 성공 기준
(자동 검증 가능한 체크리스트)
- [ ] 타입 에러 0
- [ ] 모든 테스트 통과 (예상 테스트 수: N)
- [ ] 레이어 위반 0
- [ ] 커버리지 core >= 80%
- [ ] [도메인 특화 기준]

## 아키텍처 불변 조건
(이 Phase 에서 특히 주의해야 할 아키텍처 규칙)
- core/ 는 React 를 import 하지 않는다
- types/ 는 런타임 의존성이 없다
- ...

## 산출물
(생성/수정할 구체적인 파일 목록)
- `src/core/calculator.ts` — 새로 생성
- `src/core/calculator.test.ts` — 테스트
- `src/types/stats.ts` — 타입 추가
- ...

## 필요 Fixture/데이터
(테스트에 필요한 데이터)
- 스탯 계산용 샘플 데이터: [출처]
- API 응답 목업: [형태]

## 알려진 위험
(이전 실패에서 배운 것 + 예상 위험)
- Phase 1 에서 순환 의존 발생 이력: docs/references/failure-lessons.md#순환-의존
- 외부 API 스키마 불안정: 방어적 파싱 필요

## 부정 기준 (하지 않을 것)
- core/ 에 UI 로직을 넣지 않을 것
- 기존 공개 API 시그니처를 변경하지 않을 것
- ...

## 종료 기준
(Evaluator 가 확인할 최종 항목)
- 모든 성공 기준 충족
- 레이어 경계 검사 통과
- 회귀 없음 (이전 Phase 테스트 전부 통과)
```

---

## 6. _workspace/ 파일 컨벤션

Phase 실행의 모든 중간 산출물은 `_workspace/` 에 보관한다.

### 파일 목록

| 파일 | 작성자 | 시점 |
|------|--------|------|
| `current-phase.md` | Planner | Phase 시작 시 갱신 |
| `phase-N-contract.md` | Planner | Phase 시작 시 생성 |
| `phase-N-eval.md` | Evaluator | 평가 완료 시 생성 |
| `phase-N-eval-retry-M.md` | Evaluator | 수정 루프 M회차 평가 |
| `phase-N-completion.md` | Evaluator | PASS 후 생성 |
| `phase-N-reference-analysis.md` | Explore 에이전트 | 코딩 전 사전 분석 |
| `analysis-report.md` | Explore 에이전트 | 최초 프로젝트 분석 |

### 규칙

- **삭제 금지**: 중간 산출물은 삭제하지 않는다. 감사 추적 (audit trail) 용도.
- **덮어쓰기 금지**: 같은 파일을 덮어쓰지 않는다. 수정 루프는 `-retry-M` 접미사.
- **current-phase.md 형식**:
  ```markdown
  # 현재 Phase
  Phase: 2
  이름: Core 계산 로직
  상태: in_progress
  시작일: YYYY-MM-DD
  스프린트: _workspace/phase-2-contract.md
  ```

---

## 7. 사전 분석 에이전트 연동

Phase 실행 전, 실패 방지를 위해 사전 분석 에이전트를 실행한다.
상세는 `references/failure-prevention.md` 참조.

### 파이프라인 흐름 (사전 분석 포함)

```
사전 분석 (Explore, 읽기 전용)
    ↓ PASS
Planner → 계약서 → Generator → 코드 → Evaluator
                      ↑         수정 지시서        ↓
                      └────────────────────────────┘
```

사전 분석이 FAIL 이면 Planner 를 시작하지 않고,
발견된 문제를 사람에게 보고하거나 Phase 스펙을 수정한다.
