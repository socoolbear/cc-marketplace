#!/usr/bin/env bash
# 현재 Claude 세션의 대화를 이어받은 분기 세션을 부모 window 의 패널로 띄운다.
# tmux 밖의 Herdr 터미널 ($HC_TERMINAL_ID) 에서 부르면 부모 터미널에 딸린 Herdr 터미널로 띄운다.
# 부모 패널 말고 다른 패널이 그 window 에 이미 MAX_SIDE_PANES 개면 현재 tmux 세션의 새 window 로 띄운다.
# 사용: spawn.sh --parent <부모 이름> --suffix <접미사> [--cwd <디렉토리>] [--resume <세션 ID>]
#                [--dry-run] [--env NAME]... [--flag <claude 인자>]... -- <첫 지시>
#   --resume: 분기하지 않고 닫아 둔 분기 세션을 그 세션 ID 로 다시 연다 (--cwd 는 그 세션이 떴던 디렉토리)
#   --dry-run: 띄우지 않고 실행할 claude 명령만 출력한다
# 권한 플래그 (--dangerously-skip-permissions · --allow-dangerously-skip-permissions · --permission-mode) 는
# 부모 claude 프로세스의 실행 인자에서 읽어 붙이고, --flag 로 들어온 권한 플래그는 버린다 (부모를 못 찾으면 --flag 그대로).
# 출력: place=<pane|window> pane=<%N> name=<세션 이름> cwd=<경로>
#       Herdr 면 place=herdr terminal=<터미널 주소> name=<세션 이름> cwd=<경로>
# 종료코드: 2 인자 오류 · 3 tmux·Herdr 터미널 밖이거나 세션 환경 없음 · 4 이어받을 대화 기록 없음 · 5 패널·window·터미널 생성 실패
set -euo pipefail

usage() {
    echo "사용: spawn.sh --parent <부모 이름> --suffix <접미사> [--cwd <디렉토리>] [--resume <세션 ID>] [--dry-run] [--env NAME]... [--flag <claude 인자>]... -- <첫 지시>" >&2
    exit 2
}

parent=""
suffix=""
cwd=""
resume_id=""
dry_run=""
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
        --dry-run) dry_run="yes"; shift ;;
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

# tmux 안이면 tmux pane·window 로, tmux 밖의 Herdr 터미널이면 Herdr 터미널로 띄운다
host="tmux"

if [[ -z "${TMUX:-}" || -z "${TMUX_PANE:-}" ]]; then
    host="herdr"
fi

if [[ "${host}" == "herdr" && -z "${HC_TERMINAL_ID:-}" ]]; then
    echo "tmux 나 Herdr 터미널 안에서 실행해야 합니다 (\$TMUX·\$TMUX_PANE·\$HC_TERMINAL_ID 없음)" >&2
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

if [[ -z "${cwd}" && "${host}" == "herdr" ]]; then
    cwd="${PWD}"
fi

if [[ -z "${cwd}" ]]; then
    cwd="$(command tmux display -p -t "${TMUX_PANE}" '#{pane_current_path}')"
fi

if [[ ! -d "${cwd}" ]]; then
    echo "작업 디렉토리가 없습니다: ${cwd}" >&2
    exit 2
fi

name="${parent}-${suffix}"
fork_args=(--fork-session)

if [[ -n "${resume_id}" ]]; then
    fork_args=()
fi

# 부모 claude 프로세스 PID — Claude Code 가 도구 셸에 주는 $CLAUDE_PID, 없으면 조상 프로세스에서 이름이 claude 인 것
find_parent_claude_pid() {
    local pid="${CLAUDE_PID:-}"
    local depth=0

    if [[ -n "${pid}" ]] && ps -p "${pid}" >/dev/null 2>&1; then
        printf '%s' "${pid}"
        return
    fi

    pid="${PPID}"

    while [[ -n "${pid}" && "${pid}" -gt 1 && "${depth}" -lt 20 ]]; do
        if [[ "$(basename "$(ps -o comm= -p "${pid}" 2>/dev/null)")" == "claude" ]]; then
            printf '%s' "${pid}"
            return
        fi

        pid="$(ps -o ppid= -p "${pid}" 2>/dev/null | tr -d ' ')"
        depth=$((depth + 1))
    done
}

# 부모 claude 의 실행 인자에서 권한 플래그만 골라 permission_args 에 담는다. 첫 지시 앞의 -- 에서 멈춘다 (지시 본문의 글자를 플래그로 읽지 않게)
read_parent_permission_args() {
    local parent_args=()
    local token
    local want_value=""

    read -r -a parent_args <<< "$(ps -ww -o args= -p "$1" 2>/dev/null)" || true

    for token in ${parent_args[@]+"${parent_args[@]}"}; do
        if [[ -n "${want_value}" ]]; then
            permission_args+=(--permission-mode "${token}")
            want_value=""
            continue
        fi

        case "${token}" in
            --) break ;;
            --dangerously-skip-permissions | --allow-dangerously-skip-permissions | --permission-mode=*) permission_args+=("${token}") ;;
            --permission-mode) want_value="yes" ;;
        esac
    done
}

# --flag 로 들어온 권한 플래그를 버린다 — 부모 대화에 남은 낡은 값이 부모의 실제 모드를 덮지 않게
drop_permission_flags() {
    local kept=()
    local flag
    local skip_value=""

    for flag in ${flags[@]+"${flags[@]}"}; do
        if [[ -n "${skip_value}" ]]; then
            skip_value=""
            continue
        fi

        case "${flag}" in
            --dangerously-skip-permissions | --allow-dangerously-skip-permissions | --permission-mode=*) continue ;;
            --permission-mode) skip_value="yes"; continue ;;
        esac

        kept+=("${flag}")
    done

    flags=(${kept[@]+"${kept[@]}"})
}

permission_args=()
parent_claude_pid="$(find_parent_claude_pid)"

if [[ -n "${parent_claude_pid}" ]]; then
    read_parent_permission_args "${parent_claude_pid}"
    drop_permission_flags
    echo "권한 플래그: ${permission_args[*]:-없음 (settings 기본값)} — 부모 claude (PID ${parent_claude_pid}) 실행 인자에서 읽음" >&2
else
    echo "부모 claude 프로세스를 찾지 못해 --flag 의 권한 플래그를 그대로 씁니다" >&2
fi

# --add-dir 처럼 값을 여러 개 받는 플래그가 첫 지시를 먹지 않도록 -- 로 끊는다
claude_args=(claude --resume "${session_id}" ${fork_args[@]+"${fork_args[@]}"} -n "${name}" ${flags[@]+"${flags[@]}"} ${permission_args[@]+"${permission_args[@]}"} -- "${prompt}")
cmd="$(printf '%q ' "${claude_args[@]}"); exec ${SHELL:-/bin/sh}"

if [[ -n "${dry_run}" ]]; then
    printf '%q ' "${claude_args[@]}"
    printf '\n'
    exit 0
fi

# Herdr 터미널 이름: 소문자·숫자·-·_ 32자까지. 넘으면 앞을 남기고 전체 이름의 해시를 붙인다
build_herdr_name() {
    local herdr_name

    herdr_name="$(printf '%s' "${name}" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_-' '-')"

    if [[ "${#herdr_name}" -gt 32 ]]; then
        herdr_name="${herdr_name:0:23}-$(printf '%08x' "$(printf '%s' "${name}" | cksum | cut -d' ' -f1)")"
    fi

    printf '%s' "${herdr_name}"
}

# Herdr 터미널은 이 세션이 아니라 herdr-core 서버의 환경을 물려받으므로 넘길 변수를 env 로 명령에 싣는다.
# PATH 는 늘 싣는다 — 서버의 PATH 는 시스템 경로뿐이라 node 등으로 도는 사용자 훅이 command not found 로 실패하고 그대로 통과된다
open_herdr_terminal() {
    local env_pairs=("PATH=${PATH}")
    local env_name

    for env_name in ${env_names[@]+"${env_names[@]}"}; do
        if [[ "${env_name}" != "PATH" && -n "${!env_name:-}" ]]; then
            env_pairs+=("${env_name}=${!env_name}")
        fi
    done

    # cmd 를 쓰지 않고 인자 그대로 넘긴다 — bash 3.2 의 %q 는 한글 바이트 일부만 8진수로 바꿔 UTF-8 이 아닌 문자열을 만들고 hc 는 그런 인자를 거부한다
    command hc run --bg --json --name "$(build_herdr_name)" --cwd "${cwd}" --parent "${HC_TERMINAL_ID}" -- \
        env ${env_pairs[@]+"${env_pairs[@]}"} /bin/sh -c '"$@"; exec "$0"' "${SHELL:-/bin/sh}" "${claude_args[@]}" \
        | sed -n 's/.*"address":"\([^"]*\)".*/\1/p'
}

if [[ "${host}" == "herdr" ]]; then
    terminal="$(open_herdr_terminal)" || terminal=""

    if [[ -z "${terminal}" ]]; then
        echo "Herdr 터미널을 만들지 못했습니다" >&2
        exit 5
    fi

    echo "place=herdr terminal=${terminal} name=${name} cwd=${cwd}"
    exit 0
fi

tmux_session="$(command tmux display -p -t "${TMUX_PANE}" '#{session_name}')"
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
