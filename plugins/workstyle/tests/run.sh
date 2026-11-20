#!/usr/bin/env bash
#
# workstyle 훅 · 실행 파일 시험 — 격리한 HOME · TMPDIR, 임시 프로젝트 폴더, 가짜 claude.
#
#   bash tests/run.sh                  플러그인의 훅에 입력을 넣어 종료 코드와 출력의 핵심 문구를 본다
#   bash tests/run.sh --legacy <폴더>   옮기기 전 스크립트 (그 폴더의 같은 이름 파일) 와 나란히 돌려 종료 코드 · 출력이 같은지,
#                                      그리고 파일 차이가 주석 · 문서 경로 · 훅끼리 부르는 경로뿐인지 본다

set -uo pipefail

readonly PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly PLUGIN_HOOKS="${PLUGIN_ROOT}/hooks"
readonly HOOK_NAMES=(enforce-plan-review ask-precheck ask-classify stop-gate context-guard compact-restore team-cleanup-check)

LEGACY_DIR=""
[[ "${1:-}" == "--legacy" ]] && LEGACY_DIR="${2:?--legacy 뒤에 옮기기 전 스크립트 폴더}"

readonly WORK="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "${WORK}"' EXIT

passed=0
failed=0
RC=0
OUT=""

ok() {
  passed=$((passed + 1))
  echo "ok   $1"
}

fail() {
  failed=$((failed + 1))
  echo "FAIL $1 — $2"
}

# 격리한 뿌리 폴더 하나 (HOME · TMPDIR · 프로젝트) 를 만든다
makeRoot() {
  local root="$1"

  mkdir -p "${root}/home/.claude" "${root}/tmp" "${root}/bin" "${root}/proj/.claude/plan" "${root}/proj/.prompts" "${root}/empty"
  printf '#!/usr/bin/env bash\nexit 1\n' >"${root}/bin/claude"     # 판정 모델 호출 · 세션 목록을 끊는다
  printf '#!/usr/bin/env bash\nexit 1\n' >"${root}/bin/security"   # 키체인 조회를 끊는다
  chmod +x "${root}/bin/claude" "${root}/bin/security"
  git init -q "${root}/proj"
}

# runIn <뿌리> <스크립트> <입력 JSON> [환경 변수=값 …] — RC 와 OUT (stdout + stderr, 뿌리 경로를 가린 것) 을 채운다
runIn() {
  local root="$1"
  local script="$2"
  local input="$3"
  shift 3

  OUT=$(env -i PATH="${root}/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" HOME="${root}/home" TMPDIR="${root}/tmp" "$@" \
    bash "${script}" <<<"${input//__ROOT__/${root}}" 2>&1)
  RC=$?
  OUT="${OUT//${root}/__ROOT__}"
}

# 옮기기 전 스크립트의 출력에서 문서 경로 표기만 새 표기로 바꾼다 (허용한 차이)
normalizeLegacy() {
  sed -E -e 's|~/\.[a-z]+/claude/docs/|~/.claude/workstyle/docs/|g' \
      -e 's|~/\.claude/docs/workflow\.md|~/.claude/workstyle/docs/workflow.md|g' \
      -e 's|~/\.claude/docs/work-split\.md|~/.claude/workstyle/docs/work-split.md|g' \
      -e 's|~/\.claude/AGENTS\.md|~/.claude/workstyle/AGENTS.md|g'
}

# check <이름> <훅 이름> <기대 종료 코드> <출력에 있어야 할 문구 (없으면 "")> <입력 JSON> [환경 변수=값 …]
check() {
  local name="$1"
  local hook="$2"
  local expected_rc="$3"
  local expected_text="$4"
  local input="$5"
  shift 5

  runIn "${WORK}/new" "${PLUGIN_HOOKS}/${hook}.sh" "${input}" "$@"

  local new_rc=${RC}
  local new_out="${OUT}"

  if [[ "${new_rc}" != "${expected_rc}" ]]; then
    fail "${name}" "rc=${new_rc} (기대 ${expected_rc}) out=${new_out:0:200}"
  elif [[ -n "${expected_text}" && "${new_out}" != *"${expected_text}"* ]]; then
    fail "${name}" "문구 없음: ${expected_text} / out=${new_out:0:200}"
  else
    ok "${name}"
  fi

  [[ -n "${LEGACY_DIR}" ]] || return 0

  runIn "${WORK}/legacy" "${LEGACY_DIR}/${hook}.sh" "${input}" "$@"

  if [[ "${RC}" == "${new_rc}" && "$(normalizeLegacy <<<"${OUT}")" == "${new_out}" ]]; then
    ok "${name} — 옮기기 전과 같음"
  else
    fail "${name} — 옮기기 전과 다름" "legacy rc=${RC} out=${OUT:0:200} / new rc=${new_rc} out=${new_out:0:200}"
  fi
}

# 두 뿌리에 같은 준비를 한다: eachRoot <명령…> ($ROOT 로 뿌리를 받는다)
eachRoot() {
  local ROOT

  for ROOT in "${WORK}/new" "${WORK}/legacy"; do
    [[ -d "${ROOT}" ]] && ROOT="${ROOT}" "$@"
  done
}

writePlan() { printf '%s\n' "$@" >"${ROOT}/proj/.claude/plan/plan.md"; }
removePlan() { rm -f "${ROOT}/proj/.claude/plan/plan.md"; }
writeProgress() { printf 'session: prog1234\n## 목표\n시험\n' >"${ROOT}/proj/.prompts/PROGRESS-prog1234.md"; }
writeNight() { mkdir -p "${ROOT}/home/.local/state/claude-loop/night" && touch "${ROOT}/home/.local/state/claude-loop/night/$1"; }
clearNight() { rm -rf "${ROOT}/home/.local/state/claude-loop/night"; }
writeDisabled() { mkdir -p "${ROOT}/home/.local/state/claude-loop" && touch "${ROOT}/home/.local/state/claude-loop/disabled"; }
writeGateMode() { mkdir -p "${ROOT}/home/.local/state/claude-loop/stop-gate" && echo "$1" >"${ROOT}/home/.local/state/claude-loop/stop-gate/mode"; }
clearGateMode() { rm -f "${ROOT}/home/.local/state/claude-loop/stop-gate/mode"; }
clearDisabled() { rm -f "${ROOT}/home/.local/state/claude-loop/disabled"; }

planInput() { printf '{"session_id":"%s","tool_name":"ExitPlanMode","tool_input":{},"cwd":"__ROOT__/%s"}' "$1" "${2:-proj}"; }
askInput() { printf '{"session_id":"%s","tool_name":"AskUserQuestion","tool_input":{"questions":[{"header":"%s","question":"%s","options":[{"label":"예"},{"label":"아니오"}]}]},"cwd":"__ROOT__/proj"}' "$1" "$2" "$3"; }
stopInput() { jq -cn --arg session "$1" --arg message "$2" '{session_id: $session, hook_event_name: "Stop", stop_hook_active: false, last_assistant_message: $message, cwd: "__ROOT__/proj"}'; }

readonly TAIL_OK=$'**지금**: 시험 중\n**사용자 몫**: 없음\n**다음**: 없음'

testPlanReview() {
  eachRoot writePlan '# 계획' '## Context' '내용'
  check "계획 검증 — 검증 절 없는 계획은 차단" enforce-plan-review 2 '적대적' "$(planInput plan-1)"
  eachRoot writePlan '# 계획' '## 적대적 검증' '- 리뷰어: 2명'
  check "계획 검증 — 검증 절 있는 계획은 통과" enforce-plan-review 0 '' "$(planInput plan-2)"
  eachRoot removePlan
  check "계획 검증 — 계획서 없음, 첫 요청" enforce-plan-review 2 '' "$(planInput plan-3)"
  check "계획 검증 — 계획서 없음, 다시 요청" enforce-plan-review 0 '' "$(planInput plan-3)"
  check "계획 검증 — 계획 폴더가 없는 프로젝트, 첫 요청" enforce-plan-review 2 '' "$(planInput plan-4 empty)"
}

testAskPrecheck() {
  check "질문 점검 — 세션의 첫 질문은 차단" ask-precheck 2 '[질문 전 점검]' "$(askInput ask-1 '방식' '어느 방식으로 할까요?')"
  check "질문 점검 — 다시 물으면 통과" ask-precheck 0 '' "$(askInput ask-1 '방식' '어느 방식으로 할까요?')"
  check "질문 점검 — 실행 승인 질문은 차단" ask-precheck 2 '[실행 승인 질문 금지]' "$(askInput ask-1 '커밋' '커밋할까요?')"
  check "질문 점검 — 봇 세션은 건너뜀" ask-precheck 0 '' "$(askInput ask-2 '방식' '어느 방식으로 할까요?')" AGENT_BOT=1
  eachRoot writeNight ask-3
  check "질문 점검 — 야간 모드는 차단" ask-precheck 2 '' "$(askInput ask-3 '방식' '어느 방식으로 할까요?')"
  eachRoot clearNight
  check "질문 점검 — 깨진 입력" ask-precheck 0 '' 'not json'
}

testStopGate() {
  check "멈춤 점검 — 꼬리표가 있고 묻지 않는 답은 통과" stop-gate 0 '' "$(stopInput stop-1 $'작업을 마쳤습니다.\n\n'"${TAIL_OK}")"
  check "멈춤 점검 — 묻는 말로 끝난 답, 기본 모드 (기록만)" stop-gate 0 '' "$(stopInput stop-2 $'변경을 적용했습니다.\n\n이대로 진행할까요?')"
  eachRoot writeGateMode block
  check "멈춤 점검 — 묻는 말로 끝난 답, 차단 모드" stop-gate 0 '[멈춤 점검]' "$(stopInput stop-2b $'변경을 적용했습니다.\n\n이대로 진행할까요?')"
  eachRoot clearGateMode
  check "멈춤 점검 — 사용자 몫에 분류 표시 없는 항목" stop-gate 0 '[사용자 몫 점검]' \
    "$(stopInput stop-3 $'확인했습니다.\n\n**지금**: 시험 중\n**사용자 몫**: 결과 확인해 주세요\n**다음**: 없음')"
  check "멈춤 점검 — 다음에 지금 할 수 있는 일" stop-gate 0 '[다음 점검]' \
    "$(stopInput stop-4 $'확인했습니다.\n\n**지금**: 시험 중\n**사용자 몫**: 없음\n**다음**: 시험을 돌린다')"
  check "멈춤 점검 — 본문이 긴 답" stop-gate 0 '[길이 점검]' "$(stopInput stop-5 "$(printf '줄 %s 입니다.\n' {1..30})"$'\n\n'"${TAIL_OK}")"
  check "멈춤 점검 — 이미 한 번 막은 턴은 통과" stop-gate 0 '' \
    "$(jq -cn '{session_id: "stop-6", stop_hook_active: true, last_assistant_message: "진행할까요?", cwd: "__ROOT__/proj"}')"
  check "멈춤 점검 — 봇 세션" stop-gate 0 '' "$(stopInput stop-7 '진행할까요?')" AGENT_BOT=1
  eachRoot writeDisabled
  check "멈춤 점검 — 끄기 파일" stop-gate 0 '' "$(stopInput stop-8 '진행할까요?')"
  eachRoot clearDisabled
  check "멈춤 점검 — 깨진 입력" stop-gate 0 '' 'not json'
}

testContextAndCompact() {
  check "컨텍스트 알림 — 기록 파일 없음" context-guard 0 '' '{"session_id":"ctx-1","tool_name":"Bash","cwd":"__ROOT__/proj"}'
  check "컨텍스트 알림 — 봇 세션" context-guard 0 '' '{"session_id":"ctx-2","tool_name":"Bash","cwd":"__ROOT__/proj"}' AGENT_BOT=1
  check "compact 복원 — 진행 문서 없음" compact-restore 0 '' '{"session_id":"none5678","hook_event_name":"SessionStart","source":"compact","cwd":"__ROOT__/proj"}'
  eachRoot writeProgress
  check "compact 복원 — 진행 문서 있음" compact-restore 0 'PROGRESS-prog1234.md' \
    '{"session_id":"prog1234-aaaa","hook_event_name":"SessionStart","source":"compact","cwd":"__ROOT__/proj"}'
}

testTeamCleanup() {
  check "팀 정리 — 팀이 없으면 조용히 통과" team-cleanup-check 0 '' '{"session_id":"team-1234-5678","hook_event_name":"Stop","stop_hook_active":false,"cwd":"__ROOT__/proj"}'
}

# 옮기기 전 스크립트와의 차이가 허용한 줄뿐인가 — 판정 코드가 그대로라는 증거
testDiffAgainstLegacy() {
  local name unexpected removed added

  for name in "${HOOK_NAMES[@]}"; do
    removed=$(diff "${LEGACY_DIR}/${name}.sh" "${PLUGIN_HOOKS}/${name}.sh" | grep -c '^<')
    added=$(diff "${LEGACY_DIR}/${name}.sh" "${PLUGIN_HOOKS}/${name}.sh" | grep -c '^>')
    unexpected=$(diff "${LEGACY_DIR}/${name}.sh" "${PLUGIN_HOOKS}/${name}.sh" | grep '^>' \
      | grep -vE '^> [[:space:]]*#' \
      | grep -vF '~/.claude/workstyle/' \
      | grep -vF '"$(dirname "${BASH_SOURCE[0]}")/ask-classify.sh"' || true)

    if [[ -z "${unexpected}" && "${removed}" == "${added}" ]]; then
      ok "${name}.sh — 옮기기 전과의 차이가 주석 · 문서 경로 · 훅끼리 부르는 경로뿐 (${added}줄)"
    else
      fail "${name}.sh — 허용하지 않은 차이" "removed=${removed} added=${added} ${unexpected:0:200}"
    fi
  done
}

testHooksJson() {
  local actual
  local expected='PostToolUse||context-guard.sh|5 PreToolUse|AskUserQuestion|ask-precheck.sh|5 PreToolUse|ExitPlanMode|enforce-plan-review.sh|5 SessionStart||sync-rules.sh|10 SessionStart|compact|compact-restore.sh|10 Stop||stop-gate.sh|5 Stop||team-cleanup-check.sh|5'

  actual=$(jq -r '.hooks | to_entries[] | .key as $event | .value[] | (.matcher // "") as $matcher | .hooks[] | "\($event)|\($matcher)|\(.command | capture("hooks/(?<file>[a-z-]+\\.sh)").file)|\(.timeout)"' \
    "${PLUGIN_ROOT}/hooks/hooks.json" | sort | tr '\n' ' ' | sed 's/ $//')

  if [[ "${actual}" == "${expected}" ]]; then
    ok "hooks.json — 이벤트 · matcher · timeout"
  else
    fail "hooks.json — 이벤트 · matcher · timeout" "${actual}"
  fi
}

# runSync <HOME> — sync-rules.sh 를 격리한 HOME 에서 돌린다 (설치본 rules/ 대신 시험용 플러그인 폴더를 쓴다)
runSync() {
  OUT=$(env -i PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" HOME="$1" bash "${WORK}/syncplug/hooks/sync-rules.sh" <<<'{"session_id":"sync-1"}' 2>&1)
  RC=$?
}

testSyncRules() {
  local home="${WORK}/synchome"
  local target="${home}/.claude/workstyle"

  mkdir -p "${WORK}/syncplug/hooks" "${WORK}/syncplug/rules/docs" "${home}/.claude" "${WORK}/checkout"
  cp "${PLUGIN_HOOKS}/sync-rules.sh" "${WORK}/syncplug/hooks/"
  echo "규칙 1" >"${WORK}/syncplug/rules/AGENTS.md"
  echo "문서 1" >"${WORK}/syncplug/rules/docs/workflow.md"
  echo "@~/.claude/workstyle/AGENTS.md" >"${home}/.claude/CLAUDE.md"

  runSync "${home}"
  [[ ${RC} == 0 && -z "${OUT}" && "$(cat "${target}/AGENTS.md" 2>/dev/null)" == "규칙 1" && -f "${target}/.synced-copy" && -f "${target}/docs/workflow.md" ]] \
    && ok "규칙 맞추기 — 고정 폴더가 없으면 사본을 만든다" || fail "규칙 맞추기 — 고정 폴더가 없으면 사본을 만든다" "rc=${RC} ${OUT:0:200}"

  echo "규칙 2" >"${WORK}/syncplug/rules/AGENTS.md"
  echo "손으로 고침" >"${target}/docs/workflow.md"
  runSync "${home}"
  [[ ${RC} == 0 && "$(cat "${target}/AGENTS.md")" == "규칙 2" && "$(cat "${target}/docs/workflow.md")" == "문서 1" && -z "$(ls -d "${target}".* 2>/dev/null)" ]] \
    && ok "규칙 맞추기 — 내용이 다르면 설치본으로 맞추고 임시 폴더를 남기지 않는다" || fail "규칙 맞추기 — 내용이 다르면 맞춘다" "rc=${RC} ${OUT:0:200}"

  rm -rf "${target}"
  echo "체크아웃 규칙" >"${WORK}/checkout/AGENTS.md"
  ln -s "${WORK}/checkout" "${target}"
  runSync "${home}"
  [[ ${RC} == 0 && -z "${OUT}" && -L "${target}" && "$(cat "${target}/AGENTS.md")" == "체크아웃 규칙" ]] \
    && ok "규칙 맞추기 — 심링크는 건드리지 않는다" || fail "규칙 맞추기 — 심링크는 건드리지 않는다" "rc=${RC} ${OUT:0:200}"

  rm -rf "${WORK}/checkout"
  runSync "${home}"
  [[ ${RC} == 0 && -L "${target}" && "${OUT}" == *"끊긴 심링크"* ]] && ok "규칙 맞추기 — 끊긴 심링크를 알린다" || fail "규칙 맞추기 — 끊긴 심링크를 알린다" "rc=${RC} ${OUT:0:200}"

  rm -f "${target}"
  mkdir -p "${target}"
  echo "남의 파일" >"${target}/AGENTS.md"
  runSync "${home}"
  [[ ${RC} == 0 && "$(cat "${target}/AGENTS.md")" == "남의 파일" && "${OUT}" == *"그대로 두었다"* ]] \
    && ok "규칙 맞추기 — 사본 표시가 없는 폴더는 건드리지 않고 알린다" || fail "규칙 맞추기 — 사본 표시가 없는 폴더" "rc=${RC} ${OUT:0:200}"

  rm -rf "${target}"
  echo "# 다른 내용" >"${home}/.claude/CLAUDE.md"
  runSync "${home}"
  [[ ${RC} == 0 && "${OUT}" == *"import 줄이 없다"* && "$(jq -r '.hookSpecificOutput.hookEventName' <<<"${OUT}" 2>/dev/null)" == "SessionStart" ]] \
    && ok "규칙 맞추기 — 전역 지시 파일에 import 줄이 없으면 알린다" || fail "규칙 맞추기 — import 줄 없음 알림" "rc=${RC} ${OUT:0:200}"

  # 설치본 (cache) 과 마켓플레이스 사본의 내용이 다르면 알린다
  local installed="${WORK}/pl/plugins/cache/market/workstyle/abc123"
  local latest="${WORK}/pl/plugins/marketplaces/market/plugins/workstyle"

  mkdir -p "${installed}/hooks" "${installed}/rules" "${latest}/hooks" "${latest}/rules"
  cp "${PLUGIN_HOOKS}/sync-rules.sh" "${installed}/hooks/"
  cp "${PLUGIN_HOOKS}/sync-rules.sh" "${latest}/hooks/"
  echo "규칙" >"${installed}/rules/AGENTS.md"
  echo "규칙" >"${latest}/rules/AGENTS.md"
  echo "@~/.claude/workstyle/AGENTS.md" >"${home}/.claude/CLAUDE.md"
  touch "${installed}/.in_use"   # Claude Code 가 설치본에 두는 표시 파일은 차이로 보지 않는다
  OUT=$(env -i PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" HOME="${home}" bash "${installed}/hooks/sync-rules.sh" <<<'{}' 2>&1)
  [[ -z "${OUT}" ]] && ok "옛 판 감지 — 설치본과 마켓플레이스 사본이 같으면 조용하다" || fail "옛 판 감지 — 같으면 조용" "${OUT:0:200}"
  echo "새 규칙" >"${latest}/rules/AGENTS.md"
  OUT=$(env -i PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" HOME="${home}" bash "${installed}/hooks/sync-rules.sh" <<<'{}' 2>&1)
  [[ "${OUT}" == *"claude plugin update workstyle@market"* ]] && ok "옛 판 감지 — 내용이 다르면 갱신 명령을 알린다" || fail "옛 판 감지 — 다르면 알림" "${OUT:0:200}"
  rm -rf "${target}"

  rm -rf "${WORK}/syncplug/rules"
  rm -rf "${target}"
  runSync "${home}"
  [[ ${RC} == 0 && -z "${OUT}" && ! -e "${target}" ]] && ok "규칙 맞추기 — 플러그인에 rules/ 가 없으면 아무것도 하지 않는다" || fail "규칙 맞추기 — rules/ 없음" "rc=${RC} ${OUT:0:200}"
}

testBin() {
  local root="${WORK}/new"
  local bin_dir="${root}/localbin"
  local board_dir="${root}/home/.local/state/claude-loop/board"

  cat >"${root}/bin/claude" <<'EOF'
#!/usr/bin/env bash
[[ "$1 $2" == "agents --json" ]] && printf '[{"kind":"interactive","name":"alpha","status":"idle","sessionId":"sess-a","cwd":"/tmp/a"},{"kind":"interactive","name":"beta","status":"busy","sessionId":"sess-b","cwd":"/tmp/b"}]\n'
EOF
  mkdir -p "${board_dir}"
  printf '**지금**: 시험\n**사용자 몫**: [운영] 확인\n**다음**: 없음\n' >"${board_dir}/sess-b.md"

  OUT=$(env -i PATH="${root}/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" HOME="${root}/home" "${PLUGIN_ROOT}/bin/workstyle" board 2>&1)
  [[ "${OUT}" == *"■ beta [busy]"*"🔔 사용자 몫"*"■ alpha [idle] — 꼬리표 없음"* ]] && ok "상황판 — 사용자 몫이 있는 세션이 위" || fail "상황판 — 사용자 몫이 있는 세션이 위" "${OUT:0:200}"

  OUT=$(env -i PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" HOME="${root}/home" "${PLUGIN_ROOT}/bin/workstyle" metrics 1 2>&1)
  RC=$?
  [[ ${RC} == 0 && -n "${OUT}" ]] && ok "지표 — 기록이 없어도 출력" || fail "지표 — 기록이 없어도 출력" "rc=${RC} ${OUT:0:200}"

  OUT=$(env -i PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" HOME="${root}/home" WORKSTYLE_BIN_DIR="${bin_dir}" "${PLUGIN_ROOT}/bin/workstyle" install 2>&1)
  [[ -x "${bin_dir}/workstyle" && -x "${bin_dir}/loop-metrics" ]] && ok "install — 실행 파일 두 개" || fail "install — 실행 파일 두 개" "${OUT:0:200}"

  OUT=$(env -i PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" HOME="${root}/home" WORKSTYLE_ROOT="${PLUGIN_ROOT}" "${bin_dir}/loop-metrics" 1 2>&1)
  RC=$?
  [[ ${RC} == 0 ]] && ok "실행 파일 — 플러그인 폴더를 찾아 부른다" || fail "실행 파일 — 플러그인 폴더를 찾아 부른다" "rc=${RC} ${OUT:0:200}"

  OUT=$(env -i PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" HOME="${root}/home" "${bin_dir}/workstyle" board 2>&1)
  RC=$?
  [[ ${RC} == 1 && "${OUT}" == *"찾지 못했습니다"* ]] && ok "실행 파일 — 설치 기록이 없으면 알린다" || fail "실행 파일 — 설치 기록이 없으면 알린다" "rc=${RC} ${OUT:0:200}"

  printf 'mine\n' >"${bin_dir}/workstyle"
  OUT=$(env -i PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" HOME="${root}/home" WORKSTYLE_BIN_DIR="${bin_dir}" "${PLUGIN_ROOT}/bin/workstyle" install 2>&1)
  [[ "$(cat "${bin_dir}/workstyle")" == "mine" ]] && ok "install — 남의 파일은 덮어쓰지 않는다" || fail "install — 남의 파일은 덮어쓰지 않는다" "${OUT:0:200}"
}

testBacktest() {
  local root="${WORK}/backtest"
  local transcripts="${root}/home/.claude/projects/proj"
  local path_value="${root}/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  local stamp

  makeRoot "${root}"
  mkdir -p "${transcripts}"
  stamp=$(date '+%FT%T')

  # 가짜 모델: 분류 질문에는 none, 대조 질문에는 "첫째" 가 붙은 글자를 고른다 ("물어봐" 가 있으면 ASK). 받은 질문 글을 남긴다
  cat >"${root}/bin/claude" <<'EOF'
#!/usr/bin/env bash
prompt="$2"
printf '%s\n---\n' "${prompt}" >>"${HOME}/prompts.log"
choice=$(grep -oE '^[A-H]\. 첫째' <<<"${prompt}" | head -1 | cut -c1)
[[ "${prompt}" == *"물어봐"* ]] && choice="ASK"
[[ "${prompt}" == *"Labels:"* ]] && { printf '{"result":"none"}\n'; exit 0; }
jq -cn --arg choice "${choice}" '{result: ({choice: $choice, reason: "시험"} | tojson)}'
EOF

  jq -cn --arg at "${stamp}" '
    def asked($question; $labels; $answer; $multi):
      {type: "user", timestamp: $at, toolUseResult: {questions: [{header: "시험", question: $question, multiSelect: $multi, options: ($labels | map({label: ., description: "설명"}))}], answers: {($question): $answer}}};
    {type: "user", message: {content: "배경을 알려줘"}},
    {type: "assistant", message: {content: [{type: "text", text: "조사했습니다"}]}},
    asked("어느 쪽으로 할까요?"; ["첫째 (추천)", "둘째"]; "첫째 (추천)"; false),
    asked("둘 중 무엇으로 할까요?"; ["첫째 (Recommended)", "둘째"]; "둘째"; false),
    asked("물어봐야 하는 질문"; ["첫째 (추천)", "둘째"]; "먼저 설명해줘"; false),
    asked("여러 개 고르기"; ["첫째 (추천)", "둘째"]; "첫째 (추천)"; true),
    asked("추천 표시 없는 질문"; ["첫째", "둘째"]; "첫째"; false)' >"${transcripts}/session.jsonl"

  OUT=$(env -i PATH="${path_value}" HOME="${root}/home" "${PLUGIN_ROOT}/bin/workstyle" backtest collect 30 2>&1)
  printf '%s\n' "${OUT}" >"${root}/collected.jsonl"
  [[ "$(jq -sc 'map(.kind) | sort' "${root}/collected.jsonl" 2>/dev/null)" == '["free-text","other-option","recommended"]' ]] \
    && ok "대조 — 단일 선택 · 추천 표시 있는 질문만 답에 따라 세 묶음으로 모은다" || fail "대조 — collect 묶음" "${OUT:0:300}"
  [[ "$(jq -sr '.[0].context' "${root}/collected.jsonl" 2>/dev/null)" == *"조사했습니다"* ]] \
    && ok "대조 — 질문 직전 대화 글을 함께 모은다" || fail "대조 — collect 직전 대화 글" "${OUT:0:300}"

  OUT=$(env -i PATH="${path_value}" HOME="${root}/home" "${PLUGIN_ROOT}/bin/ask-backtest" judge "${root}/collected.jsonl" 2>&1)
  printf '%s\n' "${OUT}" >"${root}/verdicts.jsonl"
  [[ "$(jq -sc 'map([.kind, .user, .unanimous, .pick])' "${root}/verdicts.jsonl" 2>/dev/null)" == '[["recommended",0,true,0],["other-option",1,true,0],["free-text",null,false,null]]' ]] \
    && ok "대조 — 돌린 순서의 글자를 원래 선택지로 되돌리고, ASK 가 있으면 만장일치가 아니다" || fail "대조 — judge 판정" "${OUT:0:300}"
  grep -qE '추천|Recommended' "${root}/home/prompts.log" \
    && fail "대조 — 추천 표시를 가린다" "$(grep -E '추천|Recommended' "${root}/home/prompts.log" | head -2)" || ok "대조 — 추천 표시를 가린다"
  grep -q '^A\. 첫째' "${root}/home/prompts.log" && grep -q '^B\. 첫째' "${root}/home/prompts.log" \
    && ok "대조 — 판정마다 선택지 순서를 돌린다" || fail "대조 — 선택지 순서" "$(grep -E '^[A-H]\. ' "${root}/home/prompts.log" | head -6)"
  grep -q '조사했습니다' "${root}/home/prompts.log" \
    && fail "대조 — 직전 대화 글은 켰을 때만 보낸다" "꺼져 있는데 보냄" || ok "대조 — 직전 대화 글은 켰을 때만 보낸다"

  OUT=$(env -i PATH="${path_value}" HOME="${root}/home" ASK_BACKTEST_CONTEXT=1 "${PLUGIN_ROOT}/bin/ask-backtest" judge "${root}/collected.jsonl" 1,0,0 2>&1)
  grep -q '조사했습니다' "${root}/home/prompts.log" && [[ "$(jq -s 'length' <<<"${OUT}" 2>/dev/null)" == 1 ]] \
    && ok "대조 — ASK_BACKTEST_CONTEXT=1 이면 직전 대화 글을 보내고, 표본 수만큼만 판정한다" || fail "대조 — 직전 대화 글 켜기 · 표본 수" "${OUT:0:300}"

  OUT=$(env -i PATH="${path_value}" HOME="${root}/home" "${PLUGIN_ROOT}/bin/ask-backtest" report "${root}/verdicts.jsonl" "${root}/collected.jsonl" 2>&1)
  [[ "${OUT}" == *"자동 승인 대상 67%"*"(일치율) 50%"*"(추천안 채택률) 33%"*"미충족: 일치율 50%"* ]] \
    && ok "대조 — 모집단 비율로 환산한 일치율과 켜는 조건 판정" || fail "대조 — report" "${OUT:0:600}"

  OUT=$(env -i PATH="${path_value}" HOME="${root}/home" "${PLUGIN_ROOT}/bin/workstyle" backtest 2>&1)
  RC=$?
  [[ ${RC} == 2 && "${OUT}" == *"사용법: ask-backtest"* ]] && ok "대조 — 하위 명령이 없으면 사용법" || fail "대조 — 사용법" "rc=${RC} ${OUT:0:200}"

  printf '%s\n' '{"text":"운영 배포를 진행할까요?","label":"production"}' '{"text":"초안을 만들까요?","label":"none"}' >"${root}/labeled.jsonl"
  OUT=$(env -i PATH="${path_value}" HOME="${root}/home" ASK_JUDGE=llm bash "${PLUGIN_HOOKS}/ask-classify.sh" eval "${root}/labeled.jsonl" 2>&1)
  [[ "${OUT}" == *"물을 일 아님으로 본 것 1건 / 1건"*"낮춤 [production → none]"* ]] \
    && ok "질문 분류 eval — 낮추면 안 되는 분류를 낮춘 건수를 센다" || fail "질문 분류 eval — 낮춤 건수" "${OUT:0:600}"
}

main() {
  makeRoot "${WORK}/new"
  [[ -n "${LEGACY_DIR}" ]] && makeRoot "${WORK}/legacy"

  testPlanReview
  testAskPrecheck
  testStopGate
  testContextAndCompact
  testTeamCleanup

  if [[ -n "${LEGACY_DIR}" ]]; then
    testDiffAgainstLegacy
  else
    testHooksJson
    testBin
    testBacktest
    testSyncRules
  fi

  echo "---"
  echo "통과 ${passed} · 실패 ${failed}"

  [[ ${failed} == 0 ]]
}

main "$@"
