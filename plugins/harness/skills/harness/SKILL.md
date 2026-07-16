---
name: harness
description: "경량 하네스 (에이전트용 지속 지식 문서 + 기계적 강제) 의 전체 라이프사이클을 단일 진입점으로 처리하는 스킬. 프로젝트 상태를 자동 감지하여 (1) 하네스가 없으면 setup 으로 0→1 구축 (AGENTS.md 지도 + harness/ 의 ARCHITECTURE·ADR·GLOSSARY·LESSONS), (2) 플러그인 버전이 다르거나 v1 구조 (docs/quality/.harness-version) 면 update 로 동기화·마이그레이션, (3) 버전이 같으면 audit 으로 문서 낡음 점검, (4) 세션 학습 누적 시 reflect 로 문서 승격. 트리거 키워드: '하네스', '하네스 실행', '하네스 셋업', '하네스 구축', '하네스 적용', '하네스 업데이트', '하네스 동기화', '하네스 마이그레이션', '하네스 감사', '하네스 점검', 'harness setup', 'harness update', 'harness audit', 'reflect', '학습 승격', '용어집', '도메인 용어집', 'glossary', 'ADR', '아키텍처 결정 기록', '아키텍처 불변 조건', '레이어 경계', '레이어 강제', '문서 낡음', '문서 드리프트', 'AGENTS.md 정리' 요청 시 사용. 사용자가 어떤 모드가 필요한지 몰라도 이 스킬 하나로 시작 — 라우터가 알아서 분기."
---

# Harness — 단일 진입점 라우터

`/harness` 로 호출되는 유일한 사용자 진입점.
프로젝트 상태를 감지하여 [`setup`](../../modes/setup.md) / [`update`](../../modes/update.md) / [`audit`](../../modes/audit.md) / [`reflect`](../../modes/reflect.md) 로 분기한다.

> 모드 역할 분리와 레이아웃 → [`../../CONTRACTS.md`](../../CONTRACTS.md) 2~3절

## Phase 0: 상태 감지 (읽기 전용)

앵커 = 현재 작업 디렉토리 (모노레포 서브패키지 가능 — CONTRACTS 3절). 다음을 읽기만 한다:

1. **v2 마커**: `harness/.harness.json` 존재 여부 + `version` 필드 vs `../../.claude-plugin/plugin.json` 의 `version`
2. **v1 마커**: `docs/quality/.harness-version` 존재 여부 (v1 레거시 신호)
3. **셋업 흔적**: `AGENTS.md`, `harness/` 문서 존재 여부 (부분 손상 판정용)
4. **학습 소스** (reflect 보조): `.harness.json` 의 `lastReflect` 이후 mtime 인 auto-memory feedback (`${CLAUDE_PROJECT_DIR}/memory/feedback_*.md`) 또는 `harness/inbox.md` 마커 줄 존재 여부

## Phase 1: 분기

사용자가 메시지에서 모드를 명시했으면 그 모드로 (아래 규칙 무시). 아니면 위→아래 첫 매칭:

```
1) v2 마커 존재 + 버전 일치
   → audit. 비파괴이므로 한 줄 통지 후 바로 진행:
     "하네스 v{버전} 최신 상태입니다 — 문서 낡음 점검 (audit) 을 진행합니다. (다른 모드를 원하시면 말씀해주세요)"

2) v2 마커 존재 + 버전 불일치
   → update (v2 동기화). 진단·보고까지 비파괴이므로 한 줄 통지 후 바로 진행
     (적용 단계의 승인은 update 모드 내부의 AskUserQuestion 이 담당)

3) v2 마커 부재 + v1 마커 존재
   → update (v1→v2 마이그레이션). 파괴적 분기 — AskUserQuestion 으로 확인 후 진행:
     "v1 하네스 구조가 감지되었습니다. v2 (harness/ 단일 디렉토리) 로 마이그레이션할까요?"

4) 마커 둘 다 부재 + 셋업 흔적도 부재
   → setup. 문서 생성·AGENTS.md 재작성이 수반되므로 AskUserQuestion 으로 구축 범위를 요약해 확인 후 진행

5) 그 외 (부분 손상 — 마커는 있는데 harness/ 문서 누락 등)
   → 감지 모호. 상태 요약과 함께 AskUserQuestion 으로 4개 모드 중 사용자가 선택
```

**reflect 보조**: Phase 0-4 에서 신규 학습이 감지되고 셋업이 완료된 상태면, 위 통지/질문에 한 줄을 덧붙인다: "세션 학습 N건이 누적되어 있습니다 — reflect 로 문서 승격도 가능합니다." (사용자가 선택 시에만 reflect 진행)

## Phase 2: 위임

선택된 모드 파일을 읽어 그대로 실행한다. 라우터는 감지·분기만 하고 모드의 행동을 변경하지 않는다.

## 안티패턴

| 안티패턴 | 대신 |
|----------|------|
| 비파괴 분기 (규칙 1·2) 에서도 매번 질문 | 한 줄 통지 후 진행 — 질문은 파괴적 (3·4)·모호 (5) 분기만 |
| 라우터에서 모드의 행동을 미리 수행 | 감지/분기만. 쓰기는 각 모드가 자기 승인 절차로 |
| Phase 0 에서 파일 수정 | 감지는 읽기 전용 |
| 사용자의 명시적 모드 지정 무시 | 명시 지정이 항상 우선 |
