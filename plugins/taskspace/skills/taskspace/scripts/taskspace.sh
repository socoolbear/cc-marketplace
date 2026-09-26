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
#   ├── tasks/CLAUDE.md     작업 지도 (추적, 없으면 init/new 가 템플릿에서 생성. 상위라 worktree 세션에도 실림.
#                           <!-- taskspace:begin/end --> 표식 안쪽만 upgrade 가 관리, 밖은 사용자 영역)
#   ├── tasks/<ID>/         진행 중 — notes.md (추적) · <repo>/ worktree (ignore) · <repo>/.prompts/ 스크래치 (info/exclude)
#   └── archive/<ID>/       끝난 태스크 (완료·보류·폐기) — notes.md 등 추적 파일만, worktree 없음 (done/hold/abandon 이 이동)
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

# 표식(<!-- taskspace:begin/end -->) 도입 전, 정확히 이 내용이었던 tasks/CLAUDE.md 의 해시 목록
# (끝 개행 차이 무시, content_hash 로 계산). upgrade 가 "사용자가 안 고친 구버전 원본"인지 판별하는 데만 쓴다.
#   644d58437e0d17644a1e82f976f4760880df8ad8d7157182a1726f515e0ea728 — 커밋 2980e71 "taskspace 1.3.0" 의 원본 (표식 도입 전)
CLAUDE_LEGACY_HASHES="644d58437e0d17644a1e82f976f4760880df8ad8d7157182a1726f515e0ea728"

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
                                             worktree 제거. worktree 가 하나도 안 남으면 notes.md 에 완료 기록 후
                                             tasks/<ID> → archive/<ID> 이동. 안전 검사 통과 시에만.
                                             --delete-branch 는 로컬 브랜치와, 기본 브랜치에 병합이 확인된 경우 원격 브랜치까지 삭제
  hold <TASK-ID> [--reason <사유>] [--discard-untracked] [--force]
                                             보류. worktree 제거 + notes.md 에 보류 기록·보존 브랜치 후 archive/ 로 이동.
                                             --merged · --delete-branch 는 지원하지 않음 (재개를 위해 브랜치를 남긴다)
  abandon <TASK-ID> [--reason <사유>] [--discard-untracked] [--delete-branch] [--force]
                                             폐기. hold 와 같되 --delete-branch 로 로컬 브랜치만 삭제 가능 (원격 브랜치는 지우지 않음).
                                             --merged 는 지원하지 않음
  resume <TASK-ID> [<repo>[=<branch>]...]    archive/<ID> → tasks/<ID> 이동 + 재개 기록. repo 인자가 없으면
                                             보존 브랜치로 worktree 재생성 (없으면 이동만)
  list                                       tasks/ 목록 (TITLE 은 notes.md 첫 줄). 끝에 archive 요약 · index 실행
  index                                      tasks/INDEX.md 재생성 (진행 중 · 보류 · 폐기 · 완료 섹션. new · done · list 끝에 자동 실행)
  upgrade                                    플러그인 업데이트를 워크스페이스에 반영 (멱등). 레거시 완료 태스크를
                                             done 경로로 archive/ 이전 + tasks/CLAUDE.md 표식 블록 최신화. 자동 실행 안 됨

종료코드: 1 인자 오류 · 2 루트 없음 · 3 repo 미지정 · 4 done/hold/abandon 차단 · 5 sync 미완료
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

# tasks/ · archive/ 의 번호형 디렉토리 (<접두사><숫자>) 중 최대 번호 +1 을 3자리로. 접두사는 계승하되 둘 이상 섞이면 거부
next_id() {
  local d base prefix num max=0 seen=0 first_prefix=""

  for d in "${ROOT}"/tasks/*/ "${ROOT}"/archive/*/; do
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

# notes.md 헤더에 '- <라벨>: <값>' 줄들을 순서대로 추가 (라벨이 이미 있으면 그 줄은 건너뜀, 보존).
# '- 생성 일시:' 줄 뒤에 삽입, 없으면 끝에. 인자: notes label1 value1 [label2 value2 ...]
# (awk -v 는 값에 개행이 섞이면 일부 awk 구현에서 깨져서 순수 bash 로 처리)
notes_set_fields() {
  local notes=$1 tmp line inserted=0 i
  local labels=() values=()
  shift

  [[ -f "${notes}" ]] || return 0

  while [[ $# -ge 2 ]]; do
    grep -q -- "^- $1:" "${notes}" || { labels+=("$1"); values+=("$2"); }
    shift 2
  done
  [[ ${#labels[@]} -gt 0 ]] || return 0

  tmp="${notes}.tmp.$$"
  : > "${tmp}"
  while IFS= read -r line || [[ -n "${line}" ]]; do
    printf '%s\n' "${line}" >> "${tmp}"
    if [[ "${inserted}" -eq 0 && "${line}" == "- 생성 일시:"* ]]; then
      for ((i = 0; i < ${#labels[@]}; i++)); do
        printf -- '- %s: %s\n' "${labels[i]}" "${values[i]}" >> "${tmp}"
      done
      inserted=1
    fi
  done < "${notes}"

  if [[ "${inserted}" -eq 0 ]]; then
    for ((i = 0; i < ${#labels[@]}; i++)); do
      printf -- '- %s: %s\n' "${labels[i]}" "${values[i]}" >> "${tmp}"
    done
  fi

  mv -- "${tmp}" "${notes}"
}

# notes.md 헤더에서 '- <라벨>: ...' 줄들을 제거 (없으면 통과). 인자: notes label...
notes_remove_fields() {
  local notes=$1 tmp pattern=""
  shift

  [[ -f "${notes}" ]] || return 0

  while [[ $# -ge 1 ]]; do
    pattern="${pattern}${pattern:+|}^- $1:"
    shift
  done
  [[ -n "${pattern}" ]] || return 0

  tmp="${notes}.tmp.$$"
  grep -vE -- "${pattern}" "${notes}" > "${tmp}" || true
  mv -- "${tmp}" "${notes}"
}

# notes.md 의 '- 재개 기록:' 줄에 항목을 추가 (이미 있으면 '; ' 로 이어 붙임, 없으면 새로 만듦)
notes_append_resume_record() {
  local notes=$1 entry=$2 tmp

  [[ -f "${notes}" ]] || return 0

  if grep -q -- '^- 재개 기록:' "${notes}"; then
    tmp="${notes}.tmp.$$"
    awk -v add="${entry}" '
      /^- 재개 기록:/ { sub(/[[:space:]]+$/, ""); $0 = $0 "; " add }
      { print }
    ' "${notes}" > "${tmp}"
    mv -- "${tmp}" "${notes}"
  else
    notes_set_fields "${notes}" "재개 기록" "${entry}"
  fi
}

# tasks/CLAUDE.md 가 없을 때만 템플릿에서 만든다 (사용자 수정 보존)
ensure_tasks_claude() {
  [[ -f "${ROOT}/tasks/CLAUDE.md" ]] && return 0
  [[ -f "${TASKS_CLAUDE_TEMPLATE}" ]] || die 1 "템플릿이 없습니다: ${TASKS_CLAUDE_TEMPLATE}"
  cp -- "${TASKS_CLAUDE_TEMPLATE}" "${ROOT}/tasks/CLAUDE.md"
  log "🗺️  tasks/CLAUDE.md 생성"
}

# 파일 내용의 sha256 (끝 개행 차이는 무시 — $() 이 command substitution 에서 trailing newline 을 없애 준다)
content_hash() {
  printf '%s' "$(cat "$1")" | shasum -a 256 | awk '{print $1}'
}

# '<!-- taskspace:begin -->' ~ '<!-- taskspace:end -->' 사이 내용만 추출 (표식 없으면 아무것도 출력하지 않음)
claude_marker_block() {
  [[ -f "$1" ]] || return 0
  awk '/<!-- taskspace:begin -->/{f=1; next} /<!-- taskspace:end -->/{f=0} f' "$1"
}

# file 의 표식 블록을 new_block(멀티라인 문자열) 으로 교체 (표식 밖은 그대로 보존). 순수 bash — awk -v 는
# 값에 개행이 섞이면 일부 awk 구현(macOS 기본)에서 깨진다 (notes_set_fields 와 같은 이유)
replace_marker_block() {
  local file=$1 new_block=$2 tmp line skip=0

  tmp="${file}.tmp.$$"
  : > "${tmp}"
  while IFS= read -r line || [[ -n "${line}" ]]; do
    if [[ "${line}" == *"<!-- taskspace:begin -->"* ]]; then
      printf '%s\n' "${line}" >> "${tmp}"
      printf '%s\n' "${new_block}" >> "${tmp}"
      skip=1
      continue
    fi
    [[ "${line}" == *"<!-- taskspace:end -->"* ]] && skip=0
    [[ "${skip}" -eq 1 ]] || printf '%s\n' "${line}" >> "${tmp}"
  done < "${file}"
  mv -- "${tmp}" "${file}"
}

# tasks/CLAUDE.md 의 표식 블록이 없거나 최신 템플릿과 다르면 0 (upgrade 가 필요하다는 뜻)
claude_needs_marker_update() {
  local file="${ROOT}/tasks/CLAUDE.md"

  [[ -f "${file}" ]] || return 0
  grep -q -- '<!-- taskspace:begin -->' "${file}" || return 0
  [[ "$(claude_marker_block "${file}")" == "$(claude_marker_block "${TASKS_CLAUDE_TEMPLATE}")" ]] && return 1
  return 0
}

# 레거시 이전 대상이 있거나 tasks/CLAUDE.md 가 최신 템플릿과 다르면 0 — list·new 끝의 안내용 싼 검사
upgrade_needed() {
  local d id n finished

  for d in "${ROOT}"/tasks/*/; do
    [[ -d "${d}" ]] || continue
    id="$(basename "${d}")"
    n="$(task_worktrees "${d}" | grep -c . || true)"
    if [[ "${n}" -eq 0 ]]; then
      finished="$(notes_field "${d}notes.md" '완료 일시')"
      [[ -n "${finished}" ]] && return 0
    fi
  done

  claude_needs_marker_update
}

# tasks/CLAUDE.md 를 표식 형식으로 최신화. 결과 한 줄을 stdout 으로 (요약용) — 항상 exit 0
upgrade_tasks_claude() {
  local file="${ROOT}/tasks/CLAUDE.md" hash tpl_block cur_block

  if [[ ! -f "${file}" ]]; then
    ensure_tasks_claude
    printf '생성\n'
    return 0
  fi

  tpl_block="$(claude_marker_block "${TASKS_CLAUDE_TEMPLATE}")"

  if grep -q -- '<!-- taskspace:begin -->' "${file}"; then
    cur_block="$(claude_marker_block "${file}")"
    if [[ "${cur_block}" == "${tpl_block}" ]]; then
      printf '최신 (변경 없음)\n'
      return 0
    fi
    replace_marker_block "${file}" "${tpl_block}"
    printf '표식 안쪽을 최신 템플릿으로 교체 (표식 밖 사용자 영역은 보존)\n'
    return 0
  fi

  hash="$(content_hash "${file}")"
  case " ${CLAUDE_LEGACY_HASHES} " in
    *" ${hash} "*)
      cp -- "${TASKS_CLAUDE_TEMPLATE}" "${file}"
      printf '표식 도입 전 원본이라 표식 형식으로 통째 교체\n'
      return 0
      ;;
  esac

  printf '표식이 없고 알려진 구버전과도 달라 사용자 수정으로 보고 그대로 둠 — %s 를 참고해 <!-- taskspace:begin -->…<!-- taskspace:end --> 로 감싸 넣으세요\n' \
    "${TASKS_CLAUDE_TEMPLATE}"
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

# notes.md 의 '- 상태:' (없으면 '- 완료 일시:' 존재 시 완료) — archive/<ID> 판정용
archive_status() {
  local notes=$1 status

  status="$(notes_field "${notes}" '상태')"
  if [[ -z "${status}" ]]; then
    [[ -n "$(notes_field "${notes}" '완료 일시')" ]] && status="완료"
  fi
  printf '%s\n' "${status:-완료}"
}

# archive/ 의 한 상태 섹션 (보류·폐기·완료) 출력. 인자: 섹션명 종료일시라벨
write_index_archive_section() {
  local section=$1 date_label=$2 d id notes title created finished reason rows=""

  for d in "${ROOT}"/archive/*/; do
    [[ -d "${d}" ]] || continue
    notes="${d}notes.md"
    [[ "$(archive_status "${notes}")" == "${section}" ]] || continue

    id="$(basename "${d}")"
    title="$(notes_title "${notes}" "${id}")"
    created="$(notes_field "${notes}" '생성 일시')"
    finished="$(notes_field "${notes}" "${date_label}")"
    reason="$(notes_field "${notes}" '사유')"
    rows="${rows}$(printf '| [%s](../archive/%s/notes.md) | %s | %s | %s | %s | %s |' \
      "${id}" "${id}" "${title//|/\\|}" "$(notes_field "${notes}" '관련 repo')" \
      "${created%% *}" "${finished%% *}" "${reason//|/\\|}")
"
  done

  # 빈 섹션은 헤더만 남은 표 대신 '없음' 한 줄
  printf '## %s\n\n' "${section}"
  if [[ -n "${rows}" ]]; then
    printf '| ID | 제목 | repo (브랜치) | 생성 | 종료 | 사유 |\n|---|---|---|---|---|---|\n%s' "${rows}"
  else
    printf '없음\n'
  fi
  printf '\n'
}

# tasks/INDEX.md 를 notes.md 만으로 다시 쓴다 (머신 로컬 상태는 넣지 않는다).
# 섹션: 진행 중(tasks/) · 보류 · 폐기 · 완료(archive/, notes.md 의 '- 상태:' 로 분류)
write_index() {
  local index="${ROOT}/tasks/INDEX.md" tmp d id notes title created rows=""

  tmp="${index}.tmp.$$"
  {
    printf '# 태스크 색인\n\n'
    # shellcheck disable=SC2016
    printf '<!-- 생성 파일 — `taskspace.sh index` 가 다시 씀. 직접 편집 금지. 제목은 각 notes.md 첫 줄에서 고친다 -->\n\n'

    for d in "${ROOT}"/tasks/*/; do
      [[ -d "${d}" ]] || continue
      id="$(basename "${d}")"
      notes="${d}notes.md"
      title="$(notes_title "${notes}" "${id}")"
      created="$(notes_field "${notes}" '생성 일시')"
      rows="${rows}$(printf '| [%s](%s/notes.md) | %s | %s | %s |' \
        "${id}" "${id}" "${title//|/\\|}" "$(notes_field "${notes}" '관련 repo')" "${created%% *}")
"
    done
    printf '## 진행 중\n\n'
    if [[ -n "${rows}" ]]; then
      printf '| ID | 제목 | repo (브랜치) | 생성 |\n|---|---|---|---|\n%s' "${rows}"
    else
      printf '없음\n'
    fi
    printf '\n'

    write_index_archive_section '보류' '보류 일시'
    write_index_archive_section '폐기' '폐기 일시'
    write_index_archive_section '완료' '완료 일시'
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

  [[ -d "${ROOT}/archive/${id}" ]] \
    && die 1 "archive 에 있는 태스크입니다 (완료·보류·폐기) — resume ${id} 로 재개하세요"

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
  if upgrade_needed; then
    log "ℹ️  워크스페이스가 현재 스킬 버전보다 오래됐습니다 — 'upgrade' 로 반영"
  fi
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

cmd_done()    { run_finish "done"    "$@"; }
cmd_hold()    { run_finish "hold"    "$@"; }
cmd_abandon() { run_finish "abandon" "$@"; }

# done · hold · abandon 공통 구현. mode: done | hold | abandon
# 안전 검사(1단계) 통과 시에만 worktree 를 제거(2단계)하고, 태스크에 worktree 가 하나도
# 안 남으면 notes.md 에 상태를 기록한 뒤 tasks/<ID> → archive/<ID> 로 옮긴다.
run_finish() {
  local mode=$1 id task_dir archive_dir notes reason=""
  local merged=0 discard=0 delete_branch=0 force=0

  shift
  [[ $# -ge 1 ]] || usage
  require_root

  id=$1
  shift
  validate_id "${id}"
  task_dir="${ROOT}/tasks/${id}"
  archive_dir="${ROOT}/archive/${id}"
  notes="${task_dir}/notes.md"

  if [[ ! -d "${task_dir}" ]]; then
    if [[ -d "${archive_dir}" ]]; then
      die 1 "이미 archive 에 있습니다 (상태: $(archive_status "${archive_dir}/notes.md")). 재개는 resume ${id}"
    fi
    die 1 "태스크가 없습니다: ${task_dir}"
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --merged)
        [[ "${mode}" == "done" ]] || die 1 "${mode} 은 --merged 를 지원하지 않습니다"
        merged=1; shift ;;
      --discard-untracked) discard=1; shift ;;
      --delete-branch)
        [[ "${mode}" != "hold" ]] || die 1 "hold 는 --delete-branch 를 지원하지 않습니다 — 브랜치를 지우면 재개할 수 없습니다"
        delete_branch=1; shift ;;
      --force) force=1; shift ;;
      --reason)
        [[ "${mode}" != "done" ]] || die 1 "done 은 --reason 을 지원하지 않습니다"
        [[ $# -ge 2 ]] || die 1 "--reason 에 값이 없습니다"
        reason=$2; shift 2 ;;
      *) die 1 "알 수 없는 옵션: $1" ;;
    esac
  done

  case "$(pwd)/" in
    "${task_dir}/"*) die 4 "[cwd] 현재 디렉토리가 태스크 안입니다. 밖으로 나간 뒤 실행하세요: cd ${ROOT}" ;;
  esac

  local names name wt bare blocks=0 skipped="" files dirty_hint=""
  [[ "${mode}" == "done" ]] || dirty_hint=" — WIP 커밋 후 push 하세요"

  names="$(task_worktrees "${task_dir}")"
  [[ -n "${names}" ]] || log "ℹ️  제거할 worktree 가 없습니다 (레거시 — 기록·이동만 진행)"

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
      log "⛔ [dirty] [${name}] 추적 파일에 미커밋 변경${dirty_hint}:"
      git -C "${wt}" status --porcelain | grep -vE '^(\?\?|!!) ' >&2
      blocks=$((blocks + 1))
    fi

    if ! git -C "${wt}" branch -r --contains HEAD | grep -q . && [[ "${merged}" -eq 0 && "${force}" -eq 0 ]]; then
      if [[ "${mode}" == "done" ]]; then
        log "⛔ [unpushed] [${name}] HEAD 가 어느 원격 브랜치에도 없음 (push 안 됨, 또는 squash 머지 후 원격 브랜치 삭제). PR 병합이 확인되면 --merged"
      else
        log "⛔ [unpushed] [${name}] HEAD 가 원격에 없음 — push 하지 않으면 이 머신의 .bares/ 에만 남습니다. push 후 재실행하세요 (무시하려면 --force)"
      fi
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

  # hold·abandon 은 worktree 제거 전에 재개용 브랜치 정보를 남긴다
  if [[ "${mode}" == "hold" || "${mode}" == "abandon" ]]; then
    local preserved="" hash
    for name in ${names}; do
      case " ${skipped} " in *" ${name} "*) continue ;; esac
      wt="${task_dir}/${name}"
      br="$(git -C "${wt}" symbolic-ref --short HEAD 2>/dev/null || true)"
      hash="$(git -C "${wt}" rev-parse --short HEAD 2>/dev/null || true)"
      [[ -n "${br}" ]] || continue
      preserved="${preserved}${preserved:+, }${name} ${br}${hash:+@${hash}}"
    done
    if [[ -n "${preserved}" ]]; then
      notes_set_fields "${notes}" "보존 브랜치" "${preserved}"
      log "🔖 보존 브랜치 기록: ${preserved}"
    fi
  fi

  # 2단계: 제거
  local rc=0 br remove_flags removed=0 is_merged def

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

    # 원격에 사본이 하나도 없는 브랜치는 지우면 작업이 사라진다 — done 에서 --merged (병합 확인) 일 때만 예외
    if ! git -C "${bare}" branch -r --contains "${br}" | grep -q . && [[ "${merged}" -eq 0 ]]; then
      log "ℹ️  [${name}] 브랜치 유지: ${br} (원격에 사본 없음 — 병합 확인 후 --merged 와 함께)"
      continue
    fi
    git -C "${bare}" branch -D "${br}" >/dev/null && log "🧹 [${name}] 로컬 브랜치 삭제: ${br}"

    # abandon 은 원격 브랜치를 절대 지우지 않는다 (로컬만 정리)
    [[ "${mode}" == "done" ]] || continue

    # 원격 브랜치는 병합이 확인됐을 때만 지운다. 병합 = 기본 브랜치 origin/<def> 가 브랜치 끝 커밋을 포함.
    # 다른 feature 브랜치가 포함하는 것 (stacked branch) 은 병합이 아니다 — 그 브랜치의 base 를 지우게 된다
    git -C "${bare}" rev-parse --verify --quiet "refs/remotes/origin/${br}" >/dev/null || continue
    is_merged=0
    if [[ "${merged}" -eq 1 ]]; then
      is_merged=1
    elif def="$(default_branch "${bare}")" && git -C "${bare}" merge-base --is-ancestor "origin/${br}" "origin/${def}" 2>/dev/null; then
      is_merged=1
    fi
    if [[ "${is_merged}" -eq 1 ]]; then
      if git -C "${bare}" push --quiet origin --delete "${br}"; then
        log "🧹 [${name}] 원격 브랜치 삭제: origin/${br}"
      else
        log "⚠️  [${name}] 원격 브랜치 삭제 실패: origin/${br}"
        rc=1
      fi
    else
      log "ℹ️  [${name}] 원격 브랜치 유지: origin/${br} (병합 확인 안 됨 — 병합 후 --merged 와 함께)"
    fi
  done

  # 태스크에 worktree 가 하나도 안 남았을 때만 상태 기록 → archive/ 로 이동 ([locked] 로 남은 게 있으면 보류)
  if [[ -n "$(task_worktrees "${task_dir}")" ]]; then
    log "📄 notes.md 보존 (일부 repo 가 남아 기록·이동을 보류합니다: ${skipped}): ${notes}"
    write_index
    log "📇 tasks/INDEX.md 갱신"
    return "${rc}"
  fi

  local now
  now="$(date '+%Y-%m-%d %H:%M')"
  case "${mode}" in
    done)
      notes_set_fields "${notes}" "상태" "완료" "완료 일시" "${now}"
      ;;
    hold)
      if [[ -n "${reason}" ]]; then
        notes_set_fields "${notes}" "상태" "보류" "보류 일시" "${now}" "사유" "${reason}"
      else
        notes_set_fields "${notes}" "상태" "보류" "보류 일시" "${now}"
      fi
      ;;
    abandon)
      if [[ -n "${reason}" ]]; then
        notes_set_fields "${notes}" "상태" "폐기" "폐기 일시" "${now}" "사유" "${reason}"
      else
        notes_set_fields "${notes}" "상태" "폐기" "폐기 일시" "${now}"
      fi
      ;;
  esac
  log "📄 notes.md 갱신: ${notes}"

  mkdir -p "${ROOT}/archive"
  [[ ! -e "${archive_dir}" ]] || die 1 "archive/${id} 가 이미 있습니다"
  mv -- "${task_dir}" "${archive_dir}"
  log "📦 이동: tasks/${id} → archive/${id}"

  write_index
  log "📇 tasks/INDEX.md 갱신"
  return "${rc}"
}

# ---------------------------------------------------------------- list

cmd_list() {
  require_root

  local d id n created status st hold_n=0 abandon_n=0 done_n=0

  printf '%-20s %-12s %-16s %s\n' "TASK" "STATUS" "CREATED" "TITLE"

  for d in "${ROOT}"/tasks/*/; do
    [[ -d "${d}" ]] || continue
    id="$(basename "${d}")"
    n="$(task_worktrees "${d}" | grep -c . || true)"
    created="$(grep -m1 '생성 일시' "${d}notes.md" 2>/dev/null || true)"
    created="${created#*: }"
    status="active(${n})"

    [[ "${n}" -eq 0 ]] && status="idle"

    printf '%-20s %-12s %-16s %s\n' "${id}" "${status}" "${created:--}" "$(notes_title "${d}notes.md" "${id}")"
  done

  for d in "${ROOT}"/archive/*/; do
    [[ -d "${d}" ]] || continue
    st="$(archive_status "${d}notes.md")"
    case "${st}" in
      보류) hold_n=$((hold_n + 1)) ;;
      폐기) abandon_n=$((abandon_n + 1)) ;;
      *)   done_n=$((done_n + 1)) ;;
    esac
  done
  printf 'archive: 보류 %s · 폐기 %s · 완료 %s — tasks/INDEX.md 참고\n' "${hold_n}" "${abandon_n}" "${done_n}"

  if upgrade_needed; then
    log "ℹ️  워크스페이스가 현재 스킬 버전보다 오래됐습니다 — 'upgrade' 로 반영"
  fi

  write_index
}

cmd_index() {
  require_root
  write_index
  log "📇 tasks/INDEX.md 갱신"
}

# ---------------------------------------------------------------- resume

cmd_resume() {
  [[ $# -ge 1 ]] || usage
  require_root

  local id=$1 archive_dir task_dir notes prev_status prev_when prev_reason prev_branches
  local specs=() rest entry repo br now
  shift
  validate_id "${id}"
  archive_dir="${ROOT}/archive/${id}"
  task_dir="${ROOT}/tasks/${id}"
  notes="${archive_dir}/notes.md"

  [[ -d "${archive_dir}" ]] || die 1 "archive 에 태스크가 없습니다: ${archive_dir}"
  [[ ! -d "${task_dir}" ]] || die 1 "이미 tasks/ 에 있는 태스크입니다: ${task_dir}"

  prev_status="$(archive_status "${notes}")"
  case "${prev_status}" in
    보류) prev_when="$(notes_field "${notes}" '보류 일시')" ;;
    폐기) prev_when="$(notes_field "${notes}" '폐기 일시')" ;;
    *)   prev_when="$(notes_field "${notes}" '완료 일시')" ;;
  esac
  prev_reason="$(notes_field "${notes}" '사유')"
  prev_branches="$(notes_field "${notes}" '보존 브랜치')"

  notes_remove_fields "${notes}" "상태" "완료 일시" "보류 일시" "폐기 일시" "사유" "보존 브랜치"
  now="$(date '+%Y-%m-%d %H:%M')"
  notes_append_resume_record "${notes}" "${now} (${prev_status} ${prev_when}${prev_reason:+, 사유: ${prev_reason}})"

  mv -- "${archive_dir}" "${task_dir}"
  log "📦 이동: archive/${id} → tasks/${id}"

  if [[ $# -gt 0 ]]; then
    specs=("$@")
  elif [[ -n "${prev_branches}" ]]; then
    rest="${prev_branches}"
    while [[ -n "${rest}" ]]; do
      if [[ "${rest}" == *", "* ]]; then
        entry="${rest%%, *}"
        rest="${rest#*, }"
      else
        entry="${rest}"
        rest=""
      fi
      repo="${entry%% *}"
      br="${entry#* }"
      br="${br%%@*}"
      [[ -n "${repo}" && -n "${br}" ]] && specs+=("${repo}=${br}")
    done
  fi

  if [[ ${#specs[@]} -gt 0 ]]; then
    log "🌿 보존 브랜치로 worktree 재생성"
    cmd_new "${id}" "${specs[@]}" || true
  else
    log "ℹ️  repo 정보가 없어 worktree 를 만들지 않았습니다 — new ${id} <repo> 로 추가하세요"
  fi

  write_index
  log "📇 tasks/INDEX.md 갱신"
  log "🔄 기본 브랜치가 전진했을 수 있으니 sync ${id} 를 실행하세요"
}

# ---------------------------------------------------------------- upgrade

# 플러그인 업데이트를 워크스페이스에 반영 (멱등). 자동 실행은 하지 않는다 — 사용자가 upgrade 를 요청하거나
# list/new 가 안내했을 때만. 1) worktree 없이 완료 일시만 있는 레거시 태스크를 done 경로로 archive/ 이전
# 2) tasks/CLAUDE.md 표식 블록을 최신 템플릿으로 (표식 밖 사용자 영역은 보존)
cmd_upgrade() {
  require_root

  local d id n finished moved=0 skipped_cwd="" idle_list="" claude_result

  for d in "${ROOT}"/tasks/*/; do
    [[ -d "${d}" ]] || continue
    id="$(basename "${d}")"
    n="$(task_worktrees "${d}" | grep -c . || true)"
    [[ "${n}" -eq 0 ]] || continue

    finished="$(notes_field "${d}notes.md" '완료 일시')"
    if [[ -z "${finished}" ]]; then
      idle_list="${idle_list}${idle_list:+, }${id}"
      continue
    fi

    case "$(pwd)/" in
      "${d}"*)
        log "ℹ️  [${id}] 현재 디렉토리 안이라 건너뜀 — 밖으로 나간 뒤 upgrade 를 다시 실행하세요"
        skipped_cwd="${skipped_cwd}${skipped_cwd:+, }${id}"
        continue
        ;;
    esac

    log "📦 [${id}] 레거시 이전 (done 경로 재사용)"
    if cmd_done "${id}"; then
      moved=$((moved + 1))
    else
      log "⚠️  [${id}] 이전 실패 — 위 로그를 확인하세요"
    fi
  done

  claude_result="$(upgrade_tasks_claude)"
  log "🗺️  tasks/CLAUDE.md: ${claude_result}"

  write_index
  log "📇 tasks/INDEX.md 갱신"

  log "✅ upgrade 요약: 레거시 이전 ${moved}건${skipped_cwd:+ · cwd 로 건너뜀: ${skipped_cwd}}${idle_list:+ · 수동 처리 필요(완료 일시 없는 idle): ${idle_list}} · CLAUDE.md: ${claude_result}"
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
  hold)  cmd_hold "$@" ;;
  abandon) cmd_abandon "$@" ;;
  resume) cmd_resume "$@" ;;
  list)  cmd_list ;;
  index) cmd_index ;;
  upgrade) cmd_upgrade ;;
  -h|--help|help) usage ;;
  *) log "알 수 없는 서브커맨드: ${cmd}"; usage ;;
esac
