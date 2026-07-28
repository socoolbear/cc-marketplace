# Harness — Reflect 모드 (세션 학습 → 문서 승격)

세션 중 누적된 학습을 팀 공유 아티팩트 (AGENTS.md, GLOSSARY.md, LESSONS.md) 로 승격한다.
개인·머신 로컬 학습은 auto-memory 가 담당하고, 본 모드는 그중 **repo 에 남길 가치가 있는 것**만 골라 올린다.

> **원칙: 자동 쓰기 없음.** 모든 승격은 분류 → **사용자 승인** → append.
>
> **사전 지식**: [`../CONTRACTS.md`](../CONTRACTS.md), [`../references/document-formats.md`](../references/document-formats.md) (등재 기준 5~6절).

## 워크플로우

### Phase 0: 사전 확인

- `harness/.harness.json` 존재 확인 (부재 시 종료 + setup 안내)
- 기준 시각: `.harness.json` 의 `lastReflect` (부재 = 전체 대상)

**학습 소스 — auto-memory 디렉토리**

```
~/.claude/projects/<슬러그>/memory/
```

슬러그는 **앵커의 절대 경로에서 `/` 를 `-` 로 치환**한 것이다 (예: `/Users/me/code/app` → `-Users-me-code-app`). 이 디렉토리에는:

| 파일 | 내용 |
|------|------|
| `MEMORY.md` | 한 줄 포인터 인덱스 (`- [제목](파일.md) — 훅`) |
| `<슬러그>.md` | 개별 메모리. frontmatter 에 `name` / `description` / `metadata.type` |

**`metadata.type` 이 분류 기준이다** — 파일명이 아니다. 대상은 `feedback` (작업 방식에 대한 지침) 과 `project` (진행 중인 작업의 제약) 이며, `user` 와 `reference` 는 개인·외부 자원이므로 제외한다.

수집 대상 = `MEMORY.md` 가 가리키는 파일 중 위 type 에 해당하고 **mtime 이 `lastReflect` 이후**인 것. 디렉토리가 없거나 대상 0건이면 종료한다.

### Phase 1: 수집 + 중복 제거 (읽기 전용)

1. 대상 파일을 `{ source, signal, evidence }` 로 정규화
2. 이미 반영된 것 제거: AGENTS.md / `harness/*.md` 를 rg 로 확인해 매칭 시 drop
3. 잔존 0건이면 `lastReflect` 만 갱신 후 종료

> auto-memory 파일에 처리 표식을 쓰지 않는다 — 쓰는 순간 mtime 이 갱신되어 다음 실행에서 다시 신규로 잡힌다. 중복 방지는 `lastReflect` 가 담당한다.

### Phase 2: 분류

| 신호 패턴 | 목적지 | 처리 |
|----------|--------|------|
| 코딩 규칙·경계 ("항상 X", "절대 Y 금지") | AGENTS.md 관리 섹션 (경계 등) | append (승인 후) |
| 용어 정의·표기 교정 ("X 는 Y 라고 부른다") | `harness/GLOSSARY.md` 용어 표 | 행 append (승인 후, 등재 기준 → document-formats 5절) |
| 반복 실수의 교훈 | `harness/LESSONS.md` | **2회 규칙** — 첫 발생은 defer, 두 번째 발생만 등재 (document-formats 6절) |
| 자동 행동 요청 ("X 때마다 Y") / 반복 승인 패턴 | settings hooks / permissions | delegate — `/update-config` · `/fewer-permission-prompts` 안내만 |
| 도메인 특화 반복 조사 | 새 sub-agent | scaffold (`.claude/agents/<name>.md` TODO 헤더만, 승인 후) |
| 아키텍처 불변 조건·전략적 결정 | ARCHITECTURE.md / ADR.md | **manual 권고만** (작업 에이전트·사람이 같은 커밋 원칙으로 반영) |
| 분류 모호 | — | defer (다음 reflect 재평가) |

### Phase 3: 승인 + 적용

1. 분류 결과를 채팅으로 보고 (보고서 파일 없음)
2. AskUserQuestion: append 는 일괄/개별, scaffold 는 개별, delegate 는 통지만
3. 승인된 항목만 append (기존 행·항목 수정 X)
4. `.harness.json` 의 `lastReflect` 갱신

## 적용하지 않는 것

- settings hooks/permissions 직접 수정 (delegate), 새 skill 자동 생성 (`skill-creator` 안내만)
- ARCHITECTURE.md·ADR.md 직접 수정 (manual 권고만 — CONTRACTS 5절)
- sub-agent 본문 자동 작성 (scaffold 만)
