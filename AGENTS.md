# cc-marketplace

socoolbear 의 개인용 Claude Code 플러그인 마켓플레이스. 플러그인은 `plugins/<name>/` 에 두고 루트 `.claude-plugin/marketplace.json` 에 등재한다.

## 검증 명령 (완료 주장 전 반드시 실행)

`bash scripts/verify.sh` 가 아래 다섯 가지를 한 번에 돈다. push · PR 때 GitHub Actions (`.github/workflows/verify.yml`, macOS 러너) 도 같은 스크립트를 돈다. 주 1회 (월 10:00 KST) 예약 실행과 손 실행 (`workflow_dispatch`) 도 있다 — 예약 실행이 실패하면 GitHub 가 cron 줄을 마지막으로 고친 사람에게 알린다 (계정의 Actions 알림 설정을 따름). 공개 저장소라 60일 동안 활동이 없으면 GitHub 가 예약을 끈다 (Actions 탭에서 다시 켬). 끄려면 Actions 탭에서 이 workflow 를 Disable.

- 매니페스트 JSON 파싱: `.claude-plugin/marketplace.json` 과 각 `plugins/*/.claude-plugin/plugin.json`
- 버전 일치: 각 `plugins/<n>/.claude-plugin/plugin.json` 의 `version` == `marketplace.json` 의 동명 플러그인 `version`, 목록과 폴더가 같은지 (예외: `workstyle` 은 두 곳 모두 `version` 을 두지 않는다 — 아래 경계)
- 스킬 내부 링크 실재: 각 `skills/*/` 아래 마크다운의 상대 링크가 실재하는지
- 임시 폴더 지우기 보호: `mktemp` 로 만든 경로를 `rm -r` 하는 셸 파일이 `mktemp` 실패를 막는지 (빈 값이면 저장소를 지운다)
- 플러그인 시험: `plugins/*/tests/run.sh`

## 경계

- Never: 플러그인 산출물에 영향을 주는 변경 (스킬 본문·references·규약 문서) 을 하면서 **버전 bump 를 빠뜨리기**
- Always: 위 변경 시 `plugins/<n>/.claude-plugin/plugin.json` 과 `.claude-plugin/marketplace.json` 의 해당 플러그인 `version` 을 **동시에** minor 이상 올린다 (두 값이 어긋나면 설치본과 목록이 갈린다)
- Always: 스킬 자료는 `skills/<skill>/` 안에 둔다 (`references/`, `scripts/`) — 스킬 디렉토리 밖 참조 금지. 예외: Claude Code 가 위치를 정한 `hooks/hooks.json`·`evals/` 는 플러그인 루트
- Always: 스킬이 없는 훅·명령 플러그인은 플러그인 루트에 역할별 폴더를 둔다 — 훅 스크립트는 `hooks/`, 세션 밖에서도 부르는 실행 파일은 `bin/`, 모델에 넘기는 지시문은 `prompts/`, 시험은 `tests/` (선례: `plugins/workstyle`)
- Always: 훅·실행 파일을 바꾸면 그 플러그인의 `tests/run.sh` 를 돌린다 (있을 때)
- Always: `workstyle` 에는 `version` 을 넣지 않는다 (plugin.json · marketplace.json 둘 다). 자주 고치는 플러그인이라 커밋 해시를 버전으로 쓴다 (2026-11-20 사용자 결정) — 고친 뒤 push 하면 플러그인 갱신 때 반영되고, 버전 bump 규칙은 이 플러그인에 적용하지 않는다
- Never: 플러그인 소스 (스크립트·SKILL.md·references·README·매니페스트) 에 특정 프로젝트·회사 이름이나 실제 경로를 남기기 — 예시는 `.env`·`vendor-src/` 같은 일반 이름만. 스킬이 사용자 워크스페이스에 만드는 산출물 (notes.md 등) 은 제약 없음
- Never: **생성 파일** (아래 표) 을 이 repo 에서 직접 편집하기 — 다음 sync 때 경고 없이 덮어써진다
- Ask first: 플러그인 삭제, 마켓플레이스 이름·소유자 변경

## 생성 파일 (직접 편집 금지)

아래 파일은 다른 repo 에서 빌드해 이 repo 로 복사한 것이다. 커밋돼 있어서 손으로 쓴 소스와 구분되지 않지만, 여기서 고치면 다음 sync 때 **경고 없이 사라진다**. 원인을 찾기 어려운 사고이므로 고치기 전에 이 표를 확인한다.

| 생성 파일 | 원본 | 갱신 방법 |
|---|---|---|
| (지금은 없음) | | |

동작을 바꿔야 하면 **원본 repo 의 소스를 고치고 갱신 명령으로 가져온 뒤**, 이 repo 에서는 커밋만 한다. 원본만 고치고 갱신 명령을 빠뜨리면 플러그인에는 반영되지 않는다.

## 진화

플러그인 개선·deprecate·정기 점검은 repo 전용 스킬 `/evolve` (`.claude/skills/evolve/`) 로 한다. 판정 이력은 `docs/evolution/<플러그인>.md` — 플러그인을 고치기 전에 읽는다.

저장소 상태 점검은 `bash scripts/health.sh` (최근 CI · 지워진 이름 참조, 읽기 전용) 이고 `--verify` 를 주면 검증 명령도 돈다. 출력은 `[FAIL]`·`[WARN]`·`[INFO]` 줄과 마지막 `FAIL n건` 이다 — 다른 저장소의 점검이 이 형식으로 불러 쓰므로 형식을 바꾸면 그쪽도 함께 본다.

## 문서 유지 규칙

- 플러그인의 모드·산출물 구조를 바꾸는 변경은 같은 커밋에서 해당 플러그인의 규약 문서와 README 표를 갱신
- 작업 중 거짓으로 판명된 문서 문장은 같은 커밋에서 수정
