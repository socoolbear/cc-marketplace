# v1 → v2 마이그레이션

v1 하네스 (docs/adr/·docs/quality/·_workspace/ 등 ~40개 파일) 프로젝트를 v2 경량 구조 (harness/ 단일 디렉토리) 로 전환하는 절차. update 모드 Phase 2 가 본 파일을 따른다.

**원칙**: 지식은 병합·이동으로 보존, 프로세스 산출물은 삭제 (git 이력으로 복구 가능). 삭제 전 반드시 사용자 승인.

---

## 1. 매핑 표

| v1 | v2 | 처리 |
|----|----|------|
| `docs/adr/NNNN-*.md` 본문 | `harness/ADR.md` 섹션 | 번호순 병합, **본문 그대로** (불변 원칙). 각 파일의 상태/결정일을 `## NNNN: 제목 — 상태 (날짜)` 헤더로 변환. README 인덱스·TEMPLATE 은 폐기 (단일 파일은 헤더가 곧 인덱스) |
| `docs/architecture.md` | `harness/ARCHITECTURE.md` | 내용 그대로 이동. 서술성 잔여물 (현황 설명 등) 정리는 이후 audit 소관 — 이동 시점에 내용을 고치지 않는다 (diff 0 검증과 충돌 방지) |
| `docs/references/failure-lessons.md` | `harness/LESSONS.md` | 내용 그대로 이동 (골격 헤더만 앞에 추가) |
| `docs/references/*.md` (사용자 문서) | `harness/*.md` | 파일 단위 이동 + AGENTS.md 포인터 갱신. 내용 0 변경 |
| (없음) | `harness/GLOSSARY.md` | 빈 골격 생성 (document-formats 5절). 용어 추출은 reflect/수동 소관 — 마이그레이션은 골격만 |
| `docs/phases/` 중 **미완료 Phase 스펙** | (예외) | 삭제 기본에서 제외 — 아직 코드가 되지 않은 계획은 재도출 불가. 내장 태스크 전환 제안 또는 `_archive/v1-YYYY-MM-DD/` 보관을 기본 제시 |
| 완료 phases + `docs/quality/` (scores, 로그 4종) | (삭제) | 진행 상태·점수 요약을 **마이그레이션 보고서 (채팅) 에 기록** 후 삭제 |
| `docs/quality/.harness-version` | `harness/.harness.json` | `{ "version": "{플러그인 현재 버전}" }` 만 생성. setupDate·features 등은 이관하지 않음 (git·파일 존재로 재도출 — CONTRACTS 1절 원칙 4) |
| `docs/conventions/cli-tooling.md` | (삭제) | agent-tooling feature 폐지 — 전역 dotfiles 의 CLI 규약이 커버 |
| `_workspace/` 전체 (프롬프트·템플릿·phase 산출물·inbox 포함) | (삭제) | 파이프라인 폐지. `_workspace/inbox.md` 에 미처리 마커가 있으면 `harness/inbox.md` 로 이동 |
| `AGENTS.md` | 재작성 | v2 골격 (document-formats 1절 — 검증 명령·포인터·경계·문서 유지 규칙). **사용자 작성 섹션 보존**, v1 관리 섹션 ("Phase 실행 — 4단계 파이프라인" 등) 은 제거 |
| `CLAUDE.md` | 부재 시 브리지 생성 | `@AGENTS.md` 한 줄 |
| `scripts/check-layer-import.js` + settings hook | 그대로 유지 | enforcement 존속. `package.json` 에 `check:layers` 가 없으면 등록 제안 |
| (없음) | `.gitignore` 항목 | setup Phase 2-7 과 동일 — `.prompts/`, `.claude/settings.local.json`, `.claude/worktrees/` 누락 시 append (기존 항목 무변경). worktree 제외 확인 (2-8) 도 동일 수행 |
| `docs/legacy-*/`, 기존 `_archive/` | 그대로 유지 | 동결 원칙 |

## 2. 삭제 vs 보관

- **삭제가 기본**: 제거 대상 (`_workspace/`, 완료 phases, `docs/quality/`, `cli-tooling.md`, `docs/adr/` 원본, `docs/architecture.md`·references 원본 등 이동 후 잔여) 은 git 이력으로 복구 가능함을 안내하고 삭제한다.
- 사용자가 보관을 선택한 경우에만 `_archive/v1-YYYY-MM-DD/{원래경로}` 로 이동한다.
- git 저장소가 아닌 프로젝트는 삭제 기본을 적용하지 않는다 — 보관을 기본으로 전환.

## 3. 검증 (실행 후 필수)

1. **ADR 본문 diff 0**: 병합 전 각 `NNNN-*.md` 본문과 `harness/ADR.md` 의 해당 섹션이 동일한지 (헤더 변환 제외)
2. **사용자 문서 0 손실**: 이동된 references 문서의 내용 동일성
3. **hook 동작 유지**: enforcement 프로젝트면 위반 파일로 스크립트 에러 확인 후 원복
4. **AGENTS.md 포인터 전수 유효** + 40줄 이내
5. **idempotent**: 재실행 시 Phase 0 경로 판정이 "v2 동기화" 로 빠지고 변경 0

## 4. 하지 않는 것

- 이동하는 문서의 내용 수정 (정리는 이후 audit·사람 소관)
- GLOSSARY 초기 용어 추출 (프로젝트 분석이 필요한 작업 — setup·reflect·수동 소관)
- `docs/` 하위 하네스 무관 문서에 대한 어떤 조치
