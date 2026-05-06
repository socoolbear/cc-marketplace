---
name: update
description: "이미 setup 된 하네스 프로젝트를 최신 스킬 버전에 맞춰 안전하게 동기화하는 스킬. /plugin update 로 스킬을 최신화한 뒤 /harness:update 를 실행하면 프로젝트의 AGENTS.md, docs/, _workspace/ 를 최신 스킬 기준으로 diff 하여 차이를 보고하고, 사용자 커스터마이징과 진행 이력(current-phase, scores.json, 발행된 ADR, 누적 교훈)을 절대 건드리지 않으면서 AskUserQuestion 으로 항목별 승인을 받아 적용한다. 신규 추가, 안전 업그레이드, 충돌 해결, 구조 변경, AGENTS.md 섹션 삽입을 처리한다. '하네스 업데이트', '하네스 최신화', 'harness update', '스킬 변경 반영', 'setup 재실행 대신', '버전 마이그레이션' 요청 시 사용. setup 을 재실행하면 진행 상태·점수 이력·ADR 인덱스가 리셋될 수 있으므로 반드시 이 스킬을 사용해야 한다."
---

# Harness Update — 최신 스킬 기준 프로젝트 동기화

하네스가 이미 셋업된 프로젝트를 최신 스킬 버전에 맞춰 안전하게 동기화한다.
setup 과 달리 **기존 커스터마이징과 진행 이력을 보존**하면서 차이만 반영한다.

> **사전 지식**: 이 스킬은 `setup`, `audit` 와 [`../../CONTRACTS.md`](../../CONTRACTS.md) 의 공유 규약 (디렉터리 레이아웃, `.harness-version` 스키마와 보존 규칙, 보호 파일 매트릭스, ADR 불변 조건) 을 따른다. 본 SKILL.md 는 **버전 동기화 행동** 만 정의한다.

## setup / audit / update 의 역할 분리

`CONTRACTS.md` 1절 참조. 요약:

| 스킬 | 방향 | 기준 |
|------|------|------|
| `setup` | 0 → 1 | 하네스가 없는 프로젝트에 구축 (1회성) |
| `audit` | 프로젝트 내부 드리프트 제거 | 프로젝트 vs 프로젝트 (내부 정합성) |
| `update` | 스킬 버전 차이 반영 | 프로젝트 vs 최신 스킬 (외부 동기화) |

## 선결 조건

1. **`/plugin update harness@cc-marketplace`** 를 먼저 실행 — 스킬 파일 자체를 마켓플레이스 최신 버전으로 갱신
2. 그 다음 이 스킬을 호출

스킬이 최신이 아니면 이 스킬도 구버전 기준으로 동작하므로 의미가 없다.
Phase 0 에서 사용자에게 이 순서를 확인한다.

## 파괴적 작업 원칙

- **자동 교체 없음**. 모든 교체는 archive → 사용자 확인 → 적용
- **절대 보존 카테고리**: 진행 이력, 품질 점수, 발행된 ADR 본문, 누적 교훈 — 어떤 상황에서도 건드리지 않음
- **AskUserQuestion 기반 승인** (audit 과 동일 원칙)

보호 대상 상세 → `references/version-manifest.md` 의 "절대 보존" 섹션
승인 패턴 상세 → `references/sync-rules.md`

## 워크플로우

### Phase 0: 사전 확인

**0-1. 하네스 셋업 여부 확인:**
- `AGENTS.md`, `docs/architecture.md`, `_workspace/current-phase.md` 존재 여부 확인
- 하나라도 없으면 "먼저 `/harness:setup` 을 실행하세요" 안내 후 종료

**0-2. 버전 마커 확인:**
- `docs/quality/.harness-version` 존재 → **마커 기반 모드**
  - `harnessVersion` 필드 읽어 이전 버전 파악
- 존재하지 않음 → **레거시 모드** (setup v1.1 이전, 즉 `.harness-version` 마커 도입 전에 구축된 프로젝트)
  - 이전 버전을 `unknown` 으로 간주하고 파일 단위 diff 로 진행

**0-3. `/plugin update` 선결 확인:**

사용자에게 **AskUserQuestion** 으로 확인:

> "이 스킬의 로컬 버전은 v{현재}. 마켓플레이스 최신 버전을 받으려면 먼저 `/plugin update harness@cc-marketplace` 를 실행해야 합니다.
> 이미 최신으로 업데이트했다면 '예' 를 선택하세요. 그렇지 않으면 이 스킬을 중단하고 먼저 `/plugin update` 를 실행해주세요."
>
> 옵션: 1. 예 (스킬이 최신임) / 2. 아니오 (중단)

### Phase 1: 차이 계산 (Auditor 역할)

표준 파일 매니페스트 → `references/version-manifest.md`

**1-1. 표준 파일 목록 수집:**

매니페스트에서 카테고리별 파일 목록 수집:
- `protection` (절대 보존) — 존재만 확인
- `stock-templates` (표준 템플릿)
- `stock-prompts` (표준 프롬프트)
- `structural` (신설 파일/디렉터리)
- `agents-md-sections` (AGENTS.md 관리 섹션)
- `scripts`

**1-2. 각 파일의 판정:**

| 상태 | 정의 | 기본 동작 |
|------|------|-----------|
| `MISSING` | 프로젝트에 없음 (새 버전에서 추가) | 생성 (auto-safe) |
| `PRISTINE` | 이전 스킬 버전의 기본값과 일치 | 최신으로 교체 가능 (auto-safe) |
| `CUSTOMIZED` | 사용자 수정 있음 | 개별 확인 (needs-confirmation) |
| `UP-TO-DATE` | 최신 기본값과 이미 일치 | 스킵 |

**1-3. 표준 내용 추출:**

각 표준 파일의 "정답" 은 `../setup/SKILL.md` 의 해당 섹션에 있다. 매니페스트가 어느 섹션을 참조할지 알려준다.

**1-4. 플레이스홀더 처리:**

`{빌드 명령어}`, `{테스트 명령어}` 등은 setup 이 의도적으로 치환한 것이다. **치환된 부분은 사용자 커스터마이징이 아니다.** 판정 시 플레이스홀더 위치의 차이는 무시하고 그 외 본문만 비교한다.

**1-5. agent-tooling feature 활성화 검사 (v1.4.0+):**

`docs/quality/.harness-version` 의 features 배열에 `"agent-tooling"` 포함 여부 확인:
- 포함됨 → `references/sync-rules.md` 9절 (agent-tooling 산출물 정책) 적용하여 차이 계산
- 미포함 (v1.3.x 프로젝트 또는 도구 0개로 비활성) → AskUserQuestion 으로 활성화 의사 확인:

```
v1.4.0 부터 agent-tooling 기능이 도입되었습니다 (CLI 도구 규약, 권한, fallback 정책).
활성화하시겠습니까?

옵션:
  1. Y — 후속 단계에서 cli-tooling.md, AGENTS.md 포인터, 5개 프롬프트 셸 도구 규약 섹션 추가 propose
  2. n — 이번 update 만 보류 (다음 update 에 다시 묻기, features 배열 변경 X, harnessVersion 미갱신)
  3. show-detail — agent-tooling 의 도구 매핑 / 빌트인 우선순위 / fallback 정책 / 환경 분리 (포터블 vs 머신별) 요약을 보여준 뒤 재질문
```

도구 0개 환경에서 Y 선택 시: setup Phase 1-5 와 동일하게 "현대 CLI 도구가 감지되지 않습니다. 비활성화 권고" 안내. 사용자가 그래도 활성화 원하면 cli-tooling.md 와 AGENTS.md 포인터만 추가 (settings.local.json permissions 는 audit 가 추후 동기화).

상세 → `references/sync-rules.md` 9절, `setup/references/agent-tooling.md` 1, 4절

### Phase 2: 업데이트 플랜 보고서 (Reporter)

`_workspace/update-plan-YYYY-MM-DD.md` 작성:

```markdown
# Update Plan — YYYY-MM-DD

## 스킬 버전
- 이전: v{.harness-version 의 harnessVersion, 없으면 "unknown (레거시)"}
- 현재: v{plugin.json 의 version}

## 요약
- 신규 추가 (MISSING): N건
- 안전 업그레이드 (PRISTINE): N건
- 충돌 (CUSTOMIZED): N건
- 이미 최신 (UP-TO-DATE): N건

## 카테고리별 발견

### 신규 추가 — auto-safe
- `docs/adr/TEMPLATE.md` — ADR 템플릿 (v1.1.0 에서 추가)
- `docs/adr/README.md` — ADR 인덱스

### 안전 업그레이드 — auto-safe
- `_workspace/templates/sprint-contract.md`
  - 변경 요약: "관련 ADR" / "예상 ADR 후보" 섹션 추가
- `_workspace/templates/completion-record.md`
  - 변경 요약: "아키텍처 결정", "발행된 ADR", "번복된 ADR" 섹션 추가

### 충돌 — needs-confirmation
- `_workspace/prompts/evaluator.md` — 사용자 수정 있음
  - 변경 요약: 최신 버전은 ADR 발행 단계 (작업 7 + PASS 시 출력 4) 추가
  - 선택지: keep / replace / show-diff

### AGENTS.md 섹션 삽입
- "Phase 실행 — 4단계 파이프라인" 섹션 — 누락 (신설 대상)
- 문서 지도에 "아키텍처 결정 이력 → docs/adr/README.md" 포인터 — 누락
- "셸 도구 규약 → docs/conventions/cli-tooling.md" 포인터 — 누락 (v1.4.0+, agent-tooling feature 활성화 시)

### agent-tooling 마이그레이션 (v1.4.0+, 1-5 에서 Y 선택 시만 표시)
- `docs/conventions/cli-tooling.md` — 신규 (MISSING)
- `_workspace/prompts/{pre-analysis,planner,generator,self-reviewer,evaluator}.md` — 끝에 "셸 도구 규약" 섹션 추가 (MISSING/CUSTOMIZED 가능)
```

### Phase 3: 승인 (대화형)

승인 패턴 상세 → `references/sync-rules.md` 섹션 3

**질문 A — auto-safe 일괄**:

```
자동 적용 가능한 {N}개 항목을 적용할까요?
  - 신규 추가 (MISSING): {N1}건
  - 안전 업그레이드 (PRISTINE): {N2}건

옵션:
  1. 예, 모두 적용
  2. 개별 검토 (질문 B 로 전환)
  3. 건너뛰기
```

**질문 B — CUSTOMIZED 개별**:

```
{파일 경로} — 사용자 수정이 감지됨.
최신 버전은 {변경 요약}.

옵션:
  1. keep (그대로 유지)
  2. replace (최신으로 교체, 기존은 _archive 로)
  3. show-diff (diff 확인 후 재선택)
```

show-diff 선택 시: 에이전트가 diff 를 출력한 뒤 다시 질문 (keep / replace).

**질문 C — AGENTS.md 섹션 삽입**:

```
AGENTS.md 에 '{섹션 제목}' 섹션을 추가할까요?

옵션:
  1. 추가 (파일 끝에 append)
  2. show-content (삽입할 내용 확인 후 재선택)
  3. 건너뛰기
```

### Phase 4: 적용 (Cleaner)

승인된 항목만 실행한다.

**4-1. 신규 추가 (MISSING)**:
- 표준 내용으로 파일/디렉터리 생성
- 구조 변경 (예: `docs/adr/`) 도 여기서 처리

**4-2. 교체 (PRISTINE → replace 또는 CUSTOMIZED → replace)**:
- 기존 파일을 `_archive/YYYY-MM-DD/update-superseded/원래경로/` 로 이동
- 표준 내용으로 덮어쓰기
- 플레이스홀더가 있으면 프로젝트 특화 값으로 재치환

**4-3. keep (CUSTOMIZED → keep)**:
- 아무 것도 하지 않음

**4-4. AGENTS.md 섹션 삽입**:
- 전체 파일 교체 금지. **섹션 단위로만 삽입**
- 누락된 섹션을 파일 끝에 append
- 기존 섹션이 있으면 내용 비교 후 CUSTOMIZED/PRISTINE 판정
- `docs/adr/README.md` 도 **인덱스 테이블은 보존**, 상단 헤더/작성 규칙 섹션만 교체

**4-5. agent-tooling 마이그레이션 적용 (v1.4.0+, 1-5 에서 Y 선택 + 도구 0개 거부 안 한 경우)**:

1. setup Phase 4-7 동등 동작: `docs/conventions/cli-tooling.md` 작성 (references/agent-tooling.md 2~5절 기반, 환경 무관)
2. setup Phase 2-1 의 AGENTS.md 포인터 한 줄 추가: 8절 AGENTS.md 섹션 삽입 패턴 (질문 C) 적용 — "셸 도구 규약 → docs/conventions/cli-tooling.md"
3. setup Phase 4-3 동등 동작: 5개 프롬프트 끝에 셸 도구 규약 섹션 append (기존 본문 0 변경, sync-rules.md 9-2 절 참조). 프롬프트 파일이 일부 부재면 존재하는 것에만 append + 부재 파일은 보고만.
4. `.harness-version` features 배열에 `"agent-tooling"` 추가 + `harnessVersion` 을 `plugin.json` 의 최신 version 으로 갱신 (CONTRACTS.md 4절)

**절대 하지 않는 것**:
- `.claude/settings.local.json` 의 `permissions.allow` 권한 등록 (audit 9영역 소관 — sync-rules.md 9-3 절)
- 사용자가 자체 작성한 cli-tooling 관련 파일 덮어쓰기 (충돌 시 사용자 위임 — sync-rules.md 9-5 절)
- 프롬프트의 기존 본문 수정 (셸 도구 규약 섹션만 끝에 append)

**마이그레이션 검증** (Phase 5 기록 단계 전):
- `scores.json` 점수 0 손실 (jq 비교)
- 발행된 ADR 본문 0 변경
- `_workspace/current-phase.md` 진행 상태 보존

**4-6. 절대 보존 카테고리는 어떤 상황에서도 건드리지 않는다** (매니페스트의 protection 섹션 참조).

### Phase 5: 기록

**5-0. 갱신 여부 판단**:

Phase 4 에서 실제 적용된 변경사항이 **하나도 없으면** (모든 항목이 UP-TO-DATE 또는 사용자가 모두 keep/skip 선택), Phase 5 의 갱신과 로그 기록을 모두 **건너뛴다**. 사용자에게 "변경사항 없음 — `.harness-version` 과 update-log 를 갱신하지 않습니다" 라고 안내하고 종료한다.

이유: `lastUpdate` 는 "마지막으로 실제 적용한 update" 의 날짜다. no-op 실행으로 갱신하면 의미가 흐려진다.

**5-1. `.harness-version` 갱신**:

스키마 정의 (필드 의미, 누가 쓰는지) → `../../CONTRACTS.md` 4절

**보존 규칙**: `setupDate`, `setupBy` 는 **절대 수정하지 않는다**. 기존 값을 읽어 그대로 보존한다 (한 번이라도 update 가 돌면 최초 셋업 흔적이 사라지면 안 됨).

마커 기반 모드 (기존 `.harness-version` 이 있는 경우):

1. 기존 파일을 읽어 `setupDate`, `setupBy` 값을 보존한다
2. `harnessVersion`, `lastUpdate`, `updatedBy`, `features` 만 갱신한다

```json
{
  "harnessVersion": "{새 버전}",
  "setupDate": "{기존 값 — 절대 수정 X}",
  "setupBy": "{기존 값 — 절대 수정 X}",
  "lastUpdate": "YYYY-MM-DD",
  "updatedBy": "harness:update",
  "features": ["adr", "4-stage-pipeline", ...]
}
```

**필드 누락 처리** (v1.2.x update 가 `setupBy` 를 silently drop 한 파일과의 호환):

기존 `.harness-version` 에서 `setupBy` 또는 `setupDate` 가 부재인 경우:
- 부재인 필드는 `"unknown (lost in v1.2.x migration)"` (setupBy) 또는 `"unknown"` (setupDate) 로 채워 넣는다
- 사용자에게 안내: "이전 update 실행에서 손실된 셋업 정보를 `unknown` 으로 보충했습니다. 정확한 값을 알면 `.harness-version` 을 직접 수정하세요."
- 채워진 `unknown` 값도 이후 update 의 보존 대상이 된다 (영구 고정)

레거시 모드 (마커가 없는 프로젝트에 update 가 처음 진입):

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

**주의**: 위 `unknown` 값은 한 번 기록되면 보존 규칙에 따라 영구 고정된다 (이후 update 도 setupDate/setupBy 를 건드리지 않음). 사용자가 실제 셋업 날짜를 안다면 update 직후 `.harness-version` 을 직접 수정해도 된다 — 본 스킬의 자동 동작은 아님을 안내한다.

**5-2. `docs/quality/update-log.md` 항목 추가**:

로그 형식 → `references/sync-rules.md` 섹션 6

로그 파일이 없으면 생성한다.

## 산출물

- [ ] `_workspace/update-plan-YYYY-MM-DD.md` — 업데이트 플랜 보고서
- [ ] `_archive/YYYY-MM-DD/update-superseded/` — 교체된 기존 파일 (교체 발생 시)
- [ ] `docs/quality/.harness-version` — 버전 마커 갱신 (레거시 모드에서는 생성)
- [ ] `docs/quality/update-log.md` — 시계열 로그 (항목 추가)

## 적용하지 않는 것

- 스킬 파일 자체 최신화 → `/plugin update harness@cc-marketplace` 사용
- 하네스가 없는 프로젝트에 0→1 구축 → `/harness:setup` 사용
- 내부 드리프트 탐지/정리 → `/harness:audit` 사용
- 코드 변경 / 테스트 실행 → 별도 도구
- `docs/legacy-*/` 정리 → 동결 원칙 유지

## 참고

- **공유 규약 (setup/audit 와 동일한 단일 진실)**: `../../CONTRACTS.md`
- 표준 파일 매니페스트 (어떤 파일이 표준인지, 어디서 정답을 가져올지): `references/version-manifest.md`
- 동기화 규칙 (AskUserQuestion 패턴, 충돌 해결, archive, log 형식): `references/sync-rules.md`
- setup 스킬 (최초 구축): `../setup/SKILL.md`
- audit 스킬 (내부 드리프트 제거): `../audit/SKILL.md`
