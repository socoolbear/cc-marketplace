# worktrees 진화 기록

최신이 위. 형식은 `.claude/skills/evolve/SKILL.md` 의 "결정 기록" 절.

## 2026-11-21 — worktree-setup 스킬 삭제 (1.1.0)

자료: 사용 흔적 — 최근 30일 대화 기록에서 worktree-setup 호출 0, worktree-refresh 6회.

| 판정 | 항목 | 근거 | 재검토 조건 |
|---|---|---|---|
| 제거 | worktree-setup 스킬 (`skills/worktree-setup/` 전체) | 여러 repo 작업 공간 준비는 taskspace 가 맡아 겹치고, 쓰지 않았다 (2026-11-21 사용자 승인) | taskspace 없이 여러 repo 작업 공간을 반복해서 손으로 만들게 되면 |
| 기록 | worktree-refresh 는 남김 | 최근 30일 6회 사용 | — |
