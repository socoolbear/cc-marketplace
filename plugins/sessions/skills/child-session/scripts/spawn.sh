#!/usr/bin/env bash
# 브리프를 받아 일하는 새 Claude 세션 (자식 세션) 을 부모 window 의 pane 으로 띄운다.
# tmux 밖의 Herdr 터미널 ($HC_TERMINAL_ID) 에서 부르면 부모 터미널에 딸린 Herdr 터미널로 띄운다.
# 부모 pane 말고 다른 pane 이 그 window 에 이미 MAX_SIDE_PANES 개면 현재 tmux 세션의 새 window 로 띄운다.
# 첫 지시는 이 스크립트가 만든다 (자식 규약 child.md 와 브리프의 절대 경로, 부모 주소).
# 사용: spawn.sh --parent <부모 이름> [--parent-ref <ref>] --suffix <접미사> --brief <브리프 파일> [--cwd <디렉토리>]
#                [--resume <세션 ID>] [--window] [--env NAME]... [--flag <claude 인자>]... [-- <덧붙일 지시>]
#   --resume: 새로 띄우지 않고 닫아 둔 자식 세션을 그 세션 ID 로 다시 연다 (--cwd 는 그 세션이 떴던 디렉토리)
#   --window: pane 수와 상관없이 새 window 로 띄운다 (Herdr 에서는 쓰이지 않는다)
# 출력: place=<pane|window> window=<@N> pane=<%N> name=<세션 이름> cwd=<경로>
#       Herdr 면 place=herdr terminal=<터미널 주소> name=<세션 이름> cwd=<경로>
# 종료코드: 2 인자 오류 · 3 tmux·Herdr 터미널 밖 · 4 재개할 대화 기록 없음 · 5 pane·window·터미널 생성 실패
set -euo pipefail

usage() {
    echo "사용: spawn.sh --parent <부모 이름> [--parent-ref <ref>] --suffix <접미사> --brief <브리프 파일> [--cwd <디렉토리>] [--resume <세션 ID>] [--window] [--env NAME]... [--flag <claude 인자>]... [-- <덧붙일 지시>]" >&2
    exit 2
}

parent=""
parent_ref=""
suffix=""
brief=""
cwd=""
resume_id=""
force_window=""
env_names=()
flags=()

while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--" ]]; then
        shift
        break
    fi

    if [[ "$1" == "--window" ]]; then
        force_window="yes"
        shift
        continue
    fi

    [[ $# -ge 2 ]] || usage

    case "$1" in
        --parent) parent="$2" ;;
        --parent-ref) parent_ref="$2" ;;
        --suffix) suffix="$2" ;;
        --brief) brief="$2" ;;
        --cwd) cwd="$2" ;;
        --resume) resume_id="$2" ;;
        --env) env_names+=("$2") ;;
        --flag) flags+=("$2") ;;
        *) usage ;;
    esac

    shift 2
done

extra="${*:-}"

if [[ -z "${parent}" || -z "${suffix}" || -z "${brief}" ]]; then
    usage
fi

if [[ ! "${suffix}" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    echo "접미사는 영문 소문자·숫자·- 만 씁니다: ${suffix}" >&2
    exit 2
fi

if [[ ! -f "${brief}" ]]; then
    echo "브리프 파일이 없습니다: ${brief}" >&2
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

if [[ -n "${resume_id}" ]] && ! compgen -G "${HOME}/.claude/projects/*/${resume_id}.jsonl" >/dev/null; then
    echo "재개할 대화 기록이 없습니다: ~/.claude/projects/*/${resume_id}.jsonl" >&2
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

brief_path="$(cd "$(dirname "${brief}")" && pwd)/$(basename "${brief}")"
child_rules="$(cd "$(dirname "${BASH_SOURCE[0]}")/../references" && pwd)/child.md"
name="${parent}-${suffix}"
parent_address="${parent}${parent_ref:+ [${parent_ref}]}"

# --add-dir 처럼 값을 여러 개 받는 플래그가 첫 지시를 먹지 않도록 -- 로 끊는다
if [[ -n "${resume_id}" ]]; then
    prompt="child-session 자식 세션 ${name} 을 후속 문의로 다시 열었습니다. 부모는 ${parent_address} 입니다 (보고할 때 이 주소 그대로). ${child_rules} 와 브리프 ${brief_path} 를 다시 읽고 따르세요.${extra:+ ${extra}}"
    claude_args=(claude --resume "${resume_id}" -n "${name}" ${flags[@]+"${flags[@]}"} -- "${prompt}")
else
    prompt="child-session 자식 세션 ${name} 입니다. 부모는 ${parent_address} 입니다 (보고할 때 이 주소 그대로). 먼저 ${child_rules} 와 브리프 ${brief_path} 를 읽고 따르세요.${extra:+ ${extra}}"
    claude_args=(claude -n "${name}" ${flags[@]+"${flags[@]}"} -- "${prompt}")
fi

cmd="$(printf '%q ' "${claude_args[@]}"); exec ${SHELL:-/bin/sh}"

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

# 부모 pane 말고 다른 pane 이 이 수만큼 있으면 새 window 로 띄운다 (더 나누면 폭이 좁아 diff·표가 깨진다)
MAX_SIDE_PANES=3

# 부모 window 의 다른 pane 을 키 큰 순서로 (한 줄에 "<높이> <pane id>")
list_side_panes() {
    command tmux list-panes -t "${TMUX_PANE}" -F '#{pane_height} #{pane_id}' | grep -v " ${TMUX_PANE}\$" | sort -rn || true
}

open_window() {
    command tmux new-window -d -t "${tmux_session}:" -n "${name}" -c "${cwd}" ${env_args[@]+"${env_args[@]}"} -P -F '#{window_id} #{pane_id}' "${cmd}"
}

# 첫 pane 은 부모 오른쪽에, 그다음부터는 가장 키 큰 다른 pane 을 위아래로 나눈다 (부모 폭이 계속 줄지 않게)
open_pane() {
    local tallest_pane="$1"

    if [[ -z "${tallest_pane}" ]]; then
        command tmux split-window -d -h -t "${TMUX_PANE}" -c "${cwd}" ${env_args[@]+"${env_args[@]}"} -P -F '#{window_id} #{pane_id}' "${cmd}"
        return
    fi

    command tmux split-window -d -v -t "${tallest_pane}" -c "${cwd}" ${env_args[@]+"${env_args[@]}"} -P -F '#{window_id} #{pane_id}' "${cmd}"
}

side_panes="$(list_side_panes)"
side_pane_count="$(printf '%s' "${side_panes}" | grep -c . || true)"
tallest_pane="$(printf '%s\n' "${side_panes}" | head -1 | cut -d' ' -f2)"
place="pane"
created=""

if [[ -z "${force_window}" && "${side_pane_count}" -lt "${MAX_SIDE_PANES}" ]]; then
    created="$(open_pane "${tallest_pane}")" || created=""
fi

# 위아래로 나눈 열의 높이를 고르게 편다 (부모 pane 크기는 그대로)
if [[ -n "${created}" && -n "${tallest_pane}" ]]; then
    command tmux select-layout -E -t "${created##* }" || true
fi

# pane 자리가 없거나 나누지 못했으면 (공간 부족 등) window 로 띄운다
if [[ -z "${created}" ]]; then
    place="window"

    if ! created="$(open_window)"; then
        echo "pane·window 를 만들지 못했습니다" >&2
        exit 5
    fi
fi

echo "place=${place} window=${created% *} pane=${created#* } name=${name} cwd=${cwd}"
