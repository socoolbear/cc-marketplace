# Harness Contracts — 공유 규약

`setup`, `maintain`, `reflect` 세 **모드**가 공통으로 따르는 규약.
사용자는 스킬 하나만 호출하고, 라우터 ([`SKILL.md`](SKILL.md)) 가 상태를 감지해 [`modes/`](modes/) 로 분기한다.

> 정의하는 것: 설계 원칙, 대상 프로젝트 레이아웃, `.harness.json` 스키마, 보호 규칙, 정답 출처.
> 정의하지 않는 것: 라우팅 (라우터), 각 모드의 행동 (각 mode 파일), 문서 골격 ([`references/document-formats.md`](references/document-formats.md)).

---

## 1. 설계 원칙

1. **재도출 가능하면 문서화하지 않는다** — 디렉토리 구조·의존성 목록·아키텍처 개요 서술 금지 (코드가 정답). 문서에 남는 것은 **함정·이유·기본값과 다른 관례·이력·용어**뿐.
2. **한 줄 테스트** — 모든 줄에 대해 "이 줄을 지우면 에이전트가 실수하는가?" 를 묻는다. 아니라면 지운다.
3. **갱신 주체는 작업 에이전트 + 사람** — 불변 조건을 바꾸는 변경은 같은 커밋에서 ARCHITECTURE.md 갱신 + ADR.md append. 하네스 모드는 유지의 주체가 아니라 **안전망** (maintain 이 낡음을 보고).
4. **강제가 필요한 규칙은 문서가 아니라 hook/스크립트** — 문서는 advisory.
5. **상태는 기록하지 않고 감지한다** — 파일시스템·git 에서 재도출 가능한 상태 (enforcement 활성 여부, 셋업 일자 등) 를 별도 기록하지 않는다.
6. **일회성 계획 문서는 하네스 소관이 아니다** — 스펙·플랜·진행 상태는 내장 플랜 모드·태스크·git 소관. 하네스는 영속 지식만 관리한다.

## 2. 모드 역할 분리

| 모드 | 방향 | 빈도 |
|------|------|------|
| `setup` | 0 → 1 구축 | 1회성 |
| `maintain` | 플러그인 버전 동기화 + 문서 낡음 점검 (안전망) | `/plugin update` 후, 또는 필요 시 |
| `reflect` | 세션 학습 → 문서 승격 | 학습 누적 시 |

## 3. 대상 프로젝트 레이아웃

```
{앵커}/                            # 앵커 = setup 을 실행한 디렉토리 (모노레포 서브패키지 가능)
  AGENTS.md                        # 지도 ≤40줄 (document-formats 1절)
  CLAUDE.md                        # "@AGENTS.md" 브리지 (부재 시 생성)
  harness/
    .harness.json                  # 상태 마커 (4절)
    ARCHITECTURE.md                # 아키텍처 불변 조건 (규칙 + 이유)
    ADR.md                         # 결정 이력 (append-only 단일 파일)
    GLOSSARY.md                    # 용어집 (함정 표기 목록)
    LESSONS.md                     # 팀 공유 교훈 (2회 규칙)
  scripts/check-layer-import.js    # (선택) enforcement — 레이어 구조 있는 프로젝트만
  scripts/layer-check-hook.js      # (선택) enforcement — PostToolUse 어댑터
  .claude/settings.local.json      # (선택) enforcement hook 등록
```

- enforcement 활성 여부는 `scripts/check-layer-import.js` + settings hook 존재로 **감지**한다 (마커에 기록하지 않음).
- **머신 로컬 (gitignore 대상)**: `.prompts/`, `.claude/settings.local.json`, `.claude/worktrees/` — setup Phase 2-7 이 git 저장소에서 `.gitignore` 등재를 보장한다. 기존 항목은 수정하지 않고 누락분만 append.
- **worktree 규약**: git worktree 는 `.claude/worktrees/` 하위에 생성한다 (Claude Code 내장 worktree 와 동일 경로). 루트에서의 전역 탐색·검사는 이 디렉토리를 제외한다 — worktree 를 **실제로 쓰는 프로젝트에만** 적용되며, 그 경우 setup Phase 2-7·2-8 과 AGENTS.md 경계 항목이 함께 보장한다.

## 4. `harness/.harness.json` 스키마

```json
{ "version": "<plugin.json 의 version>", "lastReflect": "YYYY-MM-DD" }
```

| 필드 | 의미 | 누가 쓰나 |
|------|------|-----------|
| `version` | `plugin.json` 의 `version` 과 비교 (라우터 분기 기준) | setup 생성, maintain 갱신 |
| `lastReflect` | 마지막 reflect 실행일 (부재 = 미실행) | reflect 갱신 |

재도출 가능한 값 (setupDate → git log, features → 파일 존재) 은 기록하지 않는다 (원칙 5).

## 5. 보호 규칙

세 문장이 전부다:

1. **어떤 모드도 문서의 본문 데이터를 수정·삭제하지 않는다** — ADR 항목, GLOSSARY 표 행, LESSONS 항목, 사용자가 직접 추가한 섹션. 모드가 만지는 것은 골격 (섹션 구조) 과 마커뿐이다.
2. **모드의 쓰기는 항상 사용자 승인 후 실행한다** (골격 append 포함). setup 만 최초 작성이 기본 동작이고, 그조차 구축 범위를 먼저 확인받는다.
3. **`docs/legacy-*/` 와 기존 `_archive/` 는 동결한다** — 어떤 모드도 읽지도 고치지도 않는다 (스캔 제외).

예외적으로 모드별 권한이 갈리는 것만:

| 대상 | 예외 |
|------|------|
| `harness/ARCHITECTURE.md`, `harness/ADR.md` | reflect 도 **직접 쓰지 않는다** — manual 권고만 (작업 에이전트·사람이 같은 커밋 원칙으로 반영) |
| `harness/GLOSSARY.md` | 행 **삭제는 사람만**. reflect·사람은 append 가능 |
| `harness/LESSONS.md` | reflect 의 append 는 **2회 규칙** 통과 시만 (document-formats 6절) |
| `CLAUDE.md` | setup 은 부재 시 브리지 생성만. 존재하면 어떤 모드도 수정하지 않는다 |
| `scripts/` + settings hook | maintain 은 **실행만** 하고 수정하지 않는다 |
| `harness/.harness.json` | setup 생성 / maintain 이 `version` / reflect 가 `lastReflect` — 그 외 필드는 만들지 않는다 |

## 6. 정답 출처

| 정보 | 단일 진실 |
|------|-----------|
| 문서 5종 + 브리지 골격, 등재·판단 기준 | [`references/document-formats.md`](references/document-formats.md) |
| 레이어 검사기 설계 요건·hook 프로토콜·CI | [`references/mechanical-enforcement.md`](references/mechanical-enforcement.md) |
| 보호 규칙, 스키마, 레이아웃, 원칙 | 본 파일 |
| 라우팅 (감지·분기) | [`SKILL.md`](SKILL.md) |
| 각 모드의 행동 (Phase 흐름, 질문 패턴) | 각 [`modes/`](modes/)`*.md` |
