#!/usr/bin/env python3
"""Read-only web page for the agent board: who works on what, live from origin/main.

  python3 scripts/board_web.py            then open http://localhost:8777
  python3 scripts/board_web.py --port 9000

It never commits or merges; it only fetches origin/main (at most every 15 s) and reads
board/tasks/*.md and board/playtest.json from there, so it shows the latest pushed state
whatever this checkout has. The page refreshes itself every 10 s.
"""
from __future__ import annotations

import argparse
import datetime as dt
import html
import json
import re
import subprocess
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Dict, List, Tuple

ROOT = Path(subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=True).stdout.strip())
REF = "origin/main"
STALE_HOURS = 3
ORDER = {"claimed": 0, "blocked": 1, "open": 2, "done": 3}
last_fetch = 0.0


def git(*args: str) -> str:
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True).stdout


def refresh() -> None:
    global last_fetch
    if time.time() - last_fetch > 15:
        subprocess.run(["git", "fetch", "--quiet", "origin", "main"], cwd=ROOT, capture_output=True)
        last_fetch = time.time()


def tasks() -> List[Tuple[Dict[str, str], List[str]]]:
    found = []
    for name in git("ls-tree", "--name-only", f"{REF}:board/tasks").split():
        text = git("show", f"{REF}:board/tasks/{name}")
        match = re.match(r"---\n(.*?)\n---\n?(.*)", text, re.S)
        if not match:
            continue
        meta = {k.strip(): v.strip() for k, _, v in (line.partition(":") for line in match.group(1).splitlines())}
        log = [line[2:] for line in match.group(2).splitlines() if line.startswith("- 20")]
        found.append((meta, log))
    return sorted(found, key=lambda item: (ORDER.get(item[0].get("status", ""), 9), item[0].get("id", "")))


def stale(meta: Dict[str, str]) -> bool:
    try:
        stamp = dt.datetime.strptime(meta.get("updated", ""), "%Y-%m-%dT%H:%MZ").replace(tzinfo=dt.timezone.utc)
    except ValueError:
        return False
    return meta.get("status") == "claimed" and dt.datetime.now(dt.timezone.utc) - stamp > dt.timedelta(hours=STALE_HOURS)


def activity() -> Dict[str, int]:
    """Pushes per agent in the last hour, from commit subjects and Agent: trailers."""
    counts: Dict[str, int] = {}
    for name in re.findall(r"\b([a-z]+-[a-z]+-\d+)\b", git("log", "--since=60 minutes ago", "--format=%s %b", REF)):
        counts[name] = counts.get(name, 0) + 1
    return counts


def visuals(all_tasks: List[Tuple[Dict[str, str], List[str]]]) -> str:
    total = max(1, len(all_tasks))
    counts = {status: sum(1 for m, _ in all_tasks if m.get("status") == status) for status in ORDER}
    bar = "".join(f"<div class='seg {s}' style='flex:{n}' title='{s}: {n}'>{s} {n}</div>" for s, n in counts.items() if n)
    busy = activity()
    owners = {m.get("owner", ""): m for m, _ in all_tasks if m.get("status") == "claimed" and m.get("owner")}
    agents = sorted(set(busy) | set(owners), key=lambda a: (-busy.get(a, 0), a))
    peak = max([1] + list(busy.values()))
    cards = []
    for agent in agents:
        task = owners.get(agent)
        doing = f"{html.escape(task['id'])} · {html.escape(task.get('title', ''))}" if task else "no claimed task"
        width = int(100 * busy.get(agent, 0) / peak)
        cards.append(f"<div class='card{' idle' if not task else ''}'><b>{html.escape(agent)}</b><div class='doing'>{doing}</div>"
                     f"<div class='meter'><div style='width:{width}%'></div></div><div class='log'>{busy.get(agent, 0)} pushes in the last hour</div></div>")
    return f"<div class='bar'>{bar}</div><div class='cards'>{''.join(cards)}</div><p class='log'>{total} tasks</p>"


def page() -> str:
    refresh()
    rows = []
    for meta, log in tasks():
        status = meta.get("status", "?")
        flag = " stale" if stale(meta) else ""
        last = html.escape(log[-1][:220]) if log else ""
        rows.append(
            f"<tr class='{status}{flag}'><td>{html.escape(meta.get('id', ''))}</td>"
            f"<td><span class='pill'>{html.escape(status)}{' · STALE' if flag else ''}</span></td>"
            f"<td><b>{html.escape(meta.get('owner') or '—')}</b></td>"
            f"<td>{html.escape(meta.get('title', ''))}<div class='log'>{last}</div></td>"
            f"<td class='when'>{html.escape(meta.get('updated', ''))}</td></tr>")
    pin_text = git("show", f"{REF}:board/playtest.json")
    pin = json.loads(pin_text) if pin_text.strip() else None
    pin_line = (f"Playtest pin <b>{html.escape(pin['commit'][:7])}</b> by {html.escape(pin.get('by', '?'))} at {html.escape(pin.get('at', ''))}: {html.escape(pin.get('note', ''))}"
                if pin else "No playtest pin")
    head = html.escape(git("log", "-1", "--format=%h %s", REF).strip())
    working = sorted({m.get("owner", "") for m, _ in tasks() if m.get("status") == "claimed" and m.get("owner")})
    return f"""<!doctype html><html><head><meta charset="utf-8"><meta http-equiv="refresh" content="10">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>Voina board</title><style>
:root{{color-scheme:light dark;--bg:#f6f7f9;--card:#fff;--text:#1d2329;--muted:#66717c;--line:#e2e6ea}}
@media (prefers-color-scheme:dark){{:root{{--bg:#14181c;--card:#1d2328;--text:#e6eaee;--muted:#9aa5af;--line:#2d353c}}}}
body{{margin:0;padding:16px;background:var(--bg);color:var(--text);font:14px/1.4 -apple-system,system-ui,sans-serif}}
h1{{font-size:20px;margin:0 0 4px}} .sub{{color:var(--muted);margin-bottom:14px}}
table{{width:100%;border-collapse:collapse;background:var(--card);border-radius:8px;overflow:hidden}}
td,th{{padding:8px 10px;border-bottom:1px solid var(--line);vertical-align:top;text-align:left}}
th{{color:var(--muted);font-weight:600;font-size:12px}} .log{{color:var(--muted);font-size:12px;margin-top:3px}}
.when{{white-space:nowrap;color:var(--muted);font-size:12px}} .pill{{padding:2px 8px;border-radius:10px;font-size:12px;white-space:nowrap}}
.claimed .pill{{background:#2f7de1;color:#fff}} .blocked .pill{{background:#d9822b;color:#fff}} .open .pill{{background:#8a96a3;color:#fff}}
.bar{{display:flex;height:26px;border-radius:8px;overflow:hidden;margin:6px 0 14px;font-size:12px;color:#fff}}
.seg{{display:flex;align-items:center;justify-content:center;white-space:nowrap;overflow:hidden;min-width:56px}}
.seg.claimed{{background:#2f7de1}} .seg.blocked{{background:#d9822b}} .seg.open{{background:#8a96a3}} .seg.done{{background:#3a9d5d}}
.cards{{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:10px;margin-bottom:6px}}
.card{{background:var(--card);border-radius:8px;padding:10px;border-left:4px solid #2f7de1}} .card.idle{{border-left-color:#8a96a3}}
.doing{{font-size:13px;margin:4px 0 8px}} .meter{{height:6px;background:var(--line);border-radius:3px}}
.meter div{{height:6px;background:#2f7de1;border-radius:3px}}
.done{{opacity:.55}} .done .pill{{background:#3a9d5d;color:#fff}} .stale .pill{{background:#c94343}}
</style></head><body><h1>Voina board</h1>
<div class="sub">Working now: <b>{html.escape(', '.join(working) or 'nobody')}</b> · {pin_line}<br>origin/main: {head} · refreshes every 10 s</div>
{visuals(tasks())}
<table><tr><th>Task</th><th>Status</th><th>Owner</th><th>Title · latest log</th><th>Updated (UTC)</th></tr>{''.join(rows)}</table></body></html>"""


class Handler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        body = page().encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args: object) -> None:
        pass


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--port", type=int, default=8777)
    args = parser.parse_args()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print(f"board page: http://localhost:{args.port}")
    server.serve_forever()


if __name__ == "__main__":
    main()
