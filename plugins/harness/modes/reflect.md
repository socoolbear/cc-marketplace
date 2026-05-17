# Harness — Reflect 모드 (세션 학습 → 영속 아티팩트 승격)

세션 중 누적된 사용자 피드백·반복 지시·교정 사항을 프로젝트의 영속 아티팩트
(AGENTS.md, `docs/conventions/`, settings hooks/permissions, sub-agents, skill 후보)
로 승격시키는 워크플로우.

> **진입점**: 사용자는 `/harness:run` 만 호출한다. 라우터 (`../skills/run/SKILL.md`) 가 학습 후보 누적을 감지하여 옵션으로 노출하고, 사용자가 선택 시 본 모드로 분기한다.
>
> **사전 지식**: 본 모드는 setup/audit/update 와 [`../CONTRACTS.md`](../CONTRACTS.md) 의 공유 규약 (디렉토리 레이아웃, 보호 파일 매트릭스, ADR 불변 조건) 을 따른다. 본 파일은 **승격 행동** 만 정의한다.

**다른 모드와의 관계:**
- `setup` = 0 → 1 인프라 구축
- `update` = 스킬 버전 차이 동기화
- `audit` = 쓸데없는 것 제거 (드리프트 정리)
- `reflect` = **있어야 할 것 추가** (세션 학습 → 아티팩트 승격)

reflect 는 audit/update 와 **직교**한다 — 같은 날 모두 돌아도 산출물 영역이 겹치지 않는다.

## 파괴적 작업 원칙

**핵심: 자동 쓰기 없음. 모든 승격은 분류 → 사용자 확인 → 직접 append 또는 외부 스킬 위임.**

| 작업 | 대상 | 승인 조건 |
|------|------|-----------|
| `direct-append` | `AGENTS.md` 관리 섹션 / `docs/conventions/*.md` / `docs/references/*.md` 본문 추가 | 사용자 명시 승인 (개별 또는 일괄) |
| `delegate` | `.claude/settings.local.json` hooks/permissions / 새 skill / sub-agent | 적절한 외부 스킬 호출 안내 (자동 호출 X) |
| `scaffold` | `.claude/agents/<name>.md` 빈 파일 (sub-agent 후보) | 사용자 승인 후 빈 파일 + TODO 헤더만 생성 |
| `defer` | 분류 모호 / 노이즈 | 보고서에만 기록, 다음 reflect 에서 재평가 |

## 워크플로우

### Phase 0: 사전 확인

**0-1. 하네스 셋업 여부 (필수):**

audit 와 동일한 핵심 4파일 (`AGENTS.md`, `docs/architecture.md`, `_workspace/current-phase.md`, `docs/quality/scores.json`) 존재 확인. 하나라도 부재 시 "하네스가 셋업되지 않은 프로젝트입니다. `/harness:run` 호출 시 라우터가 setup 모드로 분기했어야 합니다" 안내 후 종료.

**0-2. 학습 소스 위치:**

본 모드가 읽는 학습 소스 (둘 다 선택, 하나도 없으면 Phase 1 에서 종료):

| 소스 | 경로 | 포맷 |
|------|------|------|
| auto-memory feedback | `${CLAUDE_PROJECT_DIR}/memory/feedback_*.md` (또는 시스템에 따라 `~/.claude/projects/<slug>/memory/`) | frontmatter (`type: feedback`) + 본문 |
| 인라인 inbox (선택) | `_workspace/inbox.md` | 줄 단위, `- REMEMBER: ...` 또는 `- 규칙: ...` 접두사 |

inbox 가 없으면 그대로 skip. auto-memory 경로는 라우터가 Phase 0-4 에서 결정한 동일 경로를 그대로 사용한다.

**0-3. 마지막 reflect 시각:**

`_workspace/.last-reflect` 한 줄 ISO 8601 timestamp. 부재 시 epoch 0 (= 모든 소스 후보) 으로 간주.

### Phase 1: 학습 수집 (Collector)

**역할**: 읽기 전용. 어떤 파일도 수정하지 않는다.

1. feedback 메모리 중 mtime > `.last-reflect` 인 파일만 수집
2. `_workspace/inbox.md` 존재 시 줄 단위 파싱 (마커 접두사 줄만)
3. 각 학습을 정규화한 객체로 모음:

```
{
  source:     "feedback_testing.md" | "inbox.md:42",
  signal:     "한 줄 요약",
  evidence:   "원문 발췌 또는 reproducer",
  confidence: high | medium | low
}
```

수집 0건이면 "승격할 학습 없음" 안내 후 `_workspace/.last-reflect` 만 갱신하고 종료한다 (Phase 7 단축).

### Phase 2: 중복 제거 (Deduper)

각 후보가 이미 다음 위치에 반영되어 있는지 빠르게 확인 (rg 그렙으로 핵심 키워드):

- `AGENTS.md`
- `docs/conventions/*.md`
- `docs/references/*.md`
- `.claude/agents/*.md` (sub-agents)
- `.claude/settings.local.json` (hooks, permissions)

매칭 시 후보에서 drop + 메모리 파일 frontmatter 에 `applied: YYYY-MM-DD` 추가 (재발견 방지). 보고서에는 "중복 (이미 반영됨)" 카운트로만 기록.

### Phase 3: 분류 (Classifier)

각 잔존 후보를 다음 목적지 중 하나로 분류한다. 신호 패턴 매칭 우선, 모호하면 confidence=low + Phase 5 에서 사용자가 직접 지정.

| 신호 패턴 | 목적지 | 처리 유형 |
|----------|--------|-----------|
| "항상 X" / "절대 Y 금지" / 코딩 규칙 | `AGENTS.md` 관리 섹션 또는 `docs/conventions/<topic>.md` | direct-append |
| 명령 도구 우선순위 ("X 대신 Y 사용") | `docs/conventions/cli-tooling.md` (agent-tooling feature 활성 시) | direct-append |
| "X 때마다 자동으로 Y" (자동 행동 요청) | `.claude/settings.local.json` hooks | delegate → `update-config` 스킬 |
| 반복 승인된 Bash/MCP 패턴 | `.claude/settings.local.json` permissions.allow | delegate → `fewer-permission-prompts` 스킬 |
| 도메인 특화 반복 조사 (예: PR 리뷰, 로그 분석) | 새 sub-agent | scaffold (`.claude/agents/<name>.md` + TODO) |
| 재사용 가능한 다단계 워크플로우 | 새 skill 후보 | delegate → `skill-creator` 안내만 |
| 프로젝트 한정 사실/제약 (불변 조건) | 새 ADR 또는 `docs/architecture.md` | manual 권고 (직접 쓰기 X — § 6 ADR 불변 조건 + § 7 보호 매트릭스 준수) |

### Phase 4: 보고서 작성 (Reporter)

`_workspace/learnings/learn-YYYY-MM-DD.md` 작성:

```markdown
# Reflect Report — YYYY-MM-DD

## 환경
- 하네스 버전: v1.x.x
- 마지막 reflect: YYYY-MM-DD (또는 "최초 실행")
- 수집 소스: feedback N건, inbox M건

## 요약
- direct-append 후보: N건
- delegate 후보 (hooks): N건
- delegate 후보 (permissions): N건
- scaffold 후보 (sub-agent): N건
- skill 제안: N건
- manual 권고 (architecture/ADR): N건
- 분류 모호 (사용자 판단): N건
- 중복 (이미 반영됨, drop): N건

## 후보별 상세

### 1. direct-append → AGENTS.md (`## 언어` 섹션)
- [high] "Git 커밋 메시지 한국어로 작성"
  - source: feedback_commit-style.md
  - evidence: "(원문 발췌 1-2줄)"

### 2. delegate → update-config (hooks)
- [medium] "테스트 실패 시 자동으로 마지막 로그 100줄 출력"
  - source: feedback_test-workflow.md
  - 안내: `/update-config` 스킬을 호출하여 Stop hook 추가

...
```

### Phase 5: 게이팅 (대화형)

보고서 요약을 보여준 뒤 **AskUserQuestion** 으로 처리 의사를 수집한다.

AskUserQuestion 묶음/개별 패턴 → `../references/cleanup-rules.md` 섹션 3 차용 (audit 와 동일).

**질문 1 — direct-append 일괄**:
> "AGENTS.md / docs/conventions/ 본문에 추가할 N개 항목을 적용할까요?"
> - 전체 적용 / 개별 검토 / 건너뛰기

**질문 2 — scaffold 후보 (sub-agent)**:
> 각 후보에 대해: 스캐폴드 생성 / 다음 reflect 로 미루기 / 영영 무시

**질문 3 — delegate 항목 묶음 통지**:
> "별도 스킬 호출이 필요한 N개 항목은 보고서 마지막에 안내로만 남깁니다."
> (선택지 없음 — 단순 통지)

**질문 4 — 분류 모호 항목 개별** (있을 때만):
> 각 항목에 대해 목적지 직접 선택:
> - AGENTS.md / `docs/conventions/<topic>.md` / sub-agent scaffold / 다음 reflect / 영영 무시

5개 이상은 2-3개씩 묶어 여러 번 질문한다.

### Phase 6: 적용 (Applier)

승인된 항목만 처리한다.

**direct-append**:
- `AGENTS.md`: 관리 섹션 (예: `## 언어`, `## 코딩 스타일`, `## 외부 서비스`) 끝에 항목 추가. CONTRACTS.md § 7 "AGENTS.md 본문 — 관리 섹션만 교체" 규칙 준수, 사용자 작성 섹션 (예: `## 프로젝트`) 건드림 금지.
- `docs/conventions/<topic>.md`: 없으면 생성 (`# {topic}\n\n` 헤더 + 첫 항목), 있으면 해당 섹션 append.

**scaffold (sub-agent)**:
- `.claude/agents/<name>.md` 빈 파일 생성. 본문은 다음 골격만:
  ```markdown
  ---
  name: <name>
  description: TODO — reflect 모드가 제안한 sub-agent. 본문을 채워주세요.
  tools: [Read, Bash, ...]  # TODO
  ---

  # <Name> Sub-agent

  > reflect 가 생성한 스캐폴드. 다음 신호에서 추출됨:
  > - source: {source}
  > - signal: {signal}

  TODO: 본 sub-agent 가 수행할 작업을 기술하세요.
  ```
- 본문은 사용자가 채운다. reflect 는 본문을 추측해서 채우지 않는다.

**delegate**: 본 모드는 쓰기 작업을 수행하지 않고, 보고서 마지막에 안내 섹션을 추가한다:

```markdown
## 후속 액션 (외부 스킬 위임 필요)

- hooks N건 → `/update-config` 호출
- permissions N건 → `/fewer-permission-prompts` 호출
- skill 제안 N건 → `skill-creator` 호출 검토
```

**manual (architecture/ADR)**: 보고서에 권고만 기록. 실제 ADR 발행은 Evaluator (4단계 파이프라인) 의 권한 (CONTRACTS § 6).

### Phase 7: 마무리

1. `_workspace/.last-reflect` 를 현재 ISO 8601 timestamp 로 갱신
2. 적용된 feedback 메모리 frontmatter 에 `applied: YYYY-MM-DD` 메타 추가 (없는 파일에만 — 중복 갱신 X)
3. `docs/quality/reflect-log.md` 에 항목 추가:

```markdown
## YYYY-MM-DD
- 실행 시각: HH:MM KST
- 보고서: `_workspace/learnings/learn-YYYY-MM-DD.md`
- 수집: N건 (feedback X, inbox Y)
- 적용: direct-append A건, scaffold B건
- delegate 안내: hooks C건, permissions D건, skill E건
- defer (다음 reflect): F건
- 다음 reflect 권장: 학습 누적 3건 이상 시
```

`reflect-log.md` 가 없으면 생성한다.

## 산출물

- [ ] `_workspace/learnings/learn-YYYY-MM-DD.md` — 보고서 (매 실행 시 생성)
- [ ] `_workspace/.last-reflect` — 마지막 실행 timestamp (갱신)
- [ ] `docs/quality/reflect-log.md` — 시계열 로그 (항목 추가)
- [ ] `AGENTS.md` / `docs/conventions/*.md` 본문 (승인된 direct-append)
- [ ] `.claude/agents/<name>.md` scaffold (승인된 sub-agent 후보)

## 적용하지 않는 것

- `.claude/settings.local.json` 의 hooks / permissions 직접 수정 → `update-config` / `fewer-permission-prompts` 스킬에 위임
- 새 skill 자동 생성 → `skill-creator` 안내만
- ADR 본문 수정 / `docs/architecture.md` 수정 → CONTRACTS § 6, § 7 보호 매트릭스 준수 (별도 결정 절차 필요)
- 활성 Phase 의 산출물 변경 → 진행 중 작업 보호
- sub-agent 본문 자동 작성 → scaffold 만 생성, 본문은 사용자가 채움

## 참고

- **공유 규약**: `../CONTRACTS.md`
- 정리 규칙 (AskUserQuestion 묶음/개별 패턴): `../references/cleanup-rules.md` 섹션 3
- setup 모드: `./setup.md`
- update 모드: `./update.md`
- audit 모드: `./audit.md`
- 외부 위임 대상 스킬:
  - `update-config` — settings.local.json hooks / permissions
  - `fewer-permission-prompts` — 반복 permission 일괄 추가
  - `claude-md-management:revise-claude-md` — CLAUDE.md 갱신 (프로젝트가 AGENTS.md 대신 CLAUDE.md 를 쓸 때)
  - `skill-creator` — 새 skill 발굴 / 생성
