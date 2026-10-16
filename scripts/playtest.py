#!/usr/bin/env python3
"""Pinned playtest builds for people playing while agents keep pushing. Protocol: docs/playtest.md.

Each machine plays from its own clean worktree (<checkout>-playtest, detached at the commit pinned in
board/playtest.json), so agents' checkouts, imports and parallel test runs are never touched.

  playtest.py status                       pin, local playtest copy, and whether they match
  playtest.py pin [COMMIT] --agent NAME    pin a commit of origin/main (default: its tip) for everyone
  playtest.py sync [--commit C]            move this machine's playtest copy to the pin (or C) and import
  playtest.py host [--match] [--pve]       sync, then host from the playtest copy
  playtest.py join ADDRESS                 sync, then join from the playtest copy
"""
from __future__ import annotations

import argparse
import json
import os
import re
import socket
import subprocess
import sys
from pathlib import Path
from typing import List, Optional

sys.path.insert(0, str(Path(__file__).resolve().parent))
import board  # noqa: E402  (shares the race-safe commit/push logic and the agent-name rules)

PIN = board.ROOT / "board" / "playtest.json"
PIN_PATH = "board/playtest.json"
DEFAULT_GODOT = "/Applications/Godot.app/Contents/MacOS/Godot"


def git(*args: str, cwd: Optional[Path] = None, check: bool = True) -> str:
    proc = subprocess.run(["git", *args], cwd=cwd or board.ROOT, capture_output=True, text=True)
    if check and proc.returncode != 0:
        sys.exit(f"playtest: git {' '.join(args)} failed:\n{(proc.stderr or proc.stdout).strip()}")
    return proc.stdout.strip()


def playtest_dir() -> Path:
    if os.environ.get("PLAYTEST_DIR"):  # tests use a throwaway copy
        return Path(os.environ["PLAYTEST_DIR"])
    main_root = Path(git("rev-parse", "--path-format=absolute", "--git-common-dir")).parent
    return main_root.parent / f"{main_root.name}-playtest"


def pinned() -> Optional[dict]:
    proc = subprocess.run(["git", "show", f"{board.REMOTE}/{board.TRUNK}:{PIN_PATH}"], cwd=board.ROOT, capture_output=True, text=True)
    return json.loads(proc.stdout) if proc.returncode == 0 else None


def resolve(revision: str) -> str:
    return git("rev-parse", "--verify", f"{revision}^{{commit}}")


def godot_binary(explicit: Optional[str]) -> str:
    candidates = [explicit, os.environ.get("GODOT"), git("config", "playtest.godot", check=False) or None, DEFAULT_GODOT]
    for candidate in candidates:
        if candidate and Path(candidate).exists():
            return candidate
    sys.exit("playtest: Godot 4.7.2 not found. Pass --godot PATH, export GODOT, or run once: git config playtest.godot /path/to/Godot")


def sync(commit: Optional[str], godot: str) -> Path:
    board.fetch()
    pin = pinned()
    target = commit or (pin["commit"] if pin else f"{board.REMOTE}/{board.TRUNK}")
    sha = resolve(target)
    path = playtest_dir()
    if not path.exists():
        git("worktree", "add", "--detach", str(path), sha)
    else:
        if git("status", "--porcelain", "--untracked-files=no", cwd=path):
            sys.exit(f"playtest: {path} has local edits. The playtest copy is for playing only; move those edits to a real checkout, then retry.")
        git("checkout", "--quiet", "--detach", sha, cwd=path)
    if subprocess.run(["git", "lfs", "version"], capture_output=True).returncode == 0:
        git("lfs", "pull", cwd=path)
    imported = subprocess.run([godot, "--headless", "--editor", "--path", str(path), "--quit"], capture_output=True, text=True)
    errors = [line for line in (imported.stdout + imported.stderr).splitlines() if "ERROR" in line]
    if imported.returncode != 0 or errors:
        sys.exit("playtest: import reported errors:\n" + "\n".join(errors[:20]))
    source = "--commit" if commit else ("pin" if pin else f"{board.REMOTE}/{board.TRUNK} (nothing pinned)")
    print(f"playtest copy {path} at {sha[:7]} from {source}")
    return path


def launch(path: Path, godot: str, game_args: List[str], detach: bool) -> None:
    command = [godot, "--path", str(path), "--", *game_args]
    if detach:
        process = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        print(f"launched pid {process.pid}: {' '.join(command)}")
    else:
        sys.exit(subprocess.call(command))


def cmd_status(args: argparse.Namespace) -> None:
    board.fetch()
    pin = pinned()
    path = playtest_dir()
    local = git("rev-parse", "HEAD", cwd=path) if path.exists() else None
    if pin:
        print(f"pinned  {pin['commit'][:7]} by {pin.get('by', '?')} at {pin.get('at', '?')}: {pin.get('note', '')}")
    else:
        print("pinned  nothing (sync uses the tip of origin/main)")
    print(f"local   {local[:7] if local else 'no playtest copy yet'} ({path})")
    if pin and local:
        print("match" if local == pin["commit"] else "differs: run playtest.py sync")


def publish_pin(sha: str, agent: str, note: str) -> None:
    if subprocess.run(["git", "merge-base", "--is-ancestor", sha, f"{board.REMOTE}/{board.TRUNK}"], cwd=board.ROOT).returncode != 0:
        sys.exit(f"playtest: {sha[:7]} is not on {board.REMOTE}/{board.TRUNK}; ship it first")

    def mutate() -> List[Path]:
        record = {"commit": sha, "by": agent, "at": board.now(), "note": note}
        PIN.write_text(json.dumps(record, indent=2) + "\n")
        return [PIN]

    board.publish(f"board: {agent} pins playtest {sha[:7]}", mutate)


def host_name(args: argparse.Namespace) -> str:
    """Board name for pins written by a host; humans need not pass --agent."""
    name = getattr(args, "agent", None) or os.environ.get("BOARD_AGENT") or "host-" + socket.gethostname().split(".")[0].lower()
    return re.sub(r"[^A-Za-z0-9._-]", "-", name)


def cmd_pin(args: argparse.Namespace) -> None:
    agent = board.need_agent(args)
    board.fetch()
    sha = resolve(args.commit or f"{board.REMOTE}/{board.TRUNK}")
    publish_pin(sha, agent, args.note)
    print(f"pinned {sha[:7]}; players run: python3 scripts/playtest.py host | join ADDRESS")


def cmd_sync(args: argparse.Namespace) -> None:
    sync(args.commit, godot_binary(args.godot))


# The board pin always names the build a host is actually running, so joiners follow it.
def cmd_host(args: argparse.Namespace) -> None:
    godot = godot_binary(args.godot)
    path = sync(args.commit, godot)
    sha = git("rev-parse", "HEAD", cwd=path)
    pin = pinned()
    if not pin or pin["commit"] != sha:
        publish_pin(sha, host_name(args), f"hosting on {socket.gethostname().split('.')[0]}")
        print(f"pinned {sha[:7]}: the board now names the build this host runs")
    modes = (["--match"] if args.match else []) + (["--pve"] if args.pve else [])
    launch(path, godot, ["--host", f"--port={args.port}", *modes], args.detach)


# A joiner refused for another build reads the host's commit from the refusal, syncs to it and
# rejoins, at most twice. A host on uncommitted (+dirty) edits cannot be followed.
def cmd_join(args: argparse.Namespace) -> None:
    godot = godot_binary(args.godot)
    commit = args.commit
    game_args = [f"--join={args.address}", f"--port={args.port}"]
    if args.detach:
        launch(sync(commit, godot), godot, game_args, True)
        return
    for attempt in range(3):
        path = sync(commit, godot)
        process = subprocess.Popen([godot, "--path", str(path), "--", *game_args], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        follow = None
        for line in process.stdout:
            print(line, end="", flush=True)
            match = re.match(r"VERSION_MISMATCH: Host runs ([0-9a-f]+)(\+dirty)? ", line)
            if match:
                if match.group(2):
                    print("playtest: the host runs uncommitted edits; ask the host to ship and run playtest.py host")
                else:
                    follow = match.group(1)
                process.terminate()
                break
        process.wait()
        if not follow or attempt == 2:
            sys.exit(process.returncode if not follow else 1)
        print(f"playtest: following the host's build {follow}")
        commit = follow


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("status").set_defaults(fn=cmd_status)
    pin = sub.add_parser("pin")
    pin.add_argument("commit", nargs="?", default="")
    pin.add_argument("--note", default="")
    pin.add_argument("--agent", default=None, help="your board name, e.g. human-theo or theo-claude-4")
    pin.set_defaults(fn=cmd_pin)
    for name, fn in (("sync", cmd_sync), ("host", cmd_host), ("join", cmd_join)):
        command = sub.add_parser(name)
        if name == "join":
            command.add_argument("address", help="host LAN IP or Tailscale name, without a port")
        command.add_argument("--commit", default=None, help="exact commit to play instead of the pin")
        command.add_argument("--godot", default=None, help="path to the Godot 4.7.2 binary")
        if name != "sync":
            command.add_argument("--port", type=int, default=7777)
            command.add_argument("--detach", action="store_true", help="return after launching the game")
        if name == "host":
            command.add_argument("--match", action="store_true", help="first to three round wins")
            command.add_argument("--pve", action="store_true", help="add hostile PvE raiders")
        command.set_defaults(fn=fn)
    args = parser.parse_args()
    try:
        args.fn(args)
    except board.BoardError as error:
        sys.exit(f"playtest: {error}")


if __name__ == "__main__":
    main()
