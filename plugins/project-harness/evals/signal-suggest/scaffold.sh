#!/usr/bin/env bash
set -euo pipefail

# cwd = 평가 작업 디렉토리. 마커가 구버전 (3.0.0) 인 프로젝트를 만든다.
# 플러그인이 4.x 이면 SessionStart 훅이 "골격 갱신" 신호를 모델에 주입해야 한다.
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
{"version":"3.0.0","lastReflect":"2026-01-01"}
JSON

cat > AGENTS.md <<'MD'
# demo-app

작은 node 프로젝트.

## 검증

- 테스트: `npm test`

## 지도

- 구조·불변 조건: `harness/ARCHITECTURE.md`
- 결정 이력: `harness/ADR.md`
- 용어: `harness/GLOSSARY.md`
- 반복 실수: `harness/LESSONS.md`
MD

printf '@AGENTS.md\n' > CLAUDE.md

cat > src/a.js <<'JS'
export function getUser(id) {
  return { id, name: `user-${id}` };
}
JS

cat > src/b.js <<'JS'
import { getUser } from './a.js';

export const describeUser = (id) => `이름: ${getUser(id).name}`;
JS
