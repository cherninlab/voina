#!/usr/bin/env python3
"""Git-backed task board for many agents on many machines. Protocol: board/README.md.

Every mutation is a small commit of board files only, pushed straight to origin/main.
A rejected push means someone else moved first: we refetch, re-check, and retry, so
the remote decides who wins a claim. Nothing here stashes, resets --hard, or commits
files other than the ones named, because several agents may share one checkout.
"""
from __future__ import annotations

import argparse
import datetime as dt
import os
import re
import select
import signal
import socket
import subprocess
import sys
import time
from pathlib import Path
from typing import Callable, Dict, List, Optional, Tuple

REMOTE = "origin"
TRUNK = "main"
STALE_HOURS = 3
POKE_PORT = int(os.environ.get("BOARD_PORT", "47777"))
FIELDS = ["id", "title", "status", "owner", "scope", "depends", "updated"]
STATUSES = ("open", "claimed", "blocked", "done")


class BoardError(Exception):
    pass


def _toplevel() -> Path:
    proc = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    if proc.returncode != 0:
        sys.exit("board: run inside the git checkout")
    return Path(proc.stdout.strip())


ROOT = _toplevel()
TASKS = ROOT / "board" / "tasks"


def git(*args: str, check: bool = True) -> subprocess.CompletedProcess:
    proc = subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True)
    for attempt in range(8):
        if "index.lock" not in proc.stderr:
            break
        time.sleep(0.5 + attempt * 0.5)  # another agent in this checkout is mid-commit
        proc = subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True)
    if check and proc.returncode != 0:
        raise BoardError(f"git {' '.join(args)} failed:\n{(proc.stderr or proc.stdout).strip()}")
    return proc


def utcnow() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def now() -> str:
    return utcnow().strftime("%Y-%m-%dT%H:%MZ")


def shared_checkout() -> bool:
    """On main = the shared checkout other agents may be editing; elsewhere = a private worktree."""
    return git("rev-parse", "--abbrev-ref", "HEAD").stdout.strip() == TRUNK


def ahead_behind() -> Tuple[int, int]:
    out = git("rev-list", "--left-right", "--count", f"HEAD...{REMOTE}/{TRUNK}").stdout.split()
    return int(out[0]), int(out[1])


def fetch() -> None:
    git("fetch", "--quiet", REMOTE, TRUNK)


def integrate() -> None:
    """Bring origin/main into HEAD without touching anyone's uncommitted work."""
    ahead, behind = ahead_behind()
    if behind == 0:
        return
    upstream = f"{REMOTE}/{TRUNK}"
    if not shared_checkout():
        proc = git("rebase", "--autostash", upstream, check=False)
        if proc.returncode != 0:
            git("rebase", "--abort", check=False)
            raise BoardError(f"rebase onto {upstream} conflicts; resolve by hand:\n{proc.stdout}{proc.stderr}")
        return
    if ahead == 0:
        proc = git("merge", "--ff-only", upstream, check=False)
    else:
        if git("merge-tree", "--write-tree", "HEAD", upstream, check=False).returncode != 0:
            raise BoardError(f"local commits conflict with {upstream}; resolve by hand (shared checkout left untouched)")
        proc = git("merge", "--no-edit", upstream, check=False)
    if proc.returncode != 0:
        raise BoardError(
            "cannot merge origin/main: an agent in this checkout has uncommitted edits to files that "
            f"changed remotely. They must ship first.\n{(proc.stderr or proc.stdout).strip()}"
        )


def push() -> bool:
    proc = git("push", "--quiet", REMOTE, f"HEAD:{TRUNK}", check=False)
    if proc.returncode == 0:
        poke()
        return True
    if re.search(r"rejected|fetch first|non-fast-forward", proc.stderr):
        return False
    raise BoardError(f"push failed:\n{proc.stderr.strip()}")


def repo_id() -> str:
    return Path(git("remote", "get-url", REMOTE, check=False).stdout.strip().rstrip("/")).stem or "repo"


def poke() -> None:
    """LAN/Tailscale doorbell after a push: peers' watchers fetch now. It carries no state;
    origin/main stays the only source of truth, so a lost or forged poke costs one fetch."""
    message = f"board-poke {repo_id()} {socket.gethostname()} {os.getpid()}".encode()
    peers = git("config", "--get-all", "board.peer", check=False).stdout.split()
    peers += [host.strip() for host in os.environ.get("BOARD_PEERS", "").split(",") if host.strip()]
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        for host in ["127.0.0.1", "<broadcast>", *peers]:
            try:
                sock.sendto(message, (host, POKE_PORT))
            except OSError:
                pass  # offline peer or unresolvable name: polling still covers it


def listen() -> Optional[socket.socket]:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    if hasattr(socket, "SO_REUSEPORT"):
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
    try:
        sock.bind(("", POKE_PORT))
    except OSError as error:
        print(f"board: no LAN pokes on UDP {POKE_PORT} ({error}); polling only", flush=True)
        sock.close()
        return None
    return sock


def wait_for_poke(sock: Optional[socket.socket], timeout: float) -> Optional[str]:
    """Block until a poke for this repo arrives (returns its sender) or timeout (returns None)."""
    deadline = time.monotonic() + timeout
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return None
        if sock is None:
            time.sleep(remaining)
            return None
        if not select.select([sock], [], [], remaining)[0]:
            return None
        data, (address, _) = sock.recvfrom(256)
        words = data.decode(errors="replace").split()
        if words[:2] != ["board-poke", repo_id()] or words[2:4] == [socket.gethostname(), str(os.getpid())]:
            continue
        time.sleep(1.0)  # let a burst of pushes land, then fetch once
        while select.select([sock], [], [], 0)[0]:
            sock.recvfrom(256)
        return f"{words[2] if len(words) > 2 else address} ({address})"


def sync() -> str:
    for _ in range(4):
        fetch()
        integrate()
        ahead, behind = ahead_behind()
        if ahead == 0 or push():
            return f"in sync with {REMOTE}/{TRUNK} ({'shared checkout' if shared_checkout() else 'own worktree'})"
    raise BoardError("gave up after repeated push races")


def publish(message: str, mutate: Callable[[], List[Path]]) -> None:
    """Sync, apply mutate() to fresh state, commit only its paths, push; retry if raced."""
    for _ in range(6):
        sync()
        paths = mutate()
        rel = [str(p.relative_to(ROOT)) for p in paths]
        git("add", "--", *rel)
        if git("diff", "--cached", "--quiet", "HEAD", "--", *rel, check=False).returncode == 0:
            return
        git("commit", "--quiet", "--only", "-m", message, "--", *rel)
        mine = git("rev-parse", "HEAD").stdout.strip()
        if push():
            return
        fetch()
        if git("diff", "--quiet", f"{mine}^", f"{REMOTE}/{TRUNK}", "--", *rel, check=False).returncode != 0:
            undo(mine)  # someone changed the same board file first: redo against their version
            continue
        integrate()
        if push():
            return
    raise BoardError("gave up after repeated push races")


def undo(commit: str) -> None:
    if git("rev-parse", "HEAD").stdout.strip() != commit:
        raise BoardError(f"another commit landed on top of unpushed board commit {commit[:8]}; resolve by hand")
    git("reset", "--quiet", "--keep", f"{commit}^")


# ---------- task files ----------

def task_path(task_id: str) -> Path:
    digits = re.sub(r"\D", "", task_id)
    if not digits:
        raise BoardError(f"bad task id {task_id!r}")
    return TASKS / f"T-{int(digits):03d}.md"


def read_task(path: Path) -> Tuple[Dict[str, str], str]:
    if not path.exists():
        raise BoardError(f"no such task {path.stem}")
    text = path.read_text()
    match = re.match(r"---\n(.*?)\n---\n?(.*)", text, re.S)
    if not match:
        raise BoardError(f"{path.name} has no front matter")
    meta: Dict[str, str] = {}
    for line in match.group(1).splitlines():
        key, _, value = line.partition(":")
        meta[key.strip()] = value.strip()
    return meta, match.group(2)


def write_task(path: Path, meta: Dict[str, str], body: str) -> None:
    head = "\n".join(f"{key}: {meta.get(key, '')}".rstrip() for key in FIELDS)
    path.write_text(f"---\n{head}\n---\n{body.rstrip()}\n")


def add_log(body: str, agent: str, text: str) -> str:
    if "\n## Log" not in "\n" + body:
        body = body.rstrip() + "\n\n## Log\n"
    return body.rstrip() + f"\n- {now()} {agent}: {text}\n"


def is_stale(meta: Dict[str, str]) -> bool:
    try:
        stamp = dt.datetime.strptime(meta.get("updated", ""), "%Y-%m-%dT%H:%MZ").replace(tzinfo=dt.timezone.utc)
    except ValueError:
        return True
    return utcnow() - stamp > dt.timedelta(hours=STALE_HOURS)


def all_tasks() -> List[Tuple[Dict[str, str], str]]:
    return [read_task(p) for p in sorted(TASKS.glob("T-*.md"))]


# ---------- commands ----------

def need_agent(args: argparse.Namespace) -> str:
    agent = args.agent or os.environ.get("BOARD_AGENT", "")
    if not re.fullmatch(r"[A-Za-z0-9._-]+", agent):
        raise BoardError("pass --agent NAME (e.g. theo-claude-2) or set BOARD_AGENT")
    return agent


def cmd_sync(args: argparse.Namespace) -> None:
    print(sync())


def cmd_list(args: argparse.Namespace) -> None:
    if not args.no_sync:
        print(sync())
    tasks = all_tasks()
    done = {meta["id"] for meta, _ in tasks if meta.get("status") == "done"}
    for meta, _ in tasks:
        status = meta.get("status", "?")
        if status == "done" and not args.all:
            continue
        flags = []
        waiting = [d.strip() for d in meta.get("depends", "").split(",") if d.strip() and d.strip() not in done]
        if waiting:
            flags.append("waits " + ",".join(waiting))
        if status == "claimed" and is_stale(meta):
            flags.append("STALE")
        extra = f"  ({'; '.join(flags)})" if flags else ""
        print(f"{meta['id']}  {status:8} {meta.get('owner') or '-':20} {meta.get('title', '')}{extra}")
        if args.verbose and meta.get("scope"):
            print(f"        scope: {meta['scope']}")


def cmd_show(args: argparse.Namespace) -> None:
    print(task_path(args.id).read_text())


def cmd_new(args: argparse.Namespace) -> None:
    agent = need_agent(args)
    created: List[Path] = []

    def mutate() -> List[Path]:
        numbers = [int(p.stem[2:]) for p in TASKS.glob("T-*.md")]
        path = task_path(str(max(numbers, default=0) + 1))
        meta = {
            "id": path.stem, "title": args.title, "status": "open", "owner": "",
            "scope": args.scope, "depends": args.depends, "updated": now(),
        }
        body = f"\n## Goal\n{args.body or args.title}\n\n## Done when\n- {args.done_when or 'TBD by the claimer'}\n"
        write_task(path, meta, add_log(body, agent, "created"))
        created[:] = [path]
        return [path]

    publish(f"board: {agent} adds task", mutate)
    print(f"created {created[0].stem}: {args.title}")


def transition(args: argparse.Namespace, status: Optional[str], note: str, owner_check: bool) -> None:
    agent = need_agent(args)
    path = task_path(args.id)

    def mutate() -> List[Path]:
        meta, body = read_task(path)
        owner = meta.get("owner", "")
        if status == "claimed":
            if meta.get("status") == "done":
                raise BoardError(f"{meta['id']} is done")
            if meta.get("status") == "claimed" and owner != agent and not args.steal:
                stale = " (stale: use --steal)" if is_stale(meta) else ""
                raise BoardError(f"{meta['id']} already claimed by {owner}{stale}")
        elif owner_check and meta.get("status") == "claimed" and owner != agent:
            raise BoardError(f"{meta['id']} is owned by {owner}, not {agent}")
        if status:
            meta["status"] = status
            meta["owner"] = "" if status == "open" else agent
        meta["updated"] = now()
        text = note + (f" (stolen from {owner})" if status == "claimed" and owner and owner != agent else "")
        write_task(path, meta, add_log(body, agent, text))
        return [path]

    publish(f"board: {agent} {note.split(':')[0]} {path.stem}", mutate)
    print(f"{path.stem}: {note}")


def cmd_claim(args: argparse.Namespace) -> None:
    transition(args, "claimed", "claimed", owner_check=False)


def cmd_done(args: argparse.Namespace) -> None:
    transition(args, "done", f"done: {args.message}" if args.message else "done", owner_check=True)


def cmd_release(args: argparse.Namespace) -> None:
    transition(args, "open", f"released: {args.message}" if args.message else "released", owner_check=True)


def cmd_block(args: argparse.Namespace) -> None:
    transition(args, "blocked", f"blocked: {args.message}", owner_check=True)


def cmd_note(args: argparse.Namespace) -> None:
    transition(args, None, f"note: {args.message}", owner_check=False)


def cmd_ship(args: argparse.Namespace) -> None:
    agent = need_agent(args)
    rel: List[str] = []
    for raw in args.paths:
        path = (Path.cwd() / raw).resolve()
        if path == ROOT or ROOT not in path.parents:
            raise BoardError(f"refusing to ship {raw!r}: name the exact files you changed")
        rel.append(str(path.relative_to(ROOT)))
    git("add", "--all", "--", *rel)
    if git("diff", "--cached", "--quiet", "HEAD", "--", *rel, check=False).returncode == 0:
        print("nothing to ship in those paths")
        return
    git("commit", "--quiet", "--only", "-m", f"{args.message}\n\nAgent: {agent}", "--", *rel)
    print(git("log", "-1", "--stat", "--format=%h %s").stdout.strip())
    print(sync())


def cmd_watch(args: argparse.Namespace) -> None:
    lock = Path(git("rev-parse", "--git-path", "board-watch.pid").stdout.strip())
    lock = lock if lock.is_absolute() else ROOT / lock
    if lock.exists():
        try:
            os.kill(int(lock.read_text().strip()), 0)
            sys.exit(f"board: a watcher is already running for this checkout ({lock})")
        except (ProcessLookupError, ValueError):
            pass
    lock.write_text(str(os.getpid()))
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    sock = listen()
    reason = "start"
    try:
        while True:
            try:
                message = sync()
            except BoardError as error:
                message = f"WARN {error}"
            print(f"{dt.datetime.now():%H:%M:%S} [{reason}] {message}", flush=True)
            sender = wait_for_poke(sock, args.interval)
            reason = f"poke from {sender}" if sender else "poll"
    except KeyboardInterrupt:
        pass
    finally:
        if sock is not None:
            sock.close()
        lock.unlink(missing_ok=True)


def cmd_worktree(args: argparse.Namespace) -> None:
    need_agent(args)
    main_root = Path(git("rev-parse", "--path-format=absolute", "--git-common-dir").stdout.strip()).parent
    target = main_root.parent / f"{main_root.name}-agents" / args.agent
    fetch()
    git("worktree", "add", "-b", f"agent/{args.agent}", str(target), f"{REMOTE}/{TRUNK}")
    print(f"worktree ready: {target}\nrun: cd {target} && \"$GODOT\" --headless --editor --path . --quit")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--agent", help="your agent name, e.g. theo-claude-2 (or env BOARD_AGENT)")
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--agent", default=argparse.SUPPRESS, help="your agent name (or env BOARD_AGENT)")
    sub = parser.add_subparsers(dest="command", required=True)

    def command(name: str, fn: Callable[[argparse.Namespace], None], help_text: str = "") -> argparse.ArgumentParser:
        p = sub.add_parser(name, parents=[common], help=help_text or None)
        p.set_defaults(fn=fn)
        return p

    command("sync", cmd_sync, "fetch, merge origin/main safely, push local commits")
    p = command("list", cmd_list, "sync and list tasks")
    p.add_argument("--all", action="store_true", help="include done tasks")
    p.add_argument("-v", "--verbose", action="store_true", help="show scopes")
    p.add_argument("--no-sync", action="store_true")
    command("show", cmd_show).add_argument("id")
    p = command("new", cmd_new, "add an open task")
    p.add_argument("title")
    p.add_argument("--scope", default="", help="comma-separated paths the task will touch")
    p.add_argument("--depends", default="", help="comma-separated task ids")
    p.add_argument("--body", default="")
    p.add_argument("--done-when", default="")
    p = command("claim", cmd_claim, "take a task; the first push wins")
    p.add_argument("id")
    p.add_argument("--steal", action="store_true", help="take over another agent's task (logged)")
    for name, fn, required in (("done", cmd_done, False), ("release", cmd_release, False),
                               ("block", cmd_block, True), ("note", cmd_note, True)):
        p = command(name, fn)
        p.add_argument("id")
        p.add_argument("message", nargs=None if required else "?", default="")
    p = command("ship", cmd_ship, "commit ONLY the named paths, then sync and push")
    p.add_argument("-m", "--message", required=True)
    p.add_argument("paths", nargs="+")
    command("watch", cmd_watch, "keep this checkout synced (one per checkout)").add_argument(
        "--interval", type=int, default=60)
    command("worktree", cmd_worktree, "create a private worktree for --agent")

    args = parser.parse_args()
    try:
        args.fn(args)
    except BoardError as error:
        sys.exit(f"board: {error}")


if __name__ == "__main__":
    main()
