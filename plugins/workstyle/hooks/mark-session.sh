#!/usr/bin/env bash
# SessionStart 훅 — 이 세션에 workstyle 플러그인의 훅이 실렸다는 표시를 남긴다 (내용은 이 플러그인 폴더의 경로).
# 같은 장치를 설정 파일의 훅으로도 돌리던 장비가 플러그인으로 옮겨 올 때, 설정 쪽 훅이 이 표시를 보고 물러난다
# (표시가 없거나 표시가 가리키는 폴더에 훅이 없으면 설정 쪽이 계속 돈다 — 옮기는 동안 장치가 꺼지지 않게). 실패해도 세션을 막지 않는다.
set -uo pipefail

plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)"
session_id=$(jq -r '.session_id // empty' 2>/dev/null)

[[ "${session_id}" =~ ^[A-Za-z0-9_-]+$ ]] || exit 0

marker_dir="${TMPDIR:-/tmp}/claude-plugin-sessions"

mkdir -p "${marker_dir}" 2>/dev/null && printf '%s\n' "${plugin_root}" >"${marker_dir}/workstyle-${session_id}" 2>/dev/null

exit 0
