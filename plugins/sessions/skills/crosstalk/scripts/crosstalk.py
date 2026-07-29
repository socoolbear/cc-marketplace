#!/usr/bin/env python3
"""Claude Code 세션 간 메시징 (UDS SOCK_STREAM + Monitor 도구).

recv --name <이름>                          수신 리스너 (Monitor 가 실행)
send --from <이름> --to <이름> --text <텍스트>  메시지 전송 (--text 생략 시 stdin)
list                                        살아 있는 세션 목록 (stale 소켓 정리)
"""
import argparse
import atexit
import errno
import json
import os
import re
import signal
import socket
import sys
import tempfile
import time

BASE_DIR = os.path.expanduser("~/.claude/crosstalk")
SPOOL_DIR = os.path.join(BASE_DIR, "spool")

INLINE_CHARS = 600
PREVIEW_CHARS = 300
READ_LIMIT = 1024 * 1024
SPOOL_TTL_SECONDS = 7 * 86400
NAME_SUFFIX_MAX = 9


def ensure_dirs():
    os.makedirs(BASE_DIR, mode=0o700, exist_ok=True)
    os.makedirs(SPOOL_DIR, mode=0o700, exist_ok=True)
    os.chmod(BASE_DIR, 0o700)


def sock_path(name):
    return os.path.join(BASE_DIR, f"{name}.sock")


def meta_path(name):
    return os.path.join(BASE_DIR, f"{name}.meta")


def probe_alive(path):
    """소켓에 연결을 시도해 수신자가 살아 있는지 판별한다."""
    probe = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    probe.settimeout(1)

    try:
        probe.connect(path)
        return True
    except OSError:
        return False
    finally:
        probe.close()


def sanitize_name(raw):
    """이름을 안전한 문자 (영숫자 · - _ .) 로 제한한다."""
    name = re.sub(r"[^\w.-]", "_", raw)[:60]

    if not name:
        sys.exit("오류: 사용할 수 없는 세션 이름입니다.")

    return name


def escape_line(text):
    """개행·제어문자를 이스케이프해 한 메시지 = stdout 한 줄을 보장한다 (라인 위조 방어)."""
    escaped = []

    for ch in text:
        if ch == "\n":
            escaped.append("\\n")
        elif ch == "\r":
            escaped.append("\\r")
        elif ch == "\t":
            escaped.append("\\t")
        elif ord(ch) < 32 or ord(ch) == 127:
            escaped.append(f"\\x{ord(ch):02x}")
        else:
            escaped.append(ch)

    return "".join(escaped)


# ---------------------------------------------------------------------------
# recv
# ---------------------------------------------------------------------------

def bind_listener(base_name):
    """base_name 부터 -2..-9 접미사를 붙여가며 바인드한다. (확정 이름, 리스너) 반환."""
    candidates = [base_name] + [f"{base_name}-{i}" for i in range(2, NAME_SUFFIX_MAX + 1)]

    for name in candidates:
        path = sock_path(name)

        if os.path.exists(path):
            if probe_alive(path):
                continue
            os.unlink(path)

        listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)

        try:
            listener.bind(path)
        except OSError as exc:
            listener.close()
            if exc.errno == errno.EADDRINUSE:
                continue
            raise

        listener.listen(8)
        return name, listener

    sys.exit(f"오류: '{base_name}' 계열 이름이 모두 사용 중입니다 (list 로 확인하세요).")


def write_meta(name):
    meta = {"pid": os.getpid(), "cwd": os.getcwd(), "since": time.strftime("%Y-%m-%dT%H:%M:%S")}

    with open(meta_path(name), "w", encoding="utf-8") as fp:
        json.dump(meta, fp, ensure_ascii=False)


def cleanup_session(name):
    for path in (sock_path(name), meta_path(name)):
        try:
            os.unlink(path)
        except OSError:
            pass


def clean_spool():
    """수신 기동 시 TTL 이 지난 spool 파일을 정리한다."""
    cutoff = time.time() - SPOOL_TTL_SECONDS

    try:
        entries = os.listdir(SPOOL_DIR)
    except OSError:
        return

    for entry in entries:
        path = os.path.join(SPOOL_DIR, entry)

        try:
            if os.path.isfile(path) and os.path.getmtime(path) < cutoff:
                os.unlink(path)
        except OSError:
            pass


def read_message(conn):
    """연결에서 EOF 까지 읽는다 (연결당 2초 타임아웃, 상한 READ_LIMIT)."""
    conn.settimeout(2)
    chunks = []
    total = 0

    while total < READ_LIMIT:
        data = conn.recv(65536)

        if not data:
            break

        chunks.append(data)
        total += len(data)

    return b"".join(chunks)


def spool_message(text):
    """장문 전문을 수신 측이 직접 저장하고 경로를 반환한다 (발신자 통제 경로 배제)."""
    prefix = time.strftime("%Y%m%d-%H%M%S-")
    fd, path = tempfile.mkstemp(prefix=prefix, suffix=".txt", dir=SPOOL_DIR)

    with os.fdopen(fd, "w", encoding="utf-8") as fp:
        fp.write(text)

    return path


def emit_message(payload):
    sender = sanitize_name(str(payload.get("from", "unknown")))
    text = str(payload.get("text", ""))

    if len(text) > INLINE_CHARS:
        path = spool_message(text)
        preview = escape_line(text[:PREVIEW_CHARS])
        print(f'[crosstalk from="{sender}" spool={path}] {preview}…', flush=True)
        return

    print(f'[crosstalk from="{sender}"] {escape_line(text)}', flush=True)


def run_recv(args):
    ensure_dirs()
    clean_spool()

    name, listener = bind_listener(sanitize_name(args.name))
    write_meta(name)
    atexit.register(cleanup_session, name)
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))

    listener.settimeout(5)
    print(f'[crosstalk connected name="{name}"] 수신 대기 시작', flush=True)

    while True:
        try:
            conn, _ = listener.accept()
        except socket.timeout:
            if os.getppid() == 1:
                return  # 고아화 (CLI 강제 종료) — 이름 점유 방지 위해 자체 종료
            continue

        try:
            raw = read_message(conn)
        except OSError:
            raw = b""
        finally:
            conn.close()

        if not raw:
            continue  # liveness 프로브

        try:
            payload = json.loads(raw.decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            continue

        emit_message(payload)


# ---------------------------------------------------------------------------
# send
# ---------------------------------------------------------------------------

def run_send(args):
    ensure_dirs()

    target = sanitize_name(args.to)
    path = sock_path(target)
    text = args.text if args.text is not None else sys.stdin.read()

    if not os.path.exists(path):
        sys.exit(f"오류: 세션 '{target}' 이 없습니다 (list 로 확인하세요).")

    payload = json.dumps(
        {"from": args.sender, "text": text, "ts": time.strftime("%Y-%m-%dT%H:%M:%S")},
        ensure_ascii=False,
    )
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(3)

    try:
        client.connect(path)
        client.sendall(payload.encode("utf-8"))
    except OSError:
        # stale 소켓이어도 여기서 unlink 하지 않는다 (재바인드 레이스 방지 — 정리는 recv/list 소관)
        sys.exit(f"오류: 세션 '{target}' 이 응답하지 않습니다 (list 로 정리 후 재시도하세요).")
    finally:
        client.close()

    print(f"sent → {target}")


# ---------------------------------------------------------------------------
# list
# ---------------------------------------------------------------------------

def run_list(_args):
    ensure_dirs()
    alive = []

    for entry in sorted(os.listdir(BASE_DIR)):
        if not entry.endswith(".sock"):
            continue

        name = entry[:-len(".sock")]

        if not probe_alive(sock_path(name)):
            cleanup_session(name)  # stale 정리
            continue

        cwd = ""

        try:
            with open(meta_path(name), encoding="utf-8") as fp:
                cwd = json.load(fp).get("cwd", "")
        except (OSError, ValueError):
            pass

        alive.append((name, cwd))

    if not alive:
        print("살아 있는 세션이 없습니다.")
        return

    for name, cwd in alive:
        print(f"{name}\t{cwd}")


def main():
    parser = argparse.ArgumentParser(description="Claude Code 세션 간 메시징")
    sub = parser.add_subparsers(dest="command", required=True)

    recv = sub.add_parser("recv", help="수신 리스너 (Monitor 가 실행)")
    recv.add_argument("--name", required=True)
    recv.set_defaults(func=run_recv)

    send = sub.add_parser("send", help="메시지 전송")
    send.add_argument("--from", dest="sender", required=True)
    send.add_argument("--to", required=True)
    send.add_argument("--text", default=None, help="생략 시 stdin 에서 읽음")
    send.set_defaults(func=run_send)

    lst = sub.add_parser("list", help="살아 있는 세션 목록")
    lst.set_defaults(func=run_list)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
