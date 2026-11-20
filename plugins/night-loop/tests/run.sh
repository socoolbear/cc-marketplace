#!/usr/bin/env bash
# night-loop 시험 — 격리한 HOME 에서 훅에 시험 입력을 넣고, 가짜 claude · tmux · launchctl 로 러너를 돌린다.
# 실제 세션 · launchd · 상태 폴더는 건드리지 않는다.
#
# 사용법
#   tests/run.sh                          이 플러그인을 시험한다
#   tests/run.sh --legacy <폴더>          플러그인으로 옮기기 전 배치 (scripts/claude-loop.sh · claude/scripts/*.sh · claude/loop/*.md)
#                                         를 같은 기대값으로 시험한다. 옮기면서 더한 동작의 시험은 건너뛴다
set -uo pipefail

readonly PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

LEGACY=""

if [[ "${1:-}" == "--legacy" ]]; then
  LEGACY="${2:?--legacy <폴더>}"
fi

readonly SANDBOX="$(cd "$(mktemp -d)" && pwd)"   # 심링크를 풀지 않은 경로 — 가드가 불린 경로와 실경로를 둘 다 보는지 함께 시험된다
readonly FAKE_HOME="${SANDBOX}/home"
readonly FAKE_BIN="${SANDBOX}/fakebin"
readonly TREE="${SANDBOX}/tree"
readonly WORKSPACE="${SANDBOX}/ws"
readonly TMUX_LOG="${SANDBOX}/tmux.log"
readonly LAUNCHCTL_LOG="${SANDBOX}/launchctl.log"
readonly CLAUDE_LOG="${SANDBOX}/claude.log"
readonly NIGHT_DIR="${FAKE_HOME}/.local/state/claude-loop/night"

trap 'rm -rf "${SANDBOX}"' EXIT

failures=0
checks=0

check() {
  local label="$1" expected="$2" actual="$3"

  checks=$((checks + 1))

  if [[ "${expected}" == "${actual}" ]]; then
    echo "PASS ${label}"
    return 0
  fi

  failures=$((failures + 1))
  echo "FAIL ${label} — 기대 [${expected}] 실제 [${actual}]"
}

checkContains() {
  local label="$1" needle="$2" haystack="$3"

  if grep -qF -- "${needle}" <<<"${haystack}"; then
    check "${label}" "있음" "있음"
  else
    check "${label}" "있음: ${needle}" "없음"
  fi
}

skipNew() {
  echo "SKIP $1 (옮기면서 더한 동작)"
}

# --- 시험 대상을 임시 폴더에 복사한다 (러너의 PATH 줄만 가짜 명령이 먼저 잡히게 바꾼다) ---
mkdir -p "${FAKE_HOME}" "${FAKE_BIN}" "${TREE}" "${WORKSPACE}" "${SANDBOX}/cwd"

if [[ -n "${LEGACY}" ]]; then
  mkdir -p "${TREE}/scripts" "${TREE}/claude/scripts" "${TREE}/claude/loop"
  cp "${LEGACY}/scripts/claude-loop.sh" "${TREE}/scripts/claude-loop.sh"
  cp "${LEGACY}/claude/scripts/night-guard.sh" "${LEGACY}/claude/scripts/loop-verify-gate.sh" "${TREE}/claude/scripts/"
  cp "${LEGACY}"/claude/loop/*.md "${TREE}/claude/loop/"
  printf '#!/usr/bin/env bash\necho "fake-metrics"\n' >"${TREE}/claude/scripts/loop-metrics.sh"
  RUNNER="${TREE}/scripts/claude-loop.sh"
  GUARD="${TREE}/claude/scripts/night-guard.sh"
  GATE="${TREE}/claude/scripts/loop-verify-gate.sh"
  GUARDED_FILE="${TREE}/claude/scripts/night-guard.sh"
else
  cp -R "${PLUGIN_ROOT}/bin" "${PLUGIN_ROOT}/hooks" "${PLUGIN_ROOT}/prompts" "${TREE}/"
  RUNNER="${TREE}/bin/claude-loop"
  GUARD="${TREE}/hooks/night-guard.sh"
  GATE="${TREE}/hooks/loop-verify-gate.sh"
  GUARDED_FILE="${TREE}/hooks/night-guard.sh"
fi

perl -pi -e 's{^export PATH="}{export PATH="'"${FAKE_BIN}"':}' "${RUNNER}"
chmod +x "${RUNNER}"

# --- 가짜 명령 ---
cat >"${FAKE_BIN}/claude" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "agents" ]]; then
  echo '[{"name":"task-T1","kind":"interactive","status":"idle","sessionId":"aaaa1111-0000","startedAt":"2026-01-01T00:00:00Z","cwd":"/tmp/t1"}]'
fi
EOF
cat >>"${FAKE_BIN}/claude" <<EOF
if [[ "\$1" == "-p" ]]; then
  echo "\$*" | head -1 >>"${CLAUDE_LOG}"
  echo "가짜 아침 보고"
fi
EOF

cat >"${FAKE_BIN}/tmux" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"${TMUX_LOG}"
case "\$1" in
  list-panes) printf 'task-T1\t0\t%%9\n' ;;
  capture-pane) printf '\xe2\x9d\xaf \n' ;;
  list-sessions) echo "100 main" ;;
esac
EOF

cat >"${FAKE_BIN}/launchctl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"${LAUNCHCTL_LOG}"
EOF

printf '#!/usr/bin/env bash\nexit 0\n' >"${FAKE_BIN}/osascript"
printf '#!/usr/bin/env bash\necho "[]"\n' >"${FAKE_BIN}/gh"
printf '#!/usr/bin/env bash\necho "fake-metrics"\n' >"${FAKE_BIN}/loop-metrics"
chmod +x "${FAKE_BIN}"/*

# =====================================================================
# 야간 가드
# =====================================================================
guard() {   # guard <JSON> [환경변수=값 ...] → ask | pass | error:<종료코드>
  local json="$1" output code
  shift

  output=$(env -i HOME="${FAKE_HOME}" PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin" "$@" bash "${GUARD}" <<<"${json}" 2>/dev/null)
  code=$?

  if [[ ${code} -ne 0 ]]; then
    echo "error:${code}"
  elif grep -q '"permissionDecision": *"ask"' <<<"${output}"; then
    echo "ask"
  elif [[ -z "${output}" ]]; then
    echo "pass"
  else
    echo "unexpected:${output}"
  fi
}

toolJson() {   # toolJson <세션> <도구> <tool_input JSON>
  jq -cn --arg session "$1" --arg tool "$2" --argjson toolInput "$3" --arg cwd "${SANDBOX}/cwd" \
    '{hook_event_name: "PreToolUse", session_id: $session, tool_name: $tool, cwd: $cwd, tool_input: $toolInput}'
}

bashJson() {   # bashJson <세션> <명령>
  toolJson "$1" Bash "$(jq -cn --arg command "$2" '{command: $command}')"
}

promptJson() {
  jq -cn --arg session "$1" --arg prompt "$2" '{hook_event_name: "UserPromptSubmit", session_id: $session, prompt: $prompt}'
}

mkdir -p "${NIGHT_DIR}"
echo '{"name":"task-night","verify":""}' >"${NIGHT_DIR}/night-1"

check "가드: 보호 브랜치 push" ask "$(guard "$(bashJson night-1 'git push origin main')")"
check "가드: 작업 브랜치 push" pass "$(guard "$(bashJson night-1 'git push origin feature/x')")"
check "가드: 강제 push" ask "$(guard "$(bashJson night-1 'git push --force origin feature/x')")"
check "가드: PR 머지" ask "$(guard "$(bashJson night-1 'gh pr merge 12 --squash')")"
check "가드: PR 조회" pass "$(guard "$(bashJson night-1 'gh pr view 12')")"
check "가드: 인프라 명령" ask "$(guard "$(bashJson night-1 'kubectl get pods')")"
check "가드: 새 세션 열기" ask "$(guard "$(bashJson night-1 'tmux new-window -d claude')")"
check "가드: 서명 우회" ask "$(guard "$(bashJson night-1 'git commit --no-gpg-sign -m x')")"
check "가드: 지시 파일 셸 수정" ask "$(guard "$(bashJson night-1 'echo x > CLAUDE.md')")"
check "가드: 일반 명령" pass "$(guard "$(bashJson night-1 'ls -la src')")"
check "가드: CLAUDE.md Edit" ask "$(guard "$(toolJson night-1 Edit '{"file_path":"/work/repo/CLAUDE.md"}')")"
check "가드: 장비 설정 Write" ask "$(guard "$(toolJson night-1 Write "$(jq -cn --arg path "${FAKE_HOME}/.config/claude-loop/env" '{file_path: $path}')")")"
check "가드: 소스 파일 Edit" pass "$(guard "$(toolJson night-1 Edit '{"file_path":"/work/repo/src/a.ts"}')")"
check "가드: 쓰기 MCP" ask "$(guard "$(toolJson night-1 mcp__db-writer__query '{}')")"
check "가드: 읽기 MCP" pass "$(guard "$(toolJson night-1 mcp__docs__get_page '{}')")"
check "가드: 이름 있는 Agent" ask "$(guard "$(toolJson night-1 Agent '{"name":"helper","prompt":"x"}')")"
check "가드: 이름 없는 Agent" pass "$(guard "$(toolJson night-1 Agent '{"prompt":"x"}')")"
check "가드: 야간 모드 아님" pass "$(guard "$(bashJson day-1 'git push origin main')")"

touch "${NIGHT_DIR}/active"
check "가드: CLAUDE_NIGHT=1 + active" ask "$(guard "$(bashJson opened-1 'git push origin main')" CLAUDE_NIGHT=1)"
mkdir -p "${NIGHT_DIR}/released" && touch "${NIGHT_DIR}/released/opened-1"
check "가드: 사람이 푼 세션" pass "$(guard "$(bashJson opened-1 'git push origin main')" CLAUDE_NIGHT=1)"
rm -f "${NIGHT_DIR}/active"
check "가드: active 없으면 CLAUDE_NIGHT 무효" pass "$(guard "$(bashJson opened-2 'git push origin main')" CLAUDE_NIGHT=1)"

if [[ -z "${LEGACY}" ]]; then
  check "가드: 플러그인 파일 Edit" ask "$(guard "$(toolJson night-1 Edit "$(jq -cn --arg path "${GUARDED_FILE}" '{file_path: $path}')")")"
  check "가드: 플러그인 파일 Edit (CLAUDE_PLUGIN_ROOT 가 다른 값)" ask "$(guard "$(toolJson night-1 Edit "$(jq -cn --arg path "${GUARDED_FILE}" '{file_path: $path}')")" CLAUDE_PLUGIN_ROOT=/nonexistent)"
  check "가드: 플러그인 파일 셸 수정" ask "$(guard "$(bashJson night-1 "cp /tmp/x ${TREE}/hooks/hooks.json")")"
  check "가드: 검증 명령 스스로 승인" ask "$(guard "$(bashJson night-1 'claude-loop approve task-night')")"
  check "가드: 야간 상태 지우기" ask "$(guard "$(bashJson night-1 "${RUNNER} end")")"
  check "가드: 러너 조회 명령" pass "$(guard "$(bashJson night-1 'claude-loop list')")"
else
  skipNew "가드: 플러그인 파일 보호 · claude-loop end/approve/install/uninstall"
fi

guard "$(promptJson night-1 '[야간 루프 자동 메시지 — 사용자 입력 아님] 진행하세요')" >/dev/null
check "가드: 야간 메시지는 야간 모드 유지" 있음 "$([[ -f "${NIGHT_DIR}/night-1" ]] && echo 있음 || echo 없음)"
guard "$(promptJson night-1 '어디까지 했어?')" >/dev/null
check "가드: 사람 입력 → 상태 파일 삭제" 없음 "$([[ -f "${NIGHT_DIR}/night-1" ]] && echo 있음 || echo 없음)"
check "가드: 사람 입력 → released 생성" 있음 "$([[ -f "${NIGHT_DIR}/released/night-1" ]] && echo 있음 || echo 없음)"

# =====================================================================
# 검증 게이트
# =====================================================================
gate() {   # gate <세션> [agent_id] [환경변수=값 ...] → block | pass | error:<종료코드>
  local session="$1" agent="${2:-}" output code
  shift
  [[ $# -gt 0 ]] && shift

  output=$(jq -cn --arg session "${session}" --arg agent "${agent}" --arg cwd "${SANDBOX}/cwd" \
      '{session_id: $session, cwd: $cwd} + (if $agent == "" then {} else {agent_id: $agent} end)' \
    | env -i HOME="${FAKE_HOME}" PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin" "$@" bash "${GATE}" 2>/dev/null)
  code=$?

  if [[ ${code} -ne 0 ]]; then
    echo "error:${code}"
  elif grep -q '"decision": *"block"' <<<"${output}"; then
    echo "block"
  elif [[ -z "${output}" ]]; then
    echo "pass"
  else
    echo "unexpected:${output}"
  fi
}

rm -rf "${NIGHT_DIR}" && mkdir -p "${NIGHT_DIR}"
echo '{"name":"task-fail","verify":"echo boom; false"}' >"${NIGHT_DIR}/gate-fail"
echo '{"name":"task-ok","verify":"true"}' >"${NIGHT_DIR}/gate-ok"

check "게이트: 검증 성공" pass "$(gate gate-ok)"
check "게이트: 검증 실패 1회" block "$(gate gate-fail)"
check "게이트: 차단 횟수 기록" 1 "$(cat "${NIGHT_DIR}/blocks/gate-fail" 2>/dev/null)"
check "게이트: 서브에이전트는 검증 안 함" pass "$(gate gate-fail agent-1)"
check "게이트: 검증 실패 2회" block "$(gate gate-fail)"
check "게이트: 검증 실패 3회" block "$(gate gate-fail)"
check "게이트: 3회 뒤에는 통과" pass "$(gate gate-fail)"
check "게이트: 야간 모드 아님" pass "$(gate gate-none)"
touch "${NIGHT_DIR}/active"
check "게이트: CLAUDE_NIGHT_VERIFY 실패" block "$(gate opened-3 "" CLAUDE_NIGHT=1 CLAUDE_NIGHT_VERIFY=false)"

# =====================================================================
# 러너
# =====================================================================
runner() {   # runner [환경변수=값 ...] -- <인자…>
  local -a envArgs=()

  while [[ "$1" != "--" ]]; do
    envArgs+=("$1")
    shift
  done
  shift

  env -i HOME="${FAKE_HOME}" CLAUDE_LOOP_WORKSPACE="${WORKSPACE}" ${envArgs[@]+"${envArgs[@]}"} bash "${RUNNER}" "$@" 2>&1
}

rm -rf "${FAKE_HOME}/.local/state" && : >"${TMUX_LOG}"

for task in T1 T2 T3; do
  mkdir -p "${WORKSPACE}/group/tasks/${task}"
done

printf '# T1\n\n## 루프\n- 세션: task-T1 | 검증: `true`\n\n## 질문 대기열\n- 질문: 시험 질문\n' >"${WORKSPACE}/group/tasks/T1/notes.md"
printf '# T2\n\n## 루프\n- 세션: task-T2\n' >"${WORKSPACE}/group/tasks/T2/notes.md"
printf '# T3\n\n## 루프\n- 세션: task-T3 | 검증: make test\n' >"${WORKSPACE}/group/tasks/T3/notes.md"

if [[ -n "${LEGACY}" ]]; then
  # 원본의 approve 는 항목이 여러 개면 조용히 죽는다 (awk 가 먼저 끝나 SIGPIPE) — 승인 기록을 직접 쓴다
  skipNew "러너: approve (항목이 여러 개일 때)"
  mkdir -p "${FAKE_HOME}/.local/state/claude-loop"
  echo '{"task-T1": "true", "task-T2": ""}' >"${FAKE_HOME}/.local/state/claude-loop/approved.json"
else
  checkContains "러너: approve" "승인: task-T1 — 검증: true" "$(runner -- approve task-T1)"
  checkContains "러너: approve (검증 없음)" "승인: task-T2 — 검증: (없음)" "$(runner -- approve task-T2)"
  checkContains "러너: approve 없는 세션" "줄이 없습니다" "$(runner -- approve task-none)"
fi
listOutput=$(runner -- list)
checkContains "러너: list 승인됨" "$(printf '승인됨\ttask-T1\t검증: true')" "${listOutput}"
checkContains "러너: list 미승인" "$(printf '미승인\ttask-T3\t검증: make test')" "${listOutput}"

dryOutput=$(runner CLAUDE_LOOP_DRY=1 CLAUDE_LOOP_FORCE=1 -- night)
checkContains "러너: dry night 전달 예정" "task-T1: [dry] idle 세션 aaaa1111 에 전달 예정 (pane %9)" "${dryOutput}"
checkContains "러너: dry night 새 세션 예정" "task-T2: [dry] 세션 없음 → tmux 'main' 에 새 window 로 열 예정" "${dryOutput}"
checkContains "러너: dry night 미승인 건너뜀" "task-T3: 건너뜀 (검증 명령 미승인" "${dryOutput}"
check "러너: dry 는 상태를 남기지 않음" 없음 "$([[ -e "${FAKE_HOME}/.local/state/claude-loop/night/active" ]] && echo 있음 || echo 없음)"

: >"${TMUX_LOG}"
nightOutput=$(runner CLAUDE_LOOP_FORCE=1 -- night)
checkContains "러너: night 전달" "task-T1: 전달 (세션 aaaa1111)" "${nightOutput}"
checkContains "러너: night 새 세션" "task-T2: 새 세션 열고 전달 (tmux 'main')" "${nightOutput}"
check "러너: 야간 상태 파일의 검증 명령" "true" "$(jq -r '.verify' "${FAKE_HOME}/.local/state/claude-loop/night/aaaa1111-0000" 2>/dev/null)"
check "러너: active 표시" 있음 "$([[ -f "${FAKE_HOME}/.local/state/claude-loop/night/active" ]] && echo 있음 || echo 없음)"
tmuxLog=$(cat "${TMUX_LOG}")
checkContains "러너: 기존 세션에 글 보내기" "send-keys -t %9 -l [야간 루프 자동 메시지 — 사용자 입력 아님]" "${tmuxLog}"
checkContains "러너: 메시지에 검증 명령" "night.md 를 읽고 그 지시대로 한 바퀴 진행하세요. 검증 명령: true" "${tmuxLog}"
checkContains "러너: 새 window 인자" "new-window -d -t main: -n task-T2 -c ${WORKSPACE}/group/tasks/T2" "${tmuxLog}"
checkContains "러너: 새 세션의 야간 표시" "CLAUDE_NIGHT=1" "${tmuxLog}"
promptPath=$(grep -o '[^ ]*night\.md' <<<"${tmuxLog}" | head -1)
check "러너: 메시지가 가리킨 지시문이 실제로 있음" 있음 "$([[ -f "${promptPath}" ]] && echo 있음 || echo 없음)"

briefOutput=$(runner CLAUDE_LOOP_DRY=1 CLAUDE_LOOP_FORCE=1 -- brief)
checkContains "러너: brief 야간 로그 절" "# 야간 로그" "${briefOutput}"
checkContains "러너: brief 가 야간 로그를 실음" "task-T1: 전달" "${briefOutput}"
checkContains "러너: brief 질문 대기열" "- 질문: 시험 질문" "${briefOutput}"
checkContains "러너: brief 지표 절" "fake-metrics" "${briefOutput}"
checkContains "러너: brief 멈춤 점검 절" "# 멈춤 점검 기록" "${briefOutput}"

if [[ -z "${LEGACY}" ]]; then
  # --- 상위 모델 (CLAUDE_LOOP_UPPER_MODEL) — 없으면 지금과 같고, 있으면 brief 의 --model 과 야간 메시지에 실린다 ---
  : >"${CLAUDE_LOG}"
  runner CLAUDE_LOOP_FORCE=1 -- brief >/dev/null
  checkContains "상위 모델: 없으면 brief 는 --model 없이" "-p --permission-mode dontAsk" "$(cat "${CLAUDE_LOG}")"
  checkContains "상위 모델: brief 가 보고서를 씀" "가짜 아침 보고" "$(cat "${FAKE_HOME}/Library/Logs/claude-loop/$(date '+%F')-brief.md")"

  : >"${CLAUDE_LOG}"
  runner CLAUDE_LOOP_FORCE=1 CLAUDE_LOOP_UPPER_MODEL=fable -- brief >/dev/null
  checkContains "상위 모델: brief 가 --model 로 넘김" "-p --model fable --permission-mode dontAsk" "$(cat "${CLAUDE_LOG}")"

  : >"${TMUX_LOG}"
  runner CLAUDE_LOOP_FORCE=1 CLAUDE_LOOP_UPPER_MODEL=fable -- night >/dev/null
  upperLog=$(cat "${TMUX_LOG}")
  checkContains "상위 모델: 기존 세션 메시지에 실림" "검증 명령: true 상위 모델: fable" "${upperLog}"
  checkContains "상위 모델: 새 세션 메시지에 실림 (한글은 %q 가 8진수로 바꿈)" ":\\ fable\\'; exec zsh" "$(grep new-window <<<"${upperLog}")"
  check "상위 모델: 없을 때 메시지에 없음" 없음 "$(grep -q '상위 모델' <<<"${tmuxLog}" && echo 있음 || echo 없음)"
  checkContains "상위 모델: 지시문이 메시지의 상위 모델을 읽음" "상위 모델: <별칭>" "$(cat "${TREE}/prompts/night.md")"
else
  skipNew "상위 모델 (CLAUDE_LOOP_UPPER_MODEL)"
fi

runner -- end >/dev/null
check "러너: end 가 야간 상태를 지움" 없음 "$([[ -e "${FAKE_HOME}/.local/state/claude-loop/night/active" ]] && echo 있음 || echo 없음)"

touch "${FAKE_HOME}/.local/state/claude-loop/night.disabled"
checkContains "러너: night.disabled" "야간 루프 꺼짐" "$(runner CLAUDE_LOOP_FORCE=1 -- night)"
rm -f "${FAKE_HOME}/.local/state/claude-loop/night.disabled"

if [[ -n "${LEGACY}" ]]; then
  skipNew "러너: 장비 설정 파일 · install · uninstall · 실행 파일"
else
  # --- 장비 설정 파일 ---
  noWorkspace=$(env -i HOME="${FAKE_HOME}" CLAUDE_LOOP_FORCE=1 bash "${RUNNER}" night 2>&1; echo "exit=$?")
  checkContains "러너: 워크스페이스 없으면 안내" "CLAUDE_LOOP_WORKSPACE" "${noWorkspace}"
  checkContains "러너: 워크스페이스 없으면 실패로 끝남" "exit=1" "${noWorkspace}"

  # --- install ---
  launcher="${FAKE_HOME}/.local/bin/claude-loop"
  agents="${FAKE_HOME}/Library/LaunchAgents"
  mkdir -p "${FAKE_HOME}/.local/bin" "${agents}"
  echo "옛 러너" >"${SANDBOX}/old-runner"
  echo "옛 plist" >"${SANDBOX}/old-plist"
  ln -s "${SANDBOX}/old-runner" "${launcher}"
  ln -s "${SANDBOX}/old-plist" "${agents}/com.socoolbear.claude-loop-night.plist"

  dryInstall=$(env -i HOME="${FAKE_HOME}" CLAUDE_LOOP_DRY=1 bash "${RUNNER}" install --workspace "${WORKSPACE}" 2>&1)
  checkContains "install: dry 는 할 일만 출력" "[dry] writeLauncher" "${dryInstall}"
  check "install: dry 는 링크를 그대로 둠" 링크 "$([[ -L "${launcher}" ]] && echo 링크 || echo 파일)"

  : >"${LAUNCHCTL_LOG}"
  env -i HOME="${FAKE_HOME}" bash "${RUNNER}" install --workspace "${WORKSPACE}" >/dev/null 2>&1
  check "install: 실행 파일이 링크가 아닌 파일" 파일 "$([[ -f "${launcher}" && ! -L "${launcher}" ]] && echo 파일 || echo 링크)"
  check "install: 옛 링크의 대상은 그대로" "옛 러너" "$(cat "${SANDBOX}/old-runner")"
  check "install: 옛 plist 링크의 대상은 그대로" "옛 plist" "$(cat "${SANDBOX}/old-plist")"
  check "install: plist 두 개" 2 "$(find "${agents}" -name 'com.socoolbear.claude-loop-*.plist' -type f | wc -l | tr -d ' ')"
  check "install: plist 형식" 0 "$(plutil -lint "${agents}"/com.socoolbear.claude-loop-*.plist >/dev/null 2>&1; echo $?)"
  checkContains "install: brief 는 08:30" "<integer>8</integer>" "$(cat "${agents}/com.socoolbear.claude-loop-brief.plist")"
  checkContains "install: 장비 설정 파일" "CLAUDE_LOOP_WORKSPACE=${WORKSPACE}" "$(cat "${FAKE_HOME}/.config/claude-loop/env")"
  check "install: launchd 등록 (bootstrap 2회)" 2 "$(grep -c '^bootstrap ' "${LAUNCHCTL_LOG}")"

  echo "# 사용자 줄" >>"${FAKE_HOME}/.config/claude-loop/env"
  env -i HOME="${FAKE_HOME}" bash "${RUNNER}" install --workspace /other >/dev/null 2>&1
  checkContains "install: 두 번째 실행은 장비 설정을 건드리지 않음" "# 사용자 줄" "$(cat "${FAKE_HOME}/.config/claude-loop/env")"

  # --- 실행 파일이 러너를 찾는 순서 ---
  notFound=$(env -i HOME="${FAKE_HOME}" bash "${launcher}" list 2>&1; echo "exit=$?")
  checkContains "실행 파일: 러너가 없으면 이유를 냄" "러너를 찾지 못했습니다" "${notFound}"
  checkContains "실행 파일: 러너가 없으면 실패" "exit=1" "${notFound}"

  mkdir -p "${FAKE_HOME}/.claude/plugins"
  jq -n --arg path "${TREE}" '{plugins: {"night-loop@some-marketplace": [{scope: "user", installPath: $path}]}}' >"${FAKE_HOME}/.claude/plugins/installed_plugins.json"
  checkContains "실행 파일: 설치 기록의 경로로 러너를 찾음" "$(printf '승인됨\ttask-T1')" "$(env -i HOME="${FAKE_HOME}" bash "${launcher}" list 2>&1)"

  cp -R "${TREE}" "${SANDBOX}/checkout"
  perl -pi -e 's{^(\s*)echo "사용법: }{$1echo "체크아웃 러너 "; echo "사용법: }' "${SANDBOX}/checkout/bin/claude-loop"
  echo "CLAUDE_LOOP_ROOT=${SANDBOX}/checkout" >>"${FAKE_HOME}/.config/claude-loop/env"
  checkContains "실행 파일: CLAUDE_LOOP_ROOT 가 설치 기록보다 먼저" "체크아웃 러너" "$(env -i HOME="${FAKE_HOME}" bash "${launcher}" help 2>&1)"

  # --- uninstall ---
  env -i HOME="${FAKE_HOME}" bash "${RUNNER}" uninstall >/dev/null 2>&1
  check "uninstall: 실행 파일 삭제" 없음 "$([[ -e "${launcher}" ]] && echo 있음 || echo 없음)"
  check "uninstall: plist 삭제" 0 "$(find "${agents}" -name 'com.socoolbear.claude-loop-*.plist' | wc -l | tr -d ' ')"
  check "uninstall: 장비 설정은 남김" 있음 "$([[ -f "${FAKE_HOME}/.config/claude-loop/env" ]] && echo 있음 || echo 없음)"
fi

echo
echo "결과: ${checks}건 중 실패 ${failures}건"
[[ ${failures} -eq 0 ]]
