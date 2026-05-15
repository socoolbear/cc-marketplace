---
name: harness
description: "하네스 엔지니어링 인프라의 모든 라이프사이클을 단일 진입점으로 처리하는 스킬. 프로젝트 상태를 자동 감지하여 (1) 하네스가 없으면 setup 모드로 0→1 구축, (2) 셋업되어 있고 스킬 버전이 다르면 update 모드로 동기화, (3) 셋업되어 있고 버전이 같으면 audit 모드로 내부 드리프트 정리. 감지 결과는 AskUserQuestion 으로 사용자에게 확인받고, 사용자가 다른 모드를 강제로 선택할 수도 있다. 트리거 키워드: '하네스', '하네스 실행', '하네스 적용', '하네스 구축', '하네스 인프라', '하네스 셋업', '하네스 엔지니어링', '하네스 업데이트', '하네스 최신화', '하네스 동기화', '하네스 감사', '하네스 정리', '하네스 진단', '하네스 유지보수', '하네스 마이그레이션', 'harness setup', 'harness update', 'harness audit', '4단계 파이프라인', '레이어 경계', '레이어 강제', '품질 추적', '품질 점수', 'ADR 이력', '아키텍처 결정', '문서 드리프트', '가비지 컬렉션', '스킬 버전 동기화', '버전 마이그레이션', 'agent-tooling', 'CLI 도구 규약', 'OpenAI/Anthropic 하네스 엔지니어링' 요청 시 사용. 사용자가 setup/update/audit 중 무엇이 필요한지 모를 때도 이 스킬 하나로 시작. 라우터가 알아서 적절한 모드로 분기."
---

# Harness — 단일 진입점 라우터

`/harness:run` 으로 호출되는 유일한 사용자 진입점.
프로젝트 상태를 감지하여 [`setup`](../../modes/setup.md) / [`update`](../../modes/update.md) / [`audit`](../../modes/audit.md) 세 모드 중 하나로 분기한다.

> **세 모드의 역할 분리** ([`../../CONTRACTS.md`](../../CONTRACTS.md) 1절):
>
> | 모드 | 방향 | 기준 | 빈도 |
> |------|------|------|------|
> | `setup` | 0 → 1 | 하네스가 없는 프로젝트에 구축 | 1회성 |
> | `audit` | 프로젝트 내부 드리프트 제거 | 프로젝트 vs 프로젝트 | 월 1회 또는 3~5 Phase 완료 시점 |
> | `update` | 스킬 버전 차이 반영 | 프로젝트 vs 최신 스킬 | `/plugin update` 후 |

## 워크플로우

### Phase 0: 상태 감지

다음 신호를 **읽기만** 수행한다 (어떤 파일도 수정하지 않는다):

**0-1. 마커 파일:**
- `docs/quality/.harness-version` 존재 여부 + (존재 시) `harnessVersion` 필드값

**0-2. 핵심 파일 (셋업 흔적):**
- `AGENTS.md` 존재 여부 (setup, update, audit 모두 가드)
- `docs/architecture.md` 존재 여부 (setup, update, audit 모두 가드)
- `_workspace/current-phase.md` 존재 여부 (setup, update, audit 모두 가드)
- `docs/quality/scores.json` 존재 여부 (audit 가드)

**핵심 3종**은 위 첫 세 파일을 가리킨다 (Phase 1 분기 규칙에서 사용). `scores.json` 은 audit 모드 진입 시 추가 가드용 — 마커 + 핵심 3종이 있어도 scores.json 이 없으면 audit 은 Phase 0-1 에서 종료한다.

**0-3. 플러그인 버전:**
- `../../.claude-plugin/plugin.json` 의 `version` 필드값

### Phase 1: 모드 결정 (의사결정 트리)

위→아래 순서로 첫 매칭 규칙을 선택한다. 각 모드의 Phase 0 가드와 일치하도록 설계되어 있다.

```
1) 마커 부재 + 핵심 3종 모두 부재
   → 권장 모드: setup
   → 사유: "하네스 인프라가 없습니다. 0→1 구축이 필요합니다."

2) 마커 부재 + 핵심 3종 모두 존재 (마커만 누락된 레거시)
   → 권장 모드: update
   → 사유: "v1.1 이전 (마커 도입 전) 레거시 하네스로 보입니다. update 가 .harness-version 마커 생성 + 최신 스킬 동기화를 함께 처리합니다."
   → 근거: update 모드 Phase 0-1 가드 (핵심 3종 존재 필수) + Phase 0-2 의 레거시 모드 (마커 부재 시 unknown 으로 처리) 충족

3) 마커 존재 + plugin.json.version ≠ .harness-version.harnessVersion
   → 권장 모드: update
   → 사유: "프로젝트 버전 v{old} → 스킬 버전 v{new}. 동기화가 필요합니다."

4) 마커 존재 + plugin.json.version == .harness-version.harnessVersion
   → 권장 모드: audit
   → 사유: "스킬 버전 일치. 내부 드리프트만 점검합니다."
   → 주의: audit 모드 Phase 0-1 은 핵심 4파일 (AGENTS.md, architecture.md, current-phase.md, scores.json) 존재를 요구. 누락 시 audit 도 종료. 이 경우 5번 규칙으로 분기.

5) 마커 존재 + 핵심 파일 일부 부재 (손상 또는 부분 셋업)
   → 권장 모드: 분기 불가, 사용자 판단 필요
   → 사유: "마커는 있지만 핵심 파일이 누락되었습니다 (예: AGENTS.md 가 사용자에 의해 삭제). 자동 모드 선택이 안전하지 않습니다."
   → 동작: Phase 2 의 AskUserQuestion 에 "권장 모드 없음 — 4개 옵션 중 선택" 으로 안내. setup 강제 (force-reinstall) / update 강제 / audit 강제 모두 자체 가드 발동 가능.

6) 마커 부재 + 핵심 일부만 존재 (혼란 상태)
   → 권장 모드: 분기 불가, 사용자 판단 필요
   → 사유: "셋업 흔적이 부분적으로만 있습니다. 진단이 필요합니다."
   → 동작: 5번과 동일하게 사용자에게 위임. setup 강제 시 setup 모드의 Phase 0 재실행 가드는 마커 부재 + 핵심 3종 모두 부재가 아니므로 발동될 수 있다.
```

### Phase 2: 사용자 확인 (AskUserQuestion)

감지 결과를 사용자에게 보고하고 **반드시 AskUserQuestion** 으로 확인을 받는다.
자동으로 모드를 시작하지 않는다.

**질문 형식**:

```
감지된 프로젝트 상태:
  - 마커: {존재/부재, 존재 시 버전}
  - AGENTS.md: {O/X}
  - docs/architecture.md: {O/X}
  - _workspace/current-phase.md: {O/X}
  - docs/quality/scores.json: {O/X}
  - 스킬 버전: v{plugin.json.version}

권장 모드: {setup/update/audit/없음}
사유: {Phase 1 의 사유 텍스트}

어떻게 진행할까요?

옵션:
  1. {권장 모드} 진행 (권장)         ← 권장이 있을 때만 표시
  2. setup 진행 (0→1 구축, 또는 기존 셋업의 강제 재설치)
  3. update 진행 (스킬 버전 동기화)
  4. audit 진행 (내부 드리프트 정리)
```

**옵션 매핑 규칙**:
- 권장 모드와 일치하는 옵션 라벨에 "(권장)" 추가. 권장 없음 (분기 규칙 5·6) 인 경우 옵션 1 생략, 옵션 2/3/4 만 제시
- 권장 모드가 setup 인 경우: 옵션 3 (update) / 옵션 4 (audit) 선택 시 "셋업되지 않은 프로젝트에서는 모드 자체의 Phase 0 가드에서 종료될 수 있습니다" 사전 안내
- 권장 모드가 update / audit 인 경우 (마커 존재): 옵션 2 (setup) 선택 시 "setup 모드의 Phase 0 재실행 가드가 발동되어 강제 재설치 의사를 다시 확인합니다. 진행 시 _workspace/, docs/quality/, docs/adr/ 가 `_archive/{date}-before-reset/` 로 백업됩니다" 사전 안내
- 권장 없음 (5·6번 규칙) 인 경우: 옵션 2/3/4 의 각 모드 Phase 0 가드가 어떻게 반응할지 한 줄씩 사전 안내

### Phase 3: 모드 위임

사용자가 선택한 모드의 워크플로우를 그대로 따른다:

- **setup 선택** → [`../../modes/setup.md`](../../modes/setup.md) 의 Phase 0~6 진행
- **update 선택** → [`../../modes/update.md`](../../modes/update.md) 의 Phase 0~5 진행
- **audit 선택** → [`../../modes/audit.md`](../../modes/audit.md) 의 Phase 0~5 진행

선택된 모드의 SKILL 본문을 읽어 그대로 실행한다. 본 라우터는 모드의 행동을 변경하지 않는다 (격벽 유지).

## 안티패턴

| 안티패턴 | 대신 |
|----------|------|
| Phase 1 의 판정을 사용자에게 묻지 않고 바로 실행 | 항상 Phase 2 의 AskUserQuestion 으로 확인 |
| 라우터에서 모드의 행동을 미리 일부 수행 | 라우터는 감지/위임만. 실제 행동은 각 모드 파일이 정의 |
| `.harness-version` 의 일부 필드만 보고 setup 권장 | 마커 존재 자체로 셋업 판정 (필드 값 무관) |
| 권장 모드 외의 선택지 숨김 | 항상 4개 옵션 모두 제공 (사용자 override 보장) |
| 모드 결정을 위해 파일 수정 | Phase 0~2 는 읽기 전용. 수정은 위임된 모드만 수행 |

## 참고

- **공유 규약 (모든 모드의 단일 진실)**: [`../../CONTRACTS.md`](../../CONTRACTS.md)
- **Setup 모드**: [`../../modes/setup.md`](../../modes/setup.md)
- **Update 모드**: [`../../modes/update.md`](../../modes/update.md)
- **Audit 모드**: [`../../modes/audit.md`](../../modes/audit.md)
- **References (각 모드가 사용하는 패턴 문서)**: [`../../references/`](../../references/)
- **Scripts (setup 가 사용하는 생성기)**: [`../../scripts/`](../../scripts/)
