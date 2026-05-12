# Category Mapping — 카테고리 자동 추론 규칙

`/snippets:extract` Phase 3 (코드 분석 & 후보 추출) 에서 chunk 를 `backend / frontend / infra / ai / public-candidates` 중 하나로 분류하는 규칙. 모호한 경우는 후보 2 개를 사용자에게 제시하여 결정한다.

---

## 1. 5 개 카테고리

| 카테고리 | 의미 | 대상 출력 경로 |
|----------|------|----------------|
| `backend` | 서버 / API / DB / 큐 / 인증 로직 | `<target>/snippets/backend/<subcategory>/<slug>/` |
| `frontend` | UI / 컴포넌트 / 클라이언트 상태 / 폼 검증 | `<target>/snippets/frontend/<subcategory>/<slug>/` |
| `infra` | 인프라 설정 / CI/CD / Docker / Nginx / Terraform | `<target>/snippets/infra/<subcategory>/<slug>/` |
| `ai` | AI 프롬프트 / MCP / agent 정의 / Claude·Codex 설정 | `<target>/snippets/ai/<subcategory>/<slug>/` |
| `public-candidates` | 공개 가능 후보 — **자동 분류 대상 아님** | `<target>/snippets/public-candidates/<slug>/` |

`<subcategory>` 는 매핑 표 (§ 3~6) 의 두 번째 컬럼.

---

## 2. 분류 신호 우선순위

같은 chunk 에 여러 신호가 잡힐 수 있다. 다음 순서로 우선한다 (위쪽이 강함):

1. **파일 경로** — 디렉토리명에 `controllers/`, `pages/`, `nginx/` 등이 포함된 경우
2. **확장자** — `.tf`, `.dockerfile`, `.yml` (workflow), `.tsx` (frontend) 등
3. **import / require / use 구문** — `import { z } from "zod"` → frontend/zod
4. **코드 패턴** — `@Controller()` decorator → NestJS backend, `useEffect(` → frontend/react

신호가 충돌하면 우선순위 높은 쪽을 채택. 동일 우선순위에서 충돌하면 모호 처리 (§ 8).

---

## 3. `backend` 매핑 표

| subcategory | 신호 | 예시 |
|-------------|------|------|
| `laravel` | `app/Http/Controllers/`, `app/Models/`, `Illuminate\` import, `artisan` | Eloquent 모델, FormRequest, Service |
| `nestjs` | `@Controller`, `@Injectable`, `@Module` decorator, `@nestjs/` import | Controller / Service / Pipe / Guard |
| `graphql` | `type Query`, `@Resolver`, `gql` template, `*.graphql` 파일 | resolver, schema, dataloader |
| `redis` | `redis.set/get`, `ioredis`, `node-redis`, `Predis\` | 캐시 패턴, lock, rate limit |
| `mysql` | `SELECT/INSERT/UPDATE` SQL, `mysql2/promise`, `*.sql` | 마이그레이션, seed, 쿼리 |
| `auth` | `jwt`, `passport`, `bcrypt`, OAuth2 콜백 | 토큰 발급/검증, 세션 |
| `queue` | BullMQ, Laravel Queue, Sidekiq, SQS | job 정의, worker |
| `php` | `<?php`, namespace `App\` (Laravel 외) | 순수 PHP 유틸 |
| `node` | Node.js 서버 (NestJS 외), Express, Fastify | 미들웨어, 라우터 |

---

## 4. `frontend` 매핑 표

| subcategory | 신호 | 예시 |
|-------------|------|------|
| `nextjs` | `app/`, `pages/`, `next/`, `'use client'`, `'use server'` | layout, page, route handler |
| `react` | `useState`, `useEffect`, JSX, `.tsx` (Next.js 외) | 커스텀 hook, HOC, context |
| `react-query` | `useQuery`, `useMutation`, `QueryClient`, `@tanstack/react-query` | fetcher, invalidation |
| `zod` | `z.object`, `z.infer`, `z.parse` | schema, form validation |
| `tailwind` | `className="...flex..."`, `tailwind.config.*` | utility 조합 패턴 |
| `form` | `react-hook-form`, `formik`, `FormData` | 검증, 제출, 에러 표시 |
| `vue` | `.vue`, `setup()`, `<script setup>` | composable, component |
| `css` | `.module.css`, `styled-components`, `@emotion/` | 변수, 믹스인 |

---

## 5. `infra` 매핑 표

| subcategory | 신호 | 예시 |
|-------------|------|------|
| `docker` | `Dockerfile`, `docker-compose.yml`, `FROM`, `RUN` | 멀티 스테이지, healthcheck |
| `nginx` | `nginx.conf`, `*.conf` (server 블록), `try_files`, `proxy_pass` | rewrite, prefix 제거, static |
| `github-actions` | `.github/workflows/*.yml`, `uses: actions/`, `runs-on:` | matrix, reusable workflow |
| `terraform` | `*.tf`, `resource "..."`, `terraform {` | 모듈, variable, output |
| `k8s` | `apiVersion:`, `kind: Deployment`, `*.yaml` (kind 블록) | manifest, helm chart |
| `shell` | `#!/bin/bash`, `#!/usr/bin/env zsh`, `.sh` | wrapper, 부트스트랩 |
| `makefile` | `Makefile`, `.PHONY:`, 탭 들여쓰기 룰 | 빌드, 배포 명령 모음 |

---

## 6. `ai` 매핑 표

| subcategory | 신호 | 예시 |
|-------------|------|------|
| `claude` | `.claude/`, `CLAUDE.md`, `AGENTS.md`, `claude_code` | 프로젝트 지침, 슬래시 명령 |
| `codex` | `.codex/`, `codex.toml`, `codex` 설정 | 프로필, 통합 |
| `copilot` | `.github/copilot-instructions.md`, `.copilotignore` | 지침 |
| `mcp` | `mcp.json`, `mcpServers`, `tools: [...]` | 서버 설정, 도구 정의 |
| `prompt` | `.prompts/`, `prompt.md`, frontmatter `--- name: ...` | refactor / debug / migration 프롬프트 |
| `agent` | `subagent_type`, `name:` + `description:` frontmatter | 서브 에이전트 정의 |

---

## 7. `public-candidates`

자동 분류 **대상 아님**. 사용자가 후보 검토 (Phase 4) 단계에서 명시적으로 카테고리를 `public-candidates` 로 변경할 때만 이 경로로 출력한다.

조건 (사용자 판단 가이드 — dev-templates `.prompts/01.md` 인용):

- 완전히 범용적인가
- 회사 맥락이 없는가
- 특정 서비스 구조를 유추할 수 없는가
- 공개 블로그에 올려도 문제없는가
- 짧고 독립적인 예제인가

5 개 모두 충족 시 `public-candidates` 권장.

---

## 8. 모호한 경우 처리

다음 상황은 zero-shot 분류 한계로 후보 2 개를 사용자에게 제시한다:

- GraphQL resolver — `backend/graphql` vs `backend/nestjs` (NestJS GraphQL 모듈)
- React Server Component — `frontend/nextjs` vs `backend/node` (서버 실행)
- shell 스크립트 — `infra/shell` vs `infra/makefile` (Makefile 안에 인라인)
- prompt 정의 — `ai/prompt` vs `ai/agent` (agent 정의에 prompt 포함)
- Docker compose 안의 nginx 설정 — `infra/docker` vs `infra/nginx`

AskUserQuestion 형식:
```
이 chunk 의 카테고리가 모호합니다:
- (A) infra/docker — docker-compose 서비스 정의
- (B) infra/nginx — 안에 포함된 nginx 설정 블록
```

사용자 선택 결과는 같은 chunk 패턴에 한해 세션 내 캐시 (반복 질문 회피).
