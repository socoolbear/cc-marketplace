#!/usr/bin/env bash
# AGENTS.md 「검증 명령」 다섯 가지를 한 번에 돈다. 로컬과 GitHub Actions 가 같이 쓴다.
set -euo pipefail

cd "$(dirname "$0")/.."

failures=0

fail() {
  echo "FAIL $*"
  failures=$((failures + 1))
}

echo "== 매니페스트 JSON 파싱"
for manifest in .claude-plugin/marketplace.json plugins/*/.claude-plugin/plugin.json; do
  python3 -m json.tool "${manifest}" >/dev/null || fail "JSON ${manifest}"
done

echo "== 버전 일치"
python3 - <<'PY' || fail "버전 일치"
import glob, json, sys

listed = {entry["name"]: entry.get("version") for entry in json.load(open(".claude-plugin/marketplace.json"))["plugins"]}
plugin_dirs = {path.split("/")[1] for path in glob.glob("plugins/*/.claude-plugin/plugin.json")}
problems = [f"목록과 폴더가 다름: {name}" for name in sorted(set(listed) ^ plugin_dirs)]

for name in sorted(plugin_dirs & set(listed)):
    version = json.load(open(f"plugins/{name}/.claude-plugin/plugin.json")).get("version")
    if version != listed[name]:
        problems.append(f"{name}: plugin.json {version} != marketplace.json {listed[name]}")

for problem in problems:
    print(problem)

sys.exit(1 if problems else 0)
PY

echo "== 스킬 내부 링크 실재"
python3 - <<'PY' || fail "스킬 내부 링크"
import glob, os, re, sys

link_pattern = re.compile(r"\]\(([^)\s]+)\)")
documents = glob.glob("plugins/*/skills/*/**/*.md", recursive=True) + glob.glob(".claude/skills/*/**/*.md", recursive=True)
broken = []

for document in documents:
    for target in link_pattern.findall(open(document, encoding="utf-8").read()):
        if re.match(r"^(https?:|mailto:|#|/|<)", target):
            continue

        path = os.path.normpath(os.path.join(os.path.dirname(document), target.split("#")[0]))

        if not os.path.exists(path):
            broken.append(f"{document} → {target}")

for item in broken:
    print(item)

sys.exit(1 if broken else 0)
PY

echo "== 임시 폴더 지우기 보호"
# mktemp 로 만든 경로를 rm -r 하는 셸 파일은 mktemp 실패를 막아야 한다. 막지 않으면 빈 값이 되어
# 지금 폴더 (저장소) 를 지운다 (2026-11-21 시험 스크립트에서 실제 발생). 통과 조건 중 하나:
#   ⓐ 대입 줄에 || 실패 처리  ⓑ 다음 3줄 안에 -n/-z "${X}" 또는 ${X:?} 검사  ⓒ set -e 파일의 단순 대입 X=$(mktemp …)
# 한계: rm 줄에 직접 나온 변수만 본다. 파생 변수 (ROOT="${X}/…") 를 지우는 줄은 추적하지 않는다.
python3 - <<'PY' || fail "임시 폴더 지우기 보호"
import re, subprocess, sys

tracked = subprocess.run(["git", "ls-files"], capture_output=True, text=True).stdout.split()
rm_pattern = re.compile(r"\brm\s+-[A-Za-z]*r[A-Za-z]*\b(.*)")
variable_pattern = re.compile(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)")
problems = []


def is_shell(path):
    if path.endswith(".sh"):
        return True

    if "/bin/" not in path and "/hooks/" not in path:
        return False

    try:
        return re.match(r"#!.*\b(ba|z)?sh\b", open(path, encoding="utf-8").readline()) is not None
    except (OSError, UnicodeDecodeError):
        return False


def is_guarded(lines, index, name, strict_errexit):
    assignment = lines[index]

    if "||" in assignment:
        return True

    check = re.compile(r"-[nz]\s+\"?\$\{?" + name + r"\}?\"?|\$\{" + name + r":\?")

    if any(check.search(line) for line in lines[index + 1:index + 4]):
        return True

    simple = re.compile(r"\b" + name + r"=\"?\$\(mktemp[^()]*\)\"?\s*(#.*)?$")

    return strict_errexit and simple.search(assignment.strip()) is not None


for path in filter(is_shell, tracked):
    try:
        lines = open(path, encoding="utf-8").read().splitlines()
    except (OSError, UnicodeDecodeError):
        continue

    strict_errexit = any(re.match(r"\s*set\s+-[a-z]*e", line) for line in lines)
    removed = {name for line in lines for match in rm_pattern.finditer(line) for name in variable_pattern.findall(match.group(1))}

    for name in sorted(removed):
        for index, line in enumerate(lines):
            if re.search(r"\b" + name + r"=", line) and "mktemp" in line and not is_guarded(lines, index, name, strict_errexit):
                problems.append(f"{path}:{index + 1}: {name} 를 mktemp 로 만들고 rm -r 하는데 실패 처리가 없다")

for problem in problems:
    print(problem)

sys.exit(1 if problems else 0)
PY

echo "== 플러그인 시험"
for suite in plugins/*/tests/run.sh; do
  if ! output="$(bash "${suite}" 2>&1)"; then
    echo "${output}" | tail -40
    fail "시험 ${suite}"
  fi
done

if [[ "${failures}" -gt 0 ]]; then
  echo "실패 ${failures}건"
  exit 1
fi

echo "모두 통과"
