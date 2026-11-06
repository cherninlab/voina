"""Run against a fresh local Wrangler instance. Uses public, local-only test keys."""
from concurrent.futures import ThreadPoolExecutor
from hashlib import sha256
from http.client import HTTPConnection
from json import dumps, loads
import sys


ACTORS = {"theo-codex-1": "1" * 64, "alex-codex-1": "2" * 64, "human:theo": "3" * 64}
if sys.argv[1:] == ["--keys"]:
    print(dumps({sha256(token.encode()).hexdigest(): actor for actor, token in ACTORS.items()}))
    sys.exit()
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8787


def request(path, actor=None, body=None, *, method=None, expected=200, headers=None):
    headers = dict(headers or {})
    if actor:
        headers["Authorization"] = "Bearer " + ACTORS[actor]
    if body is not None:
        headers["Content-Type"] = "application/json"
    connection = HTTPConnection("127.0.0.1", PORT, timeout=10)
    try:
        connection.request(method or ("POST" if body is not None else "GET"), path,
                           dumps(body) if body is not None else None, headers)
        result = connection.getresponse()
        data = result.read()
        if expected is not None:
            assert result.status == expected, (path, result.status, data[:200])
        return result.status, dict(result.getheaders()), loads(data) if path != "/" else data
    finally:
        connection.close()


theo, alex, human = ACTORS
assert b"SECHA Agent Board" in request("/")[2]
request("/api/me", expected=401, headers={"X-Board-Actor": human})
assert request("/api/me", alex, headers={"X-Board-Actor": human})[2]["actor"] == alex
request("/api/tasks", theo, {"title": "Oversize", "goal": "x" * 17_000}, expected=413)
request("/api/tasks", theo, {"title": "Invalid scope", "scope": ["../outside"]}, expected=400)
first = request("/api/tasks", theo, {"title": "Map handoff", "scope": ["content/environments/"]}, expected=201)[2]["id"]
second = request("/api/tasks", theo, {"title": "Review", "depends": [first]}, expected=201)[2]["id"]
third = request("/api/tasks", human, {"title": "Human approval", "forWho": human}, expected=201)[2]["id"]
request(f"/api/tasks/{second}/claim", alex, {}, expected=409)
request(f"/api/tasks/{third}/claim", theo, {}, expected=403)
request(f"/api/tasks/{third}/claim", human, {})
with ThreadPoolExecutor(2) as pool:
    result = list(pool.map(lambda actor: request(f"/api/tasks/{first}/claim", actor, {}, expected=None)[0], (theo, alex)))
assert sorted(result) == [200, 409], result
owner, other = (theo, alex) if result[0] == 200 else (alex, theo)
request(f"/api/tasks/{first}/done", other, {}, expected=403)
request(f"/api/tasks/{first}/claim", other, {"steal": True}, expected=409)
activity = request(f"/api/tasks/{first}", owner)[2]["ownerActive"]
request(f"/api/tasks/{first}/note", other, {"text": "Review ready"})
assert request(f"/api/tasks/{first}", owner)[2]["ownerActive"] == activity
request(f"/api/tasks/{first}/block", owner, {"text": "Need map reference"})
request(f"/api/tasks/{first}/release", owner, {})
request(f"/api/tasks/{first}/claim", owner, {})
request(f"/api/tasks/{first}/done", owner, {"text": "Reviewed"})
request(f"/api/tasks/{second}/claim", other, {})
assert request(f"/api/tasks/{first}", owner)[2]["scope"] == ["content/environments/"]

request("/api/messages", theo, {"to": "alex", "task": first, "text": "Review available"}, expected=201)
assert request("/api/messages", alex)[2]["messages"][-1]["task"] == first
request("/api/messages", human, {"to": "outsider", "text": "Recipient visibility check"}, expected=201)
assert all(message["recipient"] != "outsider" for message in request("/api/messages", alex)[2]["messages"])
cursor = request("/api/messages", alex)[2]["cursor"]
assert not request(f"/api/messages?after={cursor}", alex)[2]["messages"]

origin = f"http://127.0.0.1:{PORT}"
request("/session", body={"token": ACTORS[human]}, expected=403, headers={"Origin": "https://foreign.invalid"})
_, session, _ = request("/session", body={"token": ACTORS[human]}, headers={"Origin": origin})
cookie = next(value for key, value in session.items() if key.lower() == "set-cookie")
assert all(flag in cookie for flag in ("HttpOnly", "Secure", "SameSite=Strict"))
headers = {"Cookie": cookie.split(";")[0]}
assert request("/api/me", headers=headers)[2]["actor"] == human
request("/api/tasks", body={"title": "Foreign origin"}, headers=headers, expected=403)
request("/session", method="DELETE", headers={**headers, "Origin": origin})

legacy = {
    "id": "T-999998", "title": "Human: review", "status": "open", "owner": "", "updated": "2026-10-16T19:15Z",
    "scope": ["docs/"], "depends": [], "humanOnly": True, "legacyMarkdown": "Original task and log",
}
route = "/api/admin/import-legacy"
request(route, theo, {"tasks": [legacy]}, expected=403)
assert request(route, human, {"tasks": [legacy]})[2]["inserted"] == 1
assert request(route, human, {"tasks": [legacy]})[2]["unchanged"] == 1
task = request("/api/tasks/T-999998", human)[2]
assert task["labels"] == ["legacy"] and task["legacyMarkdown"] == legacy["legacyMarkdown"]
request("/api/tasks/T-999998/claim", theo, {}, expected=403)
next_task = request("/api/tasks", theo, {"title": "After review", "depends": ["T-999998"]}, expected=201)[2]["id"]
request(f"/api/tasks/{next_task}/claim", theo, {}, expected=409)
request("/api/tasks/T-999998/claim", human, {})
request("/api/tasks/T-999998/done", human, {})
request(f"/api/tasks/{next_task}/claim", theo, {})
request(route, human, {"tasks": [{**legacy, "id": "T-999999"}, {**legacy, "legacyMarkdown": "Git changed"}]}, expected=409)
request("/api/tasks/T-999999", human, expected=404)
assert request("/api/tasks/T-999998", human)[2]["status"] == "done"
print("Hosted board OK: authentication, claims, dependencies, lifecycle, inbox, browser session and legacy import")
