---
name: audit
description: "하네스 셋업된 프로젝트의 문서/인프라 드리프트를 진단하고 안전하게 정리하는 스킬. 시간이 지남에 따라 누적되는 깨진 포인터, 고아 문서, 완료 Phase 의 작업 파일, ADR 번호 결번/중복, 코드-문서 괴리, 쓰이지 않는 레퍼런스 등 8개 영역의 오염 패턴을 탐지하여 보고서를 생성한다. 명백한 항목은 AskUserQuestion 으로 사용자 확인 후 _archive/ 로 자동 이동, 판단 필요 항목은 보고서에만 기록한다. '하네스 감사', '하네스 정리', '문서 드리프트 진단', '가비지 컬렉션', 'audit harness project', '프로젝트 오염 진단', 'harness 유지보수' 요청 시 사용. setup 스킬로 구축된 하네스가 있는 프로젝트에서만 동작."
---

# Harness Audit — 드리프트 진단 및 안전한 정리

하네스 셋업 이후 시간이 지남에 따라 누적되는 오염을 진단하고 정리한다.
OpenAI 하네스 엔지니어링의 **"가비지 컬렉션"** 원칙을 실행 경로로 구현한 스킬.

**setup 과의 관계:**
- `setup` = 1회성 하네스 인프라 구축
- `audit` = 반복 실행하는 유지보수 (월 1회 또는 3~5개 Phase 완료 시점 권장)

## 파괴적 작업 원칙

**핵심: 자동 삭제 없음. 모든 정리는 archive → 사용자 확인 → (선택적) delete.**

| 작업 | 대상 | 승인 조건 |
|------|------|-----------|
| `archive` | `_archive/YYYY-MM-DD/` 로 이동 (원래 경로 구조 보존) | auto-safe 는 일괄 승인, needs-confirmation 은 개별 승인 |
| `delete` | 실제 파일 삭제 | 사용자가 명시적으로 delete 선택한 경우만 |
| `manual` | 수정/병합 판단 필요 | 보고서에만 기록, 실행 없음 |

## 워크플로우

### Phase 0: 사전 확인

프로젝트에 하네스가 셋업되어 있는지 확인한다:
- `AGENTS.md` 존재
- `docs/architecture.md` 존재
- `_workspace/current-phase.md` 존재
- `docs/quality/scores.json` 존재

하나라도 없으면 "먼저 `/harness:setup` 을 실행하세요" 안내 후 종료.

### Phase 1: 진단 (Auditor)

**역할**: 읽기 전용 진단. 어떤 파일도 수정하지 않는다.

상세 드리프트 패턴 → `references/drift-patterns.md`

8개 영역을 순서대로 진단한다 (병렬 탐색 가능):

1. **AGENTS.md 포인터 드리프트** — 깨진 링크, 존재하지 않는 경로 참조
2. **architecture.md 와 코드 괴리** — 레이어 규칙 vs 실제 import 그래프
3. **ADR 정합성** — 번호 결번/중복, Superseded 링크 유효성, Proposed 장기 방치
4. **완료 Phase 잔여 파일** — 이전 Phase 의 `fix-directive-*`, `self-review-retry-*`, `eval-retry-*`
5. **고아 레퍼런스** — 어디서도 링크되지 않는 `docs/references/*.md`
6. **중복 레퍼런스** — 동일 주제를 분산해서 다루는 파일들
7. **quality/ 정합성** — `scores.json` ↔ `quality-log.md` ↔ `docs/phases/` ↔ `current-phase.md` 동기화
8. **쓰이지 않는 스크립트/Hook** — `scripts/` 내 참조 없는 파일

각 발견에 **심각도** + **정리 방법** 라벨 부여:
- 심각도: `critical` | `major` | `minor`
- 정리 방법: `auto-safe` | `needs-confirmation` | `manual`

### Phase 2: 보고서 작성 (Reporter)

`_workspace/audit-YYYY-MM-DD.md` 작성:

```markdown
# Audit Report — YYYY-MM-DD

## 요약
- critical: N건
- major: N건
- minor: N건
- 자동 정리 가능 (auto-safe): N건
- 확인 필요 (needs-confirmation): N건
- 수동 판단 (manual): N건

## 영역별 발견

### 1. AGENTS.md 포인터
- [critical] `교훈 요약 → docs/references/react-lessons.md` 파일 없음
  - 정리: needs-confirmation (사람 결정 필요)

### 2. architecture.md 와 코드 괴리
- [major] src/core/auth.ts 가 src/ui/ 를 import (레이어 위반)
  - 정리: manual

...
```

### Phase 3: 정리 승인 (대화형)

보고서 요약을 사용자에게 보여준 뒤, **AskUserQuestion** 으로 처리 방향을 수집한다.

AskUserQuestion 사용 패턴 → `references/cleanup-rules.md` (섹션 3)

**질문 1 — auto-safe 일괄**:
> "자동 정리 가능한 N개 항목을 `_archive/YYYY-MM-DD/` 로 이동할까요?"
> - 예, 모두 아카이브 / 개별 검토 / 건너뛰기

**질문 2 — needs-confirmation 개별 또는 묶음**:
> 각 항목에 대해 keep / archive / delete 중 선택
> (5개 이상은 2-3개씩 묶어서 여러 번 질문)

**질문 3 — manual 항목**:
> 질문 없음. 보고서에만 기록. 사용자가 별도로 판단.

### Phase 4: 정리 실행 (Cleaner)

사용자가 승인한 항목만 실행한다.

- `archive`: `_archive/YYYY-MM-DD/원래경로/` 로 이동 (원래 경로 구조 보존)
- `delete`: 실제 파일 삭제 (단, archive 메타데이터에 "삭제됨" 기록 남김)
- `keep`: 아무것도 하지 않음

**인덱스 자동 갱신:**
- `docs/adr/README.md` 인덱스 — 실제 파일 기준 재생성
- `docs/quality/scores.json` — `lastUpdated` 갱신, 누락 Phase 추가
- `AGENTS.md` 의 깨진 포인터 — **삭제하지 않고 주석 처리** (사람이 최종 판단)

### Phase 5: 기록

`docs/quality/audit-log.md` 에 실행 이력을 누적한다:

```markdown
## 2026-04-24
- 실행 시각: 10:30 KST
- 보고서: `_workspace/audit-2026-04-24.md`
- 발견: critical 1, major 2, minor 5
- 조치: auto-archive 3건, archive (승인) 2건, delete 0건, manual 대기 3건
- 다음 audit 권장: 2026-05-24
```

audit-log.md 가 존재하지 않으면 생성한다.

## 산출물

- [ ] `_workspace/audit-YYYY-MM-DD.md` — 보고서 (매 실행 시 생성)
- [ ] `_archive/YYYY-MM-DD/` — 이동된 파일들 (archive 발생 시)
- [ ] `docs/quality/audit-log.md` — 시계열 로그 (항목 추가)
- [ ] 인덱스 갱신: `docs/adr/README.md`, `docs/quality/scores.json`, (필요 시) `AGENTS.md` 주석

## 적용하지 않는 것

- 코드 리팩토링 / 죽은 코드 제거 → 별도 도구
- 테스트 커버리지 분석 → 별도 도구
- 성능 튜닝 → 별도 도구
- `docs/legacy-*/` 정리 → 동결 정책에 따라 손대지 않음
- 활성 Phase(`current-phase.md` 의 Phase)의 파일 정리 → 진행 중 작업을 건드리지 않음

## 참고

- 드리프트 패턴 (8개 영역 상세): `references/drift-patterns.md`
- 정리 규칙 (archive/delete 판단, AskUserQuestion 패턴): `references/cleanup-rules.md`
- setup 스킬 (하네스 최초 구축): `../setup/SKILL.md`
