#!/usr/bin/env python3
"""플러그인별 최근 N일 사용 세션 수를 대화 기록에서 센다 (evolve sweep 의 사용 흔적 점검).

스킬 호출 ("skill":"<이름>") 과 슬래시 명령 (<command-name>/<이름></command-name>) 을 따로 센다.
한쪽만 세면 슬래시로만 부르는 플러그인이 0 으로 보인다.
이름만 친 슬래시 (/handoff) 도 합계에 넣는다 — 내장 명령과 이름이 같으면 (/resume) 부풀 수 있으니 그 열을 보고 걸러 읽는다.
훅은 대화 기록에 호출로 남지 않으므로 훅이 있는 플러그인은 켜짐 여부를 함께 보여 준다.

사용법: usage.py [일수=30] [--projects ~/.claude/projects] [--settings ~/.claude/settings.json]
"""
import argparse
import glob
import json
import os
import re
import time

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../../.."))
SKILL_PATTERN = re.compile(r'"skill":\s?"([^"]+)"')
COMMAND_PATTERN = re.compile(r"<command-name>/?([^<]+)</command-name>")


def read_skill_name(skill_md):
    match = re.search(r"^name:\s*(\S+)", open(skill_md, encoding="utf-8").read(), re.M)

    return match.group(1) if match else None


def collect_entry_names(plugin_dir):
    names = set()

    for skill_md in glob.glob(os.path.join(plugin_dir, "skills/*/SKILL.md")):
        names.add(os.path.basename(os.path.dirname(skill_md)))
        frontmatter_name = read_skill_name(skill_md)

        if frontmatter_name:
            names.add(frontmatter_name)

    for command_md in glob.glob(os.path.join(plugin_dir, "commands/*.md")):
        names.add(os.path.splitext(os.path.basename(command_md))[0])

    return names


def load_enabled_plugins(settings_path):
    try:
        return json.load(open(settings_path)).get("enabledPlugins", {})
    except (OSError, ValueError):
        return {}


def count_sessions(transcripts, plugin, entry_names):
    qualified = {f"{plugin}:{name}" for name in entry_names}
    counts = {"skill": 0, "slash": 0, "slash_bare": 0, "any": 0}

    for invoked_skills, invoked_commands in transcripts:
        used_skill = bool(invoked_skills & (qualified | entry_names))
        used_slash = bool(invoked_commands & qualified)
        used_bare = bool(invoked_commands & entry_names)
        counts["skill"] += used_skill
        counts["slash"] += used_slash
        counts["slash_bare"] += used_bare
        counts["any"] += used_skill or used_slash or used_bare

    return counts


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("days", nargs="?", type=int, default=30)
    parser.add_argument("--projects", default=os.path.expanduser("~/.claude/projects"))
    parser.add_argument("--settings", default=os.path.expanduser("~/.claude/settings.json"))
    args = parser.parse_args()

    since = time.time() - args.days * 86400
    transcripts = []

    # 서브에이전트 기록 (<세션>/subagents/*.jsonl) 은 부모 세션과 겹치므로 세지 않는다
    for path in glob.glob(os.path.join(args.projects, "*/*.jsonl")):
        if os.path.getmtime(path) < since:
            continue

        text = open(path, encoding="utf-8", errors="ignore").read()
        transcripts.append((set(SKILL_PATTERN.findall(text)), set(COMMAND_PATTERN.findall(text))))

    marketplace = json.load(open(os.path.join(REPO_ROOT, ".claude-plugin/marketplace.json")))
    enabled = load_enabled_plugins(args.settings)

    print(f"최근 {args.days}일 세션 {len(transcripts)}개 기준 (세션 수)")
    print("| 플러그인 | 스킬 호출 | 슬래시 (플러그인:이름) | 슬래시 (이름만 — 내장 명령과 겹칠 수 있음) | 합계 (이름만 포함) | 훅 | 켜짐 |")
    print("|---|---|---|---|---|---|---|")

    for entry in marketplace["plugins"]:
        plugin = entry["name"]
        plugin_dir = os.path.join(REPO_ROOT, entry["source"])
        counts = count_sessions(transcripts, plugin, collect_entry_names(plugin_dir))
        has_hooks = os.path.exists(os.path.join(plugin_dir, "hooks/hooks.json"))
        enabled_state = enabled.get(f"{plugin}@{marketplace['name']}")
        enabled_label = {True: "켜짐", False: "꺼짐"}.get(enabled_state, "목록에 없음")
        print(f"| {plugin} | {counts['skill']} | {counts['slash']} | {counts['slash_bare']} | {counts['any']} | {'있음' if has_hooks else '-'} | {enabled_label} |")


if __name__ == "__main__":
    main()
