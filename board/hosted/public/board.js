const byId = (id) => document.getElementById(id);
let selected;
let signedIn = false;
let busy = false;

async function api(path, { method = "GET", body } = {}) {
  const options = { method };
  if (body) {
    options.headers = { "Content-Type": "application/json" };
    options.body = JSON.stringify(body);
  }
  const response = await fetch(path, options);
  if (response.status === 401 && path !== "/session") showSession(false);
  const result = await response.json();
  if (!response.ok) throw new Error(result.error);
  return result;
}

function showSession(active) {
  signedIn = active;
  selected = undefined;
  byId("login").hidden = active;
  byId("board").hidden = !active;
  byId("tasks").replaceChildren();
  byId("history").replaceChildren();
  byId("messages").replaceChildren();
  byId("action").hidden = true;
  byId("taskText").textContent = "Select a task.";
  if (!active) for (const id of ["create", "action", "message"]) byId(id).reset();
}

function list(id, lines) {
  byId(id).replaceChildren(...lines.map((line) => {
    const item = document.createElement("li");
    item.textContent = line;
    return item;
  }));
}

async function refresh() {
  const [tasks, inbox, task] = await Promise.all([
    api("/api/tasks"), api("/api/messages"), selected ? api(`/api/tasks/${selected}`) : null,
  ]);
  const focused = document.activeElement?.dataset.task;
  byId("tasks").replaceChildren(...tasks.map((entry) => {
    const button = document.createElement("button");
    button.type = "button";
    button.dataset.task = entry.id;
    button.setAttribute("aria-current", String(entry.id === selected));
    button.textContent = `${entry.id} · ${entry.title} · ${entry.status}${entry.stale ? " (stale)" : ""}${entry.owner ? " · " + entry.owner : ""}`;
    button.addEventListener("click", () => run(async () => { selected = entry.id; await refresh(); }));
    return button;
  }));
  if (focused) byId("tasks").querySelector(`[data-task="${focused}"]`)?.focus();
  list("messages", inbox.messages.toReversed().map((message) =>
    `${new Date(message.at).toLocaleString()} · ${message.sender} → ${message.recipient}${message.task ? " · " + message.task : ""}\n${message.text}`));
  if (task) {
    byId("taskText").textContent = [
      `${task.id} · ${task.title}`, `${task.area} · ${task.status}${task.owner ? " · " + task.owner : ""}`,
      task.goal, task.doneWhen && "Done when: " + task.doneWhen, task.forWho && "Reserved for: " + task.forWho,
      task.scope.length && "Scope: " + task.scope.join(", "), task.depends.length && "Waits for: " + task.depends.join(", "),
    ].filter(Boolean).join("\n");
    list("history", task.log.toReversed().map((entry) =>
      `${new Date(entry.at).toLocaleString()} · ${entry.actor} · ${entry.action}${entry.text ? "\n" + entry.text : ""}`));
    byId("action").hidden = false;
  }
}

async function open() {
  const me = await api("/api/me");
  showSession(true);
  byId("actor").textContent = me.actor;
  byId("create").elements.area.replaceChildren(...me.areas.map((area) => new Option(area, area)));
  byId("create").elements.area.value = "shared";
  await refresh();
}

async function run(operation) {
  if (busy) return;
  busy = true;
  const controls = [...document.querySelectorAll("form button, .toolbar button")];
  const focused = document.activeElement;
  for (const control of controls) control.disabled = true;
  byId("notice").textContent = "";
  try {
    await operation();
  } catch (error) {
    byId("notice").textContent = error.message;
  } finally {
    busy = false;
    for (const control of controls) control.disabled = false;
    if (controls.includes(focused) && document.activeElement === document.body && focused.getClientRects().length)
      focused.focus();
  }
}

function form(id, action) {
  byId(id).addEventListener("submit", (event) => {
    event.preventDefault();
    const element = event.currentTarget;
    const values = Object.fromEntries(new FormData(element));
    run(() => action(values, element));
  });
}
form("login", async ({ token }, element) => {
  await api("/session", { method: "POST", body: { token } });
  element.reset();
  await open();
});
form("create", async (body, element) => {
  const csv = (text) => text.split(",").map((item) => item.trim()).filter(Boolean);
  const task = await api("/api/tasks", { method: "POST", body: { ...body, scope: csv(body.scope), depends: csv(body.depends) } });
  element.reset();
  element.elements.area.value = "shared";
  selected = task.id;
  await refresh();
});
form("action", async ({ action, text, steal }, element) => {
  await api(`/api/tasks/${selected}/${action}`, { method: "POST", body: { text, steal: steal === "on" } });
  element.reset();
  await refresh();
});
form("message", async (body, element) => {
  await api("/api/messages", { method: "POST", body });
  element.reset();
  await refresh();
});
byId("refresh").addEventListener("click", () => run(refresh));
byId("logout").addEventListener("click", () => run(async () => {
  await api("/session", { method: "DELETE" });
  showSession(false);
}));
run(async () => {
  try {
    await open();
  } catch (error) {
    if (signedIn || byId("login").hidden) throw error;
  }
});
