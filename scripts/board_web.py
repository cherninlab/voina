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
from typing import Dict, List, Optional, Tuple

ROOT = Path(subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=True).stdout.strip())
REF = "origin/main"
STALE_HOURS = 3
AGENT = re.compile(r"\b([a-z]+-[a-z]+-\d+)\b")
HUE: Dict[str, str] = {}
last_fetch = 0.0

Task = Tuple[Dict[str, str], List[str]]


def git(*args: str) -> str:
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True).stdout


def refresh() -> None:
    global last_fetch
    if time.time() - last_fetch > 15:
        subprocess.run(["git", "fetch", "--quiet", "origin", "main"], cwd=ROOT, capture_output=True)
        last_fetch = time.time()


def tasks() -> List[Task]:
    found = []
    for name in git("ls-tree", "--name-only", f"{REF}:board/tasks").split():
        text = git("show", f"{REF}:board/tasks/{name}")
        match = re.match(r"---\n(.*?)\n---\n?(.*)", text, re.S)
        if not match:
            continue
        meta = {k.strip(): v.strip() for k, _, v in (line.partition(":") for line in match.group(1).splitlines())}
        log = [line[2:] for line in match.group(2).splitlines() if line.startswith("- 20")]
        found.append((meta, log))
    return sorted(found, key=lambda item: item[0].get("id", ""))


def stamp(text: str) -> Optional[dt.datetime]:
    try:
        return dt.datetime.strptime(text, "%Y-%m-%dT%H:%MZ").replace(tzinfo=dt.timezone.utc)
    except ValueError:
        return None


def ago(when: Optional[dt.datetime]) -> str:
    if when is None:
        return ""
    minutes = int((dt.datetime.now(dt.timezone.utc) - when).total_seconds() // 60)
    if minutes < 1:
        return "just now"
    if minutes < 60:
        return f"{minutes} min ago"
    if minutes < 48 * 60:
        return f"{minutes // 60} h ago"
    return f"{minutes // 1440} d ago"


def stale(meta: Dict[str, str]) -> bool:
    when = stamp(meta.get("updated", ""))
    return meta.get("status") == "claimed" and when is not None and dt.datetime.now(dt.timezone.utc) - when > dt.timedelta(hours=STALE_HOURS)


def activity() -> Dict[str, Tuple[int, dt.datetime]]:
    """Per agent: pushes in the last hour and the time of their latest push in the last day."""
    seen: Dict[str, Tuple[int, dt.datetime]] = {}
    hour_ago = time.time() - 3600
    for line in git("log", "--since=24 hours ago", "--format=%ct %s %b%x00", REF).split("\0"):
        head, _, text = line.strip().partition(" ")
        if not head.isdigit():
            continue
        pushed = dt.datetime.fromtimestamp(int(head), dt.timezone.utc)
        for name in set(AGENT.findall(text)):
            count, last = seen.get(name, (0, pushed))
            seen[name] = (count + (int(head) > hour_ago), max(last, pushed))
    return seen


def assign_hues(all_tasks: List[Task]) -> None:
    """Colour agents by first appearance on the board, spread by the golden angle, so colours never shift."""
    first: Dict[str, str] = {}
    for _, log in all_tasks:
        for entry in log:
            name = entry.partition(" ")[2].partition(":")[0]
            if AGENT.fullmatch(name) and entry < first.get(name, "~"):
                first[name] = entry
    for i, name in enumerate(sorted(first, key=lambda n: (first[n], n))):
        HUE[name] = colour(i)


def colour(i: int) -> str:
    return f"{int(212 + i * 137.508) % 360} {(62, 55, 70)[i % 3]}% {(52, 42, 62)[i % 3]}%"


def hue(agent: str) -> str:
    return HUE.setdefault(agent, colour(len(HUE)))


def who(agent: str) -> str:
    """theo-claude-2 -> a coloured dot, 'theo' and a quiet 'claude 2'."""
    person, _, tool = agent.partition("-")
    return (f"<span class='who' style='--h:{hue(agent)}'><i></i>{html.escape(person)}"
            f"<span class='tool'>{html.escape(tool.replace('-', ' '))}</span></span>")


def log_line(entry: str) -> Tuple[str, str]:
    """'2026-10-16T21:06Z theo-claude-1: note: text' -> ('5 min ago', 'theo-claude-1: text')."""
    when, _, rest = entry.partition(" ")
    return ago(stamp(when)), re.sub(r"^([^:]+): note: ", r"\1: ", rest)


def details(meta: Dict[str, str], log: List[str]) -> str:
    scope = "".join(f"<li>{html.escape(p.strip())}</li>" for p in meta.get("scope", "").split(",") if p.strip())
    entries = "".join(f"<li><span class='t'>{html.escape(t)}</span>{html.escape(text)}</li>"
                      for t, text in (log_line(e) for e in reversed(log[-6:])))
    parts = []
    if scope:
        parts.append(f"<div class='k'>Scope</div><ul class='scope'>{scope}</ul>")
    if entries:
        parts.append(f"<div class='k'>Log</div><ul class='entries'>{entries}</ul>")
    return f"<div class='more'>{''.join(parts)}</div>" if parts else ""


def latest(log: List[str]) -> str:
    if not log:
        return ""
    when, text = log_line(log[-1])
    return f"<p class='last'>{html.escape(text[:200])}<span class='t'>{html.escape(when)}</span></p>"


def agents_section(all_tasks: List[Task]) -> str:
    busy = activity()
    owned: Dict[str, List[Task]] = {}
    for meta, log in all_tasks:
        if meta.get("status") in ("claimed", "blocked") and meta.get("owner"):
            owned.setdefault(meta["owner"], []).append((meta, log))
    recent = {a for a, (count, _) in busy.items() if count}
    names = sorted(set(owned) | recent, key=lambda a: (a not in owned, a))
    rows = []
    for agent in names:
        count, last = busy.get(agent, (0, None))
        pushes = f"{count} push{'es' if count != 1 else ''} this hour" if count else "quiet this hour"
        seen = f"<span class='m'>last push {ago(last)}</span>" if last else ""
        side = f"<div class='side'><span class='m'>{pushes}</span>{seen}</div>"
        work = owned.get(agent, [])
        if not work:
            rows.append(f"<li class='agent idle'><div class='row'>{who(agent)}<div class='body'>"
                        f"<p class='task none'>No claimed task</p></div>{side}</div></li>")
            continue
        for meta, log in work:
            flags = "".join(f"<span class='flag'>{f}</span>" for f in
                            (["stale"] if stale(meta) else []) + (["blocked"] if meta.get("status") == "blocked" else []))
            rows.append(
                f"<li class='agent'><details><summary class='row'>{who(agent)}<div class='body'>"
                f"<p class='task'><span class='id'>{html.escape(meta.get('id', ''))}</span>{html.escape(meta.get('title', ''))}{flags}</p>"
                f"{latest(log)}</div>{side}</summary>{details(meta, log)}</details></li>")
            side = "<div class='side'></div>"
    body = "".join(rows) or "<li class='empty'>Nobody is working right now.</li>"
    return f"<section><h2>Agents <span class='n'>{len(names)}</span></h2><ul class='list'>{body}</ul></section>"


def hints(meta: Dict[str, str], finished: set) -> List[str]:
    """Why an unclaimed task cannot be taken yet, mirroring board.py claim rules."""
    if meta.get("status") != "open":
        return []
    found = ["for humans"] if meta.get("owner", "").startswith("human:") or meta.get("title", "").startswith("Human:") else []
    waiting = [d.strip() for d in meta.get("depends", "").split(",") if d.strip() and d.strip() not in finished]
    return found + (["waits for " + ", ".join(waiting)] if waiting else [])


def tasks_section(title: str, items: List[Task], finished: set, folded: bool = False) -> str:
    if not items:
        return ""
    rows = "".join(
        f"<li><details><summary class='row plain'><span class='id'>{html.escape(m.get('id', ''))}</span>"
        f"<span class='title'>{html.escape(m.get('title', ''))}{''.join(f'<span class=hint>{html.escape(h)}</span>' for h in hints(m, finished))}</span>"
        f"<span class='side'>{who(m['owner']) if m.get('owner') else html.escape(ago(stamp(m.get('updated', ''))))}</span>"
        f"</summary>{details(m, log)}</details></li>" for m, log in items)
    head = f"{title} <span class='n'>{len(items)}</span>"
    if not folded:
        return f"<section><h2>{head}</h2><ul class='list compact'>{rows}</ul></section>"
    return (f"<section><details class='fold' id='fold-{title.lower()}'><summary><h2>{head}</h2></summary>"
            f"<ul class='list compact'>{rows}</ul></details></section>")


def page() -> str:
    refresh()
    all_tasks = tasks()
    assign_hues(all_tasks)
    unclaimed = [t for t in all_tasks if t[0].get("status") == "open"]
    finished = {m.get("id", "") for m, _ in all_tasks if m.get("status") == "done"}
    done = sorted((t for t in all_tasks if t[0].get("status") == "done"), key=lambda t: t[0].get("updated", ""), reverse=True)
    pin_text = git("show", f"{REF}:board/playtest.json")
    pin = json.loads(pin_text) if pin_text.strip() else None
    pin_line = (f"<div class='pin'><span class='k'>Playtest</span><code>{html.escape(pin['commit'][:7])}</code>"
                f"<span class='note'>{html.escape(pin.get('note', ''))}</span>"
                f"<span class='t'>{html.escape(pin.get('by', '?'))} · {html.escape(ago(stamp(pin.get('at', ''))))}</span></div>"
                if pin else "")
    head_hash, _, head_subject = git("log", "-1", "--format=%h %s", REF).strip().partition(" ")
    return f"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>SECHA board</title><style>
:root{{color-scheme:light dark;--bg:#fbfbfa;--text:#1b1d1f;--muted:#74797f;--faint:#a3a8ad;--line:#ececea;--hover:#f4f4f2;--accent:#c2410c}}
@media (prefers-color-scheme:dark){{:root{{--bg:#131416;--text:#e8e9ea;--muted:#8d9297;--faint:#61666b;--line:#232528;--hover:#1a1c1e;--accent:#fb923c}}}}
*{{box-sizing:border-box}}
body{{margin:0;background:var(--bg);color:var(--text);font:15px/1.5 -apple-system,BlinkMacSystemFont,system-ui,sans-serif;-webkit-font-smoothing:antialiased}}
main{{max-width:900px;margin:0 auto;padding:72px 24px 96px}}
header{{margin-bottom:56px}} h1{{font-size:22px;font-weight:600;letter-spacing:-.01em;margin:0 0 6px}}
.meta{{color:var(--muted);font-size:13px}} .meta code{{color:var(--text)}}
code,.id,.scope li{{font:12px ui-monospace,SFMono-Regular,Menlo,monospace}}
.pin{{display:flex;gap:10px;align-items:baseline;flex-wrap:wrap;margin-top:14px;font-size:13px;color:var(--muted)}}
.pin .note{{color:var(--text)}} .pin .t{{margin:0}}
section{{margin-bottom:48px}}
h2{{display:inline-flex;gap:8px;align-items:baseline;font-size:12px;font-weight:600;text-transform:uppercase;letter-spacing:.08em;color:var(--muted);margin:0 0 10px}}
.n{{color:var(--faint);font-weight:500}}
.list{{list-style:none;margin:0;padding:0}} .list>li{{border-top:1px solid var(--line)}} .list>li:last-child{{border-bottom:1px solid var(--line)}}
summary{{list-style:none;cursor:pointer}} summary::-webkit-details-marker{{display:none}}
.row{{display:grid;grid-template-columns:150px 1fr auto;gap:24px;padding:18px 10px;border-radius:6px}}
.row.plain{{grid-template-columns:52px 1fr auto;padding:12px 10px;align-items:baseline}}
summary.row:hover{{background:var(--hover)}}
.who{{display:inline-flex;align-items:center;gap:8px;height:22px;align-self:start;font-weight:600;white-space:nowrap}}
.who i{{width:8px;height:8px;border-radius:50%;background:hsl(var(--h));flex:none}}
.tool{{font-weight:400;color:var(--muted);font-size:13px}}
.body p{{margin:0}} .task{{font-weight:500}} .task.none{{color:var(--faint);font-weight:400}}
.id{{color:var(--faint);margin-right:10px}}
.last{{color:var(--muted);font-size:13px;margin-top:4px!important;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}}
.t{{color:var(--faint);font-size:12px;margin-left:8px;white-space:nowrap}}
.side{{color:var(--faint);font-size:12px;text-align:right;white-space:nowrap;line-height:1.7}} .side .m{{display:block}}
.idle{{opacity:.55}}
.flag{{font-size:11px;font-weight:600;color:var(--accent);margin-left:10px;text-transform:uppercase;letter-spacing:.06em}}
.compact .title{{font-size:14px}} .hint{{font-size:12px;color:var(--faint);margin-left:10px;white-space:nowrap}} .compact .side .who{{font-weight:500;font-size:13px}}
.more{{padding:0 10px 22px 184px;font-size:13px}} .compact .more{{padding-left:86px}}
.k{{font-size:11px;text-transform:uppercase;letter-spacing:.08em;color:var(--faint);margin:12px 0 4px}}
.pin .k{{margin:0}} .more .k:first-child{{margin-top:0}}
.more ul{{list-style:none;margin:0;padding:0;color:var(--muted)}} .more li{{padding:2px 0}}
.entries li{{display:grid;grid-template-columns:80px 1fr}} .entries .t{{margin:0}}
.fold>summary{{display:flex}} .fold>summary h2::after{{content:"show";margin-left:6px;text-transform:none;letter-spacing:0;font-weight:400;color:var(--faint)}}
.fold[open]>summary h2::after{{content:"hide"}} .fold>summary:hover h2::after{{color:var(--text)}}
.empty{{padding:18px 10px;color:var(--faint)}}
@media (max-width:640px){{main{{padding:40px 16px 64px}} header{{margin-bottom:40px}}
.row{{grid-template-columns:1fr;gap:6px}} .row.plain{{grid-template-columns:44px 1fr}} .row.plain .side{{display:none}}
.side{{text-align:left}} .side .m{{display:inline}} .side .m+.m::before{{content:" · "}} .more,.compact .more{{padding-left:10px}}}}
</style></head><body><main id="board">
<header><h1>SECHA board</h1><div class="meta">main <code>{html.escape(head_hash)}</code> · {html.escape(head_subject)}</div>{pin_line}</header>
{agents_section(all_tasks)}
{tasks_section("Unclaimed", unclaimed, finished)}
{tasks_section("Done", done, finished, folded=True)}
</main><script>
// Swap in fresh content every 10 s, keeping whichever rows and folds are expanded.
const key = d => d.id || d.querySelector(".id")?.textContent;
setInterval(async () => {{
  try {{
    const open = new Set([...document.querySelectorAll("details[open]")].map(key));
    const doc = new DOMParser().parseFromString(await (await fetch(location.href)).text(), "text/html");
    doc.querySelectorAll("details").forEach(d => {{ if (open.has(key(d))) d.open = true; }});
    document.getElementById("board").replaceWith(doc.getElementById("board"));
  }} catch (e) {{}}
}}, 10000);
</script></body></html>"""


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
