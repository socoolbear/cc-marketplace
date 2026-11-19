#!/usr/bin/env bash
# 현재 Claude 세션의 대화를 이어받은 분기 세션을 부모 window 의 패널로 띄운다.
# 부모 패널 말고 다른 패널이 그 window 에 이미 MAX_SIDE_PANES 개면 현재 tmux 세션의 새 window 로 띄운다.
# 사용: spawn.sh --parent <부모 이름> --suffix <접미사> [--cwd <디렉토리>] [--resume <세션 ID>]
#                [--env NAME]... [--flag <claude 인자>]... -- <첫 지시>
#   --resume: 분기하지 않고 닫아 둔 분기 세션을 그 세션 ID 로 다시 연다 (--cwd 는 그 세션이 떴던 디렉토리)
# 출력: place=<pane|window> pane=<%N> name=<세션 이름> cwd=<경로>
# 종료코드: 2 인자 오류 · 3 tmux·세션 환경 없음 · 4 이어받을 대화 기록 없음 · 5 패널·window 생성 실패
set -euo pipefail

usage() {
    echo "사용: spawn.sh --parent <부모 이름> --suffix <접미사> [--cwd <디렉토리>] [--resume <세션 ID>] [--env NAME]... [--flag <claude 인자>]... -- <첫 지시>" >&2
    exit 2
}

parent=""
suffix=""
cwd=""
resume_id=""
env_names=()
flags=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --parent) parent="${2:?--parent 뒤에 이름이 필요합니다}"; shift 2 ;;
        --suffix) suffix="${2:?--suffix 뒤에 접미사가 필요합니다}"; shift 2 ;;
        --cwd) cwd="${2:?--cwd 뒤에 디렉토리가 필요합니다}"; shift 2 ;;
        --resume) resume_id="${2:?--resume 뒤에 세션 ID 가 필요합니다}"; shift 2 ;;
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

# 재개면 닫아 둔 분기 세션을, 아니면 지금 세션을 이어받는다
session_id="${resume_id:-${CLAUDE_CODE_SESSION_ID:-}}"

if [[ -z "${session_id}" ]]; then
    echo "Claude 세션 안에서 실행해야 합니다 (\$CLAUDE_CODE_SESSION_ID 없음)" >&2
    exit 3
fi

if ! compgen -G "${HOME}/.claude/projects/*/${session_id}.jsonl" >/dev/null; then
    echo "이어받을 대화 기록이 없습니다: ~/.claude/projects/*/${session_id}.jsonl" >&2
    exit 4
fi

if [[ -z "${cwd}" ]]; then
    cwd="$(command tmux display -p -t "${TMUX_PANE}" '#{pane_current_path}')"
fi

if [[ ! -d "${cwd}" ]]; then
    echo "작업 디렉토리가 없습니다: ${cwd}" >&2
    exit 2
fi

name="${parent}-${suffix}"
tmux_session="$(command tmux display -p -t "${TMUX_PANE}" '#{session_name}')"
fork_args=(--fork-session)

if [[ -n "${resume_id}" ]]; then
    fork_args=()
fi

# --add-dir 처럼 값을 여러 개 받는 플래그가 첫 지시를 먹지 않도록 -- 로 끊는다
claude_args=(claude --resume "${session_id}" ${fork_args[@]+"${fork_args[@]}"} -n "${name}" ${flags[@]+"${flags[@]}"} -- "${prompt}")
cmd="$(printf '%q ' "${claude_args[@]}"); exec ${SHELL:-/bin/sh}"
env_args=()

for env_name in ${env_names[@]+"${env_names[@]}"}; do
    if [[ -n "${!env_name:-}" ]]; then
        env_args+=(-e "${env_name}=${!env_name}")
    fi
done

# 부모 패널 말고 다른 패널이 이 수만큼 있으면 새 window 로 띄운다 (더 나누면 폭이 좁아 diff·표가 깨진다)
MAX_SIDE_PANES=3

# 부모 window 의 다른 패널을 키 큰 순서로 (한 줄에 "<높이> <pane id>")
list_side_panes() {
    command tmux list-panes -t "${TMUX_PANE}" -F '#{pane_height} #{pane_id}' | grep -v " ${TMUX_PANE}\$" | sort -rn || true
}

open_window() {
    command tmux new-window -d -t "${tmux_session}:" -n "${name}" -c "${cwd}" ${env_args[@]+"${env_args[@]}"} -P -F '#{pane_id}' "${cmd}"
}

# 첫 패널은 부모 오른쪽에, 그다음부터는 가장 키 큰 다른 패널을 위아래로 나눈다 (부모 폭이 계속 줄지 않게)
open_pane() {
    local tallest_pane="$1"

    if [[ -z "${tallest_pane}" ]]; then
        command tmux split-window -d -h -t "${TMUX_PANE}" -c "${cwd}" ${env_args[@]+"${env_args[@]}"} -P -F '#{pane_id}' "${cmd}"
        return
    fi

    command tmux split-window -d -v -t "${tallest_pane}" -c "${cwd}" ${env_args[@]+"${env_args[@]}"} -P -F '#{pane_id}' "${cmd}"
}

side_panes="$(list_side_panes)"
side_pane_count="$(printf '%s' "${side_panes}" | grep -c . || true)"
tallest_pane="$(printf '%s\n' "${side_panes}" | head -1 | cut -d' ' -f2)"
place="pane"
created=""

if [[ "${side_pane_count}" -lt "${MAX_SIDE_PANES}" ]]; then
    created="$(open_pane "${tallest_pane}")" || created=""
fi

# 위아래로 나눈 열의 높이를 고르게 편다 (부모 패널 크기는 그대로)
if [[ -n "${created}" && -n "${tallest_pane}" ]]; then
    command tmux select-layout -E -t "${created##* }" || true
fi

# 패널 자리가 없거나 나누지 못했으면 (공간 부족 등) window 로 띄운다
if [[ -z "${created}" ]]; then
    place="window"

    if ! created="$(open_window)"; then
        echo "패널·window 를 만들지 못했습니다" >&2
        exit 5
    fi
fi

echo "place=${place} pane=${created} name=${name} cwd=${cwd}"
