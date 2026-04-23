# ADR (Architecture Decision Records) 패턴

아키텍처 결정의 이력을 기록하는 패턴.
`docs/architecture.md` 가 "현재 아키텍처는 이렇다"의 스냅샷이라면,
ADR 은 "왜 이렇게 결정했나"의 이력이다.

---

## 1. 왜 ADR 인가

- 코드는 "무엇"을 보여주지만, "왜" 를 보여주지 않는다
- `docs/architecture.md` 는 현재 상태만 담는다 — 대안, 트레이드오프, 번복된 시도가 사라진다
- 에이전트는 결정의 배경을 모르면 "일관성 있는 변경"과 "설계 의도를 깨는 변경"을 구별하지 못한다
- ADR 은 장기 프로젝트에서 의사결정의 감사 추적 (audit trail) 역할

## 2. 언제 ADR 을 작성하나

작성 **해야 하는** 경우:
- 레이어 구조 추가/변경/삭제
- 핵심 타입 계약 도입/변경
- 주요 외부 의존성 도입 (프레임워크, DB, 메시지 큐 등)
- 금지 패턴 도입 (예: "core 에서 React import 금지")
- 배포/빌드 전략의 큰 변경
- 기존 ADR 을 번복/대체

작성 **하지 않는** 경우:
- 단순 리팩토링 (동작 불변)
- 버그 수정
- 개별 함수 구현 선택
- Phase 내부의 전술적 선택 (전략이 아닌 것)

**휴리스틱**: "6개월 뒤 새 팀원이 이 결정을 보고 '왜?'라고 물을 것 같다면 ADR."

## 3. 파일 구조

```
docs/adr/
  README.md                       # 인덱스 (모든 ADR 목록 + 상태)
  TEMPLATE.md                     # 새 ADR 작성용 템플릿
  0001-layer-structure.md
  0002-type-boundary.md
  0003-layer-enforcement-tool.md
  ...
```

### 번호 규칙

- 4자리 zero-padded (`0001`, `0002`, ..., `9999`)
- 한 번 할당된 번호는 재사용 금지 (Deprecated 되어도 번호 유지)
- 파일명: `NNNN-kebab-case-title.md` (영문 권장, 한국어도 허용)

## 4. ADR 템플릿 (`docs/adr/TEMPLATE.md`)

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
- 제약 조건 (성능, 호환성, 팀 역량 등)

## 결정 (Decision)
어떻게 하기로 했는가?
- 선택한 방안을 한 문장으로
- 구체적인 규칙/구조

## 대안 (Alternatives)
검토한 다른 방안들
- 대안 A — 기각 이유
- 대안 B — 기각 이유

## 결과 (Consequences)
이 결정으로 인한 영향
- 긍정적: 얻는 것
- 부정적: 잃는 것 / 감수하는 것
- 중립적: 파생되는 작업

## 관련
- Phase: `docs/phases/phase-N-*.md`
- 규칙: `docs/architecture.md#섹션`
- 후속 ADR: (있다면)
```

## 5. ADR 상태 전이

```
Proposed  →  Accepted  →  Deprecated
                ↓
           Superseded by ADR-XXXX
```

| 상태 | 의미 |
|------|------|
| **Proposed** | 제안됨. 아직 적용되지 않음 (논의 중) |
| **Accepted** | 승인되어 적용됨 (현재 유효) |
| **Deprecated** | 더 이상 적용하지 않음 (대체 결정 없이 폐기) |
| **Superseded** | 다른 ADR 에 의해 대체됨 — 대체 ADR 링크 필수 |

**중요: 기존 ADR 은 사후 수정하지 않는다.**
결정이 바뀌면 새 ADR 을 작성하고, 기존 ADR 의 상태만 `Superseded by [ADR-XXXX]` 로 변경한다.
이유: ADR 은 감사 추적이다. 수정하면 의사결정 이력이 왜곡된다.

## 6. 인덱스 파일 (`docs/adr/README.md`)

Evaluator 가 Phase 종료 시마다 갱신한다.

```markdown
# Architecture Decision Records

이 프로젝트의 아키텍처 결정 이력.
새 결정이 발생하면 `TEMPLATE.md` 를 복사하여 `NNNN-title.md` 로 작성한다.

| 번호 | 제목 | 상태 | Phase | 결정일 |
|------|------|------|-------|--------|
| [0001](0001-layer-structure.md) | 레이어 구조 도입 | Accepted | 0 | 2026-04-24 |
| [0002](0002-type-boundary.md) | 타입 경계 정의 | Superseded by [0005](0005-type-boundary-v2.md) | 1 | 2026-04-25 |
| ...
```

## 7. 파이프라인 통합

### Phase 시작 (Planner)
- 스프린트 계약서의 **관련 ADR** 섹션에 전제로 하는 ADR 을 링크
- Phase 스펙을 읽고 **새 ADR 이 필요한지** 판단 (레이어 변경, 타입 경계 변경 등의 시그널)

### Phase 종료 (Evaluator)
- 완료 기록의 **아키텍처 결정** 섹션을 점검
- 아키텍처 결정이 발생했다면:
  1. 다음 ADR 번호 할당 (기존 최대 번호 + 1, 4자리 zero-padded)
  2. `docs/adr/TEMPLATE.md` 를 복사하여 `docs/adr/NNNN-title.md` 로 초안 작성
  3. 초기 상태는 `Accepted` (이미 구현되었으므로) 또는 `Proposed` (논의 필요)
  4. `docs/adr/README.md` 인덱스 갱신

### 수정 루프
- Evaluator 가 FAIL 판정하며 수정 지시서에 "레이어 재정의가 필요"를 적었다면 → ADR 작성 권고

### 번복 시
- 기존 ADR 의 결정을 뒤집는 Phase 가 발생하면:
  1. 새 ADR 작성 (`Accepted`)
  2. 기존 ADR 의 상태를 `Superseded by [ADR-NNNN](NNNN-...)` 로 변경
  3. 기존 ADR 본문은 그대로 보존

## 8. 안티패턴

| 안티패턴 | 대신 |
|----------|------|
| `architecture.md` 에 결정 이력을 남긴다 | `architecture.md` 는 현재 상태만. 이력은 ADR 로 |
| ADR 을 사후 수정한다 | 기존 ADR 은 `Superseded` 로 두고 새 ADR 작성 |
| 모든 커밋마다 ADR 작성 | 전략적 결정만. 전술적 선택은 코드 주석/커밋으로 |
| ADR 에 결정만 있고 맥락 없음 | **왜 (Context)** 를 반드시 포함 |
| 대안 검토 없이 결정만 | 기각된 대안도 기록 (미래의 동일 질문 방지) |
| ADR 을 나중에 몰아서 작성 | 결정이 발생한 Phase 종료 시점에 즉시 작성 |

---

## 참고

- 지식 아키텍처 전체: `references/knowledge-architecture.md`
- Phase 실행 프로토콜: `references/phase-execution-protocol.md`
- 원 출처: Michael Nygard, "Documenting Architecture Decisions" (2011)
