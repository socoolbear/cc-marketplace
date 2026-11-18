#!/usr/bin/env bash
set -euo pipefail

# cwd = 평가 작업 디렉토리. 코드 없이 README 만 있는 신규 프로젝트.
cat > README.md <<'MD'
# todo-api

할 일 관리 API. 아직 코드는 없다.
MD
