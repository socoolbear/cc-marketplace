---
name: harness
description: "프로젝트에 에이전트용 지속 지식 문서 (AGENTS.md 지도 + harness/ 의 ARCHITECTURE·ADR·GLOSSARY·LESSONS) 와 선택적 레이어 검사 강제를 구축·유지·점검한다. 프로젝트 상태를 자동 감지해 setup (0→1 구축) / maintain (플러그인 버전 동기화 + 문서 낡음 점검) / reflect (세션 학습을 팀 문서로 승격) 로 분기하므로, 어떤 모드가 필요한지 몰라도 이 스킬 하나로 시작한다. 하네스 셋업·구축·적용·업데이트·동기화·감사·점검, 학습 승격 (reflect), 도메인 용어집 (glossary), ADR·아키텍처 결정 기록, 아키텍처 불변 조건, 레이어 경계 강제, 문서 낡음·드리프트, AGENTS.md 정리 요청 시 사용한다."
---

# Harness — 단일 진입점 라우터

프로젝트 상태를 감지해 세 모드 중 하나로 분기한다. 라우터는 **감지·분기만** 하고 모드의 행동을 바꾸지 않는다.

## 자료 (필요한 시점에 읽는다)

| 파일 | 무엇의 정답인가 |
|------|-----------------|
| [`CONTRACTS.md`](CONTRACTS.md) | 설계 원칙, 대상 레이아웃, `.harness.json` 스키마, 보호 규칙 |
| [`modes/setup.md`](modes/setup.md) | 0 → 1 구축 절차 |
| [`modes/maintain.md`](modes/maintain.md) | 버전 동기화 + 문서 낡음 점검 절차 |
| [`modes/reflect.md`](modes/reflect.md) | 세션 학습 → 문서 승격 절차 |
| [`references/document-formats.md`](references/document-formats.md) | 대상 문서 5종 + 브리지의 표준 골격, 등재 기준 |
| [`references/mechanical-enforcement.md`](references/mechanical-enforcement.md) | 레이어 검사기 설계 요건, hook 출력 프로토콜, CI |

모드 파일은 자기가 실제로 쓰는 시점에 위 references 를 읽는다 — 분기 시점에 한꺼번에 읽지 않는다.

## Phase 0: 상태 감지 (읽기 전용)

앵커 = 현재 작업 디렉토리 (모노레포 서브패키지 가능 — CONTRACTS 3절). 다음을 **읽기만** 한다:

1. **마커**: `harness/.harness.json` 존재 여부 + `version` 필드 vs `../../.claude-plugin/plugin.json` 의 `version`
2. **셋업 흔적**: `AGENTS.md`, `harness/` 문서 존재 여부 (부분 손상 판정용)
3. **학습 소스** (reflect 보조): `~/.claude/projects/<앵커 절대경로의 / 를 - 로 치환>/memory/` 의 `MEMORY.md` 가 가리키는 파일 중, frontmatter `metadata.type` 이 `feedback` 또는 `project` 이고 mtime 이 `.harness.json` 의 `lastReflect` 이후인 것

## Phase 1: 분기

사용자가 모드를 명시했으면 그 모드로 (아래 규칙 무시). 아니면 위→아래 첫 매칭:

```
1) 마커 존재
   → maintain. 비파괴이므로 한 줄 통지 후 바로 진행:
     버전 일치  → "하네스 v{버전} 최신 상태입니다 — 문서 낡음 점검을 진행합니다."
     버전 불일치 → "하네스 v{설치}→v{플러그인} 동기화와 낡음 점검을 진행합니다."
     (쓰기 단계의 승인은 maintain 내부의 AskUserQuestion 이 담당)

2) 마커 부재 + 셋업 흔적 부재
   → setup. 문서 생성·AGENTS.md 작성이 수반되므로 AskUserQuestion 으로 구축 범위를 요약해 확인 후 진행

3) 그 외 (부분 손상 — 마커는 있는데 harness/ 문서 누락, AGENTS.md 만 존재 등)
   → 감지 모호. 상태 요약과 함께 AskUserQuestion 으로 사용자가 모드 선택
```

**reflect 보조**: Phase 0-3 에서 신규 학습이 감지되고 셋업이 완료된 상태면, 위 통지·질문에 한 줄을 덧붙인다 — "세션 학습 N건이 누적되어 있습니다 — reflect 로 문서 승격도 가능합니다." (사용자가 선택할 때만 reflect 진행)

## Phase 2: 위임

선택된 모드 파일을 읽어 그대로 실행한다.

## 안티패턴

| 안티패턴 | 대신 |
|----------|------|
| 비파괴 분기 (규칙 1) 에서도 매번 질문 | 한 줄 통지 후 진행 — 질문은 파괴적 (2)·모호 (3) 분기만 |
| 라우터에서 모드의 행동을 미리 수행 | 감지·분기만. 쓰기는 각 모드가 자기 승인 절차로 |
