# 기계적 강제 — 레이어 검사 스크립트 + Hook + CI

아키텍처 불변 조건을 문서가 아닌 코드로 강제하는 패턴. 문서는 advisory 이고, 강제는 결정론적 도구만 보장한다 (CONTRACTS 1절 원칙 3).
setup Phase 3 (enforcement 선택 시) 이 본 파일을 따른다. 활성 여부는 `scripts/check-layer-import.js` 존재로 감지한다.

---

## 1. 에러 메시지 설계 원칙

에러 메시지는 에이전트의 컨텍스트에 직접 들어간다 — 메시지 자체에 수정 방법을 포함한다:

```
ERROR: 레이어 위반 — src/types/foo.ts:12
       types/ 가 core/ 를 import 합니다.
       types/ 가 import 할 수 있는 레이어: (없음)
       수정: 공유 로직을 types/ 로 이동하세요.
       규칙: harness/ARCHITECTURE.md#레이어
```

필수 요소: 위반 위치 (경로+행) / 위반된 규칙 / 구체적 수정 방법 / 규칙 문서 링크.

## 2. `scripts/check-layer-import.js` 설계

`../scripts/generate-layer-check.js` 로 생성한다. 핵심 구조:

```javascript
// harness/ARCHITECTURE.md 의 레이어 표와 동기화할 것
const LAYER_DAG = {
  'types':      [],                    // 최하위: import 불가
  'core':       ['types'],
  'adapters':   ['types', 'core'],
  'app':        ['types', 'core', 'adapters'],
};

// 특정 패키지의 사용 위치 제한 (선택)
const FORBIDDEN_IMPORTS = [
  { layer: 'core',  pattern: /from\s+['"]react['"]/, message: 'core/ 에서 React 금지 — 프레임워크 독립성' },
  { layer: 'types', pattern: /from\s+['"](?!\.)[^'"]*['"]/, message: 'types/ 는 순수 타입만 — 런타임 패키지 금지' },
];
```

- import/require/dynamic import 를 정규식으로 추출, 파일 경로의 첫 세그먼트로 레이어 판정
- **실행 모드 2종**: 단일 파일 (`node scripts/check-layer-import.js <file>` — Hook 용) / 전체 스캔 (인자 없음 — CI·수동 검증용)

## 3. Hook (세션 안 강제)

`.claude/settings.local.json`:

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

`|| true` — 경고만 출력하고 차단하지 않는다. 에이전트가 경고를 컨텍스트에서 읽고 자발적으로 수정한다 (수정 방법이 메시지에 이미 포함).

## 4. CI (세션 밖 강제) — 필수 짝

Hook 은 Claude Code 세션 안만 지킨다. 다른 도구·다른 에이전트·사람의 커밋은 CI 가 지킨다 — **양날개가 모두 있어야 강제가 완성된다**.

```json
{
  "scripts": {
    "check:layers": "node scripts/check-layer-import.js"
  }
}
```

- setup 이 `package.json` 에 `check:layers` 를 등록하고, **CI 테스트 단계에 포함**하도록 안내한다
- AGENTS.md "검증 명령" 소절에 `npm run check:layers` 한 줄 추가 (document-formats 1절)
