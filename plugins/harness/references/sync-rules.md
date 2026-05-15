# 동기화 규칙 — 충돌 해결 및 AskUserQuestion 패턴

update 모드의 Phase 3-5 에서 따르는 세부 규칙.

---

## 1. 보호 카테고리 (절대 건드리지 않음)

상세 목록: `version-manifest.md` 의 "절대 보존" 섹션.

update 는 이 파일들에 대해 다음만 수행한다:
- **존재 확인**: Phase 0 에서 하네스 셋업 여부 판정용
- **읽기**: 필요 시 맥락 파악용 (예: 현재 Phase 번호 확인)

**금지**:
- 내용 수정
- 덮어쓰기
- archive 로 이동
- 삭제

사용자가 명시적으로 수정을 요청해도 update 모드는 수행하지 않는다 (audit 모드의 범위).

---

## 2. 판정 규칙

### PRISTINE 판정

파일 내용이 현재 스킬 버전의 "정답"과 정확히 일치 (공백 정규화 후).

공백 정규화:
- 연속 공백/탭을 단일 공백으로
- 줄 끝 trailing 공백 제거
- 파일 끝 빈 줄 정규화
- 플레이스홀더 치환 위치는 비교에서 제외 (version-manifest 섹션 7 참조)

### CUSTOMIZED 판정

- 파일이 존재하지만 PRISTINE 이 아닌 경우
- 단, 플레이스홀더 치환은 커스터마이징이 아님

### MISSING 판정

파일이 존재하지 않음 (주로 새 버전에서 추가된 파일).

### UP-TO-DATE 판정

파일 내용이 **최신** 스킬 버전의 정답과 일치. 업데이트할 것이 없음.

---

## 3. AskUserQuestion 패턴

### 패턴 A: auto-safe 일괄 (질문 1개)

MISSING 과 PRISTINE 을 묶어 한 번에 확인:

```
자동으로 적용 가능한 {N}개 항목을 적용할까요?
  - 신규 추가 (MISSING): {N1}건
  - 안전 업그레이드 (PRISTINE): {N2}건

옵션:
  1. 예, 모두 적용 (권장)
  2. 개별 검토 (패턴 B 로 전환)
  3. 건너뛰기 (auto-safe 도 적용하지 않음)
```

질문 전에 요약을 보여준다:

```
MISSING 항목:
  - docs/adr/TEMPLATE.md
  - docs/adr/README.md

PRISTINE 항목:
  - _workspace/templates/sprint-contract.md (v1.1.0 업그레이드)
  - _workspace/templates/completion-record.md (v1.1.0 업그레이드)
```

### 패턴 B: CUSTOMIZED 개별 (질문 여러 개)

파일당 3-way 선택. AskUserQuestion 은 한 번에 복수 질문 병렬 가능하므로 2-3개씩 묶어 질문한다.

```
{파일 경로} — 사용자 수정이 감지됨.
최신 버전의 주요 변경: {변경 요약}

옵션:
  1. keep (그대로 유지)
  2. replace (최신으로 교체, 기존은 _archive 로)
  3. show-diff (diff 확인 후 재선택)
```

**show-diff 선택 시**:
1. 에이전트가 diff 를 출력 (공백 정규화, +/- 형식)
2. 재질문 (keep / replace — show-diff 제거)

### 패턴 C: AGENTS.md 섹션 삽입 (질문 1~N개)

AGENTS.md 는 전체 교체 금지. 섹션 단위로만 처리한다.

```
AGENTS.md 에 '{섹션 제목}' 섹션을 추가할까요?

변경 요약: {섹션이 왜 필요한지 한 줄}

옵션:
  1. 추가 (파일 끝에 append)
  2. show-content (삽입할 내용 확인 후 재선택)
  3. 건너뛰기
```

기존에 섹션이 존재하는 경우 (PRISTINE/CUSTOMIZED):
- PRISTINE → auto-safe 로 교체 (패턴 A 로 통합)
- CUSTOMIZED → 패턴 B 로 개별 확인

**묶음 전략**:
- 같은 버전업의 변경사항들을 한 번의 AskUserQuestion 호출로 병렬 질문
- 심각도 순서: MISSING > CUSTOMIZED > PRISTINE

---

## 4. 플레이스홀더 처리

플레이스홀더 5종 단일 정의 → `../CONTRACTS.md` 3-6 절

### 감지

setup 이 모든 플레이스홀더를 치환했어야 한다. 프로젝트 파일에 여전히 `{빌드 명령어}` 가 문자 그대로 남아있다면:
- setup 이 해당 명령을 찾지 못했을 가능성
- update 플랜에 "치환 누락" 로 별도 보고

### 보존 규칙

비교 시 플레이스홀더 위치는 **무시**한다. 즉 프로젝트의 치환값이 무엇이든 상관없음.

교체 시 플레이스홀더 재치환:
1. 프로젝트 현재 파일에서 플레이스홀더 위치의 치환값 추출
2. 표준 내용의 해당 위치에 같은 치환값 삽입
3. 최종 결과를 프로젝트에 쓰기

---

## 5. Archive 구조

교체 발생 시 (`../CONTRACTS.md` 3-5 절):

```
프로젝트 루트/
  _archive/
    YYYY-MM-DD/
      audit/                      # ← 같은 날 audit 가 archive 한 파일들 (update 는 안 건드림)
      update-superseded/          # ← update 의 자기 네임스페이스
        _workspace/
          templates/
            sprint-contract.md    ← 교체 전 기존 버전
          prompts/
            evaluator.md          ← 교체 전 기존 버전
        docs/
          adr/
            README.md             ← 교체 전 기존 (인덱스 테이블 보존 로직 실패 시 대비)
        AGENTS.md                 ← 섹션 교체 시 전체 백업
```

**원칙**:
- 날짜는 update 실행 날짜
- 원래 경로를 `update-superseded/` 하위에 복제
- audit 와 같은 날 실행되어도 네임스페이스로 분리되어 충돌 없음

---

## 6. update-log.md 형식

`docs/quality/update-log.md` 상단에 추가 (최신 항목이 위):

```markdown
## 2026-04-24
- 이전 버전: v1.0.0
- 새 버전: v1.1.0
- 실행 시각: HH:MM {TZ}
- 모드: 마커 기반 / 레거시 (둘 중 하나)
- 보고서: `_workspace/update-plan-2026-04-24.md`
- 조치:
  - 신규 추가 (MISSING): N건
  - 안전 업그레이드 (PRISTINE): N건 적용 / N건 스킵
  - 교체 (CUSTOMIZED → replace): N건
  - keep (CUSTOMIZED → keep): N건
  - 이미 최신 (UP-TO-DATE): N건
- 마이그레이션 (해당 시):
  - `setupBy` 필드 부재로 `"unknown (lost in v1.2.x migration)"` 보충
  - 또는 다른 호환성 보충 사항
- 주요 변경 사항:
  - ADR 인프라 통합 (docs/adr/)
  - sprint-contract 에 "관련 ADR" 섹션 추가
  - evaluator 프롬프트에 ADR 발행 단계 추가
```

로그 파일이 없으면 생성한다:

```markdown
# Update Log

harness:update 실행 이력. 최신 항목이 상단.
```

---

## 7. 레거시 모드

`.harness-version` 이 없는 프로젝트 (setup v1.1.0 이전, 즉 마커 도입 전에 구축):

- 이전 버전을 `unknown` 으로 간주
- 표준 파일 비교는 동일 (PRISTINE/CUSTOMIZED/MISSING)
- update 완료 시 `.harness-version` 을 **신규 생성** (스키마 정의 → `../CONTRACTS.md` 4절):
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
- 로그의 `모드` 필드에 `레거시` 로 표기

### 마커 기반 모드의 보존 규칙

`.harness-version` 이 이미 존재하는 경우, update 는 **`setupDate`, `setupBy` 를 절대 수정하지 않는다**. 기존 값을 읽어 그대로 보존하고 `harnessVersion`, `lastUpdate`, `updatedBy`, `features` 만 갱신한다 (`CONTRACTS.md` 4절 필드 매트릭스).

---

## 8. AGENTS.md 섹션 삽입 세부

### 삽입 위치

관리 섹션 (version-manifest 섹션 5 참조) 각각의 규칙:

**"Phase 실행 — 4단계 파이프라인" 섹션**:
- 누락 시: 파일 **끝에 append**
- 존재 시: 섹션 전체를 추출 (마크다운 헤더 기준)하여 내용 비교

**문서 지도의 ADR 포인터**:
- 누락 시: 문서 지도 섹션 내에서 `아키텍처 요약 → docs/architecture.md` 다음 줄에 삽입
- 존재 시: PRISTINE 상태로 간주 (업데이트 불필요)

### 섹션 경계 식별

- 시작: `##` 또는 `###` 마크다운 헤더
- 끝: 동일 레벨 또는 상위 레벨의 다음 헤더 직전
- 이 경계 내에서 내용 비교

---

## 9. agent-tooling 산출물 정책 (v1.4.0+)

agent-tooling feature 활성화 프로젝트의 신규 산출물에 대한 update 동기화 규칙. 권위적 정의 → `./agent-tooling.md`. 버전 차이 지도 → `version-manifest.md` 8절 v1.3.0 → v1.4.0.

### 9-1. `docs/conventions/cli-tooling.md`

- **PRISTINE 판정**: setup 이 작성한 표준 본문 (references/agent-tooling.md 2~5절 기반) 과 정규화 비교하여 일치
- **CUSTOMIZED 판정**: 사용자가 도구를 추가/제거하거나 주석을 달았음 → 본문 수정 X, 차이만 보고
- **MISSING**: v1.3.x 프로젝트에 agent-tooling 활성화 시. setup Phase 4-7 와 동일하게 작성
- **references/agent-tooling.md 자체 갱신** 시: PRISTINE 프로젝트는 자동 동기화 (auto-safe 패턴 A), CUSTOMIZED 는 차이 보고만 (패턴 B)

### 9-2. `_workspace/prompts/*.md` 끝의 "셸 도구 규약" 섹션

5개 프롬프트 (pre-analysis, planner, generator, self-reviewer, evaluator) 의 끝부분 8줄 섹션 (`## 셸 도구 규약 (agent-tooling feature 활성화 시만 포함)`).

- **PRISTINE 판정**: 표준 본문 (setup SKILL.md Phase 4-3) 과 정규화 비교 일치
- **CUSTOMIZED 판정**: 사용자가 추가 규칙 작성 → 보고만, 본문 수정 X
- **MISSING (v1.3.x → v1.4)**: 프롬프트 끝에 표준 본문 append (기존 본문 0 변경, 끝에만 추가). 8절 (AGENTS.md 섹션 삽입 세부) 의 헤더 경계 인식 알고리즘 활용
- **프롬프트 자체가 CUSTOMIZED 인 경우**: 본문은 보존, 셸 도구 규약 섹션만 끝에 append (두 정책이 충돌하지 않음)
- **프롬프트 파일 자체가 부재**: 사용자가 의도적으로 삭제했을 가능성 → 보고만 (자동 재생성 X). `_workspace/templates/*.md` 의 부재 정책과 동일

### 9-3. `.claude/settings.local.json` 의 `permissions.allow` 도구 권한

- **update 는 절대 수정 X** (CONTRACTS.md 7절: audit 9영역 소관)
- 기존 권한 (예: `Bash(rg:*)` 등) 이 있으면 그대로 보존
- v1.3 → v1.4 마이그레이션 시 사용자가 활성화에 동의하더라도 update 는 권한을 작성하지 않는다. `/harness:run` 9영역이 머신 환경에 맞춰 사용자에게 propose

### 9-4. AGENTS.md 의 "셸 도구 규약" 한 줄 포인터

- **MISSING (v1.3.x)**: AGENTS.md 의 "참조 문서" 또는 "문서 지도" 영역에 한 줄 추가 — 8절 AGENTS.md 섹션 삽입 패턴 (질문 C) 적용
- **PRISTINE/CUSTOMIZED**: 이미 추가되어 있으면 보존

### 9-5. 충돌 케이스

- 사용자가 자체적으로 비슷한 파일 (예: `docs/cli-conventions.md`, `docs/tools.md`) 을 만들어둔 경우 → 충돌 보고 + 사용자에게 병합 위임 (자동 덮어쓰기 X)
- 5개 프롬프트 중 일부에 이미 비슷한 섹션이 있으면 → 그 프롬프트만 CUSTOMIZED 로 판정, 나머지에만 표준 섹션 append

---

## 10. 안티패턴

| 안티패턴 | 대신 |
|----------|------|
| `current-phase.md`, `scores.json` 초기화 | 절대 금지 — 진행 이력 보존 |
| `docs/adr/README.md` 를 빈 인덱스로 전체 교체 | 인덱스 테이블 보존, 상단 헤더/규칙만 교체 |
| 발행된 ADR 본문 수정 | 절대 금지 — 불변 원칙 (ADR 은 새로 발행, Superseded 처리) |
| `AGENTS.md` 전체 교체 | 섹션 단위 삽입/교체만 |
| CUSTOMIZED 자동 교체 | 항상 사용자 확인 (패턴 B) |
| 보고서 없이 즉시 적용 | 항상 Phase 2 보고서 먼저 |
| 플레이스홀더를 커스터마이징으로 오판 | 치환 위치는 비교에서 제외 |
| audit 작업을 update 안에서 수행 | audit 은 별도 스킬 — update 는 스킬 버전 동기화에만 집중 |
| `docs/architecture.md` 수정 | 권위적 원천. update 가 건드리지 않음 (사람이 직접 관리) |
| `settings.local.json` 의 `permissions.allow` 권한 등록 (v1.4.0+) | audit 9영역 소관 — update 는 보존만 |
| 사용자 자체 cli-tooling 파일 자동 덮어쓰기 (v1.4.0+) | 충돌 보고 + 병합 위임 (9-5 절) |
