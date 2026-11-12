#!/usr/bin/env bash
# taskspace 태스크 notes.md 에서 단서(오류 클래스·파일:줄·요청 경로·링크 등)를 찾아 후보 태스크를 순위대로 보여 준다.
# 읽기 전용. 사용: find-task.sh [--root <워크스페이스 루트>] <단서> [<단서>...]
# 출력: 일치 단서 수 · 총 일치 줄 수 · ID · 상태 · 제목, 그 아래 일치한 단서와 예시 줄 (줄 번호 포함)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TS="${SCRIPT_DIR}/../../taskspace/scripts/taskspace.sh"
ROOT="${TASKSPACE_ROOT:-}"

if [[ "${1:-}" == "--root" ]]; then
    ROOT="${2:?--root 뒤에 경로가 필요합니다}"
    shift 2
fi

if [[ $# -eq 0 ]]; then
    echo "사용: find-task.sh [--root <워크스페이스 루트>] <단서> [<단서>...]" >&2
    exit 2
fi

if [[ -z "${ROOT}" ]]; then
    ROOT="$(bash "${TS}" root 2>/dev/null)" || { echo "taskspace 루트를 찾지 못했습니다" >&2; exit 3; }
fi

read_status() {
    local notes="$1"
    local kind="$2"

    if [[ "${kind}" == "tasks" ]]; then
        echo "진행 중"
        return
    fi

    # 머리말(첫 '## ' 전) 의 '- 상태:' 만 본다
    local status
    status="$(awk '/^## /{exit} /^- 상태:/{sub(/^- 상태:[[:space:]]*/,""); print; exit}' "${notes}")"

    if [[ -z "${status}" ]] && awk '/^## /{exit} /^- 완료 일시:/{found=1} END{exit !found}' "${notes}"; then
        status="완료"
    fi

    echo "${status:-알 수 없음}"
}

results=""

for kind in tasks archive; do
    for notes in "${ROOT}/${kind}"/*/notes.md; do
        [[ -f "${notes}" ]] || continue

        id="$(basename "$(dirname "${notes}")")"
        matched_terms=0
        total_lines=0
        detail=""

        for raw in "$@"; do
            # notes 는 경로를 앞 '/' 없이 적는 일이 많다 — '/a/b.php' 로는 'a/b.php' 가 안 잡힌다
            term="${raw#/}"
            [[ -n "${term}" ]] || continue

            count="$(grep -F -i -c -- "${term}" "${notes}" || true)"

            if [[ "${count}" -gt 0 ]]; then
                matched_terms=$((matched_terms + 1))
                total_lines=$((total_lines + count))
                sample="$(grep -F -i -n -m 2 -- "${term}" "${notes}" | cut -c1-160 | sed 's/^/      /')"
                detail+="    [${term}] ${count}줄"$'\n'"${sample}"$'\n'
            fi
        done

        if [[ "${matched_terms}" -gt 0 ]]; then
            title="$(head -n 1 "${notes}" | sed 's/^# *//')"
            status="$(read_status "${notes}" "${kind}")"
            header="${matched_terms}/$# 단서 · ${total_lines}줄 · ${id} · ${status} · ${title}"
            # 정렬 키(단서 수, 줄 수) 를 앞에 붙였다가 출력 때 뗀다
            results+="$(printf '%03d\t%05d\t%s' "${matched_terms}" "${total_lines}" "${header}")"$'\x1e'"${detail}"$'\x1f'
        fi
    done
done

if [[ -z "${results}" ]]; then
    echo "일치하는 태스크 없음 (단서 $#개)"
    exit 0
fi

printf '%s' "${results}" | tr '\037' '\0' | sort -z -r | while IFS= read -r -d '' record; do
    header="${record%%$'\x1e'*}"
    detail="${record#*$'\x1e'}"
    echo "${header#*$'\t'*$'\t'}"
    printf '%s' "${detail}"
done
