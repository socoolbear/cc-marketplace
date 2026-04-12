# Phase 실행 프로토콜 — 4단계 파이프라인

Phase 를 실행하는 4단계 파이프라인의 상세 프로토콜.
설계, 구현, 자기 리뷰, QA 평가의 4단계로 구성되며,
정보 격벽과 컨텍스트 리셋으로 자기 평가 편향을 제거한다.

각 단계의 프롬프트(`_workspace/prompts/`)는 **역할**만 정의한다.
실행 시점에 프로젝트에서 해당 역할에 맞는 에이전트를 탐색하여 사용한다:
- 커스텀 에이전트(`.agents/`, `harness` 스킬 산출물 등)가 있으면 우선 사용
- 없으면 빌트인 Agent 사용 (Explore, Plan, general-purpose 등)

---

## 1. 파이프라인 개요

```
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│  [사전 분석] (읽기 전용) — 실패 기록이 있을 때만              │
│    → _workspace/phase-N-reference-analysis.md                │
│         ↓ PASS                                               │
│                                                              │
│  ① 설계: Planner (읽기 전용)                                 │
│    입력: Phase 스펙 + 이전 완료 기록 + 품질 점수              │
│    출력: 스프린트 계약서                                      │
│                                                              │
│         ┌──────────────┐                                     │
│         │ 스프린트 계약서 │                                    │
│         └──────┬───────┘                                     │
│                ▼                                             │
│  ② 구현: Generator                                           │
│    입력: 스프린트 계약서 + Phase 스펙                          │
│    출력: 구현된 코드 + 테스트                                  │
│                                                              │
│         ┌──────────────┐                                     │
│         │ 코드 + 테스트  │                                    │
│         └──────┬───────┘                                     │
│                ▼                                             │
│  ③ 자기 리뷰: Self-Reviewer (별도 컨텍스트)                   │
│    입력: 스프린트 계약서 + 코드 (Generator 추론 비공개)        │
│    출력: 이슈 수정 + 자기 리뷰 결과                           │
│                                                              │
│         ┌──────────────┐                                     │
│         │ 리뷰 완료 코드  │                                   │
│         └──────┬───────┘                                     │
│                ▼                                             │
│  ④ QA 평가: Evaluator                                        │
│    입력: 스프린트 계약서 + 코드 (Self-Review 결과 비공개)      │
│    출력: PASS/FAIL + 품질 점수                                │
│                                                              │
│         ┌──────────────┐    FAIL (최대 3회)                   │
│         │ 수정 지시서    │──────────────┐                      │
│         └──────────────┘              │                      │
│                                       ▼                      │
│                              ② 구현 (재실행)                  │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

---

## 2. 단계별 상세

### 2-1. ① 설계: Planner (읽기 전용)

**역할 요건**: 읽기 전용 분석/설계
**프롬프트**: `_workspace/prompts/planner.md`

**역할:** Phase 의 실행 계획을 수립하고 측정 가능한 성공 기준을 정의한다.

**입력:**
- `docs/phases/phase-N-*.md` — 해당 Phase 스펙
- `_workspace/phase-(N-1)-completion.md` — 이전 Phase 완료 기록 (있는 경우)
- `_workspace/phase-N-reference-analysis.md` — 사전 분석 결과 (있는 경우)
- `docs/quality/scores.json` — 현재 품질 점수
- `docs/architecture.md` — 아키텍처 규칙
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

### 2-2. ② 구현: Generator

**역할 요건**: 코드 구현 및 테스트 작성
**프롬프트**: `_workspace/prompts/generator.md`

**역할:** 스프린트 계약서에 따라 코드를 구현하고 테스트를 작성한다.

**입력:**
- `_workspace/phase-N-contract.md` — 스프린트 계약서
- `docs/phases/phase-N-*.md` — Phase 스펙
- `docs/architecture.md` — 아키텍처 규칙
- (수정 루프 시) `_workspace/phase-N-fix-directive-M.md` — 수정 지시서

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

### 2-3. ③ 자기 리뷰: Self-Reviewer (별도 컨텍스트)

**역할 요건**: 코드 리뷰 및 이슈 수정 — Generator 와 **별도 컨텍스트**
**프롬프트**: `_workspace/prompts/self-reviewer.md`

**역할:** Generator 가 구현한 코드를 독립적으로 리뷰하고, 발견한 이슈를 직접 수정한다.

**입력:**
- `_workspace/phase-N-contract.md` — 스프린트 계약서
- `docs/architecture.md` — 아키텍처 규칙
- 구현된 소스 코드 (src/ 하위)

**출력:**
- 이슈 수정된 코드
- `_workspace/phase-N-self-review.md` — 자기 리뷰 결과

**원칙:**
- **Generator 추론 비공개**: Generator 의 추론 과정을 보지 않는다.
  별도 컨텍스트에서 실행하여, 코드 자체만 보고 리뷰한다.
- **이슈 직접 수정**: 발견한 문제를 리포트만 하지 않고 직접 수정한다.
  QA 에 넘기기 전에 품질을 높이는 것이 목적이다.
- **Evaluator 에 비공개**: 자기 리뷰 결과는 Evaluator 에게 전달하지 않는다.
  Evaluator 가 독립적으로 평가할 수 있도록 정보 격벽을 유지한다.

**실행 순서:**
1. 빌드 확인
2. 타입 체크
3. 테스트 실행
4. 레이어 경계 검사
5. 스프린트 계약서 성공 기준 점검
6. 발견 이슈 직접 수정
7. `_workspace/phase-N-self-review.md` 작성

### 2-4. ④ QA 평가: Evaluator

**역할 요건**: 독립 검증 및 품질 채점
**프롬프트**: `_workspace/prompts/evaluator.md`

**역할:** 구현 결과를 독립적으로 검증하고 품질을 채점한다.

**입력:**
- `_workspace/phase-N-contract.md` — 스프린트 계약서
- `docs/architecture.md` — 아키텍처 규칙
- `docs/quality/scores.json` — 이전 품질 점수 (회귀 비교용)
- 구현된 소스 코드 (src/ 하위)

**출력 (PASS):**
- `_workspace/phase-N-eval.md` — 평가 결과 (PASS + 품질 점수)
  (수정 루프 M회차에서 PASS 시: `phase-N-eval-retry-M.md`)
- `docs/quality/scores.json` 갱신
- `docs/quality/quality-log.md` 에 항목 추가
- `_workspace/phase-N-completion.md` — 완료 기록
- `_workspace/current-phase.md` 갱신 (다음 Phase 로)

**출력 (FAIL):**
- `_workspace/phase-N-eval.md` — 평가 결과 (FAIL + 이슈 목록)
  (수정 루프 M회차: `phase-N-eval-retry-M.md`)
- `_workspace/phase-N-fix-directive-M.md` — 수정 지시서

**원칙:**
- **Self-Review 결과 비공개**: Evaluator 는 Self-Reviewer 의 리뷰 결과를 볼 수 없다.
  코드 자체만 보고 평가한다. 이렇게 해야 자기 평가 편향이 제거된다.
- **Generator 추론 비공개**: Generator 의 추론 과정도 볼 수 없다.
- **실행 순서**: 반드시 다음 순서로 검증한다:
  1. 타입 체크
  2. 린트
  3. 단위 테스트
  4. E2E 테스트 (있는 경우)
  5. 아키텍처 검증 (레이어 경계 검사)
  6. 계약서 대비 리뷰 (성공 기준 체크리스트 점검)
  7. 컨텍스트 불안 감지 (전반부 vs 후반부 품질 비교, TODO/FIXME 검출) — 상세: 섹션 9

---

## 3. 수정 루프

### FAIL 시 처리

Evaluator 가 FAIL 판정을 내리면:

1. **수정 지시서만 전달**: Evaluator 의 수정 지시서를 Generator 에게 전달한다.
   Generator 는 새로운 컨텍스트에서 시작하며, 이전 자신의 추론은 보지 않는다.
2. **②③④ 재실행**: Generator(②) → Self-Reviewer(③) → Evaluator(④) 를 다시 실행한다.
3. **최대 3회 반복**: FAIL → 수정 → 재평가를 최대 3회 반복한다.
4. **3회 실패 시 사람 개입**: 3회 연속 FAIL 이면 자동 수정을 중단하고,
   문제의 원인과 시도한 해결책을 정리하여 사람에게 보고한다.

### 수정 지시서 형식

`_workspace/templates/fix-directive.md` 양식을 따른다:

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

`_workspace/templates/completion-record.md` 양식을 따른다:

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

Planner 가 작성하는 스프린트 계약서의 전체 형식.
`_workspace/templates/sprint-contract.md` 양식을 기반으로 하되, 다음 항목을 모두 포함한다:

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
| `current-phase.md` | Evaluator | PASS 시 다음 Phase 로 갱신 |
| `phase-N-contract.md` | Planner | Phase 시작 시 생성 |
| `phase-N-self-review.md` | Self-Reviewer | 자기 리뷰 완료 시 생성 |
| `phase-N-self-review-retry-M.md` | Self-Reviewer | 수정 루프 M회차 리뷰 |
| `phase-N-eval.md` | Evaluator | 평가 완료 시 생성 |
| `phase-N-eval-retry-M.md` | Evaluator | 수정 루프 M회차 평가 |
| `phase-N-fix-directive-M.md` | Evaluator | FAIL 시 수정 지시서 (M회차) |
| `phase-N-completion.md` | Evaluator | PASS 후 생성 |
| `phase-N-reference-analysis.md` | 사전 분석 에이전트 | 코딩 전 사전 분석 |
| `analysis-report.md` | 분석 에이전트 | 최초 프로젝트 분석 |

### 프롬프트 및 템플릿

| 디렉터리 | 용도 |
|----------|------|
| `_workspace/prompts/` | 파이프라인 에이전트 프롬프트 (5개) |
| `_workspace/templates/` | 문서 양식 (4개) |

### 규칙

- **삭제 금지**: 중간 산출물은 삭제하지 않는다. 감사 추적 (audit trail) 용도.
- **덮어쓰기 금지**: 같은 파일을 덮어쓰지 않는다. 수정 루프의 평가/리뷰는 `-retry-M` 접미사.
  (예: `phase-N-self-review-retry-1.md`, `phase-N-eval-retry-1.md`)
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

## 7. 정보 격벽 (Information Barrier) 요약

4단계 파이프라인의 핵심은 단계 간 정보 격벽이다.

| 단계 | 보는 것 | 보지 않는 것 |
|------|---------|-------------|
| ① Planner | Phase 스펙, 이전 완료 기록, 품질 점수 | (제한 없음) |
| ② Generator | 스프린트 계약서, Phase 스펙 | Evaluator 평가 기준 상세 |
| ③ Self-Reviewer | 스프린트 계약서, 코드 | Generator 추론, Evaluator 기준 |
| ④ Evaluator | 스프린트 계약서, 코드, 이전 품질 점수 | Generator 추론, Self-Review 결과 |

각 단계는 별도 컨텍스트의 Agent 로 실행하여 격벽을 보장한다.

---

## 8. 사전 분석 에이전트 연동

Phase 실행 전, 실패 방지를 위해 사전 분석 에이전트를 실행한다.
상세는 `references/failure-prevention.md` 참조.

### 파이프라인 흐름 (사전 분석 포함)

```
사전 분석 (읽기 전용)
    ↓ PASS
① Planner → 계약서
    ↓
② Generator → 코드
    ↓
③ Self-Reviewer → 리뷰 + 수정
    ↓
④ Evaluator → 검증
    ↑         수정 지시서        ↓
    └────────────────────────────┘
```

사전 분석이 FAIL 이면 Planner 를 시작하지 않고,
발견된 문제를 사람에게 보고하거나 Phase 스펙을 수정한다.

---

## 9. 컨텍스트 불안 (Context Anxiety) 대응

### 정의

컨텍스트 윈도우 사용량이 **40% 를 넘어가면** 에이전트가 작업을 대충 마무리하려는 경향.
이는 LLM 의 알려진 행동 패턴으로, 파이프라인의 모든 단계에서 발생할 수 있다.

### 증상

| 증상 | 설명 |
|------|------|
| 후반부 품질 저하 | 앞부분 파일은 꼼꼼하게, 뒷부분 파일은 대충 구현 |
| 테스트 생략/최소화 | "테스트는 나중에" 또는 최소한의 케이스만 작성 |
| 에러 핸들링 생략 | 초반엔 방어적 코딩, 후반엔 happy path 만 처리 |
| TODO/FIXME 급증 | 구현 대신 주석으로 떠넘기기 |
| 설계 단순화 | 계약서의 요구사항을 슬그머니 축소하거나 생략 |
| 마무리 서두르기 | 검증 단계를 건너뛰거나 "문제없음" 으로 요약 |

### 단계별 대응 전략

#### ② Generator — 체크포인팅 + 서브에이전트 분할

1. **파일 단위 체크포인팅**:
   - 구현할 파일이 **3개 이상**이면 파일 단위로 나눠서 하나씩 완성한다.
   - 각 파일 완성 후 빌드/타입 체크를 실행하여 중간 검증한다.
   - 중간 산출물이 유효한 상태를 유지해야 한다 (깨진 상태로 다음 파일로 넘어가지 않는다).

2. **서브에이전트 분할**:
   - 구현할 파일이 **5개 이상**이면 서브에이전트로 분할을 고려한다.
   - 각 서브에이전트는 **1-2개 파일**만 담당한다.
   - 서브에이전트 간 의존성이 있으면 인터페이스(타입)를 먼저 확정한 후 병렬 실행한다.

3. **자기 진단 규칙**:
   - 코드에 `TODO`, `FIXME`, `나중에`, `일단` 이 남아있으면 **미완성**이다.
   - 테스트를 생략하고 싶은 충동이 느껴지면 = 컨텍스트 불안 신호.
     → 멈추고, 현재까지의 작업을 파일로 저장한 뒤, 새 컨텍스트의 서브에이전트로 이어간다.

#### ③ Self-Reviewer — 후반부 집중 리뷰

- 리뷰 순서를 **역순**으로 진행한다 (마지막 구현 파일부터 리뷰).
- 후반부 파일에서 다음을 집중 점검한다:
  - 전반부 대비 테스트 케이스 수가 적은지
  - 에러 핸들링이 전반부보다 허술한지
  - 스프린트 계약서의 성공 기준이 모두 반영되었는지

#### ④ Evaluator — 품질 저하 감지

Evaluator 의 실행 순서(섹션 2-4)에 **"7. 컨텍스트 불안 감지"** 를 추가한다:

- **전반부 vs 후반부 품질 비교**:
  - 파일 구현 순서 기준으로 전반 50% 와 후반 50% 의 품질을 비교한다.
  - 후반부에서 테스트 커버리지, 에러 핸들링, 코드 밀도가 눈에 띄게 낮으면 FAIL.
- **TODO/FIXME 검출**:
  - `TODO`, `FIXME`, `HACK`, `나중에`, `일단` 이 1건이라도 있으면 FAIL.
- **계약서 대비 누락 검사**:
  - 스프린트 계약서의 산출물 목록과 실제 구현을 1:1 대조한다.
  - 계약서에 있는데 구현에 없는 항목이 있으면 FAIL.

### 파이프라인 전체 원칙

```
컨텍스트 불안이 의심되면: 멈추고 → 저장하고 → 새 컨텍스트에서 이어간다.
절대로 대충 끝내고 다음 단계로 넘기지 않는다.
```

- 어떤 단계든 작업량이 예상보다 크면, **무리하게 한 컨텍스트에서 끝내지 않는다**.
- 중간 산출물을 `_workspace/` 에 저장하고 서브에이전트로 분할하는 것이 정답이다.
- Evaluator 가 컨텍스트 불안 징후를 감지하면 FAIL 처리하여 수정 루프로 보낸다.
