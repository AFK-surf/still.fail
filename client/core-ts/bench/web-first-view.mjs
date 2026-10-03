// The first view from a large dataset in Chrome (docs/core-db.md, Measurements): the core's worker of a web build
// (`build:cloud`'s dist) served here with no still.fail cloud behind it, its IndexedDB seeded as the core before the
// databases per account kept it (the same dataset as first-view.ts: 20 stations × 2 000 chats, sessions and threads,
// 100 000 entries), then started by a bare page that subscribes the chat list as the app does (no UI drawing it):
// when the core's first chat list with rows reached the page, when its last change did, and the renderer's memory
// (the worker's). This core imports the former store on its first open (`import` runs that once).
//
//   node web-first-view.mjs <dist dir> <port> <profile dir> seed|run|import
// (playwright-core from where it is installed; Google Chrome.)
import { createServer } from "node:http";
import { readFileSync, readdirSync, existsSync, statSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { extname, join } from "node:path";
import { chromium } from "playwright-core";

const [, , dist, portArg, profile, mode] = process.argv;
const port = Number(portArg);
const TYPES = { ".html": "text/html", ".js": "text/javascript", ".mjs": "text/javascript", ".css": "text/css", ".wasm": "application/wasm", ".json": "application/json", ".svg": "image/svg+xml", ".png": "image/png", ".woff2": "font/woff2" };
const worker = readdirSync(join(dist, "assets")).find((f) => f.startsWith("worker-") && f.endsWith(".js"));
/// The page that starts the core's worker and subscribes as the app's client does.
const BENCH = `<!doctype html><script type="module">
const seen = (window.__fv = { first: null, last: null, rows: 0, messages: 0 });
const rowsOf = (days) => (days ?? []).reduce((n, d) => n + (d.items?.length ?? 0), 0);
// The deltas as the app applies them (client/core-ts/src/collections.ts applyKeyed).
const isObj = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const keyOf = (item, f) => { const v = (k) => (isObj(item) && item[k] !== undefined ? item[k] : null); return f.length === 1 ? v(f[0]) : f.map(v); };
const text = (k) => JSON.stringify(k);
const apply = (value, ops) => ops.reduce((v, op) => one(v, op, 0), value);
function one(node, op, depth) {
  if (depth === op.path.length) {
    if ("key" in op) return Array.isArray(node) ? list(node, op) : node;
    if ("set" in op) return op.set;
    if ("append" in op) return Array.isArray(node) ? [...node, ...op.append] : node;
    return node;
  }
  const key = op.path[depth];
  if (Array.isArray(node)) { if (typeof key !== "number" || key >= node.length) return node; const c = node.slice(); c[key] = one(node[key], op, depth + 1); return c; }
  if (!isObj(node) || typeof key !== "string") return node;
  if ("remove" in op && depth === op.path.length - 1) { const r = { ...node }; delete r[key]; return r; }
  if (!(key in node) && !("set" in op && depth === op.path.length - 1)) return node;
  return { ...node, [key]: one(node[key], op, depth + 1) };
}
function list(l, op) {
  const find = (k) => l.findIndex((x) => text(keyOf(x, op.key)) === text(k));
  const out = l.slice();
  const place = (item, before) => { const at = before === null ? -1 : out.findIndex((x) => text(keyOf(x, op.key)) === text(before)); if (at < 0) out.push(item); else out.splice(at, 0, item); };
  if ("drop" in op) { const i = find(op.drop); if (i >= 0) out.splice(i, 1); }
  else if ("patch" in op) { const i = find(op.patch); if (i >= 0) out[i] = apply(out[i], op.ops); }
  else if ("move" in op) { const i = find(op.move); if (i < 0) return l; const [x] = out.splice(i, 1); place(x, op.before); }
  else { const i = find(keyOf(op.put, op.key)); if (i >= 0 && op.before === undefined) out[i] = op.put; else { if (i >= 0) out.splice(i, 1); place(op.put, op.before ?? null); } }
  return out;
}
let value;
const w = new Worker("/assets/${worker}", { type: "module", name: "stillfail-core-bench" });
w.onmessage = (event) => {
  const m = event.data;
  if (!m || m.id !== 1) return;
  if ("value" in m) value = m.value;
  else if (Array.isArray(m.delta)) value = apply(value, m.delta);
  else return;
  const rows = rowsOf(value?.days);
  seen.messages++;
  const at = Math.round(performance.now());
  seen.rows = rows;
  if (seen.first === null && rows > 0) seen.first = { ms: at, rows };
  seen.last = at;
};
w.postMessage({ id: 1, subscribe: { topic: "chats", scope: "w", mine: false }, keyed: true });
</script>`;
const server = createServer((req, res) => {
  const path = decodeURIComponent(new URL(req.url, "http://x").pathname);
  if (path === "/__bench") {
    res.writeHead(200, { "content-type": "text/html" }).end(BENCH);
    return;
  }
  if (path.startsWith("/v1/") || path.startsWith("/__")) {
    res.writeHead(503).end("no cloud");
    return;
  }
  let file = join(dist, path);
  if (!existsSync(file) || statSync(file).isDirectory()) file = join(dist, "index.html");
  res.writeHead(200, { "content-type": TYPES[extname(file)] ?? "application/octet-stream" }).end(readFileSync(file));
}).listen(port, "127.0.0.1");

const origin = `http://127.0.0.1:${port}`;
const context = await chromium.launchPersistentContext(profile, {
  executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  headless: true,
  viewport: { width: 1440, height: 900 },
  args: ["--disable-features=LocalNetworkAccessChecks,PrivateNetworkAccessChecks"],
});
const page = context.pages()[0] ?? (await context.newPage());

if (mode === "seed") {
  await page.goto(`${origin}/robots-none`);
  const t0 = Date.now();
  const seeded = await page.evaluate(seedPage);
  console.log(JSON.stringify({ seeded, ms: Date.now() - t0 }));
} else {
  await page.goto(`${origin}/__bench`);
  // Quiet for 5 s once its rows came (or 3 minutes): the whole list is there.
  for (let waited = 0; waited < 180_000; waited += 500) {
    await page.waitForTimeout(500);
    if (await page.evaluate(() => window.__fv.first !== null && performance.now() - window.__fv.last > 5000)) break;
  }
  const fv = await page.evaluate(() => window.__fv);
  const renderers = execFileSync("ps", ["-ax", "-o", "rss=,command="], { encoding: "utf8" })
    .split("\n")
    .filter((l) => l.includes(profile) && l.includes("--type=renderer"))
    .map((l) => Number(l.trim().split(/\s+/)[0]) / 1024);
  const persisted = await page.evaluate(() => navigator.storage.persisted());
  const usage = await page.evaluate(async () => Math.round((await navigator.storage.estimate()).usage / 1024 / 1024));
  console.log(JSON.stringify({ mode, first: fv.first, whole: { ms: fv.last, rows: fv.rows, messages: fv.messages }, rendererRssMB: renderers.map((m) => Math.round(m)), storageMB: usage, persisted }));
}
await context.close();
server.close();

/// Runs in the page: the former store (IndexedDB stillfail-core v2: `values`, `records`) as the core before kept it.
async function seedPage() {
  const STATIONS = 20, PER = 2000, ENTRIES = 100000, SUB = "bench-account", WS = "w", NOW = Date.UTC(2026, 9, 3, 12), SEP = "\u0001";
  const enc = new TextEncoder();
  const bytes = (v) => enc.encode(JSON.stringify(v));
  const db = await new Promise((resolve, reject) => {
    const r = indexedDB.open("stillfail-core", 2);
    r.onupgradeneeded = () => {
      for (const s of ["values", "records"]) if (!r.result.objectStoreNames.contains(s)) r.result.createObjectStore(s);
    };
    r.onsuccess = () => resolve(r.result);
    r.onerror = () => reject(r.error);
  });
  const batch = [];
  const flush = async () => {
    const items = batch.splice(0);
    await new Promise((resolve, reject) => {
      const tx = db.transaction(["values", "records"], "readwrite");
      for (const [store, key, value] of items) tx.objectStore(store).put(value, key);
      tx.oncomplete = resolve;
      tx.onerror = () => reject(tx.error);
    });
  };
  const rec = async (tbl, key, value) => {
    batch.push(["records", [tbl, key], bytes(value)]);
    if (batch.length >= 5000) await flush();
  };
  const nowS = Math.floor(Date.now() / 1000);
  batch.push(["values", "accounts", bytes([{ sub: SUB, email: "me@x.com", name: "我", picture: "", access: "a", refresh: "r", access_expires: nowS + 365 * 86400 }])]);
  await rec("me", SUB, { workspaces: [{ id: WS, name: "Bench" }], invitations: [], relay_url: null, user: { email: "me@x.com" } });
  await rec("workspace", WS, { id: WS, name: "Bench", role: "owner", members: [{ email: "me@x.com", name: "我", role: "owner" }], stations: Array.from({ length: STATIONS }, (_, i) => ({ id: `s${String(i).padStart(2, "0")}`, name: `station ${i}`, online: true, last_seen: nowS, version: "0.1.0" })) });
  const perThread = Math.floor(ENTRIES / STATIONS / PER), extra = (ENTRIES / STATIONS) % PER;
  let entries = 0;
  for (let s = 0; s < STATIONS; s++) {
    const st = `${WS}/s${String(s).padStart(2, "0")}`;
    await rec("overview", st, { viewer: { via: "local" }, connects: [], profiles: [], processes: [], counts: { sessions: PER, running: 0, warm: 0 }, mesh: null, slackUsers: [], slackTeams: [], slackApps: [], disk: null, logins: [] });
    await rec("list", `row${SEP}${st}`, Array.from({ length: PER }, (_, i) => `k${i}`));
    await rec("list", `session_summary${SEP}${st}`, Array.from({ length: PER }, (_, i) => `k${i}`));
    await rec("list", `thread${SEP}${st}`, Array.from({ length: PER }, (_, i) => String(i)));
    for (let i = 0; i < PER; i++) {
      const key = `k${i}`, n = i < extra ? perThread + 1 : perThread;
      await rec("row", `${st}${SEP}${key}`, {
        id: key, session: key, thread: i, title: `第 ${i} 个对话：排查 ${st} 上的构建`, mine: i % 3 === 0, unread: i % 7 === 0, connect: null, origin: null, lastActiveAt: NOW - i * 60000, pinned: i < 2 ? NOW - i : undefined,
        agents: [{ key, runtime: "claude", model: "claude-opus-4-1", effort: null, process: i % 50 === 0 ? "running" : "warm", pending: 0, lastTurn: { kind: "chat", declared: "final", outcome: "completed", detail: null, startedAt: NOW - i * 60000 - 5000, endedAt: NOW - i * 60000 } }],
        last: { seq: 3, thread: i, ts: `${i}.3`, authorKind: "agent", author: key, authorName: null, text: `好的，已经改完了第 ${i} 处，测试都过了。`, attachments: [], quotes: [], declared: "final", createdAt: NOW - i * 60000, editedAt: null, agentIdentity: { model: "claude-opus-4-1" } },
      });
      await rec("session_summary", `${st}${SEP}${key}`, { key, connect: "ember", scope: "thread", title: null, createdBy: null, boundTo: [], creator: null, participants: [], runtime: "claude", profile: "p1", profilePinned: false, model: "claude-opus-4-1", effort: null, runtimeSessionId: `rs-${i}`, workspace: `/w/${i}`, running: false, createdAt: NOW - i * 3600000, lastActiveAt: NOW - i * 60000, archivedAt: null, process: "warm", turns: 3, pending: 0, firstText: `帮我看看第 ${i} 个问题`, lastTurn: { kind: "chat", outcome: "completed", declared: "final", detail: null, startedAt: NOW - i * 60000 - 5000, endedAt: NOW - i * 60000 } });
      await rec("thread", `${st}${SEP}${i}`, { id: i, surface: "ember", channel: "EMBER", channelName: null, threadTs: `${i}.0`, title: null, createdBy: null, creator: { id: "me@x.com", name: "我" }, createdAt: NOW - i * 3600000, sessions: [{ thread: i, session: key, connect: "ember", joinedAt: NOW - i * 3600000 }], last: n, read: n, unread: 0, people: [], lastMessage: { seq: n, thread: i, ts: `${i}.${n}`, authorKind: "agent", author: key, authorName: null, text: "好的，已经改完了。", attachments: [], quotes: [], declared: "final", createdAt: NOW - i * 60000, editedAt: null }, firstText: `帮我看看第 ${i} 个问题` });
      for (let e = 1; e <= n; e++) {
        await rec("entry", `${st}${SEP}${i}${SEP}${String(e).padStart(12, "0")}`, { thread: i, n: e, kind: "message", seq: e, ts: `${i}.${e}`, authorKind: e % 2 ? "person" : "agent", author: e % 2 ? "me@x.com" : key, authorName: null, text: `第 ${e} 条消息：${"这是一段普通长度的回复，说明做了什么、为什么。".repeat(2)}`, attachments: [], quotes: [], declared: null, createdAt: NOW - e * 1000, editedAt: null });
        entries++;
      }
    }
  }
  await flush();
  db.close();
  return { stations: STATIONS, entries };
}
