#!/usr/bin/env python3
"""현재 프로젝트의 Claude Code 세션 목록을 메타데이터와 함께 JSON Lines 로 출력한다.

usage: list_sessions.py [--cwd PATH] [--limit N] [--include-current]

출력 필드 (한 줄 = 세션 하나, 최근 활동순):
  id            세션 ID (파일명)
  name          세션 이름 (agent-name 레코드, 없으면 null)
  last_active   마지막 활동 시각 (ISO)
  size_kb       transcript 크기
  branch        마지막으로 기록된 git 브랜치
  user_msgs     실제 사용자 메시지 수 (메타·명령 제외)
  assistant_msgs어시스턴트 메시지 수 — 실질 작업량의 근사치
  first_prompt  첫 사용자 메시지 앞부분
  last_prompt   마지막 사용자 메시지 앞부분
"""
import argparse
import json
import os
import re
import sys
from pathlib import Path


def resolveProjectDir(cwd: str) -> Path:
    slug = re.sub(r"[^A-Za-z0-9]", "-", cwd)

    return Path.home() / ".claude" / "projects" / slug


def resolveCurrentSessionId():
    sock = os.environ.get("CLAUDE_CODE_MESSAGING_SOCKET", "")
    match = re.search(r"(\d+)\.sock$", sock)

    if not match:
        return None

    infoPath = Path.home() / ".claude" / "sessions" / f"{match.group(1)}.json"

    try:
        return json.loads(infoPath.read_text()).get("sessionId")
    except (OSError, ValueError):
        return None


def extractUserText(message: dict):
    content = message.get("content")

    if isinstance(content, str):
        text = content
    elif isinstance(content, list):
        parts = [b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text"]
        text = "\n".join(p for p in parts if p)
    else:
        return None

    text = text.strip()

    # 슬래시 명령 래퍼, 로컬 명령 출력, 인터럽트 알림 등은 실제 프롬프트가 아니다
    if not text or text.startswith("<") or text.startswith("[Request interrupted"):
        return None

    return text


def summarizeSession(path: Path) -> dict:
    name = None
    branch = None
    lastTimestamp = None
    firstPrompt = None
    lastPrompt = None
    userCount = 0
    assistantCount = 0

    with open(path, errors="replace") as f:
        for line in f:
            try:
                record = json.loads(line)
            except ValueError:
                continue

            recordType = record.get("type")

            if recordType == "agent-name":
                name = record.get("agentName") or name
                continue

            if record.get("isSidechain"):
                continue

            branch = record.get("gitBranch") or branch
            lastTimestamp = record.get("timestamp") or lastTimestamp

            if recordType == "assistant":
                assistantCount += 1
            elif recordType == "user" and not record.get("isMeta"):
                text = extractUserText(record.get("message", {}))

                if text:
                    userCount += 1
                    lastPrompt = text[:150]

                    if firstPrompt is None:
                        firstPrompt = text[:150]

    return {
        "id": path.stem,
        "name": name,
        "last_active": lastTimestamp,
        "size_kb": round(path.stat().st_size / 1024),
        "branch": branch,
        "user_msgs": userCount,
        "assistant_msgs": assistantCount,
        "first_prompt": firstPrompt,
        "last_prompt": lastPrompt,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cwd", default=os.getcwd())
    parser.add_argument("--limit", type=int, default=15)
    parser.add_argument("--include-current", action="store_true")
    args = parser.parse_args()

    projectDir = resolveProjectDir(args.cwd)

    if not projectDir.is_dir():
        print(f"transcript 디렉터리 없음: {projectDir}", file=sys.stderr)
        sys.exit(1)

    currentId = resolveCurrentSessionId()
    transcripts = sorted(projectDir.glob("*.jsonl"), key=lambda p: p.stat().st_mtime, reverse=True)

    printed = 0

    for path in transcripts:
        if printed >= args.limit:
            break

        if path.stem == currentId and not args.include_current:
            continue

        summary = summarizeSession(path)

        # 실제 대화가 전혀 없는 세션 (즉시 종료, /exit 만 친 세션) 은 후보가 아니다
        if summary["user_msgs"] == 0 and summary["assistant_msgs"] == 0:
            continue

        print(json.dumps(summary, ensure_ascii=False))
        printed += 1

    if printed == 0:
        print("이어받을 수 있는 이전 세션이 없습니다.", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
