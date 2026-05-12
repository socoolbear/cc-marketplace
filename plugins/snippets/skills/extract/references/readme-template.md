# README Template — snippet 디렉토리 README.md 작성 규칙

`/snippets:extract` Phase 6 (Wrapping) 에서 각 snippet 디렉토리에 자동 생성되는 `README.md` 의 표준 형식. 본 문서는 단일 진실이며 SKILL.md Phase 6 가 참조한다.

---

## 1. 5 개 섹션 강제 + 메타 푸터

모든 snippet README 는 다음 순서를 따른다:

```markdown
# <제목>

## 목적
## 사용 상황
## 기술 스택
## 주의사항
## 예시

---
> 출처: <원본 path or URL> (line N~M)
> 추출일: 2026-MM-DD
> 스캐너: gitleaks v<x.y.z> + 내장 PII regex  (or "내장 regex 폴백")
```

섹션 제목과 순서는 변경 금지. `--no-source` 옵션이 켜진 경우 메타 푸터의 "출처" 라인만 제거한다 (다른 메타는 유지).

---

## 2. 섹션별 작성 지침

### 2-1. 제목 (`# <제목>`)
- 한국어 명사구 우선, 영문 약어는 그대로 (예: `# Laravel Eloquent N+1 회피 패턴`)
- 30 자 이내
- chunk 의 함수명 / 클래스명을 그대로 쓰지 말고, **의도** 를 표현 (예: `useDebounce` → "디바운스 hook")

### 2-2. 목적
- 1~2 문장
- "**무엇을 해결하는가**" 가 핵심. 코드 동작 설명 금지 (그건 예시 섹션이 함).
- 평어체 (~다 종결)

### 2-3. 사용 상황
- bullet 3~5 개
- "**이 패턴을 언제 꺼내쓰면 좋은가**" 관점
- 안티 패턴 / 부적합 상황도 1 줄 포함 권장

### 2-4. 기술 스택
- 다음 4 개 항목 — 해당사항 없으면 "—" 표기

```markdown
- 언어: TypeScript 5+
- 프레임워크: Next.js 14 App Router
- 주요 의존성: zod ^3, react ^18
- 외부 도구: 없음
```

### 2-5. 주의사항
- bullet 2~5 개
- 다음을 반드시 포함하라:
  - 보안 스캐닝 결과 (감지된 PII 가 masking 됐다면 그 사실)
  - 외부 의존성 (env, 인증, 네트워크)
  - 한계 / 알려진 엣지케이스
- 발견된 보안 이슈가 0 건이면 `- 보안 스캐닝 통과 (이슈 없음)` 한 줄.

### 2-6. 예시
- `import` 또는 `require` 1 줄 + 호출 시그니처 + 짧은 호출 예시 (3~10 줄)
- 코드 펜스에 언어 명시 (` ```ts `, ` ```bash `)
- 주변 컨텍스트 (호출자) 가 충분히 명확하면 1 개 예시, 아니면 2 개

---

## 3. "기술 스택" 자동 추출 규칙

Phase 6 에서 chunk 와 주변 컨텍스트로부터 다음을 추론한다:

| 항목 | 신호원 |
|------|--------|
| 언어 | 파일 확장자 + shebang + frontmatter |
| 프레임워크 | import 경로 (예: `from "next/..."` → Next.js), config 파일 (`next.config.*`) |
| 주요 의존성 | `package.json` / `composer.json` / `requirements.txt` 의 의존성 중 chunk 가 직접 import 한 것 |
| 외부 도구 | shell 명령 호출 (`docker`, `gh`, `aws`), 환경변수 (`process.env.X`) |

`package.json` 등 manifest 가 없으면 "—" 처리. 추측 금지 (false 정보 방지).

---

## 4. "주의사항" 자동 생성 신호

Claude 가 chunk 를 분석할 때 자동으로 다음을 점검하여 주의사항에 반영:

- 환경변수 의존 → `- 환경변수 \`X\` 필요`
- 네트워크 호출 → `- 외부 HTTP 호출 (도메인: <host>) — rate limit / 인증 토큰 확인`
- 파일 I/O → `- 파일 시스템 쓰기 (경로: <path>) — 권한 확인`
- 에러 처리 누락 → `- 에러 처리 명시되지 않음 — 호출자 측 try/catch 권장`
- 동시성 우려 → `- 동시 호출 시 race condition 가능 — lock 또는 mutex 검토`

스캐너 결과:
- 보안 이슈 0 건: `- 보안 스캐닝 통과 (이슈 없음)`
- masking 된 PII 가 있음: `- PII <N> 건이 \`<MASKED>\` 로 치환됨 (원본 컨텍스트는 추출 단계에서 제거)`
- block 된 chunk 가 있음: 해당 chunk 는 출력 자체가 없으므로 README 에 별도 표기 안 함 (결과 요약에만 카운트)

---

## 5. "예시" 작성 규칙

코드 펜스의 언어 토큰은 반드시 명시:

| 확장자 | 토큰 |
|--------|------|
| `.ts`, `.tsx` | `ts` |
| `.js`, `.jsx` | `js` |
| `.php` | `php` |
| `.py` | `python` |
| `.sh`, `.bash` | `bash` |
| `.yml`, `.yaml` | `yaml` |
| `.tf` | `hcl` |
| Dockerfile | `dockerfile` |
| nginx | `nginx` |

호출 예시는 **실행 가능한 형태** 를 우선 — placeholder 는 `<...>` 로 명시:

```ts
import { useDebounce } from "./useDebounce";

const debounced = useDebounce(value, 300);
```

---

## 6. 메타 푸터

```markdown
---
> 출처: https://github.com/owner/repo/blob/<sha>/<path>#L<start>-L<end>
> 추출일: 2026-05-12
> 스캐너: gitleaks v8.18.0 + 내장 PII regex
```

- 출처는 GitHub URL 입력 시 가능하면 commit SHA + line 앵커까지 포함 (영구 링크)
- 로컬 경로 입력 시: `> 출처: ~/code/portfolio/<repo>/<path> (line 10~45)`
- `--no-source` 옵션 시 "출처" 라인만 제거. 추출일 / 스캐너는 유지.

---

## 7. 한국어 톤 가이드

| 영역 | 톤 |
|------|-----|
| README 본문 | 평어체 (~다 종결, 개조식) |
| 코드 주석 | 원본 유지 (영어면 영어, 한국어면 한국어) |
| 코드 식별자 | 변경 금지 |
| 영한 혼용 | 띄어쓰기 (예: "Makefile 에서") |

평어체 예:
- ✅ `디바운스로 입력 폭주를 제어한다.`
- ❌ `디바운스로 입력 폭주를 제어합니다.`
- ❌ `디바운스로 입력 폭주를 제어함.` (지나친 명사화)
