// A chat opened from what the device holds: how long from the UI's `subscribe` to the chat's first value, the first
// time this run (cold) and again a moment after it was let go (warm), with the chat list subscribed as Home has it.
// One account, one station of 300 chats; the first 20 with 120 entries each, the agents' as long Markdown (parts of
// this repository's docs: paragraphs, lists, tables, code), the people's a line, all said weeks ago (none read ahead).
// Run twice on one directory, the second is the app started anew (what the first read kept on the device). In Hermes,
// the engine the phones run: apps/mbui/scripts/core.sh chat-open (core/chatopen.m).
//
//   node --expose-gc bench/chat-open.ts seed <dir>
//   node --expose-gc bench/chat-open.ts run <dir>
//
// No network: still.fail cloud's origin answers nothing, so what shows is what the device holds.
import { mkdirSync, writeFileSync } from "node:fs";
import { Session } from "node:inspector/promises";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { Effect } from "effect";
import { NodeHost, start } from "../src/hosts/node.ts";
import { replies as parts } from "./replies.ts";

const [, , mode, dir] = process.argv;
if (!dir) throw new Error("usage: chat-open.ts seed|run <dir>");

const CHATS = Number(process.env.CHATS ?? 300);
const LONG = 20;
const PER_LONG = 120;
const SUB = "bench-account";
const WS = "w";
const ST = `${WS}/s00`;
const NOW = Date.UTC(2026, 9, 3, 12);
const SEP = "\u0001";
const pad = (n: number) => String(n).padStart(12, "0");

function row(i: number, last: number) {
  const key = `k${i}`;
  return {
    id: key, session: key, thread: i, title: `第 ${i} 个对话`, mine: true, unread: false, connect: null, origin: null,
    lastActiveAt: NOW - i * 60_000,
    agents: [{ key, runtime: "claude", model: "claude-opus-4-1", effort: null, process: "warm", pending: 0, lastTurn: { kind: "chat", declared: "final", outcome: "completed", detail: null, startedAt: NOW - i * 60_000 - 5000, endedAt: NOW - i * 60_000 } }],
    last: { seq: last, thread: i, ts: `${i}.${last}`, authorKind: "agent", author: key, authorName: null, text: "好的，已经改完了。", attachments: [], quotes: [], declared: "final", createdAt: NOW - i * 60_000, editedAt: null, agentIdentity: { model: "claude-opus-4-1" } },
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
    id: i, surface: "ember", channel: "EMBER", channelName: null, threadTs: `${i}.0`, title: null, createdBy: null, creator: null, createdAt: NOW - i * 3_600_000,
    sessions: [{ thread: i, session: `k${i}`, connect: "ember", joinedAt: NOW - i * 3_600_000 }], last, read: last, unread: 0, people: [],
    lastMessage: { seq: last, thread: i, ts: `${i}.${last}`, authorKind: "agent", author: `k${i}`, authorName: null, text: "好的，已经改完了。", attachments: [], quotes: [], declared: "final", createdAt: NOW - i * 60_000, editedAt: null },
    firstText: `帮我看看第 ${i} 个问题`,
  };
}

function entry(md: string[], thread: number, n: number) {
  const agent = n % 2 === 0;
  const text = agent ? md[(thread * 131 + n) % md.length] : `第 ${n} 条：这里再看一下，顺便把测试也补上。`;
  return { thread, n, kind: "message", seq: n, ts: `${thread}.${n}`, authorKind: agent ? "agent" : "person", author: agent ? `k${thread}` : "me@x.com", authorName: null, text, attachments: [], quotes: [], declared: agent ? "final" : null, at: NOW - (PER_LONG - n) * 60_000 };
}

async function seed(): Promise<void> {
  mkdirSync(dir, { recursive: true });
  const md = parts();
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
  rec("workspace", WS, { id: WS, name: "Bench", role: "owner", members: [{ email: "me@x.com", name: "我", role: "owner" }], stations: [{ id: "s00", name: "station 0", online: true, last_seen: nowS, version: "0.1.0" }] });
  rec("overview", ST, { viewer: { via: "local" }, connects: [], profiles: [], processes: [], counts: { sessions: CHATS, running: 0, warm: 0 }, mesh: null, slackUsers: [], slackTeams: [], slackApps: [], disk: null, logins: [] });
  const ids = Array.from({ length: CHATS }, (_, i) => i);
  rec("list", `row${SEP}${ST}`, ids.map((i) => `k${i}`));
  rec("list", `session_summary${SEP}${ST}`, ids.map((i) => `k${i}`));
  rec("list", `thread${SEP}${ST}`, ids.map((i) => String(i)));
  let chars = 0;
  for (const i of ids) {
    const n = i < LONG ? PER_LONG : 3;
    rec("row", `${ST}${SEP}k${i}`, row(i, n));
    rec("session_summary", `${ST}${SEP}k${i}`, session(i));
    rec("thread", `${ST}${SEP}${i}`, thread(i, n));
    for (let e = 1; e <= n; e++) {
      const v = entry(md, i, e);
      if (i < LONG && e > n - 50) chars += v.text.length;
      rec("entry", `${ST}${SEP}${i}${SEP}${pad(e)}`, v);
    }
  }
  db.exec("COMMIT");
  db.close();
  host.close();
  console.log(JSON.stringify({ seeded: dir, chats: CHATS, long: LONG, perLong: PER_LONG, parts: md.length, avgWindowChars: Math.round(chars / LONG) }));
}

async function run(): Promise<void> {
  const waits = new Map<number, (m: { value?: unknown; error?: unknown }, bytes: number) => void>();
  let listRows = 0;
  const core = start(dir, "http://127.0.0.1:9", (_client, json) => {
    const m = JSON.parse(json) as { id?: number; value?: { days?: { items: unknown[] }[] }; error?: unknown };
    if (m.id === 1 && m.value) listRows = (m.value.days ?? []).reduce((n, d) => n + d.items.length, 0);
    const w = m.id !== undefined ? waits.get(m.id) : undefined;
    if (w && ("value" in m || "error" in m)) {
      waits.delete(m.id!);
      w(m, json.length);
    }
  }, undefined, { hostWire: true });
  const ui = core.connect();
  core.receive(ui, JSON.stringify({ id: 1, subscribe: { topic: "chats", scope: WS, mine: false }, keyed: true }));
  const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
  for (let i = 0; i < 100 && listRows < CHATS; i++) await sleep(200);
  await sleep(3000);
  let next = 100;
  const open = (i: number) =>
    new Promise<{ ms: number; kb: number; err?: unknown }>((resolve) => {
      const id = next++;
      const t0 = performance.now();
      waits.set(id, (m, bytes) => {
        const ms = Math.round((performance.now() - t0) * 10) / 10;
        core.receive(ui, JSON.stringify({ id, unsubscribe: true }));
        resolve({ ms, kb: Math.round(bytes / 1024), ...(m.error ? { err: m.error } : {}) });
      });
      core.receive(ui, JSON.stringify({ id, subscribe: { topic: "chat", station: ST, session: `k${i}` }, keyed: true }));
    });
  // (the cold opens profiled: CHAT_OPEN_PROF=<file> writes their CPU profile)
  const prof = process.env.CHAT_OPEN_PROF ? new Session() : null;
  if (prof) {
    prof.connect();
    await prof.post("Profiler.enable");
    await prof.post("Profiler.setSamplingInterval", { interval: 100 });
    await prof.post("Profiler.start");
  }
  const cold: unknown[] = [];
  for (let i = 0; i < 10; i++) {
    cold.push(await open(i));
    await sleep(300);
  }
  if (prof) {
    const { profile } = await prof.post("Profiler.stop");
    writeFileSync(process.env.CHAT_OPEN_PROF!, JSON.stringify(profile));
  }
  const warm: unknown[] = [];
  for (let i = 0; i < 10; i++) {
    warm.push(await open(i));
    await sleep(300);
  }
  // Let go longer than the core keeps a view (store.ts EVICT_AFTER_MS): its Markdown kept, the view made again.
  await sleep(62_000);
  const prof2 = process.env.CHAT_OPEN_PROF ? new Session() : null;
  if (prof2) {
    prof2.connect();
    await prof2.post("Profiler.enable");
    await prof2.post("Profiler.setSamplingInterval", { interval: 100 });
    await prof2.post("Profiler.start");
  }
  const again: unknown[] = [];
  for (let i = 0; i < 10; i++) {
    again.push(await open(i));
    await sleep(300);
  }
  if (prof2) {
    const { profile } = await prof2.post("Profiler.stop");
    writeFileSync(process.env.CHAT_OPEN_PROF! + ".evicted", JSON.stringify(profile));
  }
  console.log(JSON.stringify({ listRows, cold, warm, evicted: again }));
  process.exit(0);
}

if (mode === "seed") await seed();
else if (mode === "run") await run();
else throw new Error(`no mode ${mode}`);
