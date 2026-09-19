---
name: taskspace
description: bare 저장소 (`.bares/`) 로 여러 repo 를 중앙 등록해 두고, 이슈 단위 TASK-ID 로 `tasks/<TASK-ID>/` 아래에 repo 별 worktree 와 영구 보존 notes.md 를 격리해 관리하는 taskspace 워크스페이스 전용 스킬. "taskspace", "TASK-ID 로 작업 시작", "bare 저장소 등록", "tasks/ 아래에 worktree", "taskspace 워크스페이스 최초 세팅", "태스크 워크스페이스 정리 (done)", "태스크 worktree 에 최신 main 반영 (sync)", "taskspace 목록", "태스크 색인 (index)", "지난 태스크 찾기", "기존 체크아웃의 gitignore 된 로컬 파일을 .local/ 로 가져오기 (migrate)", ".env·키·참조 소스처럼 gitignore 된 필수 파일 공유" 같은 요청에 사용한다. `.bares/` 구조가 아닌 일반 우산 워크스페이스에 그때그때 worktree 만 깔아 달라는 요청은 이 스킬이 아니라 `worktree-setup` 이다.
---

# taskspace — bare 저장소 + tasks/<TASK-ID>/ 격리 작업 환경

스크립트 경로 (이하 `$TS`): `${CLAUDE_PLUGIN_ROOT}/skills/taskspace/scripts/taskspace.sh`
아래 명령의 `$TS` 는 실제 실행 시 **절대 경로로 치환**해서 사용하세요 (이 SKILL.md 와 같은 디렉토리의 `scripts/taskspace.sh`).

## 1. 구조와 전제

`.bares/` 에 여러 repo 를 bare 저장소로 중앙 등록해 두고, 이슈 하나(TASK-ID)마다 `tasks/<TASK-ID>/` 아래에 관련 repo 의 worktree 를 한 벌 모아 둔다. **워크스페이스 루트 자체가 git repo** 다 — `.gitignore`·`repos.txt`·`tasks/CLAUDE.md`·`tasks/INDEX.md`·`tasks/*/notes.md`·`tasks/*/CLAUDE.md` 만 추적하고, `.bares/`·`.local/`·`shared/`·각 worktree 는 ignore 한다.

```
<워크스페이스 루트>/            ← git repo (notes 추적용)
├── .gitignore                   # .bares/ · .local/ · shared/ · tasks/*/*/ 제외
├── repos.txt                    # 추적 — 등록한 repo 목록 (다른 머신 복원용)
├── .bares/<repo>.git/           # ignore — bare 저장소
├── .local/<repo>/<상대경로>      # ignore — 비밀·참조 자료·개인 설정의 원본 (파일·디렉토리·외부 위치로의 심링크)
├── shared/                      # ignore — repo 밖에서도 의미 있는 자료 (배포 로그, QA 자료 등). notes.md 에서 경로로 참조
└── tasks/
    ├── CLAUDE.md                # 추적 — 작업 지도 (init/new 가 없으면 생성. 상위라 worktree 세션에도 실림)
    ├── INDEX.md                 # 추적 — 생성 파일 (index 가 다시 씀, 직접 편집 금지)
    └── <TASK-ID>/
        ├── notes.md             # 추적 — 영구 보존 (done 후에도 남음)
        ├── CLAUDE.md            # 추적 — 선택. repo 가 둘 이상일 때 규칙 문서 경로 표
        └── <repo>/              # ignore — worktree, 브랜치 feature/<TASK-ID>[-<슬러그>]
            ├── .prompts/                                      # info/exclude — 스크래치, done 때 함께 삭제
            ├── .env → ../../../.local/<repo>/.env             # 상대 심링크 (파일)
            └── vendor-src → ../../../.local/<repo>/vendor-src  # 상대 심링크 (디렉토리)
```

루트는 `$TS root` 로 판별한다 (`TASKSPACE_ROOT` 환경변수 > cwd 부터 상위로 `.bares/` 또는 `repos.txt` 탐색 — clone 직후엔 `.bares/` 가 없어서 `repos.txt` 가 마커다). **루트를 찾지 못하면 taskspace 워크스페이스가 아직 없다는 뜻이다** — 추측으로 `.bares/` 를 만들지 말고 사용자에게 두 갈래를 제시해 고르게 한다:

- (a) 여기 또는 지정한 위치에 taskspace 를 최초 세팅한다 → 2절 (init)
- (b) `.bares/` 구조 없이 일반 우산 워크스페이스에 그때그때 worktree 만 필요하면 `worktree-setup` 스킬을 대신 쓴다

## 2. 최초 세팅 (init)

1. 루트 디렉토리를 사용자에게 확인한다 (예: `~/Company-A`). 추측하지 않는다.
2. repo URL 목록을 받는다. 조직명만 주어졌으면 `gh repo list <org> --limit 100 --json name,sshUrl` 로 목록을 보여 주고 고르게 한다 (`gh` 가 없으면 URL 을 직접 받는다).
3. 한 번에 세팅한다.
   ```bash
   $TS init <dir> <git-url>[=<name>]...
   ```
   디렉토리·`.bares/`·`tasks/` 생성, `git init` (이미 repo 면 통과), `.gitignore` 추가, 지도 `tasks/CLAUDE.md` 생성(있으면 보존), repo 등록까지 한 번에 끝난다. 여러 번 실행해도 안전하다(멱등).
4. `$TS repos` 로 등록 결과를 보고한다.
5. **워크스페이스 repo 의 첫 커밋은 사용자가 지시할 때만 한다.** `init` 은 커밋하지 않는다 — `.gitignore`·notes 를 추적하는 repo 라는 사실과 원격 연결은 사용자 몫이라고 안내한다.

## 2-1. 로컬 파일 분류와 등록

최초 세팅 또는 `new` 직후, repo 에 gitignore 된 실행 필수 파일(`.env` 등)이 있는지 사용자에게 묻는다. 기존 체크아웃이 있으면 다음으로 후보를 보여 준다.

```bash
git -C <체크아웃> status --ignored --short
```

**분류는 경로·이름과 사용자 답으로만 한다 — 내용은 어느 위치에서도 열지 않는다.** 세 질문으로 가른다.

1. **재생성 가능한가** (`node_modules`, 빌드 산출물, 태스크 스크래치 — 스크래치는 `tasks/<TASK-ID>/<repo>/.prompts/` 가 자리다) → 올리지 않는다. 기존 체크아웃에 쌓인 **과거 태스크 이력 문서**(`.prompts/` 등)는 `tasks/<TASK-ID>/<repo>/.prompts/` 로 쪼개지 않는다 — 코드·문서가 repo 안 경로로 참조하면 `.local/<repo>/` 에 통째로, 아니면 `shared/<repo>/` 에 두고 notes.md 에서 가리킨다. 자격증명(`ftp.env` 등)만 `.local/<repo>/.secrets/` 로 따로 빼면 `link` 대상이 작아진다.
2. **repo 트리 안에 있어야 하는가** — 빌드·실행·repo 안 스크립트가 그 경로에서 읽거나, IDE·에이전트가 repo 트리 안에서 봐야 하는 자료 (`.env`, `keys/`, 코드가 참조하는 벤더 소스, `config/local.php`) → `.local/<repo>/` 에 두고 `link` 로 연결한다.
3. **repo 밖에서도 의미 있는가** (배포 로그, QA 자료, 참조 문서) → `<root>/shared/` 에 두고 notes.md 에서 경로로 참조한다. `migrate` 대상이 아니다.

흔한 규칙:
- 가져온 뒤 갱신은 `.local/` 쪽에만 한다 — worktree 는 심링크라 따라간다.
- **외부 도구가 갱신하는 자료는 복사하지 말고 `.local/<repo>/<경로>` 에 그 위치로의 심링크만 둔다** — 원본이 한 곳이고, 도구를 다른 곳으로 재지정할 필요가 없다.
- 그 경로에 쓰는 코드·도구가 있으면 `.local/` 에 부적합하다 — 쓰기가 전 태스크에 전파된다.

드문 규칙·태그 대응은 `references/local-files.md` 참조.

2번 부류는 사용자가 `<root>/.local/<repo>/<상대경로>` 에 두고 (기존 체크아웃에서 가져오면 2-2 절) 심링크를 건다:

```bash
$TS link
```

`link` 는 `.local/<repo>/` 를 파일 단위가 아니라 **디렉토리째 심링크**하고, bare 저장소의 `info/exclude` 에 자동 등록해 repo 의 `.gitignore` 를 건드리지 않는다. 인자 없이 실행하면 worktree 가 있는 태스크 전부에 연결한다 (`link <TASK-ID> [<repo>...]` 로 범위를 좁힐 수도 있다).

## 2-2. migrate — 기존 체크아웃에서 가져오기

이미 로컬 파일이 채워진 기존 체크아웃이 있으면, 하나씩 새로 만드는 대신 거기서 가져온다.

```bash
$TS migrate <repo> <checkout-path> <rel-path>...
```

taskspace 루트(또는 `TASKSPACE_ROOT`)에서 실행한다. **실행 전에 복사될 경로 목록을 사용자에게 보여 주고 확인받는다.** `<rel-path>` 는 `<checkout-path>` 기준 상대경로다.

각 경로를 `.local/<repo>/<rel-path>` 로 **복사**한다 — 기존 체크아웃은 그대로 남고, 정리(삭제·아카이브)는 사용자 몫이다. 이 스킬은 어떤 경우에도 기존 체크아웃의 파일을 지우지 않는다. 경로별 결과는 태그로 나오며, 뜻과 대응은 `references/local-files.md` 참조.

끝나면 `link` 가 자동으로 다시 실행돼 전 태스크에 연결된다.

## 3. add — 기존 루트에 repo 추가

```bash
$TS add <git-url>[=<name>]...
```

URL 은 사용자에게 받는다. **워크스페이스 repo 를 새 머신에 clone 한 직후**라면 (`repos` 에 `missing` 이 보이거나 `.bares/` 가 비어 있음) 인자 없이 실행해 `repos.txt` 전체를 복원한다.

```bash
$TS add
```

## 4. new — 태스크 시작

### 4-1. repo 선택

repo 를 지정받지 않았으면 `$TS repos` 출력을 보여 주고 고르게 한다.

### 4-2. 브랜치 규칙 확인 — 앱 규칙이 루트 규칙을 이긴다

bare 저장소라 파일이 체크아웃돼 있지 않으므로, 후보 경로를 먼저 열거한 뒤 내용을 읽는다.

```bash
git -C <bare> ls-tree -r --name-only origin/<기본브랜치> \
  | grep -E '(^|/)(AGENTS|CLAUDE)\.md$|^\.claude/rules/'
git -C <bare> show origin/<기본브랜치>:<path>
```

모노레포는 앱 디렉토리 규칙이 루트 규칙보다 우선한다(`worktree-setup` 3절과 같은 원칙). 규칙이 `feat/<설명>` 처럼 TASK-ID 만으로 못 만드는 형식이면 설명을 사용자에게 받는다. 규칙이 있으면 `<repo>=<branch>`, 없으면 기본값 `feature/<TASK-ID>[-<슬러그>]` 를 쓴다.

ID 가 번호형(`001`·`task-001`)이면 브랜치에 슬러그가 필수다 (순수 숫자 ID 는 스크립트가 거부한다). 사용자에게 **영문 kebab-case 슬러그**와 **사람용 제목**(한국어 가능)을 받는다. 앱 규칙 우선 원칙은 그대로 — 앱 규칙으로 `<repo>=<branch>` 를 쓰더라도 슬러그는 notes 기록용으로 받는다.

**worktree 를 만들기 전에 브랜치명을 한 줄로 먼저 보고한다.** 브랜치는 PR·리뷰에 그대로 노출돼서, 만든 뒤 고치면 이미 늦다.

### 4-3. 실행

```bash
$TS new <TASK-ID|next> [--slug <슬러그>] [--title <제목>] [<repo>[=<branch>]...]
```

ID 를 지정받지 않았으면 `next` 로 자동 배정한다 (`001` 부터, 기존 접두사 계승, 접두사 혼재 시 오류 → ID 를 직접 받는다). `task-001` 접두사를 원하면 첫 태스크만 그 ID 로 만들면 이후 `next` 가 따라간다. `--title` 로 제목을 바로 넣는다 — 사후 편집 단계 없음.

성공하면 stdout 마지막 줄에 태스크 디렉토리 절대경로가 출력된다. 실행 후 `notes.md` 의 "이슈 개요" 절을 사용자가 준 이슈 내용·링크로 채운다 (없으면 비워 둔다 — 추측하지 않는다).

### 4-4. 세션 위치와 CLAUDE.md

세션은 **주로 만질 repo 의 worktree** `tasks/<TASK-ID>/<repo>/` 에서 `claude --add-dir ..` 로 연다 — 훅·`settings.json` 은 cwd 의 `.claude/` 만 실리기 때문이다. `--add-dir ..` 는 `notes.md`·형제 repo 접근 승인 프롬프트를 없앤다 (`tasks/<TASK-ID>/` 에는 `.claude/` 가 없어 훅·설정 오염이 없다). `tasks/<TASK-ID>/` 에서 열면 repo 의 훅·설정을 잃는다고 사용자에게 알린다.

기록 위치는 지도 `tasks/CLAUDE.md`(템플릿 `references/tasks-claude-template.md`)가 알려 준다 — `init`/`new` 가 없으면 만든다.

태스크 CLAUDE.md(`tasks/<TASK-ID>/CLAUDE.md`)는 **repo 가 둘 이상일 때만** 쓴다. 형제 repo 의 CLAUDE.md 는 조상도 자손도 아니라 실리지 않으므로, 4-2 에서 찾은 repo 별 규칙 문서 경로 표를 여기 둔다. 지도와 겹치는 경계는 넣지 않는다 (이중 로드). `@notes.md` 임포트는 하지 않는다 — 모든 세션의 컨텍스트를 갉아먹는다. repo 를 나중에 추가할 때는 `new <TASK-ID> <repo>` 만 치면 된다 (슬러그는 notes.md 에서 계승된다) — 추가 후 표를 갱신한다.

1.3.0 이전 태스크의 CLAUDE.md 는 그대로 둬도 되나, 지도와 겹치는 경계 목록은 지운다.

### 4-5. 보고

- ID · 제목 · 브랜치
- repo 별 경로 · 브랜치 · 기준 커밋
- 연결된 심링크 목록 (`.local/<repo>/` 가 비어 있으면 2-1·2-2 절 안내)
- 각 worktree 의 `.prompts/` (스크래치, done 때 삭제)
- 다음 세션: `cd tasks/<TASK-ID>/<repo> && claude --add-dir ..` (주로 만질 repo)
- 의존성이 설치돼 있지 않다는 사실

## 5. done — 태스크 정리

먼저 플래그 없이 실행한다.

```bash
$TS done <TASK-ID>
```

종료코드 4 면 아무것도 지우지 않은 것이다. stderr 의 태그로 분기한다 (`[locked]` 만은 차단이 아니라 그 repo 를 건너뛴 것이라 종료코드 0 으로도 나온다).

| 태그 | 뜻 | 대응 |
|---|---|---|
| `[dirty]` | 추적 파일 변경 있음 | 멈추고 사용자에게 확인 (커밋할지 버릴지는 사용자 결정, `--force` 는 명시 지시 때만) |
| `[unpushed]` | HEAD 를 포함하는 원격 브랜치 없음 | worktree 안에서 `gh pr list --head <branch> --state merged --json number,mergedAt` 로 병합 확인 (`gh` 는 cwd 의 remote 로 repo 를 정하므로 `cd <worktree> &&` 로 실행). 병합됐으면 `--merged` 로 재실행, 아니면 멈춘다 |
| `[untracked]` | 미추적·ignored 파일 있음 (`.local/` 심링크는 제외) | 삭제될 목록을 보여 주고 확인받은 뒤 `--discard-untracked` |
| `[locked]` | worktree 가 잠김 | 그 repo 만 건너뛰고 나머지 보고 |
| `[offline]` | `fetch --prune` 실패 | 멈춘다 (stale 원격 상태로 판정하지 않는다) |

`--delete-branch` 는 사용자가 말할 때만 붙인다. 로컬 브랜치를 지우고, **병합이 확인된 경우** (브랜치 끝 커밋이 다른 원격 브랜치에 있거나 `--merged`) 원격 브랜치 `origin/<branch>` 도 지운다. push 만 되고 병합이 안 된 브랜치는 원격에 남기고 그 사실을 알린다 — 지우려면 병합 후 `--merged` 와 함께 다시 실행하거나 사용자가 직접 지운다. 완료 후 notes.md 는 보존되고 `- 완료 일시:` 줄이 추가되며 INDEX.md 가 갱신된다 — 워크스페이스 repo 에 2개 파일 diff. 미커밋 상태면 그 사실을 보고한다.

## 6. sync — 작업 중 기본 브랜치 반영

"main 이 전진했어", "최신 main 반영해줘" 류 요청에 쓴다.

```bash
$TS sync <TASK-ID> [<repo>...] [--rebase]
```

기본은 merge다 — 이미 push 된 브랜치를 rebase 하면 협업자 히스토리가 깨진다. `--rebase` 는 **브랜치가 아직 원격에 없고** (`git -C <worktree> branch -r --contains HEAD` 가 비어 있음) 사용자가 원할 때만 붙인다.

종료코드 5 면 태그로 분기한다.

| 태그 | 대응 |
|---|---|
| `[dirty]` | 커밋할지 stash 할지는 사용자 결정 |
| `[conflict]` | 충돌 파일을 보여 주고 사용자와 해결한 뒤 `git -C <worktree> merge --continue` (또는 `rebase --continue`) |
| `[offline]` | 멈춘다 |

이미 PR 이 병합된 브랜치를 "최신화"하는 요청이면 이 스킬에서는 `sync` 가 아니라 `done` → 다음 태스크 `new` 다 (`worktree-refresh` 의 reset 경로에 해당).

`sync` 는 끝에 `link` 를 다시 실행해 연결 상태를 재확인한다.

## 7. list / index / repos

```bash
$TS list    # tasks/* 목록: TASK-ID · worktree 있는 repo 수 (0 이면 archived) · 생성일 · TITLE. 끝에 tasks/INDEX.md 재생성
$TS index   # tasks/INDEX.md 재생성만 (new·done·list 끝에도 자동 실행)
$TS repos   # .bares/*.git 목록: 이름 · 기본 브랜치 · 열린 worktree 수 (repos.txt 에만 있으면 missing)
```

**"지난 태스크 찾기" 요청은 `tasks/INDEX.md` 를 먼저 읽고 해당 `notes.md` 로 간다.** 제목을 고쳤으면 `$TS index` (또는 `list`) 로 재생성한다 — 색인은 손으로 고치지 않는다.

## 8. 경계

- `.bares/` 와 worktree 밖에서 코드 repo 의 git 조작을 하지 않는다 — 항상 `git -C <repo>`.
- 워크스페이스 repo(루트)의 commit·push 도 지시할 때만 한다.
- 코드 수정·커밋·PR 은 지시할 때만 한다.
- TASK-ID 는 `^[A-Za-z0-9][A-Za-z0-9._-]*$` 이면서 `git check-ref-format --branch "feature/<ID>"` 를 통과해야 한다 (`new`/`done` 이 스크립트에서 검증한다). `.`·`..`·`-x` 로 시작하는 값은 거부된다. `next` 는 예약어라 TASK-ID 로 못 쓴다.
- 슬러그는 `^[a-z0-9][a-z0-9-]*$` 만 허용한다. 한 태스크 안에서 슬러그를 바꾸지 않는다 (계승된 값과 다른 `--slug` 는 오류).
- `tasks/INDEX.md` 는 생성 파일이다 — 직접 편집하지 않는다. 제목을 고치려면 `notes.md` 첫 줄을 고친 뒤 `$TS index` 로 재생성한다.
- 로컬 파일 후보의 내용은 어느 위치에서도 읽거나 출력하지 않는다 — 경로만 다룬다.
- `.local/`·`shared/` 어디에 무엇을 올릴지는 사용자가 정한다. 추측으로 분류하지 않는다.
- `migrate` 는 복사될 경로 목록을 보여 주고 확인받은 뒤, 지시할 때만 실행한다.
- `migrate` 를 포함해 어떤 명령도 기존 체크아웃의 파일을 지우지 않는다.
