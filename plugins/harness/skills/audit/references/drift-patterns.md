# 드리프트 패턴 — 8개 영역 상세

setup 스킬로 구축된 하네스 인프라에서 시간이 지남에 따라 발생할 수 있는 오염 패턴.
각 패턴마다 **탐지 방법**과 **정리 방법**을 명시한다.

---

## 심각도 기준

| 레벨 | 의미 | 예시 |
|------|------|------|
| `critical` | 에이전트 실행을 직접 차단하거나 잘못된 결정을 유도 | AGENTS.md 포인터 깨짐, ADR 번호 중복 |
| `major` | 문서-코드 괴리로 에이전트가 잘못된 맥락 파악 | architecture.md 규칙이 코드에서 미적용 |
| `minor` | 노이즈 증가, 즉각적 위험 없음 | 완료 Phase 의 fix-directive 잔여물 |

## 정리 방법 분류

| 분류 | 설명 | 자동 실행? |
|------|------|-----------|
| `auto-safe` | 데이터 손실 없이 아카이브 가능. 사용자에게 일괄 확인 후 실행. | 예 (AskUserQuestion 일괄 승인 후) |
| `needs-confirmation` | 개별 판단 필요. keep/archive/delete 중 선택. | 예 (항목별 AskUserQuestion) |
| `manual` | 코드나 문서 내용 수정 필요. 보고서에만 기록. | 아니오 |

---

## 1. AGENTS.md 포인터 드리프트

### 정의
AGENTS.md 가 가리키는 파일이 실제로 존재하지 않거나 경로가 바뀐 상태.

### 탐지 방법
1. AGENTS.md 에서 모든 `→ 경로` 포인터와 마크다운 링크 `[...](경로)` 추출
2. 각 경로에 대해 파일 존재 여부 확인
3. 경로가 상대 경로라면 AGENTS.md 기준으로 해석

### 심각도
`critical` — 에이전트가 없는 파일을 찾아 실패한다.

### 정리 방법
`needs-confirmation` — 사람이 결정해야 한다:
- 경로 오타 → 사용자가 수정 (audit 이 자동 수정하지 않음)
- 파일 의도적 삭제 → 해당 포인터를 **주석 처리** (즉시 제거하지 않음)

### 예시
```
AGENTS.md:
  교훈 요약 → docs/references/react-lessons.md    ← 이 파일 없음
```

---

## 2. architecture.md 와 코드 괴리

### 정의
`docs/architecture.md` 에 정의된 레이어 규칙이 실제 import 그래프에서 위반되거나, 코드에는 있는 레이어가 문서에 없는 상태.

### 탐지 방법
1. architecture.md 의 "## 레이어 구조" 섹션 파싱 → 레이어 목록과 허용 import 관계 추출
2. `scripts/check-layer-import.js` 실행 (존재하는 경우) → 위반 보고
3. `src/` 스캔 → architecture.md 에 없는 디렉터리 (잠재적 신규 레이어) 탐지

### 심각도
- 위반 존재: `major` — 에이전트가 문서를 따르면 코드와 충돌
- 문서에 없는 신규 레이어: `major`

### 정리 방법
`manual` — 양방향 수정 판단 필요:
- 문서가 낡음 → `architecture.md` 갱신
- 코드가 위반 → 코드 수정
- audit 은 판단하지 않고 두 가능성을 모두 보고서에 제시

---

## 3. ADR 정합성

### 정의
- `docs/adr/README.md` 인덱스와 실제 파일 목록 불일치
- 번호 결번 (예: 0001, 0003 만 있고 0002 없음)
- 번호 중복 (예: 두 파일이 모두 0002)
- `Superseded by [ADR-NNNN]` 링크가 존재하지 않는 ADR 을 가리킴
- `Proposed` 상태로 30일 이상 방치

### 탐지 방법
1. `docs/adr/` 스캔 → `NNNN-*.md` 파일 목록 수집
2. 각 파일의 상단 "## 상태" 섹션에서 상태/결정일 파싱
3. 번호 중복/결번 검사
4. README.md 테이블과 실제 파일 목록 diff
5. 각 ADR 의 Superseded 링크 유효성 검사
6. Proposed 상태 + 결정일 + 현재 날짜 비교

### 심각도
- 번호 중복: `critical` (파이프라인에서 ADR 발행 시 충돌)
- 번호 결번: `minor` (의도적 skip 일 수 있음)
- 인덱스-실제 불일치: `major`
- 깨진 Superseded 링크: `major`
- Proposed 30일 초과: `minor`

### 정리 방법
- **README.md 인덱스 재생성**: `auto-safe` (실제 파일 기준으로 테이블 다시 빌드)
- 번호 중복: `manual` (사람이 번호 재할당 결정)
- 깨진 Superseded 링크: `manual`
- Proposed 장기 방치: 보고서에 "결정 필요" 로 기록, `manual`

---

## 4. 완료 Phase 잔여 파일

### 정의
`_workspace/phase-N-*.md` 중 이미 완료된 Phase 의 수정 루프 산출물:
- `phase-N-fix-directive-M.md`
- `phase-N-self-review-retry-M.md`
- `phase-N-eval-retry-M.md`

**유지 대상 (이력)**: `phase-N-contract.md`, `phase-N-eval.md`, `phase-N-completion.md`, `phase-N-self-review.md`, `phase-N-reference-analysis.md`

### 탐지 방법
1. `_workspace/current-phase.md` 에서 현재 Phase 번호 파싱
2. `_workspace/phase-*.md` 중 현재 Phase 번호보다 작은 N 의 파일 수집
3. 이 중 파일명에 `fix-directive`, `self-review-retry`, `eval-retry` 포함 파일을 잔여물로 분류

### 심각도
`minor`

### 정리 방법
`auto-safe` — `_archive/YYYY-MM-DD/_workspace/phase-N/` 로 이동

### 예시
```
current-phase.md → Phase: 3

_workspace/:
  phase-0-contract.md              ← 유지 (이력)
  phase-0-completion.md            ← 유지 (이력)
  phase-0-fix-directive-1.md       ← 아카이브 대상
  phase-0-eval-retry-1.md          ← 아카이브 대상
  phase-1-*.md ...                 ← 동일 규칙 적용
  phase-3-contract.md              ← 활성 Phase. 건드리지 않음
```

---

## 5. 고아 레퍼런스

### 정의
`docs/references/*.md` 중 AGENTS.md, `docs/phases/*`, `docs/adr/*`, 다른 `docs/references/*`, `_workspace/prompts/*` 어디서도 링크되지 않는 파일.

### 탐지 방법
1. `docs/references/` 스캔 → 파일 목록 수집
2. 각 파일 경로 문자열을 프로젝트 전체에서 grep
3. 참조가 0건인 파일을 고아로 분류

### 심각도
`minor` — 즉각적 위험 없음. 노이즈 증가.

### 정리 방법
`needs-confirmation` — 사람이 결정:
- 정말 안 쓰는 내용 → archive
- 미래 참조용 → keep
- 다른 문서와 병합 필요 → manual

### 예외 (정리 대상에서 제외)
- `docs/references/failure-lessons.md` — setup 스킬이 초기 파일로 생성. 비어있어도 유지

---

## 6. 중복 레퍼런스

### 정의
`docs/references/` 내 여러 파일이 동일한 주제를 분산해서 다루는 상태.

### 탐지 방법
1. 각 파일의 상단 섹션 제목 수집 (`# `, `## ` 로 시작하는 줄)
2. 유사한 제목/키워드를 가진 파일 쌍 탐지
3. 내용 유사도 판단은 사람 몫 — audit 은 제목 기반 후보만 제시

### 심각도
`minor`

### 정리 방법
`manual` — 병합 판단 필요. audit 은 후보만 제시하고 실행하지 않는다.

---

## 7. quality/ 정합성

### 정의
- `docs/quality/scores.json` 의 `phases` 키와 `docs/phases/` 실제 파일 목록 불일치
- `quality-log.md` 최상단 항목 날짜와 `scores.json` 의 `lastUpdated` 불일치
- `scores.json` 의 `currentPhase` 와 `_workspace/current-phase.md` 불일치

### 탐지 방법
1. `scores.json` 파싱 → `phases` 키 목록, `lastUpdated`, `currentPhase` 추출
2. `docs/phases/` 스캔 → 실제 Phase 스펙 파일 목록
3. `quality-log.md` 최상단 항목에서 날짜 파싱
4. `_workspace/current-phase.md` 에서 Phase 번호 파싱
5. 각각 비교

### 심각도
- 파일 목록 불일치: `major`
- 날짜 불일치: `minor`
- currentPhase 불일치: `major`

### 정리 방법
- scores.json 에 누락된 Phase 를 `pending` 상태로 추가: `auto-safe`
- 날짜 싱크 (`lastUpdated` 를 `quality-log.md` 최신 항목 날짜로): `auto-safe`
- currentPhase 불일치: `manual` (어느 쪽이 진실인지 사람 판단)

---

## 8. 쓰이지 않는 스크립트/Hook

### 정의
`scripts/` 디렉터리 내 파일 중 `.claude/settings.local.json` 의 Hook, `package.json` 의 scripts, AGENTS.md 중 어디서도 참조되지 않는 파일.

### 탐지 방법
1. `scripts/*` 스캔 → 파일 목록
2. 각 파일명/경로를 `.claude/settings.local.json`, `package.json`, AGENTS.md, `_workspace/prompts/*` 에서 grep
3. 참조 0건 파일을 분류

### 심각도
`minor`

### 정리 방법
`needs-confirmation` — 수동 실행 전용일 수도 있음:
- 사용자에게 "수동 실행용인가" 확인 → keep / archive 선택
