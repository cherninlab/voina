#!/usr/bin/env python3
"""Create a local key for each actor and rebuild the Cloudflare secrets file."""
from hashlib import sha256
import json
import os
from pathlib import Path
import re
import secrets
import sys

ACTOR = re.compile(r"(?:human:[a-z0-9]+|[a-z0-9]+(?:-[a-z0-9]+)+-[1-9][0-9]*)")
ROOT = Path.home() / ".config" / "secha-board"


def main():
    actors = sys.argv[1:]
    if not actors or any(not ACTOR.fullmatch(actor) for actor in actors):
        sys.exit("usage: keys.py human:theo theo-codex-1 [other-actor ...]")
    os.umask(0o077)
    ROOT.mkdir(mode=0o700, parents=True, exist_ok=True)
    keys = {}
    for actor in actors:
        path = ROOT / (actor.replace(":", "-") + ".key")
        try:
            with path.open("x") as keyfile:
                keyfile.write(secrets.token_hex(32) + "\n")
        except FileExistsError:
            pass
        key = path.read_text().strip()
        if not re.fullmatch(r"[0-9a-f]{64}", key):
            sys.exit(f"invalid key file: {path}")
        keys[sha256(key.encode()).hexdigest()] = actor
    output = ROOT / "cloudflare-secrets.json"
    with output.open("w") as secretfile:
        json.dump({"BOARD_KEYS": json.dumps(keys)}, secretfile)
    print(f"Prepared {len(keys)} board keys in {ROOT}")


if __name__ == "__main__":
    main()
