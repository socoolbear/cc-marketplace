# Harness Contracts — 공유 규약

`setup`, `audit`, `update` 세 스킬이 공통으로 따르는 데이터 계약과 파일 규약.
스킬은 이 파일의 정의에 따라 동작하고, **행동 (어떻게 진행하는가)** 만 자기 SKILL.md 에 정의한다.

> 이 파일이 정의하는 것: 디렉터리 레이아웃, 파일 명명 규칙, 데이터 스키마, 보호 파일 매트릭스, 정보 격벽.
> 이 파일이 정의하지 않는 것: Phase 워크플로우, AskUserQuestion 흐름, 진단/동기화 알고리즘 (각 스킬 SKILL.md 참조).

---

## 1. 스킬 역할 분리

| 스킬 | 방향 | 기준 | 빈도 |
|------|------|------|------|
| `setup` | 0 → 1 | 하네스가 없는 프로젝트에 구축 | 1회성 |
| `audit` | 프로젝트 내부 드리프트 제거 | 프로젝트 vs 프로젝트 (내부 정합성) | 월 1회 또는 3~5 Phase 완료 시점 |
| `update` | 스킬 버전 차이 반영 | 프로젝트 vs 최신 스킬 (외부 동기화) | `/plugin update` 후 |

세 스킬은 같은 프로젝트 산출물을 다루므로 본 문서의 규약을 공유한다.

---

## 2. 디렉터리 레이아웃

```
프로젝트 루트/
  AGENTS.md                          # 지도 (포인터 모음 50줄 내외 + 파이프라인 가이드 섹션 ≈ 80줄 이내)
  docs/
    architecture.md                  # 아키텍처 규칙 (현재 스냅샷, 권위적 원천)
    adr/                             # 아키텍처 결정 이력
      README.md                      # 인덱스 (테이블)
      TEMPLATE.md                    # 작성 템플릿
      NNNN-제목.md                   # 발행된 ADR (4자리 zero-padded)
    phases/
      phase-N-*.md                   # Phase 별 스펙 + 성공 기준
    references/
      failure-lessons.md             # 실패 교훈 (누적)
      *.md                           # 핵심 레퍼런스
    quality/
      .harness-version               # 버전 마커 (4절 스키마)
      scores.json                    # 품질 점수
      quality-log.md                 # 평가 로그
      audit-log.md                   # audit 실행 이력 (audit 이 생성)
      update-log.md                  # update 실행 이력 (update 가 생성)
    legacy-*/                        # 동결된 기존 문서
  _workspace/
    current-phase.md                 # 현재 Phase 상태
    analysis-report.md               # setup Phase 1 분석
    audit-YYYY-MM-DD.md              # audit 보고서
    update-plan-YYYY-MM-DD.md        # update 플랜
    phase-N-*.md                     # Phase 실행 산출물 (3-1 절)
    templates/                       # 4개 표준 템플릿
    prompts/                         # 5개 표준 프롬프트
  _archive/
    YYYY-MM-DD/
      audit/{원래경로}/              # audit 가 archive 한 파일
      update-superseded/{원래경로}/  # update 가 교체한 기존 파일
  scripts/                           # 레이어 검사 등
  .claude/settings.local.json        # Hook/권한
```

---

## 3. 파일 명명 규칙

### 3-1. Phase 실행 산출물 (`_workspace/`)

| 파일 | 누가 쓰나 | 보존 |
|------|-----------|------|
| `phase-{N}-contract.md` | Planner | 이력 |
| `phase-{N}-reference-analysis.md` | 사전 분석 | 이력 |
| `phase-{N}-self-review.md` | Self-Reviewer | 이력 |
| `phase-{N}-self-review-retry-{M}.md` | Self-Reviewer (재시도, M=1~3) | 완료 Phase 의 것은 audit archive 대상 |
| `phase-{N}-eval.md` | Evaluator | 이력 |
| `phase-{N}-eval-retry-{M}.md` | Evaluator (재시도) | 완료 Phase 의 것은 audit archive 대상 |
| `phase-{N}-fix-directive-{M}.md` | Evaluator → Generator | 완료 Phase 의 것은 audit archive 대상 |
| `phase-{N}-completion.md` | Evaluator (PASS 시) | 이력 |

### 3-2. ADR 파일

- `docs/adr/NNNN-제목.md` — N: 4자리 zero-padded (`0001`, `0002`, ...)
- 번호 재사용 금지. 결번은 의도적인 경우만 허용
- `docs/adr/README.md` — 인덱스 (테이블 행 누적)
- `docs/adr/TEMPLATE.md` — 신규 작성 시 복사용

### 3-3. 표준 템플릿 (`_workspace/templates/`, 4개)

`sprint-contract.md`, `self-review.md`, `completion-record.md`, `fix-directive.md`

정답 출처: `setup/SKILL.md` Phase 4-2

### 3-4. 표준 프롬프트 (`_workspace/prompts/`, 5개)

`pre-analysis.md`, `planner.md`, `generator.md`, `self-reviewer.md`, `evaluator.md`

정답 출처: `setup/SKILL.md` Phase 4-3

setup 이 프로젝트별 명령어로 플레이스홀더 (`{빌드 명령어}` 등) 를 치환한다. 비교 시 치환 위치는 사용자 커스터마이징으로 보지 않는다.

### 3-5. `_archive/` 네임스페이스

audit 와 update 가 같은 날 실행해도 충돌하지 않도록 하위 네임스페이스로 분리한다:

```
_archive/YYYY-MM-DD/
  audit/                    # audit 이 archive 한 파일들 (원래경로 복제)
  update-superseded/        # update 가 교체한 기존 파일들 (원래경로 복제)
```

setup 의 강제 재실행 (예외 케이스) 은 별도 디렉터리를 사용한다:

```
_archive/YYYY-MM-DD-before-reset/   # setup 의 강제 재실행 백업 (날짜 디렉터리 자체에 -before-reset 접미사)
```

원래 경로를 그대로 복제하여 되돌리기 쉽게 한다.

**기존 archive 와의 호환**: 네임스페이스 도입 (v1.3.0) 이전에 archive 한 파일들은 `_archive/{date}/_workspace/...`, `_archive/{date}/docs/...` 식으로 루트에 직접 들어가 있다. audit/update 모두 이 기존 archive 를 건드리지 않는다 (보존). 신규 archive 만 자기 네임스페이스 하위에 쓴다.

### 3-6. 프롬프트 플레이스홀더

setup 이 `_workspace/prompts/*.md` 작성 시 프로젝트별 명령어로 치환하는 플레이스홀더 목록 (5종):

| 플레이스홀더 | 의미 | 치환 예시 |
|--------------|------|-----------|
| `{빌드 명령어}` | 빌드 실행 | `npm run build`, `pnpm build`, `yarn build` |
| `{테스트 명령어}` | 테스트 실행 | `npm test`, `vitest`, `pytest` |
| `{타입체크 명령어}` | 타입 검증 | `tsc --noEmit`, `mypy` |
| `{린트 명령어}` | 정적 분석 | `eslint .`, `ruff check` |
| `{레이어 검사 명령어}` | 아키텍처 경계 검사 | `node scripts/check-layer-import.js` |

**규칙**:
- setup 은 Phase 1 분석 결과로 5종을 모두 치환한다. 해당 도구가 없으면 (예: 레이어 검사 불필요한 프로젝트) 해당 작업 항목 자체를 프롬프트에서 제거한다 (빈 명령어로 남기지 않는다).
- update 는 비교 시 치환 위치의 차이를 사용자 커스터마이징으로 보지 않는다 (정규화 비교 시 제외).
- audit 은 프롬프트 본문을 수정하지 않는다.

---

## 4. `.harness-version` JSON 스키마

위치: `docs/quality/.harness-version`

### 정식 스키마

```json
{
  "harnessVersion": "x.y.z",
  "setupDate": "YYYY-MM-DD",
  "setupBy": "harness:setup",
  "lastUpdate": "YYYY-MM-DD",
  "updatedBy": "harness:update",
  "features": ["adr", "4-stage-pipeline", "quality-tracking", "mechanical-enforcement"]
}
```

### 필드 의미

| 필드 | 의미 | 누가 쓰나 | 누가 변경하나 |
|------|------|-----------|---------------|
| `harnessVersion` | `plugin.json` 의 `version` 과 일치 | setup 최초 생성, update 갱신 | setup, update |
| `setupDate` | 최초 setup 실행 날짜 | setup | **불변 — update 도 보존** |
| `setupBy` | 최초 셋업한 스킬 이름 | setup | **불변 — update 도 보존** |
| `lastUpdate` | 마지막 update 실행 날짜 (setup 직후엔 없거나 setupDate 와 동일) | update Phase 5 | update |
| `updatedBy` | 마지막 갱신한 스킬 이름 (setup 직후엔 없음) | update Phase 5 | update |
| `features` | 활성화된 기능 목록 | setup 최초 생성, update 가 추가/제거 가능 | setup, update |

**중요**:
- update 는 `setupDate`, `setupBy` 를 절대 수정하지 않는다. Phase 5 갱신 시 기존 값을 읽어 그대로 보존한다.
- update 가 **변경을 하나도 적용하지 않은 실행** (모든 항목 UP-TO-DATE 또는 사용자 keep/skip) 에서는 `lastUpdate`, `updatedBy`, `harnessVersion` 모두 **갱신하지 않는다**. `lastUpdate` 는 "마지막으로 실제 적용한 update" 만을 의미한다.
- 레거시 모드에서 기록된 `unknown` 값은 영구 고정 (이후 update 도 보존). 사용자가 정확한 값을 알고 직접 수정하는 건 본 규약 밖의 수동 작업.
- **필드 누락 호환**: v1.2.x update 가 `setupBy` 를 silently drop 한 파일을 v1.3 update 가 만나면, 부재 필드를 `"unknown (lost in v1.2.x migration)"` 으로 채워 넣고 사용자에게 안내한다. 이후엔 보존 대상.

### setup 직후 (update 미실행)

```json
{
  "harnessVersion": "1.2.0",
  "setupDate": "2026-04-12",
  "setupBy": "harness:setup",
  "features": ["adr", "4-stage-pipeline", "quality-tracking", "mechanical-enforcement"]
}
```

`lastUpdate`, `updatedBy` 는 update 가 처음 실행될 때 추가된다.

### 레거시 모드 (마커 없는 프로젝트에 update 가 처음 진입)

```json
{
  "harnessVersion": "{새 버전}",
  "setupDate": "unknown",
  "setupBy": "unknown (pre-marker)",
  "lastUpdate": "YYYY-MM-DD",
  "updatedBy": "harness:update",
  "features": [...]
}
```

---

## 5. `scores.json` 핵심 키

위치: `docs/quality/scores.json`. 권위적 스키마 정의 → `setup/references/quality-tracking.md` 1절.

세 스킬이 공통으로 의존하는 최상위 키:

| 키 | 의미 | 누가 갱신하나 |
|----|------|---------------|
| `lastUpdated` | 마지막 갱신 날짜 (YYYY-MM-DD) | Evaluator (PASS 시), audit (정합성 보정 시) |
| `currentPhase` | 현재 진행 중 Phase 번호 (정수) | Evaluator (다음 Phase 진입 시) |
| `phases` | Phase 별 점수 객체 맵 (`phase-N` 키) | Evaluator (PASS 시 새 항목 추가) |
| `phases.{key}.status` | `pending` / `in_progress` / `completed` | Evaluator |
| `phases.{key}.completedAt` | Phase 완료 날짜 | Evaluator (PASS 시) |
| `phases.{key}.layers` / `phases.{key}.overall` | 레이어 별 / 전체 점수 | Evaluator |

**audit 의 정합성 검사 대상** (drift-patterns.md 7절):
- `phases` 키 ↔ `docs/phases/` 실제 파일
- `lastUpdated` ↔ `quality-log.md` 최상단 항목 날짜
- `currentPhase` ↔ `_workspace/current-phase.md` 의 Phase 번호

**update 의 동작**: 절대 보존 (점수 이력 손상 위험).

---

## 6. ADR 불변 조건

| 규칙 | 내용 |
|------|------|
| 번호 형식 | 4자리 zero-padded (`0001`) |
| 번호 재사용 | 금지 |
| 본문 불변 | 발행 후 어떤 스킬도 본문 수정 X (오타 수정도 새 ADR 로) |
| 상태 집합 | `Proposed` \| `Accepted` \| `Deprecated` \| `Superseded by [ADR-NNNN](NNNN-...)` |
| 상태 전이 | 이 4개 사이만 가능. 본문 외 상태 한 줄만 갱신 |
| 번복 절차 | 새 ADR 작성 (Accepted) + 기존 ADR 의 상태만 `Superseded by ...` 로 변경 |
| 상태 변경 권한 | setup 의 회고 시점 / Evaluator 의 신규 발행 또는 Supersede 시점 |

audit 는 본문도 상태도 수정하지 않는다 (인덱스 테이블 재생성만).
update 는 본문도 상태도 수정하지 않는다.

---

## 7. 보호 파일 매트릭스

행: 파일/디렉터리, 열: 각 스킬이 그 파일에 대해 갖는 권한.

| 파일 / 디렉터리 | setup | audit | update |
|-----------------|-------|-------|--------|
| `AGENTS.md` 본문 | 작성 (최초) | 깨진 포인터 **주석 처리만** | 관리 섹션만 교체 (전체 교체 금지) |
| `docs/architecture.md` | 작성 (최초) | 보고만 (수정 X) | 보고만 (수정 X) |
| `docs/adr/NNNN-*.md` 본문 | 작성 (회고 ADR) | 본문 X · 상태 X | 본문 X · 상태 X |
| `docs/adr/README.md` 헤더/규칙 섹션 | 작성 | 보존 | 교체 가능 |
| `docs/adr/README.md` 인덱스 테이블 | 빈 테이블 작성 | **재생성** (실제 파일 기준) | **보존** (테이블 본문 절대 X) |
| `docs/adr/TEMPLATE.md` | 작성 | 보존 | PRISTINE 시 교체 |
| `docs/quality/scores.json` | 빈 상태 작성 | `lastUpdated` + 누락 Phase 만 갱신, 기존 점수 X | 보존 (점수 이력 절대 X) |
| `docs/quality/quality-log.md` | 빈 파일 작성 | 보존 | 보존 (누적 이력) |
| `docs/quality/audit-log.md` | (없음 — audit 첫 실행 시 자동 생성) | 첫 실행 시 생성, 이후 append 만 | 보존 |
| `docs/quality/update-log.md` | (없음 — update 첫 실행 시 자동 생성) | 보존 (예외 목록 명시) | 첫 실행 시 생성, 이후 append 만 |
| `docs/quality/.harness-version` | 작성 (최초) | 읽기만 (버전 정보 표시) | 갱신 (4절 규칙) |
| `docs/references/failure-lessons.md` | 빈 파일 작성 | 보존 (비어있어도 유지) | 본문 X (섹션 추가만 가능) |
| `docs/legacy-*/` | (없음) | 보존 (동결) | 보존 (동결) |
| `docs/phases/phase-*-*.md` | 작성 | 보존 | 보존 (프로젝트 고유) |
| `_workspace/current-phase.md` | 작성 (Phase 0) | 보존 | 보존 (진행 상태) |
| `_workspace/phase-{N}-contract.md` | (Planner 작성) | 보존 (모든 Phase 의 계약서는 이력) | 보존 (이력) |
| `_workspace/phase-{N}-completion.md` | (Evaluator 작성) | 보존 (이력) | 보존 (이력) |
| `_workspace/phase-{N}-eval.md` / `self-review.md` / `reference-analysis.md` | (각 단계 작성) | 보존 (이력) | 보존 (이력) |
| `_workspace/phase-{N}-fix-directive-{M}.md` 등 retry 산출물 | (각 단계 작성) | **완료 Phase 만** archive (활성 Phase 의 retry 산출물은 진행 중 작업이므로 보존) | 보존 |
| `_workspace/templates/*.md` | 작성 (4개) | 보존 | PRISTINE 이면 교체 |
| `_workspace/prompts/*.md` | 작성 (5개, 플레이스홀더 치환) | 보존 | PRISTINE 이면 교체 |
| `_workspace/analysis-report.md` | 작성 | 보존 | 보존 |
| `_workspace/audit-*.md` | (audit 가 생성) | 자기 이력 | 보존 |
| `_workspace/update-plan-*.md` | (update 가 생성) | 보존 | 자기 이력 |
| `scripts/*.js` | 작성 (레이어 검사) | 미사용 시 보고만 | 기본 CUSTOMIZED, PRISTINE 이면 교체 |
| `.claude/settings.local.json` | 작성 (Hook) | 수정 X | 수정 X |
| `_archive/` | 강제 재실행 시 `_archive/{date}-before-reset/` (예외 케이스) | `_archive/{date}/audit/` 아래만 추가 | `_archive/{date}/update-superseded/` 아래만 추가 |

**범례**:
- `작성 (최초)`: 없으면 생성. 있으면 setup 재실행 가드 발동
- `보존`: 절대 수정/이동/삭제 안 함
- `교체 가능`: 사용자 승인 시 표준 버전으로 갱신
- `archive`: `_archive/` 로 이동 (원본 위치 비움)
- `PRISTINE / CUSTOMIZED`: update 의 판정 (정규화 비교). 상세 → `update/references/sync-rules.md` 섹션 2

### `docs/adr/README.md` 분담 (충돌 방지)

이 파일은 setup, audit, update 모두가 만지지만 **다른 부분**을 만진다:
- 헤더/규칙 섹션 (`# Architecture Decision Records` ~ `## 작성 규칙`): **update 소관**
- 인덱스 테이블 (`| 번호 | 제목 | ... |`): **audit 소관 (재생성)**, **update 는 보존**
- 신규 ADR 발행 시 테이블 행 추가: Evaluator 소관

같은 날 audit + update 를 모두 돌려도 영역이 분리되어 충돌하지 않는다.

---

## 8. 4단계 파이프라인 산출물 흐름

```
사전 분석 (선택, 실패 기록 있을 때만)
  └─ phase-{N}-reference-analysis.md
       ↓
① 설계: Planner (읽기 전용)
  └─ phase-{N}-contract.md (← templates/sprint-contract.md 양식)
       ↓
② 구현: Generator
  └─ 코드 + 테스트
       ↓
③ 자기 리뷰: Self-Reviewer (별도 컨텍스트)
  └─ phase-{N}-self-review.md (← templates/self-review.md 양식)
       ↓
④ QA 평가: Evaluator
  ├─ PASS → phase-{N}-eval.md + phase-{N}-completion.md (← templates/completion-record.md)
  │         + scores.json 갱신 + ADR 발행 (해당 시)
  └─ FAIL → phase-{N}-eval.md + phase-{N}-fix-directive-{M}.md (← templates/fix-directive.md)
            → ② 구현 재진입 (최대 M=3)
            → 재진입 산출물: phase-{N}-self-review-retry-{M}.md, phase-{N}-eval-retry-{M}.md
```

---

## 9. 정보 격벽 (Information Barriers)

생성과 평가의 분리 (Anthropic 원칙) 를 강제한다:

- **Generator** 는 Evaluator 의 평가 기준 상세를 보지 않는다 (편향 방지)
- **Self-Reviewer** 는 Generator 의 추론을 보지 않는다 (코드와 계약서만 본다)
- **Evaluator** 는 Self-Reviewer 의 리뷰 결과를 보지 않는다 (독립 평가 보장)
- **Phase 간** 컨텍스트 리셋 — `_workspace/` 의 파일로만 인수인계

세 스킬은 이 격벽을 깨지 않는 범위에서만 동작한다.

---

## 10. 본 문서를 참조하는 곳 + 분담 규칙

### 누가 어떤 정보를 어디에 두는가

| 정보의 종류 | 단일 진실 | 예시 |
|-------------|-----------|------|
| 데이터 스키마 / 파일 명명 / 디렉터리 레이아웃 / 보호 권한 | **CONTRACTS.md** (이 문서) | `.harness-version` 필드, ADR 번호 형식, `_archive/` 네임스페이스 |
| 표준 템플릿 본문 / 표준 프롬프트 본문 | **setup/SKILL.md** Phase 4-2, 4-3 | `sprint-contract.md` 양식, `evaluator.md` 프롬프트 |
| 각 스킬의 행동 (Phase 흐름, AskUserQuestion, 알고리즘) | **각 SKILL.md** + `references/` | audit 의 8 영역 진단 순서, update 의 PRISTINE 판정 |
| 도메인 상세 (실패 교훈, 컨텍스트 불안 대응 등) | **setup/references/** | `phase-execution-protocol.md` 섹션 9 |

### 변경 시 영향 범위

- **CONTRACTS.md 변경** → 세 스킬에 동시 영향. 호환성 영향 (이미 셋업된 프로젝트의 동작 변화 여부) 을 검토하고 **`plugins/harness/.claude-plugin/plugin.json`** 과 **`.claude-plugin/marketplace.json`** 의 harness `version` 을 동시에 minor 이상 bump (두 파일이 일치해야 마켓플레이스에서 정확히 동기화됨). update 스킬의 `version-manifest.md` 8절 (버전 간 차이 지도) 에도 변경 사항을 추가한다.
- **setup/SKILL.md Phase 4-2/4-3 변경** → 표준 템플릿/프롬프트 변경. update 의 차이 지도 (`version-manifest.md` 8절) 갱신 필요.
- **각 SKILL.md 행동 변경** → 해당 스킬 1개에만 영향. 다른 스킬과의 인수인계 (보호 매트릭스, 산출물 명) 가 변경되면 CONTRACTS.md 도 함께 갱신.

### 참조하는 곳

- `skills/setup/SKILL.md` — 셋업 시 본 규약대로 인프라 생성
- `skills/audit/SKILL.md` — 본 규약 위반을 드리프트로 진단
- `skills/update/SKILL.md` — 본 규약을 보존하며 스킬 버전 동기화
- `skills/setup/references/knowledge-architecture.md` — 지도 원칙 (AGENTS.md 분량 가이드)
- `skills/audit/references/drift-patterns.md` — 본 규약 위반 패턴 정의
- `skills/update/references/version-manifest.md` — 본 규약을 따르는 update 매니페스트
