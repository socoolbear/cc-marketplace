#!/bin/bash
# taskspace.sh — bare 저장소 중앙 관리 + tasks/<TASK-ID>/ 격리 작업 환경
#
# 구조:
#   <root>/                 워크스페이스 repo (notes 추적용)
#   ├── .gitignore          .bares/ .local/ shared/ tasks/*/*/
#   ├── repos.txt           등록한 repo 목록 (<url>[=<name>] 한 줄씩)
#   ├── .bares/<repo>.git/  bare 저장소 (ignore). info/exclude 에 링크 경로를 등록 (전 worktree 적용)
#   ├── .local/<repo>/      repo 별 로컬 파일 원본 (.env·키·참조 소스, ignore) → worktree 에 심링크
#   ├── shared/             repo 밖에 둬도 되는 공용 자료 (ignore)
#   ├── tasks/INDEX.md      태스크 색인 (추적, 생성 파일 — index 가 notes.md 만으로 다시 씀)
#   ├── tasks/CLAUDE.md     작업 지도 (추적, 없으면 init/new 가 템플릿에서 생성. 상위라 worktree 세션에도 실림)
#   └── tasks/<ID>/         notes.md (추적) · <repo>/ worktree (ignore) · <repo>/.prompts/ 스크래치 (info/exclude)
#
# macOS 기본 bash 3.2 호환 (연관배열·mapfile 사용 금지, 빈 배열은 ${arr[@]+"${arr[@]}"}).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="${SCRIPT_DIR}/../references/notes-template.md"
TASKS_CLAUDE_TEMPLATE="${SCRIPT_DIR}/../references/tasks-claude-template.md"
GITIGNORE_LINES=".bares/
.local/
shared/
tasks/*/*/"

ROOT=""

log() { printf '%s\n' "$*" >&2; }
die() { local code=$1; shift; log "❌ $*"; exit "${code}"; }

usage() {
  cat >&2 <<'EOF'
사용법: taskspace.sh <서브커맨드> [인자...]

  root                                       루트 절대경로 출력
  init [<dir>] [<url>[=<name>]...]           최초 세팅 (디렉토리 · git init · .gitignore · tasks/CLAUDE.md · bare 등록)
  add  [<url>[=<name>]...]                   bare 등록. 인자 없으면 repos.txt 의 미등록 항목 전부
  repos                                      등록된 repo 와 기본 브랜치 · 열린 worktree 수
  new  <TASK-ID|next> [--slug <슬러그>] [--title <제목>] [<repo>[=<branch>]...]
                                             태스크 생성 + worktree + notes.md + 심링크. next 는 다음 번호 자동 배정,
                                             슬러그가 있으면 브랜치 feature/<ID>-<슬러그> (번호만인 ID 는 슬러그 필수)
  link [<TASK-ID> [<repo>...]]               .local/<repo>/ 를 worktree 에 상대 심링크 (디렉토리 통째 가능). 인자 없으면 전 태스크
  migrate <repo> <checkout> <rel-path>...    기존 체크아웃의 gitignore 된 파일을 .local/<repo>/ 로 복사 (원본은 그대로)
  sync <TASK-ID> [<repo>...] [--rebase]      worktree 에 origin/<기본 브랜치> 반영 (merge 기본)
  done <TASK-ID> [--merged] [--discard-untracked] [--delete-branch] [--force]
                                             worktree 제거 (notes.md 보존). 안전 검사 통과 시에만
  list                                       태스크 목록 (TITLE 은 notes.md 첫 줄). 끝에 index 도 실행
  index                                      tasks/INDEX.md 재생성 (new · done · list 끝에 자동 실행)

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

  [[ "${id}" != "next" ]] || die 1 "TASK-ID 'next' 는 예약어입니다 (new next 로 다음 번호 자동 배정)"
  [[ "${id}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] \
    || die 1 "TASK-ID 형식 오류: '${id}' (허용: ^[A-Za-z0-9][A-Za-z0-9._-]*$)"
  git check-ref-format --branch "feature/${id}" >/dev/null 2>&1 \
    || die 1 "TASK-ID 가 브랜치명으로 부적합합니다: '${id}'"
}

validate_slug() {
  [[ "$1" =~ ^[a-z0-9][a-z0-9-]*$ ]] \
    || die 1 "슬러그 형식 오류: '$1' (영문 소문자·숫자·하이픈 kebab-case)"
}

# tasks/ 의 번호형 디렉토리 (<접두사><숫자>) 중 최대 번호 +1 을 3자리로. 접두사는 계승하되 둘 이상 섞이면 거부
next_id() {
  local d base prefix num max=0 seen=0 first_prefix=""

  for d in "${ROOT}"/tasks/*/; do
    [[ -d "${d}" ]] || continue
    base="$(basename "${d}")"
    [[ "${base}" =~ ^([A-Za-z._-]*)([0-9]+)$ ]] || continue
    prefix="${BASH_REMATCH[1]}"
    num=$((10#${BASH_REMATCH[2]}))

    if [[ "${seen}" -eq 0 ]]; then
      first_prefix="${prefix}"
      seen=1
    elif [[ "${prefix}" != "${first_prefix}" ]]; then
      die 1 "번호형 TASK-ID 의 접두사가 섞여 있어 next 를 정할 수 없습니다 ('${first_prefix}' 와 '${prefix}') — ID 를 직접 지정하세요"
    fi
    [[ "${num}" -gt "${max}" ]] && max="${num}"
  done

  printf '%s%03d\n' "${first_prefix}" "$((max + 1))"
}

# notes.md 의 '- <라벨>: <값>' 줄에서 값 (없으면 빈 문자열)
notes_field() {
  local notes=$1 label=$2 line

  [[ -f "${notes}" ]] || return 0
  line="$(grep -m1 -- "^- ${label}:" "${notes}" || true)"
  line="${line#*:}"
  line="${line# }"
  printf '%s\n' "${line}"
}

# notes.md 첫 '# ' 줄에서 '<ID> — ' 접두사를 뗀 제목. 없거나 ID 와 같으면 '-'
notes_title() {
  local notes=$1 id=$2 title

  title="$(grep -m1 '^# ' "${notes}" 2>/dev/null || true)"
  title="${title#\# }"
  [[ "${title}" == "${id} — "* ]] && title="${title#"${id} — "}"
  [[ -n "${title}" && "${title}" != "${id}" ]] || title="-"
  printf '%s\n' "${title}"
}

# notes.md 의 '- 관련 repo:' 줄에 '<name> (<branch>)' 를 없을 때만 덧붙인다. 줄 자체가 없으면 건드리지 않는다
notes_add_repo() {
  local notes=$1 name=$2 br=$3 tmp

  [[ -f "${notes}" ]] || return 0
  grep -q -- '^- 관련 repo:' "${notes}" || return 0
  grep -m1 -- '^- 관련 repo:' "${notes}" | grep -qF -- " ${name} (" && return 0

  tmp="${notes}.tmp.$$"
  awk -v item="${name} (${br})" '
    !done && /^- 관련 repo:/ { sub(/[[:space:]]+$/, ""); $0 = $0 ($0 ~ /:$/ ? " " : ", ") item; done = 1 }
    { print }
  ' "${notes}" > "${tmp}"
  mv -- "${tmp}" "${notes}"
}

# notes.md 에 '- 완료 일시:' 줄을 없을 때만 넣는다 — '- 생성 일시:' 줄 뒤, 없으면 제목 줄 뒤
notes_mark_done() {
  local notes=$1 tmp

  [[ -f "${notes}" ]] || return 0
  grep -q -- '^- 완료 일시:' "${notes}" && return 0

  tmp="${notes}.tmp.$$"
  awk -v line="- 완료 일시: $(date '+%Y-%m-%d %H:%M')" '
    { print }
    !done && /^- 생성 일시:/ { print line; done = 1 }
    END { if (!done) print line }
  ' "${notes}" > "${tmp}"
  mv -- "${tmp}" "${notes}"
}

# tasks/CLAUDE.md 가 없을 때만 템플릿에서 만든다 (사용자 수정 보존)
ensure_tasks_claude() {
  [[ -f "${ROOT}/tasks/CLAUDE.md" ]] && return 0
  [[ -f "${TASKS_CLAUDE_TEMPLATE}" ]] || die 1 "템플릿이 없습니다: ${TASKS_CLAUDE_TEMPLATE}"
  cp -- "${TASKS_CLAUDE_TEMPLATE}" "${ROOT}/tasks/CLAUDE.md"
  log "🗺️  tasks/CLAUDE.md 생성"
}

# worktree 안 스크래치 .prompts/ — bare 의 info/exclude 에 등록해 repo 의 .gitignore 를 건드리지 않는다
ensure_prompts() {
  local name=$1 wt=$2

  mkdir -p "${wt}/.prompts"
  ensure_line "$(exclude_file "${name}")" ".prompts/"
}

# 템플릿을 채워 stdout 으로. sed 대신 bash 치환 — 제목의 & | \ 가 그대로 들어간다
render_notes() {
  local id=$1 slug=$2 title=$3 tpl heading now

  heading="${id}"
  [[ -n "${title:-${slug}}" ]] && heading="${id} — ${title:-${slug}}"
  now="$(date '+%Y-%m-%d %H:%M')"
  tpl="$(cat "${TEMPLATE}")"
  tpl="${tpl//\{\{TITLE\}\}/${heading}}"
  tpl="${tpl//\{\{DATE\}\}/${now}}"
  if [[ -n "${slug}" ]]; then
    tpl="${tpl//\{\{SLUG\}\}/${slug}}"
    printf '%s\n' "${tpl}"
  else
    printf '%s\n' "${tpl}" | grep -v -- '{{SLUG}}'
  fi
}

# tasks/INDEX.md 를 notes.md 만으로 다시 쓴다 (머신 로컬 상태는 넣지 않는다)
write_index() {
  local index="${ROOT}/tasks/INDEX.md" tmp d id notes title created finished status

  tmp="${index}.tmp.$$"
  {
    printf '# 태스크 색인\n\n'
    # shellcheck disable=SC2016
    printf '<!-- 생성 파일 — `taskspace.sh index` 가 다시 씀. 직접 편집 금지. 제목은 각 notes.md 첫 줄에서 고친다 -->\n\n'
    printf '| ID | 제목 | 상태 | repo (브랜치) | 생성 | 완료 |\n|---|---|---|---|---|---|\n'

    for d in "${ROOT}"/tasks/*/; do
      [[ -d "${d}" ]] || continue
      id="$(basename "${d}")"
      notes="${d}notes.md"
      created="$(notes_field "${notes}" '생성 일시')"
      finished="$(notes_field "${notes}" '완료 일시')"
      title="$(notes_title "${notes}" "${id}")"
      status="진행 중"
      [[ -n "${finished}" ]] && status="완료"
      printf '| [%s](%s/notes.md) | %s | %s | %s | %s | %s |\n' \
        "${id}" "${id}" "${title//|/\\|}" "${status}" \
        "$(notes_field "${notes}" '관련 repo')" "${created%% *}" "${finished%% *}"
    done
  } > "${tmp}"
  mv -- "${tmp}" "${index}"
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

# 파일에서 정확히 같은 줄만 제거 (없으면 통과)
remove_line() {
  local file=$1 line=$2 tmp

  [[ -f "${file}" ]] || return 0
  grep -qxF -- "${line}" "${file}" || return 0
  tmp="${file}.tmp.$$"
  grep -vxF -- "${line}" "${file}" > "${tmp}" || true
  mv -- "${tmp}" "${file}"
}

# bare 의 info/exclude 경로 — 여기 등록한 패턴은 그 bare 의 모든 worktree 에 적용된다
exclude_file() { printf '%s/info/exclude\n' "$(bare_path "$1")"; }

# exclude 패턴에 쓸 수 없는 이름 (주석·글롭·이스케이프 문자, 앞뒤 공백)
is_bad_name() {
  case "$1" in
    *[\#\!\[\]\*\?\\]*|" "*|*" ") return 0 ;;
  esac
  return 1
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
  [[ -f "${dir}/.git" ]] && die 1 "git worktree 안입니다 (.git 이 파일) — 워크스페이스 루트에서 실행하세요: ${dir}"

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
  ensure_tasks_claude

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

# .local/<repo>/ 를 걸어 내려가며 worktree 에 없는 가장 얕은 경로에서 상대 심링크를 건다.
# - .local/ 안의 심링크는 잎이다 (따라 들어가지 않고 그 자체를 링크) — 외부 위치를 가리키는 링크를 둘 수 있다
# - 링크한 경로는 bare 의 info/exclude 에 "/<path>" 로 앵커 등록 (repo .gitignore 의 "dir/" 패턴은 심링크를 무시하지 않는다)
# - worktree 에 실디렉토리가 있으면 (추적 디렉토리, 또는 sync 로 심링크가 실디렉토리가 된 경우) exclude 를 지우고 안으로 내려간다
link_tree() {
  local name=$1 local_dir=$2 wt=$3 rel=$4
  local dir entry base path src dst depth ups target i excl

  dir="${local_dir}${rel:+/${rel}}"
  excl="$(exclude_file "${name}")"

  for entry in "${dir}"/* "${dir}"/.[!.]* "${dir}"/..?*; do
    [[ -e "${entry}" || -L "${entry}" ]] || continue   # nullglob 없는 bash 3.2 의 리터럴 방어
    base="$(basename "${entry}")"
    [[ "${base}" == ".DS_Store" ]] && continue
    path="${rel:+${rel}/}${base}"

    if is_bad_name "${base}"; then
      log "⚠️  [bad-name] [${name}] exclude 패턴에 쓸 수 없는 이름이라 건너뜀: ${path}"
      continue
    fi

    src="${local_dir}/${path}"
    dst="${wt}/${path}"
    depth="$(printf '%s' "${path}" | tr -cd '/' | wc -c | tr -d ' ')"
    ups=$((3 + depth))
    target=""
    for ((i = 0; i < ups; i++)); do target="${target}../"; done
    target="${target}.local/${name}/${path}"

    # -L 을 -e 보다 먼저: 끊긴 링크는 -e 가 false 라 ln 이 실패한다
    if [[ -L "${dst}" ]]; then
      if [[ "$(readlink "${dst}")" == "${target}" ]]; then
        ensure_line "${excl}" "/${path}"
      else
        log "⚠️  [exists] 다른 곳을 가리키는 심링크가 있어 건너뜀: ${dst}"
      fi
      continue
    fi

    if [[ ! -e "${dst}" ]]; then
      mkdir -p "$(dirname "${dst}")"
      ln -s "${target}" "${dst}"
      ensure_line "${excl}" "/${path}"
      log "🔗 [${name}] ${path} → ${target}"
      continue
    fi

    if [[ ! -L "${src}" && -d "${src}" && -d "${dst}" ]]; then
      remove_line "${excl}" "/${path}"
      link_tree "${name}" "${local_dir}" "${wt}" "${path}"
      continue
    fi

    log "⚠️  [exists] 파일이 이미 있어 건너뜀: ${dst}"
  done
}

link_repo() {
  local id=$1 name=$2
  local local_dir="${ROOT}/.local/${name}" wt="${ROOT}/tasks/${id}/${name}"

  [[ -d "${local_dir}" && -d "${wt}" ]] || return 0
  mkdir -p "$(dirname "$(exclude_file "${name}")")"
  link_tree "${name}" "${local_dir}" "${wt}" ""
}

# 모든 태스크의 모든 worktree 에 재연결 (.local/ 에 항목을 추가한 뒤)
link_all() {
  local d id name

  for d in "${ROOT}"/tasks/*/; do
    [[ -d "${d}" ]] || continue
    id="$(basename "${d}")"
    for name in $(task_worktrees "${d}"); do
      link_repo "${id}" "${name}"
    done
  done
}

cmd_link() {
  require_root

  if [[ $# -eq 0 ]]; then
    link_all
    return 0
  fi

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

  local id=$1 task_dir notes spec name br bare def wt rc=0 slug="" title="" existing from_next=0 specs=()
  shift

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --slug)  [[ $# -ge 2 ]] || die 1 "--slug 에 값이 없습니다"; slug=$2; shift 2 ;;
      --title) [[ $# -ge 2 ]] || die 1 "--title 에 값이 없습니다"; title=$2; shift 2 ;;
      --*) die 1 "알 수 없는 옵션: $1" ;;
      *) specs+=("$1"); shift ;;
    esac
  done

  if [[ "${id}" == "next" ]]; then
    id="$(next_id)"
    from_next=1
    log "🔢 다음 TASK-ID: ${id}"
  fi
  validate_id "${id}"
  task_dir="${ROOT}/tasks/${id}"
  notes="${task_dir}/notes.md"

  if [[ ${#specs[@]} -eq 0 ]]; then
    cmd_repos
    die 3 "repo 를 지정하세요: new ${id} [--slug <슬러그>] [--title <제목>] <repo>[=<branch>]..."
  fi

  # 슬러그: 명시 > notes.md 계승. 한 태스크 안에서 브랜치 규칙이 둘이 되지 않게 불일치는 거부
  existing="$(notes_field "${notes}" '슬러그')"
  if [[ -n "${slug}" ]]; then
    validate_slug "${slug}"
    [[ -z "${existing}" || "${existing}" == "${slug}" ]] \
      || die 1 "이 태스크의 슬러그는 이미 '${existing}' 입니다 (notes.md). 한 태스크 안에서 슬러그를 바꾸지 않습니다"
  else
    slug="${existing}"
  fi
  if [[ "${id}" =~ ^[0-9]+$ && -z "${slug}" && "${specs[*]}" != *=* ]]; then
    die 1 "번호만인 TASK-ID 는 브랜치에 슬러그가 필요합니다: new ${id} --slug <슬러그> ... (또는 <repo>=<branch> 로 직접 지정)"
  fi

  # next 로 정한 디렉토리는 -p 없이 만들어 동시 실행 충돌을 실패로 드러낸다
  if [[ "${from_next}" -eq 1 ]]; then
    mkdir -- "${task_dir}" || die 1 "TASK-ID ${id} 가 방금 생겼습니다 — 다시 실행하세요"
  fi
  mkdir -p "${task_dir}"
  ensure_tasks_claude

  if [[ ! -f "${notes}" ]]; then
    [[ -f "${TEMPLATE}" ]] || die 1 "템플릿이 없습니다: ${TEMPLATE}"
    render_notes "${id}" "${slug}" "${title}" > "${notes}"
    log "📝 notes.md 생성"
  fi

  for spec in "${specs[@]}"; do
    name="${spec%%=*}"
    br="feature/${id}${slug:+-${slug}}"
    [[ "${spec}" == *=* ]] && br="${spec#*=}"
    git check-ref-format --branch "${br}" >/dev/null 2>&1 \
      || { log "⚠️  [${name}] 브랜치명 부적합: '${br}'"; rc=1; continue; }

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
      notes_add_repo "${notes}" "${name}" "$(git -C "${wt}" symbolic-ref --short HEAD 2>/dev/null || printf '%s' "${br}")"
      ensure_prompts "${name}" "${wt}"
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

    notes_add_repo "${notes}" "${name}" "${br}"
    ensure_prompts "${name}" "${wt}"
    link_repo "${id}" "${name}"
  done

  write_index
  log "✅ 태스크 준비: ${task_dir}"
  printf '%s\n' "${task_dir}"
  return "${rc}"
}

# ---------------------------------------------------------------- migrate

# 기존 체크아웃의 gitignore 된 파일을 .local/<repo>/ 로 복사한다. 원본은 건드리지 않는다 (정리는 사용자 몫).
# 내용은 읽거나 출력하지 않는다 — 경로만 다룬다.
cmd_migrate() {
  [[ $# -ge 3 ]] || usage
  require_root

  local name=$1 checkout=$2 bare co_url bare_url rc=0
  local arg rel src dst target n
  shift 2

  bare="$(bare_path "${name}")"
  [[ -d "${bare}" ]] || die 1 "등록되지 않은 repo: ${name} ('add <url>' 먼저)"
  [[ -d "${checkout}" ]] || die 1 "체크아웃 디렉토리가 없습니다: ${checkout}"
  checkout="$(cd "${checkout}" && pwd)"
  case "${checkout}/" in
    "${ROOT}/tasks/"*) die 1 "taskspace 의 worktree 는 migrate 대상이 아닙니다: ${checkout}" ;;
  esac
  git -C "${checkout}" rev-parse --show-toplevel >/dev/null 2>&1 || die 1 "git 체크아웃이 아닙니다: ${checkout}"

  co_url="$(git -C "${checkout}" remote get-url origin 2>/dev/null || true)"
  bare_url="$(git -C "${bare}" remote get-url origin 2>/dev/null || true)"
  if [[ -z "${co_url}" ]]; then
    log "⚠️  [remote] 체크아웃에 origin 이 없어 같은 repo 인지 확인하지 못함 — 계속 진행"
  elif [[ "${co_url}" != "${bare_url}" ]]; then
    log "⚠️  [remote] origin 이 다릅니다: ${co_url} vs ${bare_url} — 계속 진행"
  fi

  mkdir -p "${ROOT}/.local/${name}"

  for arg in "$@"; do
    rel="${arg%/}"
    rel="${rel#./}"
    if [[ -z "${rel}" || "${rel}" == /* || "${rel}" == .. || "${rel}" == ../* || "${rel}" == */.. || "${rel}" == */../* ]]; then
      log "⛔ [bad-path] 체크아웃 기준 상대 경로만 허용 (절대경로·.. 불가): '${arg}'"
      rc=1
      continue
    fi

    src="${checkout}/${rel}"
    dst="${ROOT}/.local/${name}/${rel}"

    if [[ ! -e "${src}" && ! -L "${src}" ]]; then
      log "⛔ [missing] [${name}] ${rel}"
      rc=1
      continue
    fi

    if git -C "${checkout}" ls-files --error-unmatch -- ":(literal)${rel}" >/dev/null 2>&1; then
      log "⛔ [tracked] [${name}] ${rel} — 추적 파일은 .local/ 에 둘 수 없음 (worktree 에 같은 경로가 있어 link 가 영원히 [exists] 로 건너뜀)"
      rc=1
      continue
    fi

    # check-ignore 는 pathspec 이 아니라 경로를 받는다 (:(literal) 불가)
    if ! git -C "${checkout}" check-ignore -q -- "${rel}" 2>/dev/null; then
      log "⚠️  [not-ignored] [${name}] ${rel} — .gitignore 에 없는 경로 (계속 진행)"
    fi

    if [[ -e "${dst}" || -L "${dst}" ]]; then
      log "ℹ️  [exists] [${name}] ${rel} — 이미 .local/ 에 있어 건너뜀 (갱신하려면 diff -rq 로 다른지 확인한 뒤 .local/ 쪽을 지우고 재실행)"
      continue
    fi

    mkdir -p "$(dirname "${dst}")"

    if [[ -L "${src}" ]]; then
      target="$(readlink "${src}")"
      if [[ "${target}" == /* ]]; then
        ln -s "${target}" "${dst}"
        log "🔗 [${name}] ${rel} → ${target} (절대 심링크를 그대로 둠)"
      else
        log "⛔ [symlink] [${name}] ${rel} → ${target} — 상대 심링크는 복사하면 끊김. 원본 위치를 지정하세요"
        rc=1
      fi
      continue
    fi

    # cp 는 소켓·읽기 불가 파일 하나에도 rc=1 을 내면서 나머지를 복사해 둔다 → 부분 사본은 지운다
    trap 'rm -rf -- "${dst}"; trap - INT TERM; exit 130' INT TERM
    if cp -pR -- "${src}" "${dst}"; then
      trap - INT TERM
      n="$(find "${dst}" -type l ! -exec test -e {} \; -print | wc -l | tr -d ' ')"
      [[ "${n}" -eq 0 ]] || log "⚠️  [dangling] [${name}] ${rel} 안에 끊긴 심링크 ${n}개 (바깥을 가리키는 상대 링크)"
      log "📥 [${name}] ${rel} → .local/${name}/${rel}"
    else
      trap - INT TERM
      rm -rf -- "${dst}"
      log "⛔ [copy-failed] [${name}] ${rel} — 복사 실패로 되돌림 (소켓·읽기 불가 파일?)"
      rc=1
    fi
  done

  chmod 700 "${ROOT}/.local"
  link_all
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
      link_repo "${id}" "${name}"
      continue
    fi

    if [[ "${rebase}" -eq 1 ]]; then
      log "🔀 [${name}] rebase origin/${def}"
      if ! git -C "${wt}" rebase --quiet "origin/${def}"; then
        log "⚠️  [conflict] [${name}] rebase 충돌 — 해결 후 'git -C ${wt} rebase --continue' (취소: --abort)"
        git -C "${wt}" diff --name-only --diff-filter=U >&2
        rc=5
        continue
      fi
    else
      log "🔀 [${name}] merge origin/${def}"
      if ! git -C "${wt}" merge --no-edit --quiet "origin/${def}"; then
        log "⚠️  [conflict] [${name}] merge 충돌 — 해결 후 'git -C ${wt} merge --continue' (취소: --abort)"
        git -C "${wt}" diff --name-only --diff-filter=U >&2
        rc=5
        continue
      fi
    fi

    # upstream 이 심링크 자리를 추적하기 시작하면 merge 가 심링크를 실디렉토리로 바꾼다 → 파일 단위로 재연결
    link_repo "${id}" "${name}"
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
    # .prompts/ 는 스크래치 — worktree 와 함께 사라지는 게 맞으므로 차단 사유가 아니다
    case "${path}" in .prompts|.prompts/*) continue ;; esac
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
  local rc=0 br remove_flags removed=0

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
    removed=$((removed + 1))
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

  # 이번 실행에서 지웠고 아무것도 안 남았을 때만 완료로 기록 (재실행·[locked] 잔류 시엔 찍지 않는다)
  if [[ "${removed}" -gt 0 ]] && [[ -z "$(task_worktrees "${task_dir}")" ]]; then
    notes_mark_done "${task_dir}/notes.md"
    log "📄 notes.md 에 완료 일시 기록 (보존): ${task_dir}/notes.md"
  else
    log "📄 notes.md 보존: ${task_dir}/notes.md"
  fi
  write_index
  log "📇 tasks/INDEX.md 갱신"
  return "${rc}"
}

# ---------------------------------------------------------------- list

cmd_list() {
  require_root

  local d id n created status

  printf '%-20s %-12s %-16s %s\n' "TASK" "STATUS" "CREATED" "TITLE"

  for d in "${ROOT}"/tasks/*/; do
    [[ -d "${d}" ]] || continue
    id="$(basename "${d}")"
    n="$(task_worktrees "${d}" | grep -c . || true)"
    created="$(grep -m1 '생성 일시' "${d}notes.md" 2>/dev/null || true)"
    created="${created#*: }"
    status="active(${n})"
    [[ "${n}" -eq 0 ]] && status="archived"
    printf '%-20s %-12s %-16s %s\n' "${id}" "${status}" "${created:--}" "$(notes_title "${d}notes.md" "${id}")"
  done

  write_index
}

cmd_index() {
  require_root
  write_index
  log "📇 tasks/INDEX.md 갱신"
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
  migrate) cmd_migrate "$@" ;;
  sync)  cmd_sync "$@" ;;
  done)  cmd_done "$@" ;;
  list)  cmd_list ;;
  index) cmd_index ;;
  -h|--help|help) usage ;;
  *) log "알 수 없는 서브커맨드: ${cmd}"; usage ;;
esac
