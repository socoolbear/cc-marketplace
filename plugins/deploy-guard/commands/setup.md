---
description: deploy-guard 장비 설정 — 훅이 읽는 정책 파일 (~/.config/claude/deploy-targets 등) 의 자리를 잡는다. 장비마다 한 번
disable-model-invocation: true
allowed-tools: Read, Bash(ls:*), Bash(command -v:*), Bash(readlink:*), AskUserQuestion
---

deploy-guard 플러그인이 이 장비에서 읽는 정책 파일을 확인하고 자리를 잡습니다. 아래 순서를 그대로 따르고, 단계마다 결과를 한 줄로 보고하세요.

## 1. 필요한 것 확인

```bash
command -v jq git gh md5
```

하나라도 없으면 무엇이 없는지 알리고 멈춥니다 (`md5` 는 macOS 기본 명령입니다).

## 2. 정책 파일 확인

```bash
ls -la ~/.config/claude/deploy-targets ~/.config/claude/deploy-targets.md ~/.config/claude/deploy-qa-patterns
```

| 파일 | 읽는 쪽 | 없을 때 |
|---|---|---|
| `deploy-targets` | 배포 점검 훅 | `main` · `master` · `dev` 로 가는 push·머지를 모두 운영으로 본다 (엄격한 판정) |
| `deploy-targets.md` | 모델 (repo 별 분류 표) | 표 없이 그때그때 workflow 를 확인한다 |
| `deploy-qa-patterns` | QA 알림 훅 | 공용 패턴만 쓴다 (없어도 된다) |

## 3. 없는 파일의 자리 잡기

없는 파일이 있으면 `AskUserQuestion` 으로 한 번에 묻습니다: 원본을 둔 곳 (비공개 저장소의 경로) 이 있는지, 새로 만들지, 지금은 두지 않을지.

- **원본이 있다** → 사용자가 알려 준 경로로 심링크를 겁니다 (`ln -s <원본> ~/.config/claude/<파일>`). 실행 전에 명령을 보여 주고 확인받습니다
- **새로 만든다** → 형식을 설명하고 (이 플러그인의 `skills/deploy/references/` 예시 3개) 사용자가 실제 대상을 불러 주면 그 내용으로 만듭니다. **예시 파일을 그대로 복사하지 않습니다** — 실제 대상이 아닌 줄로 형식만 맞는 파일이 생기면 파일이 없을 때의 엄격한 판정이 풀립니다
- **두지 않는다** → 그대로 둡니다. 훅은 엄격한 판정으로 동작합니다

## 4. 결과 보고

세 파일의 상태 (있음 · 심링크 대상 · 없음) 와, `deploy-targets.md` 가 모델에 실리려면 전역 지시 파일에서 불러와야 한다는 점 (`@~/.config/claude/deploy-targets.md`) 을 알립니다. 전역 지시 파일은 이 명령이 고치지 않습니다.
