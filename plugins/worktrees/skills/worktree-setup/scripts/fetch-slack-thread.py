#!/usr/bin/env python3
"""슬랙 쓰레드 원문을 사람이 읽을 수 있게 출력한다.

사용법:
    SLACK_TOKEN=xoxb-... python3 fetch-slack-thread.py <채널ID> <ts>

링크 .../archives/C0123ABCDEF/p1712345678901234 를 인자로 바꾸는 규칙:
    채널ID = archives/ 뒤의 C...
    ts     = p 뒤 숫자에서 앞 10자리 뒤에 소수점 -> 1712345678.901234

토큰은 SLACK_TOKEN 환경변수로 준다 (스레드 열람 권한이 있는 봇/유저 토큰).
표준 라이브러리만 사용한다.
"""

from __future__ import annotations

import json
import os
import sys
import urllib.parse
import urllib.request


def readToken() -> str:
    token = os.environ.get("SLACK_TOKEN")
    if token:
        return token

    sys.exit("SLACK_TOKEN 환경변수가 없습니다. 스레드 열람 권한이 있는 토큰을 export 하세요.")


def normalizeTs(raw: str) -> str:
    if "." in raw:
        return raw

    digits = raw.lstrip("p")
    if len(digits) <= 10:
        return digits

    return f"{digits[:10]}.{digits[10:]}"


def callSlack(token: str, method: str, params: dict) -> dict:
    url = f"https://slack.com/api/{method}?" + urllib.parse.urlencode(params)
    request = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})

    with urllib.request.urlopen(request) as response:
        return json.load(response)


def buildNameResolver(token: str):
    cache: dict[str, str] = {}

    def resolve(userId: str) -> str:
        if userId in cache:
            return cache[userId]

        try:
            result = callSlack(token, "users.info", {"user": userId})
            profile = result["user"]["profile"]
            cache[userId] = profile.get("display_name") or result["user"].get("real_name") or userId
        except Exception:
            cache[userId] = userId

        return cache[userId]

    return resolve


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit(__doc__)

    channel, ts = sys.argv[1], normalizeTs(sys.argv[2])
    token = readToken()

    result = callSlack(token, "conversations.replies", {"channel": channel, "ts": ts, "limit": 200})
    if not result.get("ok"):
        sys.exit(f"슬랙 API 오류: {result.get('error')}")

    resolveName = buildNameResolver(token)

    for message in result["messages"]:
        print("---")
        print(f"from: {resolveName(message.get('user', '?'))} | ts: {message.get('ts')}")
        print(message.get("text", ""))

        for file in message.get("files") or []:
            print("[file]", file.get("name"), file.get("permalink"))

        for attachment in message.get("attachments") or []:
            print("[attach]", attachment.get("title"), (attachment.get("text") or "")[:500])


if __name__ == "__main__":
    main()
