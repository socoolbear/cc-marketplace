---
name: snippets-extract
description: "코드베이스에서 재사용 가능한 snippet 을 추출하는 스킬. 로컬 경로 또는 GitHub URL 을 입력으로 받아 (1) 함수·클래스 단위 chunk 분석 → snippet 후보 자동 리스트업, (2) 사용자 선택 → 2 단계 보안 스캐닝 (gitleaks + 내장 PII regex / Luhn / 회사명 blocklist), (3) README + 코드 디렉토리 wrapping (목적·사용 상황·기술 스택·주의사항·예시 5 섹션 + 메타 푸터), (4) local 파일 / private GitHub Gist / repo push 중 선택해 출력. dev-templates 의 snippets/<backend|frontend|infra|ai|public-candidates> 카테고리 구조에 자동 배치. '스니펫 추출', 'snippet 만들기', 'snippet 만들어줘', '코드 패턴 자산화', '재사용 snippet 추출', 'code snippet 생성', '코드 조각 정리', 'extract snippet', '저장소에서 snippet 뽑기' 요청 시 사용. 보유 코드를 dev-templates 같은 개인 자산 저장소로 옮기는 작업이 필요할 때 활용."
---

# Snippets Extract — 코드베이스에서 재사용 가능한 snippet 추출

이 스킬은 사용자가 다년간 작업한 프로젝트 / 외부 GitHub repo 에서 **재사용 가능한 코드 패턴** 을 발굴하여 `dev-templates` 같은 개인 자산 저장소에 표준화된 형태로 옮긴다. 입력은 로컬 경로 또는 GitHub URL, 출력은 `README.md + 코드 파일` 디렉토리이며 local / private gist / repo push 중 선택해 저장한다.

**전제**: 추출 과정에서 회사 코드 / credential / PII 가 섞일 위험이 항상 존재한다. 따라서 2 단계 보안 스캐닝 (`gitleaks` + 내장 regex / Luhn) 을 거치고, 후보를 자동 일괄 추출하지 않고 **반드시 사용자 검토 단계** 를 둔다. 출처는 기본 포함이며 `--no-source` 로 옵트아웃 가능하다.

---

## 적용하지 않는 것

- `prompts/`, `workflows/`, `docker/`, `scripts/`, `docs/` 추출 — 별도 후속 스킬 영역
- 추출된 코드의 자동 테스트 / 실행 검증
- 라이센스 자동 부여 (사용자가 README 에 명시)
- tree-sitter 기반 정밀 AST chunking — Claude 가 코드를 직접 읽고 `rg` 휴리스틱과 결합해 chunk 경계 식별
- 한국어 외 출력 언어 (영어 README 옵션 등)

---

## 호출 형식

```
/snippets:extract [<path-or-url>] [--target <repo>] [--output local|gist|push] [--no-source] [--yes]
```

| 옵션 | 의미 | 기본값 |
|------|------|--------|
| `<path-or-url>` | 로컬 디렉토리 절대 경로 또는 GitHub URL | 미지정 시 AskUserQuestion |
| `--target <repo>` | 출력 대상 저장소 경로 | `SNIPPETS_TARGET` 또는 `~/code/portfolio/dev-templates` |
| `--output` | 출력 모드 | `local` |
| `--no-source` | README 메타 푸터에서 "출처" 라인 제거 | off |
| `--yes` | push 모드 최종 확인 생략 | off |

GitHub URL 형식: `https://github.com/<owner>/<repo>`, `git@github.com:<owner>/<repo>.git`, `<owner>/<repo>` (단축).

---

## Phase 0: 입력 검증 & 환경 준비

### 0-1. 인자 파싱

위 호출 형식에 따라 파싱한다. `<path-or-url>` 미지정 시:

```
> "어떤 프로젝트에서 snippet 을 추출할까요?
> - 로컬 경로 (예: /Users/me/code/some-project)
> - GitHub URL (예: https://github.com/owner/repo 또는 owner/repo)"
```

AskUserQuestion 으로 받는다.

### 0-2. 외부 도구 가용성 체크

| 도구 | 필수도 | 미설치 시 동작 |
|------|--------|----------------|
| `gh` | 필수 (GitHub URL 입력 시) | hard-fail — 설치 안내 후 중단 |
| `git` | 필수 | hard-fail |
| `gitleaks` | 권장 | 한 줄 경고 + 내장 regex 폴백 |
| `rg` (ripgrep) | 권장 | `grep -r` 폴백 |
| `fd` | 권장 | `find` 폴백 |

체크 명령:
```bash
command -v gh git gitleaks rg fd 2>/dev/null
```

gitleaks 폴백 안내 메시지:
```
[안내] gitleaks 미설치 — 내장 regex 폴백으로 진행합니다 (정확도 ↓). 설치: brew install gitleaks
```

### 0-3. target repo 결정

우선순위:
1. `--target <repo>` 옵션
2. 환경변수 `SNIPPETS_TARGET`
3. 기본값 `~/code/portfolio/dev-templates`

결정된 경로로 AskUserQuestion 재확인 (보안 가드):

```
> "출력 대상은 <resolved-path> 입니다. 계속할까요?
> - 예 (이대로 진행)
> - 아니오 (다른 경로 입력)"
```

### 0-4. target 사전 검사

| 상태 | 동작 |
|------|------|
| 미존재 | "생성할까요?" AskUserQuestion → `mkdir -p <target>/snippets` |
| 존재 + git repo | push 모드 활성 |
| 존재 + 일반 디렉토리 | push 모드 자동 비활성, `[안내] git repo 가 아닙니다. local / gist 모드만 사용 가능합니다.` |

또한 working tree dirty (`git status --porcelain`) 면 push 모드는 사용자 확인 후 진행 (또는 local 폴백).

---

## Phase 1: 소스 준비

### 1-1. 로컬 경로

입력이 로컬 경로면 `SOURCE=<path>` 로 그대로 사용한다. cleanup 불필요.

### 1-2. GitHub URL

`gh auth status` 로 인증 확인. private repo 인데 미인증이면 사용자에게 `gh auth login` 안내 후 중단.

임시 디렉토리에 shallow clone:

```bash
TMP=$(mktemp -d -t snippets-XXXX)
trap "rm -rf \"$TMP\"" EXIT INT TERM
gh repo clone "<url>" "$TMP" -- --depth 1 --filter=blob:none
SOURCE="$TMP"
```

세션 변수로 `$TMP` 추적. Phase 8 에서 명시적으로 정리한다.

상세 → `references/output-modes.md` 6 절

---

## Phase 2: 1 차 보안 스캐닝 (코드베이스 전체)

### 2-1. gitleaks 실행

```bash
gitleaks detect \
  --source "$SOURCE" \
  --no-git \
  --report-format json \
  --report-path "$TMP/gitleaks-report.json" \
  --exit-code 0
```

JSON 보고서를 파싱해 차단 리스트 생성:
```json
[{ "file": "<rel-path>", "start_line": N, "end_line": M, "rule_id": "<id>" }, ...]
```

### 2-2. 폴백 — 내장 regex

`gitleaks` 미설치 또는 실행 실패 시 내장 regex 세트를 `rg` 로 적용:

```bash
rg --json -e '<regex>' "$SOURCE"
```

각 매치를 차단 리스트에 추가.

### 2-3. 회사명 blocklist 적용

`SNIPPETS_BLOCKLIST` 환경변수 (기본 `opgg`) 의 토큰을 `\b<token>\b` 패턴으로 검사:

```bash
TOKENS="${SNIPPETS_BLOCKLIST:-opgg}"
for tok in $(echo "$TOKENS" | tr ',' ' '); do
  rg -i --json -e "\b${tok}\b" "$SOURCE"
done
```

상세 → `references/security-rules.md`

---

## Phase 3: 코드 분석 & 후보 추출

### 3-1. 파일 트리 스캔

다음 디렉토리 / 패턴은 제외:

```
node_modules/  vendor/  dist/  build/  .git/  .next/  .nuxt/  target/  out/
__pycache__/   *.min.js  *.min.css  *.lock  *.snap
```

테스트 디렉토리 (`__tests__/`, `*.test.*`, `*.spec.*`, `tests/`) 도 1 차 범위에서 제외 (테스트는 별도 후속 스킬).

### 3-2. 후보 chunk 추출

`rg` 로 정의문 1 차 후보:

```bash
rg --json -t ts -t js -t php -t py \
  -e '^(export\s+)?(async\s+)?function\s+\w+' \
  -e '^(export\s+)?class\s+\w+' \
  -e '^(export\s+)?interface\s+\w+' \
  -e '^(export\s+)?type\s+\w+\s*=' \
  -e '^const\s+\w+\s*=\s*(\(|async\s*\(|function)' \
  "$SOURCE"
```

infra / 설정 파일은 파일 단위 후보 (Dockerfile, `*.yml`, `nginx.conf`, `*.tf` 등).

각 후보에 대해 Claude 가 다음을 수행:
1. **chunk 경계 식별** — 정의문 시작 ~ 닫는 괄호 / 다음 정의 직전
2. **메타데이터 부여**:
   - `title` (한국어 명사구, 30 자 이내)
   - `description` (1~2 문장)
   - `category` / `subcategory` (`references/category-mapping.md` 매핑)
   - `language`
   - `file`, `start_line`, `end_line`
   - `dependencies` (import / require 목록)

### 3-3. 필터링

| 규칙 | 처리 |
|------|------|
| 10 줄 미만 | 제외 (보통 trivial) |
| 200 줄 초과 | 후보 유지 + "분할 후보" 표기 (Phase 4 에서 사용자 분할 결정) |
| 차단 리스트와 line range 겹침 | 자동 제외, 카운터 증가 |
| 같은 함수의 중복 정의 | dedup |

상세 → `references/category-mapping.md`

---

## Phase 4: 후보 제시 & 사용자 선택

### 4-1. 표 출력

```
# | 카테고리              | 제목                          | 파일:lines           | 한 줄 요약
--|----------------------|------------------------------|---------------------|-----------------
1 | frontend/react       | 디바운스 hook                  | hooks/useDebounce.ts:1-22  | 입력 폭주를 setTimeout 으로 억제
2 | backend/laravel      | Eloquent N+1 회피 패턴         | app/Models/User.php:45-78  | with() 로 lazy load 차단
3 | infra/nginx          | prefix 제거 rewrite            | nginx/default.conf:12-40   | /abc/* → /* try_files
...
```

차단된 항목 카운트도 한 줄로 안내 (`[안내] 보안 스캐닝으로 N 개 chunk 가 후보에서 제외되었습니다.`).

### 4-2. 선택 받기

AskUserQuestion 으로 번호 / 전체선택 / 전체거부 / 재분석 중 선택. 카테고리가 모호한 chunk 는 별도 질문으로 분류 확정.

```
> "추출할 항목을 선택해주세요:
> - 번호 입력 (예: 1, 3, 5)
> - 전체 선택
> - 전체 거부 (작업 중단)
> - 재분석 (제외 패턴 조정 후 다시)"
```

### 4-3. 카테고리 수정

선택된 chunk 의 카테고리가 모호 매핑 (예: `frontend/nextjs` vs `backend/node` Server Component) 인 경우 사용자에게 확인. 명시 결정은 세션 캐시.

---

## Phase 5: 2 차 PII 스캐닝 (선택 chunk 정밀)

선택된 chunk 만 대상으로 PII regex 적용:

| 항목 | 차단 / 확인 |
|------|-------------|
| 이메일 (`example.com` / `test.com` / `localhost` 외) | warn-and-confirm |
| 한국 휴대전화 | warn-and-confirm |
| 공인 IP (사설 화이트리스트 외) | warn-and-confirm |
| 카드번호 (Luhn 통과) | block |
| 주민등록번호 | block |

warn-and-confirm 시 AskUserQuestion:
```
> "<file>:<line> 에서 PII 가 발견되었습니다: <masked-preview>
> - 제외 (이 chunk 추출 안 함)
> - masking 후 추출 (해당 토큰을 <MASKED> 로 치환)
> - 그대로 진행 (사용자 책임)"
```

상세 → `references/security-rules.md` 4 절 / 7 절

---

## Phase 6: README 생성 & Wrapping

### 6-1. 디렉토리 결정

```
<target>/snippets/<category>/<subcategory>/<slug>/
```

`<slug>` 규칙 (kebab-case, 한글 음차, 50 자 이내) → `references/output-modes.md` 2-2 절

### 6-2. 멱등성 처리

같은 slug 가 이미 존재하면 AskUserQuestion:

```
> "<slug> 가 이미 존재합니다. 어떻게 할까요?
> - 덮어쓰기 (기존 파일 교체, 추출일 갱신)
> - -v2 (별도 디렉토리)
> - 건너뛰기"
```

출처 + line range 가 동일하면 묻지 않고 "변경 없음 — 건너뜁니다" 자동 처리.

### 6-3. README.md 자동 생성

5 개 섹션 (목적 / 사용 상황 / 기술 스택 / 주의사항 / 예시) + 메타 푸터.

- 기술 스택은 manifest (`package.json`, `composer.json`, `requirements.txt`) 와 import 를 교차 검증
- 주의사항은 환경변수 / 네트워크 / 파일 I/O / 보안 스캐닝 결과를 자동 점검
- 메타 푸터: 출처 (GitHub 입력 시 SHA + line 앵커 포함), 추출일, 스캐너 버전
- `--no-source` 옵션 시 출처 라인만 제거 (추출일 / 스캐너는 유지)

상세 → `references/readme-template.md`

### 6-4. 코드 파일 복사

원본 파일에서 chunk 의 line range 를 잘라낸 결과를 `<original-filename>` 으로 저장. 여러 파일에 걸친 chunk 면 `<slug>-<n>.<ext>` 번호 부여. PII masking 결정이 있으면 해당 라인을 치환 후 저장.

---

## Phase 7: 출력

### 7-1. `local` (기본)

Phase 6 작성 결과를 그대로 둔다. 추가 작업 없음.

### 7-2. `gist`

```bash
cd "<snippet-dir>"
GIST_URL=$(gh gist create README.md <code-files...> \
  --desc "<제목> — extracted by snippets-extract" \
  --private 2>/dev/null | tail -1)
echo "Gist: $GIST_URL"
```

`<target>` 의 local 디렉토리는 건드리지 않는다 (별도 임시 디렉토리에서 업로드).

### 7-3. `push`

사전 조건 (working tree clean, remote 존재) 확인 후:

```bash
cd "<target>"
git add "snippets/<category>/<subcategory>/<slug>"
```

`--yes` 옵션이 아니면 최종 확인:
```
> "다음 변경을 push 합니다:
>   - 추가: snippets/<category>/<subcategory>/<slug>/ (N 개 파일)
>   - 대상: <remote>/<branch>
> 계속할까요?"
```

커밋 + push (HEREDOC 으로 본문):
```bash
git commit -m "$(cat <<'EOF'
snippets: <slug> 추가

<제목> — <출처-축약>

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
git push
```

다중 snippet 추출이고 `--squash` 옵션이 아니면 snippet 당 별도 commit.

상세 → `references/output-modes.md` 2~4 절

---

## Phase 8: Cleanup & 요약

### 8-1. 임시 디렉토리 정리

GitHub URL 입력으로 만든 `$TMP` 가 있으면 명시적으로 제거:

```bash
[ -n "$TMP" ] && [ -d "$TMP" ] && [[ "$TMP" == /tmp/snippets-* ]] && rm -rf "$TMP"
```

`$TMP` 가 `/tmp/snippets-` prefix 가 아니면 안전 가드로 삭제 거부.

### 8-2. 결과 요약

```
=== 추출 완료 ===
- 후보 분석: <total> 건
- 보안 차단: <blocked> 건 (1 차 <p2>, PII <p5>)
- 추출 성공: <extracted> 건
- 출력 위치: <target>/snippets/...
- 출력 모드: <mode>
- (gist 모드) Gist URL: <url>
- (push 모드) 커밋: <sha>
```

---

## 산출물 체크리스트

- [ ] `<target>/snippets/<category>/<subcategory>/<slug>/README.md` (선택된 후보별)
- [ ] `<target>/snippets/<category>/<subcategory>/<slug>/<code-files>` (선택된 후보별)
- [ ] 결과 요약 콘솔 출력 (Phase 8-2)
- [ ] 임시 디렉토리 정리 확인 (`ls /tmp/snippets-*` 결과 없음)
- (gist 모드) gist URL 콘솔 표시
- (push 모드) 한국어 커밋 메시지 + push 성공

---

## 참고

- 보안 원칙 + regex 세트 + Luhn: `references/security-rules.md`
- 카테고리 매핑 (backend / frontend / infra / ai): `references/category-mapping.md`
- README 5 섹션 템플릿 + 메타 푸터: `references/readme-template.md`
- 출력 모드 상세 (local / gist / push) + cleanup: `references/output-modes.md`
