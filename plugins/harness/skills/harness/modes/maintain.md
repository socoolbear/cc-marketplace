# Maintain — 낡음 점검 · 골격 갱신 · 학습 승격

설치된 하네스가 코드·현실과 어긋난 곳을 찾고, 세션에서 쌓인 학습을 팀 문서로 올린다. 규약·보호 규칙은 [`../SKILL.md`](../SKILL.md), 골격·등재 기준은 [`../references/document-formats.md`](../references/document-formats.md).

진단과 수집은 읽기 전용이다. 쓰기는 보고 후 승인받은 항목만 한다. 사용자가 "reflect"·"학습 승격" 만 요청했으면 2단계만 한다.

## 1. 진단

| # | 점검 | 판단 |
|---|---|---|
| ① | AGENTS.md 포인터 실재, 검증 명령 실행 가능, ≤40줄 | 깨진 것·실패한 명령·초과를 보고 |
| ② | `ARCHITECTURE.md` 규칙 vs 코드 | 규칙마다 import 방향·금지 패턴을 코드에서 직접 확인. 강제가 활성이면 검사기를 전체 모드로 실행 ("미판정 N건" 도 보고). **문서가 낡았을 가능성과 코드가 위반했을 가능성을 모두** 적는다 |
| ③ | `ADR.md` 정합성 | 번호 중복·결번, `Superseded by` 대상 실재, 오래 방치된 `Proposed` |
| ④ | 낡은 코드 명칭 | GLOSSARY "코드 명칭"·LESSONS "관련" 의 백틱 식별자를 검색해 0건인 것 |
| ⑤ | 골격 차이 | 표준 골격 대비 **누락 섹션** (추가 후보) 과 **표준에서 빠진 줄** (구버전 잔재 — 보고만. 팀이 의존할 수 있어 삭제는 사람 판단) |
| ⑥ | 강제 훅 위치 | 훅이 `.claude/settings.local.json` 에만 있거나 양쪽에 있으면 공유 설정으로 이관 후보. `.claude/settings.json` 이 gitignore 돼 있으면 "팀에 공유되지 않음" 보고 |

정의·본문의 정확성, 표기 위반 전수 검사, 미등재 용어 탐지는 하지 않는다 (사람 판단 · 거짓 양성 과다).

## 2. 학습 수집 (auto-memory → 팀 문서)

**위치** — `${CLAUDE_CONFIG_DIR:-~/.claude}/projects/<슬러그>/memory/`. 슬러그는 경로의 영숫자가 아닌 문자를 모두 `-` 로 바꾼 값이다. 후보 경로 (실재하는 것 모두):

- 앵커 (realpath)
- `git rev-parse --show-toplevel`
- `git rev-parse --path-format=absolute --git-common-dir` — bare 저장소면 그 디렉토리 자체, 아니면 상위 디렉토리

**대상** — `MEMORY.md` 가 가리키는 파일 중:

- type 이 `feedback`·`project` (frontmatter 최상위 `type:` 또는 `metadata.type`). `user`·`reference` 는 개인·외부 자원이라 제외
- 수정 시각 (`metadata.modified`, 없으면 mtime) 이 `lastReflect` 이후

memory 파일에는 아무것도 쓰지 않는다 — 쓰면 수정 시각이 바뀌어 다음에 다시 잡힌다.

**중복 제거** — AGENTS.md·`harness/*.md` 에 이미 반영된 것은 버린다.

**분류**

| 신호 | 목적지 |
|---|---|
| 코딩 규칙·경계 ("항상 X", "Y 금지") | AGENTS.md 경계 (≤5줄 유지 — 넘치면 제안하지 않고 보고) |
| 용어 정의·표기 교정 | GLOSSARY 행 (등재 기준 통과 시) |
| 반복 실수 | LESSONS — **2회 규칙**: 두 번째 발생부터 등재, 첫 발생은 보류 |
| 불변 조건·전략적 결정 | ARCHITECTURE·ADR 반영 권고만 |
| 모호함 | 보류 (다음에 재평가) |

한계: memory 는 머신별이고 `lastReflect` 는 커밋되므로, 다른 머신에서 승격하면 이 머신의 그 이전 학습이 대상에서 빠질 수 있다.

## 3. 보고

발견을 `critical`/`major`/`minor` 로 나누고, 승격 후보는 목적지별로 채팅에 보고한다. 보고서 파일은 만들지 않는다.

## 4. 승인 후 적용

AskUserQuestion 으로 일괄 / 개별 검토 / 건너뛰기 를 받는다. 적용 가능한 것만:

- 누락 골격 섹션 append (본문 무변경)
- 깨진 포인터는 주석 처리 (삭제는 사람 판단)
- 승격 후보 append (기존 행·항목 수정 없음)
- 강제 훅 이관: 훅 항목을 `.claude/settings.json` 으로 옮기고 `settings.local.json` 의 사본을 지운다 (다른 항목 무변경)
- 그 외 (규칙-코드 괴리, 낡은 항목, ADR 정합성, 구버전 잔재) 는 보고만

마커 갱신:

- `version`: 골격 갱신을 한 가지라도 적용했거나 골격 차이가 없을 때 플러그인 버전으로 올린다.
- `lastReflect`: 학습 수집을 실행했으면 (승격 0건이어도) 현재 ISO 시각으로 올린다.
- 사용자가 전부 거부하면 올리지 않는다. 세션 시작 신호는 7일 간격으로만 다시 뜬다.

## 하지 않는 것

- 플러그인 자체 갱신 → `/plugin update harness@socoolbear-cc-marketplace`
- 코드·검사기 수정, settings 의 다른 항목 수정
- 새 스킬·서브에이전트·설정 자동 생성 — 필요하면 `/update-config`·`skill-creator` 를 안내만
