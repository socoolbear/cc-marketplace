---
name: harness
description: "프로젝트에 에이전트용 지속 지식 문서 (AGENTS.md 지도 + harness/ 의 ARCHITECTURE·ADR·GLOSSARY·LESSONS) 와 선택적 레이어 검사 강제를 구축하고 유지한다. 상태를 감지해 setup (최초 구축) 또는 maintain (낡음 점검 + 세션 학습 승격) 으로 분기한다. 하네스 셋업·점검·업데이트, 학습 승격 (reflect), 용어집, ADR, 아키텍처 불변 조건, 레이어 경계 강제, AGENTS.md 정리 요청, 또는 세션 시작 시 '하네스 자가 점검 신호' 를 받고 사용자가 점검을 수락했을 때 사용한다."
---

# Harness

에이전트가 매 세션 다시 알아내지 않도록 **코드에서 재도출할 수 없는 지식**(함정·이유·관례·이력·용어)을 repo 문서로 유지한다. 이 파일은 규약과 분기를 정하고, 모드별 행동은 `modes/` 가 정한다.

| 파일 | 역할 |
|---|---|
| [`modes/setup.md`](modes/setup.md) | 최초 구축 |
| [`modes/maintain.md`](modes/maintain.md) | 낡음 점검 + 골격 갱신 + 학습 승격 |
| [`references/document-formats.md`](references/document-formats.md) | 산출 문서 골격·등재 기준 (쓰는 시점에 읽는다) |
| [`references/enforcement.md`](references/enforcement.md) | 레이어 검사기·훅·CI 설계 요건 (강제를 다룰 때만 읽는다) |

## 원칙

1. **재도출 가능하면 쓰지 않는다** — 디렉토리 구조·의존성 목록·현황 서술은 코드가 정답이다.
2. **한 줄 테스트** — "이 줄을 지우면 에이전트가 실수하는가?" 아니면 지운다.
3. **유지 주체는 작업 에이전트와 사람이다** — 불변 조건을 바꾸는 커밋이 같은 커밋에서 문서를 고친다. 하네스는 안전망이다.
4. **강제가 필요한 규칙은 문서가 아니라 훅·CI 로** — 문서는 권고다.
5. **repo 에는 재도출 가능한 상태를 기록하지 않는다** — 강제 활성 여부, 셋업 일자 등은 감지한다.
6. **일회성 계획·진행 상태는 소관이 아니다** — 플랜 모드·태스크·git 이 맡는다.

## 대상 레이아웃

```
{앵커}/                     # setup 을 실행한 디렉토리 (모노레포 서브패키지 가능)
  AGENTS.md                 # 지도 ≤40줄
  CLAUDE.md                 # "@AGENTS.md" 연결 파일 (부재 시만 생성)
  harness/
    .harness.json           # 마커
    ARCHITECTURE.md  ADR.md  GLOSSARY.md  LESSONS.md
  .claude/settings.json     # (선택) 레이어 검사 훅 — 팀 공유
  scripts/…                 # (선택) 검사기 + 훅 어댑터
```

강제 활성 = settings 에 레이어 검사 훅 항목이 있음 (검사기 파일명은 도구 체인마다 다르므로 기준이 아니다).

## 마커 `harness/.harness.json`

```json
{ "version": "<설치 당시 plugin.json version>", "lastReflect": "<ISO 8601 시각>" }
```

- `version` — setup 이 쓰고 maintain 이 골격을 갱신했을 때만 올린다.
- `lastReflect` — 학습 승격을 실행했을 때만 갱신한다. v3 이하는 `YYYY-MM-DD` 였다 — 읽을 때 그날의 끝으로 해석한다.
- 그 외 필드는 만들지 않는다.

**버전 규칙**: 산출 문서 골격 (document-formats) 을 바꾸는 릴리스는 major 를 올린다. 세션 시작 신호는 major 차이만 골격 갱신으로 알린다.

## 보호 규칙 (모든 모드 공통)

- 문서의 **본문 데이터**(ADR 항목, GLOSSARY 행, LESSONS 항목, 사용자가 추가한 섹션) 는 수정·삭제하지 않는다. 모드가 만지는 것은 골격과 마커뿐이다.
- 쓰기는 사용자 승인 후에만 한다. setup 도 구축 범위를 먼저 확인받는다 (사용자가 기본값 진행을 미리 허락했으면 생략).
- `ARCHITECTURE.md`·`ADR.md` 는 모드가 직접 고치지 않는다 — 권고만 하고 작업 에이전트·사람이 반영한다. GLOSSARY 행 삭제는 사람만 한다.
- 기존 `CLAUDE.md` 는 수정하지 않는다. 검사기 스크립트는 실행만 한다.
- `docs/legacy-*/`, `_archive/` 는 읽지도 고치지도 않는다.

## 분기

사용자가 모드를 명시하면 따른다 ("reflect"·"학습 승격" → maintain 의 학습 단계만). 아니면 앵커 (현재 디렉토리) 를 읽기만 하고 판단한다:

| 상태 | 모드 |
|---|---|
| 마커 있음 | maintain — 한 줄 알리고 바로 진단 (진단은 읽기 전용) |
| 마커·AGENTS.md·`harness/` 모두 없음 | setup — 구축 범위를 요약해 확인 후 진행 |
| 일부만 있음 (마커 없이 문서만, 마커만 있고 문서 누락 등) | 상태를 요약하고 사용자에게 모드를 묻는다 |

세션 시작 신호로 들어왔으면 신호에 적힌 항목부터 다룬다.

## 세션 시작 신호

플러그인 `SessionStart` 훅 ([`scripts/harness-signal.mjs`](scripts/harness-signal.mjs)) 이 마커가 있는 프로젝트에서만 결정적 신호를 감지해 모델 컨텍스트에 넣는다: 골격 major 차이, 승격 대기 학습 건수, 깨진 지도 포인터. 같은 신호는 7일에 한 번만 다시 알린다 (상태는 `${CLAUDE_PLUGIN_DATA}` 에만 둔다).

신호를 받으면 **사용자의 요청을 먼저 끝내고** 응답 끝에 한 줄로 점검을 제안한다. 수락 전에는 실행하지 않는다.

한계: 세션을 앵커가 아닌 곳 (예: 모노레포 루트) 에서 열면 신호가 나오지 않는다. memory 위치는 기본 경로만 따른다 (`autoMemoryDirectory` 설정·200자 초과 경로는 미지원).
