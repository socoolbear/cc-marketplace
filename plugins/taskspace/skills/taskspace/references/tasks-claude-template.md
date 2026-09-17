# taskspace — 태스크 작업 지도

이 파일은 taskspace 워크스페이스의 `tasks/CLAUDE.md` 다. 아래 경로는 `tasks/` 기준이다. 세션은 보통 `tasks/<TASK-ID>/<repo>/`(worktree) 에서 열리며, 그때 `<TASK-ID>/notes.md` 는 `../notes.md` 다. cwd 가 worktree 밖(`tasks/<TASK-ID>/`)이면 repo 의 훅·설정이 실리지 않았다고 사용자에게 알린다.

| 무엇 | 어디 |
|---|---|
| 진행·결정·열린 쟁점 | `<TASK-ID>/notes.md` — 워크스페이스 repo 가 추적, 영구 보존 |
| 프롬프트·스크래치 | `<TASK-ID>/<repo>/.prompts/` (worktree 안, cwd 의 `.prompts/`) — `done` 때 worktree 와 함께 사라지므로 남길 것은 notes.md 에 |
| 태스크 목록·제목 | `INDEX.md` — 생성 파일, 직접 편집 금지 (제목은 `notes.md` 첫 줄) |

- `<TASK-ID>/<repo>/` 는 별개 git worktree 다 — 코드의 git 은 그 안에서만. 워크스페이스 repo 의 commit·push 는 지시할 때만
- 두 repo 를 한 커밋에 섞지 않는다
- `.local/` 로 향하는 심링크(`.env` 등)는 전 태스크가 공유한다 — 태스크 전용 값은 링크를 지우고 실파일로
