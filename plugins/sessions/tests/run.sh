#!/usr/bin/env bash
#
# sessions spawn.sh 시험 — 권한 플래그를 부모 claude 프로세스에서 읽는지 본다.
# 가짜 부모는 이름이 claude 인 bash 심링크로 띄우고, spawn.sh 는 --dry-run 으로 실행할 명령만 받아 본다.
#
#   bash tests/run.sh

set -uo pipefail

readonly PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly CHILD_SPAWN="${PLUGIN_ROOT}/skills/child-session/scripts/spawn.sh"
readonly SIDE_SPAWN="${PLUGIN_ROOT}/skills/side-task/scripts/spawn.sh"

# mktemp 이 실패하면 cd "" 가 지금 폴더에 남아 정리 단계가 저장소를 지운다 — 빈 값이면 바로 멈춘다
readonly WORK="$(tmpDir="$(mktemp -d)" && [[ -n "${tmpDir}" ]] && cd "${tmpDir}" && pwd -P)"
[[ -n "${WORK}" ]] || { echo "임시 폴더를 만들지 못했다 (mktemp)" >&2; exit 1; }

PARENT_PID=""
trap '[[ -n "${PARENT_PID}" ]] && kill "${PARENT_PID}" 2>/dev/null; rm -rf "${WORK}"' EXIT

readonly FAKE_CLAUDE="${WORK}/bin/claude"
readonly SESSION_ID="11111111-2222-3333-4444-555555555555"

mkdir -p "${WORK}/bin" "${WORK}/home/.claude/projects/p"
ln -s /bin/bash "${FAKE_CLAUDE}"
touch "${WORK}/home/.claude/projects/p/${SESSION_ID}.jsonl"
echo "# 브리프" > "${WORK}/brief.md"

passed=0
failed=0
OUT=""

ok() {
  passed=$((passed + 1))
  echo "ok   $1"
}

fail() {
  failed=$((failed + 1))
  echo "FAIL $1 — $2"
}

# 주어진 인자로 가짜 부모 claude 를 띄운다 (ps 의 args 에 그대로 보인다)
startParent() {
  stopParent
  "${FAKE_CLAUDE}" -c 'sleep 60; :' _ "$@" &
  PARENT_PID=$!
}

stopParent() {
  if [[ -n "${PARENT_PID}" ]]; then
    kill "${PARENT_PID}" 2>/dev/null
    wait "${PARENT_PID}" 2>/dev/null
  fi

  PARENT_PID=""
}

# Herdr 쪽 분기로 dry-run 한다 (tmux 를 쓰지 않는다). 출력 중 첫 지시 앞 (-- 앞) 만 OUT 에 담는다
runSpawn() {
  local script="$1"
  shift

  OUT="$(env -u TMUX -u TMUX_PANE HC_TERMINAL_ID=t0 HOME="${WORK}/home" CLAUDE_PID="${PARENT_PID}" \
    CLAUDE_CODE_SESSION_ID="${SESSION_ID}" bash "${script}" --dry-run "$@" 2>/dev/null)"
  OUT="${OUT%% -- *}"
}

expectHas() {
  local label="$1"
  local needle="$2"

  if [[ " ${OUT} " == *" ${needle} "* ]]; then
    ok "${label}"
  else
    fail "${label}" "'${needle}' 가 없다: ${OUT}"
  fi
}

expectLacks() {
  local label="$1"
  local needle="$2"

  # spawn.sh 가 도중에 죽어 출력이 비어도 "없다" 가 참이 되므로 명령이 나왔는지 먼저 본다
  if [[ "${OUT}" != claude\ * ]]; then
    fail "${label}" "실행할 명령이 나오지 않았다: ${OUT}"
    return
  fi

  if [[ " ${OUT} " != *" ${needle} "* ]]; then
    ok "${label}"
  else
    fail "${label}" "'${needle}' 가 있다: ${OUT}"
  fi
}

childArgs=(--parent p --suffix s --brief "${WORK}/brief.md" --cwd "${WORK}")

startParent --dangerously-skip-permissions -- "hi"
runSpawn "${CHILD_SPAWN}" "${childArgs[@]}" --flag --permission-mode --flag auto
expectHas "child: bypass 부모 → 자식 bypass" "--dangerously-skip-permissions"
expectLacks "child: --flag 의 낡은 --permission-mode 는 버림" "--permission-mode"

runSpawn "${CHILD_SPAWN}" "${childArgs[@]}" --resume "${SESSION_ID}" --flag --permission-mode=auto
expectHas "child 재개: bypass 부모 → 자식 bypass" "--dangerously-skip-permissions"
expectLacks "child 재개: --flag 의 --permission-mode=auto 는 버림" "--permission-mode=auto"

startParent --permission-mode plan -- "hi"
runSpawn "${CHILD_SPAWN}" "${childArgs[@]}" --flag --model --flag opus --flag --dangerously-skip-permissions
expectHas "child: plan 부모 → 자식 --permission-mode plan" "--permission-mode plan"
expectHas "child: 권한 아닌 --flag 는 그대로" "--model opus"
expectLacks "child: --flag 의 bypass 는 버림" "--dangerously-skip-permissions"

startParent -- "x --dangerously-skip-permissions --permission-mode auto"
runSpawn "${CHILD_SPAWN}" "${childArgs[@]}"
expectLacks "child: 첫 지시 본문의 bypass 글자는 플래그로 읽지 않음" "--dangerously-skip-permissions"
expectLacks "child: 첫 지시 본문의 --permission-mode 글자는 플래그로 읽지 않음" "--permission-mode"

startParent --dangerously-skip-permissions -- "hi"
runSpawn "${SIDE_SPAWN}" --parent p --suffix s --cwd "${WORK}" --flag --permission-mode --flag auto -- "go"
expectHas "side: bypass 부모 → 분기 세션 bypass" "--dangerously-skip-permissions"
expectHas "side: 분기 인자 유지" "--fork-session"
expectLacks "side: --flag 의 낡은 --permission-mode 는 버림" "--permission-mode"
stopParent

# $CLAUDE_PID 가 없으면 조상 프로세스에서 이름이 claude 인 것을 찾는다
cat > "${WORK}/run-child.sh" <<EOF
env -u TMUX -u TMUX_PANE -u CLAUDE_PID HC_TERMINAL_ID=t0 HOME="${WORK}/home" \\
  bash "${CHILD_SPAWN}" --dry-run --parent p --suffix s --brief "${WORK}/brief.md" --cwd "${WORK}" 2>/dev/null
EOF
OUT="$("${FAKE_CLAUDE}" -c 'bash "$1"; :' _ "${WORK}/run-child.sh" --permission-mode acceptEdits)"
OUT="${OUT%% -- *}"
expectHas "child: \$CLAUDE_PID 없으면 조상 claude 에서 읽음" "--permission-mode acceptEdits"

echo "통과 ${passed} · 실패 ${failed}"
[[ "${failed}" -eq 0 ]]
