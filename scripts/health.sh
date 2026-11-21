#!/usr/bin/env bash
# 저장소 상태 점검 — evolve sweep 이 먼저 돌리고, 사용자의 개인 설정 저장소 점검도 불러 쓴다.
# 기본은 정적 점검만 한다 (최근 CI 결과 · 지워진 이름 참조). 파일을 만들거나 지우지 않는다.
# --verify 를 주면 scripts/verify.sh (플러그인 시험 포함) 도 돈다 — 시험은 임시 폴더를 만들고 지우므로
# 다른 작업이 진행 중일 수 있는 체크아웃을 남이 점검할 때는 옵션 없이 부른다.
#
# 출력: [FAIL] 확실한 결함 / [WARN] 판단할 것 / [INFO] 판단 재료, 마지막 줄 "FAIL n건". FAIL 이 있으면 exit 1.
# set -e 를 쓰지 않는 이유: 점검 하나가 실패해도 나머지 점검을 끝까지 돌려야 한다.
set -uo pipefail

cd "$(dirname "$0")/.." || { echo "[FAIL] 저장소 루트로 이동하지 못함"; exit 1; }

fail_count=0

fail() { printf '[FAIL] %s\n' "$*"; fail_count=$(( fail_count + 1 )); }
warn() { printf '[WARN] %s\n' "$*"; }
info() { printf '[INFO] %s\n' "$*"; }

with_verify=false
[[ "${1:-}" == "--verify" ]] && with_verify=true

# --- 1. 최근 CI (GitHub Actions verify) ---
echo "## 1. CI"

if ! command -v gh >/dev/null 2>&1; then
  info "gh 없음 — CI 결과 확인 불가"
elif ! run=$(gh run list --workflow verify.yml --branch main -L 1 --json status,conclusion,headSha,url 2>/dev/null) || [[ "${run}" == "[]" || -z "${run}" ]]; then
  info "CI 결과 확인 불가 (gh 인증 · 네트워크 · 실행 기록 없음)"
else
  status=$(jq -r '.[0].status' <<< "${run}")
  conclusion=$(jq -r '.[0].conclusion' <<< "${run}")
  head_sha=$(jq -r '.[0].headSha' <<< "${run}")
  run_url=$(jq -r '.[0].url' <<< "${run}")

  if [[ "${status}" != completed ]]; then
    info "CI 진행 중 (${head_sha:0:7}) — ${run_url}"
  elif [[ "${conclusion}" != success ]]; then
    fail "최근 main CI 실패 (${head_sha:0:7}, ${conclusion}) — ${run_url}"
  fi

  remote_head=$(git rev-parse --verify -q origin/main 2>/dev/null)
  [[ -z "${remote_head}" || "${remote_head}" == "${head_sha}" ]] \
    || info "최근 CI 커밋 (${head_sha:0:7}) 이 로컬이 아는 origin/main (${remote_head:0:7}) 과 다름 — fetch 전이거나 CI 대기 중"
fi

# --- 2. 지워진 스킬 · 플러그인 이름을 가리키는 참조 ---
# 지워진 플러그인 = marketplace.json 이력에 있던 이름 − 지금 목록. 참조 꼴 (<이름>:<스킬>, <이름>@<마켓>, plugins/<이름>/) 만 본다 —
# 맨 단어로 찾으면 다른 뜻의 같은 단어 (폴더 이름 · man 페이지) 가 걸린다.
# 지금 있는 플러그인의 <플러그인>:<이름> 은 그 이름의 스킬 · 명령 · 에이전트가 있어야 한다.
# docs/evolution/ 과 CHANGELOG 는 지난 일을 적는 기록이라 보지 않는다.
echo "## 2. 지워진 이름 참조"

if [[ "$(git rev-parse --is-shallow-repository 2>/dev/null)" == true ]]; then
  info "얕은 clone — 지워진 플러그인 이름을 이력에서 구할 수 없어 확인 불가 (git fetch --unshallow)"
else
  historic_names=$(
    git log --format=%H -- .claude-plugin/marketplace.json | while read -r commit; do
      git show "${commit}:.claude-plugin/marketplace.json" 2>/dev/null | jq -r '.plugins[]?.name' 2>/dev/null
    done | sort -u
  )

  hits=$(HISTORIC_NAMES="${historic_names}" python3 - <<'PY'
import glob, json, os, re, subprocess

live = {entry["name"]: entry["source"] for entry in json.load(open(".claude-plugin/marketplace.json"))["plugins"]}
removed = sorted(set(os.environ["HISTORIC_NAMES"].split()) - set(live))


def entry_names(plugin_dir):
    names = set()

    for skill_md in glob.glob(os.path.join(plugin_dir, "skills/*/SKILL.md")):
        names.add(os.path.basename(os.path.dirname(skill_md)))
        match = re.search(r"^name:\s*(\S+)", open(skill_md, encoding="utf-8").read(), re.M)

        if match:
            names.add(match.group(1).strip("\"'"))

    for pattern in ("commands/*.md", "agents/*.md"):
        names.update(os.path.splitext(os.path.basename(path))[0] for path in glob.glob(os.path.join(plugin_dir, pattern)))

    return names


tracked = subprocess.run(["git", "ls-files", "plugins", "README.md", "AGENTS.md", "docs"], capture_output=True, text=True).stdout.split()
documents = [path for path in tracked if not path.startswith("docs/evolution/") and "CHANGELOG" not in path and os.path.isfile(path)]
before = r"(?<![A-Za-z0-9_./-])"
removed_patterns = [(name, re.compile(before + re.escape(name) + r"(?::[a-z]|@[a-z])|plugins/" + re.escape(name) + r"/")) for name in removed]
live_pattern = re.compile(before + r"(" + "|".join(re.escape(name) for name in live) + r"):([a-z][a-z0-9-]*)")
live_entries = {name: entry_names(source) for name, source in live.items()}

for path in documents:
    try:
        text = open(path, encoding="utf-8").read()
    except UnicodeDecodeError:
        continue

    for number, line in enumerate(text.splitlines(), 1):
        for name, pattern in removed_patterns:
            if pattern.search(line):
                print(f"지워진 플러그인 '{name}' 참조: {path}:{number}")

    # 지금 있는 플러그인 참조는 문서 (마크다운 · JSON) 에서만 본다. HTML 주석 (<!-- 이름:begin --> 같은 표지, 여러 줄 포함) 은 줄 수를 유지한 채 지운다
    if not path.endswith((".md", ".json")):
        continue

    uncommented = re.sub(r"<!--.*?-->", lambda comment: "\n" * comment.group(0).count("\n"), text, flags=re.S)

    for number, line in enumerate(uncommented.splitlines(), 1):
        for plugin, entry in live_pattern.findall(line):
            if entry not in live_entries[plugin]:
                print(f"없는 스킬·명령·에이전트 '{plugin}:{entry}' 참조: {path}:{number}")
PY
)

  while IFS= read -r hit; do
    [[ -n "${hit}" ]] && warn "${hit}"
  done <<< "${hits}"
fi

# --- 3. 검증 명령 (--verify 일 때만) ---
echo "## 3. 검증 명령"

if [[ "${with_verify}" != true ]]; then
  info "scripts/verify.sh 는 돌리지 않음 (--verify 로 실행 — 플러그인 시험이 임시 폴더를 만들고 지운다)"
elif ! verify_output=$(bash scripts/verify.sh 2>&1); then
  while IFS= read -r line; do
    fail "verify.sh: ${line#FAIL }"
  done < <(grep '^FAIL ' <<< "${verify_output}")
fi

echo
echo "FAIL ${fail_count}건"
(( fail_count == 0 ))
