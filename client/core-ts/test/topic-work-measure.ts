// What answering each way the app asks reads of the account's database, counted, at one size of the real-size
// workspace (real-size.ts `SIZE`, this worker thread's `workerData.realSize`), and what each change the sync writes
// costs (`CAUSES`, real-size-asked.ts): topic-work.test.ts runs it once a size, each in a worker of its own, and holds
// what it finds to its bars. Counted at the bottom, in the database's own calls (NodeSql's `all`,
// `run`, `exec`, as the test's host makes them): the statements run, the rows they return and the bytes of text in
// those rows, the bytes of text bound to those that write, by statement as well; and, printed only, the core's `work`
// counters (work.ts).
import { isMainThread, parentPort, workerData } from "node:worker_threads";
import { holds } from "../src/data.ts";
import { NodeSql } from "../src/hosts/node-sql.ts";
import { holdLanguage } from "../src/i18n.ts";
import { parseTopic, type Topic } from "../src/protocol.ts";
import { EVICT_AFTER_MS } from "../src/store.ts";
import { FakeHost } from "../src/testing.ts";
import { work, workSince, type Work } from "../src/work.ts";
import { CHAT, SIZE, fixture, more, type Size } from "./real-size.ts";
import { AGAIN, ASKED, CAUSES, LONG, WINDOWS, held, topicOf, type Cause } from "./real-size-asked.ts";

// deno-lint-ignore no-explicit-any
type J = any;

/// What a statement did while something was measured: how many times it ran, the rows it returned, the bytes of text
/// in them, the bytes of text bound to it where it writes.
export type Statement = { sql: string; runs: number; rows: number; bytes: number; written: number };
/// What answering or a change took: statements run, rows read, bytes of text read, bytes of text written; bytes sent (as
/// topic-bytes weighs them); the statements that read most; each `work` counter that moved.
export type Measured = { statements: number; rows: number; read: number; written: number; sent: number; top: Statement[]; work: Record<string, number>; error?: string };
export type Interaction = { name: string; waited: Measured; idle: Measured; unanswered: string[] };
/// What a change cost (by its cause's name, `<cause> six pages` done with the chat's six pages loaded): `alone`, on a core
/// started anew on the device, nothing of the app's asked (the write's own cost); `held`, on a rig holding every way the
/// app asks, at rest (the write and every reader's reaction).
export type Changed = { name: string; alone: Measured; held: Measured };
export type Found = { size: Size; asked: { name: string; cold: Measured; warm: Measured }[]; interactions: Interaction[]; changes: Changed[] };

// ── the instrument ──

const count = { statements: 0, rows: 0, read: 0, written: 0 };
let by = new Map<string, Statement>();
const utf8 = (s: string) => Buffer.byteLength(s, "utf8");
const statementOf = (sql: string): Statement => {
  let s = by.get(sql);
  if (s === undefined) {
    s = { sql, runs: 0, rows: 0, bytes: 0, written: 0 };
    by.set(sql, s);
  }
  return s;
};
const textOf = (v: unknown) => (typeof v === "string" ? utf8(v) : v instanceof Uint8Array ? v.byteLength : 0);
/// The bytes of text bound to a statement that writes (INSERT, UPDATE, REPLACE, DELETE), counted to it.
const wrote = (s: Statement, sql: string, params: unknown[]) => {
  if (!/^\s*(INSERT|UPDATE|REPLACE|DELETE)\b/i.test(sql)) return;
  let bytes = 0;
  for (const v of params) bytes += textOf(v);
  s.written += bytes;
  count.written += bytes;
};
{
  const proto = NodeSql.prototype as J;
  const all = proto.all, run = proto.run, exec = proto.exec;
  proto.all = function (sql: string, params: unknown[] = []) {
    const rows = all.call(this, sql, params) as unknown[][];
    let bytes = 0;
    for (const row of rows) for (const v of row) bytes += textOf(v);
    const s = statementOf(sql);
    wrote(s, sql, params);
    s.runs++;
    s.rows += rows.length;
    s.bytes += bytes;
    count.statements++;
    count.rows += rows.length;
    count.read += bytes;
    return rows;
  };
  proto.run = function (sql: string, params: unknown[] = []) {
    const s = statementOf(sql);
    s.runs++;
    wrote(s, sql, params);
    count.statements++;
    return run.call(this, sql, params);
  };
  proto.exec = function (sql: string) {
    statementOf(sql).runs++;
    count.statements++;
    return exec.call(this, sql);
  };
}

/// The counters as they stand: the totals, each statement's (since the last `mark`), the core's `work`.
type Snap = { count: typeof count; by: Statement[]; work: Work };
const snap = (): Snap => ({ count: { ...count }, by: [...by.values()].map((s) => ({ ...s })), work: { ...work } });
/// Where measuring begins: each statement's counted afresh from here.
const mark = (): Snap => {
  by = new Map();
  return snap();
};
const TOP = 5;
/// What was counted from `from` to `to` (a snapshot taken as an answer went out, or now).
const between = (from: Snap, to: Snap, sent: number, error?: string): Measured => {
  const moved: Record<string, number> = {};
  for (const k of Object.keys(to.work) as (keyof Work)[]) if (to.work[k] !== from.work[k]) moved[k] = to.work[k] - from.work[k];
  const top = [...to.by].sort((a, b) => b.bytes - a.bytes || b.runs - a.runs).slice(0, TOP).map((s) => ({ ...s, sql: s.sql.replace(/\s+/g, " ").trim().slice(0, 120) }));
  return {
    statements: to.count.statements - from.count.statements, rows: to.count.rows - from.count.rows, read: to.count.read - from.count.read, written: to.count.written - from.count.written,
    sent, top, work: moved, ...(error !== undefined ? { error } : {}),
  };
};

// The moment each first answer goes out: the counters snapshot as the host is handed it (FakeHost's `emit`, wrapped here
// alone), so what is counted for an answer ends where it went, whatever the clock's step.
const answered = new Map<number, { message: J; at: Snap; n: number }>();
/// The bytes of every message gone to the app's subscriptions (client 1), first answers and what changed after.
let sentAll = 0;
/// The same, a rig `held`'s second subscription of each topic (past `AGAIN`) left out: what topic-bytes weighs.
let sentOnce = 0;
{
  const proto = FakeHost.prototype as J;
  const emit = proto.emit;
  proto.emit = function (client: number, message: J) {
    emit.call(this, client, message);
    if (client === 1) sentAll += bytes(message);
    if (client === 1 && !(typeof message?.id === "number" && message.id > AGAIN)) sentOnce += bytes(message);
    const id = message?.id;
    if (client === 1 && typeof id === "number" && !answered.has(id) && ("value" in message || "error" in message)) answered.set(id, { message, at: snap(), n: answered.size });
  };
}
const enc = new TextEncoder();
const bytes = (m: unknown) => enc.encode(JSON.stringify(m)).length;

// ── a device with the workspace on it, and a core started anew on it ──

/// The host whose database holds the workspace (real-size-asked.ts `held`: the chat with its last page, or its six).
async function device(long: boolean): Promise<FakeHost> {
  const h = await held(long);
  h.t.store.runner.shutdown();
  return h.t.host;
}

type Started = Awaited<ReturnType<typeof held>>;

/// The clock run on till the core is at rest: nothing goes out and no statement runs a settle long. Asserted.
async function rest(h: Started): Promise<void> {
  for (let i = 0; i < 100; i++) {
    const before = count.statements;
    await h.t.host.settle();
    if (h.t.host.takeEmitted().length === 0 && count.statements === before) return;
  }
  throw new Error("the core did not come to rest");
}

/// A core started anew on `host` (cold: nothing of it kept in memory), with what comes of the network as the sync keeps
/// it while the app runs (the station topics no table holds, watched and set), at rest, nothing of the app's asked yet.
async function started(host: FakeHost, long: boolean): Promise<Started> {
  const h = await held(long, { host, cold: true });
  const live = [...fixture(h.base, h.chat), ...more(h.base)].filter(([topic]) => !holds(topic));
  live.forEach(([topic], i) => h.t.store.subscribe(9, i + 1, topic, false));
  for (let round = 0; round < 2; round++) {
    h.setLive();
    await h.t.host.time.pass(100);
  }
  await rest(h);
  return h;
}

/// The clock's step as answers are waited for, in ms (`workerData.step`; what is counted does not depend on it).
const STEP: number = (workerData as J)?.step ?? 10;

/// The clock passed in steps till every one of `ids` has its first answer (a value or an error: `answered`, as it went
/// out), 5 s at most.
async function answers(h: Started, ids: number[]): Promise<void> {
  for (let t = 0; t < 5000 && ids.some((id) => !answered.has(id)); t += STEP) await h.t.host.time.pass(STEP, STEP);
  h.t.host.takeEmitted();
}
/// What was counted from `from` to subscription `id`'s first answer.
const toAnswer = (from: Snap, id: number): Measured => {
  const a = answered.get(id);
  return a === undefined ? between(from, snap(), 0, "no answer") : between(from, a.at, bytes(a.message), a.message.error?.code);
};

/// Each way of asking named (all of `ASKED` but `skip`): cold, its first answer on a core started anew; warm, asked
/// again once let go without `keep` (the store's eviction passed).
async function askedAll(skip: Set<string>): Promise<Found["asked"]> {
  const out: Found["asked"] = [];
  for (const long of [false, true]) {
    const host = await device(long);
    for (const name of Object.keys(ASKED).filter((n) => LONG.has(n) === long && !skip.has(n))) {
      const h = await started(host, long);
      const topic = topicOf(name);
      answered.clear();
      let m = mark();
      h.t.store.subscribe(1, 1, topic, true);
      await answers(h, [1]);
      const c = toAnswer(m, 1);
      h.t.store.unsubscribe(1, 1);
      await h.t.host.time.pass(EVICT_AFTER_MS + 2000, 1000);
      await rest(h);
      // (a chats list's window let go with it, views.ts `stop`: told again first, as the app tells it, sfbase/rows.mbt)
      if (WINDOWS[name] !== undefined) h.t.window(topic, WINDOWS[name]);
      m = mark();
      h.t.store.subscribe(1, 2, topic, true);
      await answers(h, [2]);
      const w = toAnswer(m, 2);
      out.push({ name, cold: c, warm: w });
      h.t.store.runner.shutdown();
    }
  }
  return out;
}

// ── the interactions, as the app sends them ──

/// A topic an interaction asks, as the app asks it: whether the first screen waits for it (`waited`), and the window a
/// chats list is told first (real-size-asked.ts WINDOWS).
export type Ask = [topic: J, waited: boolean, window?: number];
const ws = "ws";
const st = CHAT.station;
const key = CHAT.keys[0];
const chats = (w: string): Ask => [{ topic: "chats", scope: w, mine: false }, true, 30];
/// The device's own topics the app holds all along (apps/mbui/core/wsswitch.m 280-307, the app's main's).
const own = (): Ask[] => [[{ topic: "prefs" }, false], [{ topic: "accounts" }, false], [{ topic: "workspaces" }, false], [{ topic: "downloads" }, false], [{ topic: "doing" }, false], [{ topic: "lockPrompts" }, false], [{ topic: "notify" }, false]];
/// What a chat's page reads as it comes on top (apps/mbui/src/sfbase/pages.mbt:825-835 page_opens: chat_params,
/// composer, stations_asked, chat_jobs_summary_params, sfbase/chat_model.mbt:901-953).
const chatPage = (): Ask[] => [[{ topic: "chat", station: st, session: key }, true], [{ topic: "composer", key: `${st}:${key}` }, true], [{ topic: "stations", scope: ws }, true], [{ topic: "chatJobs", station: st, session: key, summary: true }, true]];

export const INTERACTIONS: Record<string, { before: Ask[]; asks: Ask[] }> = {
  // The first screen after a start (wsswitch.m 278-311, `start`): on 小屏 the list, longJobs, the marks, the workspace,
  // its stations and profiles waited for; on 大屏 the marks, the list, longJobs, status and transfers, then the new chat
  // the pane lands on (wsswitch.m 160-196, land_page; 399-405).
  "start 小屏": {
    before: [],
    asks: [...own(), [{ topic: "lock", workspace: ws }, true], [{ topic: "longJobs", scope: ws }, true], chats(ws), [{ topic: "changelog", news: true }, true], [{ topic: "workspaceMarks" }, true],
      [{ topic: "workspace", workspace: ws }, true], [{ topic: "stations", scope: ws }, true], [{ topic: "profiles", scope: ws }, true], [{ topic: "driveTransfers", workspace: ws }, false], [{ topic: "status", workspace: ws }, false], [{ topic: "notify", workspace: ws }, false]],
  },
  "start 大屏": {
    before: [],
    asks: [...own(), [{ topic: "lock", workspace: ws }, true], [{ topic: "workspaceMarks" }, true], chats(ws), [{ topic: "longJobs", scope: ws }, true], [{ topic: "status", workspace: ws }, true], [{ topic: "driveTransfers", workspace: ws }, true],
      [{ topic: "newChat", scope: ws }, true], [{ topic: "composer", key: `new:${ws}` }, true], [{ topic: "notify", workspace: ws }, false]],
  },
  // A switch of workspace from the owner's other one (wsswitch.m 314-322 `press`: the list and longJobs waited for;
  // 236-275 `commit`: what the new screen shows besides).
  "switch 小屏": {
    before: [...own(), [{ topic: "workspaceMarks" }, false], chats("ws-labs"), [{ topic: "longJobs", scope: "ws-labs" }, false], [{ topic: "stations", scope: "ws-labs" }, false]],
    asks: [chats(ws), [{ topic: "longJobs", scope: ws }, true],
      [{ topic: "lock", workspace: ws }, false], [{ topic: "workspace", workspace: ws }, false], [{ topic: "stations", scope: ws }, false], [{ topic: "profiles", scope: ws }, false], [{ topic: "driveTransfers", workspace: ws }, false], [{ topic: "status", workspace: ws }, false], [{ topic: "notify", workspace: ws }, false]],
  },
  "switch 大屏 to 新对话": {
    before: [...own(), [{ topic: "workspaceMarks" }, false], chats("ws-labs"), [{ topic: "longJobs", scope: "ws-labs" }, false]],
    asks: [chats(ws), [{ topic: "longJobs", scope: ws }, true], [{ topic: "newChat", scope: ws }, true],
      [{ topic: "driveTransfers", workspace: ws }, false], [{ topic: "status", workspace: ws }, false], [{ topic: "lock", workspace: ws }, false], [{ topic: "composer", key: `new:${ws}` }, false], [{ topic: "notify", workspace: ws }, false]],
  },
  // (landing on the chat workspaceMarks says was open: wsswitch.m 190, and its commit's 253-262)
  "switch 大屏 to a chat": {
    before: [...own(), [{ topic: "workspaceMarks" }, false], chats("ws-labs"), [{ topic: "longJobs", scope: "ws-labs" }, false]],
    asks: [chats(ws), [{ topic: "longJobs", scope: ws }, true], [{ topic: "chat", station: st, session: key, compact: true }, true],
      [{ topic: "driveTransfers", workspace: ws }, false], [{ topic: "status", workspace: ws }, false], [{ topic: "lock", workspace: ws }, false],
      [{ topic: "chatOutline", station: st, thread: CHAT.thread }, false], [{ topic: "chatFeedback", station: st, session: key }, false], [{ topic: "composer", key: `${st}:${key}` }, false],
      [{ topic: "chatRow", station: st, session: key }, false], [{ topic: "stations", scope: ws }, false], [{ topic: "chatJobs", station: st, session: key, summary: true, compact: true }, false], [{ topic: "notify", workspace: ws }, false]],
  },
  // A chat opened from the list, on 小屏's Home (the list held: apps/mbui/src/sfbase/pages.mbt:825-835 page_opens).
  "open a chat from the list": { before: [...own(), chats(ws), [{ topic: "longJobs", scope: ws }, false]], asks: chatPage() },
  // Each place of the bar (apps/mbui/src/sfbase/bars.mbt:111-136 place_reads), from Home.
  "place files": { before: [...own(), chats(ws)], asks: [[{ topic: "workspace", workspace: ws }, true], [{ topic: "stations", scope: ws }, true]] },
  "place stations": { before: [...own(), chats(ws)], asks: [[{ topic: "stations", scope: ws }, true]] },
  "place profiles": { before: [...own(), chats(ws)], asks: [[{ topic: "profiles", scope: ws }, true]] },
  "place connects": { before: [...own(), chats(ws)], asks: [[{ topic: "stations", scope: ws }, true], [{ topic: "connects", scope: ws, mine: false }, true]] },
  "place vault": { before: [...own(), chats(ws)], asks: [[{ topic: "vaults", workspace: ws }, true]] },
  "place usage": { before: [...own(), chats(ws)], asks: [[{ topic: "usage", scope: ws, days: 7 }, true]] },
  "place archive": { before: [...own(), chats(ws)], asks: [[{ topic: "archive", scope: ws, limit: 60 }, true]] },
};

/// Each interaction: from a core started anew showing what the screen before held, at rest, to the last answer the
/// first screen waits for (`waited`), and on to the core at rest again (`idle`).
async function interactionsAll(): Promise<Interaction[]> {
  const host = await device(false);
  const out: Interaction[] = [];
  for (const [name, x] of Object.entries(INTERACTIONS)) {
    const h = await started(host, false);
    const ask = (asks: Ask[], from: number) =>
      asks.map(([topic, waited, window], i) => {
        const t = parseTopic(topic) as Topic;
        if (window !== undefined) h.t.window(t, window);
        h.t.store.subscribe(1, from + i, t, true);
        return { id: from + i, waited, name: t.topic };
      });
    ask(x.before, 100);
    await rest(h);
    answered.clear();
    const m = mark();
    const sentFrom = sentAll;
    const asked = ask(x.asks, 1);
    const waitedIds = asked.filter((a) => a.waited).map((a) => a.id);
    await answers(h, waitedIds);
    // (to the last of the first screen's answers, as it went out)
    const last = waitedIds.map((id) => answered.get(id)).filter((a) => a !== undefined).reduce<{ message: J; at: Snap; n: number } | undefined>((l, a) => (l === undefined || a.n > l.n ? a : l), undefined);
    const sentWaited = waitedIds.reduce((n, id) => n + (answered.has(id) ? bytes(answered.get(id)!.message) : 0), 0);
    const waited = last === undefined ? between(m, snap(), 0, "no answer") : between(m, last.at, sentWaited);
    await answers(h, asked.map((a) => a.id));
    await rest(h);
    const idle = between(m, snap(), sentAll - sentFrom);
    const unanswered = asked.filter((a) => !answered.has(a.id)).map((a) => a.name);
    out.push({ name, waited, idle, unanswered });
    h.t.store.runner.shutdown();
  }
  return out;
}

// ── what each change the sync writes costs ──

/// What `cause` costs on `h`: from its run, as real-size-asked.ts `during` does it (`ms` of the clock in steps of 100),
/// to the core at rest; what goes out counted as topic-bytes weighs it.
async function change(h: Started, cause: Cause): Promise<Measured> {
  const m = mark();
  const sentFrom = sentOnce;
  let error: string | undefined;
  try {
    cause.run(h);
    await h.t.host.time.pass(cause.ms ?? 1000, 100);
    await rest(h);
  } catch (e) {
    error = String((e as Error)?.stack ?? e);
  }
  return between(m, snap(), sentOnce - sentFrom, error);
}

/// Each cause of `CAUSES` (again with the chat's six pages loaded where it says `long`), one after another in its order:
/// alone, on one core started anew on the device, nothing of the app's asked; held, on one rig `held` made, every way of
/// asking subscribed, at rest. Each is measured on the rig as the causes before it left it.
async function changesAll(): Promise<Changed[]> {
  const out: Changed[] = [];
  for (const long of [false, true]) {
    const causes = Object.entries(CAUSES).filter(([, c]) => (long ? c.long === true : true));
    const name = (cause: string) => (long ? `${cause} six pages` : cause);
    const alone = new Map<string, Measured>();
    const a = await started(await device(long), long);
    for (const [cause, c] of causes) alone.set(name(cause), await change(a, c));
    a.t.store.runner.shutdown();
    const h = await held(long);
    for (const [cause, c] of causes) out.push({ name: name(cause), alone: alone.get(name(cause))!, held: await change(h, c) });
    h.t.store.runner.shutdown();
  }
  return out;
}

/// What this size finds: every way of asking but `skip`, every interaction, every change.
export async function measure(skip: string[]): Promise<Found> {
  holdLanguage();
  return { size: SIZE, asked: await askedAll(new Set(skip)), interactions: await interactionsAll(), changes: await changesAll() };
}

if (!isMainThread && (workerData as J)?.topicWork === true) {
  measure((workerData as J).skip ?? []).then((f) => parentPort!.postMessage(f), (e) => parentPort!.postMessage({ error: String(e?.stack ?? e) }));
}
