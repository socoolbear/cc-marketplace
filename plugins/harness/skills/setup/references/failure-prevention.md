# 실패 방지 메커니즘

이전에 실패한 곳은 다시 실패할 가능성이 높다.
코딩을 시작하기 전에 실패 가능성을 차단하는 메커니즘.

---

## 1. 원칙

**"이전에 실패한 곳은 다시 실패할 가능성이 높다. 코딩 전에 차단한다."**

사후 검증 (Evaluator) 만으로는 부족하다.
Evaluator 가 FAIL 을 내면 이미 코드가 작성된 후다 — 수정 비용이 높다.

사전 차단 전략:
- 코딩 전에 읽기 전용 에이전트가 실패 가능성을 분석한다
- 스프린트 계약서에 이전 실패 원인별 검증 항목을 포함한다
- E2E 테스트로 이전 실패 시나리오를 자동 검증한다
- 실패 교훈을 문서화하여 반복을 방지한다

---

## 2. 사전 분석 에이전트 패턴

### 개요

Phase 실행 전, 읽기 전용 Explore 에이전트가 코딩 전 실행된다.
이전 실패 원인을 기반으로 현재 코드베이스를 분석하고,
실패 가능성이 있는 부분을 사전에 식별한다.

### 실행 조건

- 해당 Phase 와 관련된 이전 실패 기록이 있을 때
- 이전 Phase 의 Evaluator 가 "주의사항" 을 남겼을 때
- Phase 스펙의 "위험 요소" 섹션에 항목이 있을 때

### 에이전트 동작

1. `docs/references/` 에서 관련 실패 교훈을 수집한다
2. 이전 Phase 의 `_workspace/phase-(N-1)-completion.md` 에서 주의사항을 확인한다
3. Phase 스펙의 위험 요소를 확인한다
4. 현재 코드베이스에서 해당 위험이 존재하는지 분석한다
5. 각 위험에 대해 PASS/FAIL 판정을 내린다

### 산출물

`_workspace/phase-N-reference-analysis.md`:

```markdown
# Phase N 사전 분석

## 분석 대상
- 실패 교훈: docs/references/failure-lessons.md
- 이전 Phase 주의사항: _workspace/phase-(N-1)-completion.md
- Phase 스펙 위험 요소: docs/phases/phase-N-*.md

## 검증 결과

### 1. [위험 항목 이름]
- 출처: (어디서 식별된 위험인지)
- 현재 상태: PASS / FAIL
- 분석: (코드베이스에서 확인한 내용)
- 조치 필요: (FAIL 인 경우 필요한 선행 작업)

### 2. [위험 항목 이름]
- ...

## 종합 판정: PASS / FAIL
(FAIL 인 경우 Generator 시작 불가)
```

### FAIL 시 처리

사전 분석이 FAIL 이면:
- Generator 를 시작하지 않는다
- 발견된 문제를 사람에게 보고하거나
- Phase 스펙을 수정하여 위험을 해소한 뒤 다시 분석한다

---

## 3. 스프린트 계약의 필수 검증 항목

Planner 가 스프린트 계약서를 작성할 때, 이전 실패 원인별 검증 항목을 반드시 포함한다.

### 구체적 테스트 시나리오

이전 실패 원인마다 대응하는 테스트 시나리오를 명시:

```markdown
## 알려진 위험 — 필수 검증

### 순환 의존 (Phase 1 에서 발생)
- 출처: docs/references/failure-lessons.md#순환-의존
- 검증: `scripts/check-layer-import.js` 통과
- 테스트: core/ → types/ → core/ 경로가 존재하지 않을 것

### 외부 API 파싱 실패 (Phase 2 에서 발생)
- 출처: docs/references/failure-lessons.md#api-파싱
- 검증: 누락 필드, null 필드, 예상 외 타입에 대한 테스트
- 테스트: adapter 테스트에 malformed input 케이스 3개 이상 포함
```

### 부정 기준

"~하지 않을 것" 형태의 기준을 포함한다:

```markdown
## 부정 기준 (하지 않을 것)
- core/ 에서 React 를 import 하지 않을 것 (순환 의존 방지)
- 기존 공개 API 시그니처를 변경하지 않을 것 (하위 호환성)
- 외부 API 응답을 검증 없이 신뢰하지 않을 것 (파싱 실패 방지)
```

---

## 4. E2E 자동 검증

이전 실패와 관련된 시나리오를 E2E 테스트로 자동 검증한다.
Evaluator 가 수동으로 판단할 필요 없이 자동으로 PASS/FAIL 을 결정한다.

### 자동 검증 테스트 작성 기준

| 기준 | 설명 |
|------|------|
| 이전 FAIL 시나리오 | 이전에 FAIL 을 유발한 정확한 시나리오를 재현하는 테스트 |
| 경계값 | 이전 실패의 원인이 된 경계 조건을 포함하는 테스트 |
| 의존성 변경 | 레이어 경계를 넘는 호출이 올바른지 검증하는 테스트 |

### 예시

```typescript
// 이전 실패: 외부 API 에서 null 필드가 올 때 파싱 실패
describe('외부 API 파싱 — 방어적 처리', () => {
  it('누락 필드에 대해 기본값을 사용한다', () => {
    const malformed = { id: 1 }; // name, stats 필드 누락
    const result = parseExternalData(malformed);
    expect(result.name).toBe('unknown');
  });

  it('null 필드에 대해 안전하게 처리한다', () => {
    const withNull = { id: 1, name: null, stats: null };
    const result = parseExternalData(withNull);
    expect(result).toBeDefined();
  });
});
```

---

## 5. 실패 기록 문서화 패턴

### 형식: 증상 → 원인 → 해결 규칙

`docs/references/` 에 주제별 독립 문서로 보관한다:

```markdown
# 실패 교훈: [주제]

## 1. [실패 이름]

### 증상
(어떤 에러/실패가 발생했는가)
- 타입 에러: "Cannot assign to ..."
- 테스트 실패: "Expected X but received Y"

### 원인
(근본 원인은 무엇이었는가)
- core/ 에서 React 컴포넌트를 직접 import 하여 순환 의존 발생

### 해결 규칙
(앞으로 어떻게 방지할 것인가)
- core/ 는 React 를 import 하지 않는다 (docs/architecture.md 에 명시)
- scripts/check-layer-import.js 에 검사 규칙 추가
- 해당 로직은 components/ 레이어로 이동

### 발생 시점
- Phase 1, 2025-01-20

### 관련 파일
- src/core/calculator.ts (위반 파일)
- docs/architecture.md#레이어-구조 (규칙)
```

### Phase 스펙과의 연결

Phase 스펙의 "위험 요소" 섹션에서 실패 교훈 문서를 직접 링크한다:

```markdown
## 위험 요소
- 순환 의존: → docs/references/failure-lessons.md#순환-의존
- 외부 API 파싱: → docs/references/failure-lessons.md#api-파싱
```

---

## 6. 가비지 컬렉션 패턴 (패턴 드리프트 방지)

프로젝트가 진행되면서 문서, 규칙, 코드 사이에 불일치 (드리프트) 가 누적된다.
주기적으로 정합성을 검증하여 드리프트를 제거한다.

### 검증 항목

| 항목 | 검증 방법 | 주기 |
|------|-----------|------|
| **AGENTS.md 포인터 유효성** | 모든 포인터가 가리키는 파일이 존재하는지 | Phase 시작 시 |
| **Phase 스펙-구현 일치** | Phase 스펙의 산출물이 실제로 존재하는지 | Phase 종료 시 |
| **품질 점수 최신성** | scores.json 의 lastUpdated 가 최근인지 | Phase 종료 시 |
| **레이어 경계 상시 감시** | PostToolUse Hook 이 활성화되어 있는지 | 상시 (Hook) |
| **Fixture-코드 정합성** | 모든 공개 타입에 대응 Fixture 가 존재하는지 | Phase 종료 시 |

### 가비지 컬렉션 실행

Phase 시작 시 Planner 가 다음을 확인한다:

1. **포인터 유효성**: AGENTS.md 의 모든 링크가 유효한 파일을 가리키는가
2. **동결 문서 무결성**: `docs/legacy-*/` 하위 파일이 수정되지 않았는가
3. **scores.json 정합성**: 현재 Phase 번호와 상태가 올바른가
4. **architecture.md 최신성**: 최근 추가된 레이어나 규칙이 반영되었는가

무효한 포인터, 낡은 점수, 불일치하는 규칙이 발견되면
Planner 가 스프린트 계약서의 첫 번째 작업으로 수정을 지시한다.

### 검증 스크립트 (선택)

```bash
# AGENTS.md 포인터 유효성 검사
node scripts/check-doc-pointers.js

# Fixture 완성도 검사
node scripts/check-fixture-completeness.js
```
