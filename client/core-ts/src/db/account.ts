// One signed-in account's database (docs/core-db.md): the tables of db/schema.ts, read by indexed queries, written by
// one writer. Everything here is synchronous (the host's SQLite is), on the core's one thread.
//
// The writer: every change opens the burst's transaction (BEGIN IMMEDIATE) if none is open and runs in it, so what
// is read next sees it; the database's write fiber commits the burst once the work at hand has run (a burst of
// events is one transaction), then tells what changed in it: the topics whose values changed, the chat rows before
// and after, the logs that grew. A row that did not change is not written. When the disk or the browser's quota is
// full, the burst is rolled back and what this device did itself (the outbox, chats asked for, drafts, …) is written
// again on its own; the rest comes again from the stations.
//
// Reads: a row asked for by key is kept (by identity, frozen) until it is written; a station's list a view shows (its
// chats, sessions, threads, jobs) is loaded by one indexed query the first time it is asked for and from then on kept
// current by the writer, row by row, until no topic reads it. Nothing is loaded at start.
import { Deferred, Effect, type Fiber, Queue } from "effect";
import type { Sql, SqlRow, SqlValue } from "../host.ts";
import { SqlError, sqlError } from "../host.ts";
import { topicKey, type Topic } from "../protocol.ts";
import type { Runner } from "../runtime.ts";
import { equal, isObject } from "../util.ts";
import { ensureKept, ensureSaid, ensureSlackSaid, migrate, versionOf } from "./schema.ts";
import { readItem, type Said } from "../elsewhere.ts";

// deno-lint-ignore no-explicit-any
type J = any;

/// What the core finds a chat row by that only it can say (views/marks.ts, decisions.ts): how urgent the row is for
/// its person, whether it asks something, whether the 奏 page lists it (it asks, was answered, or its agent works).
export type Derive = { tone(row: J): string | null; asks(row: J): boolean; desk?(row: J): boolean };

/// A chat row before and after a burst (undefined: not there).
export type RowChange = { id: string; before: J | undefined; after: J | undefined };

/// What a burst changed.
export type Changes = {
  /// The held topics whose values changed.
  topics: Map<string, Topic>;
  /// Each station's sidebar rows (archived = 0) that changed.
  chats: Map<string, Map<string, RowChange>>;
  /// The logs that changed: [table, station, thread or session].
  logs: Map<string, [string, string, string]>;
  /// The stations whose sidebar rows were read for the first time (where noticing starts from).
  firstChats: Set<string>;
};

/// A station's list a view reads: which rows, in what order.
export type ListKind = "chats" | "archived" | "sessions" | "threads" | "jobs";

export const LIST_OF: Record<string, ListKind> = { chatRows: "chats", archivedRows: "archived", sessions: "sessions", threads: "threads", jobs: "jobs" };
const TOPIC_OF: Record<ListKind, string> = { chats: "chatRows", archived: "archivedRows", sessions: "sessions", threads: "threads", jobs: "jobs" };

const u64 = (v: unknown): number | null => (typeof v === "number" && Number.isInteger(v) && v >= 0 ? v : null);
const str = (v: unknown): string | null => (typeof v === "string" ? v : null);
const num = (v: unknown): number | null => (typeof v === "number" && Number.isFinite(v) ? v : null);
const get = (v: unknown, k: string): J => (isObject(v) ? (v as J)[k] : undefined);

/// Frozen all through: a row as it is kept, shared by every reader (rule 7: a row that did not change is the same
/// object from one read to the next).
export function frozen<T>(v: T): T {
  if (v !== null && typeof v === "object" && !Object.isFrozen(v)) {
    for (const k of Object.keys(v)) frozen((v as Record<string, unknown>)[k]);
    Object.freeze(v);
  }
  return v;
}

const parse = (text: SqlValue): J => (typeof text === "string" ? JSON.parse(text) : undefined);

/// An id as text (a station's ids are strings, threads' numbers).
export function idText(id: unknown): string | null {
  if (typeof id === "string") return id;
  if (typeof id === "number") return String(id);
  return null;
}

/// The session keys taking part in a thread.
export function membersOf(thread: J): string[] {
  const out: string[] = [];
  for (const m of Array.isArray(get(thread, "sessions")) ? thread.sessions : []) if (typeof get(m, "session") === "string") out.push(m.session);
  return out;
}

/// Places for rows given in a new order: those already placed in an order the new one keeps (the longest such run)
/// stay where they are; the others go between their neighbours. So a row put on top, or moved, writes that row alone.
export function placesFor(was: (number | null)[]): number[] {
  const n = was.length;
  const keep = longestRun(was);
  const out = new Array<number>(n);
  for (let i = 0; i < n; i++) if (keep.has(i)) out[i] = was[i]!;
  let i = 0;
  while (i < n) {
    if (keep.has(i)) {
      i++;
      continue;
    }
    let j = i;
    while (j < n && !keep.has(j)) j++;
    const lo = i > 0 ? out[i - 1] : null;
    const hi = j < n ? out[j] : null;
    const count = j - i;
    for (let k = 0; k < count; k++) {
      if (lo === null && hi === null) out[i + k] = k;
      else if (lo === null) out[i + k] = hi! - (count - k);
      else if (hi === null) out[i + k] = lo + k + 1;
      else out[i + k] = lo + ((hi - lo) * (k + 1)) / (count + 1);
    }
    i = j;
  }
  // Places worn too fine to tell apart: all of them anew.
  for (let k = 1; k < n; k++) if (!(out[k] > out[k - 1])) return out.map((_, x) => x);
  return out;
}

function longestRun(values: (number | null)[]): Set<number> {
  const tails: number[] = [];
  const prev = new Array<number>(values.length).fill(-1);
  for (let i = 0; i < values.length; i++) {
    const p = values[i];
    if (p === null) continue;
    let lo = 0;
    let hi = tails.length;
    while (lo < hi) {
      const mid = (lo + hi) >> 1;
      if ((values[tails[mid]] as number) < p) lo = mid + 1;
      else hi = mid;
    }
    if (lo > 0) prev[i] = tails[lo - 1];
    tails[lo] = i;
  }
  const out = new Set<number>();
  for (let i = tails.length > 0 ? tails[tails.length - 1] : -1; i >= 0; i = prev[i]) out.add(i);
  return out;
}

/// A list loaded: its rows by id and where each sorts.
class Collection {
  readonly items = new Map<string, J>();
  readonly sort = new Map<string, number[]>();
  #array: J[] | null = null;
  readonly descending: boolean;
  constructor(descending: boolean) {
    this.descending = descending;
  }

  set(id: string, row: J, sort: number[]): void {
    this.items.set(id, row);
    this.sort.set(id, sort);
    this.#array = null;
  }

  delete(id: string): void {
    if (this.items.delete(id)) {
      this.sort.delete(id);
      this.#array = null;
    }
  }

  /// The rows in order (the same array while nothing changed).
  array(): J[] {
    if (this.#array) return this.#array;
    const ids = [...this.items.keys()];
    const d = this.descending ? -1 : 1;
    ids.sort((a, b) => {
      const x = this.sort.get(a)!;
      const y = this.sort.get(b)!;
      for (let i = 0; i < x.length; i++) if (x[i] !== y[i]) return (x[i] - y[i]) * d;
      return a < b ? -1 : a > b ? 1 : 0;
    });
    this.#array = ids.map((id) => this.items.get(id));
    return this.#array;
  }
}

/// Rows read by key, kept until written; the oldest go past `cap`.
class Cache {
  readonly #map = new Map<string, J>();
  readonly cap: number;
  constructor(cap: number) {
    this.cap = cap;
  }
  get(key: string): J | undefined {
    const v = this.#map.get(key);
    if (v !== undefined) {
      this.#map.delete(key);
      this.#map.set(key, v);
    }
    return v;
  }
  has(key: string): boolean {
    return this.#map.has(key);
  }
  set(key: string, v: J): void {
    this.#map.delete(key);
    this.#map.set(key, v);
    if (this.#map.size > this.cap) this.#map.delete(this.#map.keys().next().value!);
  }
  delete(key: string): void {
    this.#map.delete(key);
  }
  clear(): void {
    this.#map.clear();
  }
}

const K = (...parts: (string | number)[]) => parts.join("\u0001");

/// The tables of what this device did itself: written again on their own when a burst could not be (a full disk).
const PRECIOUS = /^(INSERT|DELETE|UPDATE)[^(]*\b(outbox|pending|first|changing|draft|workspace_pref)\b/i;

/// The chat columns of a row, and its JSON without them.
type ChatCols = { json: string; unread: number | null; thread: number | null; session: string | null; clientKey: string | null; lastActive: number; pinnedAt: number | null; mine: number; running: number; tone: string | null; asks: number; desk: number };

export class AccountDb {
  readonly sub: string;
  readonly name: string;
  readonly sql: Sql;
  /// Written by a newer core: read, never written.
  readonly readOnly: boolean;
  /// Its version as found (before migrating): 0 for a database made now.
  readonly found: number;
  /// How what was said is found: by its full-text index, by scanning it, or not at all (it could not be made).
  readonly #said: "index" | "scan" | null = null;
  /// The logs let go for room (`log_use`), by K(kind, station, id).
  readonly #evicted = new Set<string>();
  readonly #runner: Runner;
  readonly #derive: Derive;
  #inTx = false;
  /// What failed in this burst: it is rolled back.
  #failed: SqlError | null = null;
  #changes: Changes = { topics: new Map(), chats: new Map(), logs: new Map(), firstChats: new Set() };
  /// The statements of this burst that are what the device did itself, to be written again if the burst fails.
  #precious: [string, readonly SqlValue[]][] = [];
  /// What could not be written even so, written again with the next burst.
  #unwritten: [string, readonly SqlValue[]][] = [];
  readonly #bursts: Queue.Queue<void>;
  readonly #writer: Fiber.Fiber<never, never>;
  #waiting: Deferred.Deferred<void>[] = [];
  readonly #cache = new Cache(4096);
  readonly #logCache = new Cache(8192);
  readonly #lists = new Map<string, Collection>();
  #closed = false;
  /// Told after each burst is written, with what it changed.
  onCommit: (changes: Changes) => void = () => {};
  /// Told when a burst could not be written for want of room (true), and once one could again (false).
  onFull: (full: boolean, error: string | null) => void = () => {};
  #full = false;

  constructor(sub: string, name: string, sql: Sql, runner: Runner, derive: Derive) {
    this.sub = sub;
    this.name = name;
    this.sql = sql;
    this.#runner = runner;
    this.#derive = derive;
    this.found = versionOf(sql);
    this.readOnly = !migrate(sql);
    if (!this.readOnly) {
      const was = this.sql.all("SELECT value FROM meta WHERE key = 'account'")[0]?.[0];
      if (was === undefined) this.sql.run("INSERT INTO meta (key, value) VALUES ('account', ?)", [sub]);
      try {
        this.#said = ensureSaid(sql) ? "index" : "scan";
      } catch {
        // No room to make it: messages are not found by their words this time.
      }
      try {
        if (ensureSlackSaid(sql)) this.#fillSlackSaid();
      } catch {
        // No room to make it: what agents said in Slack is not shown in their chats this time.
      }
      try {
        ensureKept(sql);
        for (const r of sql.all("SELECT kind, station, id FROM log_use WHERE evicted = 1")) this.#evicted.add(K(String(r[0]), String(r[1]), String(r[2])));
      } catch {
        // No room to make it: nothing is let go this time.
      }
    } else if (this.sql.all("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'said'").length > 0) {
      this.#said = "scan";
    }
    this.#bursts = Effect.runSync(Queue.unbounded<void>());
    // The one write fiber: a burst is committed once what started it has run.
    this.#writer = runner.fork(Effect.forever(Effect.andThen(Queue.take(this.#bursts), Effect.andThen(Effect.yieldNow, Effect.sync(() => this.#commit())))));
  }

  // ── writing ──

  /// Runs `fn` in the burst's transaction (opened now if none is). A database only read does nothing.
  #write(fn: () => void): void {
    if (this.readOnly || this.#closed) return;
    try {
      if (!this.#inTx) {
        this.#inTx = true;
        Queue.offerUnsafe(this.#bursts, undefined);
        this.sql.exec("BEGIN IMMEDIATE");
      }
      fn();
    } catch (e) {
      // SQLite could not write (no room, the file gone): the burst is rolled back as it is committed, and said.
      if (!(e instanceof SqlError)) throw e;
      this.#failed ??= e;
    }
  }

  #run(sql: string, params: readonly SqlValue[]): number {
    if (PRECIOUS.test(sql)) this.#precious.push([sql, params]);
    return this.sql.run(sql, params);
  }

  #commit(): void {
    if (!this.#inTx) return this.#settled();
    const changes = this.#changes;
    const precious = this.#precious;
    this.#changes = { topics: new Map(), chats: new Map(), logs: new Map(), firstChats: new Set() };
    this.#precious = [];
    this.#inTx = false;
    const failed = this.#failed;
    this.#failed = null;
    try {
      if (failed) throw failed;
      // What could not be written before goes first.
      if (this.#unwritten.length > 0) {
        for (const [sql, params] of this.#unwritten) this.sql.run(sql, params);
      }
      this.sql.exec("COMMIT");
      this.#unwritten = [];
      if (this.#full) {
        this.#full = false;
        this.onFull(false, null);
      }
    } catch (e) {
      const error = sqlError(e);
      try {
        this.sql.exec("ROLLBACK");
      } catch {
        // Rolled back already.
      }
      // What was read is not what is kept any more.
      this.#cache.clear();
      this.#logCache.clear();
      this.#lists.clear();
      const again = [...this.#unwritten, ...precious];
      this.#unwritten = [];
      if (again.length > 0) {
        try {
          this.sql.exec("BEGIN IMMEDIATE");
          for (const [sql, params] of again) this.sql.run(sql, params);
          this.sql.exec("COMMIT");
        } catch {
          try {
            this.sql.exec("ROLLBACK");
          } catch {
            // Rolled back already.
          }
          this.#unwritten = again;
        }
      }
      if (error.kind === "full" && !this.#full) {
        this.#full = true;
        this.onFull(true, error.message);
      } else if (error.kind !== "full") console.error("still.fail core: a write failed:", error.message);
    }
    this.onCommit(changes);
    this.#settled();
  }

  #settled(): void {
    const waiting = this.#waiting;
    this.#waiting = [];
    for (const d of waiting) Deferred.doneUnsafe(d, Effect.void);
  }

  /// Resolves once what was written so far is committed.
  get written(): Effect.Effect<void> {
    return Effect.suspend(() => {
      if (!this.#inTx) return Effect.void;
      return Effect.flatMap(Deferred.make<void>(), (d) => {
        this.#waiting.push(d);
        return Deferred.await(d);
      });
    });
  }

  /// Whether a write is waiting for room.
  get full(): boolean {
    return this.#full;
  }

  #tell(topic: Topic): void {
    this.#changes.topics.set(topicKey(topic), topic);
  }

  #tellChat(station: string, id: string, before: J | undefined, after: J | undefined): void {
    let m = this.#changes.chats.get(station);
    if (!m) {
      m = new Map();
      this.#changes.chats.set(station, m);
    }
    const was = m.get(id);
    m.set(id, { id, before: was ? was.before : before, after });
  }

  #tellLog(table: string, station: string, id: string): void {
    this.#changes.logs.set(K(table, station, id), [table, station, id]);
  }

  close(): void {
    if (this.#closed) return;
    if (this.#inTx) this.#commit();
    this.#closed = true;
    this.#runner.interrupt(this.#writer as Fiber.Fiber<unknown, unknown>);
    this.sql.close();
  }

  // ── documents: one JSON value by key ──

  /// The account's own documents (`me`, `login_sessions`, `admin/<list>`).
  accountDoc(name: string): J {
    return this.#doc(K("acct", name), "SELECT json FROM account_doc WHERE name = ?", [name]);
  }

  putAccountDoc(name: string, value: J, confirmed: number | null, topic: Topic | null): void {
    this.#putDoc(K("acct", name), value, "SELECT json FROM account_doc WHERE name = ?", [name], "INSERT INTO account_doc (name, json, confirmed) VALUES (?, ?, ?) ON CONFLICT (name) DO UPDATE SET json = excluded.json, confirmed = coalesce(excluded.confirmed, confirmed)", (json) => [name, json, confirmed], topic);
  }

  dropAccountDoc(name: string, topic: Topic | null): void {
    this.#dropDoc(K("acct", name), "DELETE FROM account_doc WHERE name = ?", [name], topic);
  }

  workspace(id: string): J {
    return this.#doc(K("ws", id), "SELECT json FROM workspace WHERE id = ?", [id]);
  }

  putWorkspace(id: string, value: J, confirmed: number | null): void {
    this.#putDoc(K("ws", id), value, "SELECT json FROM workspace WHERE id = ?", [id], "INSERT INTO workspace (id, json, confirmed) VALUES (?, ?, ?) ON CONFLICT (id) DO UPDATE SET json = excluded.json, confirmed = coalesce(excluded.confirmed, confirmed)", (json) => [id, json, confirmed], { topic: "workspace", workspace: id });
  }

  dropWorkspace(id: string): void {
    this.#dropDoc(K("ws", id), "DELETE FROM workspace WHERE id = ?", [id], { topic: "workspace", workspace: id });
  }

  workspaceIds(): string[] {
    return this.sql.all("SELECT id FROM workspace").map((r) => String(r[0]));
  }

  /// A station's overview, footprint or usage.
  stationDoc(station: string, kind: string): J {
    return this.#doc(K("st", station, kind), "SELECT json FROM station WHERE address = ? AND kind = ?", [station, kind]);
  }

  putStationDoc(station: string, kind: string, value: J, confirmed: number | null, topic: Topic): void {
    this.#putDoc(K("st", station, kind), value, "SELECT json FROM station WHERE address = ? AND kind = ?", [station, kind], "INSERT INTO station (address, kind, json, confirmed) VALUES (?, ?, ?, ?) ON CONFLICT (address, kind) DO UPDATE SET json = excluded.json, confirmed = coalesce(excluded.confirmed, confirmed)", (json) => [station, kind, json, confirmed], topic);
  }

  slackApp(station: string, connect: string): J {
    return this.#doc(K("slack", station, connect), "SELECT json FROM slack_app WHERE station = ? AND connect = ?", [station, connect]);
  }

  putSlackApp(station: string, connect: string, value: J, confirmed: number | null): void {
    this.#putDoc(K("slack", station, connect), value, "SELECT json FROM slack_app WHERE station = ? AND connect = ?", [station, connect], "INSERT INTO slack_app (station, connect, json, confirmed) VALUES (?, ?, ?, ?) ON CONFLICT (station, connect) DO UPDATE SET json = excluded.json, confirmed = coalesce(excluded.confirmed, confirmed)", (json) => [station, connect, json, confirmed], { topic: "slackApp", station, connect });
  }

  draft(station: string, chat: string): J {
    return this.#doc(K("draft", station, chat), "SELECT json FROM draft WHERE station = ? AND chat = ?", [station, chat]);
  }

  putDraft(station: string, chat: string, value: J | undefined): void {
    const topic = { topic: "draft", station, chat };
    if (value === undefined) this.#dropDoc(K("draft", station, chat), "DELETE FROM draft WHERE station = ? AND chat = ?", [station, chat], topic);
    else this.#putDoc(K("draft", station, chat), value, "SELECT json FROM draft WHERE station = ? AND chat = ?", [station, chat], "INSERT OR REPLACE INTO draft (station, chat, json) VALUES (?, ?, ?)", (json) => [station, chat, json], topic);
  }

  workspacePref(workspace: string, key: string): J {
    return this.#doc(K("wpref", workspace, key), "SELECT json FROM workspace_pref WHERE workspace = ? AND key = ?", [workspace, key]);
  }

  putWorkspacePref(workspace: string, key: string, value: J | undefined): void {
    if (value === undefined) this.#dropDoc(K("wpref", workspace, key), "DELETE FROM workspace_pref WHERE workspace = ? AND key = ?", [workspace, key], null);
    else this.#putDoc(K("wpref", workspace, key), value, "SELECT json FROM workspace_pref WHERE workspace = ? AND key = ?", [workspace, key], "INSERT OR REPLACE INTO workspace_pref (workspace, key, json) VALUES (?, ?, ?)", (json) => [workspace, key, json], null);
  }

  /// What this device did and its station has not confirmed (views/local.ts): every row of one of its tables.
  locals(table: "outbox" | "pending" | "first" | "changing"): [string, string, J][] {
    const key = table === "outbox" ? "thread" : table === "pending" ? "key" : table === "first" ? "session" : "id";
    return this.sql.all(`SELECT station, ${key}, json FROM ${table} ORDER BY station, ${key}`).map((r) => [String(r[0]), String(r[1]), parse(r[2])]);
  }

  putLocal(table: "outbox" | "pending" | "first" | "changing", station: string, key: string, value: J | undefined): void {
    this.#write(() => {
      const column = table === "outbox" ? "thread" : table === "pending" ? "key" : table === "first" ? "session" : "id";
      const k: SqlValue = table === "outbox" || table === "changing" ? Number(key) : key;
      if (value === undefined) this.#run(`DELETE FROM ${table} WHERE station = ? AND ${column} = ?`, [station, k]);
      else if (table === "pending") this.#run("INSERT OR REPLACE INTO pending (key, station, json) VALUES (?, ?, ?)", [key, station, JSON.stringify(value)]);
      else this.#run(`INSERT OR REPLACE INTO ${table} (station, ${column}, json) VALUES (?, ?, ?)`, [station, k, JSON.stringify(value)]);
    });
  }

  #doc(key: string, select: string, params: SqlValue[]): J {
    if (this.#cache.has(key)) return this.#cache.get(key) ?? undefined;
    const row = this.sql.all(select, params)[0];
    const value = row ? frozen(parse(row[0])) : undefined;
    this.#cache.set(key, value ?? null);
    return value;
  }

  #putDoc(key: string, value: J, select: string, selectParams: SqlValue[], upsert: string, params: (json: string) => SqlValue[], topic: Topic | null): void {
    this.#write(() => {
      const json = JSON.stringify(value);
      const was = this.sql.all(select, selectParams)[0]?.[0];
      if (was === json) {
        // The same: only when it was confirmed changes.
        const p = params(json);
        if (p[p.length - 1] !== null) this.#run(upsert, p);
        return;
      }
      this.#run(upsert, params(json));
      this.#cache.set(key, frozen(JSON.parse(json)));
      if (topic) this.#tell(topic);
    });
  }

  #dropDoc(key: string, del: string, params: SqlValue[], topic: Topic | null): void {
    this.#write(() => {
      if (this.#run(del, params) > 0 && topic) this.#tell(topic);
      this.#cache.set(key, null);
    });
  }

  // ── lists ──

  /// Whether a station's list has been read (else it is not known: undefined, not empty).
  listed(station: string, list: ListKind): boolean {
    const key = K("listed", station, list);
    if (this.#cache.has(key)) return this.#cache.get(key) === true;
    const known = this.sql.all("SELECT 1 FROM list WHERE station = ? AND list = ?", [station, list]).length > 0;
    this.#cache.set(key, known);
    return known;
  }

  /// How often a station's sidebar rows changed (what a change made here waits on: views/local.ts).
  rowsRev(station: string): number {
    const v = this.sql.all("SELECT rev FROM list WHERE station = ? AND list = 'chats'", [station])[0]?.[0];
    return typeof v === "number" ? v : 0;
  }

  #markListed(station: string, list: ListKind, confirmed: number | null, changed: boolean): void {
    const known = this.listed(station, list);
    this.#run("INSERT INTO list (station, list, confirmed, rev) VALUES (?, ?, ?, ?) ON CONFLICT (station, list) DO UPDATE SET confirmed = coalesce(excluded.confirmed, confirmed), rev = rev + ?", [station, list, confirmed, changed ? 1 : 0, changed ? 1 : 0]);
    this.#cache.set(K("listed", station, list), true);
    if (!known) {
      this.#tell({ topic: TOPIC_OF[list], station });
      if (list === "chats") this.#changes.firstChats.add(station);
    }
  }

  #bumpRev(station: string, list: ListKind): void {
    this.#run("INSERT INTO list (station, list, confirmed, rev) VALUES (?, ?, NULL, 1) ON CONFLICT (station, list) DO UPDATE SET rev = rev + 1", [station, list]);
  }

  /// A list as a topic shows it: its rows in order, undefined while it was never read. Loaded the first time.
  list(station: string, kind: ListKind): J[] | undefined {
    if (!this.listed(station, kind)) return undefined;
    return this.#collection(station, kind).array();
  }

  /// Lets go of a list nobody reads (its topic went).
  release(station: string, kind: ListKind): void {
    this.#lists.delete(K(kind, station));
  }

  /// Whether a list is loaded (a view reads it at once).
  loaded(station: string, kind: ListKind): boolean {
    return this.#lists.has(K(kind, station));
  }

  #collection(station: string, kind: ListKind): Collection {
    const key = K(kind, station);
    let c = this.#lists.get(key);
    if (c) return c;
    c = new Collection(kind === "threads");
    switch (kind) {
      case "chats":
      case "archived":
        for (const r of this.sql.all("SELECT id, ord, json, unread FROM chat WHERE station = ? AND archived = ?", [station, kind === "archived" ? 1 : 0])) {
          const id = String(r[0]);
          c.set(id, this.#chatRow(station, kind === "archived" ? 1 : 0, id, r[2], r[3]), [r[1] as number]);
        }
        break;
      case "sessions":
        for (const r of this.sql.all("SELECT key, ord, summary FROM session WHERE station = ? AND listed = 1", [station])) c.set(String(r[0]), this.#cached(K("sum", station, String(r[0])), r[2]), [r[1] as number]);
        break;
      case "threads":
        for (const r of this.sql.all("SELECT id, sort_at, created_at, json, last, read, unread FROM thread WHERE station = ? AND listed = 1", [station])) {
          c.set(String(r[0]), this.#threadRow(station, r[0] as number, r[3], r[4], r[5], r[6]), [r[1] as number, r[2] as number, r[0] as number]);
        }
        break;
      case "jobs":
        for (const r of this.sql.all("SELECT id, ord, json, chat FROM job WHERE station = ? AND open = 1", [station])) c.set(String(r[0]), this.#jobItem(station, String(r[0]), r[2], r[3]), [r[1] as number]);
        break;
    }
    this.#lists.set(key, c);
    return c;
  }

  #loadedList(station: string, kind: ListKind): Collection | undefined {
    return this.#lists.get(K(kind, station));
  }

  /// A row parsed once and kept by its key until written.
  #cached(key: string, json: SqlValue, make?: (parsed: J) => J): J {
    const hit = this.#cache.get(key);
    if (hit !== undefined && hit !== null) return hit;
    const v = frozen(make ? make(parse(json)) : parse(json));
    this.#cache.set(key, v);
    return v;
  }

  // ── chats ──

  #chatRow(station: string, archived: number, id: string, json: SqlValue, unread: SqlValue): J {
    return this.#cached(K("chat", station, archived, id), json, (row) => {
      if (unread !== null && unread !== undefined) row.unread = unread === 1;
      return row;
    });
  }

  #chatCols(row: J): ChatCols {
    const rest = { ...row };
    const unread = typeof rest.unread === "boolean" ? (rest.unread ? 1 : 0) : null;
    delete rest.unread;
    let running = 0;
    for (const a of Array.isArray(row.agents) ? row.agents : []) if (get(a, "process") === "running") running = 1;
    return {
      json: JSON.stringify(rest),
      unread,
      thread: u64(row.thread),
      session: str(row.session),
      clientKey: str(row.clientKey),
      lastActive: num(row.lastActiveAt) ?? 0,
      pinnedAt: num(row.pinned),
      mine: row.mine === true ? 1 : 0,
      running,
      tone: this.#derive.tone(row),
      asks: this.#derive.asks(row) ? 1 : 0,
      desk: this.#derive.desk?.(row) ? 1 : 0,
    };
  }

  #putChatRow(station: string, archived: number, id: string, row: J, ord: number, before: J | undefined): void {
    const c = this.#chatCols(row);
    this.#run(
      "INSERT OR REPLACE INTO chat (station, id, archived, ord, thread, session, client_key, last_active, pinned_at, unread, mine, running, tone, asks, desk, json) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
      [station, id, archived, ord, c.thread, c.session, c.clientKey, c.lastActive, c.pinnedAt, c.unread, c.mine, c.running, c.tone, c.asks, c.desk, c.json],
    );
    const kept = frozen(JSON.parse(JSON.stringify(row)));
    this.#cache.set(K("chat", station, archived, id), kept);
    this.#loadedList(station, archived ? "archived" : "chats")?.set(id, kept, [ord]);
    if (!archived) this.#tellChat(station, id, before, kept);
    this.#tell({ topic: archived ? "archivedRows" : "chatRows", station });
  }

  /// A station's chat list as read: rows that changed are written, those gone deleted, the list read.
  setChats(station: string, archived: boolean, rows: J[], confirmed: number | null): void {
    this.#write(() => {
      const a = archived ? 1 : 0;
      const was = new Map<string, SqlRow>();
      for (const r of this.sql.all("SELECT id, ord, json, unread FROM chat WHERE station = ? AND archived = ? ORDER BY ord", [station, a])) was.set(String(r[0]), r);
      const items: [string, J][] = [];
      const seen = new Set<string>();
      for (const row of rows) {
        const id = idText(get(row, "id"));
        if (id === null || seen.has(id)) continue;
        seen.add(id);
        items.push([id, row]);
      }
      const places = placesFor(items.map(([id]) => (was.has(id) ? (was.get(id)![1] as number) : null)));
      let changed = false;
      items.forEach(([id, row], i) => {
        const before = was.get(id);
        const c = this.#chatCols(row);
        if (before && before[1] === places[i] && before[2] === c.json && before[3] === c.unread) return;
        changed = true;
        this.#putChatRow(station, a, id, row, places[i], before ? this.#chatRow(station, a, id, before[2], before[3]) : undefined);
      });
      for (const [id, r] of was) {
        if (seen.has(id)) continue;
        changed = true;
        this.#deleteChatRow(station, a, id, this.#chatRow(station, a, id, r[2], r[3]));
      }
      this.#markListed(station, archived ? "archived" : "chats", confirmed, changed);
    });
  }

  #deleteChatRow(station: string, archived: number, id: string, before: J | undefined): void {
    this.#run("DELETE FROM chat WHERE station = ? AND archived = ? AND id = ?", [station, archived, id]);
    this.#cache.delete(K("chat", station, archived, id));
    this.#loadedList(station, archived ? "archived" : "chats")?.delete(id);
    if (!archived) this.#tellChat(station, id, before, undefined);
    this.#tell({ topic: archived ? "archivedRows" : "chatRows", station });
  }

  /// A sidebar row as an event has it: in place, or last when new. Nothing while the station's rows were never read.
  putChat(station: string, row: J): void {
    const id = idText(get(row, "id"));
    if (id === null || !this.listed(station, "chats")) return;
    this.#write(() => {
      const r = this.sql.all("SELECT ord, json, unread FROM chat WHERE station = ? AND archived = 0 AND id = ?", [station, id])[0];
      const c = this.#chatCols(row);
      if (r && r[1] === c.json && r[2] === c.unread) return;
      const ord = r ? (r[0] as number) : ((this.sql.all("SELECT max(ord) FROM chat WHERE station = ? AND archived = 0", [station])[0]?.[0] as number | null) ?? -1) + 1;
      this.#putChatRow(station, 0, id, row, ord, r ? this.#chatRow(station, 0, id, r[1], r[2]) : undefined);
      this.#bumpRev(station, "chats");
    });
  }

  dropChat(station: string, id: string): void {
    this.#write(() => {
      const r = this.sql.all("SELECT json, unread FROM chat WHERE station = ? AND archived = 0 AND id = ?", [station, id])[0];
      if (!r) return;
      this.#deleteChatRow(station, 0, id, this.#chatRow(station, 0, id, r[0], r[1]));
      this.#bumpRev(station, "chats");
    });
  }

  /// A sidebar row by its id.
  chat(station: string, id: string): J {
    const r = this.sql.all("SELECT json, unread FROM chat WHERE station = ? AND archived = 0 AND id = ?", [station, id])[0];
    return r ? this.#chatRow(station, 0, id, r[0], r[1]) : undefined;
  }

  /// The sidebar row of a thread.
  chatOfThread(station: string, thread: number): J {
    const r = this.sql.all("SELECT id, json, unread FROM chat WHERE station = ? AND archived = 0 AND thread = ? ORDER BY ord LIMIT 1", [station, thread])[0];
    return r ? this.#chatRow(station, 0, String(r[0]), r[1], r[2]) : undefined;
  }

  /// The sidebar row of an agent's session.
  chatOfSession(station: string, session: string): J {
    const r = this.sql.all("SELECT id, json, unread FROM chat WHERE station = ? AND archived = 0 AND session = ? ORDER BY ord LIMIT 1", [station, session])[0];
    return r ? this.#chatRow(station, 0, String(r[0]), r[1], r[2]) : undefined;
  }

  /// The sidebar row asked for here under a client key (views/local.ts).
  chatOfClientKey(station: string, key: string): J {
    const r = this.sql.all("SELECT id, json, unread FROM chat WHERE station = ? AND archived = 0 AND client_key = ? LIMIT 1", [station, key])[0];
    return r ? this.#chatRow(station, 0, String(r[0]), r[1], r[2]) : undefined;
  }

  /// The rows of these stations a list shows first: the pinned, then the latest active, `limit` of them.
  chatHead(stations: string[], limit: number): [string, J][] {
    if (stations.length === 0) return [];
    const marks = stations.map(() => "?").join(", ");
    return this.sql
      .all(`SELECT station, id, json, unread FROM chat WHERE archived = 0 AND station IN (${marks}) ORDER BY pinned_at DESC, last_active DESC LIMIT ?`, [...stations, limit])
      .map((r) => [String(r[0]), this.#chatRow(String(r[0]), 0, String(r[1]), r[2], r[3])]);
  }

  /// How many sidebar rows these stations have.
  chatCount(stations: string[]): number {
    if (stations.length === 0) return 0;
    return (this.sql.all(`SELECT count(*) FROM chat WHERE archived = 0 AND station IN (${stations.map(() => "?").join(", ")})`, stations)[0]?.[0] as number) ?? 0;
  }

  /// The rows of these stations that ask something of their person or are unread (views/marks.ts).
  marked(stations: string[]): [string, J][] {
    if (stations.length === 0) return [];
    const marks = stations.map(() => "?").join(", ");
    return this.sql
      .all(`SELECT station, id, json, unread FROM chat WHERE archived = 0 AND station IN (${marks}) AND (tone IS NOT NULL OR asks = 1)`, stations)
      .map((r) => [String(r[0]), this.#chatRow(String(r[0]), 0, String(r[1]), r[2], r[3])]);
  }

  /// The rows of these stations the 奏 page lists (db/account.ts Derive.desk), in the stations' order.
  desk(stations: string[]): [string, J][] {
    if (stations.length === 0) return [];
    const marks = stations.map(() => "?").join(", ");
    return this.sql
      .all(`SELECT station, id, json, unread FROM chat WHERE archived = 0 AND desk = 1 AND station IN (${marks}) ORDER BY station, ord`, stations)
      .map((r) => [String(r[0]), this.#chatRow(String(r[0]), 0, String(r[1]), r[2], r[3])]);
  }

  /// The rows of a station whose agents are at work.
  running(station: string): J[] {
    return this.sql.all("SELECT id, json, unread FROM chat WHERE station = ? AND archived = 0 AND running = 1", [station]).map((r) => this.#chatRow(station, 0, String(r[0]), r[1], r[2]));
  }

  /// The viewer read a thread up to `n`: its rows unread no more where that covers their last message.
  #readRows(station: string, thread: number, n: number): void {
    for (const r of this.sql.all("SELECT id, ord, json, unread FROM chat WHERE station = ? AND archived = 0 AND thread = ? AND unread = 1", [station, thread])) {
      const id = String(r[0]);
      const before = this.#chatRow(station, 0, id, r[2], r[3]);
      const last = u64(get(get(before, "last"), "seq"));
      if (last !== null && n < last) continue;
      const after = { ...before, unread: false };
      this.#putChatRow(station, 0, id, after, r[1] as number, before);
      this.#bumpRev(station, "chats");
    }
  }

  // ── sessions ──

  #sessionCols(summary: J): SqlValue[] {
    return [num(get(summary, "lastActiveAt")), str(get(summary, "process")), str(get(summary, "connect")), num(get(summary, "archivedAt")), u64(get(summary, "turns"))];
  }

  /// A session's summary.
  summary(station: string, key: string): J {
    const r = this.sql.all("SELECT summary FROM session WHERE station = ? AND key = ?", [station, key])[0];
    return r && r[0] !== null ? this.#cached(K("sum", station, key), r[0]) : undefined;
  }

  /// A session's summary if its station lists it (it is not archived).
  listedSummary(station: string, key: string): J {
    const r = this.sql.all("SELECT summary FROM session WHERE station = ? AND key = ? AND listed = 1", [station, key])[0];
    return r && r[0] !== null ? this.#cached(K("sum", station, key), r[0]) : undefined;
  }

  /// A station's sessions as read: summaries written where they changed, those no longer listed unlisted.
  setSessions(station: string, list: J[], confirmed: number | null): void {
    this.#write(() => {
      const was = new Map<string, SqlRow>();
      for (const r of this.sql.all("SELECT key, ord, summary, listed, detail FROM session WHERE station = ?", [station])) was.set(String(r[0]), r);
      const items: [string, J][] = [];
      const seen = new Set<string>();
      for (const s of list) {
        const key = str(get(s, "key"));
        if (key === null || seen.has(key)) continue;
        seen.add(key);
        items.push([key, s]);
      }
      const places = placesFor(items.map(([key]) => (was.get(key)?.[3] === 1 ? (was.get(key)![1] as number) : null)));
      let changed = false;
      items.forEach(([key, s], i) => {
        const r = was.get(key);
        const json = JSON.stringify(s);
        if (r && r[3] === 1 && r[1] === places[i] && r[2] === json) return;
        changed = true;
        this.#putSummary(station, key, s, json, 1, places[i], r !== undefined, r?.[4] !== null && r?.[4] !== undefined);
      });
      for (const [key, r] of was) {
        if (seen.has(key) || r[3] !== 1) continue;
        changed = true;
        this.#run("UPDATE session SET listed = 0 WHERE station = ? AND key = ?", [station, key]);
        this.#loadedList(station, "sessions")?.delete(key);
        this.#tell({ topic: "sessions", station });
      }
      this.#markListed(station, "sessions", confirmed, changed);
    });
  }

  #putSummary(station: string, key: string, summary: J, json: string, listed: number, ord: number, exists: boolean, hasDetail: boolean): void {
    const cols = this.#sessionCols(summary);
    if (exists) this.#run("UPDATE session SET summary = ?, listed = ?, ord = ?, last_active = ?, process = ?, connect = ?, archived_at = ?, turns = ? WHERE station = ? AND key = ?", [json, listed, ord, ...cols, station, key]);
    else this.#run("INSERT INTO session (station, key, listed, ord, last_active, process, connect, archived_at, turns, summary) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", [station, key, listed, ord, ...cols, json]);
    const kept = frozen(JSON.parse(json));
    this.#cache.set(K("sum", station, key), kept);
    const list = this.#loadedList(station, "sessions");
    if (listed) list?.set(key, kept, [ord]);
    else list?.delete(key);
    this.#tell({ topic: "sessions", station });
    if (hasDetail) this.#tellSession(station, key);
  }

  #tellSession(station: string, key: string): void {
    this.#cache.delete(K("detail", station, key));
    this.#tell({ topic: "session", station, key });
  }

  /// A session's summary as an event has it: in place among the listed (first when new) while it is not archived,
  /// out of the list once it is. Answers whether its detail is to be read again (its turns changed, or none is held).
  putSummary(station: string, summary: J): boolean {
    const key = str(get(summary, "key"));
    if (key === null) return false;
    let again = false;
    this.#write(() => {
      const r = this.sql.all("SELECT ord, summary, listed, detail, turns FROM session WHERE station = ? AND key = ?", [station, key])[0];
      const shown = (get(summary, "archivedAt") ?? null) === null;
      const listKnown = this.listed(station, "sessions");
      const listed = shown && listKnown ? 1 : r && !shown ? 0 : ((r?.[2] as number | undefined) ?? 0);
      let ord = r ? (r[0] as number) : 0;
      if (listed === 1 && r?.[2] !== 1) ord = ((this.sql.all("SELECT min(ord) FROM session WHERE station = ? AND listed = 1", [station])[0]?.[0] as number | null) ?? 1) - 1;
      const json = JSON.stringify(summary);
      const detail = r && r[3] !== null ? parse(r[3]) : undefined;
      again = detail === undefined || !sameTurns(get(detail, "turns"), summary);
      // Its detail shows it as it is now too.
      if (detail !== undefined && JSON.stringify(detail.session) !== json) {
        detail.session = summary;
        this.#run("UPDATE session SET detail = ? WHERE station = ? AND key = ?", [JSON.stringify(detail), station, key]);
        this.#tellSession(station, key);
      }
      if (r && r[1] === json && r[2] === listed) return;
      this.#putSummary(station, key, summary, json, listed, ord, r !== undefined, false);
    });
    return again;
  }

  /// A session gone from its station: its summary, detail, transcript and membership of threads; threads it alone took
  /// part in go too.
  dropSession(station: string, key: string): void {
    this.#write(() => {
      const r = this.sql.all("SELECT listed, detail FROM session WHERE station = ? AND key = ?", [station, key])[0];
      if (r) {
        this.#run("DELETE FROM session WHERE station = ? AND key = ?", [station, key]);
        this.#cache.delete(K("sum", station, key));
        this.#loadedList(station, "sessions")?.delete(key);
        this.#tell({ topic: "sessions", station });
        this.#tellSession(station, key);
      }
      for (const t of this.sql.all("SELECT thread FROM thread_member WHERE station = ? AND session = ?", [station, key])) {
        const id = t[0] as number;
        const row = this.thread(station, id);
        if (!row) continue;
        const sessions = (Array.isArray(row.sessions) ? row.sessions : []).filter((m: J) => get(m, "session") !== key);
        if (sessions.length === 0) this.#deleteThread(station, id);
        else this.#putThreadRow(station, { ...row, sessions }, null);
      }
      this.#run("DELETE FROM thread_member WHERE station = ? AND session = ?", [station, key]);
      if (this.#run("DELETE FROM transcript WHERE station = ? AND session = ?", [station, key]) > 0) this.#tellLog("transcript", station, key);
    });
  }

  /// A session's detail as a topic shows it: its summary, turns and jobs as read (the summary as events since say), and
  /// its threads as their rows are now: those it read as its own and those whose members it is among.
  detail(station: string, key: string): J {
    const ck = K("detail", station, key);
    const hit = this.#cache.get(ck);
    if (hit !== undefined) return hit ?? undefined;
    const r = this.sql.all("SELECT detail FROM session WHERE station = ? AND key = ?", [station, key])[0];
    if (!r || r[0] === null) {
      this.#cache.set(ck, null);
      return undefined;
    }
    const detail = parse(r[0]);
    detail.threads = this.#detailThreads(station, key, Array.isArray(detail.threadIds) ? detail.threadIds : []);
    delete detail.threadIds;
    const v = frozen(detail);
    this.#cache.set(ck, v);
    return v;
  }

  /// Whether a session's detail is held.
  hasDetail(station: string, key: string): boolean {
    return this.sql.all("SELECT 1 FROM session WHERE station = ? AND key = ? AND detail IS NOT NULL", [station, key]).length > 0;
  }

  #detailThreads(station: string, key: string, ids: number[]): J[] {
    const rows = this.sql.all(
      `SELECT id, json, last, read, unread FROM thread WHERE station = ? AND (id IN (SELECT thread FROM thread_member WHERE station = ? AND session = ?)${ids.length > 0 ? ` OR id IN (${ids.map(() => "?").join(", ")})` : ""}) ORDER BY sort_at DESC, created_at DESC, id DESC`,
      [station, station, key, ...ids],
    );
    return rows.map((r) => this.#threadRow(station, r[0] as number, r[1], r[2], r[3], r[4]));
  }

  /// A session's detail as read (GET /sessions/:key): its threads into their rows (the ids it named kept), the rest
  /// kept as it came.
  setDetail(station: string, key: string, answer: J): void {
    this.#write(() => {
      const rest: J = { ...answer };
      const threads = Array.isArray(rest.threads) ? rest.threads : [];
      delete rest.threads;
      rest.threadIds = threads.flatMap((t: J) => (u64(get(t, "id")) === null ? [] : [t.id]));
      const json = JSON.stringify(rest);
      const r = this.sql.all("SELECT detail FROM session WHERE station = ? AND key = ?", [station, key])[0];
      if (!r) this.#run("INSERT INTO session (station, key, listed, ord) VALUES (?, ?, 0, 0)", [station, key]);
      const changed = !r || r[0] !== json;
      if (changed) this.#run("UPDATE session SET detail = ? WHERE station = ? AND key = ?", [json, station, key]);
      for (const view of threads) this.#upsertThread(station, view, false);
      if (changed) this.#tellSession(station, key);
    });
  }

  /// A thread a session is no longer in: out of the ids its detail named.
  #leftThread(station: string, key: string, id: number): void {
    const r = this.sql.all("SELECT detail FROM session WHERE station = ? AND key = ?", [station, key])[0];
    if (!r || r[0] === null) return;
    const detail = parse(r[0]);
    if (!Array.isArray(detail.threadIds) || !detail.threadIds.includes(id)) return;
    detail.threadIds = detail.threadIds.filter((t: number) => t !== id);
    this.#run("UPDATE session SET detail = ? WHERE station = ? AND key = ?", [JSON.stringify(detail), station, key]);
  }

  /// Changes a session's detail in place (a job's event); nothing while none is held.
  patchDetail(station: string, key: string, change: (detail: J) => void): void {
    this.#write(() => {
      const r = this.sql.all("SELECT detail FROM session WHERE station = ? AND key = ?", [station, key])[0];
      if (!r || r[0] === null) return;
      const detail = parse(r[0]);
      change(detail);
      const json = JSON.stringify(detail);
      if (json === r[0]) return;
      this.#run("UPDATE session SET detail = ? WHERE station = ? AND key = ?", [json, station, key]);
      this.#tellSession(station, key);
    });
  }

  /// A station's sessions with whether each one's detail is to be read again (none held, or its turns changed).
  sessionsToRead(station: string): [string, boolean][] {
    return this.sql.all("SELECT key, summary, detail FROM session WHERE station = ? AND listed = 1 ORDER BY ord", [station]).map((r) => {
      const detail = r[2] === null ? undefined : parse(r[2]);
      return [String(r[0]), detail === undefined || !sameTurns(get(detail, "turns"), parse(r[1]))];
    });
  }

  // ── threads ──

  #threadRow(station: string, id: number, json: SqlValue, last: SqlValue, read: SqlValue, unread: SqlValue): J {
    return this.#cached(K("thread", station, id), json, (t) => {
      if (last !== null) t.last = last;
      if (read !== null) t.read = read;
      if (unread !== null) t.unread = unread;
      return t;
    });
  }

  /// A thread's summary, listed or not.
  thread(station: string, id: number): J {
    const hit = this.#cache.get(K("thread", station, id));
    if (hit) return hit;
    const r = this.sql.all("SELECT json, last, read, unread FROM thread WHERE station = ? AND id = ?", [station, id])[0];
    return r ? this.#threadRow(station, id, r[0], r[1], r[2], r[3]) : undefined;
  }

  /// A thread's summary if its station lists it.
  listedThread(station: string, id: number): J {
    const r = this.sql.all("SELECT json, last, read, unread FROM thread WHERE station = ? AND id = ? AND listed = 1", [station, id])[0];
    return r ? this.#threadRow(station, id, r[0], r[1], r[2], r[3]) : undefined;
  }

  /// The station's chat bound to an agent: the still.fail thread it started.
  threadOf(station: string, session: string): number | null {
    const r = this.sql.all("SELECT id FROM thread WHERE station = ? AND listed = 1 AND first_member = ? AND surface IN ('ember', 'stillfail') ORDER BY sort_at DESC, created_at DESC, id DESC LIMIT 1", [station, session])[0];
    return r ? (r[0] as number) : null;
  }

  /// A station's listed threads' ids.
  threadIds(station: string): number[] {
    return this.sql.all("SELECT id FROM thread WHERE station = ? AND listed = 1 ORDER BY sort_at DESC, created_at DESC, id DESC", [station]).map((r) => r[0] as number);
  }

  /// How far a thread goes as its summary says (0 when none is held).
  threadLast(station: string, id: number): number {
    const v = this.sql.all("SELECT last FROM thread WHERE station = ? AND id = ?", [station, id])[0]?.[0];
    return typeof v === "number" ? v : 0;
  }

  #threadCols(view: J): { json: string; last: number | null; read: number | null; unread: number | null; sortAt: number; createdAt: number; surface: string | null; first: string | null } {
    const rest = { ...view };
    delete rest.last;
    delete rest.read;
    delete rest.unread;
    return {
      json: JSON.stringify(rest),
      last: u64(view.last),
      read: u64(view.read),
      unread: u64(view.unread),
      sortAt: num(get(view.lastMessage, "createdAt")) ?? 0,
      createdAt: num(view.createdAt) ?? 0,
      surface: str(view.surface),
      first: membersOf(view)[0] ?? null,
    };
  }

  /// Writes a thread's row (`listed` null: as it was), its membership and what shows it.
  #putThreadRow(station: string, view: J, listed: number | null): void {
    const id = u64(view.id)!;
    const c = this.#threadCols(view);
    const r = this.sql.all("SELECT listed, json, last, read, unread FROM thread WHERE station = ? AND id = ?", [station, id])[0];
    const isListed = listed ?? ((r?.[0] as number | undefined) ?? 0);
    if (r && r[0] === isListed && r[1] === c.json && r[2] === c.last && r[3] === c.read && r[4] === c.unread) return;
    const before = r ? this.thread(station, id) : undefined;
    this.#run(
      "INSERT OR REPLACE INTO thread (station, id, listed, last, read, unread, sort_at, created_at, surface, first_member, json) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
      [station, id, isListed, c.last, c.read, c.unread, c.sortAt, c.createdAt, c.surface, c.first, c.json],
    );
    this.#cache.delete(K("thread", station, id));
    const row = this.#threadRow(station, id, c.json, c.last, c.read, c.unread);
    const members = membersOf(view);
    const was = before ? membersOf(before) : [];
    if (members.join("\u0001") !== was.join("\u0001")) {
      this.#run("DELETE FROM thread_member WHERE station = ? AND thread = ?", [station, id]);
      for (const m of new Set(members)) this.#run("INSERT OR IGNORE INTO thread_member (station, session, thread) VALUES (?, ?, ?)", [station, m, id]);
      for (const m of was) if (!members.includes(m)) this.#leftThread(station, m, id);
    }
    const list = this.#loadedList(station, "threads");
    if (isListed) list?.set(String(id), row, [c.sortAt, c.createdAt, id]);
    else list?.delete(String(id));
    if (isListed || r?.[0] === 1) this.#tell({ topic: "threads", station });
    for (const m of new Set([...members, ...was])) this.#tellSession(station, m);
    this.#tell({ topic: "thread", station, thread: id });
  }

  #upsertThread(station: string, view: J, list: boolean): void {
    if (u64(get(view, "id")) === null) return;
    this.#putThreadRow(station, view, list ? 1 : null);
  }

  #deleteThread(station: string, id: number): void {
    const before = this.thread(station, id);
    const r = this.sql.all("SELECT listed FROM thread WHERE station = ? AND id = ?", [station, id])[0];
    if (!r) return;
    this.#run("DELETE FROM thread WHERE station = ? AND id = ?", [station, id]);
    this.#run("DELETE FROM thread_member WHERE station = ? AND thread = ?", [station, id]);
    this.#cache.delete(K("thread", station, id));
    this.#loadedList(station, "threads")?.delete(String(id));
    if (r[0] === 1) this.#tell({ topic: "threads", station });
    for (const m of new Set(membersOf(before))) this.#tellSession(station, m);
    this.#tell({ topic: "thread", station, thread: id });
  }

  /// A station's threads as read.
  setThreads(station: string, list: J[], confirmed: number | null): void {
    this.#write(() => {
      const seen = new Set<number>();
      for (const view of list) {
        const id = u64(get(view, "id"));
        if (id === null || seen.has(id)) continue;
        seen.add(id);
        this.#putThreadRow(station, view, 1);
      }
      let changed = false;
      for (const r of this.sql.all("SELECT id FROM thread WHERE station = ? AND listed = 1", [station])) {
        const id = r[0] as number;
        if (seen.has(id)) continue;
        changed = true;
        this.#run("UPDATE thread SET listed = 0 WHERE station = ? AND id = ?", [station, id]);
        this.#loadedList(station, "threads")?.delete(String(id));
        this.#tell({ topic: "threads", station });
      }
      this.#markListed(station, "threads", confirmed, changed);
    });
  }

  /// A thread's summary into the station's threads (listed from now on) and the sessions taking part.
  putThread(station: string, view: J): void {
    this.#write(() => this.#upsertThread(station, view, this.listed(station, "threads")));
  }

  /// A thread gone: its row and its entries.
  dropThread(station: string, id: number): void {
    this.#write(() => {
      this.#deleteThread(station, id);
      this.#forgetEntries(station, id);
    });
  }

  /// A thread out of the lists (it is not there any more), its entries kept.
  unlistThread(station: string, id: number): void {
    this.#write(() => this.#deleteThread(station, id));
  }

  /// A thread goes at least to `n` (an event, a message sent).
  raiseLast(station: string, id: number, n: number): void {
    this.#write(() => {
      const r = this.sql.all("SELECT last FROM thread WHERE station = ? AND id = ?", [station, id])[0];
      if (!r || (typeof r[0] === "number" && r[0] >= n)) return;
      this.#run("UPDATE thread SET last = ? WHERE station = ? AND id = ?", [n, station, id]);
      this.#threadChanged(station, id);
    });
  }

  #threadChanged(station: string, id: number): void {
    this.#cache.delete(K("thread", station, id));
    const row = this.thread(station, id);
    if (!row) return;
    const r = this.sql.all("SELECT listed, sort_at, created_at FROM thread WHERE station = ? AND id = ?", [station, id])[0];
    if (r?.[0] === 1) {
      this.#loadedList(station, "threads")?.set(String(id), row, [r[1] as number, r[2] as number, id]);
      this.#tell({ topic: "threads", station });
    }
    for (const m of new Set(membersOf(row))) this.#tellSession(station, m);
    this.#tell({ topic: "thread", station, thread: id });
  }

  /// The viewer read a thread up to `n`: its position moves there, nothing unread once that covers its last entry.
  /// Answers whether the count of what is unread is to be read again.
  setRead(station: string, id: number, n: number): boolean {
    let stale = false;
    this.#write(() => {
      const r = this.sql.all("SELECT read, last FROM thread WHERE station = ? AND id = ?", [station, id])[0];
      if (r && !(typeof r[0] === "number" && r[0] >= n)) {
        const last = r[1];
        if (last === null || n >= (last as number)) this.#run("UPDATE thread SET read = ?, unread = 0 WHERE station = ? AND id = ?", [n, station, id]);
        else {
          this.#run("UPDATE thread SET read = ? WHERE station = ? AND id = ?", [n, station, id]);
          stale = true;
        }
        this.#threadChanged(station, id);
      }
      this.#readRows(station, id, n);
    });
    return stale;
  }

  /// How far the viewer has read a thread, as its summary says.
  readPosition(station: string, id: number): number | null {
    const v = this.sql.all("SELECT read FROM thread WHERE station = ? AND id = ?", [station, id])[0]?.[0];
    return typeof v === "number" ? v : null;
  }

  // ── jobs ──

  #jobItem(station: string, id: string, json: SqlValue, chat: SqlValue): J {
    return this.#cached(K("jobitem", station, id), json, (job) => {
      if (chat !== null && chat !== undefined) job.chat = parse(chat);
      return job;
    });
  }

  /// A job as it is now.
  job(station: string, id: string): J {
    const r = this.sql.all("SELECT json FROM job WHERE station = ? AND id = ?", [station, id])[0];
    return r ? this.#cached(K("job", station, id), r[0]) : undefined;
  }

  /// A station's open jobs as read (GET /jobs), each with its chat.
  setJobs(station: string, list: J[], confirmed: number | null): void {
    this.#write(() => {
      const was = new Map<string, SqlRow>();
      for (const r of this.sql.all("SELECT id, ord, json, chat, open FROM job WHERE station = ?", [station])) was.set(String(r[0]), r);
      const items: [string, J][] = [];
      const seen = new Set<string>();
      for (const j of list) {
        const id = idText(get(j, "id"));
        if (id === null || seen.has(id)) continue;
        seen.add(id);
        items.push([id, j]);
      }
      const places = placesFor(items.map(([id]) => (was.get(id)?.[4] === 1 ? (was.get(id)![1] as number) : null)));
      let changed = false;
      items.forEach(([id, item], i) => {
        const job = { ...item };
        const chat = job.chat === undefined ? null : JSON.stringify(job.chat);
        delete job.chat;
        const json = JSON.stringify(job);
        const r = was.get(id);
        if (r && r[4] === 1 && r[1] === places[i] && r[2] === json && r[3] === chat) return;
        changed = true;
        this.#putJobRow(station, id, json, chat, 1, places[i], str(get(job, "session")));
      });
      for (const [id, r] of was) {
        if (seen.has(id) || r[4] !== 1) continue;
        changed = true;
        this.#run("UPDATE job SET open = 0 WHERE station = ? AND id = ?", [station, id]);
        this.#loadedList(station, "jobs")?.delete(id);
        this.#tell({ topic: "jobs", station });
      }
      this.#markListed(station, "jobs", confirmed, changed);
    });
  }

  #putJobRow(station: string, id: string, json: string, chat: string | null, open: number, ord: number, session: string | null): void {
    this.#run("INSERT OR REPLACE INTO job (station, id, session, open, ord, chat, json) VALUES (?, ?, ?, ?, ?, ?, ?)", [station, id, session, open, ord, chat, json]);
    this.#cache.delete(K("job", station, id));
    this.#cache.delete(K("jobitem", station, id));
    const list = this.#loadedList(station, "jobs");
    if (open) list?.set(id, this.#jobItem(station, id, json, chat), [ord]);
    else list?.delete(id);
    this.#tell({ topic: "jobs", station });
    this.#tell({ topic: "job", station, id });
  }

  /// A job as an event has it: as it is now, among the open ones while it is open (with the chat the list said).
  /// Answers whether it is open and the list does not have it (which chat it is in is the station's to say).
  putJob(station: string, job: J, open: boolean): boolean {
    const id = idText(get(job, "id"));
    if (id === null) return false;
    let unknown = false;
    this.#write(() => {
      const r = this.sql.all("SELECT ord, json, chat, open FROM job WHERE station = ? AND id = ?", [station, id])[0];
      const json = JSON.stringify(job);
      const wasOpen = r?.[3] === 1;
      const nowOpen = open && wasOpen ? 1 : 0;
      if (open && !wasOpen) unknown = this.listed(station, "jobs");
      if (r && r[1] === json && (r[3] as number) === nowOpen) return;
      this.#putJobRow(station, id, json, (r?.[2] as string | null | undefined) ?? null, nowOpen, (r?.[0] as number | undefined) ?? 0, str(get(job, "session")));
    });
    return unknown;
  }

  // ── what was said ──

  /// The messages of these stations whose latest text has every one of `terms` (case aside), newest first: the full-text
  /// index finds those of three characters or more, shorter ones are looked for in what it found (or in everything).
  findSaid(stations: string[], terms: string[], limit: number): { station: string; thread: number; seq: number; at: number | null; text: string }[] {
    if (this.#said === null || stations.length === 0 || terms.length === 0) return [];
    const indexed = this.#said === "index" ? terms.filter((t) => [...t].length >= 3) : [];
    const scanned = terms.filter((t) => !indexed.includes(t));
    const where = [`s.station IN (${stations.map(() => "?").join(", ")})`, ...scanned.map(() => "s.text LIKE ? ESCAPE '\\'")];
    const params: SqlValue[] = [...stations, ...scanned.map((t) => `%${t.replace(/[\\%_]/g, (c) => `\\${c}`)}%`)];
    let from = "said s";
    if (indexed.length > 0) {
      from = "said_index JOIN said s ON s.id = said_index.rowid";
      where.unshift("said_index MATCH ?");
      params.unshift(indexed.map((t) => `"${t.replace(/"/g, '""')}"`).join(" "));
    }
    params.push(limit);
    return this.sql
      .all(`SELECT s.station, s.thread, s.seq, s.at, s.text FROM ${from} WHERE ${where.join(" AND ")} ORDER BY s.at IS NULL, s.at DESC, s.seq DESC LIMIT ?`, params)
      .map((r) => ({ station: String(r[0]), thread: Number(r[1]), seq: Number(r[2]), at: typeof r[3] === "number" ? r[3] : null, text: String(r[4]) }));
  }

  // ── what is kept within the device's room ──

  /// How much of the database is in use (its pages less the free ones), in bytes.
  used(): number {
    const n = (q: string) => Number(this.sql.all(q)[0]?.[0] ?? 0);
    return (n("PRAGMA page_count") - n("PRAGMA freelist_count")) * n("PRAGMA page_size");
  }

  /// Whether a log's items were let go for room (and not brought back since).
  evicted(kind: "entry" | "transcript", station: string, id: string): boolean {
    return this.#evicted.has(K(kind, station, id));
  }

  /// A log's chat opened here: the most recently opened, and kept again (its items brought back by the sync). Answers
  /// whether they had been let go.
  opened(kind: "entry" | "transcript", station: string, id: string, at: number): boolean {
    const was = this.#evicted.delete(K(kind, station, id));
    this.#write(() => {
      this.sql.run("INSERT INTO log_use (kind, station, id, opened, evicted) VALUES (?, ?, ?, ?, 0) ON CONFLICT (kind, station, id) DO UPDATE SET opened = excluded.opened, evicted = 0", [kind, station, id, at]);
    });
    return was;
  }

  /// The logs held, of `kind`, least recently used first: by when their chat was last opened here or last said
  /// something (an agent's: last active), whichever is later.
  logsByUse(kind: "entry" | "transcript", limit: number): { station: string; id: string }[] {
    const rows =
      kind === "entry"
        ? this.sql.all(
            `SELECT e.station, e.thread FROM (SELECT DISTINCT station, thread FROM entry) e
             LEFT JOIN log_use u ON u.kind = 'entry' AND u.station = e.station AND u.id = CAST(e.thread AS TEXT)
             LEFT JOIN thread t ON t.station = e.station AND t.id = e.thread
             ORDER BY max(coalesce(u.opened, 0), coalesce(t.sort_at, 0), coalesce(t.created_at, 0)), e.station, e.thread LIMIT ?`,
            [limit],
          )
        : this.sql.all(
            `SELECT x.station, x.session FROM (SELECT DISTINCT station, session FROM transcript) x
             LEFT JOIN log_use u ON u.kind = 'transcript' AND u.station = x.station AND u.id = x.session
             LEFT JOIN session s ON s.station = x.station AND s.key = x.session
             ORDER BY max(coalesce(u.opened, 0), coalesce(s.last_active, 0)), x.station, x.session LIMIT ?`,
            [limit],
          );
    return rows.map((r) => ({ station: String(r[0]), id: String(r[1]) }));
  }

  /// A log's items let go for room: they are read again when its chat is opened. Its thread, read position and row stay.
  evict(kind: "entry" | "transcript", station: string, id: string): void {
    this.#evicted.add(K(kind, station, id));
    this.#write(() => {
      this.#logCache.clear();
      if (kind === "entry") this.#forgetEntries(station, Number(id));
      else if (this.sql.run("DELETE FROM transcript WHERE station = ? AND session = ?", [station, id]) > 0) this.#tellLog("transcript", station, id);
      this.sql.run("INSERT INTO log_use (kind, station, id, evicted) VALUES (?, ?, ?, 1) ON CONFLICT (kind, station, id) DO UPDATE SET evicted = 1", [kind, station, id]);
    });
  }

  // ── a thread's entries and a session's transcript ──

  /// The numbers of a log's items held, in order.
  logNumbers(table: "entry" | "transcript", station: string, id: string): number[] {
    const [key, col] = table === "entry" ? ["thread", "n"] : ["session", "i"];
    return this.sql.all(`SELECT ${col} FROM ${table} WHERE station = ? AND ${key} = ? ORDER BY ${col}`, [station, table === "entry" ? Number(id) : id]).map((r) => r[0] as number);
  }

  /// A log's items `from ..= to` held, by number.
  logRange(table: "entry" | "transcript", station: string, id: string, from: number, to: number): Map<number, J> {
    const [key, col] = table === "entry" ? ["thread", "n"] : ["session", "i"];
    const out = new Map<number, J>();
    const rows = this.sql.all(`SELECT ${col}, json FROM ${table} WHERE station = ? AND ${key} = ? AND ${col} BETWEEN ? AND ? ORDER BY ${col}`, [station, table === "entry" ? Number(id) : id, from, to]);
    for (const r of rows) {
      const n = r[0] as number;
      out.set(n, this.#logItem(table, station, id, n, r[1]));
    }
    return out;
  }

  #logItem(table: string, station: string, id: string, n: number, json: SqlValue): J {
    const key = K(table, station, id, n);
    const hit = this.#logCache.get(key);
    if (hit !== undefined) return hit;
    const v = frozen(parse(json));
    this.#logCache.set(key, v);
    return v;
  }

  /// The highest and lowest numbers a log holds, and how many (null when it holds none).
  logSpan(table: "entry" | "transcript", station: string, id: string): { min: number; max: number; count: number } | null {
    const [key, col] = table === "entry" ? ["thread", "n"] : ["session", "i"];
    const r = this.sql.all(`SELECT min(${col}), max(${col}), count(*) FROM ${table} WHERE station = ? AND ${key} = ?`, [station, table === "entry" ? Number(id) : id])[0];
    return r && r[2] !== 0 ? { min: r[0] as number, max: r[1] as number, count: r[2] as number } : null;
  }

  /// How many of `from ..= to` a log holds.
  logCount(table: "entry" | "transcript", station: string, id: string, from: number, to: number): number {
    const [key, col] = table === "entry" ? ["thread", "n"] : ["session", "i"];
    return (this.sql.all(`SELECT count(*) FROM ${table} WHERE station = ? AND ${key} = ? AND ${col} BETWEEN ? AND ?`, [station, table === "entry" ? Number(id) : id, from, to])[0]?.[0] as number) ?? 0;
  }

  /// Items into a log, by number; those it holds the same are not written. `cutAfter`: nothing past it is kept.
  /// `keep`: what is held stays (an import: what the sync brought is newer).
  putLog(table: "entry" | "transcript", station: string, id: string, items: [number, J][], cutAfter: number | null = null, keep = false): void {
    if (items.length === 0 && cutAfter === null) return;
    this.#write(() => {
      const [key, col] = table === "entry" ? ["thread", "n"] : ["session", "i"];
      const k: SqlValue = table === "entry" ? Number(id) : id;
      let changed = false;
      const written: [number, J][] = [];
      if (items.length > 0) {
        let lo = Infinity;
        let hi = -Infinity;
        for (const [n] of items) {
          lo = Math.min(lo, n);
          hi = Math.max(hi, n);
        }
        const held = new Map<number, SqlValue>();
        for (const r of this.sql.all(`SELECT ${col}, json FROM ${table} WHERE station = ? AND ${key} = ? AND ${col} BETWEEN ? AND ?`, [station, k, lo, hi])) held.set(r[0] as number, r[1]);
        for (const [n, value] of items) {
          const json = JSON.stringify(value);
          const was = held.get(n);
          if (was === json || (keep && was !== undefined)) continue;
          this.sql.run(`INSERT OR REPLACE INTO ${table} (station, ${key}, ${col}, json) VALUES (?, ?, ?, ?)`, [station, k, n, json]);
          this.#logCache.delete(K(table, station, id, n));
          written.push([n, value]);
          changed = true;
        }
      }
      if (cutAfter !== null) {
        for (const r of this.sql.all(`SELECT ${col} FROM ${table} WHERE station = ? AND ${key} = ? AND ${col} > ?`, [station, k, cutAfter])) this.#logCache.delete(K(table, station, id, r[0] as number));
        if (this.sql.run(`DELETE FROM ${table} WHERE station = ? AND ${key} = ? AND ${col} > ?`, [station, k, cutAfter]) > 0) changed = true;
      }
      if (table === "transcript" && this.#hasSlackSaid()) {
        let said = false;
        if (cutAfter !== null && this.sql.run("DELETE FROM slack_said WHERE station = ? AND session = ? AND i > ?", [station, id, cutAfter]) > 0) said = true;
        if (written.length > 0 && this.#readSlackSaid(station, id, written)) said = true;
        if (said) this.#tellLog("slack", station, id);
      }
      if (changed) this.#tellLog(table, station, id);
    });
  }

  #slackSaidMade: boolean | undefined;
  #hasSlackSaid(): boolean {
    this.#slackSaidMade ??= this.sql.all("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'slack_said'").length > 0;
    return this.#slackSaidMade;
  }

  /// What transcript items of a session say of Slack, into `slack_said`; calls' results, onto what they sent. Answers
  /// whether anything changed.
  #readSlackSaid(station: string, session: string, items: [number, J][]): boolean {
    let changed = false;
    for (const [n, e] of [...items].sort((a, b) => a[0] - b[0])) {
      const read = readItem(n, e);
      if (read === null) continue;
      if ("said" in read) {
        for (const s of read.said) {
          this.sql.run(
            "INSERT OR REPLACE INTO slack_said (station, session, i, k, out, call, user, who, at, dest, text, failed) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)",
            [station, session, n, s.k, s.out ? 1 : 0, s.call, s.user, s.who, s.at, s.to, s.text],
          );
          changed = true;
        }
        continue;
      }
      const r = read.result;
      // Its call by its id, else the item just before it.
      const where = r.call !== null ? "call = ?" : "i = ?";
      const row = this.sql.all(`SELECT i, dest, failed FROM slack_said WHERE station = ? AND session = ? AND out = 1 AND ${where}`, [station, session, r.call ?? n - 1])[0];
      if (row === undefined) continue;
      const dest = String(row[1]);
      // A message of its own in a channel: Slack's answer says its thread.
      const to = r.ts !== null && !dest.includes("/") ? `${dest}/${r.ts}` : dest;
      if (to === dest && (row[2] === 1) === r.failed) continue;
      this.sql.run("UPDATE slack_said SET dest = ?, failed = ? WHERE station = ? AND session = ? AND i = ? AND out = 1", [to, r.failed ? 1 : 0, station, session, row[0] as number]);
      changed = true;
    }
    return changed;
  }

  /// `slack_said` made now: filled from the transcripts held.
  #fillSlackSaid(): void {
    const sessions = this.sql.all("SELECT DISTINCT station, session FROM transcript");
    if (sessions.length === 0) return;
    this.sql.exec("BEGIN IMMEDIATE");
    try {
      for (const [station, session] of sessions) {
        const items = this.sql.all("SELECT i, json FROM transcript WHERE station = ? AND session = ? ORDER BY i", [station as string, session as string]).map((r) => [r[0] as number, parse(r[1])] as [number, J]);
        this.#readSlackSaid(station as string, session as string, items);
      }
      this.sql.exec("COMMIT");
    } catch (e) {
      try {
        this.sql.exec("ROLLBACK");
      } catch {
        // Rolled back already.
      }
      throw e;
    }
  }

  /// What a session said in Slack and heard from it, in the order of its transcript.
  slackSaid(station: string, session: string): Said[] {
    if (!this.#hasSlackSaid()) return [];
    return this.sql.all("SELECT i, k, out, call, user, who, at, dest, text, failed FROM slack_said WHERE station = ? AND session = ? ORDER BY i, k", [station, session])
      .map((r) => ({
        i: r[0] as number, k: r[1] as number, out: r[2] === 1, call: (r[3] as string | null) ?? null, user: (r[4] as string | null) ?? null,
        who: (r[5] as string | null) ?? null, at: r[6] as number, to: r[7] as string, text: r[8] as string, failed: r[9] === 1,
      }));
  }

  #forgetEntries(station: string, thread: number): void {
    if (this.sql.run("DELETE FROM entry WHERE station = ? AND thread = ?", [station, thread]) > 0) this.#tellLog("entry", station, String(thread));
  }

  /// A log known no more.
  forgetLog(table: "entry" | "transcript", station: string, id: string): void {
    this.#write(() => {
      if (table === "entry") this.#forgetEntries(station, Number(id));
      else {
        if (this.sql.run("DELETE FROM transcript WHERE station = ? AND session = ?", [station, id]) > 0) this.#tellLog("transcript", station, id);
        if (this.#hasSlackSaid() && this.sql.run("DELETE FROM slack_said WHERE station = ? AND session = ?", [station, id]) > 0) this.#tellLog("slack", station, id);
      }
    });
  }

  /// What this database keeps of each chat (a thread): its entries and its sessions' transcripts, in characters of
  /// their JSON (near enough their bytes), with its title and sessions; a session's transcript counted with its first
  /// thread. For the device's page of what it keeps (`cache.usage`).
  cacheUsage(): { station: string; thread: number; title: string | null; sessions: string[]; bytes: number }[] {
    const out = new Map<string, { station: string; thread: number; title: string | null; sessions: string[]; bytes: number }>();
    const of = (station: string, thread: number) => {
      const k = `${station}\0${thread}`;
      let row = out.get(k);
      if (row === undefined) out.set(k, (row = { station, thread, title: null, sessions: [], bytes: 0 }));
      return row;
    };
    for (const r of this.sql.all("SELECT station, thread, sum(length(json)) FROM entry GROUP BY station, thread")) of(r[0] as string, r[1] as number).bytes += Number(r[2] ?? 0);
    const firstThread = new Map<string, number>();
    for (const r of this.sql.all("SELECT station, session, thread FROM thread_member ORDER BY station, session, thread")) {
      const [station, session, thread] = [r[0] as string, r[1] as string, r[2] as number];
      of(station, thread).sessions.push(session);
      if (!firstThread.has(`${station}\0${session}`)) firstThread.set(`${station}\0${session}`, thread);
    }
    for (const r of this.sql.all("SELECT station, session, sum(length(json)) FROM transcript GROUP BY station, session")) {
      const thread = firstThread.get(`${r[0] as string}\0${r[1] as string}`);
      if (thread !== undefined) of(r[0] as string, thread).bytes += Number(r[2] ?? 0);
    }
    for (const row of out.values()) {
      const json = this.sql.all("SELECT json FROM thread WHERE station = ? AND id = ?", [row.station, row.thread])[0]?.[0];
      const title = json === undefined ? undefined : (parse(json) as { title?: unknown })?.title;
      if (typeof title === "string" && title.trim() !== "") row.title = title;
    }
    return [...out.values()].filter((r) => r.bytes > 0);
  }

  /// Forgets what is kept of a chat: its entries and its sessions' transcripts (read again from its station when it is
  /// opened). What waits to be sent, drafts and the chat's row stay.
  forgetChat(station: string, thread: number): void {
    this.#write(() => {
      const sessions = this.sql.all("SELECT session FROM thread_member WHERE station = ? AND thread = ?", [station, thread]).map((r) => r[0] as string);
      this.#logCache.clear();
      this.#forgetEntries(station, thread);
      for (const session of sessions) if (this.sql.run("DELETE FROM transcript WHERE station = ? AND session = ?", [station, session]) > 0) this.#tellLog("transcript", station, session);
    });
  }

  // ── what goes ──

  /// Every station this database holds anything of.
  stations(): string[] {
    const out = new Set<string>();
    for (const [table, column] of [["station", "address"], ["list", "station"], ["chat", "station"], ["session", "station"], ["thread", "station"], ["job", "station"], ["slack_app", "station"], ["outbox", "station"], ["pending", "station"], ["first", "station"], ["changing", "station"], ["draft", "station"]]) {
      for (const r of this.sql.all(`SELECT DISTINCT ${column} FROM ${table}`)) out.add(String(r[0]));
    }
    return [...out].sort();
  }

  /// What is held of a station goes, every table of it.
  forgetStation(station: string): void {
    this.#write(() => {
      for (const [table, column] of [["station", "address"], ["slack_app", "station"], ["list", "station"], ["chat", "station"], ["session", "station"], ["thread", "station"], ["thread_member", "station"], ["entry", "station"], ["transcript", "station"], ["job", "station"], ["outbox", "station"], ["pending", "station"], ["first", "station"], ["changing", "station"], ["draft", "station"]]) {
        this.sql.run(`DELETE FROM ${table} WHERE ${column} = ?`, [station]);
      }
      if (this.sql.all("SELECT 1 FROM sqlite_master WHERE name = 'log_use'").length > 0) this.sql.run("DELETE FROM log_use WHERE station = ?", [station]);
      if (this.#hasSlackSaid()) this.sql.run("DELETE FROM slack_said WHERE station = ?", [station]);
      for (const key of [...this.#evicted]) if (key.split("\u0001")[1] === station) this.#evicted.delete(key);
      this.#cache.clear();
      this.#logCache.clear();
      for (const key of [...this.#lists.keys()]) if (key.endsWith(`\u0001${station}`)) this.#lists.delete(key);
      for (const topic of ["overview", "footprint", "stationUsage", "chatRows", "archivedRows", "sessions", "threads", "jobs"]) this.#tell({ topic, station });
    });
  }

  // ── the meta table ──

  meta(key: string): string | null {
    const v = this.sql.all("SELECT value FROM meta WHERE key = ?", [key])[0]?.[0];
    return typeof v === "string" ? v : null;
  }

  setMeta(key: string, value: string): void {
    this.#write(() => void this.sql.run("INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)", [key, value]));
  }

  /// Several writes as one (an import): run now, in the burst's transaction.
  batch(fn: () => void): void {
    this.#write(fn);
  }

  /// A read only database's error, for a test.
  static isSqlError(e: unknown): e is SqlError {
    return e instanceof SqlError;
  }
}

/// Whether the turns a session detail lists still end as its summary says.
export function sameTurns(turns: unknown, summary: unknown): boolean {
  const list = Array.isArray(turns) ? turns : [];
  if (get(summary, "turns") !== list.length) return false;
  const lastTurn = get(summary, "lastTurn") ?? null;
  const record = list.length > 0 ? list[list.length - 1] : null;
  if (record === null && lastTurn === null) return true;
  if (record === null || lastTurn === null) return false;
  return ["kind", "outcome", "declared", "detail", "startedAt", "endedAt"].every((k) => equal(get(record, k), get(lastTurn, k)));
}
