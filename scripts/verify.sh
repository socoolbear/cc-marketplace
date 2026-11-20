#!/usr/bin/env bash
# AGENTS.md 「검증 명령」 네 가지를 한 번에 돈다. 로컬과 GitHub Actions 가 같이 쓴다.
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
