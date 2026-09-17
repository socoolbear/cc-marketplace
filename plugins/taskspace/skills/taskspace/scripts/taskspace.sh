#!/bin/bash
# taskspace.sh — bare 저장소 중앙 관리 + tasks/<TASK-ID>/ 격리 작업 환경
#
# 구조:
#   <root>/                 워크스페이스 repo (notes 추적용)
#   ├── .gitignore          .bares/ .local/ tasks/*/*/
#   ├── repos.txt           등록한 repo 목록 (<url>[=<name>] 한 줄씩)
#   ├── .bares/<repo>.git/  bare 저장소 (ignore)
#   ├── .local/<repo>/      repo 별 로컬 파일 원본 (.env 등, ignore) → worktree 에 심링크
#   └── tasks/<ID>/         notes.md (추적) · .prompts/ (ignore) · <repo>/ worktree (ignore)
#
# macOS 기본 bash 3.2 호환 (연관배열·mapfile 사용 금지, 빈 배열은 ${arr[@]+"${arr[@]}"}).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="${SCRIPT_DIR}/../references/notes-template.md"
GITIGNORE_LINES=".bares/
.local/
tasks/*/*/"

ROOT=""

log() { printf '%s\n' "$*" >&2; }
die() { local code=$1; shift; log "❌ $*"; exit "${code}"; }

usage() {
  cat >&2 <<'EOF'
사용법: taskspace.sh <서브커맨드> [인자...]

  root                                       루트 절대경로 출력
  init [<dir>] [<url>[=<name>]...]           최초 세팅 (디렉토리 · git init · .gitignore · bare 등록)
  add  [<url>[=<name>]...]                   bare 등록. 인자 없으면 repos.txt 의 미등록 항목 전부
  repos                                      등록된 repo 와 기본 브랜치 · 열린 worktree 수
  new  <TASK-ID> [<repo>[=<branch>]...]      태스크 생성 + worktree + notes.md + 심링크
  link <TASK-ID> [<repo>...]                 .local/<repo>/ 의 파일을 worktree 에 상대 심링크
  sync <TASK-ID> [<repo>...] [--rebase]      worktree 에 origin/<기본 브랜치> 반영 (merge 기본)
  done <TASK-ID> [--merged] [--discard-untracked] [--delete-branch] [--force]
                                             worktree 제거 (notes.md 보존). 안전 검사 통과 시에만
  list                                       태스크 목록

종료코드: 1 인자 오류 · 2 루트 없음 · 3 repo 미지정 · 4 done 차단 · 5 sync 미완료
EOF
  exit 1
}

# ---------------------------------------------------------------- 공통

# 루트 마커: .bares/ 디렉토리 또는 repos.txt (워크스페이스 repo 를 clone 한 직후엔 .bares/ 가 없다)
is_root() { [[ -d "$1/.bares" || -f "$1/repos.txt" ]]; }

find_root() {
  if [[ -n "${TASKSPACE_ROOT:-}" ]]; then
    is_root "${TASKSPACE_ROOT}" || { log "TASKSPACE_ROOT 가 taskspace 루트가 아닙니다 (.bares/ 또는 repos.txt 없음): ${TASKSPACE_ROOT}"; return 1; }
    (cd "${TASKSPACE_ROOT}" && pwd)
    return 0
  fi

  local dir
  dir="$(pwd)"

  while true; do
    if is_root "${dir}"; then
      printf '%s\n' "${dir}"
      return 0
    fi
    [[ "${dir}" == "/" ]] && return 1
    dir="$(dirname "${dir}")"
  done
}

require_root() {
  ROOT="$(find_root)" || die 2 "taskspace 루트 (.bares/ 또는 repos.txt 가 있는 디렉토리) 를 찾지 못했습니다. 'taskspace.sh init [<dir>] [<url>...]' 로 최초 세팅하세요."
  mkdir -p "${ROOT}/.bares" "${ROOT}/tasks"
  log "📁 root: ${ROOT}"
}

validate_id() {
  local id=$1

  [[ "${id}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] \
    || die 1 "TASK-ID 형식 오류: '${id}' (허용: ^[A-Za-z0-9][A-Za-z0-9._-]*$)"
  git check-ref-format --branch "feature/${id}" >/dev/null 2>&1 \
    || die 1 "TASK-ID 가 브랜치명으로 부적합합니다: '${id}'"
}

bare_path() { printf '%s/.bares/%s.git\n' "${ROOT}" "$1"; }

# origin/HEAD 가 가리키는 기본 브랜치 이름 (main / develop ...)
default_branch() {
  local ref

  ref="$(git -C "$1" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)" || return 1
  printf '%s\n' "${ref#origin/}"
}

# worktree 가 속한 bare 저장소의 절대경로
bare_of_worktree() {
  git -C "$1" rev-parse --path-format=absolute --git-common-dir
}

# <url>[=<name>] → name 출력
spec_name() {
  local spec=$1 url name

  if [[ "${spec}" == *=* ]]; then
    printf '%s\n' "${spec#*=}"
    return
  fi

  url="${spec%/}"
  name="$(basename "${url}")"
  name="${name%.git}"
  printf '%s\n' "${name}"
}

spec_url() { printf '%s\n' "${1%%=*}"; }

# 인자가 git URL 처럼 보이는가 (init 의 <dir> 판별용)
looks_like_url() {
  [[ "$1" == *://* || "$1" =~ ^[^/]+@[^:]+: ]]
}

# 파일에 같은 줄이 없을 때만 추가 (멱등)
ensure_line() {
  local file=$1 line=$2

  [[ -f "${file}" ]] || : > "${file}"
  grep -qxF -- "${line}" "${file}" || printf '%s\n' "${line}" >> "${file}"
}

# 태스크 아래의 worktree 디렉토리 이름 목록 (.git 파일이 있는 하위 디렉토리)
task_worktrees() {
  local task_dir=$1 sub

  for sub in "${task_dir}"/*/; do
    [[ -f "${sub}.git" ]] || continue
    basename "${sub}"
  done
}

# 추적 파일 변경 (untracked/ignored 제외) 이 있으면 0
has_tracked_changes() {
  git -C "$1" status --porcelain | grep -vE '^(\?\?|!!) ' | grep -q .
}

# ---------------------------------------------------------------- add

add_one() {
  local url=$1 name=$2 bare

  bare="$(bare_path "${name}")"

  if [[ -d "${bare}" ]]; then
    log "🔄 [${name}] 이미 등록됨 — fetch"
    if git -C "${bare}" fetch origin --quiet; then
      git -C "${bare}" remote set-head origin --auto >/dev/null
    else
      log "⚠️  [${name}] fetch 실패 (오프라인?)"
    fi
    return 0
  fi

  log "📦 [${name}] bare 등록: ${url}"
  git init --bare --quiet -- "${bare}"
  git -C "${bare}" remote add origin -- "${url}"

  if ! git -C "${bare}" fetch origin --quiet; then
    rm -rf "${bare}"   # 방금 만든 빈 bare 만 제거
    log "❌ [${name}] fetch 실패 — 등록 취소: ${url}"
    return 1
  fi

  git -C "${bare}" remote set-head origin --auto >/dev/null
}

record_repo() {
  local spec=$1 url name line

  url="$(spec_url "${spec}")"
  name="$(spec_name "${spec}")"
  line="${url}"
  [[ "$(spec_name "${url}")" == "${name}" ]] || line="${url}=${name}"
  ensure_line "${ROOT}/repos.txt" "${line}"
}

add_specs() {
  local spec rc=0

  for spec in "$@"; do
    if add_one "$(spec_url "${spec}")" "$(spec_name "${spec}")"; then
      record_repo "${spec}"
    else
      rc=1
    fi
  done

  return "${rc}"
}

cmd_add() {
  require_root

  if [[ $# -gt 0 ]]; then
    add_specs "$@"
    return
  fi

  # 인자 없음 → repos.txt 의 미등록 항목 복원
  local spec name found=0 rc=0

  [[ -f "${ROOT}/repos.txt" ]] || die 1 "repos.txt 가 없습니다. URL 을 지정하세요."

  while IFS= read -r spec; do
    [[ -n "${spec}" && "${spec}" != \#* ]] || continue
    name="$(spec_name "${spec}")"
    [[ -d "$(bare_path "${name}")" ]] && continue
    found=1
    add_specs "${spec}" || rc=1
  done < "${ROOT}/repos.txt"

  [[ "${found}" -eq 1 ]] || log "✅ repos.txt 의 repo 가 모두 등록돼 있습니다"
  return "${rc}"
}

# ---------------------------------------------------------------- init

cmd_init() {
  local dir parent
  dir="$(pwd)"

  if [[ $# -gt 0 ]] && ! looks_like_url "$1"; then
    dir=$1
    shift
  fi

  mkdir -p -- "${dir}"
  dir="$(cd "${dir}" && pwd)"

  parent="$(dirname "${dir}")"
  while [[ "${parent}" != "/" ]]; do
    [[ -d "${parent}/.bares" ]] && log "⚠️  상위 디렉토리에 다른 taskspace 가 있습니다: ${parent}"
    parent="$(dirname "${parent}")"
  done

  mkdir -p "${dir}/.bares" "${dir}/tasks"

  if [[ -d "${dir}/.git" ]]; then
    log "🔄 이미 git repo: ${dir}"
  else
    git init --quiet -- "${dir}"
    log "🌱 git init: ${dir}"
  fi

  local line
  while IFS= read -r line; do
    ensure_line "${dir}/.gitignore" "${line}"
  done <<< "${GITIGNORE_LINES}"
  [[ -f "${dir}/repos.txt" ]] || : > "${dir}/repos.txt"

  ROOT="${dir}"
  log "📁 root: ${ROOT}"

  [[ $# -eq 0 ]] || add_specs "$@"

  log "✅ 최초 세팅 완료: ${ROOT} (커밋은 하지 않았습니다)"
  printf '%s\n' "${ROOT}"
}

# ---------------------------------------------------------------- repos

cmd_repos() {
  require_root

  local bare name def total bares n spec

  printf '%-28s %-12s %s\n' "REPO" "DEFAULT" "WORKTREES"

  for bare in "${ROOT}"/.bares/*.git; do
    [[ -d "${bare}" ]] || continue
    name="$(basename "${bare}")"
    name="${name%.git}"
    def="$(default_branch "${bare}")" || def="?"
    total="$(git -C "${bare}" worktree list --porcelain | grep -c '^worktree ' || true)"
    bares="$(git -C "${bare}" worktree list --porcelain | grep -c '^bare$' || true)"
    n=$((total - bares))
    printf '%-28s %-12s %s\n' "${name}" "${def}" "${n}"
  done

  [[ -f "${ROOT}/repos.txt" ]] || return 0

  while IFS= read -r spec; do
    [[ -n "${spec}" && "${spec}" != \#* ]] || continue
    name="$(spec_name "${spec}")"
    [[ -d "$(bare_path "${name}")" ]] && continue
    printf '%-28s %-12s %s\n' "${name}" "missing" "(repos.txt 에만 있음 — 'add' 로 복원)"
  done < "${ROOT}/repos.txt"
}

# ---------------------------------------------------------------- link

# .local/<repo>/ 의 파일을 tasks/<id>/<repo>/ 의 같은 상대경로에 상대 심링크로 연결
link_repo() {
  local id=$1 name=$2
  local local_dir="${ROOT}/.local/${name}" wt="${ROOT}/tasks/${id}/${name}"
  local src rel dst depth ups target i

  [[ -d "${local_dir}" && -d "${wt}" ]] || return 0

  find "${local_dir}" -type f -print | while IFS= read -r src; do
    rel="${src#"${local_dir}"/}"
    dst="${wt}/${rel}"
    depth="$(printf '%s' "${rel}" | tr -cd '/' | wc -c | tr -d ' ')"
    ups=$((3 + depth))
    target=""
    for ((i = 0; i < ups; i++)); do target="${target}../"; done
    target="${target}.local/${name}/${rel}"

    if [[ -L "${dst}" ]]; then
      if [[ "$(readlink "${dst}")" == "${target}" ]]; then
        continue
      fi
      log "⚠️  [exists] 다른 곳을 가리키는 심링크가 있어 건너뜀: ${dst}"
      continue
    fi

    if [[ -e "${dst}" ]]; then
      log "⚠️  [exists] 파일이 이미 있어 건너뜀: ${dst}"
      continue
    fi

    mkdir -p "$(dirname "${dst}")"
    ln -s "${target}" "${dst}"
    log "🔗 [${name}] ${rel} → ${target}"
  done
}

cmd_link() {
  [[ $# -ge 1 ]] || usage
  require_root

  local id=$1 task_dir name
  shift
  validate_id "${id}"
  task_dir="${ROOT}/tasks/${id}"
  [[ -d "${task_dir}" ]] || die 1 "태스크가 없습니다: ${task_dir}"

  if [[ $# -eq 0 ]]; then
    for name in $(task_worktrees "${task_dir}"); do
      link_repo "${id}" "${name}"
    done
    return 0
  fi

  for name in "$@"; do
    link_repo "${id}" "${name}"
  done
}

# ---------------------------------------------------------------- new

cmd_new() {
  [[ $# -ge 1 ]] || usage
  require_root

  local id=$1 task_dir spec name br bare def wt rc=0 names=""
  shift
  validate_id "${id}"
  task_dir="${ROOT}/tasks/${id}"

  if [[ $# -eq 0 ]]; then
    cmd_repos
    die 3 "repo 를 지정하세요: new ${id} <repo>[=<branch>]..."
  fi

  mkdir -p "${task_dir}/.prompts"

  for spec in "$@"; do
    name="${spec%%=*}"
    br="feature/${id}"
    [[ "${spec}" == *=* ]] && br="${spec#*=}"
    names="${names}${names:+ }${name}"

    bare="$(bare_path "${name}")"
    if [[ ! -d "${bare}" ]]; then
      log "⚠️  [${name}] 등록되지 않은 repo — 'add <url>' 먼저"
      rc=1
      continue
    fi

    if git -C "${bare}" fetch origin --quiet; then
      git -C "${bare}" remote set-head origin --auto >/dev/null
    else
      log "⚠️  [${name}] fetch 실패 — 캐시된 origin/* 로 진행"
    fi

    if ! def="$(default_branch "${bare}")"; then
      log "⚠️  [${name}] 기본 브랜치를 알 수 없음 (origin/HEAD 없음) — 건너뜀"
      rc=1
      continue
    fi

    wt="${task_dir}/${name}"

    if git -C "${bare}" worktree list --porcelain | grep -qxF -- "worktree ${wt}"; then
      log "🔄 [${name}] worktree 이미 있음: ${wt}"
      link_repo "${id}" "${name}"
      continue
    fi

    if [[ -e "${wt}" ]] && [[ -n "$(ls -A "${wt}")" ]]; then
      log "⚠️  [${name}] 디렉토리가 비어 있지 않은데 worktree 로 등록돼 있지 않음 — 비우거나 옮긴 뒤 다시 실행: ${wt}"
      rc=1
      continue
    fi

    log "🌿 [${name}] worktree 생성: ${br}"
    if git -C "${bare}" show-ref --verify --quiet "refs/heads/${br}"; then
      git -C "${bare}" worktree add -- "${wt}" "${br}" || { rc=1; continue; }
    elif git -C "${bare}" show-ref --verify --quiet "refs/remotes/origin/${br}"; then
      git -C "${bare}" worktree add --track -b "${br}" -- "${wt}" "origin/${br}" || { rc=1; continue; }
    else
      git -C "${bare}" worktree add --no-track -b "${br}" -- "${wt}" "origin/${def}" || { rc=1; continue; }
    fi

    link_repo "${id}" "${name}"
  done

  if [[ ! -f "${task_dir}/notes.md" ]]; then
    [[ -f "${TEMPLATE}" ]] || die 1 "템플릿이 없습니다: ${TEMPLATE}"
    sed -e "s|{{TASK_ID}}|${id}|g" \
        -e "s|{{DATE}}|$(date '+%Y-%m-%d %H:%M')|g" \
        -e "s|{{REPOS}}|${names}|g" \
        "${TEMPLATE}" > "${task_dir}/notes.md"
    log "📝 notes.md 생성"
  fi

  log "✅ 태스크 준비: ${task_dir}"
  printf '%s\n' "${task_dir}"
  return "${rc}"
}

# ---------------------------------------------------------------- sync

cmd_sync() {
  [[ $# -ge 1 ]] || usage
  require_root

  local id=$1 task_dir rebase=0 names="" name wt bare def rc=0 arg
  shift
  validate_id "${id}"
  task_dir="${ROOT}/tasks/${id}"
  [[ -d "${task_dir}" ]] || die 1 "태스크가 없습니다: ${task_dir}"

  for arg in "$@"; do
    case "${arg}" in
      --rebase) rebase=1 ;;
      --*) die 1 "알 수 없는 옵션: ${arg}" ;;
      *) names="${names}${names:+ }${arg}" ;;
    esac
  done
  [[ -n "${names}" ]] || names="$(task_worktrees "${task_dir}")"

  for name in ${names}; do
    wt="${task_dir}/${name}"
    [[ -f "${wt}/.git" ]] || { log "⚠️  [${name}] worktree 가 없음: ${wt}"; rc=5; continue; }

    if ! git -C "${wt}" fetch origin --quiet; then
      log "⚠️  [offline] [${name}] fetch 실패 — 건너뜀"
      rc=5
      continue
    fi

    if has_tracked_changes "${wt}"; then
      log "⚠️  [dirty] [${name}] 추적 파일에 변경이 있어 건너뜀 (커밋하거나 stash 후 다시)"
      rc=5
      continue
    fi

    bare="$(bare_of_worktree "${wt}")"
    def="$(default_branch "${bare}")" || { log "⚠️  [${name}] 기본 브랜치를 알 수 없음"; rc=5; continue; }

    if git -C "${wt}" merge-base --is-ancestor "origin/${def}" HEAD; then
      log "✅ [${name}] up-to-date (origin/${def} 포함)"
      continue
    fi

    if [[ "${rebase}" -eq 1 ]]; then
      log "🔀 [${name}] rebase origin/${def}"
      if ! git -C "${wt}" rebase --quiet "origin/${def}"; then
        log "⚠️  [conflict] [${name}] rebase 충돌 — 해결 후 'git -C ${wt} rebase --continue' (취소: --abort)"
        git -C "${wt}" diff --name-only --diff-filter=U >&2
        rc=5
      fi
    else
      log "🔀 [${name}] merge origin/${def}"
      if ! git -C "${wt}" merge --no-edit --quiet "origin/${def}"; then
        log "⚠️  [conflict] [${name}] merge 충돌 — 해결 후 'git -C ${wt} merge --continue' (취소: --abort)"
        git -C "${wt}" diff --name-only --diff-filter=U >&2
        rc=5
      fi
    fi
  done

  return "${rc}"
}

# ---------------------------------------------------------------- done

# 미추적·ignored 파일 중 .local/ 심링크를 뺀 목록
untracked_files() {
  local wt=$1 line path

  # grep 이 0건이면 1 을 돌려주므로 pipefail 에 걸리지 않게 || true
  { git -C "${wt}" status --ignored --porcelain --untracked-files=all | grep -E '^(\?\?|!!) ' || true; } | while IFS= read -r line; do
    path="${line:3}"
    if [[ -L "${wt}/${path}" ]] && [[ "$(readlink "${wt}/${path}")" == *".local/"* ]]; then
      continue
    fi
    printf '%s\n' "${path}"
  done
}

is_locked() {
  local bare=$1 wt=$2

  git -C "${bare}" worktree list --porcelain | awk -v wt="worktree ${wt}" '
    $0 == wt { hit = 1; next }
    hit && /^locked/ { found = 1 }
    hit && /^$/ { hit = 0 }
    END { exit found ? 0 : 1 }'
}

cmd_done() {
  [[ $# -ge 1 ]] || usage
  require_root

  local id=$1 task_dir arg merged=0 discard=0 delete_branch=0 force=0
  shift
  validate_id "${id}"
  task_dir="${ROOT}/tasks/${id}"
  [[ -d "${task_dir}" ]] || die 1 "태스크가 없습니다: ${task_dir}"

  for arg in "$@"; do
    case "${arg}" in
      --merged) merged=1 ;;
      --discard-untracked) discard=1 ;;
      --delete-branch) delete_branch=1 ;;
      --force) force=1 ;;
      *) die 1 "알 수 없는 옵션: ${arg}" ;;
    esac
  done

  case "$(pwd)/" in
    "${task_dir}/"*) die 4 "[cwd] 현재 디렉토리가 태스크 안입니다. 밖으로 나간 뒤 실행하세요: cd ${ROOT}" ;;
  esac

  local names name wt bare blocks=0 skipped="" files

  names="$(task_worktrees "${task_dir}")"
  [[ -n "${names}" ]] || log "ℹ️  제거할 worktree 가 없습니다 (이미 archived)"

  # 1단계: 전부 검사. 하나라도 걸리면 아무것도 지우지 않는다.
  for name in ${names}; do
    wt="${task_dir}/${name}"
    bare="$(bare_of_worktree "${wt}")"

    if is_locked "${bare}" "${wt}"; then
      log "⚠️  [locked] [${name}] 잠긴 worktree — 건너뜀 (git -C ${bare} worktree unlock ${wt})"
      skipped="${skipped}${skipped:+ }${name}"
      continue
    fi

    if ! git -C "${wt}" fetch --prune origin --quiet; then
      if [[ "${force}" -eq 0 ]]; then
        log "⛔ [offline] [${name}] 원격 확인 불가 (fetch 실패) — --force 로만 진행 가능"
        blocks=$((blocks + 1))
      fi
      continue
    fi

    if has_tracked_changes "${wt}" && [[ "${force}" -eq 0 ]]; then
      log "⛔ [dirty] [${name}] 추적 파일에 미커밋 변경:"
      git -C "${wt}" status --porcelain | grep -vE '^(\?\?|!!) ' >&2
      blocks=$((blocks + 1))
    fi

    if ! git -C "${wt}" branch -r --contains HEAD | grep -q . && [[ "${merged}" -eq 0 && "${force}" -eq 0 ]]; then
      log "⛔ [unpushed] [${name}] HEAD 가 어느 원격 브랜치에도 없음 (push 안 됨, 또는 squash 머지 후 원격 브랜치 삭제). PR 병합이 확인되면 --merged"
      blocks=$((blocks + 1))
    fi

    files="$(untracked_files "${wt}")"
    if [[ -n "${files}" && "${discard}" -eq 0 && "${force}" -eq 0 ]]; then
      log "⛔ [untracked] [${name}] 제거 시 함께 삭제될 미추적·ignored 파일 (--discard-untracked 로 허용):"
      printf '%s\n' "${files}" | sed 's/^/    /' >&2
      blocks=$((blocks + 1))
    fi
  done

  [[ "${blocks}" -eq 0 ]] || die 4 "차단 ${blocks}건 — 아무것도 지우지 않았습니다"

  # 2단계: 제거
  local rc=0 br remove_flags

  for name in ${names}; do
    case " ${skipped} " in *" ${name} "*) continue ;; esac

    wt="${task_dir}/${name}"
    bare="$(bare_of_worktree "${wt}")"
    br="$(git -C "${wt}" symbolic-ref --short HEAD 2>/dev/null || true)"

    # git 자체도 미추적 파일이 있으면 거부한다. 1단계를 통과했으면 남은 미추적은
    # 허용된 것 (--discard-untracked/--force) 이거나 .local/ 심링크뿐이므로 --force 로 넘긴다.
    remove_flags=""
    if git -C "${wt}" status --ignored --porcelain --untracked-files=all | grep -qE '^(\?\?|!!) '; then
      remove_flags="--force"
    fi

    # shellcheck disable=SC2086
    if ! git -C "${bare}" worktree remove ${remove_flags} -- "${wt}"; then
      log "❌ [${name}] worktree 제거 실패"
      rc=1
      continue
    fi
    git -C "${bare}" worktree prune
    log "🗑️  [${name}] worktree 제거"

    [[ "${delete_branch}" -eq 1 && -n "${br}" ]] || continue

    if git -C "${bare}" branch -r --contains "${br}" | grep -q .; then
      git -C "${bare}" branch -D "${br}" >/dev/null && log "🧹 [${name}] 브랜치 삭제: ${br} (원격에 사본 있음)"
    elif [[ "${merged}" -eq 1 ]]; then
      git -C "${bare}" branch -D "${br}" >/dev/null && log "🧹 [${name}] 브랜치 삭제: ${br} (--merged)"
    else
      log "ℹ️  [${name}] 브랜치 유지: ${br} (원격에 사본 없음 — 병합 확인 후 --merged 와 함께)"
    fi
  done

  log "📄 notes.md 보존: ${task_dir}/notes.md"
  return "${rc}"
}

# ---------------------------------------------------------------- list

cmd_list() {
  require_root

  local d id n created status

  printf '%-20s %-12s %s\n' "TASK" "STATUS" "CREATED"

  for d in "${ROOT}"/tasks/*/; do
    [[ -d "${d}" ]] || continue
    id="$(basename "${d}")"
    n="$(task_worktrees "${d}" | grep -c . || true)"
    created="$(grep -m1 '생성 일시' "${d}notes.md" 2>/dev/null || true)"
    created="${created#*: }"
    status="active(${n})"
    [[ "${n}" -eq 0 ]] && status="archived"
    printf '%-20s %-12s %s\n' "${id}" "${status}" "${created:--}"
  done
}

# ---------------------------------------------------------------- main

[[ $# -ge 1 ]] || usage
cmd=$1
shift

case "${cmd}" in
  root)  require_root; printf '%s\n' "${ROOT}" ;;
  init)  cmd_init "$@" ;;
  add)   cmd_add "$@" ;;
  repos) cmd_repos ;;
  new)   cmd_new "$@" ;;
  link)  cmd_link "$@" ;;
  sync)  cmd_sync "$@" ;;
  done)  cmd_done "$@" ;;
  list)  cmd_list ;;
  -h|--help|help) usage ;;
  *) log "알 수 없는 서브커맨드: ${cmd}"; usage ;;
esac
