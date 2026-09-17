---
name: taskspace
description: bare 저장소 (`.bares/`) 로 여러 repo 를 중앙 등록해 두고, 이슈 단위 TASK-ID 로 `tasks/<TASK-ID>/` 아래에 repo 별 worktree 와 영구 보존 notes.md 를 격리해 관리하는 taskspace 워크스페이스 전용 스킬. "taskspace", "TASK-ID 로 작업 시작", "bare 저장소 등록", "tasks/ 아래에 worktree", "taskspace 워크스페이스 최초 세팅", "태스크 워크스페이스 정리 (done)", "태스크 worktree 에 최신 main 반영 (sync)", "taskspace 목록" 같은 요청에 사용한다. `.bares/` 구조가 아닌 일반 우산 워크스페이스에 그때그때 worktree 만 깔아 달라는 요청은 이 스킬이 아니라 `worktree-setup` 이다.
---

# taskspace — bare 저장소 + tasks/<TASK-ID>/ 격리 작업 환경

스크립트 경로 (이하 `$TS`): `${CLAUDE_PLUGIN_ROOT}/skills/taskspace/scripts/taskspace.sh`
아래 명령의 `$TS` 는 실제 실행 시 **절대 경로로 치환**해서 사용하세요 (이 SKILL.md 와 같은 디렉토리의 `scripts/taskspace.sh`).

## 1. 구조와 전제

`.bares/` 에 여러 repo 를 bare 저장소로 중앙 등록해 두고, 이슈 하나(TASK-ID)마다 `tasks/<TASK-ID>/` 아래에 관련 repo 의 worktree 를 한 벌 모아 둔다. **워크스페이스 루트 자체가 git repo** 다 — `.gitignore`·`repos.txt`·`tasks/*/notes.md`·`tasks/*/CLAUDE.md` 만 추적하고, `.bares/`·`.local/`·각 worktree 는 ignore 한다.

```
<워크스페이스 루트>/            ← git repo (notes 추적용)
├── .gitignore                   # .bares/ · .local/ · tasks/*/*/ 제외
├── repos.txt                    # 추적 — 등록한 repo 목록 (다른 머신 복원용)
├── .bares/<repo>.git/           # ignore — bare 저장소
├── .local/<repo>/<상대경로>      # ignore — repo 별 로컬 파일 원본 (.env 등)
└── tasks/<TASK-ID>/
    ├── notes.md                 # 추적 — 영구 보존 (done 후에도 남음)
    ├── CLAUDE.md                # 추적 — 선택. 작업 루트에서 세션 열 때만 작성
    ├── .prompts/                # ignore — 이 태스크의 프롬프트·스크래치
    └── <repo>/                  # ignore — worktree, 브랜치 feature/<TASK-ID>
        └── .env → ../../../.local/<repo>/.env   # 상대 심링크
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
   디렉토리·`.bares/`·`tasks/` 생성, `git init` (이미 repo 면 통과), `.gitignore` 추가, repo 등록까지 한 번에 끝난다. 여러 번 실행해도 안전하다(멱등).
4. `$TS repos` 로 등록 결과를 보고한다.
5. **워크스페이스 repo 의 첫 커밋은 사용자가 지시할 때만 한다.** `init` 은 커밋하지 않는다 — `.gitignore`·notes 를 추적하는 repo 라는 사실과 원격 연결은 사용자 몫이라고 안내한다.

## 2-1. 로컬 파일 등록

최초 세팅 또는 `new` 직후, repo 에 gitignore 된 실행 필수 파일(`.env` 등)이 있는지 사용자에게 묻는다. 기존 체크아웃이 있으면 다음으로 후보를 보여 준다.

```bash
git -C <체크아웃> status --ignored --short
```

사용자가 지정한 파일을 `<root>/.local/<repo>/<상대경로>` 로 **복사**한다(원본 체크아웃에서 옮기지 않는다). 내용은 읽거나 출력하지 않는다 — 민감정보이므로 경로만 다룬다. 복사 후 심링크를 건다 (worktree 의 같은 자리에 심링크가 아닌 파일이 이미 있으면 덮어쓰지 않고 `[exists]` 로 경고한다 — 사용자에게 어느 쪽을 쓸지 확인):

```bash
$TS link <TASK-ID>
```

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

모노레포는 앱 디렉토리 규칙이 루트 규칙보다 우선한다(`worktree-setup` 3절과 같은 원칙). 규칙이 `feat/<설명>` 처럼 TASK-ID 만으로 못 만드는 형식이면 설명을 사용자에게 받는다. 규칙이 있으면 `<repo>=<branch>`, 없으면 기본값 `feature/<TASK-ID>` 를 쓴다.

**worktree 를 만들기 전에 브랜치명을 한 줄로 먼저 보고한다.** 브랜치는 PR·리뷰에 그대로 노출돼서, 만든 뒤 고치면 이미 늦다.

### 4-3. 실행

```bash
$TS new <TASK-ID> [<repo>[=<branch>]...]
```

성공하면 stdout 마지막 줄에 태스크 디렉토리 절대경로가 출력된다. 실행 후 `notes.md` 의 "이슈 개요" 절을 사용자가 준 이슈 내용·링크로 채운다 (없으면 비워 둔다 — 추측하지 않는다).

### 4-4. CLAUDE.md — 조건부로만 작성

어디서 세션을 열지 사용자에게 확인한다. **작업 루트(`tasks/<TASK-ID>/`)에서 열 때만** `CLAUDE.md` 를 쓴다 — 각 repo 안에서 세션을 열면 그 repo 의 `CLAUDE.md` 가 이미 실리므로 필요 없다. 담을 내용은 하위 repo 안에서 열어도 참이 되게 쓴다:

- `tasks/<TASK-ID>/` 는 워크스페이스 repo(notes 추적용) 안이고, 각 `<repo>/` 는 별개 worktree 라는 사실 — 코드 작업의 git 은 반드시 `git -C <repo>`. cwd 가 repo 안이면 그 repo 규칙이 이 지도보다 우선한다.
- 4-2 에서 찾은 repo 별 규칙 문서 경로 표
- 경계 — commit·push·PR 은 지시할 때만, 두 repo 를 한 커밋에 섞지 않는다, 의존성 미설치

`@notes.md` 임포트는 하지 않는다 — 모든 세션의 컨텍스트를 갉아먹는다. repo 를 나중에 추가하면 표를 갱신한다.

### 4-5. 보고

- repo 별 경로 · 브랜치 · 기준 커밋
- 연결된 심링크 목록 (`.local/<repo>/` 가 비어 있으면 2-1 절 안내)
- `.prompts/` 경로
- 다음 세션을 열 디렉토리
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

`--delete-branch` 는 사용자가 말할 때만 붙인다. 완료 후 notes.md 는 보존된다는 사실과, 워크스페이스 repo 에 notes 변경이 미커밋 상태면 그 사실을 보고한다.

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

## 7. list / repos

```bash
$TS list    # tasks/* 목록: TASK-ID · worktree 있는 repo 수 (0 이면 archived) · 생성일
$TS repos   # .bares/*.git 목록: 이름 · 기본 브랜치 · 열린 worktree 수 (repos.txt 에만 있으면 missing)
```

## 8. 경계

- `.bares/` 와 worktree 밖에서 코드 repo 의 git 조작을 하지 않는다 — 항상 `git -C <repo>`.
- 워크스페이스 repo(루트)의 commit·push 도 지시할 때만 한다.
- 코드 수정·커밋·PR 은 지시할 때만 한다.
- TASK-ID 는 `^[A-Za-z0-9][A-Za-z0-9._-]*$` 이면서 `git check-ref-format --branch "feature/<ID>"` 를 통과해야 한다 (`new`/`done` 이 스크립트에서 검증한다). `.`·`..`·`-x` 로 시작하는 값은 거부된다.
