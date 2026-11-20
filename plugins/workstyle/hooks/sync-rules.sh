#!/usr/bin/env bash
# SessionStart 훅 — 취향 규칙 (이 플러그인의 rules/) 을 고정 폴더 ~/.claude/workstyle 에 내놓는다.
#
# 전역 지시 파일 (~/.claude/CLAUDE.md) 이 그 폴더의 글을 import 한다. 설치본 경로는 커밋마다 바뀌어 import 대상이 될 수 없다.
#   - 고정 폴더가 없다                      → 설치본의 rules/ 를 복사한다 (사본 표시 파일 .synced-copy 를 함께 둔다)
#   - 사본 표시가 있는 폴더고 내용이 다르다 → 설치본 내용으로 맞춘다 (사본을 직접 고친 것은 사라진다)
#   - 심링크다 (개발 장비 — 플러그인 체크아웃을 가리킨다) → 건드리지 않는다. 끊겼으면 알린다
#   - 사본 표시가 없는 폴더다               → 이 훅이 만든 것이 아니므로 건드리지 않고 알린다
# 전역 지시 파일에 import 줄이 없으면 알린다. 실패해도 세션을 막지 않는다.
set -uo pipefail

readonly PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)"
readonly SOURCE_DIR="${PLUGIN_ROOT}/rules"
readonly TARGET_DIR="${WORKSTYLE_RULES_DIR:-${HOME}/.claude/workstyle}"
readonly GLOBAL_FILE="${HOME}/.claude/CLAUDE.md"
readonly COPY_MARK=".synced-copy"

notes=()

syncCopy() {
  local staging="${TARGET_DIR}.sync.$$"
  local previous="${TARGET_DIR}.old.$$"

  rm -rf "${staging}" "${previous}"
  cp -R "${SOURCE_DIR}" "${staging}" || return 1
  printf '%s\n' "workstyle 플러그인의 세션 시작 훅이 맞추는 사본이다. 여기서 고친 내용은 다음 맞추기 때 사라진다 — 규칙은 플러그인 저장소의 rules/ 에서 고친다." >"${staging}/${COPY_MARK}"

  if [[ -e "${TARGET_DIR}" ]]; then
    mv "${TARGET_DIR}" "${previous}" || { rm -rf "${staging}"; return 1; }
  fi

  mkdir -p "$(dirname "${TARGET_DIR}")"
  mv "${staging}" "${TARGET_DIR}" || { [[ -e "${previous}" ]] && mv "${previous}" "${TARGET_DIR}"; return 1; }
  rm -rf "${previous}"
}

# 이 플러그인은 버전 번호가 없어 "옛 판에 머문 장비" 를 다른 곳에서 잡지 못한다. 설치본과 이 장비의 마켓플레이스 사본
# (마켓플레이스를 갱신할 때 바뀐다) 의 내용이 다르면 알린다. 읽기만 하고 네트워크를 쓰지 않는다
checkStale() {
  [[ "${PLUGIN_ROOT}" =~ ^(.*/plugins)/cache/([^/]+)/workstyle/[^/]+$ ]] || return 0

  local marketplace="${BASH_REMATCH[2]}"
  local latest="${BASH_REMATCH[1]}/marketplaces/${marketplace}/plugins/workstyle"

  [[ -d "${latest}" ]] || return 0

  if ! diff -rq -x ".orphaned_at" "${latest}" "${PLUGIN_ROOT}" >/dev/null 2>&1; then
    notes+=("설치된 workstyle 이 이 장비의 마켓플레이스 사본과 내용이 다르다 — 옛 규칙 · 훅으로 일하고 있을 수 있다. claude plugin update workstyle@${marketplace} 를 실행하고 세션을 다시 연다")
  fi
}

[[ -d "${SOURCE_DIR}" ]] || exit 0

checkStale

if [[ -L "${TARGET_DIR}" ]]; then
  [[ -e "${TARGET_DIR}" ]] || notes+=("취향 규칙 폴더 ${TARGET_DIR} 가 끊긴 심링크다 — 규칙이 실리지 않는다. /workstyle:setup 으로 다시 건다")
elif [[ ! -e "${TARGET_DIR}" ]]; then
  syncCopy || notes+=("취향 규칙 폴더 ${TARGET_DIR} 를 만들지 못했다 — /workstyle:setup 으로 확인한다")
elif [[ -f "${TARGET_DIR}/${COPY_MARK}" ]]; then
  if ! diff -rq -x "${COPY_MARK}" "${SOURCE_DIR}" "${TARGET_DIR}" >/dev/null 2>&1; then
    syncCopy || notes+=("취향 규칙 폴더 ${TARGET_DIR} 를 새 내용으로 맞추지 못했다 — /workstyle:setup 으로 확인한다")
  fi
else
  notes+=("취향 규칙 폴더 ${TARGET_DIR} 가 workstyle 이 만든 사본도 심링크도 아니다 — 그대로 두었다. /workstyle:setup 으로 정리한다")
fi

if ! grep -qF "workstyle/AGENTS.md" "${GLOBAL_FILE}" 2>/dev/null; then
  notes+=("전역 지시 파일 ${GLOBAL_FILE} 에 workstyle 취향 규칙의 import 줄이 없다 — 규칙이 실리지 않는다. /workstyle:setup 으로 넣는다")
fi

(( ${#notes[@]} > 0 )) || exit 0

message=$(printf '[workstyle] %s\n' "${notes[@]}")

jq -n --arg msg "${message}" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $msg}}' 2>/dev/null

exit 0
