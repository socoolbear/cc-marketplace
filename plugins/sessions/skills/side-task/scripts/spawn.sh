#!/usr/bin/env bash
# 현재 Claude 세션의 대화를 이어받은 분기 세션을 부모 tmux 패널 옆에 띄운다.
# 사용: spawn.sh --parent <부모 이름> --suffix <접미사> [--env NAME]... [--flag <claude 인자>]... -- <첫 지시>
# 출력: pane=<%N> name=<세션 이름> cwd=<경로>
# 종료코드: 2 인자 오류 · 3 tmux·세션 환경 없음 · 4 fork 할 대화 기록 없음 · 5 패널 분할 실패
set -euo pipefail

usage() {
    echo "사용: spawn.sh --parent <부모 이름> --suffix <접미사> [--env NAME]... [--flag <claude 인자>]... -- <첫 지시>" >&2
    exit 2
}

parent=""
suffix=""
env_names=()
flags=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --parent) parent="${2:?--parent 뒤에 이름이 필요합니다}"; shift 2 ;;
        --suffix) suffix="${2:?--suffix 뒤에 접미사가 필요합니다}"; shift 2 ;;
        --env) env_names+=("${2:?--env 뒤에 변수 이름이 필요합니다}"); shift 2 ;;
        --flag) flags+=("${2:?--flag 뒤에 인자가 필요합니다}"); shift 2 ;;
        --) shift; break ;;
        *) usage ;;
    esac
done

prompt="${*:-}"

if [[ -z "${parent}" || -z "${suffix}" || -z "${prompt}" ]]; then
    usage
fi

if [[ ! "${suffix}" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    echo "접미사는 영문 소문자·숫자·- 만 씁니다: ${suffix}" >&2
    exit 2
fi

if [[ -z "${TMUX:-}" || -z "${TMUX_PANE:-}" ]]; then
    echo "tmux 안에서 실행해야 합니다 (\$TMUX·\$TMUX_PANE 없음)" >&2
    exit 3
fi

session_id="${CLAUDE_CODE_SESSION_ID:-}"

if [[ -z "${session_id}" ]]; then
    echo "Claude 세션 안에서 실행해야 합니다 (\$CLAUDE_CODE_SESSION_ID 없음)" >&2
    exit 3
fi

if ! compgen -G "${HOME}/.claude/projects/*/${session_id}.jsonl" >/dev/null; then
    echo "fork 할 대화 기록이 없습니다: ~/.claude/projects/*/${session_id}.jsonl" >&2
    exit 4
fi

name="${parent}-${suffix}"
cwd="$(command tmux display -p -t "${TMUX_PANE}" '#{pane_current_path}')"

claude_args=(claude --resume "${session_id}" --fork-session -n "${name}" ${flags[@]+"${flags[@]}"} "${prompt}")
cmd="$(printf '%q ' "${claude_args[@]}"); exec ${SHELL:-/bin/sh}"

env_args=()

for env_name in ${env_names[@]+"${env_names[@]}"}; do
    if [[ -n "${!env_name:-}" ]]; then
        env_args+=(-e "${env_name}=${!env_name}")
    fi
done

if ! pane="$(command tmux split-window -d -h -t "${TMUX_PANE}" -c "${cwd}" ${env_args[@]+"${env_args[@]}"} -P -F '#{pane_id}' "${cmd}")"; then
    echo "패널을 나누지 못했습니다 (공간 부족이면 다른 패널을 닫거나 창을 넓혀 주세요)" >&2
    exit 5
fi

echo "pane=${pane} name=${name} cwd=${cwd}"
