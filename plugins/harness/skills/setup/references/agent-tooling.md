# Agent Tooling — 셸 도구 규약

에이전트가 셸 작업에서 더 좋은 결과를 내도록 도구 환경을 정렬하는 패턴.
지식 아키텍처, 기계적 강제, 4단계 파이프라인, 품질 추적과 함께 하네스 엔지니어링의 5번째 차원이다.

---

## 1. 원칙

### 왜 5번째 차원인가

OpenAI/Anthropic 의 하네스 엔지니어링은 "에이전트 주변 인프라가 결과 품질을 결정한다" 는 명제에서 출발한다. 기존 4개 차원에 더해 **에이전트가 셸 작업 시 어떤 도구를 사용하는가** 도 같은 명제의 직접적 적용이다.

| 차원 | 역할 |
|------|------|
| 지식 아키텍처 | 에이전트가 정확한 정보에 접근 |
| 기계적 강제 | 에이전트가 어길 수 없는 가드레일 |
| 4단계 파이프라인 | 에이전트의 추론 흐름 분리 |
| 품질 추적 | 에이전트 결과의 피드백 루프 |
| **agent-tooling** | **에이전트의 셸 작업 도구 품질** |

`grep` 대신 `rg` 는 검색 속도와 정확도를 향상시킨다. `gh --json` 강제는 Evaluator 의 자동 검증을 가능하게 만든다. `jq` 파이프라인은 결과 파싱을 결정론적으로 만든다. 이 차이가 파이프라인 성능에 직접 누적된다.

### 다루지 않는 것

- 도구 자체의 설치/관리 (사용자 환경 책임)
- IDE 설정, 셸 alias, 키바인딩 (개인 설정)
- 빌드/테스트/린트 명령 (4-stage-pipeline 의 플레이스홀더 소관)

---

## 2. 도구 그룹 분류 + 매핑 표

agent-tooling 이 권장하는 도구는 6개 그룹으로 분류한다. setup 시 `command -v` 로 감지하고, 설치된 것만 권한 등록한다.

### 코어 대체

| 도구 | 용도 | 대체 대상 | 설치 (macOS / Linux) |
|------|------|-----------|----------------------|
| ripgrep | 텍스트 검색 | `grep -r` | `brew install ripgrep` / `apt install ripgrep` |
| fd | 파일 탐색 | `find` | `brew install fd` / `apt install fd-find` |
| bat | 파일 출력 | `cat` | `brew install bat` / `apt install bat` |
| eza | 디렉터리 목록 | `ls` | `brew install eza` / `apt install eza` |
| zoxide | 디렉터리 이동 | `cd` | `brew install zoxide` / `apt install zoxide` |

### 검색 및 히스토리

| 도구 | 용도 | 설치 |
|------|------|------|
| fzf | 인터랙티브 검색 | `brew install fzf` |
| atuin | 셸 히스토리 동기화 | `brew install atuin` |

### 데이터 처리

| 도구 | 용도 | 설치 |
|------|------|------|
| jq | JSON 파싱 | `brew install jq` |
| yq | YAML 파싱 | `brew install yq` |
| httpie | HTTP 클라이언트 | `brew install httpie` |

### 코드 검색 및 품질

| 도구 | 용도 | 설치 |
|------|------|------|
| ast-grep | 구조 기반 코드 검색 | `brew install ast-grep` |
| difftastic | 구조 기반 diff | `brew install difftastic` |
| shellcheck | 셸 스크립트 린트 | `brew install shellcheck` |
| shfmt | 셸 포맷터 | `brew install shfmt` |
| ruff | Python 린트/포맷 | `brew install ruff` |

### Git 및 TUI

| 도구 | 용도 | 설치 |
|------|------|------|
| gh | GitHub CLI | `brew install gh` |
| git-delta | Git diff 뷰어 | `brew install git-delta` |
| lazygit | Git TUI | `brew install lazygit` |
| yazi | 파일 매니저 TUI | `brew install yazi` |

### 프롬프트

| 도구 | 용도 | 설치 |
|------|------|------|
| starship | 크로스셸 프롬프트 | `brew install starship` |

### 일괄 설치 (macOS 권장)

```bash
brew install ripgrep fd bat eza zoxide fzf atuin jq yq httpie \
             ast-grep difftastic shellcheck shfmt ruff \
             gh git-delta lazygit yazi starship
```

---

## 3. 도구 호출 방식

### Claude Code 빌트인 우선

에이전트는 셸을 호출하기 전에 Claude Code 빌트인 도구를 먼저 시도한다. 빌트인은 정확도, 안전성, 추적성 모두 셸 호출보다 우월하다.

| 작업 | 빌트인 (우선) | 셸 (대안) |
|------|---------------|-----------|
| 파일 읽기 | `Read` | `bat` 또는 `cat` |
| 파일 편집 | `Edit` / `Write` | `sed` / `awk` (금지) |
| 코드 검색 | `Grep` + `Glob` | `rg` (Bash 필요할 때만) |
| 파일 탐색 | `Glob` | `fd` (Bash 필요할 때만) |
| 디렉터리 트리 | (없음) | `eza --tree` |

빌트인이 표현 가능한 작업이면 셸로 떨어지지 않는다. 셸이 필요한 경우 (명령 실행, 파이프라인 등) 만 2절 매핑을 따른다.

### 외부 CLI 비대화형 강제

외부 CLI 는 항상 **비대화형 + 기계 판독 가능한 출력** 으로 호출한다. Evaluator 가 결과를 자동 검증할 수 있어야 한다.

| CLI | 강제 플래그 | 이유 |
|-----|-------------|------|
| gh | `--json {fields} --jq '...'` | 사람용 출력 파싱 금지 |
| npm / pnpm / yarn | `-y` 또는 `--yes` | 인터랙티브 프롬프트 차단 |
| 인스톨러 | `--quiet` 또는 동등 | 노이즈 제거 |
| 일반 CLI | `--format json` 또는 `--output json` | 결정론적 파싱 |

ast-grep 은 구조 기반 코드 검색이 필요한 모든 케이스에서 텍스트 정규식보다 우선한다 (리팩토링, 함수 호출 패턴 추적 등).

---

## 4. fallback 정책

도구가 미설치이거나 호출이 실패하는 케이스를 모두 **차단 없이** 처리한다.

### 케이스 1: 미설치 (`command not found`)

POSIX 기본 명령으로 자동 우회한다. 작업은 계속하고, 종료 시 1줄 보고만 남긴다.

| 권장 | 미설치 시 fallback |
|------|---------------------|
| `rg` | `grep -r` |
| `fd` | `find` |
| `bat` | `Read` 도구 또는 `cat` |
| `eza` | `ls` |
| `jq` | `python3 -c "import json,sys;..."` |
| `gh --json` | `git` + 사람용 텍스트 파싱 (최후 수단) |

### 케이스 2: 도구 0개 환경

setup Phase 1 의 도구 감지에서 핵심 도구 (rg, fd, jq) 가 모두 미설치인 경우, AskUserQuestion 으로 다음을 확인한다:

> 현대 CLI 도구가 감지되지 않습니다. agent-tooling 기능을 비활성화할까요? (Y/n)

거부 시 `.harness-version` 의 features 배열에서 `agent-tooling` 을 제외하고, `docs/conventions/cli-tooling.md` 작성과 권한 등록 단계를 모두 skip 한다.

### 케이스 3: PATH 미스 / 실행 실패

설치는 되어 있지만 PATH 에 없거나 실행이 실패한 경우, 1회 재시도 후 케이스 1 의 POSIX fallback 으로 우회한다. 작업을 절대 차단하지 않는다.

### 종료 시 보고 형식

```
[agent-tooling] 미설치 감지: rg, fd
권장: brew install ripgrep fd
```

---

## 5. 환경 분리 정책

agent-tooling 산출물은 **포터블 (repo 커밋)** 과 **머신별 (gitignore)** 두 영역으로 분리한다. 다른 머신에서 clone 받았을 때 환경 구성이 가능해야 한다.

| 산출물 | 위치 | 영역 | 내용 |
|--------|------|------|------|
| 권장 도구 목록 + 사용 규칙 | `docs/conventions/cli-tooling.md` | 포터블 (repo 커밋) | 2~4절 본문 (전체 목록 + 매핑 + fallback) |
| 도구 권한 | `.claude/settings.local.json` 의 `permissions.allow` | 머신별 (gitignore) | 설치된 도구만 `Bash(rg:*)` 형태 |
| 감지 결과 | `_workspace/analysis-report.md` | 머신별 (참조용) | Phase 1 의 `command -v` 결과 |

### 다른 머신에서 clone 했을 때

- `docs/conventions/cli-tooling.md` 가 설치 가이드 역할을 한다 (2절의 일괄 설치 명령)
- `.claude/settings.local.json` 은 없으므로 `/harness:audit` 실행으로 머신 환경에 맞게 재생성한다

### 권한 분담

setup, audit, update 가 각각 어느 영역을 만지는지의 권위적 정의는 `CONTRACTS.md` 7절 보호 매트릭스에 있다:

- `docs/conventions/cli-tooling.md` — setup 작성, audit 본문 보존, update PRISTINE 시 교체
- `.claude/settings.local.json` 의 `permissions.allow` 도구 권한 영역 — setup 추가, audit 환경 동기화, update 보존

상세는 → `../../../CONTRACTS.md` 7절.

---

## 6. 확장 정책

사용자가 새 도구를 설치하거나 기존 도구를 제거하면, agent-tooling 라이프사이클은 다음과 같이 동작한다.

### 새 도구 설치

```
brew install fzf       # 셋업 시 미설치였던 도구
/harness:audit         # 9번째 드리프트 영역이 환경 변화 감지
→ AskUserQuestion: "fzf 권한을 settings.local.json 에 추가하시겠습니까? (Y/n)"
→ Y: .claude/settings.local.json 에 Bash(fzf:*) 추가
→ docs/conventions/cli-tooling.md 본문 0 변경 (포터블 보장)
```

### 도구 제거

```
brew uninstall fd
/harness:audit
→ AskUserQuestion: "fd 권한을 settings.local.json 에서 제거하시겠습니까? (Y/n)"
→ Y: settings.local.json 에서 Bash(fd:*) 제거
→ 이후 generator 의 Bash 호출은 4절 fallback 정책에 따라 find 사용
```

### 권장 목록 자체 갱신

본 파일 (`references/agent-tooling.md`) 의 2~4절을 수정하고 harness 플러그인의 minor version 을 bump 한다. 이후 update 스킬이 PRISTINE 프로젝트의 `cli-tooling.md` 를 자동 동기화한다 (CUSTOMIZED 프로젝트는 차이 보고만).

---

## 7. 다른 references 및 CONTRACTS.md 와의 관계

### 권위 방향

- **본 파일**: 도구 목록 + 사용 규칙 + fallback 정책의 권위적 원천
- **CONTRACTS.md 7절**: 보호 매트릭스 (setup/audit/update 권한 분담) 의 권위적 원천
- **CONTRACTS.md 4절**: `.harness-version` features 배열 정의 (`agent-tooling` 키 포함)

### 다른 references 와의 관계

- `knowledge-architecture.md` 1절 — AGENTS.md 의 "셸 도구 규약" 한 줄 포인터 추가는 지도 원칙 정합
- `mechanical-enforcement.md` — 도구 권한 (`permissions.allow`) 은 settings.local.json 의 hooks 영역과 분리되어 충돌 없음
- `quality-tracking.md` — features 배열에 agent-tooling 추가, scores.json 영향 없음
- `failure-prevention.md` — 4절 fallback 정책이 도구 부재로 인한 실패를 자동 우회

### 참조 흐름

```
setup/SKILL.md
  → references/agent-tooling.md (본 파일, 권위적 원천)
  → CONTRACTS.md 7절 (권한 분담)

audit/SKILL.md
  → references/drift-patterns.md 9절 (본 파일 6절 확장 정책 구체화)
  → CONTRACTS.md 7절

update/SKILL.md
  → references/version-manifest.md 8절 (v1.3 → v1.4 차이)
  → references/sync-rules.md (cli-tooling.md PRISTINE/CUSTOMIZED 정책)
  → CONTRACTS.md 7절
```
