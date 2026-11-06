import { DurableObject } from "cloudflare:workers";

const actorPattern = /^(?:human:[a-z0-9]+|[a-z0-9]+-[a-z0-9]+-[1-9][0-9]*)$/;
const tokenPattern = /^[0-9a-f]{64}$/;
const taskPattern = /^H-(\d{3,12})$/;
const staleAfter = 3 * 60 * 60 * 1000;
const areas = ["gameplay", "world", "art", "tools", "shared"];
const privateHeaders = { "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff" };

class Rejected extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

function reject(status, message) {
  throw new Rejected(status, message);
}

function json(value, status = 200, headers = {}) {
  return Response.json(value, { status, headers: { ...privateHeaders, ...headers } });
}

async function handle(run) {
  try {
    return await run();
  } catch (error) {
    if (error instanceof Rejected) return json({ error: error.message }, error.status);
    console.error(error);
    return json({ error: "Board request failed. Try again." }, 500);
  }
}

async function payload(request) {
  if (request.headers.get("Content-Type")?.split(";")[0].trim() !== "application/json")
    reject(415, "Send an application/json body.");
  if (!request.body) reject(400, "Send a JSON object.");
  const reader = request.body.getReader();
  const bytes = new Uint8Array(16_384);
  let length = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    if (length + value.length > bytes.length) {
      await reader.cancel();
      reject(413, "JSON is limited to 16 KiB.");
    }
    bytes.set(value, length);
    length += value.length;
  }
  let value;
  try {
    value = JSON.parse(new TextDecoder().decode(bytes.subarray(0, length)));
  } catch {
    reject(400, "Send valid JSON.");
  }
  if (!value || typeof value !== "object" || Array.isArray(value)) reject(400, "Send a JSON object.");
  return value;
}

function field(value, name, max, required = false) {
  if (value == null && !required) return "";
  if (typeof value !== "string" || value.trim().length > max || (required && !value.trim()))
    reject(400, `${name} must be ${required ? "nonempty " : ""}text of at most ${max} characters.`);
  return value.trim();
}

function items(value, name, check) {
  if (value == null) return [];
  if (!Array.isArray(value) || value.length > 20 || value.some((entry) => typeof entry !== "string" || !check(entry)))
    reject(400, `${name} must contain at most 20 valid entries.`);
  return [...new Set(value)];
}

function validPath(path) {
  return path.length <= 240 && /^[\w./-]+$/.test(path) &&
    path.replace(/\/$/, "").split("/").every((part) => part && part !== "." && part !== "..");
}

function person(actor) {
  return actor.startsWith("human:") ? actor.slice(6) : actor.split("-")[0];
}

async function identify(env, token) {
  if (!tokenPattern.test(token)) return null;
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token));
  const hash = Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
  const keys = JSON.parse(env.BOARD_KEYS ?? "{}");
  const actor = keys[hash];
  return typeof actor === "string" && actorPattern.test(actor) ? actor : null;
}

const sessionCookie = "__Host-secha_board";
function cookie(token, age) {
  return `${sessionCookie}=${token}; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=${age}`;
}

export default {
  async fetch(request, env) {
    return handle(async () => {
      const url = new URL(request.url);
      const { pathname } = url;
      if (request.method === "GET" && ["/", "/board.js", "/board.css"].includes(pathname)) {
        const asset = await env.ASSETS.fetch(request);
        const headers = new Headers(asset.headers);
        headers.set("Content-Security-Policy", "default-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'");
        headers.set("X-Content-Type-Options", "nosniff");
        headers.set("Referrer-Policy", "no-referrer");
        return new Response(asset.body, { status: asset.status, headers });
      }
      if (pathname === "/session" && ["POST", "DELETE"].includes(request.method)) {
        if (request.headers.get("Origin") !== url.origin) reject(403, "Wrong request origin.");
        if (request.method === "DELETE") return json({}, 200, { "Set-Cookie": cookie("", 0) });
        const { token } = await payload(request);
        const actor = await identify(env, typeof token === "string" ? token : "");
        if (!actor) reject(401, "Invalid board key.");
        return json({ actor }, 200, { "Set-Cookie": cookie(token, 28_800) });
      }
      if (!pathname.startsWith("/api/")) reject(404, "Route not found.");
      const authorization = request.headers.get("Authorization");
      const bearer = authorization?.match(/^Bearer ([0-9a-f]{64})$/i)?.[1];
      const session = request.headers.get("Cookie")?.match(/(?:^|;\s*)__Host-secha_board=([0-9a-f]{64})(?:;|$)/)?.[1];
      const actor = await identify(env, (authorization ? bearer : session) ?? "");
      if (!actor) reject(401, "A board key is required.");
      if (!bearer && request.method !== "GET" && request.headers.get("Origin") !== url.origin)
        reject(403, "Wrong request origin.");
      const board = env.BOARD.getByName("secha");
      return board.fetch(request, { headers: { "Content-Type": request.headers.get("Content-Type") ?? "", "X-Board-Actor": actor } });
    });
  },
};

export class Board extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.storage = ctx.storage;
    this.sql = ctx.storage.sql;
    this.sql.exec("CREATE TABLE IF NOT EXISTS tasks (id INTEGER PRIMARY KEY, record TEXT NOT NULL)");
    this.sql.exec("CREATE TABLE IF NOT EXISTS messages (id INTEGER PRIMARY KEY, sender TEXT NOT NULL, sender_person TEXT NOT NULL, recipient TEXT NOT NULL, task TEXT, text TEXT NOT NULL, at TEXT NOT NULL)");
  }

  task(id) {
    const row = this.sql.exec("SELECT record FROM tasks WHERE id = ?", Number(taskPattern.exec(id)?.[1])).toArray()[0];
    const record = row && JSON.parse(row.record);
    if (record?.id !== id) reject(404, "Task not found.");
    return record;
  }

  create(body, actor, now) {
    const title = field(body.title, "Title", 200, true);
    const scope = items(body.scope, "Scope", validPath);
    const depends = items(body.depends, "Dependencies", (entry) => taskPattern.test(entry));
    const area = body.area ?? "shared";
    if (!areas.includes(area)) reject(400, "Unknown area.");
    const goal = field(body.goal, "Goal", 2000);
    const doneWhen = field(body.doneWhen, "Done when", 2000);
    const forWho = field(body.forWho, "Reserved for", 60);
    if (forWho && !/^human:[a-z0-9]+$/.test(forWho)) reject(400, "Use human:<person> to reserve a task.");
    return this.storage.transactionSync(() => {
      for (const id of depends) this.task(id);
      const { next } = this.sql.exec("SELECT COALESCE(MAX(id), 0) + 1 AS next FROM tasks").one();
      const id = `H-${String(next).padStart(3, "0")}`;
      const record = {
        id, title, scope, depends, area, goal, doneWhen, forWho, status: "open", owner: null, ownerActive: null,
        updated: now, log: [{ at: now, actor, action: "created" }],
      };
      this.sql.exec("INSERT INTO tasks VALUES (?, ?)", next, JSON.stringify(record));
      return record;
    });
  }

  change(id, action, body, actor, now) {
    const note = field(body.text, "Note", 2000, action === "note" || action === "block");
    return this.storage.transactionSync(() => {
      const task = this.task(id);
      const previous = task.owner;
      let text = note;
      if (action !== "note" && task.status === "done") reject(409, "This task is done.");
      if (action === "claim") {
        if (task.forWho && task.forWho !== actor) reject(403, `Reserved for ${task.forWho}.`);
        const waiting = task.depends.filter((dep) => this.task(dep).status !== "done");
        if (waiting.length) reject(409, `Waiting for ${waiting.join(", ")}.`);
        if (previous && previous !== actor) {
          const stale = task.status === "claimed" && Date.parse(now) - Date.parse(task.ownerActive) >= staleAfter;
          if (!stale || body.steal !== true) reject(409, `Owned by ${previous}.${stale ? " Use an explicit stale claim." : ""}`);
          text = `Taken over from ${previous}.`;
        }
        Object.assign(task, { owner: actor, ownerActive: now, status: "claimed" });
      } else if (action !== "note") {
        if (previous !== actor) reject(403, "Only the task owner can do that.");
        const status = { release: "open", block: "blocked", done: "done" }[action];
        Object.assign(task, { status, owner: status === "open" ? null : actor, ownerActive: status === "open" ? null : now });
      } else if (previous === actor) {
        task.ownerActive = now;
      }
      task.updated = now;
      // ponytail: keep the latest 100 entries on each task; split logs out if tasks need longer history.
      task.log = [...task.log, { at: now, actor, action, ...(text ? { text } : {}) }].slice(-100);
      this.sql.exec("UPDATE tasks SET record = ? WHERE id = ?", JSON.stringify(task), Number(taskPattern.exec(id)[1]));
      return task;
    });
  }

  async fetch(request) {
    return handle(async () => {
      const { pathname, searchParams } = new URL(request.url);
      const actor = request.headers.get("X-Board-Actor");
      if (!actor || !actorPattern.test(actor)) reject(403, "Unknown actor.");
      const method = request.method;
      const now = new Date().toISOString();
      if (pathname === "/api/me" && method === "GET") return json({ actor, areas });
      if (pathname === "/api/tasks") {
        if (method === "POST") return json(this.create(await payload(request), actor, now), 201);
        if (method === "GET") {
          return json(this.sql.exec("SELECT record FROM tasks ORDER BY id DESC").toArray().map(({ record }) => {
            const { log, ...summary } = JSON.parse(record);
            return { ...summary, stale: summary.status === "claimed" && Date.parse(now) - Date.parse(summary.ownerActive) >= staleAfter };
          }));
        }
      }
      const taskRoute = /^\/api\/tasks\/(H-\d{3,12})(?:\/(claim|note|done|block|release))?$/.exec(pathname);
      if (taskRoute) {
        const [, id, action] = taskRoute;
        if (!action && method === "GET") return json(this.task(id));
        if (action && method === "POST") return json(this.change(id, action, await payload(request), actor, now));
      }
      if (pathname === "/api/messages") {
        if (method === "GET") {
          const raw = searchParams.get("after");
          const after = Number(raw ?? 0);
          if (!Number.isSafeInteger(after) || after < 0) reject(400, "Invalid message cursor.");
          const order = raw === null ? "DESC" : "ASC";
          const messages = this.sql.exec(`SELECT id, sender, recipient, task, text, at FROM messages
            WHERE id > ? AND (sender = ? OR sender_person = ? OR recipient IN (?, ?, ?, 'all'))
            ORDER BY id ${order} LIMIT 100`,
            after, actor, person(actor), actor, person(actor), `human:${person(actor)}`).toArray();
          if (raw === null) messages.reverse();
          return json({ messages, cursor: messages.at(-1)?.id ?? after });
        }
        if (method === "POST") {
          const body = await payload(request);
          const to = field(body.to, "Recipient", 60, true);
          if (!actorPattern.test(to) && !/^[a-z0-9]+$/.test(to)) reject(400, "Use a person, agent name, or all.");
          const task = field(body.task, "Task", 20);
          if (task && !taskPattern.test(task)) reject(400, "Invalid task ID.");
          if (task) this.task(task);
          const text = field(body.text, "Message", 2000, true);
          const message = this.sql.exec(`INSERT INTO messages (sender, sender_person, recipient, task, text, at)
            VALUES (?, ?, ?, ?, ?, ?) RETURNING id, sender, recipient, task, text, at`,
            actor, person(actor), to, task || null, text, now).one();
          return json(message, 201);
        }
      }
      reject(404, "Route not found.");
    });
  }
}
