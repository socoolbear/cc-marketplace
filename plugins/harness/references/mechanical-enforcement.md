# 기계적 강제 패턴

아키텍처 불변 조건을 문서가 아닌 코드와 도구로 강제하는 패턴.
문서에만 의존하면 드리프트가 발생한다. 코드로 강제하면 위반이 즉시 드러난다.

---

## 1. 원칙

### 왜 기계적 강제인가

**OpenAI: "불변 조건을 강제하되 구현을 세세하게 관리하지 않음"**

문서 기반 규칙의 한계:
- 에이전트가 긴 문서의 특정 규칙을 **누락** 할 수 있다
- 프로젝트가 커질수록 문서와 코드 사이의 **드리프트** 가 발생한다
- 위반을 사후에 발견하면 수정 비용이 높아진다

기계적 강제의 장점:
- 위반이 **즉시** 드러난다 (코딩 중에)
- 에러 메시지에 **수정 방법을 삽입** 하면 에이전트 컨텍스트에 즉시 주입된다
- 문서를 읽지 않아도 규칙을 따르게 된다

### 에러 메시지 설계 원칙

에러 메시지는 에이전트의 컨텍스트에 직접 들어간다.
따라서 에러 메시지 자체에 수정 방법을 포함해야 한다:

```
ERROR: 레이어 위반 — src/types/foo.ts
       types/ 가 core/ 를 import 합니다.
       types/ 가 import 할 수 있는 레이어: (없음)
       수정: 공유 로직은 types/ 로 이동하세요.
       규칙: docs/architecture.md#레이어-구조
```

**필수 요소:**
1. 위반 위치 (파일 경로 + 행 번호)
2. 규칙 설명 (어떤 규칙이 위반되었는지)
3. 수정 방법 (구체적인 행동 지시)
4. 규칙 문서 링크 (심화 정보)

---

## 2. 레이어 경계 검사 스크립트 설계

`scripts/check-layer-import.js` 의 설계 패턴.

### 2-1. DAG 정의

레이어 이름과 허용 import 목록을 코드 상단에 선언한다:

```javascript
// docs/architecture.md 의 레이어 구조와 동기화할 것
const LAYER_DAG = {
  'types':      [],                    // 최하위: 아무것도 import 불가
  'core':       ['types'],             // types 만 import 가능
  'adapters':   ['types', 'core'],     // types + core
  'components': ['types', 'core', 'adapters'],
  'app':        ['types', 'core', 'adapters', 'components'],
};
```

### 2-2. import/require 정적 분석

정규식 기반으로 import 문을 추출한다:

```javascript
// ES import
const ES_IMPORT = /import\s+.*?\s+from\s+['"]([^'"]+)['"]/g;
// require
const REQUIRE = /require\s*\(\s*['"]([^'"]+)['"]\s*\)/g;
// dynamic import
const DYNAMIC_IMPORT = /import\s*\(\s*['"]([^'"]+)['"]\s*\)/g;
```

### 2-3. 상대 경로 → 레이어 매핑

```javascript
function resolveLayer(filePath) {
  // src/core/utils.ts → 'core'
  // src/types/game.ts → 'types'
  const relative = path.relative(SRC_ROOT, filePath);
  const firstSegment = relative.split(path.sep)[0];

  if (!LAYER_DAG[firstSegment]) {
    return null; // src/ 바로 아래가 아닌 파일은 검사 대상 아님
  }

  return firstSegment;
}
```

### 2-4. 에러 메시지 형식

```javascript
function formatViolation(filePath, line, importedLayer, currentLayer) {
  const allowed = LAYER_DAG[currentLayer].join(', ') || '(없음)';

  return [
    `ERROR: 레이어 위반 — ${filePath}:${line}`,
    `       ${currentLayer}/ 가 ${importedLayer}/ 를 import 합니다.`,
    `       ${currentLayer}/ 가 import 할 수 있는 레이어: ${allowed}`,
    `       수정: 해당 import 를 제거하거나, 공유 로직을 허용된 레이어로 이동하세요.`,
    `       규칙: docs/architecture.md#레이어-구조`,
  ].join('\n');
}
```

### 2-5. 실행 모드

**단일 파일 모드** (Hook 에서 사용):
```bash
node scripts/check-layer-import.js src/core/utils.ts
```

**전체 스캔 모드** (CI 또는 수동 검증):
```bash
node scripts/check-layer-import.js
# 인자 없으면 src/ 전체 스캔
```

---

## 3. Claude Code Hook 설정

### PostToolUse Hook

`.claude/settings.local.json` 템플릿:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "command": "if echo \"$CLAUDE_FILE_PATH\" | grep -q '^src/'; then node scripts/check-layer-import.js \"$CLAUDE_FILE_PATH\" || true; fi"
      }
    ]
  }
}
```

### 설계 결정

| 결정 | 이유 |
|------|------|
| `PostToolUse` 시점 | 파일 수정 직후에 검사하여 즉각적 피드백 제공 |
| `Edit\|Write` 매칭 | 파일을 변경하는 도구에만 적용 |
| `src/` 하위만 대상 | 설정 파일, 문서 등은 검사 대상이 아님 |
| `\|\| true` | 경고만 출력하고 에이전트 실행을 차단하지 않음 |

### 왜 경고만 하는가

차단하면 에이전트가 중간 상태에서 멈출 수 있다.
경고만 출력하면 에이전트는 경고를 컨텍스트에서 읽고 **자발적으로** 수정한다.
에러 메시지에 수정 방법이 포함되어 있으므로 추가 문서 참조 없이 즉시 수정 가능하다.

---

## 4. ESLint 통합 (선택적)

프로젝트에 ESLint 가 이미 설정되어 있다면 `eslint-plugin-boundaries` 를 활용할 수 있다.

### 설정 예시

```javascript
// .eslintrc.js (관련 부분)
module.exports = {
  plugins: ['boundaries'],
  settings: {
    'boundaries/elements': [
      { type: 'types',      pattern: 'src/types/*' },
      { type: 'core',       pattern: 'src/core/*' },
      { type: 'adapters',   pattern: 'src/adapters/*' },
      { type: 'components', pattern: 'src/components/*' },
      { type: 'app',        pattern: 'src/app/*' },
    ],
  },
  rules: {
    'boundaries/element-types': [
      'error',
      {
        default: 'disallow',
        rules: [
          { from: 'core',       allow: ['types'] },
          { from: 'adapters',   allow: ['types', 'core'] },
          { from: 'components', allow: ['types', 'core', 'adapters'] },
          { from: 'app',        allow: ['types', 'core', 'adapters', 'components'] },
        ],
      },
    ],
  },
};
```

### 커스텀 메시지

```javascript
// 기본 에러 메시지 대신 수정 방법을 포함한 메시지 설정
'boundaries/element-types': ['error', {
  default: 'disallow',
  message: '${file.type} 레이어가 ${dependency.type} 를 import 할 수 없습니다. docs/architecture.md 를 참조하세요.',
  // ...rules
}],
```

---

## 5. 금지 의존성 검사

레이어 경계 외에, 특정 패키지의 사용 위치를 제한하는 검사.

### 대표 패턴

| 금지 규칙 | 이유 |
|-----------|------|
| `core/` 에서 React import 금지 | 프레임워크 독립성 유지 |
| `types/` 에서 런타임 패키지 import 금지 | 타입 레이어 순수성 유지 |
| `src/` 에서 `apps/web` 직접 import 금지 | 모노레포 경계 위반 방지 |

### 검사 로직

```javascript
const FORBIDDEN_IMPORTS = [
  {
    layer: 'core',
    pattern: /from\s+['"]react['"]/,
    message: 'core/ 에서 React 를 직접 import 하지 마세요. UI 로직은 components/ 에 작성하세요.',
  },
  {
    layer: 'types',
    pattern: /from\s+['"](?!\.)[^'"]*['"]/,  // 외부 패키지 import
    message: 'types/ 는 순수 타입만 포함해야 합니다. 런타임 패키지를 import 하지 마세요.',
  },
];
```

---

## 6. 컨벤션 검사

코드 스타일과 구조적 컨벤션을 검사하는 추가 규칙.

### 파일명 kebab-case 검사

```javascript
function checkFileNaming(filePath) {
  const fileName = path.basename(filePath, path.extname(filePath));
  const isKebab = /^[a-z][a-z0-9]*(-[a-z0-9]+)*$/.test(fileName);

  if (!isKebab) {
    return `WARNING: 파일명이 kebab-case 가 아닙니다 — ${filePath}\n`
         + `         수정: ${toKebabCase(fileName)} 으로 변경하세요.`;
  }

  return null;
}
```

### 배럴 export 검사

각 레이어 디렉터리에 `index.ts` (배럴 파일) 가 존재하는지 확인:

```javascript
function checkBarrelExport(layerDir) {
  const indexPath = path.join(layerDir, 'index.ts');

  if (!fs.existsSync(indexPath)) {
    return `WARNING: 배럴 export 누락 — ${layerDir}\n`
         + `         수정: ${indexPath} 를 생성하고 공개 API 를 re-export 하세요.`;
  }

  return null;
}
```

### 테스트 파일 배치 검사

테스트 파일이 소스 파일과 동일 디렉터리에 있는지 (또는 프로젝트 컨벤션에 맞는지) 확인:

```javascript
// 코로케이션 패턴: src/core/utils.ts → src/core/utils.test.ts
function checkTestCollocation(srcFile) {
  const testFile = srcFile.replace(/\.ts$/, '.test.ts');

  if (!fs.existsSync(testFile)) {
    return `WARNING: 테스트 파일 누락 — ${srcFile}\n`
         + `         기대 위치: ${testFile}`;
  }

  return null;
}
```

---

## 7. 통합 실행

모든 검사를 하나의 진입점에서 실행할 수 있도록 구성한다:

```bash
# 레이어 경계 검사
node scripts/check-layer-import.js

# 또는 package.json 스크립트로
npm run check:layers
npm run check:conventions
```

### package.json 스크립트 예시

```json
{
  "scripts": {
    "check:layers": "node scripts/check-layer-import.js",
    "check:conventions": "node scripts/check-conventions.js",
    "check:all": "npm run check:layers && npm run check:conventions"
  }
}
```
