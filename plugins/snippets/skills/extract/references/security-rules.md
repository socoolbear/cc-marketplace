# Security Rules — 보안 원칙 및 스캐닝 규칙

`/snippets:extract` 가 추출 과정에서 적용하는 보안 정책. SKILL.md Phase 2 (코드베이스 전체 1차 스캐닝) 와 Phase 5 (선택 chunk PII 정밀 2차) 가 이 문서를 단일 진실로 참조한다.

---

## 1. 개요 — 2 단계 스캐닝

| 단계 | 시점 | 범위 | 도구 |
|------|------|------|------|
| 1차 (Phase 2) | 입력 소스 준비 직후 | 코드베이스 전체 | `gitleaks` 우선, 미설치 시 내장 regex 폴백 |
| 2차 (Phase 5) | 사용자 선택 직후 | 선택된 chunk 만 | 내장 PII regex (이메일/전화/IP/카드+Luhn) |

1차는 "전체 차단 리스트" 를 만들고, 2차는 선택된 chunk 의 잔여 PII 를 정밀 검사한다. 1차에서 차단된 라인은 후보 리스트 자체에 노출되지 않는다.

---

## 2. 9 개 보안 원칙 (dev-templates 인용)

추출 결과는 다음 9 개를 위반하지 않아야 한다. 위반 감지 시 해당 chunk 는 자동 차단 또는 사용자 확인 후 차단된다.

1. 회사 코드 포함 금지
2. 회사 내부 설정 포함 금지
3. 실제 비밀번호 포함 금지
4. 실제 API Token 포함 금지
5. 실제 인증서 포함 금지
6. 특정 회사명 기반 설정 금지
7. 특정 회사 도메인 / IP 포함 금지
8. production credential 포함 금지
9. 고객 데이터 (PII) 포함 금지

원전: `/Users/socoolbear/code/portfolio/dev-templates/.prompts/01.md` "# 중요 원칙 / 보안 원칙" 절.

---

## 3. 외부 도구 통합 — `gitleaks`

### 가용성 체크
```bash
command -v gitleaks >/dev/null 2>&1
```

### 실행 명령
```bash
gitleaks detect \
  --source "<source-path>" \
  --no-git \
  --report-format json \
  --report-path "<tmp>/gitleaks-report.json" \
  --exit-code 0
```

- `--no-git`: git 히스토리가 아닌 디렉토리 트리 자체를 스캔
- `--exit-code 0`: 발견 시에도 종료 코드 0 (파싱 단계에서 결정)

### JSON 파싱 규칙
보고서 각 항목에서 다음 필드만 추출:
- `File` (상대 경로)
- `StartLine` / `EndLine`
- `RuleID` (어떤 규칙에 걸렸는지)
- `Match` (앞 10자 + `...` 마스킹 후 사용자에게 표시)

차단 리스트 구조: `{ file_path, start_line, end_line, rule_id }[]`.

---

## 4. 내장 regex 폴백 세트

`gitleaks` 미설치 또는 명시적 폴백 모드에서 다음 패턴을 사용한다. 라인 단위로 매칭, 첫 매치 발견 시 해당 라인 차단.

### Credential 패턴

| 종류 | 정규식 |
|------|--------|
| API key (generic) | `(?i)(api[_-]?key\|apikey\|access[_-]?token)['"\s:=]+['"]?[A-Za-z0-9_\-]{16,}` |
| AWS Access Key ID | `AKIA[0-9A-Z]{16}` |
| AWS Secret | `(?i)aws[_-]?secret[_-]?access[_-]?key['"\s:=]+['"]?[A-Za-z0-9/+=]{40}` |
| GCP Service Account | `"type":\s*"service_account"` |
| JWT | `eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+` |
| Private key | `-----BEGIN (RSA \|EC \|DSA \|OPENSSH )?PRIVATE KEY-----` |
| Password 변수 할당 | `(?i)(password\|passwd\|pwd)\s*[=:]\s*['"][^'"]{4,}['"]` |
| Slack token | `xox[baprs]-[A-Za-z0-9\-]{10,}` |
| GitHub token | `gh[pousr]_[A-Za-z0-9]{36,}` |

### PII 패턴 (Phase 5 2 차 검사 전용)

| 종류 | 정규식 | 후처리 |
|------|--------|--------|
| 이메일 | `[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}` | example.com / test.com / localhost 화이트리스트 |
| 한국 휴대전화 | `01[0-9][-\s]?[0-9]{3,4}[-\s]?[0-9]{4}` | 없음 |
| 공인 IP | `(?:\d{1,3}\.){3}\d{1,3}` | 사설 IP 화이트리스트 (§ 6) |
| 카드번호 후보 | `\b\d{13,19}\b` | Luhn 검증 통과 시에만 차단 (§ 7) |
| 주민등록번호 | `\b\d{6}[-\s]?[1-4]\d{6}\b` | 첫 6자리 날짜 패턴 검증 |

---

## 5. 회사명 blocklist

조직명 / 내부 식별자가 코드에 노출되는 사고를 막기 위한 단어 기반 차단 리스트.

### 기본값
```
opgg
```

### 사용자 확장
환경변수 `SNIPPETS_BLOCKLIST` 로 콤마 구분 추가:
```bash
export SNIPPETS_BLOCKLIST="opgg,internal,acme,foo"
```

### 매칭 규칙
- 대소문자 무시 (`re.IGNORECASE`)
- 단어 경계 적용 (`\b<token>\b`) — `opgg-internal` 은 매칭, `opggalaxy` 도 매칭, 일반 토큰 사이의 부분 매칭 방지
- 주석 / 문자열 / 식별자 모두 검사

매칭 시 1차에서는 자동 차단, 사용자가 `--allow-blocklist` 옵션을 명시한 경우만 후보로 유지 (확인 후 진행).

---

## 6. 사설 IP 화이트리스트

다음 대역의 IP 는 차단하지 않는다. 로컬 개발 예시에 흔히 등장하므로 제거하면 snippet 가치가 훼손된다.

| 대역 | 범위 |
|------|------|
| `10.0.0.0/8` | `10.*.*.*` |
| `172.16.0.0/12` | `172.16.*.*` ~ `172.31.*.*` |
| `192.168.0.0/16` | `192.168.*.*` |
| `127.0.0.0/8` | `127.*.*.*` (loopback) |
| `0.0.0.0` | bind-all |

화이트리스트에 속하지 않는 공인 IP 가 코드에 하드코딩되어 있으면 차단 후보로 분류.

---

## 7. Luhn 알고리즘 의사코드

카드번호 false positive 를 줄이기 위해 13~19 자리 숫자 시퀀스에 대해 Luhn 검증을 수행한다. 통과한 경우만 PII 차단.

```text
function luhn_check(digits):
    sum := 0
    alt := false
    for d in reverse(digits):
        n := int(d)
        if alt:
            n := n * 2
            if n > 9: n := n - 9
        sum := sum + n
        alt := not alt
    return sum % 10 == 0
```

검증 통과 + 16 자리이고 BIN (앞 6 자리) 가 알려진 카드사 prefix (4, 5, 34/37, 6011 등) 와 일치하면 신뢰도 높음.

---

## 8. 감지 → 처리 매트릭스

| 감지 항목 | 1차 (Phase 2) | 2차 (Phase 5) |
|-----------|---------------|---------------|
| credential (API key / AWS / GCP / JWT / Private key / password) | **block** (후보 노출 안 함) | block |
| 회사명 blocklist | **block** | block |
| 카드번호 (Luhn 통과) | block | block |
| 이메일 (화이트리스트 외) | warn-and-confirm | warn-and-confirm |
| 공인 IP (사설 외) | warn-and-confirm | warn-and-confirm |
| 한국 휴대전화 | warn-and-confirm | warn-and-confirm |
| 주민등록번호 | block | block |
| 사설 IP / loopback | pass | pass |

- **block**: 후보 리스트에 노출하지 않고 차단 카운터 증가
- **warn-and-confirm**: 후보 리스트에는 노출하되 추출 직전 사용자에게 (제외 / masking / 진행) AskUserQuestion
- **pass**: 통과

---

## 9. 폴백 정책 — `gitleaks` 미설치 시

스킬 시작 시 한 줄로 안내한다 (작업 차단 안 함):

```
[안내] gitleaks 미설치 — 내장 regex 폴백으로 진행합니다 (정확도 ↓). 설치: brew install gitleaks
```

추출된 모든 snippet 의 README.md 메타 푸터에는 스캐너 정보를 명시한다:

- gitleaks 사용 시: `> 스캐너: gitleaks v<version> + 내장 PII regex`
- 폴백 시: `> 스캐너: 내장 regex (gitleaks 미설치)`

이 표기는 향후 같은 snippet 을 재검토할 때 신뢰도를 빠르게 판단하는 단서다.
