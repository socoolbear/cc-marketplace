# 기계적 강제 — 레이어 검사기 + Hook + CI

아키텍처 불변 조건을 문서가 아닌 코드로 강제하는 패턴. 문서는 advisory 이고, 강제는 결정론적 도구만 보장한다 (CONTRACTS 1절 원칙 3).
setup Phase 3 (enforcement 선택 시) 이 본 파일을 따른다. 활성 여부는 `scripts/check-layer-import.js` 존재로 감지한다.

본 파일은 **설계 요건**이다 — 검사기 코드는 대상 프로젝트의 레이어 표 (`harness/ARCHITECTURE.md`) 를 보고 그 프로젝트에 맞게 작성한다. 고정 템플릿을 쓰지 않는다.

## 목차
- 1절 에러 메시지 4요소
- 2절 검사기 설계 요건 (경로 해석 규칙 포함 — 거짓 합격 방지)
- 3절 Hook 규약 (세션 안) — 출력 프로토콜이 핵심
- 4절 CI (세션 밖)

---

## 1. 에러 메시지 4요소

에러 메시지는 에이전트의 컨텍스트에 직접 들어간다 — 메시지 자체에 수정 방법을 포함한다:

```
ERROR: 레이어 위반 — src/types/foo.ts:12
       types/ 가 core/ 를 import 합니다.
       types/ 가 import 할 수 있는 레이어: (없음)
       수정: 공유 로직을 types/ 로 이동하세요.
       규칙: harness/ARCHITECTURE.md#레이어
```

필수: **위반 위치** (경로+행) / **위반된 규칙** / **구체적 수정 방법** / **규칙 문서 링크**.

## 2. `scripts/check-layer-import.js` 설계 요건

**2-1. 레이어 DAG 는 `harness/ARCHITECTURE.md` 의 레이어 표와 동기화한다.** 표가 바뀌면 같은 커밋에서 검사기도 바꾼다.

**2-2. 실행 모드 2종**
- 단일 파일: `node scripts/check-layer-import.js <file>` — Hook 용
- 전체 스캔: 인자 없음 — CI·수동 검증용

**2-3. 경로 → 레이어 해석 (거짓 합격 방지 — 필수)**

> **프로젝트 루트 기준 상대 경로로 정규화한 뒤 판정한다. 절대 경로에 정규식 첫 매칭을 쓰지 않는다.**

절대 경로에 `src/([^/]+)/` 같은 첫 매칭을 쓰면 **상위 경로의 동명 디렉토리에 오매칭**된다. 저장소가 `~/src/proj/` 아래 있으면 `/Users/me/src/proj/src/core/x.ts` 의 첫 매칭이 `src/proj/` 라서 레이어가 `proj` 로 해석되고, 알려진 레이어가 아니므로 **검사에서 조용히 제외된 뒤 "통과 ✓" 가 출력된다**. 경고 누락보다 위험하다 — 위반이 *합격*으로 보고되기 때문이다.

정규화 후 소스 루트 접두사를 제거하고 첫 세그먼트를 레이어로 삼는다. 판정 불가 파일은 **조용히 스킵하지 않고** 그 사실이 드러나게 한다 (전체 스캔 요약에 "미판정 N건" 표기).

**2-4. import 추출**: 정적 `import ... from`, side-effect `import '...'`, `require(...)`, **dynamic `import(...)`** 를 모두 잡는다. 문자열 리터럴이 아닌 동적 경로는 판정하지 않는다.

**2-5. 레이어 경계 외 규칙** (선택): 특정 레이어에서의 패키지 import 금지 등. 규칙마다 1절의 4요소를 갖춘 고유 메시지를 준다.

**2-6. 종료 코드**: 위반 0 → `0`, 위반 있음 → `1`. 위반은 stderr 로 출력한다. 단일 파일 모드는 성공 시 **무출력** (success is silent).

## 3. Hook — 세션 안 강제

### 3-1. 출력 프로토콜 (가장 중요)

PostToolUse 는 **차단할 수 없다** (도구가 이미 실행됨). 전달 경로는 종료 코드에 따라 갈린다:

| 종료 코드 | 결과 |
|---|---|
| `0` | stdout 은 **디버그 로그로만** 간다 — 모델은 보지 못한다 |
| `2` | stderr 를 모델에게 보여준다 |
| 그 외 | "hook error" 알림 + stderr 첫 줄 |

따라서 **검사기를 그냥 실행하고 `|| true` 로 넘기면 경고가 모델에 도달하지 않는다.** 차단 없이 컨텍스트만 주입하려면 exit 0 + stdout JSON 을 쓴다:

```json
{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"<위반 메시지>"}}
```

이 형태는 툴 결과 옆에 시스템 리마인더로 붙어 **모델에게 보이면서** 편집을 막지 않는다. 에이전트는 메시지에 이미 포함된 수정 방법을 읽고 자발적으로 고친다.

### 3-2. 어댑터 `scripts/layer-check-hook.js`

검사기 (사람·CI 용 출력) 와 훅 프로토콜 (JSON) 을 분리한다. 훅은 어댑터가 담당한다.

```javascript
#!/usr/bin/env node
'use strict';
// PostToolUse 어댑터 — 검사 결과를 모델 컨텍스트로 주입한다.
// stdin JSON 은 반드시 끝까지 읽는다 (미소비 시 EPIPE → "hook error").

const { execFileSync } = require('node:child_process');
const path = require('node:path');

let raw = '';

process.stdin.setEncoding('utf8');
process.stdin.on('data', (chunk) => { raw += chunk; });
process.stdin.on('end', () => {
  const projectDir = process.env.CLAUDE_PROJECT_DIR || process.cwd();

  let filePath;

  try {
    filePath = JSON.parse(raw)?.tool_input?.file_path;
  } catch {
    process.exit(0);            // 훅 입력이 깨져도 편집을 방해하지 않는다
  }

  if (!filePath || !/\.(ts|tsx|js|jsx|mjs|cjs)$/.test(filePath)) process.exit(0);

  try {
    execFileSync(process.execPath, [path.join(projectDir, 'scripts/check-layer-import.js'), filePath],
      { cwd: projectDir, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  } catch (err) {
    const message = `${err.stdout || ''}${err.stderr || ''}`.trim();

    if (message) {
      process.stdout.write(JSON.stringify({
        hookSpecificOutput: { hookEventName: 'PostToolUse', additionalContext: message },
      }));
    }
  }

  process.exit(0);              // 항상 0 — 전달은 stdout JSON 이 한다
});
```

- **소스 디렉토리를 훅에 하드코딩하지 않는다.** 확장자만 거르고 레이어 판정은 검사기에 맡긴다 (프로젝트마다 소스 루트가 다르다).
- `jq` 같은 외부 의존을 두지 않는다 — 검사기가 이미 node 이므로 어댑터도 node 로 맞춘다.

### 3-3. 등록 (`.claude/settings.local.json`)

matcher 객체 안에 `hooks` 배열이 **중첩**돼야 한다. 평평한 `{"matcher":…, "command":…}` 는 핸들러가 없어 등록되지 않는다.

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          { "type": "command", "command": "node \"$CLAUDE_PROJECT_DIR/scripts/layer-check-hook.js\"" }
        ]
      }
    ]
  }
}
```

`$CLAUDE_FILE_PATH` 같은 환경변수는 **없다** — 편집 경로는 stdin JSON 의 `tool_input.file_path` 로만 온다.

## 4. CI — 세션 밖 강제 (필수 짝)

Hook 은 Claude Code 세션 안만 지킨다. 다른 도구·다른 에이전트·사람의 커밋은 CI 가 지킨다 — **양날개가 모두 있어야 강제가 완성된다.** 특히 훅이 기록되는 `.claude/settings.local.json` 은 gitignore 대상이라 **팀원에게는 존재하지 않는다**. 팀 차원의 강제는 CI 쪽이 담당한다.

```json
{ "scripts": { "check:layers": "node scripts/check-layer-import.js" } }
```

- setup 이 `package.json` 에 `check:layers` 를 등록하고 **CI 테스트 단계 포함**을 안내한다
- AGENTS.md "검증 명령" 에 `npm run check:layers` 한 줄 추가 (document-formats 1절)
