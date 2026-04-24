# 정리 규칙 — archive/delete 판단 및 AskUserQuestion 패턴

audit 스킬의 Phase 3-4 에서 따라야 할 정리 규칙.

---

## 1. Archive 디렉터리 구조

모든 archive 는 다음 구조로 저장한다:

```
프로젝트 루트/
  _archive/
    YYYY-MM-DD/
      docs/
        references/
          낡은-문서.md
      _workspace/
        phase-0-fix-directive-1.md
      (원래 경로 구조를 그대로 복제)
    2026-03-15/
    2026-04-24/
```

**원칙:**
- 날짜는 audit 실행 날짜 (`YYYY-MM-DD`)
- 원래 경로를 그대로 복제하여 되돌리기 쉽게 한다
- `_archive/` 의 `.gitignore` 포함 여부는 프로젝트 정책 (audit 은 결정하지 않음. 기본은 커밋 권장 — 감사 추적 유지)

---

## 2. 파괴적 작업의 안전 원칙

### auto-safe 판정 기준 (모두 만족)

- [ ] 데이터 손실 없음 (archive 로 이동만 하고 삭제하지 않음)
- [ ] 사용자 의사 결정 불필요 (명백한 잔여물)
- [ ] 되돌리기 쉬움 (`_archive/` 에서 파일 복사만으로 복원 가능)
- [ ] 인덱스 갱신이 기계적 (수동 판단 없음)

### auto-safe 금지 대상

다음은 auto-safe 판정을 내리지 않는다:
- 일반 사용자가 손으로 작성한 문서 (`docs/references/*.md` 중 고아가 아닌 것)
- **활성 Phase** (`current-phase.md` 의 Phase)의 파일
- `docs/legacy-*/` 디렉터리 (동결 정책)
- `docs/architecture.md` (권위적 원천, 전체 교체 금지)
- `AGENTS.md` 자체 (전체 수정은 사람 판단)

### Delete 정책

- 기본 동작: `archive` (삭제하지 않음)
- `delete` 는 사용자가 **명시적으로 delete 선택**한 경우만
- delete 된 파일도 `_archive/YYYY-MM-DD/_deleted.md` 에 "삭제됨" 메타데이터로 기록 (파일 경로, 사유, 삭제 시각)

---

## 3. AskUserQuestion 사용 패턴

### 패턴 A — auto-safe 일괄 확인 (질문 1개)

auto-safe 로 분류된 모든 항목을 한 번에 묶어 질문:

```
질문: "자동 정리 가능한 {N}개 항목을 _archive/{YYYY-MM-DD}/ 로 이동할까요?"
옵션:
  1. 예, 모두 아카이브 (권장)
  2. 개별 검토 (패턴 B 로 전환)
  3. 건너뛰기 (이번 audit 에서 정리 안 함)
```

질문 전에 간단한 요약을 보여준다:
```
auto-safe 항목 요약:
  - 완료 Phase 잔여 파일: 5건 (phase-0, phase-1)
  - ADR README.md 인덱스 재생성: 1건
  - scores.json 의 누락 Phase 추가: 2건
```

### 패턴 B — needs-confirmation 개별/묶음 (질문 여러 개)

항목별로 3-way 선택지를 제시한다. AskUserQuestion 은 한 번에 복수 질문을 병렬로 보낼 수 있으므로 2-3개씩 묶어서 질문한다.

```
질문: "고아 레퍼런스: docs/references/old-notes.md (어디서도 참조되지 않음)"
      → 마지막 수정일: 2025-11-03
      → 내용 요약: (파일 첫 3줄)
옵션:
  1. keep (그대로 유지)
  2. archive (_archive 로 이동)
  3. delete (완전 삭제 — 되돌릴 수 없음)
```

**묶음 전략:**
- 같은 드리프트 영역의 항목들을 한 번에 묶음 (예: 고아 레퍼런스 3개를 한 AskUserQuestion 호출로)
- 심각도가 다르면 분리 (critical 은 먼저, minor 는 나중)

### 패턴 C — manual 항목 (질문 없음)

보고서에만 기록. 사용자가 별도 세션에서 판단 후 수정한다.
Phase 3 에서 manual 항목이 있음을 사용자에게 **텍스트로 통지**하되 AskUserQuestion 은 사용하지 않는다.

예:
> "수동 판단 필요 항목이 {N}건 있습니다. `_workspace/audit-{YYYY-MM-DD}.md` 의 'manual' 섹션을 검토해주세요."

---

## 4. 인덱스 자동 갱신

정리 작업 후 다음 인덱스는 자동으로 재생성한다:

| 인덱스 | 갱신 방법 | 주의사항 |
|--------|-----------|----------|
| `docs/adr/README.md` | `docs/adr/*.md` 실제 파일 기준으로 테이블 재생성 | TEMPLATE.md 는 제외 |
| `docs/quality/scores.json` | `lastUpdated` 를 오늘 날짜로, 누락 Phase 는 `pending` 으로 추가 | 기존 Phase 점수 건드리지 않음 |
| `AGENTS.md` 의 깨진 포인터 | **삭제하지 않고 주석 처리** (`<!-- BROKEN: docs/... (2026-04-24 audit) -->`) | 사람이 최종 제거 판단 |

**중요**: AGENTS.md 의 포인터는 **삭제하지 않고 주석 처리**만 한다. 사람이 "정말 제거" 결정할 때까지 흔적을 남긴다.

---

## 5. audit-log.md 항목 형식

`docs/quality/audit-log.md` 상단에 추가 (최신이 위):

```markdown
## YYYY-MM-DD
- 실행 시각: HH:MM {TZ}
- 보고서: `_workspace/audit-YYYY-MM-DD.md`
- 발견: critical N, major N, minor N
- 조치:
  - auto-archive: N건 (완료 Phase 잔여물 N, ADR 인덱스 재생성 등)
  - archive (사용자 승인): N건
  - delete (사용자 명시 승인): N건
  - manual 대기: N건
- 다음 audit 권장: YYYY-MM-DD (+30일)
```

audit-log.md 가 존재하지 않으면 Phase 5 에서 생성한다:

```markdown
# Audit Log

harness:audit 실행 이력. 최신 항목이 상단.
```

---

## 6. 예외 규칙 (정리에서 제외)

다음은 어떤 상황에서도 audit 이 건드리지 않는다:

| 대상 | 이유 |
|------|------|
| `docs/legacy-*/` | 동결 정책에 따라 수정 금지 |
| 활성 Phase 의 `_workspace/phase-N-*.md` | 진행 중 작업 보호 |
| `docs/architecture.md`, `AGENTS.md` 의 본문 | 권위적 원천, 전체 수정은 사람 판단 |
| `docs/references/failure-lessons.md` | setup 이 생성한 초기 파일, 비어있어도 유지 |
| `.claude/settings.local.json` | Hook 설정, audit 이 수정하지 않음 |
| `docs/adr/*.md` 본문 | ADR 불변 원칙 — 상태만 Superseded 로 변경하는 건 audit 이 아닌 다음 Phase 의 Evaluator 책임 |

---

## 7. 안티패턴

| 안티패턴 | 대신 |
|----------|------|
| 자동 삭제 | 항상 archive 먼저. delete 는 사용자 명시 승인 후만 |
| 모든 항목 한 번에 묻기 | 카테고리별 묶음 (auto-safe → 일괄, needs-confirmation → 개별) |
| AGENTS.md 에서 깨진 포인터 즉시 제거 | 주석 처리로 흔적 남기기 |
| `docs/legacy-*/` 정리 | 동결 원칙에 따라 손대지 않음 |
| audit 중 코드 수정 | audit 은 문서/인프라만. 코드 수정은 별도 |
| audit 중 ADR 본문 수정 | ADR 은 불변. 상태 변경은 Evaluator 의 책임 |
| 보고서 없이 바로 정리 실행 | 항상 Phase 2 에서 보고서 먼저 생성 |
