#!/usr/bin/env bash
set -euo pipefail

# cwd = 평가 작업 디렉토리. CLAUDE.md / AGENTS.md 는 만들지 않는다.
mkdir -p src/types src/core src/ui test

cat > package.json <<'JSON'
{
  "name": "demo-app",
  "version": "0.1.0",
  "type": "module",
  "scripts": {
    "test": "node --test"
  }
}
JSON

cat > src/types/user.js <<'JS'
export const makeUser = (id, name) => ({ id, name });
JS

cat > src/core/user-service.js <<'JS'
import { makeUser } from '../types/user.js';

export const createUser = (name) => makeUser(Date.now(), name);
JS

cat > src/core/greeting.js <<'JS'
import { makeUser } from '../types/user.js';

export const greet = (user) => `hello, ${user.name}`;
export const anonymous = () => makeUser(0, 'guest');
JS

cat > src/ui/render.js <<'JS'
import { createUser } from '../core/user-service.js';
import { greet } from '../core/greeting.js';

export const renderWelcome = (name) => greet(createUser(name));
JS

cat > src/ui/index.js <<'JS'
import { renderWelcome } from './render.js';

console.log(renderWelcome('world'));
JS

cat > test/greeting.test.js <<'JS'
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { greet } from '../src/core/greeting.js';

test('greet', () => {
  assert.equal(greet({ name: 'a' }), 'hello, a');
});
JS
