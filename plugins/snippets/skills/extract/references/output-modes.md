# Output Modes — 출력 모드 상세 동작

`/snippets:extract` Phase 7 (출력) 의 3 가지 모드 — `local` / `gist` / `push` — 의 정확한 동작 규칙. SKILL.md Phase 1 (소스 준비) 의 임시 디렉토리 cleanup 패턴도 본 문서 6 절에 정의한다.

---

## 1. 3 모드 비교

| 모드 | 기본 여부 | 조건 | 결과물 | 사용 시점 |
|------|----------|------|--------|-----------|
| `local` | ✅ 기본 | 없음 | 파일 시스템 디렉토리 | 일단 로컬에서 확인하고 싶을 때 |
| `gist` | — | `gh auth` 인증됨 | private gist URL | 동료 공유 / 임시 보관 / 단일 페이지 |
| `push` | — | target 이 git repo + remote 설정 | commit + push 결과 | dev-templates 같은 영구 저장소에 누적 |

선택: `--output local|gist|push` 옵션. 미지정 시 `local`.

---

## 2. `local` 모드

### 2-1. 디렉토리 구조
```
<target>/snippets/<category>/<subcategory>/<slug>/
├── README.md
├── <code-file-1>
├── <code-file-2>
└── ...
```

- `<target>` 우선순위: `--target` > `SNIPPETS_TARGET` > `~/code/portfolio/dev-templates`
- `<category>` / `<subcategory>`: `references/category-mapping.md` 매핑 표 기준
- `<slug>`: 본 문서 § 2-2

### 2-2. slug 규칙

1. 후보 chunk 의 "제목" 을 입력으로 받는다 (예: "Laravel Eloquent N+1 회피 패턴")
2. 한국어 → 영문 음차 (한글 토큰은 영어 단어로 매핑, 못 매핑하면 로마자 표기)
3. 소문자 + kebab-case (`laravel-eloquent-n1-prevention`)
4. 특수문자 제거, 연속 하이픈 단일화, 앞뒤 하이픈 제거
5. 최대 50 자

### 2-3. 코드 파일

- 단일 chunk 이고 단일 파일 출처면 `<original-filename>` 그대로 사용 (예: `useDebounce.ts`)
- 여러 파일에 걸친 chunk 면 `<slug>-<n>.<ext>` 형태로 번호 부여
- 원본의 import 경로 중 외부 모듈은 그대로 두고, 같은 프로젝트 내 상대 경로 import 는 README "주의사항" 에 의존성 사실 명시

---

## 3. `gist` 모드

### 3-1. 사전 조건
```bash
gh auth status
```

미인증이면 hard-fail: `[오류] gh auth 가 필요합니다. gh auth login 후 재시도하세요.`

### 3-2. 명령 조립

`local` 모드와 동일하게 임시 디렉토리에 파일을 생성한 뒤 `gh gist create` 로 업로드:

```bash
cd "<tmp-snippet-dir>"
gh gist create \
  README.md \
  <code-file-1> \
  <code-file-2> \
  --desc "<제목> — extracted by snippets-extract" \
  --private
```

- `--private` 이 기본 (보안 원칙). `--public` 은 명시적 옵션 시에만.
- multi-file 은 파일을 positional args 로 나열.
- `gh gist create` 의 stdout 마지막 줄이 gist URL.

### 3-3. URL 회수

```bash
GIST_URL=$(gh gist create ... 2>/dev/null | tail -1)
echo "Gist 생성: $GIST_URL"
```

### 3-4. local 디렉토리 보존

`gist` 모드여도 임시 작성 디렉토리는 `<target>/snippets/<category>/<...>/` 가 아닌 `mktemp -d` 경로에 만든다. 작업 종료 시 정리. `<target>` 은 건드리지 않는다.

---

## 4. `push` 모드

### 4-1. 사전 조건

다음 조건을 **모두** 만족할 때만 활성:

1. `<target>` 이 git 작업 트리
2. `git remote -v` 에 origin 또는 명시 remote 존재
3. working tree 가 clean (또는 사용자가 명시적 `--allow-dirty` 동의)

위반 시:
- (1) 미충족: push 비활성화 + 경고 `[안내] <target> 은 git repo 가 아닙니다. local 모드로 진행합니다.`
- (2) 미충족: 사용자 확인 후 local 폴백
- (3) 미충족: 작업 중지 + 사용자가 stash/commit 후 재시도 안내

### 4-2. 작업 흐름

```bash
cd "<target>"
git add "snippets/<category>/<subcategory>/<slug>"
git commit -m "$(cat <<'EOF'
snippets: <slug> 추가

<제목> — <출처-축약>

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
git push
```

### 4-3. 커밋 메시지 규칙

- 제목 줄: `snippets: <slug> 추가` (한국어, 50 자 이내)
- 본문: 1 줄 — 제목 + 출처 축약 (예: `Laravel Eloquent N+1 회피 패턴 — github.com/owner/repo`)
- Co-Authored-By 푸터 (글로벌 컨벤션 — `~/.dotfiles/claude/AGENTS.md` 의 commit-and-push 스킬 패턴)

### 4-4. 최종 확인

push 직전 AskUserQuestion 으로 한 번 더 확인:

```
다음 변경을 push 합니다:
  - 추가: snippets/<category>/<subcategory>/<slug>/ (N 개 파일)
  - 대상: <remote>/<branch>
계속할까요?
```

`--yes` 옵션 시 확인 생략.

### 4-5. 다중 snippet 처리

여러 snippet 을 한 번에 추출한 경우:
- 기본: snippet 하나당 commit 하나 (커밋 히스토리 가독성)
- `--squash` 옵션: 단일 커밋으로 묶기 — 메시지 `snippets: N 개 패턴 추가`

---

## 5. 멱등성 — 동일 slug 처리

`<target>/snippets/<category>/<subcategory>/<slug>/` 가 이미 존재하면 AskUserQuestion 으로 분기:

| 선택지 | 동작 |
|--------|------|
| 덮어쓰기 | 기존 디렉토리의 README + 코드 파일 모두 교체. 메타 푸터의 "추출일" 갱신. |
| `-v2` | `<slug>-v2/` (또는 `-v3`, `-v4`...) 로 별도 디렉토리 생성 |
| 건너뛰기 | 해당 snippet 만 추출 생략, 다른 후보는 계속 진행 |

메타 푸터의 출처 + line range 가 동일하면 "변경 없음 — 건너뜁니다" 자동 안내 (사용자에게 묻지 않음).

---

## 6. 임시 디렉토리 cleanup 패턴

GitHub URL 입력 시 SKILL.md Phase 1 에서 임시 디렉토리를 만든다. cleanup 은 이중 안전망:

### 6-1. trap (1차 안전망)
```bash
TMP=$(mktemp -d -t snippets-XXXX)
trap "rm -rf \"$TMP\"" EXIT INT TERM
gh repo clone "$URL" "$TMP" -- --depth 1 --filter=blob:none
# ... 작업 ...
```

Claude Code 는 매 Bash 호출이 신규 shell 이므로 trap 은 **해당 호출 내에서만** 보장된다.

### 6-2. Phase 8 명시적 rm (2차 안전망)
세션 변수 (`_workspace`) 로 TMP 경로를 추적하고, Phase 8 에서 명시적으로 정리:

```bash
rm -rf "$TMP"
ls /tmp/snippets-* 2>/dev/null && echo "[안내] 정리되지 않은 임시 디렉토리: ..."
```

### 6-3. 안전 가드

- TMP 경로는 반드시 `mktemp -d -t snippets-XXXX` 로 생성 (사용자 home / target 디렉토리 절대 금지)
- `rm -rf` 전에 경로 prefix 가 `/tmp/snippets-` 인지 검증

---

## 7. 에러 처리

| 단계 | 실패 | 동작 |
|------|------|------|
| gh clone | 네트워크 / 인증 실패 | 사용자에게 원인 표시 후 작업 중단 (cleanup 실행) |
| gitleaks | 실행 실패 | 폴백 안내 + 내장 regex 로 진행 |
| 카테고리 매핑 모호 | 분류 불가 | AskUserQuestion (후보 2 개) |
| README 생성 | Claude 응답 실패 | 해당 snippet 건너뛰기 + 결과 요약에 "생성 실패 1 건" |
| gist 업로드 | gh 실패 | local 디렉토리는 유지 + 오류 메시지 표시 |
| push | git push 실패 | local 산출물은 유지 + 사용자에게 충돌 / 권한 안내 |

원칙: **local 산출물은 항상 보존**. 후속 단계 실패가 앞 단계 결과를 파괴해서는 안 된다.
