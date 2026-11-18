# 레이어 강제 — 검사기 · 훅 · CI

불변 조건을 문서가 아닌 도구로 강제한다. 이 파일은 **설계 요건**이다. 검사기는 프로젝트의 도구 체인으로 (JS/TS 면 node, Python 이면 python 등) `harness/ARCHITECTURE.md` 레이어 표에 맞춰 작성하고, 고정 템플릿을 쓰지 않는다. 아래 코드는 JS 프로젝트의 예다.

## 1. 에러 메시지 4요소

메시지는 에이전트 컨텍스트에 그대로 들어가므로 고치는 방법까지 담는다.

```
ERROR: 레이어 위반 — src/types/foo.ts:12
       types/ 가 core/ 를 import 합니다.
       types/ 가 import 할 수 있는 레이어: (없음)
       수정: 공유 로직을 types/ 로 이동하세요.
       규칙: harness/ARCHITECTURE.md#레이어
```

위반 위치 (경로+행) / 위반된 규칙 / 구체적 수정 방법 / 규칙 문서 링크.

## 2. 검사기 요건

- **레이어 DAG = ARCHITECTURE.md 레이어 표.** 표가 바뀌면 같은 커밋에서 검사기도 바꾼다.
- **실행 모드 2종**: 파일 인자 1개 (훅용, 성공 시 무출력) / 인자 없음 (전체 스캔 — CI·maintain 용).
- **경로 해석 (거짓 합격 방지, 필수)**: 프로젝트 루트 기준 상대 경로로 정규화한 뒤 소스 루트 접두사를 떼고 첫 세그먼트를 레이어로 삼는다. 절대 경로에 정규식 첫 매칭을 쓰면 저장소가 `~/src/proj/` 아래 있을 때 상위 `src/` 에 걸려 모든 파일이 "알 수 없는 레이어" 로 조용히 빠지고 **통과** 가 출력된다. 판정 불가 파일은 전체 스캔 요약에 "미판정 N건" 으로 드러낸다.
- **import 추출**: 정적 import, side-effect import, `require(...)`, 동적 `import(...)` 모두 (언어별 등가물 포함). 문자열 리터럴이 아닌 동적 경로는 판정하지 않는다.
- **종료 코드**: 위반 없음 `0`, 위반 `1`. 위반은 stderr.

## 3. 훅 — 세션 안

### 출력 프로토콜

PostToolUse 는 차단할 수 없다 (도구가 이미 실행됨). 전달은 종료 코드로 갈린다:

| 종료 코드 | 결과 |
|---|---|
| `0` | stdout 은 디버그 로그로만 간다 — 모델은 못 본다 |
| `2` | stderr 를 모델에게 보인다 |
| 그 외 | "hook error" 알림 |

검사기를 `|| true` 로 넘기면 경고가 모델에 닿지 않는다. 막지 않고 알리려면 exit 0 + stdout JSON:

```json
{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"<위반 메시지>"}}
```

### 어댑터 (`scripts/layer-check-hook.js` 예)

검사기 출력 (사람·CI 용) 과 훅 프로토콜 (JSON) 을 분리한다.

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

- 소스 디렉토리를 훅에 하드코딩하지 않는다 — 확장자만 거르고 판정은 검사기에 맡긴다.
- 편집 경로는 stdin JSON 의 `tool_input.file_path` 로만 온다 (`$CLAUDE_FILE_PATH` 같은 환경변수는 없다).

### 등록 — `.claude/settings.json` (팀 공유)

matcher 객체 안에 `hooks` 배열이 **중첩**돼야 한다. 평평한 `{"matcher":…, "command":…}` 는 등록되지 않는다.

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

- 등록 전 `git check-ignore -q .claude/settings.json` 으로 커밋 여부를 확인한다. `.claude` 를 통째로 무시하는 프로젝트에서는 팀원에게 없으므로 사실대로 알린다.
- `settings.local.json` (v3 방식) 은 머신 로컬이다. 양쪽에 있으면 검사가 두 번 돈다 — 공유 설정만 남긴다.

## 4. CI — 세션 밖 (필수 짝)

훅은 Claude Code 세션만 지킨다. 다른 도구·사람의 커밋은 CI 가 지킨다. 검사기 전체 스캔을 프로젝트 스크립트 (예: `package.json` 의 `check:layers`) 로 등록하고, CI 테스트 단계 포함과 AGENTS.md 검증 명령 추가를 안내한다.
