import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

const SCRIPT = path.join(path.dirname(fileURLToPath(import.meta.url)), 'harness-signal.mjs');
const DAY = 24 * 60 * 60 * 1000;
const GIT_ENV = { ...process.env, GIT_CONFIG_NOSYSTEM: '1' };
const GIT_ARGS = ['-c', 'user.name=tester', '-c', 'user.email=tester@example.com'];
const hasGit = spawnSync('git', ['--version'], { stdio: 'ignore' }).status === 0;

const toSlug = (p) => p.replace(/[^A-Za-z0-9]/g, '-');
const makeTemp = (name) => fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), `harness-signal-${name}-`)));
const git = (cwd, ...args) => execFileSync('git', [...GIT_ARGS, ...args], { cwd, env: GIT_ENV, stdio: 'pipe' });

// 격리된 실행 환경: 프로젝트·설정·데이터·플러그인 루트·HOME 모두 임시 디렉토리
function createFixture({ pluginVersion = '4.0.0', marker = { version: '3.0.0' } } = {}) {
  const base = makeTemp('fx');
  const fixture = {
    project: path.join(base, 'project'),
    config: path.join(base, 'config'),
    data: path.join(base, 'data'),
    pluginRoot: path.join(base, 'plugin'),
    home: path.join(base, 'home'),
  };

  for (const dir of Object.values(fixture)) fs.mkdirSync(dir, { recursive: true });
  fs.mkdirSync(path.join(fixture.pluginRoot, '.claude-plugin'));
  fs.writeFileSync(
    path.join(fixture.pluginRoot, '.claude-plugin', 'plugin.json'),
    JSON.stringify({ name: 'harness', version: pluginVersion }),
  );
  if (marker) writeMarker(fixture.project, marker);

  return fixture;
}

function writeMarker(project, marker) {
  fs.mkdirSync(path.join(project, 'harness'), { recursive: true });
  fs.writeFileSync(
    path.join(project, 'harness', '.harness.json'),
    typeof marker === 'string' ? marker : JSON.stringify(marker),
  );
}

function runSignal(fixture, { anchor = fixture.project, env = {} } = {}) {
  const result = spawnSync('node', [SCRIPT], {
    input: '{}',
    encoding: 'utf8',
    env: {
      ...GIT_ENV,
      HOME: fixture.home,
      CLAUDE_CONFIG_DIR: fixture.config,
      CLAUDE_PLUGIN_DATA: fixture.data,
      CLAUDE_PLUGIN_ROOT: fixture.pluginRoot,
      CLAUDE_PROJECT_DIR: anchor,
      ...env,
    },
  });

  assert.equal(result.status, 0, result.stderr);

  return result.stdout;
}

function contextOf(stdout) {
  const json = JSON.parse(stdout);

  assert.equal(json.hookSpecificOutput.hookEventName, 'SessionStart');

  return json.hookSpecificOutput.additionalContext;
}

function writeMemory(fixture, root, files) {
  const dir = path.join(fixture.config, 'projects', toSlug(root), 'memory');

  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(
    path.join(dir, 'MEMORY.md'),
    Object.keys(files).map((name) => `- [${name}](${name})`).join('\n'),
  );
  for (const [name, content] of Object.entries(files)) fs.writeFileSync(path.join(dir, name), content);

  return dir;
}

const oldStyle = (type = 'feedback') => `---\nname: x\ntype: ${type}\n---\nbody\n`;
const newStyle = (modified, type = 'project') =>
  `---\nname: x\nmetadata:\n  type: ${type}\n  modified: ${modified}\n---\nbody\n`;
const learningsLine = (n) => `승격 대기 학습 ${n}건`;

function setMtime(dir, names, iso) {
  const seconds = Date.parse(iso) / 1000;

  for (const name of names) fs.utimesSync(path.join(dir, name), seconds, seconds);
}

test('마커 없음 → 무출력', () => {
  const fixture = createFixture({ marker: null });

  assert.equal(runSignal(fixture), '');
});

test('major 차이 → 골격 신호', () => {
  const fixture = createFixture({ pluginVersion: '4.0.0', marker: { version: '3.2.1' } });

  assert.match(contextOf(runSignal(fixture)), /골격 갱신 가능 \(v3 → v4\)/);
});

test('minor 차이 → 무신호', () => {
  const fixture = createFixture({ pluginVersion: '3.5.0', marker: { version: '3.0.0' } });

  assert.equal(runSignal(fixture), '');
});

test('형식이 깨진 version → 무신호', () => {
  const broken = createFixture({ marker: { version: 'abc' } });
  const brokenPlugin = createFixture({ pluginVersion: 'next', marker: { version: '3.0.0' } });

  assert.equal(runSignal(broken), '');
  assert.equal(runSignal(brokenPlugin), '');
});

test('구형(최상위 type)·신형(metadata) frontmatter 를 모두 집계', () => {
  const fixture = createFixture({ marker: { version: '4.0.0', lastReflect: '2020-01-01' } });

  writeMemory(fixture, fixture.project, {
    'old.md': oldStyle('feedback'),
    'new.md': newStyle('2030-01-01T00:00:00Z', 'project'),
    'skip.md': newStyle('2030-01-01T00:00:00Z', 'user'),
  });

  assert.ok(contextOf(runSignal(fixture)).includes(learningsLine(2)));
});

test('lastReflect 날짜만 + 같은 날 modified → 0건', () => {
  const fixture = createFixture({ marker: { version: '4.0.0', lastReflect: '2026-05-10' } });
  const sameDay = new Date(2026, 4, 10, 12, 0, 0).toISOString();

  const dir = writeMemory(fixture, fixture.project, { 'a.md': newStyle(sameDay) });

  setMtime(dir, ['a.md'], sameDay);

  assert.equal(runSignal(fixture), '');
});

test('ISO 기준 시각보다 뒤인 것만 집계', () => {
  const fixture = createFixture({ marker: { version: '4.0.0', lastReflect: '2026-05-10T12:00:00Z' } });

  const dir = writeMemory(fixture, fixture.project, {
    'before.md': newStyle('2026-05-10T11:00:00Z'),
    'after.md': newStyle('2026-05-10T13:00:00Z'),
  });

  setMtime(dir, ['before.md', 'after.md'], '2026-05-10T11:00:00Z');

  assert.ok(contextOf(runSignal(fixture)).includes(learningsLine(1)));
});

test('modified 가 기준 이전이어도 본문을 고쳐 mtime 이 뒤면 집계', () => {
  const fixture = createFixture({ marker: { version: '4.0.0', lastReflect: '2026-05-10T12:00:00Z' } });

  writeMemory(fixture, fixture.project, { 'edited.md': newStyle('2026-05-10T11:00:00Z') });

  assert.ok(contextOf(runSignal(fixture)).includes(learningsLine(1)));
});

test('lastReflect·승격 시각 모두 없음 → 전체 집계, 깨진 승격 시각 파일은 무시', () => {
  const fixture = createFixture({ marker: { version: '4.0.0' } });
  const dir = writeMemory(fixture, fixture.project, { 'a.md': oldStyle(), 'b.md': oldStyle() });

  setMtime(dir, ['a.md', 'b.md'], '2001-01-01T00:00:00Z');
  fs.writeFileSync(path.join(dir, '.harness-reflect.json'), '{broken');

  assert.ok(contextOf(runSignal(fixture)).includes(learningsLine(2)));
});

test('memory 디렉토리의 머신별 승격 시각이 마커 lastReflect 보다 우선', () => {
  const fixture = createFixture({ marker: { version: '4.0.0', lastReflect: '2020-01-01' } });
  const dir = writeMemory(fixture, fixture.project, { 'a.md': oldStyle() });

  fs.writeFileSync(path.join(dir, '.harness-reflect.json'), JSON.stringify({ '.': '2999-01-01T00:00:00Z' }));

  assert.equal(runSignal(fixture), '');

  fs.writeFileSync(path.join(dir, '.harness-reflect.json'), JSON.stringify({ other: '2999-01-01T00:00:00Z' }));

  assert.ok(contextOf(runSignal(fixture)).includes(learningsLine(1)));
});

test('모노레포 서브패키지 앵커는 toplevel 기준 상대 경로로 승격 시각을 찾음', { skip: !hasGit }, () => {
  const fixture = createFixture({ marker: null });
  const main = makeTemp('mono');
  const pkg = path.join(main, 'pkg');

  git(main, 'init', '-q');
  writeMarker(pkg, { version: '4.0.0', lastReflect: '2020-01-01' });

  const dir = writeMemory(fixture, main, { 'a.md': oldStyle() });

  fs.writeFileSync(path.join(dir, '.harness-reflect.json'), JSON.stringify({ pkg: '2999-01-01T00:00:00Z' }));

  assert.equal(runSignal(fixture, { anchor: pkg }), '');
});

test('MEMORY.md 의 상위 경로·절대 경로 링크는 무시', () => {
  const fixture = createFixture({ marker: { version: '4.0.0', lastReflect: '2020-01-01' } });
  const outside = path.join(path.dirname(fixture.project), 'outside.md');

  fs.writeFileSync(outside, oldStyle());

  const dir = writeMemory(fixture, fixture.project, {});

  fs.writeFileSync(path.join(dir, 'MEMORY.md'), `- [a](../../../../../../outside.md)\n- [b](${outside})\n`);

  assert.equal(runSignal(fixture), '');
});

test('일반 repo worktree 앵커에서 메인 toplevel 의 memory 를 찾음', { skip: !hasGit }, () => {
  const fixture = createFixture({ marker: null });
  const main = makeTemp('repo');
  const worktree = path.join(makeTemp('wt'), 'feature');

  git(main, 'init', '-q');
  git(main, 'commit', '-q', '--allow-empty', '-m', 'init');
  git(main, 'worktree', 'add', '-q', '-b', 'feature', worktree);
  writeMarker(worktree, { version: '4.0.0', lastReflect: '2020-01-01' });
  writeMemory(fixture, main, { 'a.md': oldStyle() });

  assert.ok(contextOf(runSignal(fixture, { anchor: worktree })).includes(learningsLine(1)));
});

test('bare 저장소 worktree 앵커에서 bare 디렉토리 slug 의 memory 를 찾음', { skip: !hasGit }, () => {
  const fixture = createFixture({ marker: null });
  const base = makeTemp('bare');
  const bare = path.join(base, 'x.git');
  const seed = path.join(base, 'seed');
  const worktree = path.join(base, 'wt');

  git(base, 'init', '-q', '--bare', bare);
  git(base, 'init', '-q', seed);
  git(seed, 'commit', '-q', '--allow-empty', '-m', 'init');
  git(seed, 'push', '-q', bare, 'HEAD:refs/heads/main');
  git(base, `--git-dir=${bare}`, 'worktree', 'add', '-q', worktree, 'main');
  writeMarker(worktree, { version: '4.0.0', lastReflect: '2020-01-01' });
  writeMemory(fixture, fs.realpathSync(bare), { 'a.md': oldStyle() });

  assert.ok(contextOf(runSignal(fixture, { anchor: worktree })).includes(learningsLine(1)));
});

test('깨진 포인터는 최대 5개, 존재하는 경로는 제외', () => {
  const fixture = createFixture({ marker: { version: '4.0.0', lastReflect: '2999-01-01' } });
  const missing = Array.from({ length: 7 }, (_, i) => `harness/MISSING${i}.md`);
  const lines = missing.map((p) => `- \`${p}\``);

  fs.writeFileSync(path.join(fixture.project, 'harness', 'REAL.md'), '');
  fs.writeFileSync(
    path.join(fixture.project, 'AGENTS.md'),
    [...lines, '- [ok](harness/REAL.md)', '- [link](harness/LINKED.md#anchor).'].join('\n'),
  );

  const context = contextOf(runSignal(fixture));
  const listed = context.match(/harness\/[A-Za-z0-9._/-]+\.md/g);

  assert.equal(listed.length, 5);
  assert.ok(!context.includes('REAL.md'));
});

test('같은 지문 재실행 → 무출력, 지문 변경 → 출력, 신호 없음 → 상태 미기록', () => {
  const fixture = createFixture({ pluginVersion: '4.0.0', marker: { version: '3.0.0' } });

  assert.notEqual(runSignal(fixture), '');
  assert.equal(runSignal(fixture), '');

  fs.writeFileSync(path.join(fixture.project, 'AGENTS.md'), '`harness/GONE.md`\n');

  assert.match(contextOf(runSignal(fixture)), /harness\/GONE\.md/);

  const quiet = createFixture({ marker: { version: '4.0.0', lastReflect: '2999-01-01' } });

  assert.equal(runSignal(quiet), '');
  assert.equal(fs.existsSync(path.join(quiet.data, 'signals')), false);
});

test('7일이 지난 같은 지문은 다시 출력', () => {
  const fixture = createFixture({ pluginVersion: '4.0.0', marker: { version: '3.0.0' } });

  assert.notEqual(runSignal(fixture), '');

  const stateFile = path.join(fixture.data, 'signals', `${toSlug(fixture.project)}.json`);
  const state = JSON.parse(fs.readFileSync(stateFile, 'utf8'));

  state.shownAt = new Date(Date.now() - 8 * DAY).toISOString();
  fs.writeFileSync(stateFile, JSON.stringify(state));

  assert.notEqual(runSignal(fixture), '');
});

test('CLAUDE_PLUGIN_DATA 미설정 → 스로틀 없이 매번 출력', () => {
  const fixture = createFixture({ pluginVersion: '4.0.0', marker: { version: '3.0.0' } });
  const env = { CLAUDE_PLUGIN_DATA: '' };

  assert.notEqual(runSignal(fixture, { env }), '');
  assert.notEqual(runSignal(fixture, { env }), '');
});

test('잘못된 마커 JSON → exit 0 무출력', () => {
  const fixture = createFixture({ marker: '{not json' });

  assert.equal(runSignal(fixture), '');
});

test('git 없는 디렉토리·PATH 에 git 없음 → exit 0, 나머지 신호는 유지', () => {
  const fixture = createFixture({ pluginVersion: '4.0.0', marker: { version: '3.0.0' } });
  const stdout = runSignal(fixture, { env: { PATH: path.dirname(process.execPath) } });

  assert.match(contextOf(stdout), /골격 갱신 가능/);
});
