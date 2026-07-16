# Harness — Audit 모드 (문서 낡음 점검)

하네스 문서가 코드·현실과 어긋난 지점을 찾아 보고하는 안전망.
문서 유지의 주체는 작업 에이전트 + 사람이고 (CONTRACTS 1절 원칙 2), audit 은 놓친 낡음을 주기적으로 잡는다.

> **진입점**: 라우터가 `harness/.harness.json` 버전 = 플러그인 버전인 경우 본 모드로 분기한다 (비파괴 모드 — 한 줄 통지 후 바로 진행 가능).
>
> **원칙**: 진단은 읽기 전용. 수정은 사용자 승인 후 최소한만. **문서 본문 데이터는 수정하지 않는다** (보고만).

## 워크플로우

### Phase 1: 진단 (읽기 전용, 4종)

**① 지도 유효성**
- AGENTS.md 의 모든 포인터 (`→ 경로`, 마크다운 링크) 가 실재하는지
- "검증 명령" 소절의 각 명령이 **실제 실행 가능한지** (dry-run 또는 실행)
- AGENTS.md 가 40줄을 초과했는지

**② 아키텍처 불변 조건 vs 코드**
- enforcement 활성 시 (`scripts/check-layer-import.js` 존재로 감지): 스크립트 전체 스캔 실행 → 위반 보고
- 공통: `harness/ARCHITECTURE.md` 의 규칙 문장 각각을 코드와 직접 대조 (import 방향·금지 패턴을 Grep 으로 확인) — 문서가 낡았는지 / 코드가 위반인지 양쪽 가능성을 모두 보고

**③ ADR.md 정합성**
- 번호 중복·결번, `Superseded by NNNN` 링크가 실재하는 항목을 가리키는지, `Proposed` 상태 30일 이상 방치

**④ stale 코드 명칭 + 골격**
- `harness/GLOSSARY.md` "코드 명칭" 컬럼과 `harness/LESSONS.md` "관련" 필드의 백틱 식별자를 각각 rg → 코드베이스 0 hit 이면 낡은 항목 후보로 보고
- 문서 4종의 표준 골격 (필수 섹션·표 헤더) 훼손 여부 (`../references/document-formats.md` 기준)

**검사하지 않는 것**: 정의·본문 내용의 정확성 (사람 판단), 문서·커밋 내 표기 위반 전수 검사 (false positive 과다), 미등재 용어 탐지 (기계적 불가).

### Phase 2: 보고 (채팅)

발견을 심각도 (`critical`/`major`/`minor`) 와 함께 채팅으로 보고한다. 로그 파일은 만들지 않는다 (git 이력 + 채팅으로 충분).

### Phase 3: 수정 (승인 후 최소한)

AskUserQuestion 으로 승인받은 항목만:
- 깨진 포인터 → **주석 처리** (삭제 X — 사람이 최종 판단)
- 골격 훼손 → 누락 섹션 헤더 복구 (본문 데이터 0 변경)
- 그 외 전부 (규칙-코드 괴리, stale 항목, ADR 정합성) → **보고만**, 수정은 사람/작업 에이전트 소관

## 적용하지 않는 것

- 문서 본문 데이터 수정·삭제 (CONTRACTS 5절)
- 코드 수정, `docs/legacy-*/`·`_archive/` 정리 (동결·스캔 제외)
- `harness/.harness.json` 수정 (읽기만)

## 참고

- 공유 규약: `../CONTRACTS.md` / 골격 기준: `../references/document-formats.md` / 레이어 검사: `../references/mechanical-enforcement.md`
