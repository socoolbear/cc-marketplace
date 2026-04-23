#!/usr/bin/env node

/**
 * generate-layer-check.js
 *
 * 프로젝트의 레이어 구조를 입력받아 check-layer-import.js 를 자동 생성한다.
 *
 * 사용법:
 *   node generate-layer-check.js --config layers.json --output scripts/check-layer-import.js
 *   node generate-layer-check.js --interactive
 *
 * layers.json 형식:
 * {
 *   "srcDir": "src",
 *   "layers": {
 *     "types":      [],
 *     "game-data":  ["types"],
 *     "adapters":   ["types", "game-data"],
 *     "core":       ["types", "game-data", "adapters"],
 *     "components": ["types", "game-data", "adapters", "core"]
 *   },
 *   "freeDirectories": ["utils", "__fixtures__"],
 *   "noReactLayers": ["types", "game-data", "adapters", "core"],
 *   "forbiddenImports": ["apps/web"],
 *   "rulesDoc": "docs/architecture.md"
 * }
 */

'use strict';

const fs = require('fs');
const path = require('path');

function generateScript(config) {
  const {
    srcDir = 'src',
    layers = {},
    freeDirectories = ['utils'],
    noReactLayers = [],
    forbiddenImports = [],
    rulesDoc = 'docs/architecture.md',
  } = config;

  const layerNames = Object.keys(layers);
  const freeSet = JSON.stringify(freeDirectories);

  return `#!/usr/bin/env node

'use strict';

const fs = require('fs');
const path = require('path');

// ─── Layer DAG ───────────────────────────────────────────────
const LAYER_ALLOWED = ${JSON.stringify(layers, null, 2)};

const LAYER_NAMES = Object.keys(LAYER_ALLOWED);
const FREE_DIRS = ${freeSet};
const NO_REACT_LAYERS = ${JSON.stringify(noReactLayers)};
const FORBIDDEN_IMPORTS = ${JSON.stringify(forbiddenImports)};
const RULES_DOC = '${rulesDoc}';
const SRC_DIR = '${srcDir}';

// ─── Helpers ─────────────────────────────────────────────────

function resolveLayer(filePath) {
  const normalized = filePath.replace(/\\\\/g, '/');
  const regex = new RegExp(SRC_DIR + '/([^/]+)/');
  const match = normalized.match(regex);

  if (!match) return null;

  const dir = match[1];

  if (FREE_DIRS.includes(dir)) return null;
  if (LAYER_NAMES.includes(dir)) return dir;

  return null;
}

function extractImports(source) {
  const imports = [];
  const fromRegex = /from\\s+['"]([^'"]+)['"]/g;
  const sideEffectRegex = /import\\s+['"]([^'"]+)['"]/g;
  const requireRegex = /require\\(\\s*['"]([^'"]+)['"]\\s*\\)/g;

  let m;

  while ((m = fromRegex.exec(source)) !== null) imports.push(m[1]);
  while ((m = sideEffectRegex.exec(source)) !== null) imports.push(m[1]);
  while ((m = requireRegex.exec(source)) !== null) imports.push(m[1]);

  return [...new Set(imports)];
}

function resolveImportLayer(importPath, fileDir) {
  if (!importPath.startsWith('.')) return null;

  const resolved = path.resolve(fileDir, importPath);
  const normalized = resolved.replace(/\\\\/g, '/');
  const regex = new RegExp(SRC_DIR + '/([^/]+)');
  const match = normalized.match(regex);

  if (!match) return null;

  const dir = match[1];

  if (FREE_DIRS.includes(dir)) return null;
  if (LAYER_NAMES.includes(dir)) return dir;

  return null;
}

function checkFile(filePath) {
  const violations = [];
  const srcLayer = resolveLayer(filePath);

  let source;

  try {
    source = fs.readFileSync(filePath, 'utf-8');
  } catch {
    return violations;
  }

  const imports = extractImports(source);
  const fileDir = path.dirname(filePath);

  for (const imp of imports) {
    // 금지 import
    for (const forbidden of FORBIDDEN_IMPORTS) {
      if (imp.includes(forbidden) || imp.startsWith(forbidden)) {
        violations.push({
          file: filePath,
          message:
            \`ERROR: 금지된 import — \${filePath}\\n\` +
            \`       \${forbidden} 을 import 합니다.\\n\` +
            \`       수정: \${forbidden} 의존을 제거하고, 필요한 인터페이스를 adapters/ 에 정의하세요.\\n\` +
            \`       규칙: \${RULES_DOC}\`,
        });
        continue;
      }
    }

    // React import 제한
    if (srcLayer && NO_REACT_LAYERS.includes(srcLayer)) {
      if (imp === 'react' || imp === 'react-dom' || imp.startsWith('react/') || imp.startsWith('react-dom/')) {
        violations.push({
          file: filePath,
          message:
            \`ERROR: React import 위반 — \${filePath}\\n\` +
            \`       \${srcLayer}/ 에서 \${imp} 를 import 합니다.\\n\` +
            \`       수정: React 의존 로직을 components/ 로 이동하세요.\\n\` +
            \`       규칙: \${RULES_DOC}\`,
        });
        continue;
      }
    }

    // 레이어 경계 위반
    if (!srcLayer) continue;

    const targetLayer = resolveImportLayer(imp, fileDir);

    if (!targetLayer || targetLayer === srcLayer) continue;

    const allowed = LAYER_ALLOWED[srcLayer];

    if (!allowed.includes(targetLayer)) {
      const allowedStr = allowed.length > 0
        ? allowed.join(', ')
        : '없음 (다른 레이어를 import 할 수 없습니다)';

      violations.push({
        file: filePath,
        message:
          \`ERROR: 레이어 위반 — \${filePath}\\n\` +
          \`       \${srcLayer}/ 가 \${targetLayer}/ 를 import 합니다.\\n\` +
          \`       \${srcLayer}/ 가 import 할 수 있는 레이어: \${allowedStr}\\n\` +
          \`       수정: 공유 로직은 하위 레이어로 이동하거나, import 방향을 역전하세요.\\n\` +
          \`       규칙: \${RULES_DOC}\`,
      });
    }
  }

  return violations;
}

function collectFiles(dir) {
  const results = [];

  if (!fs.existsSync(dir)) return results;

  const entries = fs.readdirSync(dir, { withFileTypes: true });

  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);

    if (entry.isDirectory()) {
      if (entry.name === 'node_modules' || entry.name === '.git') continue;
      results.push(...collectFiles(fullPath));
    } else if (entry.isFile() && /\\.(ts|tsx|js|jsx)$/.test(entry.name)) {
      results.push(fullPath);
    }
  }

  return results;
}

function main() {
  const args = process.argv.slice(2);
  let files;

  if (args.length > 0) {
    const targetFile = path.resolve(args[0]);

    if (!fs.existsSync(targetFile)) {
      console.error(\`파일을 찾을 수 없습니다: \${targetFile}\`);
      process.exit(1);
    }

    files = [targetFile];
  } else {
    files = collectFiles(path.resolve(SRC_DIR));
  }

  let allViolations = [];

  for (const file of files) {
    allViolations.push(...checkFile(file));
  }

  if (allViolations.length === 0) {
    if (args.length === 0) console.log('레이어 import 검사 통과 ✓');
    process.exit(0);
  }

  console.error(\`\\n레이어 import 위반 \${allViolations.length}건 발견:\\n\`);

  for (const v of allViolations) {
    console.error(v.message);
    console.error('');
  }

  process.exit(1);
}

main();
`;
}

function main() {
  const args = process.argv.slice(2);

  let configPath = null;
  let outputPath = null;

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--config' && args[i + 1]) {
      configPath = args[++i];
    } else if (args[i] === '--output' && args[i + 1]) {
      outputPath = args[++i];
    } else if (args[i] === '--help') {
      console.log(`사용법:
  node generate-layer-check.js --config layers.json --output scripts/check-layer-import.js

layers.json 형식:
{
  "srcDir": "src",
  "layers": {
    "types":      [],
    "services":   ["types"],
    "components": ["types", "services"]
  },
  "freeDirectories": ["utils"],
  "noReactLayers": ["types", "services"],
  "forbiddenImports": ["apps/web"],
  "rulesDoc": "docs/architecture.md"
}`);
      process.exit(0);
    }
  }

  if (!configPath) {
    console.error('ERROR: --config 옵션이 필요합니다.');
    console.error('사용법: node generate-layer-check.js --config layers.json --output scripts/check-layer-import.js');
    process.exit(1);
  }

  const config = JSON.parse(fs.readFileSync(path.resolve(configPath), 'utf-8'));
  const script = generateScript(config);

  if (outputPath) {
    const dir = path.dirname(path.resolve(outputPath));

    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }

    fs.writeFileSync(path.resolve(outputPath), script, 'utf-8');
    fs.chmodSync(path.resolve(outputPath), 0o755);
    console.log(`생성 완료: ${outputPath}`);
  } else {
    process.stdout.write(script);
  }
}

main();
