# Harness — Update 모드 (버전 동기화 + v1→v2 마이그레이션)

이미 셋업된 프로젝트를 최신 플러그인 버전에 맞춰 동기화한다.
**문서의 본문 데이터 (ADR 항목, GLOSSARY 표 행, LESSONS 항목) 는 어떤 경우에도 보존한다** — update 가 만지는 것은 골격 (섹션 구조) 과 마커뿐이다.

> **진입점**: 라우터가 `harness/.harness.json` 버전 ≠ 플러그인 버전, 또는 v1 마커 (`docs/quality/.harness-version`) 감지 시 본 모드로 분기한다.
>
> **사전 지식**: [`../CONTRACTS.md`](../CONTRACTS.md), [`../references/document-formats.md`](../references/document-formats.md) (골격의 정답).

## 워크플로우

### Phase 0: 사전 확인

1. **`/plugin update harness@cc-marketplace` 선결 확인** (AskUserQuestion): 플러그인이 구버전이면 update 도 구버전 기준으로 동작하므로 의미가 없다. "이미 최신" 확인 후 진행, 아니면 중단.
2. **경로 판정**:
   - `harness/.harness.json` 존재 → **v2 동기화** (Phase 1)
   - 부재 + v1 마커 (`docs/quality/.harness-version`) 존재 → **v1→v2 마이그레이션** (Phase 2)
   - 둘 다 부재 → 중단 + "셋업되지 않은 프로젝트입니다. 라우터가 setup 으로 분기했어야 합니다" 안내

### Phase 1: v2 동기화

1. **골격 diff**: 대상 문서 (AGENTS.md + `harness/` 4종) 를 `document-formats.md` 골격과 비교 — **누락된 표준 섹션**만 찾는다. 본문 데이터·사용자 작성 섹션의 차이는 diff 대상이 아니다.
2. **보고 + 승인**: 누락 섹션 목록과 삽입 위치를 보고하고 AskUserQuestion 으로 승인받는다 (전체 적용 / 개별 검토 / 건너뛰기).
3. **적용**: 승인된 섹션만 해당 문서에 append. 기존 본문 0 변경.
4. **마커 갱신**: `harness/.harness.json` 의 `version` 을 플러그인 버전으로. 단, 사용자가 제안된 변경을 모두 거부한 경우 `version` 을 갱신하지 않는다 (다음 update 에서 다시 제안).

변경 사항이 아예 없으면 (골격 일치) `version` 만 갱신하고 종료한다.

### Phase 2: v1→v2 마이그레이션

절차·매핑·검증의 정답 → [`../references/migration-v1-to-v2.md`](../references/migration-v1-to-v2.md)

1. **분석 (읽기 전용)**: v1 산출물 목록화 — ADR 파일들, architecture.md, references 문서, phases (완료/미완료 구분), quality, _workspace, cli-tooling
2. **마이그레이션 보고서** (채팅): 매핑 표 + **v1 진행 상태 요약** (current-phase, scores.json 의 Phase 진행 — 삭제되므로 여기 남겨 조용한 유실 방지)
3. **승인** (AskUserQuestion): (a) 마이그레이션 진행 여부 (b) 제거 대상 처리 — **삭제 (기본, git 으로 복구 가능)** / `_archive/v1-YYYY-MM-DD/` 보관 (c) 미완료 Phase 스펙 처리 — 태스크 전환 / `_archive/` 보관 (기본) / 삭제
4. **실행**: 매핑 표 순서대로. ADR 병합은 본문 그대로 (불변 원칙)
5. **검증**: ADR 본문 diff 0 / 사용자 문서 0 손실 / hook 동작 유지 / 재실행 시 no-op (idempotent)

## 적용하지 않는 것

- 플러그인 자체 최신화 → `/plugin update harness@cc-marketplace`
- 문서 본문 데이터 수정·삭제 (보호 규칙 — CONTRACTS 5절)
- `docs/legacy-*/`, 기존 `_archive/` 정리 (동결)

## 참고

- 공유 규약: `../CONTRACTS.md` / 골격 정답: `../references/document-formats.md` / 마이그레이션: `../references/migration-v1-to-v2.md`
