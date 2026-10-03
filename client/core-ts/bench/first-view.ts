// The first view from a large dataset (docs/core-db.md, Measurements): 20 stations × 2 000 chats, sessions and
// threads, 100 000 entries, one account. The same script runs against this tree and against a checkout of the core
// before the databases per account (it seeds the former records store, which that core reads and this one imports).
//
//   node --expose-gc bench/first-view.ts seed <dir>     the former records store (core.db) and a signed-in account
//   node --expose-gc bench/first-view.ts run <dir>      starts the core offline, subscribes the chat list; prints
//                                                       when its first value and its whole list came, and memory
//
// No network: still.fail cloud's origin answers nothing, so what shows is what the device holds.
import { mkdirSync } from "node:fs";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { Effect } from "effect";
import { NodeHost, start } from "../src/hosts/node.ts";

const [, , mode, dir] = process.argv;
if (!dir) throw new Error("usage: first-view.ts seed|run <dir>");

export const STATIONS = 20;
export const PER_STATION = 2000;
export const ENTRIES = 100_000;
const SUB = "bench-account";
const WS = "w";
const NOW = Date.UTC(2026, 9, 3, 12);

const SEP = "\u0001";
const pad = (n: number) => String(n).padStart(12, "0");
const station = (i: number) => `${WS}/s${String(i).padStart(2, "0")}`;

/// What a station's lists say of chat `i` (as GET /chats, /sessions, /threads give them).
function row(st: string, i: number) {
  const key = `k${i}`;
  return {
    id: key, session: key, thread: i, title: `第 ${i} 个对话：排查 ${st} 上的构建`, mine: i % 3 === 0, unread: i % 7 === 0, connect: null, origin: null,
    lastActiveAt: NOW - i * 60_000, pinned: i < 2 ? NOW - i : undefined,
    agents: [{ key, runtime: "claude", model: "claude-opus-4-1", effort: null, process: i % 50 === 0 ? "running" : "warm", pending: 0, lastTurn: { kind: "chat", declared: "final", outcome: "completed", detail: null, startedAt: NOW - i * 60_000 - 5000, endedAt: NOW - i * 60_000 } }],
    last: { seq: 3, thread: i, ts: `${i}.3`, authorKind: "agent", author: key, authorName: null, text: `好的，已经改完了第 ${i} 处，测试都过了。`, attachments: [], quotes: [], declared: "final", createdAt: NOW - i * 60_000, editedAt: null, agentIdentity: { model: "claude-opus-4-1" } },
  };
}

function session(i: number) {
  return {
    key: `k${i}`, connect: "ember", scope: "thread", title: null, createdBy: null, boundTo: [], creator: null, participants: [], runtime: "claude", profile: "p1",
    profilePinned: false, model: "claude-opus-4-1", effort: null, runtimeSessionId: `rs-${i}`, workspace: `/w/${i}`, running: false, createdAt: NOW - i * 3_600_000,
    lastActiveAt: NOW - i * 60_000, archivedAt: null, process: "warm", turns: 3, pending: 0, firstText: `帮我看看第 ${i} 个问题`, lastTurn: { kind: "chat", outcome: "completed", declared: "final", detail: null, startedAt: NOW - i * 60_000 - 5000, endedAt: NOW - i * 60_000 },
  };
}

function thread(i: number, last: number) {
  return {
    id: i, surface: "ember", channel: "EMBER", channelName: null, threadTs: `${i}.0`, title: null, createdBy: null, creator: { id: "me@x.com", name: "我" }, createdAt: NOW - i * 3_600_000,
    sessions: [{ thread: i, session: `k${i}`, connect: "ember", joinedAt: NOW - i * 3_600_000 }], last, read: last, unread: 0, people: [],
    lastMessage: { seq: last, thread: i, ts: `${i}.${last}`, authorKind: "agent", author: `k${i}`, authorName: null, text: "好的，已经改完了。", attachments: [], quotes: [], declared: "final", createdAt: NOW - i * 60_000, editedAt: null },
    firstText: `帮我看看第 ${i} 个问题`,
  };
}

function entry(thread: number, n: number) {
  return { thread, n, kind: "message", seq: n, ts: `${thread}.${n}`, authorKind: n % 2 ? "person" : "agent", author: n % 2 ? "me@x.com" : `k${thread}`, authorName: null, text: `第 ${n} 条消息：${"这是一段普通长度的回复，说明做了什么、为什么。".repeat(2)}`, attachments: [], quotes: [], declared: null, createdAt: NOW - n * 1000, editedAt: null };
}

/// How many entries thread `i` of a station has: 100 000 over 20 × 2 000 threads (3 each for the first half, 2 after).
const PER_THREAD = Math.floor(ENTRIES / STATIONS / PER_STATION);
const EXTRA = (ENTRIES / STATIONS) % PER_STATION;
const entriesOf = (i: number) => (i < EXTRA ? PER_THREAD + 1 : PER_THREAD);

async function seed(): Promise<void> {
  mkdirSync(dir, { recursive: true });
  const host = new NodeHost(dir, "http://127.0.0.1:9", false, () => {});
  const nowS = Math.floor(Date.now() / 1000);
  await Effect.runPromise(host.storageSet("accounts", new TextEncoder().encode(JSON.stringify([{ sub: SUB, email: "me@x.com", name: "我", picture: "", access: "a", refresh: "r", access_expires: nowS + 365 * 86400 }]))));
  const db = new DatabaseSync(join(dir, "core.db"));
  db.exec("PRAGMA journal_mode = WAL; CREATE TABLE IF NOT EXISTS records (tbl TEXT NOT NULL, key TEXT NOT NULL, value BLOB NOT NULL, PRIMARY KEY (tbl, key)) WITHOUT ROWID;");
  const put = db.prepare("INSERT OR REPLACE INTO records (tbl, key, value) VALUES (?, ?, ?)");
  const enc = new TextEncoder();
  const rec = (tbl: string, key: string, value: unknown) => put.run(tbl, key, enc.encode(JSON.stringify(value)));
  db.exec("BEGIN");
  rec("me", SUB, { workspaces: [{ id: WS, name: "Bench" }], invitations: [], relay_url: null, user: { email: "me@x.com" } });
  rec("workspace", WS, { id: WS, name: "Bench", role: "owner", members: [{ email: "me@x.com", name: "我", role: "owner" }], stations: Array.from({ length: STATIONS }, (_, i) => ({ id: `s${String(i).padStart(2, "0")}`, name: `station ${i}`, online: true, last_seen: nowS, version: "0.1.0" })) });
  let entries = 0;
  for (let s = 0; s < STATIONS; s++) {
    const st = station(s);
    rec("overview", st, { viewer: { via: "local" }, connects: [], profiles: [], processes: [], counts: { sessions: PER_STATION, running: 0, warm: 0 }, mesh: null, slackUsers: [], slackTeams: [], slackApps: [], disk: null, logins: [] });
    const ids = Array.from({ length: PER_STATION }, (_, i) => i);
    rec("list", `row${SEP}${st}`, ids.map((i) => `k${i}`));
    rec("list", `session_summary${SEP}${st}`, ids.map((i) => `k${i}`));
    rec("list", `thread${SEP}${st}`, ids.map((i) => String(i)));
    for (const i of ids) {
      const n = entriesOf(i);
      rec("row", `${st}${SEP}k${i}`, row(st, i));
      rec("session_summary", `${st}${SEP}k${i}`, session(i));
      rec("thread", `${st}${SEP}${i}`, thread(i, n));
      for (let e = 1; e <= n; e++) rec("entry", `${st}${SEP}${i}${SEP}${pad(e)}`, entry(i, e));
      entries += n;
    }
  }
  db.exec("COMMIT");
  db.close();
  host.close();
  console.log(JSON.stringify({ seeded: dir, stations: STATIONS, perStation: PER_STATION, entries }));
}

const mb = (n: number) => Math.round((n / 1024 / 1024) * 10) / 10;
const memory = () => {
  (globalThis as { gc?: () => void }).gc?.();
  const m = process.memoryUsage();
  return { rssMB: mb(m.rss), heapMB: mb(m.heapUsed) };
};

async function runOnce(): Promise<void> {
  const t0 = performance.now();
  let first: { ms: number; rows: number; memory: ReturnType<typeof memory> } | null = null;
  let whole: { ms: number; rows: number } | null = null;
  let value: { days?: { items: unknown[] }[] } | null = null;
  const rowsOf = (v: typeof value) => (v?.days ?? []).reduce((n, d) => n + d.items.length, 0);
  const done = new Promise<void>((resolve) => {
    const core = start(dir, "http://127.0.0.1:9", (_client, json) => {
      const m = JSON.parse(json) as { id?: number; value?: typeof value; delta?: unknown };
      if (m.id !== 1) return;
      if ("value" in m) value = m.value ?? null;
      else if ("delta" in m) value = applyDelta(value, m.delta);
      const rows = rowsOf(value);
      if (first === null && rows > 0) first = { ms: Math.round(performance.now() - t0), rows, memory: memory() };
      if (rows >= STATIONS * PER_STATION && whole === null) {
        whole = { ms: Math.round(performance.now() - t0), rows };
        resolve();
      }
    }, undefined, { hostWire: true });
    const ui = core.connect();
    core.receive(ui, JSON.stringify({ id: 1, subscribe: { topic: "chats", scope: WS, mine: false }, keyed: true }));
    setTimeout(resolve, 60_000);
    process.on("exit", () => void core.close());
  });
  await done;
  // Settled: what is held after the whole list went out and the sync gave up on the network.
  await new Promise((r) => setTimeout(r, 5_000));
  console.log(JSON.stringify({ first, whole, settled: memory() }));
  process.exit(0);
}

// The old ops (set/append/remove) and the keyed ones, as the UIs apply them.
import { applyKeyed } from "../src/collections.ts";
function applyDelta(v: unknown, ops: unknown): typeof v {
  return applyKeyed(v, ops as never) as typeof v;
}

if (mode === "seed") await seed();
else if (mode === "run") await runOnce();
else throw new Error(`no mode ${mode}`);
