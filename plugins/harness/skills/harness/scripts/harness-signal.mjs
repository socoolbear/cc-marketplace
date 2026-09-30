#!/usr/bin/env node
// SessionStart 훅: 하네스 점검 신호(골격 갱신·승격 대기 학습·깨진 포인터)를 감지해 additionalContext 로 출력한다.
// 어떤 실패도 삼키고 exit 0 한다.
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const THROTTLE_MS = 7 * 24 * 60 * 60 * 1000;
const POINTER_CAP = 5;

export const toSlug = (p) => p.replace(/[^A-Za-z0-9]/g, '-');

export function readJson(file) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    return null;
  }
}

export function parseMajor(version) {
  const match = /^(\d+)\./.exec(String(version ?? ''));

  return match ? Number(match[1]) : null;
}

function readStdin() {
  try {
    return fs.readFileSync(0, 'utf8');
  } catch {
    return '';
  }
}

function runGit(anchor, args) {
  try {
    return execFileSync('git', args, {
      cwd: anchor,
      env: { ...process.env, GIT_OPTIONAL_LOCKS: '0' },
      timeout: 1500,
      stdio: ['ignore', 'pipe', 'ignore'],
    }).toString().trim();
  } catch {
    return null;
  }
}

function realpathOrNull(p) {
  try {
    return fs.realpathSync(p);
  } catch {
    return null;
  }
}

export function findMemoryDirs(anchor, configDir) {
  const roots = [anchor];
  const toplevel = runGit(anchor, ['rev-parse', '--show-toplevel']);
  const commonRaw = runGit(anchor, ['rev-parse', '--path-format=absolute', '--git-common-dir']);
  const commonDir = commonRaw && realpathOrNull(commonRaw);

  if (toplevel) roots.push(toplevel);
  if (commonDir) {
    const isBare = runGit(anchor, [`--git-dir=${commonDir}`, 'config', '--bool', 'core.bare']) === 'true';

    roots.push(isBare ? commonDir : path.dirname(commonDir));
  }

  const dirs = roots
    .map(realpathOrNull)
    .filter(Boolean)
    .map((root) => path.join(configDir, 'projects', toSlug(root), 'memory'));

  return [...new Set(dirs)].filter((dir) => fs.existsSync(dir));
}

export function parseBaseline(marker, markerMtimeMs) {
  const value = marker.lastReflect;
  const dateOnly = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(value ?? ''));

  if (dateOnly) {
    const [, y, m, d] = dateOnly.map(Number);

    return new Date(y, m - 1, d, 23, 59, 59, 999).getTime();
  }

  const parsed = Date.parse(value);

  return Number.isNaN(parsed) ? markerMtimeMs : parsed;
}

export function parseFrontmatter(text) {
  const match = /^---\r?\n([\s\S]*?)\r?\n---/.exec(text);

  if (!match) return {};

  const body = match[1];

  return {
    type: (/^type:\s*(\S+)/m.exec(body) ?? /^\s+type:\s*(\S+)/m.exec(body))?.[1],
    modified: /^\s*modified:\s*(\S+)/m.exec(body)?.[1],
  };
}

export function listMemoryFiles(memoryDir) {
  const index = path.join(memoryDir, 'MEMORY.md');

  if (!fs.existsSync(index)) return [];

  const text = fs.readFileSync(index, 'utf8');
  const files = [...text.matchAll(/\]\(([^)\s]+)\)/g)].map((m) => m[1]);

  return files
    .filter((f) => !f.includes('..') && !path.isAbsolute(f) && !/^[a-z]+:/i.test(f))
    .map((f) => path.join(memoryDir, f))
    .filter((f) => fs.existsSync(f));
}

export function countLearnings(memoryDirs, baseline) {
  const counted = new Set();
  const visited = new Set();

  for (const dir of memoryDirs) {
    for (const file of listMemoryFiles(dir)) {
      const real = realpathOrNull(file);

      if (!real || visited.has(real)) continue;

      visited.add(real);

      try {
        const { type, modified } = parseFrontmatter(fs.readFileSync(real, 'utf8'));
        const parsed = Date.parse(modified);
        const ts = Number.isNaN(parsed) ? fs.statSync(real).mtimeMs : parsed;

        if ((type === 'feedback' || type === 'project') && ts > baseline) counted.add(real);
      } catch {
        // 읽을 수 없는 파일은 건너뛴다
      }
    }
  }

  return counted.size;
}

export function findBrokenPointers(anchor) {
  const agents = path.join(anchor, 'AGENTS.md');

  if (!fs.existsSync(agents)) return [];

  const text = fs.readFileSync(agents, 'utf8');
  const spans = [...text.matchAll(/`([^`]+)`/g), ...text.matchAll(/\]\(([^)\s]+)\)/g)].map((m) => m[1]);
  const pointers = spans
    .flatMap((span) => span.match(/harness\/[A-Za-z0-9._\/-]+/g) ?? [])
    .map((p) => p.replace(/[.,;:\/-]+$/, ''))
    .filter((p) => p.startsWith('harness/'));

  return [...new Set(pointers)].filter((p) => !fs.existsSync(path.join(anchor, p))).slice(0, POINTER_CAP);
}

export function buildContext({ skeleton, learnings, pointers }) {
  const lines = [];

  if (skeleton) lines.push(`- 골격 갱신 가능 (v${skeleton.marker} → v${skeleton.plugin})`);
  if (learnings > 0) lines.push(`- 승격 대기 학습 ${learnings}건 (auto-memory)`);
  if (pointers.length > 0) lines.push(`- 깨진 지도 포인터: ${pointers.map((p) => `\`${p}\``).join(', ')}`);
  if (lines.length === 0) return null;

  return [
    '[harness 자가 점검 신호] 이 프로젝트의 하네스 문서에 점검할 거리가 있습니다:',
    ...lines,
    '사용자의 현재 요청을 먼저 끝내세요. 그 응답 끝에 한 줄로만 "`/harness` 로 하네스 점검을 할 수 있어요" 라고 한 번 제안하고, 스스로 실행하지 마세요. 사용자가 원하면 harness 스킬로 점검합니다.',
  ].join('\n');
}

function isThrottled(stateFile, fingerprint) {
  const state = readJson(stateFile);

  if (!state || state.fingerprint !== fingerprint) return false;

  return Date.now() - Date.parse(state.shownAt) < THROTTLE_MS;
}

function readPluginVersion() {
  const here = path.dirname(fileURLToPath(import.meta.url));
  const root = process.env.CLAUDE_PLUGIN_ROOT;
  const candidates = [
    root && path.join(root, '.claude-plugin', 'plugin.json'),
    path.join(here, '..', '..', '..', '.claude-plugin', 'plugin.json'),
  ].filter(Boolean);

  for (const file of candidates) {
    const json = readJson(file);

    if (json?.version) return json.version;
  }

  return null;
}

export function main() {
  const stdinText = readStdin();
  let stdinJson = {};

  try {
    stdinJson = JSON.parse(stdinText) ?? {};
  } catch {
    // stdin 은 참고용이라 파싱 실패해도 진행한다
  }

  const anchor = fs.realpathSync(process.env.CLAUDE_PROJECT_DIR || stdinJson.cwd || process.cwd());
  const markerFile = path.join(anchor, 'harness', '.harness.json');
  const marker = readJson(markerFile);

  if (!marker || typeof marker !== 'object') return;

  const markerMajor = parseMajor(marker.version);
  const pluginMajor = parseMajor(readPluginVersion());
  const skeleton = markerMajor !== null && pluginMajor !== null && markerMajor < pluginMajor
    ? { marker: markerMajor, plugin: pluginMajor }
    : null;

  const configDir = process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude');
  const baseline = parseBaseline(marker, fs.statSync(markerFile).mtimeMs);
  const learnings = countLearnings(findMemoryDirs(anchor, configDir), baseline);
  const pointers = findBrokenPointers(anchor);
  const context = buildContext({ skeleton, learnings, pointers });

  if (!context) return;

  const dataDir = process.env.CLAUDE_PLUGIN_DATA;
  const stateFile = dataDir && path.join(dataDir, 'signals', `${toSlug(anchor)}.json`);
  const fingerprint = JSON.stringify({
    skeleton: skeleton ? `${skeleton.marker}->${skeleton.plugin}` : false,
    learnings,
    pointers,
  });

  if (stateFile) {
    if (isThrottled(stateFile, fingerprint)) return;

    fs.mkdirSync(path.dirname(stateFile), { recursive: true });
    fs.writeFileSync(stateFile, JSON.stringify({ fingerprint, shownAt: new Date().toISOString() }));
  }

  process.stdout.write(JSON.stringify({
    hookSpecificOutput: { hookEventName: 'SessionStart', additionalContext: context },
  }));
}

if (process.argv[1] && realpathOrNull(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    main();
  } catch {
    // 훅은 세션을 방해하지 않는다
  }
  process.exit(0);
}
