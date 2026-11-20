#!/usr/bin/env bash
#
# deploy-guard 훅 시험 — 격리한 HOME · TMPDIR, 시험용 대상 파일, 원격 URL 만 넣은 임시 git 저장소, 가짜 gh.
#
#   bash tests/run.sh                              플러그인의 훅을 시험한다
#   bash tests/run.sh --legacy <폴더> [변수 이름]   옮기기 전 스크립트 (그 폴더의 enforce-deploy-check.sh · remind-deploy-qa.sh) 에
#                                                  같은 기대값을 돌리고, 플러그인 훅과의 차이가 주석 · 안내문 · 승인 위임 변수 한 줄뿐인지 본다.
#                                                  [변수 이름] 은 옮기기 전 스크립트가 승인 위임 세션을 가리는 환경 변수 (없으면 그 시험은 건너뜀)

set -uo pipefail

readonly PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly PLUGIN_HOOKS="${PLUGIN_ROOT}/hooks"

HOOK_DIR="${PLUGIN_HOOKS}"
APPROVED_ENV="CLAUDE_DEPLOY_APPROVED_SESSION"
LEGACY=""

if [[ "${1:-}" == "--legacy" ]]; then
  LEGACY=1
  HOOK_DIR="${2:?--legacy 뒤에 옮기기 전 스크립트 폴더}"
  APPROVED_ENV="${3:-}"
fi

readonly CHECK="${HOOK_DIR}/enforce-deploy-check.sh"
readonly REMIND="${HOOK_DIR}/remind-deploy-qa.sh"
readonly WORK="$(cd "$(mktemp -d)" && pwd -P)"
readonly APP="${WORK}/app"
readonly TOOLS="${WORK}/tools"
readonly TARGETS="${WORK}/targets"

trap 'rm -rf "${WORK}"' EXIT

passed=0
failed=0
session_seq=0
RC=0
OUT=""
ERR=""

ok() {
  passed=$((passed + 1))
  echo "ok   $1"
}

fail() {
  failed=$((failed + 1))
  echo "FAIL $1 — rc=${RC} out=${OUT:0:160} err=${ERR:0:160}"
}

newSession() {
  session_seq=$((session_seq + 1))
  SESSION="test-${session_seq}"
}

writeTargets() {
  printf '%s\n' "$@" >"${TARGETS}"
}

writeDefaultTargets() {
  writeTargets 'prod acme/app:main' 'dev acme/app:dev' 'none acme/tools:main' 'dev-workflow preview-env' \
    'prod-command my-upload\.sh[[:space:]]+prod'
}

makeRepo() {   # makeRepo <폴더> <owner/repo> <브랜치>
  git init -q -b "$3" "$1"
  git -C "$1" remote add origin "git@github.com:$2.git"
  git -C "$1" -c user.name=test -c user.email=test@example.com commit -q --allow-empty -m init   # 커밋이 있어야 현재 브랜치를 읽는다
}

# runHook <스크립트> <입력 JSON> [환경 변수=값 …] — RC · OUT (stdout) · ERR (stderr) 를 채운다
runHook() {
  local script="$1"
  local input="$2"
  shift 2

  OUT=$(env -i PATH="${WORK}/bin:${PATH}" HOME="${WORK}/home" TMPDIR="${WORK}/tmp" \
    CLAUDE_DEPLOY_TARGETS="${TARGETS}" CLAUDE_DEPLOY_QA_PATTERNS="${WORK}/qa-patterns" FAKE_BASE="${FAKE_BASE:-main}" "$@" \
    bash "${script}" <<<"${input}" 2>"${WORK}/stderr")
  RC=$?
  ERR=$(cat "${WORK}/stderr")
}

bashInput() {   # bashInput <명령> [cwd]
  jq -cn --arg command "$1" --arg cwd "${2:-${APP}}" --arg session "${SESSION}" \
    '{session_id: $session, tool_name: "Bash", tool_input: {command: $command}, cwd: $cwd}'
}

check() {   # check <명령> [cwd] [환경 변수=값 …]
  local command="$1"
  local cwd="${2:-${APP}}"
  shift
  [[ $# -gt 0 ]] && shift

  runHook "${CHECK}" "$(bashInput "${command}" "${cwd}")" "$@"
}

isBlocked() { [[ ${RC} == 2 && "${ERR}" == *"$1"* ]]; }
isAsk() { [[ ${RC} == 0 && "$(jq -r '.hookSpecificOutput.permissionDecision // empty' <<<"${OUT}" 2>/dev/null)" == "ask" && "${OUT}" == *"$1"* ]]; }
isPass() { [[ ${RC} == 0 && -z "${OUT}" ]]; }

expect() {   # expect <이름> <판정 함수> [인자]
  local name="$1"
  shift

  if "$@"; then
    ok "${name}"
  else
    fail "${name}"
  fi
}

# 첫 실행과 재실행을 한 번에: twice <이름> <명령> <cwd> <첫 실행 판정…> -- <재실행 판정…> [-- 환경 변수=값 …]
twice() {
  local name="$1"
  local command="$2"
  local cwd="$3"
  shift 3

  local -a first=()
  local -a second=()

  while [[ $# -gt 0 && "$1" != "--" ]]; do first+=("$1"); shift; done
  shift
  while [[ $# -gt 0 && "$1" != "--" ]]; do second+=("$1"); shift; done
  [[ $# -gt 0 ]] && shift

  newSession
  check "${command}" "${cwd}" "$@"
  expect "${name} — 첫 실행" "${first[@]}"
  check "${command}" "${cwd}" "$@"
  expect "${name} — 재실행" "${second[@]}"
}

setup() {
  mkdir -p "${WORK}/home" "${WORK}/tmp" "${WORK}/bin" "${WORK}/elsewhere"
  makeRepo "${APP}" acme/app main
  makeRepo "${TOOLS}" acme/tools main
  writeDefaultTargets

  cat >"${WORK}/bin/gh" <<'EOF'
#!/usr/bin/env bash
# 가짜 gh — pr view 만 답한다. 대상 브랜치는 FAKE_BASE
if [[ "$1 $2" == "pr view" ]]; then
  printf '{"url":"https://github.com/acme/app/pull/7","baseRefName":"%s"}\n' "${FAKE_BASE}"
  exit 0
fi
exit 1
EOF
  chmod +x "${WORK}/bin/gh"
}

testPush() {
  twice "운영 push" 'git push origin main' "${APP}" isBlocked '[운영 배포 점검]' -- isAsk '[운영 배포] acme/app:main'
  twice "운영 push (브랜치 생략, 현재 브랜치 main)" 'git push' "${APP}" isBlocked '[운영 배포 점검]' -- isAsk '[운영 배포]'
  twice "dev push" 'git push origin dev' "${APP}" isBlocked 'dev' -- isPass
  twice "배포 없음 (none) push" 'git push origin main' "${TOOLS}" isPass -- isPass
  twice "작업 브랜치 push" 'git push origin feature/login' "${APP}" isPass -- isPass
  twice "다른 폴더에서 git -C" "git -C ${APP} push origin main" "${WORK}/elsewhere" isBlocked '[운영 배포 점검]' -- isAsk '[운영 배포] acme/app:main'
  twice "맨 앞 cd" "cd ${APP} && git push origin main" "${WORK}/elsewhere" isBlocked '[운영 배포 점검]' -- isAsk '[운영 배포] acme/app:main'
  twice "맨 앞 cd — 배포 없음 대상" "cd ${TOOLS} && git push origin main" "${WORK}/elsewhere" isPass -- isPass
  twice "cd 두 번 (repo 미확인)" "cd ${WORK} && cd app && git push origin main" "${WORK}/elsewhere" isBlocked '' -- isAsk '[배포 대상 미확인]'
  newSession
  check 'git commit -m "push origin main 설명"'
  expect "push 가 아닌 명령" isPass
}

testMerge() {
  FAKE_BASE=main twice "gh pr merge → 운영" 'gh pr merge 7 --squash' "${APP}" isBlocked '[운영 배포 점검]' -- isAsk '[운영 배포] acme/app:main'
  FAKE_BASE=dev twice "gh pr merge → dev" 'gh pr merge 7 --squash' "${APP}" isBlocked 'dev' -- isPass
  FAKE_BASE=main twice "gh pr merge -R" 'gh pr merge 7 -R acme/app' "${WORK}/elsewhere" isBlocked '[운영 배포 점검]' -- isAsk '[운영 배포]'
  FAKE_BASE=main twice "gh pr merge --repo=" 'gh pr merge 7 --repo=acme/app' "${WORK}/elsewhere" isBlocked '[운영 배포 점검]' -- isAsk '[운영 배포]'
  FAKE_BASE=main twice "gh pr merge <PR URL>" 'gh pr merge https://github.com/acme/app/pull/7' "${WORK}/elsewhere" isBlocked '[운영 배포 점검]' -- isAsk '[운영 배포]'
  FAKE_BASE=feature/x twice "gh pr merge → 작업 브랜치" 'gh pr merge 7' "${APP}" isPass -- isPass

  local input

  newSession
  input=$(jq -cn --arg session "${SESSION}" --arg cwd "${WORK}/elsewhere" \
    '{session_id: $session, tool_name: "mcp__github__merge_pull_request", tool_input: {owner: "acme", repo: "app", pull_number: 7}, cwd: $cwd}')
  FAKE_BASE=main runHook "${CHECK}" "${input}"
  expect "MCP 머지 → 운영 — 첫 실행" isBlocked '[운영 배포 점검]'
  FAKE_BASE=main runHook "${CHECK}" "${input}"
  expect "MCP 머지 → 운영 — 재실행" isAsk '[운영 배포]'
}

testWorkflow() {
  twice "workflow run production" 'gh workflow run deploy.yml -f environment=production' "${APP}" isBlocked '[운영 배포 점검]' -- isAsk '[운영 배포]'
  twice "workflow run development" 'gh workflow run deploy.yml -f environment=development' "${APP}" isBlocked 'dev' -- isPass
  twice "workflow run dev-workflow 단어" 'gh workflow run preview-env.yml' "${APP}" isBlocked 'dev' -- isPass
  twice "workflow run 입력 없음 → 운영" 'gh workflow run deploy.yml' "${APP}" isBlocked '[운영 배포 점검]' -- isAsk '[운영 배포]'
  twice "gh api dispatches production" 'gh api repos/acme/app/actions/workflows/deploy.yml/dispatches -f inputs[environment]=production' "${APP}" isBlocked '[운영 배포 점검]' -- isAsk '[운영 배포]'
}

testProdCommand() {
  newSession
  check './my-upload.sh prod --apply'
  expect "prod-command → 바로 확인창" isAsk 'prod-command'
  newSession
  check './my-upload.sh prod --apply' "${APP}" AGENT_BOT=1
  expect "prod-command — 봇 세션도 확인창" isAsk 'prod-command'
}

testBrokenTargets() {
  writeTargets 'prod acme/app:main' 'oops acme/app:dev' 'none acme/tools:main'
  twice "깨진 대상 파일 — none 대상의 main 도 운영" 'git push origin main' "${TOOLS}" isBlocked '[운영 배포 점검]' -- isAsk '[운영 배포]'

  rm -f "${TARGETS}"
  twice "대상 파일 없음 — main 은 운영" 'git push origin main' "${APP}" isBlocked '[운영 배포 점검]' -- isAsk '[운영 배포]'

  writeTargets 'none acme/tools:main'
  twice "운영 줄도 no-prod 도 없음 — main 은 운영" 'git push origin main' "${TOOLS}" isBlocked '[운영 배포 점검]' -- isAsk '[운영 배포]'

  writeTargets 'no-prod' 'none acme/tools:main'
  twice "no-prod — none 대상 통과" 'git push origin main' "${TOOLS}" isPass -- isPass

  writeTargets 'no-prod' 'prod acme/app:main'
  twice "no-prod 와 prod 줄이 함께 — 깨진 파일" 'git push origin main' "${APP}" isBlocked '[운영 배포 점검]' -- isAsk '[운영 배포]'

  writeDefaultTargets
}

testApprovedSessions() {
  twice "봇 세션 (AGENT_BOT=1) — 운영 재실행 통과" 'git push origin main' "${APP}" isBlocked '[운영 배포 점검]' -- isPass -- AGENT_BOT=1

  if [[ -z "${APPROVED_ENV}" ]]; then
    echo "skip 승인 위임 세션 (변수 이름을 주지 않음)"
    return 0
  fi

  twice "승인 위임 세션 — 운영 재실행 통과" 'git push origin main' "${APP}" isBlocked '[운영 배포 점검]' -- isPass -- "${APPROVED_ENV}=/some/dir"
  twice "승인 위임 세션 — repo 미확인은 확인창" "cd ${WORK} && cd app && git push origin main" "${WORK}/elsewhere" \
    isBlocked '' -- isAsk '[배포 대상 미확인]' -- "${APPROVED_ENV}=/some/dir"

  if [[ -z "${LEGACY}" ]]; then
    twice "승인 위임 변수가 비어 있음 — 확인창" 'git push origin main' "${APP}" isBlocked '[운영 배포 점검]' -- isAsk '[운영 배포]' -- "${APPROVED_ENV}="
    twice "다른 이름의 변수는 승인 위임이 아님" 'git push origin main' "${APP}" isBlocked '[운영 배포 점검]' -- isAsk '[운영 배포]' -- "DEPLOY_APPROVED=1"
  fi
}

testNightMode() {
  local night_dir="${WORK}/home/.local/state/claude-loop/night"

  mkdir -p "${night_dir}"
  newSession
  touch "${night_dir}/${SESSION}"
  check 'git push origin main'
  expect "야간 모드 — 운영 push 는 처음부터 확인창" isAsk '[야간 모드 배포 차단]'
  check 'git push origin dev'
  expect "야간 모드 — dev push 도 확인창" isAsk '[야간 모드 배포 차단]'
  rm -rf "${WORK}/home/.local"
}

testEmptyMachine() {
  # 정책 파일이 하나도 없는 장비 — CLAUDE_DEPLOY_TARGETS 를 주지 않고 빈 HOME 의 기본 경로를 읽게 한다
  newSession
  OUT=$(env -i PATH="${WORK}/bin:${PATH}" HOME="${WORK}/home" TMPDIR="${WORK}/tmp" bash "${CHECK}" <<<"$(bashInput 'git push origin main')" 2>"${WORK}/stderr")
  RC=$?
  ERR=$(cat "${WORK}/stderr")
  expect "빈 장비 (대상 파일 없음) — main push 차단" isBlocked '[운영 배포 점검]'
}

testRemind() {
  newSession
  runHook "${REMIND}" "$(bashInput 'gh pr merge 7 --squash')"
  expect "QA 알림 — 머지" test "$(jq -r '.hookSpecificOutput.hookEventName // empty' <<<"${OUT}" 2>/dev/null)" == "PostToolUse"
  runHook "${REMIND}" "$(bashInput 'git push origin main')"
  expect "QA 알림 — push" test "${OUT}" != ""
  runHook "${REMIND}" "$(bashInput 'ls -la')"
  expect "QA 알림 — 일반 명령은 출력 없음" isPass
  runHook "${REMIND}" "$(bashInput './my-upload.sh --apply')"
  expect "QA 알림 — 패턴 파일 없으면 출력 없음" isPass
  printf '%s\n' '# 주석' 'my-upload\.sh[[:space:]].*--apply' >"${WORK}/qa-patterns"
  runHook "${REMIND}" "$(bashInput './my-upload.sh --apply')"
  expect "QA 알림 — 추가 패턴" test "${OUT}" != ""
  rm -f "${WORK}/qa-patterns"
}

# 옮기기 전 스크립트와 플러그인 훅의 차이가 허용한 줄뿐인가 — 판정 코드가 그대로라는 증거
testDiffAgainstLegacy() {
  local name unexpected removed added

  for name in enforce-deploy-check.sh remind-deploy-qa.sh; do
    removed=$(diff "${HOOK_DIR}/${name}" "${PLUGIN_HOOKS}/${name}" | grep -c '^<')
    added=$(diff "${HOOK_DIR}/${name}" "${PLUGIN_HOOKS}/${name}" | grep -c '^>')
    unexpected=$(diff "${HOOK_DIR}/${name}" "${PLUGIN_HOOKS}/${name}" | grep '^>' \
      | grep -vE '^> [[:space:]]*#' \
      | grep -vF 'deploy-guard 플러그인의' \
      | grep -vF '[[ "${AGENT_BOT:-}" == "1" || -n "${CLAUDE_DEPLOY_APPROVED_SESSION:-}" ]]' || true)
    RC=0
    OUT="${unexpected}"
    ERR="removed=${removed} added=${added}"
    expect "${name} — 옮기기 전과의 차이가 주석 · 안내문 · 승인 위임 변수 한 줄뿐" test -z "${unexpected}" -a "${removed}" == "${added}"
  done
}

testHooksJson() {
  local hooks_json="${PLUGIN_ROOT}/hooks/hooks.json"

  RC=0
  OUT=$(jq -c '[.hooks.PreToolUse[0].matcher, .hooks.PreToolUse[0].hooks[0].timeout, .hooks.PostToolUse[0].matcher, .hooks.PostToolUse[0].hooks[0].timeout]' "${hooks_json}")
  ERR=""
  expect "hooks.json — matcher · timeout" test "${OUT}" == '["Bash|mcp__github__merge_pull_request",5,"Bash",5]'
  OUT=$(jq -r '[.hooks.PreToolUse[].hooks[].command, .hooks.PostToolUse[].hooks[].command, .hooks.SessionStart[].hooks[].command] | join(" ")' "${hooks_json}")
  expect "hooks.json — 훅 스크립트 세 개를 부른다" test "${OUT}" == 'bash "${CLAUDE_PLUGIN_ROOT}/hooks/enforce-deploy-check.sh" bash "${CLAUDE_PLUGIN_ROOT}/hooks/remind-deploy-qa.sh" bash "${CLAUDE_PLUGIN_ROOT}/hooks/mark-session.sh"'
}

testMarkSession() {
  local marker="${WORK}/tmp/claude-plugin-sessions/deploy-guard-abc-123"

  runHook "${PLUGIN_HOOKS}/mark-session.sh" '{"session_id":"abc-123","hook_event_name":"SessionStart"}'
  expect "세션 표시 — 표시 파일에 플러그인 폴더 경로를 적는다" test "${RC}" == 0 -a "$(cat "${marker}" 2>/dev/null)" == "${PLUGIN_ROOT}"
  runHook "${PLUGIN_HOOKS}/mark-session.sh" '{"session_id":"../escape"}'
  expect "세션 표시 — 이상한 세션 ID 는 무시" test "${RC}" == 0 -a ! -e "${WORK}/tmp/escape"
  runHook "${PLUGIN_HOOKS}/mark-session.sh" 'not json'
  expect "세션 표시 — 깨진 입력도 exit 0" test "${RC}" == 0
}

main() {
  setup
  testPush
  testMerge
  testWorkflow
  testProdCommand
  testBrokenTargets
  testApprovedSessions
  testNightMode
  testEmptyMachine
  testRemind

  if [[ -n "${LEGACY}" ]]; then
    testDiffAgainstLegacy
  else
    testHooksJson
    testMarkSession
  fi

  echo "---"
  echo "통과 ${passed} · 실패 ${failed}"

  [[ ${failed} == 0 ]]
}

main "$@"
