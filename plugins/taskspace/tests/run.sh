#!/usr/bin/env bash
# taskspace 시험 — 세션 시작 점검 (check) 과 요구 선언 (requires.txt · requires 명령).
# 격리한 임시 폴더 안에 워크스페이스 · 가짜 HOME · 가짜 설치 기록 · 가짜 claude 를 만들어 돌린다.
# 실제 워크스페이스 · 설정 폴더는 건드리지 않는다. 스크립트는 /bin/bash (macOS 기본 3.2) 로 돌려 호환을 함께 본다.
#
# 사용법: tests/run.sh
set -uo pipefail

readonly PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly TS="${PLUGIN_ROOT}/skills/taskspace/scripts/taskspace.sh"
readonly SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
readonly FAKE_HOME="${SANDBOX}/home"
readonly FAKE_CONFIG="${SANDBOX}/config"
readonly FAKE_BIN="${SANDBOX}/fakebin"
readonly NOJQ_BIN="${SANDBOX}/nojqbin"
readonly INSTALLED="${FAKE_CONFIG}/plugins/installed_plugins.json"
readonly BUNDLE="${SANDBOX}/bundle"          # 묶음 repo (꼭대기에 .git)
readonly GROUP="${BUNDLE}/grp"               # 그 안의 taskspace 루트
readonly DECLARED="${BUNDLE}/requires.txt"
readonly SOLO="${SANDBOX}/solo"              # 단독 워크스페이스 (루트가 곧 git repo)
readonly MARKER="${SANDBOX}/evaluated"       # 셸로 평가됐으면 생기는 파일

readonly JQ_DIR="$(dirname "$(command -v jq 2>/dev/null || echo /usr/bin/jq)")"   # jq 가 /usr/bin 밖에 있는 장비

trap 'rm -rf "${SANDBOX}"' EXIT

failures=0
checks=0

check() {
  local label="$1" expected="$2" actual="$3"

  checks=$((checks + 1))

  if [[ "${expected}" == "${actual}" ]]; then
    echo "PASS ${label}"
    return 0
  fi

  failures=$((failures + 1))
  echo "FAIL ${label} — 기대 [${expected}] 실제 [${actual}]"
}

checkContains() {
  local label="$1" needle="$2" haystack="$3"

  if grep -qF -- "${needle}" <<<"${haystack}"; then
    check "${label}" "있음" "있음"
  else
    check "${label}" "있음: ${needle}" "없음: ${haystack}"
  fi
}

checkLacks() {
  local label="$1" needle="$2" haystack="$3"

  if grep -qF -- "${needle}" <<<"${haystack}"; then
    check "${label}" "없음: ${needle}" "있음"
  else
    check "${label}" "없음" "없음"
  fi
}

# runTs <cwd> <서브커맨드> — 격리한 환경에서 스크립트를 돌린다. 호출 쪽이 앞에 붙인 환경변수 (PATH · FAKE_CLAUDE_MODE 등) 는 그대로 넘어간다
runTs() {
  local cwd="$1"
  shift

  (
    cd "${cwd}" || exit 99
    env -u TASKSPACE_ROOT HOME="${FAKE_HOME}" CLAUDE_CONFIG_DIR="${FAKE_CONFIG}" \
      PATH="${TEST_PATH:-${FAKE_BIN}:${JQ_DIR}:/usr/bin:/bin}" \
      TASKSPACE_REQUIRES_SKIP="${TEST_SKIP:-}" FAKE_CLAUDE_MODE="${FAKE_CLAUDE_MODE:-ok}" \
      /bin/bash "${TS}" "$@"
  )
}

upgradeLine() {   # upgradeLine <루트> <사유> — 2.11.0 의 upgrade 안내 문구 그대로
  printf 'taskspace 워크스페이스 (%s) 에 플러그인 업데이트 반영이 남아 있습니다: %s. 사용자에게 한 줄로 알리고, 수락하면 taskspace 스킬의 upgrade 를 실행하세요.' "$1" "$2"
}

requiresLine() {  # requiresLine <루트> <선언 파일> <항목들>
  printf 'taskspace 워크스페이스 (%s) 가 요구하는 것 중 이 장비에 없는 것이 있습니다 (선언: %s): %s. 하던 일을 먼저 하고, 사용자에게 한 줄로 알린 뒤 수락하면 안내된 명령을 실행하세요 (플러그인은 새 세션부터 적용). 사용자가 없는 세션이면 실행하지 말고 넘어가세요. 선택 항목을 포함한 전체는 taskspace 스킬의 requires 로 봅니다.' "$1" "$2" "$3"
}

treeHash() {      # 폴더 전체의 파일 목록과 내용 해시 (읽기 전용 확인용)
  (cd "$1" && find . \( -type f -o -type l \) -print0 | sort -z | xargs -0 shasum 2>/dev/null | shasum | cut -d' ' -f1)
}

writeInstalled() {
  mkdir -p "${FAKE_CONFIG}/plugins"
  cat >"${INSTALLED}"
}

setUp() {
  mkdir -p "${FAKE_HOME}" "${FAKE_BIN}" "${NOJQ_BIN}" "${BUNDLE}"

  # 가짜 claude — `plugin list --json` 만 답한다. 실제 CLI 가 가짜 설정 폴더에 쓰는 것을 막는다
  cat >"${FAKE_BIN}/claude" <<'EOF'
#!/bin/bash
case "${FAKE_CLAUDE_MODE:-ok}" in
  fail)  exit 1 ;;
  empty) exit 0 ;;
esac
printf '[{"id":"on@m","enabled":true},{"id":"off@m","enabled":false}]\n'
EOF
  chmod +x "${FAKE_BIN}/claude"

  # jq 만 없는 PATH — /usr/bin 을 통째로 빼면 grep · sed 도 사라져 엉뚱한 이유로 조용해진다
  local tool
  for tool in /usr/bin/* /bin/*; do
    [[ "$(basename "${tool}")" == "jq" ]] || ln -sf "${tool}" "${NOJQ_BIN}/$(basename "${tool}")"   # jq 가 다른 폴더에 있으면 애초에 여기 없다
  done

  writeInstalled <<'EOF'
{"version": 2, "plugins": {
  "old@m":   [{"scope": "user", "version": "1.9.0"}],
  "short@m": [{"scope": "user", "version": "2.0"}],
  "zero@m":  [{"scope": "user", "version": "1.8.0"}],
  "odd@m":   [{"scope": "user", "version": "main-abc"}],
  "multi@m": [{"scope": "user", "version": "1.0.0"}, {"scope": "user", "version": "1.2.0"}],
  "other@m": [{"scope": "project", "projectPath": "/somewhere/else", "version": "1.0.0"}],
  "on@m":    [{"scope": "user", "version": "1.0.0"}],
  "off@m":   [{"scope": "user", "version": "1.0.0"}]
}}
EOF

  git -C "${BUNDLE}" init -q
  runTs "${BUNDLE}" init "${GROUP}" >/dev/null 2>&1
  mkdir -p "${GROUP}/tasks/T-1/repo"
  printf '# T-1\n' >"${GROUP}/tasks/T-1/notes.md"
  printf 'gitdir: %s/.bares/repo.git/worktrees/repo\n' "${GROUP}" >"${GROUP}/tasks/T-1/repo/.git"   # worktree 는 .git 이 파일이다

  runTs "${SANDBOX}" init "${SOLO}" >/dev/null 2>&1
}

# ---------------------------------------------------------------- 선언이 없으면 2.11.0 과 같다

testNoDeclaration() {
  local out rc

  out="$(runTs "${GROUP}" check 2>&1)"; rc=$?
  check "선언 없음 · 깨끗한 워크스페이스 → 출력 없음" "" "${out}"
  check "선언 없음 → 종료코드 0" "0" "${rc}"

  mv "${GROUP}/tasks/CLAUDE.md" "${SANDBOX}/CLAUDE.md.keep"
  out="$(runTs "${GROUP}" check 2>&1)"
  check "선언 없음 · upgrade 사유 → 기존 문구 한 줄" "$(upgradeLine "${GROUP}" "tasks/CLAUDE.md 가 없거나 구버전")" "${out}"
  mv "${SANDBOX}/CLAUDE.md.keep" "${GROUP}/tasks/CLAUDE.md"

  out="$(runTs "${SANDBOX}" check 2>&1)"; rc=$?
  check "워크스페이스 밖 cwd → 출력 없음" "" "${out}"
  check "워크스페이스 밖 cwd → 종료코드 0" "0" "${rc}"

  mkdir -p "${SANDBOX}/notws"
  printf 'x\n' >"${SANDBOX}/notws/repos.txt"
  printf 'plugin missing@m\n' >"${SANDBOX}/notws/requires.txt"
  out="$(runTs "${SANDBOX}/notws" check 2>&1)"
  check "tasks/ 없는 루트 (repos.txt 만 있는 다른 프로젝트) → 출력 없음" "" "${out}"

  out="$(runTs "${GROUP}" requires 2>&1)"; rc=$?
  checkContains "선언 없음 · requires → 없다고 알림" "선언 파일 (requires.txt) 이 없습니다" "${out}"
  check "선언 없음 · requires → 종료코드 0" "0" "${rc}"
}

# ---------------------------------------------------------------- 없거나 낮으면 안내, 다 갖추면 조용

testPlugins() {
  local out

  printf 'plugin missing@m 1.0.0\n' >"${DECLARED}"
  out="$(runTs "${GROUP}" check 2>&1)"
  check "미설치 → 설치 명령" "$(requiresLine "${GROUP}" "${DECLARED}" "missing@m 미설치 → claude plugin install missing@m")" "${out}"

  printf 'plugin old@m 1.10.0\n' >"${DECLARED}"
  out="$(runTs "${GROUP}" check 2>&1)"
  check "1.9.0 < 1.10.0 → 갱신 명령" \
    "$(requiresLine "${GROUP}" "${DECLARED}" "old@m 1.9.0 < 1.10.0 → claude plugin marketplace update m && claude plugin update old@m")" "${out}"

  printf 'plugin old@m 1.9.0\nplugin short@m 2.0.0\nplugin zero@m 1.08.0\nplugin multi@m 1.2.0\nplugin on@m\nplugin old@m v1.9\n' >"${DECLARED}"
  out="$(runTs "${GROUP}" check 2>&1)"
  check "같은 버전 · 2.0 = 2.0.0 · 1.08.0 = 1.8.0 · 여러 설치 중 높은 것 · 버전 없이 선언 · v 접두 → 조용" "" "${out}"

  printf 'plugin short@m 2.0.1\nplugin zero@m 1.09\n' >"${DECLARED}"
  out="$(runTs "${GROUP}" check 2>&1)"
  checkContains "2.0 < 2.0.1 → 안내" "short@m 2.0 < 2.0.1" "${out}"
  checkContains "1.8.0 < 1.09 → 안내 (08 · 09 자리에서 죽지 않음)" "zero@m 1.8.0 < 1.09" "${out}"

  printf 'plugin odd@m 1.0.0\n' >"${DECLARED}"
  out="$(runTs "${GROUP}" check 2>&1)"
  check "설치 버전이 숫자가 아님 → 세션 시작 때는 조용 (없앨 수 없는 사유)" "" "${out}"
  out="$(runTs "${GROUP}" requires 2>&1)"
  checkContains "설치 버전이 숫자가 아님 → 목록에는 표시" "버전 비교 불가" "${out}"

  printf 'plugin odd@m\n' >"${DECLARED}"
  out="$(runTs "${GROUP}" requires 2>&1)"
  checkContains "최소 버전 없음 + 설치 버전이 숫자가 아님 (커밋 해시) → ok" " ok" "$(grep -F 'odd@m' <<<"${out}")"
  checkLacks "최소 버전 없음 + 설치 버전이 숫자가 아님 → 버전 비교 불가가 아님" "버전 비교 불가" "${out}"

  printf 'plugin other@m\n' >"${DECLARED}"
  out="$(runTs "${GROUP}" check 2>&1)"
  checkContains "다른 프로젝트 범위로만 설치 → 미설치" "other@m 미설치" "${out}"

  # 판정 결과를 줄 순서로 맞추므로, 종류와 상태가 섞여도 각 줄이 제 결과를 받아야 한다
  printf 'plugin missing@m\npath ~/nothing-here\nplugin on@m 1.0.0\nbroken line\nplugin -x@m\nplugin old@m 2.0.0\nplugin old@m 1.0.0\npath /\nplugin gone@m optional\nplugin short@m 3\n' >"${DECLARED}"
  out="$(runTs "${GROUP}" check 2>&1)"
  check "미설치 · ok · 낮음 · 중복 · optional 이 path · 알 수 없는 줄과 섞임 → 줄마다 제 결과" \
    "$(requiresLine "${GROUP}" "${DECLARED}" "missing@m 미설치 → claude plugin install missing@m; ~/nothing-here 없음; old@m 1.9.0 < 2.0.0 → claude plugin marketplace update m && claude plugin update old@m; short@m 2.0 < 3 → claude plugin marketplace update m && claude plugin update short@m")" "${out}"
  out="$(runTs "${GROUP}" requires 2>&1)"
  check "- 로 시작하는 이름은 알 수 없는 줄이고 다른 줄의 판정을 끄지 않음" "2" "$(grep -c '알 수 없는 줄' <<<"${out}")"
  checkLacks "- 로 시작하는 이름이 있어도 판정 불가가 아님" "판정 불가" "${out}"

  printf 'plugin missing@m 1.0.0 optional\nplugin gone@m optional\n' >"${DECLARED}"
  out="$(runTs "${GROUP}" check 2>&1)"
  check "optional 만 빠짐 → 세션 시작 때는 조용" "" "${out}"
  out="$(runTs "${GROUP}" requires 2>&1)"
  checkContains "optional → 목록에는 나옴" "missing@m (optional)" "${out}"
  checkContains "optional · 버전 없이 선언 → 목록에 미설치" "미설치 → claude plugin install gone@m" "${out}"
}

testPaths() {
  local out command

  printf 'path ~/.config/tool/policy -- mkdir -p ~/.config/tool && ln -sfn "{dir}/policy/file" ~/.config/tool/policy\n' >"${DECLARED}"
  mkdir -p "${BUNDLE}/policy"
  printf 'policy\n' >"${BUNDLE}/policy/file"
  command="mkdir -p ~/.config/tool && ln -sfn \"${BUNDLE}/policy/file\" ~/.config/tool/policy"

  out="$(runTs "${GROUP}" check 2>&1)"
  check "경로 없음 (상위 폴더도 없음) → {dir} 이 바뀐 안내문" "$(requiresLine "${GROUP}" "${DECLARED}" "~/.config/tool/policy 없음 → ${command}")" "${out}"

  HOME="${FAKE_HOME}" /bin/bash -c "${command}"
  out="$(runTs "${GROUP}" check 2>&1)"
  check "안내된 명령을 실행한 뒤 → 조용 (상위 폴더 없음에서 출발)" "" "${out}"

  ln -sfn "${SANDBOX}/does-not-exist" "${FAKE_HOME}/.config/tool/policy"
  out="$(runTs "${GROUP}" check 2>&1)"
  checkContains "끊긴 심링크 → 없음으로 안내" "~/.config/tool/policy 없음" "${out}"

  HOME="${FAKE_HOME}" /bin/bash -c "${command}"
  out="$(runTs "${GROUP}" check 2>&1)"
  check "안내된 명령을 실행한 뒤 → 조용 (끊긴 심링크에서 출발)" "" "${out}"

  printf 'path $HOME/.config/tool/policy\npath %s\n' "${BUNDLE}/policy/file" >"${DECLARED}"
  out="$(runTs "${GROUP}" check 2>&1)"
  check "\$HOME/ 표기 · 절대 경로 · 안내문 없는 줄 → 있으면 조용" "" "${out}"

  printf 'path ~/nothing-here\npath ~/also-nothing optional -- 선택 안내\n' >"${DECLARED}"
  out="$(runTs "${GROUP}" check 2>&1)"
  check "안내문 없는 경로 · optional 경로" "$(requiresLine "${GROUP}" "${DECLARED}" "~/nothing-here 없음")" "${out}"
  out="$(runTs "${GROUP}" requires 2>&1)"
  checkContains "optional 경로 → 목록에 안내문과 함께" "없음 → 선택 안내" "${out}"

  rm -rf "${FAKE_HOME}/.config"
}

testCombined() {
  local out

  printf 'plugin missing@m\n' >"${DECLARED}"
  mv "${GROUP}/tasks/CLAUDE.md" "${SANDBOX}/CLAUDE.md.keep"

  out="$(runTs "${GROUP}" check 2>&1)"
  check "upgrade 사유 + 요구 미충족 → 두 줄 (upgrade 가 먼저)" \
    "$(upgradeLine "${GROUP}" "tasks/CLAUDE.md 가 없거나 구버전")
$(requiresLine "${GROUP}" "${DECLARED}" "missing@m 미설치 → claude plugin install missing@m")" "${out}"

  mv "${INSTALLED}" "${INSTALLED}.keep"
  printf '{ broken' >"${INSTALLED}"
  out="$(runTs "${GROUP}" check 2>&1)"
  check "upgrade 사유 + 깨진 설치 기록 → upgrade 줄은 그대로" "$(upgradeLine "${GROUP}" "tasks/CLAUDE.md 가 없거나 구버전")" "${out}"
  mv "${INSTALLED}.keep" "${INSTALLED}"

  mv "${SANDBOX}/CLAUDE.md.keep" "${GROUP}/tasks/CLAUDE.md"
}

testSkip() {
  local out

  printf 'plugin missing@m\npath ~/nothing-here\n' >"${DECLARED}"

  out="$(TEST_SKIP="missing@m" runTs "${GROUP}" check 2>&1)"
  check "대상 하나를 끔 → 나머지만 안내" "$(requiresLine "${GROUP}" "${DECLARED}" "~/nothing-here 없음")" "${out}"

  out="$(TEST_SKIP="missing@m ~/nothing-here" runTs "${GROUP}" check 2>&1)"
  check "대상 둘을 끔 (경로는 선언에 적힌 글자 그대로) → 조용" "" "${out}"

  out="$(TEST_SKIP="all" runTs "${GROUP}" check 2>&1)"
  check "all → 조용" "" "${out}"

  out="$(TEST_SKIP="$(printf 'missing@m\t~/nothing-here')" runTs "${GROUP}" check 2>&1)"
  check "탭으로 나눈 대상 → 조용" "" "${out}"

  out="$(TEST_SKIP="missing@m" runTs "${GROUP}" requires 2>&1)"
  checkContains "끈 대상 → 목록에 건너뜀" "건너뜀 (TASKSPACE_REQUIRES_SKIP)" "${out}"
}

# ---------------------------------------------------------------- 어디서 열어도 같은 선언

testLocations() {
  local out expected

  printf 'plugin missing@m\n' >"${DECLARED}"
  expected="$(requiresLine "${GROUP}" "${DECLARED}" "missing@m 미설치 → claude plugin install missing@m")"

  out="$(runTs "${GROUP}" check 2>&1)"
  check "그룹 루트 → 꼭대기 선언" "${expected}" "${out}"
  out="$(runTs "${GROUP}/tasks/T-1" check 2>&1)"
  check "태스크 루트 → 같은 안내" "${expected}" "${out}"
  out="$(runTs "${GROUP}/tasks/T-1/repo" check 2>&1)"
  check "worktree (별도 git repo 안) → 같은 안내" "${expected}" "${out}"

  out="$(cd "${GROUP}/tasks/T-1" && env HOME="${FAKE_HOME}" CLAUDE_CONFIG_DIR="${FAKE_CONFIG}" PATH="${FAKE_BIN}:/usr/bin:/bin" \
    TASKSPACE_ROOT="${GROUP}" /bin/bash "${TS}" check 2>&1)"
  check "TASKSPACE_ROOT 로 지정한 루트 → 같은 안내" "${expected}" "${out}"

  ln -s "${GROUP}" "${SANDBOX}/link"
  out="$(runTs "${SANDBOX}/link" check 2>&1)"
  check "심링크로 들어온 루트 → 실제 경로로 올라가 꼭대기 선언" \
    "$(requiresLine "${SANDBOX}/link" "${DECLARED}" "missing@m 미설치 → claude plugin install missing@m")" "${out}"
  rm "${SANDBOX}/link"

  printf 'plugin near@m\n' >"${GROUP}/requires.txt"
  out="$(runTs "${GROUP}/tasks/T-1" check 2>&1)"
  check "그룹에 선언이 있으면 그것만 (합치지 않음)" \
    "$(requiresLine "${GROUP}" "${GROUP}/requires.txt" "near@m 미설치 → claude plugin install near@m")" "${out}"

  : >"${GROUP}/requires.txt"
  out="$(runTs "${GROUP}" check 2>&1)"
  check "그룹의 빈 선언 → 꼭대기 선언을 가림 (조용)" "" "${out}"
  rm "${GROUP}/requires.txt"

  printf 'plugin missing@m\n' >"${SOLO}/requires.txt"
  out="$(runTs "${SOLO}" check 2>&1)"
  check "단독 워크스페이스 → 루트의 선언" "$(requiresLine "${SOLO}" "${SOLO}/requires.txt" "missing@m 미설치 → claude plugin install missing@m")" "${out}"
  rm "${SOLO}/requires.txt"

  # git repo 밖의 루트는 상위 폴더의 선언을 줍지 않는다
  mkdir -p "${SANDBOX}/loose/ws/.bares" "${SANDBOX}/loose/ws/tasks"
  printf 'plugin missing@m\n' >"${SANDBOX}/loose/requires.txt"
  out="$(runTs "${SANDBOX}/loose/ws" check 2>&1)"
  checkLacks "git repo 밖 루트 → 상위 폴더의 선언을 읽지 않음" "missing@m" "${out}"
  printf 'plugin missing@m\n' >"${SANDBOX}/loose/ws/requires.txt"
  out="$(runTs "${SANDBOX}/loose/ws" check 2>&1)"
  checkContains "git repo 밖 루트 → 루트의 선언은 읽음" "missing@m 미설치" "${out}"
}

# ---------------------------------------------------------------- 선언 파일의 글은 셸로 평가하지 않는다

testNoEvaluation() {
  local out long path200 index

  {
    printf 'plugin bad$(touch %s)@m\n' "${MARKER}"
    printf 'plugin ok@m;touch_%s\n' "x"
    printf 'plugin ver@m latest\n'
    printf 'plugin ver@m 1.0.0 required\n'
    printf 'path ~/$(pwd)*/x -- `touch %s` ; $(touch %s) ; $PATH * {dir}\n' "${MARKER}" "${MARKER}"
    printf 'path ~/ctl\033x/y\n'
    printf 'path ~/has space/x -- 공백 든 경로\n'
    printf 'path relative/path\n'
    printf 'unknown-kind something\n'
  } >"${DECLARED}"

  out="$(runTs "${GROUP}" check 2>&1)"
  check "명령 치환 · 백틱 · ; · \$PATH · * 는 글자 그대로 나오고 {dir} 만 바뀜" \
    "$(requiresLine "${GROUP}" "${DECLARED}" "~/\$(pwd)*/x 없음 → \`touch ${MARKER}\` ; \$(touch ${MARKER}) ; \$PATH * ${BUNDLE}")" "${out}"
  check "평가됐다면 생겼을 파일이 없음" "없음" "$([[ -e "${MARKER}" ]] && echo 있음 || echo 없음)"

  out="$(runTs "${GROUP}" requires 2>&1)"
  check "형식에 맞지 않는 줄 8개 (제어 문자 든 경로 포함) → 알 수 없는 줄" "8" "$(grep -c '알 수 없는 줄' <<<"${out}")"
  check "requires 뒤에도 평가 흔적 없음" "없음" "$([[ -e "${MARKER}" ]] && echo 있음 || echo 없음)"

  long="$(printf 'x%.0s' $(seq 1 301))"
  printf 'path ~/nothing-here -- %s\n' "${long}" >"${DECLARED}"
  out="$(runTs "${GROUP}" check 2>&1)"
  checkContains "300자를 넘는 안내문 → 자르지 않고 생략" "~/nothing-here 없음 → (안내문이 길어 생략 — 선언 파일 참고)" "${out}"
  checkLacks "300자를 넘는 안내문 → 원문이 나가지 않음" "xxxxxxxxxx" "${out}"

  path200="/$(printf 'p%.0s' $(seq 1 200))"
  printf 'path %s\n' "${path200}" >"${DECLARED}"
  out="$(runTs "${GROUP}" check 2>&1)"
  check "200자를 넘는 경로 → 알 수 없는 줄 (세션 시작 때는 조용)" "" "${out}"

  : >"${DECLARED}"
  for index in $(seq 1 13); do
    printf 'plugin absent%s@m\n' "${index}" >>"${DECLARED}"
  done
  out="$(runTs "${GROUP}" check 2>&1)"
  checkContains "항목 13개 → 10개까지만" "absent10@m 미설치 → claude plugin install absent10@m; 외 3건" "${out}"
  checkLacks "항목 13개 → 11번째는 나가지 않음" "absent11@m" "${out}"
}

# ---------------------------------------------------------------- 읽기 전용 · 망가진 환경 · 시간

testReadOnly() {
  local before after

  printf 'plugin missing@m\nplugin off@m\npath ~/nothing-here -- 안내\n' >"${DECLARED}"
  before="$(treeHash "${SANDBOX}")"
  runTs "${GROUP}/tasks/T-1" check >/dev/null 2>&1
  runTs "${GROUP}/tasks/T-1" requires >/dev/null 2>&1
  after="$(treeHash "${SANDBOX}")"
  check "check · requires 뒤 파일 목록·내용이 그대로" "${before}" "${after}"
}

testDisabled() {
  local out rc

  printf 'plugin on@m\nplugin off@m\n' >"${DECLARED}"

  out="$(runTs "${GROUP}" check 2>&1)"
  check "꺼진 플러그인 → 세션 시작 때는 조용 (설치 기록만 본다)" "" "${out}"

  out="$(runTs "${GROUP}" requires 2>&1)"
  checkContains "꺼진 플러그인 → 목록에 꺼짐" "꺼짐 → claude plugin enable off@m" "${out}"
  check "켜진 플러그인 → 목록에 ok" "1" "$(grep -c 'on@m .* ok$' <<<"${out}")"

  out="$(FAKE_CLAUDE_MODE=fail runTs "${GROUP}" requires 2>&1)"; rc=$?
  checkLacks "claude 실패 → 꺼짐 판정만 건너뜀" "꺼짐" "${out}"
  check "claude 실패 → 종료코드 0" "0" "${rc}"

  out="$(FAKE_CLAUDE_MODE=empty runTs "${GROUP}" requires 2>&1)"; rc=$?
  checkLacks "claude 빈 출력 → 꺼짐 판정만 건너뜀" "꺼짐" "${out}"
  check "claude 빈 출력 → 종료코드 0" "0" "${rc}"
}

testBrokenEnvironment() {
  local out rc pathOnly

  printf 'plugin missing@m\npath ~/nothing-here\n' >"${DECLARED}"
  pathOnly="$(requiresLine "${GROUP}" "${DECLARED}" "~/nothing-here 없음")"

  out="$(TEST_PATH="${NOJQ_BIN}" runTs "${GROUP}" check 2>&1)"; rc=$?
  check "jq 없음 → plugin 줄은 건너뛰고 path 줄만" "${pathOnly}" "${out}"
  check "jq 없음 → 종료코드 0" "0" "${rc}"
  out="$(TEST_PATH="${NOJQ_BIN}" runTs "${GROUP}" requires 2>&1)"
  checkContains "jq 없음 → 목록에 이유" "판정 불가 (jq 없음)" "${out}"

  mv "${INSTALLED}" "${INSTALLED}.keep"

  out="$(runTs "${GROUP}" check 2>&1)"; rc=$?
  check "설치 기록 없음 → plugin 줄은 건너뛰고 path 줄만 (전부 미설치로 보지 않음)" "${pathOnly}" "${out}"
  check "설치 기록 없음 → 종료코드 0" "0" "${rc}"
  out="$(runTs "${GROUP}" requires 2>&1)"
  checkContains "설치 기록 없음 → 목록에 이유" "판정 불가 (설치 기록 없음)" "${out}"

  printf '{ broken' >"${INSTALLED}"
  out="$(runTs "${GROUP}" check 2>&1)"; rc=$?
  check "깨진 JSON → plugin 줄은 건너뛰고 path 줄만" "${pathOnly}" "${out}"
  check "깨진 JSON → 종료코드 0" "0" "${rc}"
  out="$(runTs "${GROUP}" requires 2>&1)"
  checkContains "깨진 JSON → 목록에 이유" "판정 불가 (설치 기록을 읽을 수 없음)" "${out}"

  printf '[]' >"${INSTALLED}"
  out="$(runTs "${GROUP}" check 2>&1)"; rc=$?
  check "설치 기록이 객체가 아님 → plugin 줄은 건너뜀" "${pathOnly}" "${out}"

  : >"${INSTALLED}"
  out="$(runTs "${GROUP}" requires 2>&1)"
  check "0바이트 설치 기록 → plugin 줄 전부 판정 불가" "1" "$(grep -c '판정 불가 (설치 기록을 읽을 수 없음)' <<<"${out}")"
  checkLacks "0바이트 설치 기록 → 알 수 없는 줄로 나오지 않음" "알 수 없는 줄" "${out}"

  printf '{"plugins": {"missing@m": [{"version": "1.0.0"}]}}\n{"plugins": {}}\n' >"${INSTALLED}"
  out="$(runTs "${GROUP}" check 2>&1)"
  check "JSON 문서가 둘 이어진 설치 기록 → plugin 줄은 건너뜀 (줄 수가 어긋남)" "${pathOnly}" "${out}"

  printf '{"plugins": {"missing@m": "x", "odd@m": ["str", 3], "on@m": [{"version": "1.0.0"}]}}' >"${INSTALLED}"
  printf 'plugin missing@m\nplugin odd@m\nplugin on@m 1.0.0\n' >"${DECLARED}"
  out="$(runTs "${GROUP}" check 2>&1)"
  check "설치 기록의 이상한 항목 → 그 플러그인만 미설치, 나머지는 판정" \
    "$(requiresLine "${GROUP}" "${DECLARED}" "missing@m 미설치 → claude plugin install missing@m; odd@m 미설치 → claude plugin install odd@m")" "${out}"
  printf 'plugin missing@m\npath ~/nothing-here\n' >"${DECLARED}"

  rm -f "${INSTALLED}"
  mv "${INSTALLED}.keep" "${INSTALLED}"

  printf 'plugin missing@m\r\npath ~/nothing-here -- 안내\r\n' >"${DECLARED}"
  out="$(runTs "${GROUP}" check 2>&1)"
  check "CRLF 줄 끝 → CR 없이 읽음" \
    "$(requiresLine "${GROUP}" "${DECLARED}" "missing@m 미설치 → claude plugin install missing@m; ~/nothing-here 없음 → 안내")" "${out}"

  printf '\357\273\277plugin missing@m\n' >"${DECLARED}"
  out="$(runTs "${GROUP}" check 2>&1)"
  checkContains "UTF-8 BOM 으로 시작하는 파일 → 첫 줄도 읽음" "missing@m 미설치" "${out}"

  printf '# 주석\n\n   \nplugin on@m\n\tplugin\tmissing@m\t1.0.0' >"${DECLARED}"
  out="$(runTs "${GROUP}" check 2>&1)"
  checkContains "끝 개행 없는 마지막 줄 · 탭 구분 · 주석 · 빈 줄" "missing@m 미설치 → claude plugin install missing@m" "${out}"

  : >"${DECLARED}"
  out="$(runTs "${GROUP}" check 2>&1)"; rc=$?
  check "빈 선언 파일 → 조용" "" "${out}"
  check "빈 선언 파일 → 종료코드 0" "0" "${rc}"
  out="$(runTs "${GROUP}" requires 2>&1)"; rc=$?
  check "빈 선언 파일 · requires → 종료코드 0" "0" "${rc}"
}

testSpeed() {
  local index started elapsed out

  : >"${DECLARED}"
  for index in $(seq 1 199); do
    printf '# 주석 %s\n' "${index}" >>"${DECLARED}"
  done
  printf 'plugin missing@m\nplugin beyond@m\n' >>"${DECLARED}"
  out="$(runTs "${GROUP}" check 2>&1)"
  checkContains "200번째 줄까지 읽음" "missing@m 미설치" "${out}"
  checkLacks "201번째 줄부터는 읽지 않음" "beyond@m" "${out}"

  : >"${DECLARED}"
  for index in $(seq 1 199); do
    printf '%20000s\n' "" >>"${DECLARED}"
  done
  printf 'plugin missing@m\n' >>"${DECLARED}"
  started="$(date +%s)"
  out="$(runTs "${GROUP}" check 2>&1)"
  elapsed=$(( $(date +%s) - started ))
  checkContains "공백만 2만 자인 줄 199개 뒤의 줄도 읽음" "missing@m 미설치" "${out}"
  check "공백만 2만 자인 줄 199개 · check 가 2초 안" "통과" "$([[ "${elapsed}" -lt 2 ]] && echo 통과 || echo "${elapsed}초")"

  : >"${DECLARED}"
  for index in $(seq 1 25); do
    printf 'plugin absent%s@m 1.0.0\npath ~/nothing-%s -- 안내 %s\n' "${index}" "${index}" "${index}" >>"${DECLARED}"
  done

  started="$(date +%s)"
  runTs "${GROUP}/tasks/T-1" check >/dev/null 2>&1
  elapsed=$(( $(date +%s) - started ))
  check "선언 50줄 · check 가 2초 안 (훅 제한 5초)" "통과" "$([[ "${elapsed}" -lt 2 ]] && echo 통과 || echo "${elapsed}초")"
}

setUp
testNoDeclaration
testPlugins
testPaths
testCombined
testSkip
testLocations
testNoEvaluation
testReadOnly
testDisabled
testBrokenEnvironment
testSpeed
rm -f "${DECLARED}"

echo
echo "검사 ${checks}건 · 실패 ${failures}건"
[[ "${failures}" -eq 0 ]]
