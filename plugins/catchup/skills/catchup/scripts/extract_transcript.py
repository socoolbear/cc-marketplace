#!/usr/bin/env python3
"""세션 transcript(jsonl)를 읽기 쉬운 마크다운 대화록으로 변환한다.

usage: extract_transcript.py <transcript.jsonl> [--out FILE]

- 메인 스레드만 담는다 (서브에이전트 sidechain 과 도구 결과는 제외)
- 어시스턴트의 도구 호출은 한 줄 요약으로 압축한다 (무엇을 만졌는지 추적용)
- 결과는 --out 파일 또는 stdout, 통계는 stderr
"""
import argparse
import json
import sys


def summarizeToolUse(block: dict) -> str:
    name = block.get("name", "?")
    toolInput = block.get("input") or {}

    detail = (
        toolInput.get("file_path")
        or toolInput.get("path")
        or toolInput.get("command")
        or toolInput.get("description")
        or toolInput.get("prompt")
        or toolInput.get("pattern")
        or ""
    )
    detail = str(detail).replace("\n", " ")[:160]

    return f"- [도구] {name}: {detail}" if detail else f"- [도구] {name}"


def extractText(content) -> str:
    if isinstance(content, str):
        return content.strip()

    if not isinstance(content, list):
        return ""

    parts = []

    for block in content:
        if not isinstance(block, dict):
            continue

        if block.get("type") == "text" and block.get("text", "").strip():
            parts.append(block["text"].strip())
        elif block.get("type") == "tool_use":
            parts.append(summarizeToolUse(block))

    return "\n".join(parts)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("transcript")
    parser.add_argument("--out")
    args = parser.parse_args()

    lines = []
    stats = {"user": 0, "assistant": 0, "summary": 0}
    lastRole = None

    with open(args.transcript, errors="replace") as f:
        for raw in f:
            try:
                record = json.loads(raw)
            except ValueError:
                continue

            if record.get("isSidechain"):
                continue

            recordType = record.get("type")

            if recordType == "summary":
                lines.append(f"\n## [이전 요약] {record.get('summary', '')}")
                stats["summary"] += 1
                continue

            if recordType not in ("user", "assistant") or record.get("isMeta"):
                continue

            text = extractText(record.get("message", {}).get("content"))

            if not text or text.startswith("<local-command") or text.startswith("[Request interrupted"):
                continue

            # 슬래시 명령 래퍼는 명령 이름만 남긴다
            if text.startswith("<command-name>"):
                command = text.split("</command-name>")[0].replace("<command-name>", "")
                text = f"(슬래시 명령 실행: {command})"

            timestamp = (record.get("timestamp") or "")[:16].replace("T", " ")

            if recordType != lastRole:
                header = "USER" if recordType == "user" else "ASSISTANT"
                lines.append(f"\n## {header} ({timestamp})")
                lastRole = recordType

            lines.append(text)
            stats[recordType] += 1

    output = "\n".join(lines).strip() + "\n"

    if args.out:
        with open(args.out, "w") as f:
            f.write(output)
    else:
        sys.stdout.write(output)

    print(
        f"user {stats['user']}개, assistant {stats['assistant']}개, "
        f"이전 요약 {stats['summary']}개, 총 {len(output):,} 자",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
