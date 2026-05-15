# 품질 추적 시스템

Phase 별 품질을 기계 판독 가능한 점수와 시간순 로그로 추적하는 시스템.
Evaluator 가 점수를 갱신하고, 회귀를 자동 감지한다.

---

## 1. scores.json 스키마

`docs/quality/scores.json` — 기계 판독 가능한 품질 점수 파일.

```json
{
  "lastUpdated": "YYYY-MM-DD",
  "currentPhase": 2,
  "phases": {
    "phase-0": {
      "status": "completed",
      "completedAt": "2025-01-15",
      "layers": {
        "types": {
          "coverage": 95,
          "apiStability": 100,
          "docAlignment": 90
        },
        "core": {
          "coverage": 87,
          "apiStability": 95,
          "docAlignment": 85
        }
      },
      "overall": {
        "testCount": 42,
        "testPassRate": 100,
        "e2eTestCount": 5,
        "e2ePassRate": 100,
        "typeErrors": 0,
        "lintErrors": 0,
        "layerViolations": 0,
        "fixtureCompleteness": 80
      }
    },
    "phase-1": {
      "status": "completed",
      "completedAt": "2025-02-01",
      "layers": {
        "types": {
          "coverage": 95,
          "apiStability": 100,
          "docAlignment": 92
        },
        "core": {
          "coverage": 91,
          "apiStability": 90,
          "docAlignment": 88
        },
        "adapters": {
          "coverage": 78,
          "apiStability": 85,
          "docAlignment": 80
        }
      },
      "overall": {
        "testCount": 98,
        "testPassRate": 100,
        "e2eTestCount": 12,
        "e2ePassRate": 100,
        "typeErrors": 0,
        "lintErrors": 0,
        "layerViolations": 0,
        "fixtureCompleteness": 90
      }
    },
    "phase-2": {
      "status": "pending",
      "completedAt": null,
      "layers": {},
      "overall": {
        "testCount": 98,
        "testPassRate": 100,
        "e2eTestCount": 12,
        "e2ePassRate": 100,
        "typeErrors": 0,
        "lintErrors": 0,
        "layerViolations": 0,
        "fixtureCompleteness": 90
      }
    }
  }
}
```

---

## 2. 점수 차원 설명

### 레이어 별 점수

| 차원 | 범위 | 측정 방법 | 의미 |
|------|------|-----------|------|
| **coverage** | 0-100 | vitest/jest 커버리지 보고서 | 해당 레이어의 코드 커버리지 (%) |
| **apiStability** | 0-100 | 공개 API 시그니처 변경 비율 | 이전 Phase 대비 공개 API 시그니처가 변경된 비율. 낮을수록 안정. 100 = 변경 없음 |
| **docAlignment** | 0-100 | Evaluator 주관 판단 | 코드와 `docs/architecture.md` 의 일치도. 100 = 완전 일치 |

### 전체 점수

| 차원 | 측정 방법 | 목표 |
|------|-----------|------|
| **testCount** | 테스트 러너 출력 | 단조 증가 (Phase 진행에 따라) |
| **testPassRate** | 통과/전체 * 100 | 100 |
| **e2eTestCount** | E2E 러너 출력 | Phase 에 따라 증가 |
| **e2ePassRate** | 통과/전체 * 100 | 100 |
| **typeErrors** | `tsc --noEmit` 출력 | 0 |
| **lintErrors** | ESLint 출력 | 0 |
| **layerViolations** | `check-layer-import.js` 출력 | 0 |
| **fixtureCompleteness** | 타입 대비 Fixture 커버리지 | 100 |

### fixtureCompleteness 계산

```
fixtureCompleteness = (Fixture 가 존재하는 타입 수 / 전체 공개 타입 수) * 100
```

모든 공개 타입에 대해 테스트용 Fixture 가 존재해야 한다.
Fixture 가 없으면 테스트가 불완전하거나 임의 데이터로 작성될 위험이 있다.

---

## 3. quality-log.md 작성 형식

`docs/quality/quality-log.md` — 시간순 품질 추적 로그.
사람이 읽을 수 있는 형태로, Phase 평가가 완료될 때마다 항목을 추가한다.

### 형식

```markdown
# 품질 추적 로그

## Phase 2: Core 계산 로직 - 2025-02-15
- 테스트: 98 pass / 0 fail (이전: 42/0)
- E2E: 12 pass / 0 fail (이전: 5/0)
- 레이어 위반: 0
- 타입 에러: 0
- 린트 에러: 0
- 커버리지 변동: core 91% (+4%), adapters 78% (신규)
- Fixture 완성도: 90% (+10%)
- Evaluator 발견 이슈:
  - adapters/ 의 에러 핸들링 일부 누락 → Phase 3 에서 보완
  - 외부 API 타입 변환 테스트 부족
- 회귀: 없음

## Phase 1: 타입 시스템 기초 - 2025-02-01
- 테스트: 42 pass / 0 fail (이전: 0/0)
- E2E: 5 pass / 0 fail (이전: 0/0)
- 레이어 위반: 0
- 타입 에러: 0
- 린트 에러: 0
- 커버리지 변동: types 95% (신규), core 87% (신규)
- Fixture 완성도: 80% (신규)
- Evaluator 발견 이슈:
  - 일부 유니온 타입의 분기 누락
- 회귀: 없음 (첫 Phase)
```

### 작성 규칙

- **최신 항목이 위**: 가장 최근 Phase 가 파일 상단에 온다.
- **이전 대비 변동**: 모든 수치에 이전 Phase 대비 변동을 괄호로 표기한다.
- **이슈 구체적으로**: "이슈 있음" 이 아니라 구체적인 내용을 기록한다.
- **회귀 명시**: 이전 Phase 대비 악화된 항목이 있으면 반드시 기록한다.

---

## 4. Evaluator 가 점수를 갱신하는 시점

| 시점 | 갱신 대상 | 설명 |
|------|-----------|------|
| Phase 평가 완료 (PASS) | scores.json + quality-log.md | 최종 점수 기록 |
| Phase 평가 완료 (FAIL) | scores.json (임시) | FAIL 시점의 점수를 기록하되, status 는 pending 유지 |
| 수정 루프 완료 (PASS) | scores.json + quality-log.md | 최종 점수로 덮어쓰기 |

### 갱신 절차

1. 모든 검증 도구를 실행하여 수치를 수집한다
2. `scores.json` 의 해당 Phase 섹션을 갱신한다
3. `quality-log.md` 에 새 항목을 추가한다
4. 이전 Phase 대비 회귀가 있는지 확인한다

---

## 5. 회귀 감지

### 자동 감지 규칙

이전 Phase 대비 다음 항목이 악화되면 경고:

| 항목 | 회귀 기준 |
|------|-----------|
| testPassRate | 100% 미만 |
| e2ePassRate | 100% 미만 |
| typeErrors | 0 초과 |
| lintErrors | 0 초과 |
| layerViolations | 0 초과 |
| coverage (레이어별) | 이전 Phase 대비 5% 이상 하락 |
| apiStability (레이어별) | 80 미만 (API 가 과도하게 변경됨) |

### 회귀 발견 시 처리

1. `quality-log.md` 의 "회귀" 항목에 구체적으로 기록
2. Evaluator 가 FAIL 판정에 회귀 항목을 포함
3. Generator 에게 전달되는 수정 지시서에 회귀 복구를 최우선으로 명시
4. 회귀가 3회 연속 해결되지 않으면 사람 개입 요청
