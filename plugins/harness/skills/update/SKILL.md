---
name: update
description: "이미 setup 된 하네스 프로젝트를 최신 스킬 버전에 맞춰 안전하게 동기화하는 스킬. /plugin update 로 스킬을 최신화한 뒤 /harness:update 를 실행하면 프로젝트의 AGENTS.md, docs/, _workspace/ 를 최신 스킬 기준으로 diff 하여 차이를 보고하고, 사용자 커스터마이징과 진행 이력(current-phase, scores.json, 발행된 ADR, 누적 교훈)을 절대 건드리지 않으면서 AskUserQuestion 으로 항목별 승인을 받아 적용한다. 신규 추가, 안전 업그레이드, 충돌 해결, 구조 변경, AGENTS.md 섹션 삽입을 처리한다. '하네스 업데이트', '하네스 최신화', 'harness update', '스킬 변경 반영', 'setup 재실행 대신', '버전 마이그레이션' 요청 시 사용. setup 을 재실행하면 진행 상태·점수 이력·ADR 인덱스가 리셋될 수 있으므로 반드시 이 스킬을 사용해야 한다."
---

# Harness Update — 최신 스킬 기준 프로젝트 동기화

하네스가 이미 셋업된 프로젝트를 최신 스킬 버전에 맞춰 안전하게 동기화한다.
setup 과 달리 **기존 커스터마이징과 진행 이력을 보존**하면서 차이만 반영한다.

## setup / audit / update 의 역할 분리

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
- 존재하지 않음 → **레거시 모드** (setup v1.0 이전에 구축된 프로젝트)
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

**4-5. 절대 보존 카테고리는 어떤 상황에서도 건드리지 않는다** (매니페스트의 protection 섹션 참조).

### Phase 5: 기록

**5-1. `.harness-version` 갱신**:

```json
{
  "harnessVersion": "{새 버전}",
  "setupDate": "{기존 값 유지}",
  "lastUpdate": "YYYY-MM-DD",
  "updatedBy": "harness:update",
  "features": ["adr", "4-stage-pipeline", ...]
}
```

레거시 모드에서 신규 생성하는 경우:
- `setupDate`: `"unknown"` 으로 기록
- `lastUpdate`: 오늘 날짜

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

- 표준 파일 매니페스트 (어떤 파일이 표준인지, 어디서 정답을 가져올지): `references/version-manifest.md`
- 동기화 규칙 (AskUserQuestion 패턴, 충돌 해결, archive, log 형식): `references/sync-rules.md`
- setup 스킬 (최초 구축): `../setup/SKILL.md`
- audit 스킬 (내부 드리프트 제거): `../audit/SKILL.md`
