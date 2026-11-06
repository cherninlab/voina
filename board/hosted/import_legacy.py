#!/usr/bin/env python3
"""Import and verify archived Git tasks from an immutable Git snapshot."""
from concurrent.futures import ThreadPoolExecutor
import argparse
import json
from pathlib import Path
import re
import subprocess
from urllib.parse import urlsplit
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[2]


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT).decode("utf-8")


def records(ref):
    files = git("ls-tree", "-r", "--name-only", ref, "board/tasks").splitlines()
    tasks = []
    for path in files:
        if not re.fullmatch(r"board/tasks/T-\d{3,12}\.md", path):
            raise ValueError(f"Unexpected file in the task archive: {path}")
        source = git("show", f"{ref}:{path}")
        head = re.match(r"\A---\r?\n(.*?)\r?\n---\r?\n(.*)\Z", source, re.S)
        if not head:
            raise ValueError(f"Malformed task: {path}")
        meta = dict((key.strip(), value.strip()) for line in head[1].splitlines()
                    for key, _, value in [line.partition(":")])
        task_id = Path(path).stem
        if meta["id"] != task_id:
            raise ValueError(f"ID mismatch: {path}")
        sections = re.split(r"^## +(.+?)\s*$", head[2], flags=re.M)
        body = {name: text.strip() for name, text in zip(sections[1::2], sections[2::2])}
        scope = [item.strip() for item in meta.get("scope", "").split(",") if item.strip()]
        depends = [item.strip() for item in meta.get("depends", "").split(",") if item.strip()]
        owner = meta.get("owner", "")
        tasks.append(dict(
            id=task_id, title=meta["title"], status=meta["status"], owner=owner, updated=meta["updated"],
            scope=scope, depends=depends, goal=body.get("Goal", ""), doneWhen=body.get("Done when", ""),
            humanOnly=owner.startswith("human:") or meta["title"].startswith("Human:"), legacyMarkdown=source,
        ))
    if not tasks:
        raise ValueError(f"No task files in {ref}")
    return tasks


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ref", default="origin/main")
    parser.add_argument("--url", default="https://secha-agent-board.cherninlab.workers.dev")
    parser.add_argument("--key-file", type=Path, default=Path.home() / ".config/secha-board/human-theo.key")
    parser.add_argument("--apply", action="store_true", help="write and read back all legacy tasks")
    args = parser.parse_args()
    ref = git("rev-parse", "--verify", f"{args.ref}^{{commit}}").strip()
    tasks = records(ref)
    print(f"{len(tasks)} Git tasks in {ref[:12]}", flush=True)
    if not args.apply:
        return
    url = urlsplit(args.url)
    if url.scheme != "https" and not (url.scheme == "http" and url.hostname in ("localhost", "127.0.0.1")):
        parser.error("HTTPS is required outside loopback")
    if not url.netloc or url.username or url.path not in ("", "/") or url.query or url.fragment:
        parser.error("use the board's origin URL")
    key = args.key_file.expanduser().read_text().strip()
    if not re.fullmatch(r"[0-9a-f]{64}", key):
        parser.error("invalid board key")

    def request(path, body=None):
        data = json.dumps(body, ensure_ascii=False).encode() if body is not None else None
        req = Request(args.url.rstrip("/") + path, data, {
            "Content-Type": "application/json", "User-Agent": "SECHA-Board/1.0",
        })
        req.add_unredirected_header("Authorization", f"Bearer {key}")
        with urlopen(req, timeout=30) as response:
            return json.load(response)

    try:
        result = request("/api/admin/import-legacy", {"tasks": tasks})
        print(json.dumps(result), flush=True)
        if result["total"] != len(tasks):
            raise ValueError("Import count differs from source")

        def verify(source):
            item = request(f"/api/tasks/{source['id']}")
            keys = ("id", "title", "scope", "depends", "goal", "doneWhen", "humanOnly", "legacyMarkdown")
            if item["labels"] != ["legacy"] or any(item[k] != source[k] for k in keys):
                raise ValueError(f"Legacy data differs for {source['id']}")
            if not item["log"] and (item["status"], item["owner"], item["updated"]) != (
                source["status"], source["owner"] or None, source["updated"],
            ):
                raise ValueError(f"Task state differs for {source['id']}")

        with ThreadPoolExecutor(max_workers=8) as pool:
            list(pool.map(verify, tasks))
    except (OSError, ValueError, KeyError) as error:
        parser.exit(1, f"import: {error}\n")
    print(f"Verified {len(tasks)} legacy tasks against {ref[:12]}, including original Markdown.")


if __name__ == "__main__":
    main()
