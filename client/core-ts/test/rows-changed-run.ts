// A station of the real-size workspace (real-size.ts: Maple's sessions, threads, its chat list as it makes it for
// everyone, and marks of them all) answering a core started on it, and what rows-changed.test.ts holds of what the core
// makes of it: its chat list as stored, against what is made of what it holds anew (rows-made.ts with an empty memo);
// and what one change makes the core do (work.ts), measured in a worker thread a size (`workerData.rowsChanged`).
import { isMainThread, parentPort, workerData } from "node:worker_threads";
import { worded } from "../src/chat-row.ts";
import { rowWords, rowsMade, rowsShared } from "../src/station/rows-made.ts";
import { glanced, work } from "../src/work.ts";
import type { HttpRequest } from "../src/host.ts";
import { CHAT, SIZE, address, fixture } from "./real-size.ts";
import { base, stationReplies, started, status } from "./station-fixture.ts";

// deno-lint-ignore no-explicit-any
type J = any;

export const ST = "ws/st";
/// The viewer, as station-fixture's core is signed in (helpers.ts `signIn`); the workspace's owner in real-size.ts is
/// made them.
const ME = "a@x.com";
/// When the workspace is made.
const BASE = 1_794_000_000_000;

/// A deterministic stream of numbers in [0, 1) (mulberry32).
export function seeded(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/// What the station holds and says: Maple's of the real-size workspace, its owner the viewer.
export class Station {
  readonly sessions = new Map<string, J>();
  readonly threads = new Map<number, J>();
  /// Its chat list as it makes it for everyone (chat-row.ts), by row id.
  readonly shared = new Map<string, J>();
  marks: J;
  constructor() {
    const of = (topic: string) => JSON.parse(JSON.stringify(fixture(BASE).find(([t]) => t.topic === topic && t.station === address(0))![1]).replaceAll("me@x.com", ME)) as J[];
    for (const s of of("sessions")) this.sessions.set(s.key, s);
    for (const t of of("threads")) this.threads.set(t.id, t);
    const rows = of("chatRows");
    const marks: J = {
      card: {}, need: {}, answered: {}, suggested: [], verdicts: {}, reviews: true, kept: [], hidden: [], muted: [], pins: {}, openers: {}, opened: {}, shares: {}, clientKeys: {},
      teams: { "c-slack-1": "Acme" }, selves: ["U04A1B2C3D4"], dismissed: [], reads: {},
    };
    rows.forEach((r, i) => {
      const id = String(r.thread);
      if (r.card !== undefined) marks.card[id] = r.card;
      else if (i % 7 === 2) marks.need[id] = { seq: r.last.seq, text: "需要你看一下", at: r.lastActiveAt };
      if (i % 9 === 4) marks.answered[id] = [{ seq: r.last.seq - 1, label: "可以" }];
      if (r.archiveRecommended) marks.suggested.push(r.thread);
      if (i % 8 === 6) marks.verdicts[id] = { done: i % 16 === 6, why: "看起来做完了" };
      if (i % 12 === 7) marks.kept.push(r.thread);
      if (i % 15 === 11) marks.hidden.push(r.thread);
      if (i % 17 === 13) marks.muted.push(r.thread);
      if (r.pinned !== null) marks.pins[r.id] = r.pinned;
      if (r.opened !== undefined) marks.opened[r.id] = r.opened;
      if (r.xshare !== undefined) marks.shares[r.id] = r.xshare;
      if (i % 19 === 3) marks.openers[r.id] = { session: CHAT.keys[0], title: "从这里开的" };
      if (i % 23 === 5) marks.clientKeys[r.id] = `ck-${i}`;
      if (i % 10 === 1) marks.reads[id] = r.last.seq - 1;
      // (as a station makes it for everyone: what its last message was, and what was said after the viewer's own)
      this.shared.set(r.id, { ...r, said: { n: r.last.seq, other: r.last.seq - (i % 3) } });
    });
    this.marks = marks;
  }

  /// The marks of some chats (GET /chats?marks=1&session=…&thread=…), or all of them.
  marksOf(sessions: Set<string> | null, threads: Set<number> | null): J {
    const m = this.marks;
    if (sessions === null || threads === null) return structuredClone(m);
    const ofThreads = (o: Record<string, J>) => Object.fromEntries(Object.entries(o).filter(([k]) => threads.has(Number(k))));
    const ofSessions = (o: Record<string, J>) => Object.fromEntries(Object.entries(o).filter(([k]) => sessions.has(k)));
    const ids = (a: number[]) => a.filter((t) => threads.has(t));
    return structuredClone({
      card: ofThreads(m.card), need: ofThreads(m.need), answered: ofThreads(m.answered), verdicts: ofThreads(m.verdicts), reads: ofThreads(m.reads),
      suggested: ids(m.suggested), kept: ids(m.kept), hidden: ids(m.hidden), muted: ids(m.muted),
      dismissed: m.dismissed.filter((d: string) => threads.has(Number(d.slice(0, d.indexOf(":"))))),
      pins: ofSessions(m.pins), openers: ofSessions(m.openers), opened: ofSessions(m.opened), shares: ofSessions(m.shares), clientKeys: ofSessions(m.clientKeys),
      teams: m.teams, selves: m.selves, reviews: m.reviews,
    });
  }

  /// Its answer to a request of the core's (undefined: station-fixture's table's).
  reply(req: HttpRequest): unknown {
    const path = req.url.replace("https://stillfail.test/admin/api", "");
    if (req.method !== "GET") return undefined;
    if (path === "/sessions") return [...this.sessions.values()];
    if (path === "/threads") return [...this.threads.values()];
    if (path === "/chats?shared=1") return [...this.shared.values()];
    const thread = /^\/threads\/(\d+)$/.exec(path);
    if (thread) return this.threads.get(Number(thread[1])) ?? status(404, { error: "no such chat" });
    if (path.startsWith("/chats?marks=1")) {
      const q = new URLSearchParams(path.slice(path.indexOf("?") + 1));
      const scoped = q.has("session") || q.has("thread");
      return this.marksOf(scoped ? new Set(q.getAll("session")) : null, scoped ? new Set(q.getAll("thread").map(Number)) : null);
    }
    return undefined;
  }
}

/// A core started on `station` (its chat list made for everyone where `shared`), everything read.
export async function startedOn(station: Station, shared = false) {
  const s = await started({ ...base(), "GET /chats?archived=1": [] }, 0, undefined, (s) => {
    s.gate.shared = shared;
    stationReplies(s.host, (req) => station.reply(req));
  });
  await s.host.time.pass(3000, 100);
  return s;
}
export type Started = Awaited<ReturnType<typeof startedOn>>;

/// A row as the chat table keeps it: its JSON (`unread` apart) and `unread`.
const asStored = (row: J): { json: string; unread: number | null } => {
  const { unread, ...rest } = row;
  return { json: JSON.stringify(rest), unread: typeof unread === "boolean" ? (unread ? 1 : 0) : null };
};

/// The station's chat list as the core stored it, in its order.
export function stored(s: Started): { id: string; json: string; unread: number | null }[] {
  return s.core.inner.data.of(ST)!.sql.all("SELECT id, json, unread FROM chat WHERE station = ? AND archived = 0 ORDER BY ord", [ST])
    .map((r) => ({ id: String(r[0]), json: String(r[1]), unread: r[2] as number | null }));
}

/// What a core started anew makes of what this one holds (its sessions, threads, its list made for everyone, the
/// marks): rows-made.ts with an empty memo, in the viewer's words, each id once.
export function madeAnew(s: Started): { id: string; json: string; unread: number | null }[] {
  const link = s.core.inner.stations.link(ST)!;
  const data = s.core.inner.data;
  const words = rowWords();
  const rows = link.shared
    ? rowsShared(link.sharedRows!.values(), link.marks!, ME, words)
    : rowsMade(data.shared({ topic: "sessions", station: ST }) as J[], data.shared({ topic: "threads", station: ST }) as J[], link.marks!, ME, words);
  const seen = new Set<string>();
  return rows.flatMap((r) => {
    if (seen.has(r.id)) return [];
    seen.add(r.id);
    return [{ id: r.id, ...asStored(worded(r, words)) }];
  });
}

/// Where two lists of rows differ: an id at a place, or a field of a row (none: the same).
export function differences(stored: { id: string; json: string; unread: number | null }[], made: { id: string; json: string; unread: number | null }[]): string[] {
  const out: string[] = [];
  for (let i = 0; i < Math.max(stored.length, made.length); i++) {
    const a = stored[i];
    const b = made[i];
    if (a?.id !== b?.id) {
      out.push(`at ${i}: stored ${a?.id ?? "nothing"}, made ${b?.id ?? "nothing"}`);
      continue;
    }
    if (a!.unread !== b!.unread) out.push(`${a!.id} unread: stored ${a!.unread}, made ${b!.unread}`);
    if (a!.json === b!.json) continue;
    const x = JSON.parse(a!.json) as J;
    const y = JSON.parse(b!.json) as J;
    for (const k of new Set([...Object.keys(x), ...Object.keys(y)])) {
      if (JSON.stringify(x[k]) !== JSON.stringify(y[k])) out.push(`${a!.id} ${k}: stored ${JSON.stringify(x[k])}, made ${JSON.stringify(y[k])}`);
    }
    if (out.length === 0) out.push(`${a!.id}: the same fields in another order`);
  }
  return out;
}

// ── what the station tells ──

const pick = <T>(r: () => number, a: readonly T[]): T => a[Math.floor(r() * a.length)]!;

/// A message said in thread `t` (`person`: by a person, else by its first agent), as the station tells it and keeps it.
export function said(station: Station, s: Started, t: J, person: boolean, text = "好的，我先跑一遍测试再合。"): void {
  const n = t.last + 1;
  const at = s.host.nowMs();
  const author = person ? "lina@acme.dev" : t.sessions[0]?.session ?? "k";
  const entry = { thread: t.id, n, kind: "message", target: null, ts: `${t.id}.${n}`, authorKind: person ? "person" : "agent", author, authorName: person ? "Lina Park" : null, text, at };
  station.threads.set(t.id, {
    ...t, last: n, unread: (t.unread ?? 0) + 1,
    lastMessage: { seq: n, thread: t.id, ts: entry.ts, authorKind: entry.authorKind, author, authorName: entry.authorName, text, attachments: [], quotes: [], declared: null, createdAt: at, editedAt: null },
  });
  s.push("thread", { id: t.id, entries: [entry] });
}

/// A session's summary as its station tells it changed (`turn`: its last turn now asks a person).
export function summary(station: Station, s: Started, key: string, change: J): void {
  const now = { ...station.sessions.get(key)!, lastActiveAt: s.host.nowMs(), ...change };
  if (now.archivedAt !== null && now.archivedAt !== undefined) station.sessions.delete(key);
  else station.sessions.set(key, now);
  s.push("session", now);
}

/// The marks of thread `t` and session `key` changed on the station (a card come or gone, a verdict, an opener, a
/// share), and said so (`chat-mark`): read again, those alone.
export function marked(station: Station, s: Started, t: J, key: string, r: () => number): void {
  const m = station.marks;
  const id = String(t.id);
  if (m.card[id] !== undefined && r() < 0.5) delete m.card[id];
  else m.card[id] = { seq: t.last, card: { type: "options", options: [{ label: "好" }, { label: "不要" }] }, message: { seq: t.last, text: "选一个" }, before: [] };
  if (r() < 0.5) m.verdicts[id] = { done: r() < 0.5, why: "又看了一遍" };
  else delete m.verdicts[id];
  if (r() < 0.5) m.openers[key] = { session: CHAT.keys[1], title: `开自 ${Math.floor(r() * 100)}` };
  else delete m.openers[key];
  if (r() < 0.3) m.shares[key] = { to: ["ws-labs"], write: r() < 0.5 };
  s.push("chat-mark", { session: key, thread: t.id });
}

/// One of the changes a station tells of its chats, picked by `r` (its kind, what it is of), as it tells it.
export function anyChange(station: Station, s: Started, r: () => number): string {
  const threads = [...station.threads.values()];
  const keys = [...station.sessions.keys()];
  const t = pick(r, threads);
  const key = pick(r, keys);
  const m = station.marks;
  const toggle = (list: number[], id: number, on: boolean) => [...list.filter((x) => x !== id), ...(on ? [id] : [])];
  const kind = pick(r, ["message", "message", "message", "person", "summary", "summary", "turn", "pending", "read", "hidden", "muted", "pin", "dismiss", "kept", "marked", "renamed", "whole", "new", "thread-removed", "session-removed"] as const);
  switch (kind) {
    case "message":
      said(station, s, t, false);
      break;
    case "person":
      said(station, s, t, true, "这个先别合，等我看看");
      break;
    case "summary":
      summary(station, s, key, { process: pick(r, ["cold", "warm", "running"]), ...(r() < 0.3 ? { title: `改名 ${Math.floor(r() * 1000)}` } : {}), ...(r() < 0.05 ? { archivedAt: s.host.nowMs() } : {}) });
      break;
    case "turn":
      summary(station, s, key, { lastTurn: { id: `turn-${Math.floor(r() * 1e6)}`, kind: "chat", outcome: "done", declared: "block", ending: "need_help", need: "要你看一下", detail: null, startedAt: s.host.nowMs() - 60_000, endedAt: s.host.nowMs() } });
      break;
    case "pending":
      s.push("session-pending", { key, pending: r() < 0.5 ? 0 : 1 + Math.floor(r() * 3) });
      break;
    case "read":
      station.threads.set(t.id, { ...t, read: t.last, unread: 0 });
      m.reads[String(t.id)] = t.last;
      s.push("read", { thread: t.id, n: t.last });
      break;
    case "hidden":
    case "muted": {
      const on = r() < 0.5;
      m[kind] = toggle(m[kind], t.id, on);
      s.push(kind, { thread: t.id, [kind]: on });
      break;
    }
    case "pin": {
      const at = r() < 0.6 ? s.host.nowMs() : null;
      if (at === null) delete m.pins[key];
      else m.pins[key] = at;
      s.push("pin", { session: key, at });
      break;
    }
    case "dismiss": {
      const carded = Object.keys(m.card);
      if (carded.length === 0) return anyChange(station, s, r);
      const id = pick(r, carded);
      const seq = m.card[id].seq;
      if (!m.dismissed.includes(`${id}:${seq}`)) m.dismissed.push(`${id}:${seq}`);
      m.card[id] = { ...m.card[id], dismissed: true };
      s.push("dismiss", { thread: Number(id), n: seq });
      break;
    }
    case "kept": {
      const on = r() < 0.5;
      m.kept = toggle(m.kept, t.id, on);
      s.push("kept", { thread: t.id, kept: on });
      break;
    }
    case "marked":
      marked(station, s, t, t.sessions[0]?.session ?? key, r);
      break;
    case "renamed":
      station.threads.set(t.id, { ...t, title: `改了名字 ${Math.floor(r() * 1000)}` });
      s.push("chat-changed", { thread: t.id });
      break;
    case "whole":
      m.teams = { "c-slack-1": pick(r, ["Acme", "Acme Inc", "ACME"]) };
      m.reviews = r() < 0.7;
      s.push("chat-changed", { thread: null });
      break;
    case "new": {
      const made = { ...station.sessions.get(key)!, key: `k-new-${Math.floor(r() * 1e9)}`, title: null, createdAt: s.host.nowMs(), lastActiveAt: s.host.nowMs() };
      station.sessions.set(made.key, made);
      s.push("session", made);
      break;
    }
    case "thread-removed":
      station.threads.delete(t.id);
      s.push("thread-removed", { id: t.id });
      break;
    case "session-removed":
      station.sessions.delete(key);
      for (const [id, x] of station.threads) {
        const sessions = x.sessions.filter((y: J) => y.session !== key);
        if (sessions.length === 0) station.threads.delete(id);
        else if (sessions.length !== x.sessions.length) station.threads.set(id, { ...x, sessions });
      }
      s.push("session-removed", { key });
      break;
  }
  return kind;
}

/// One of the changes a station that makes its chat list for everyone tells, picked by `r`.
export function anySharedChange(station: Station, s: Started, r: () => number): string {
  const rows = [...station.shared.values()];
  const row = pick(r, rows);
  const m = station.marks;
  const kind = pick(r, ["row", "row", "row", "removed", "read", "pin", "kept", "hidden", "dismiss", "marked", "whole"] as const);
  switch (kind) {
    case "row": {
      const at = s.host.nowMs();
      const seq = row.last.seq + 1;
      const now = { ...row, lastActiveAt: at, last: { ...row.last, seq, text: `第 ${seq} 条`, createdAt: at }, said: { n: seq, other: r() < 0.5 ? seq : seq - 1 } };
      station.shared.set(row.id, now);
      s.push("chat-shared", now);
      break;
    }
    case "removed":
      station.shared.delete(row.id);
      s.push("chat-shared-removed", { id: row.id });
      break;
    case "read":
      m.reads[String(row.thread)] = row.last.seq;
      s.push("read", { thread: row.thread, n: row.last.seq });
      break;
    case "pin": {
      const at = r() < 0.6 ? s.host.nowMs() : null;
      if (at === null) delete m.pins[row.id];
      else m.pins[row.id] = at;
      s.push("pin", { session: row.id, at });
      break;
    }
    case "kept":
    case "hidden": {
      const on = r() < 0.5;
      m[kind] = [...m[kind].filter((x: number) => x !== row.thread), ...(on ? [row.thread] : [])];
      s.push(kind, { thread: row.thread, [kind]: on });
      break;
    }
    case "dismiss": {
      const c = row.card ?? row.need;
      if (c === undefined) return anySharedChange(station, s, r);
      if (!m.dismissed.includes(`${row.thread}:${c.seq}`)) m.dismissed.push(`${row.thread}:${c.seq}`);
      s.push("dismiss", { thread: row.thread, n: c.seq });
      break;
    }
    case "marked":
      m.reads[String(row.thread)] = row.last.seq - 1;
      s.push("chat-mark", { session: row.id, thread: row.thread });
      break;
    case "whole":
      m.selves = r() < 0.5 ? ["U04A1B2C3D4"] : ["U04A1B2C3D4", "U05J9K0L1M2"];
      s.push("chat-changed", { thread: null });
      break;
  }
  return kind;
}

// ── what one change makes the core do ──

/// What a change made the core do: rows made, serialised, and taken as written; chat records' JSON read.
export type Did = { made: number; serialised: number; same: number; chatJson: number };

/// Counts the rows of the chat table's JSON the core's database reads.
function counting(s: Started): () => number {
  const sql = s.core.inner.data.of(ST)!.sql as J;
  const all = sql.all.bind(sql);
  let rows = 0;
  sql.all = (q: string, params?: unknown[]) => {
    const out = all(q, params);
    if (/^\s*SELECT\b/i.test(q) && /\b(FROM|JOIN) chat\b/.test(q) && /\bjson\b/.test(q)) rows += out.length;
    return out;
  };
  return () => rows;
}

/// The changes measured one at a time, each of one chat of the list (the same chats at every size: real-size.ts keeps
/// a station's first rows as they are), and what each made the core do.
export const PROBES: Record<string, (station: Station, s: Started, r: () => number) => void> = {
  // (an agent's message in a chat of its own, row 6; a person's, row 10, which reads that chat's marks again)
  "message": (station, s) => said(station, s, station.threads.get(2006)!, false),
  "person": (station, s) => said(station, s, station.threads.get(2010)!, true),
  // (in a Slack thread, row 5: read again, the row of its agent, whose origin it is, made again)
  "slack message": (station, s) => said(station, s, station.threads.get(2005)!, false),
  "summary": (station, s) => summary(station, s, "k-maple-8", { process: "running" }),
  "turn": (station, s) => summary(station, s, "k-maple-9", { lastTurn: { id: "turn-new", kind: "chat", outcome: "done", declared: "block", ending: "need_help", detail: null, startedAt: 1, endedAt: 2 } }),
  "read": (_, s) => s.push("read", { thread: 2012, n: 52 }),
  "pin": (_, s) => s.push("pin", { session: "k-maple-14", at: s.host.nowMs() }),
  "hidden": (_, s) => s.push("hidden", { thread: 2015, hidden: true }),
  "kept": (_, s) => s.push("kept", { thread: 2016, kept: true }),
  "dismiss": (station, s) => s.push("dismiss", { thread: 2018, n: station.marks.card["2018"].seq }),
  "marked": (station, s, r) => marked(station, s, station.threads.get(2020)!, "k-maple-20", r),
  "renamed": (station, s) => {
    station.threads.set(2022, { ...station.threads.get(2022)!, title: "迁移演练" });
    s.push("chat-changed", { thread: 2022 });
  },
  // (all the marks read again: every row a new entry of them reads made again)
  "whole": (_, s) => s.push("chat-changed", { thread: null }),
};
/// Those whose rows are made again as the station's chats are many: none but a whole read of the marks.
export const GROWING = new Set(["whole"]);

/// Each probe on one core, in turn, with what it did, and whether the list stored was what is made anew after each.
export async function probed(): Promise<{ chats: number; did: Record<string, Did>; differ: string[] }> {
  const station = new Station();
  const s = await startedOn(station);
  const chatJson = counting(s);
  const differ: string[] = [];
  const did: Record<string, Did> = {};
  const r = seeded(7);
  for (const [name, probe] of Object.entries(PROBES)) {
    const from = { made: work.chatRowsMade, serialised: work.chatRowsSerialised, same: glanced.chatRowsSame, chatJson: chatJson() };
    probe(station, s, r);
    await s.host.time.pass(1500, 100);
    did[name] = { made: work.chatRowsMade - from.made, serialised: work.chatRowsSerialised - from.serialised, same: glanced.chatRowsSame - from.same, chatJson: chatJson() - from.chatJson };
    for (const d of differences(stored(s), madeAnew(s))) differ.push(`${name}: ${d}`);
  }
  const chats = stored(s).length;
  s.core.close();
  return { chats, did, differ };
}

if (!isMainThread && (workerData as J)?.rowsChanged === true) {
  probed().then((found) => parentPort!.postMessage({ size: SIZE, ...found }), (e) => parentPort!.postMessage({ error: String(e?.stack ?? e) }));
}
