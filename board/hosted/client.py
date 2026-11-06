#!/usr/bin/env python3
"""SECHA's hosted coordination board. Git task and ship commands stay in scripts/board.py."""
import argparse
import json
import os
from pathlib import Path
import re
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import Request, urlopen


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default=os.environ.get("SECHA_BOARD_URL"))
    parser.add_argument("--key-file", default=os.environ.get("SECHA_BOARD_KEY_FILE"))
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("whoami", "list", "show", "claim", "note", "done", "block", "release"):
        command = commands.add_parser(name)
        if name not in ("whoami", "list"):
            command.add_argument("task")
        if name == "claim":
            command.add_argument("--steal", action="store_true")
        if name in ("note", "block"):
            command.add_argument("text")
        if name in ("done", "release"):
            command.add_argument("text", nargs="?", default="")
    create = commands.add_parser("new")
    create.add_argument("title")
    create.add_argument("--area", default="shared")
    create.add_argument("--scope", action="append", default=[])
    create.add_argument("--depends", action="append", default=[])
    create.add_argument("--goal", default="")
    create.add_argument("--done-when", default="")
    create.add_argument("--for-human", default="")
    inbox = commands.add_parser("inbox")
    inbox.add_argument("--after", type=int)
    message = commands.add_parser("msg")
    message.add_argument("to")
    message.add_argument("text")
    message.add_argument("--task")
    args = parser.parse_args()

    if not args.url or not args.key_file:
        parser.error("set SECHA_BOARD_URL and SECHA_BOARD_KEY_FILE")
    url = urlsplit(args.url)
    if not url.netloc or url.username or url.path not in ("", "/") or url.query or url.fragment:
        parser.error("use the board's origin URL")
    if url.scheme != "https" and not (url.scheme == "http" and url.hostname in ("localhost", "127.0.0.1")):
        parser.error("HTTPS is required outside loopback")
    if hasattr(args, "task") and args.task and not re.fullmatch(r"H-[0-9]{3,12}", args.task):
        parser.error("expected a hosted task ID such as H-001")

    body = None
    match args.command:
        case "whoami":
            path = "/api/me"
        case "list":
            path = "/api/tasks"
        case "show":
            path = f"/api/tasks/{args.task}"
        case "new":
            path = "/api/tasks"
            body = {
                "title": args.title, "area": args.area, "scope": args.scope, "depends": args.depends,
                "goal": args.goal, "doneWhen": args.done_when,
                "forWho": f"human:{args.for_human}" if args.for_human else "",
            }
        case "inbox":
            path = "/api/messages" if args.after is None else f"/api/messages?after={args.after}"
        case "msg":
            path = "/api/messages"
            body = {"to": args.to, "task": args.task, "text": args.text}
        case _:
            path = f"/api/tasks/{args.task}/{args.command}"
            body = {"text": getattr(args, "text", ""), "steal": getattr(args, "steal", False)}
    try:
        key = Path(args.key_file).expanduser().read_text().strip()
        if not re.fullmatch(r"[0-9a-f]{64}", key):
            parser.error("invalid key file")
        data = json.dumps(body).encode() if body is not None else None
        request = Request(args.url.rstrip("/") + path, data, {
            "Content-Type": "application/json",
            "User-Agent": "SECHA-Board/1.0",
        })
        request.add_unredirected_header("Authorization", f"Bearer {key}")
        with urlopen(request, timeout=15) as response:
            print(json.dumps(json.load(response), ensure_ascii=False, indent=2))
    except HTTPError as error:
        try:
            detail = json.load(error).get("error", error.reason)
        except ValueError:
            detail = error.reason
        sys.exit(f"board: HTTP {error.code}: {detail}")
    except (OSError, URLError) as error:
        sys.exit(f"board: {error}")


if __name__ == "__main__":
    main()
