#!/usr/bin/env bash
set -euo pipefail

# cwd = 평가 작업 디렉토리. 하네스가 이미 셋업된 프로젝트를 만든다.
mkdir -p harness src

cat > harness/ARCHITECTURE.md <<'MD'
# ARCHITECTURE

## 레이어

- `src/types` -> `src/core` -> `src/ui` 방향으로만 의존한다.

## 불변 조건

- 하위 레이어는 상위 레이어를 import 하지 않는다.
MD

cat > harness/ADR.md <<'MD'
# ADR

## ADR-001: 테스트 러너는 node --test

- 상태: 채택
- 맥락: 의존성 없이 테스트를 돌리고 싶다.
- 결정: 내장 `node --test` 를 쓴다.
MD

cat > harness/GLOSSARY.md <<'MD'
# GLOSSARY

| 용어 | 정의 |
|---|---|
| user | 서비스 이용자 레코드 |
MD

cat > harness/LESSONS.md <<'MD'
# LESSONS

## 반복 실수

- (아직 없음)
MD

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

cat > harness/.harness.json <<'JSON'
{"version":"4.0.0","lastReflect":"2026-01-01T00:00:00.000Z"}
JSON

cat > AGENTS.md <<'MD'
# demo-app

작은 node 프로젝트. 레이어는 types -> core -> ui.

## 검증

- 테스트: `npm test`

## 지도

- 구조·불변 조건: `harness/ARCHITECTURE.md`
- 결정 이력: `harness/ADR.md`
- 용어: `harness/GLOSSARY.md`
- 반복 실수: `harness/LESSONS.md`
- 운영 절차: `harness/RUNBOOK.md`
MD

printf '@AGENTS.md\n' > CLAUDE.md

cat > src/index.js <<'JS'
export const main = () => 'ok';
JS
