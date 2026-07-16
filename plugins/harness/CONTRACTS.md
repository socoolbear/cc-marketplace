# Harness Contracts — 공유 규약 (v2)

`setup`, `update`, `audit`, `reflect` 네 **모드**가 공통으로 따르는 규약.
사용자는 `/harness:run` 단일 진입점만 호출하고, 라우터 ([`skills/run/SKILL.md`](skills/run/SKILL.md)) 가 상태를 감지하여 [`modes/`](modes/) 의 모드로 분기한다.

> 이 파일이 정의하는 것: 설계 원칙, 대상 프로젝트 레이아웃, `.harness.json` 스키마, 보호 규칙, 정답 출처.
> 이 파일이 정의하지 않는 것: 라우팅 (라우터), 각 모드의 행동 (각 mode 파일), 문서 골격 ([`references/document-formats.md`](references/document-formats.md)).

### 플러그인 내부 레이아웃 (참고)

```
plugins/harness/
  .claude-plugin/plugin.json     # 버전 + 메타
  CONTRACTS.md                   # 본 파일 (단일 진실)
  skills/run/SKILL.md            # 사용자 진입점 (라우터)
  modes/{setup,update,audit,reflect}.md
  references/
    document-formats.md          # 대상 문서 5종 표준 골격 (정답)
    mechanical-enforcement.md    # 레이어 검사 스크립트 + hook + CI
    migration-v1-to-v2.md        # v1 → v2 마이그레이션
  scripts/generate-layer-check.js
```

---

## 1. 설계 원칙

1. **재도출 가능하면 문서화하지 않는다** — 디렉토리 구조·의존성 목록·아키텍처 개요 서술 금지 (코드가 정답). 문서에 남는 것은 함정·이유·기본값과 다른 관례·이력·용어뿐.
2. **갱신 주체는 작업 에이전트 + 사람** — 불변 조건을 바꾸는 변경은 같은 커밋에서 ARCHITECTURE.md 갱신 + ADR.md append. 하네스 모드는 유지의 주체가 아니라 **안전망** (audit 이 낡음을 보고).
3. **강제가 필요한 규칙은 문서가 아니라 hook/스크립트** — 문서는 advisory.
4. **상태는 기록하지 않고 감지한다** — 파일시스템·git 에서 재도출 가능한 상태 (enforcement 활성 여부, 셋업 일자 등) 를 별도 기록하지 않는다.
5. **일회성 계획 문서는 하네스 소관이 아니다** — 스펙/플랜/진행 상태는 내장 플랜 모드·태스크·git 소관. 하네스는 영속 지식만 관리한다.

## 2. 모드 역할 분리

| 모드 | 방향 | 라우터 분기 조건 | 빈도 |
|------|------|------------------|------|
| `setup` | 0 → 1 구축 | `harness/.harness.json` 부재 + v1 마커 부재 | 1회성 |
| `update` | 플러그인 버전 차이 동기화 (+ v1→v2 마이그레이션) | 마커 버전 ≠ 플러그인 버전, 또는 v1 마커 감지 | `/plugin update` 후 |
| `audit` | 문서 낡음 점검 (안전망) | 마커 버전 = 플러그인 버전 | 필요 시 |
| `reflect` | 세션 학습 → 문서 승격 | `lastReflect` 이후 신규 학습 소스 존재 시 보조 옵션 | 학습 누적 시 |

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
    inbox.md                       # (선택) 사용자가 채우는 학습 마커 — reflect 가 읽음
  scripts/check-layer-import.js    # (선택) enforcement — 레이어 구조 있는 프로젝트만
  .claude/settings.local.json      # (선택) enforcement hook
```

- 마이그레이션 보관 선택 시에만 `_archive/v1-YYYY-MM-DD/` 가 추가로 존재할 수 있다.
- enforcement 활성 여부는 `scripts/check-layer-import.js` + settings hook 존재로 **감지**한다 (마커에 기록하지 않음).

## 4. `harness/.harness.json` 스키마

```json
{ "version": "2.0.0", "lastReflect": "YYYY-MM-DD" }
```

| 필드 | 의미 | 누가 쓰나 |
|------|------|-----------|
| `version` | `plugin.json` 의 `version` 과 비교 (라우터 분기 기준) | setup 생성, update 갱신 |
| `lastReflect` | 마지막 reflect 실행일 (부재 = 미실행) | reflect 갱신 |

재도출 가능한 값 (setupDate → git log, features → 파일 존재) 은 기록하지 않는다 (원칙 4).

## 5. 보호 규칙

| 파일 | setup | update | audit | reflect | 작업 에이전트/사람 (상시) |
|------|-------|--------|-------|---------|---------------------------|
| `AGENTS.md` | 작성 (최초) | 골격 누락 섹션만 append | 보고만 | 관리 섹션 항목 append (승인 후) | 자유 (사용자 섹션 포함) |
| `CLAUDE.md` | 부재 시 브리지 생성 | 보존 | 보고만 | 보존 | 자유 |
| `harness/ARCHITECTURE.md` | 작성 | 보존 | 보고만 | 보존 (manual 권고만) | 불변 조건 변경 시 같은 커밋 갱신 |
| `harness/ADR.md` | 작성 (회고 항목 포함 가능) | 보존 | 정합성 보고만 | 보존 (manual 권고만) | 항목 append 만 (본문 불변, 상태 줄만 전이) |
| `harness/GLOSSARY.md` | 작성 (초기 ≤10행) | 골격만 보수 | stale 보고만 | 표 행 append (승인 후) | 자유 (행 삭제는 사람만) |
| `harness/LESSONS.md` | 빈 골격 작성 | 골격만 보수 | stale 보고만 | 항목 append (승인 후, 2회 규칙) | 항목 append |
| `harness/.harness.json` | 생성 | `version` 갱신 | 읽기만 | `lastReflect` 갱신 | — |
| `scripts/` + settings hook | 작성 (enforcement 선택 시) | 보존 | 실행만 (수정 X) | 수정 X (delegate) | 자유 |
| `docs/legacy-*/`, 기존 `_archive/` | 보존 | 보존 | 보존 (스캔 제외) | 보존 | — |

공통: **어떤 모드도 문서의 본문 데이터 (ADR 항목, GLOSSARY 표 행, LESSONS 항목) 를 수정·삭제하지 않는다.** 모드의 쓰기는 항상 사용자 승인 후 실행한다 (골격 append 포함).

## 6. 정답 출처 + 변경 시 영향

| 정보 | 단일 진실 |
|------|-----------|
| 문서 5종 + 브리지 골격, 등재·판단 기준 | `references/document-formats.md` |
| 레이어 검사 스크립트·hook·CI 연동 | `references/mechanical-enforcement.md` |
| v1 → v2 마이그레이션 매핑·검증 | `references/migration-v1-to-v2.md` |
| 보호 규칙, 스키마, 레이아웃, 원칙 | 본 파일 |
| 각 모드의 행동 (Phase 흐름, 질문 패턴) | 각 `modes/*.md` |

**변경 시 규칙**: 대상 프로젝트 산출물에 영향을 주는 변경 (본 파일, document-formats, mechanical-enforcement) 은 `plugins/harness/.claude-plugin/plugin.json` 과 루트 `.claude-plugin/marketplace.json` 의 harness `version` 을 **동시에 minor 이상 bump** 한다 (두 파일 버전 일치 필수).
