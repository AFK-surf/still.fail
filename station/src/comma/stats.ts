// What Comma keeps of the workspace through a Comma connect, as a Comma station sends of its own (Cue's
// systems/station/src/stats and connector/task-index.ts), of this station and of the other stations of its workspace
// (read of them as `outflow.read`, peer.ts):
// - the Stats index (`stats.index`), source `stillfail`: what the agents spent, by day, chat, person, account and
//   model, and the chats they worked in;
// - the Task index (`task.index`): the chats as Comma lists the Tasks its stations host, which the Router reads and
//   writes in through the connect (`task.read`, `task.say`, surface.ts), each with what it asks of whom now
//   (`attention`, `waits_for`, `note`: read/outflow.ts attentionOf) and its link in the app (`url`), for Comma to
//   remind them by, and `router: true` when a Comma Router ever wrote in it (read/outflow.ts routerWrote), for
//   Comma's clients to list those alone.
// Both cover the last BUILD_DAYS, are kept per workspace under <data>/comma-indexes, numbered as their rows change, and each
// connection sends Comma what it does not hold yet, a page at a time.
//
// Built as Comma first connects, a minute after the agents' spending was recorded, as a chat moves or someone reads
// one (a minute after too), and every hour (another station's changes reach it so); one build at a time.
import { createHash, randomBytes } from "node:crypto";
import { mkdirSync } from "node:fs";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { installStatsAge, statsAgeCandidates, statsAgeReady, statsAgeStep } from "./stats-age.ts";

type Json = any;

/// The days a build takes again: what can still change (a call recorded late, a chat going on).
export const BUILD_DAYS = 31;
const DAY_MS = 24 * 60 * 60_000;
const SETTLE_MS = 60_000;
const EVERY_MS = 60 * 60_000;
// A writer that keeps committing while the old rows are classified can keep dirtying them indefinitely. After
// several such turns, apply the still-dirty rows with the original predicate instead of never finishing the build.
const ACTIVE_REPAIR_TURNS = 4;
/// The source the rows are of, as Comma's analysis names it.
export const SOURCE = "stillfail";
const SEP = "\u0000";
/// Comma keeps at most this many characters of a Task's title, and of its creator.
const MAX_TITLE = 120;
const MAX_TEXT = 200;

/// What one station of the workspace gave: its usage rows (`outflowUsage`'s) and chats (`outflowChats`'), and the
/// people its rows name. `station`: another station's id; none for this one.
export type StationRows = { station?: string; usage: Json; chats: Json[] };

/// What a build reads: this station's rows, and those of each other station of the workspace that answered
/// (`unread`, the ids of those that did not: their rows stay as they were).
export type Read = (from: number, to: number) => Promise<{ stations: StationRows[]; unread: string[]; valid?: () => boolean }>;

/// A row as an index keeps it.
export type IndexRow = { key: string; source: string; kind: string; rev: number; removed: boolean; json: string };

/// A chat as the Task index and the Router name it: its thread here, `<thread>@<station>` on another station.
export const chatRef = (thread: number, station?: string) => (station === undefined ? String(thread) : `${thread}@${station}`);

/// The chat a Task index ref names, as chatRef made it; null for anything else.
export function chatOf(ref: string): { thread: number; station: string | null } | null {
  const m = /^([0-9]+)(?:@(.+))?$/.exec(ref);
  const thread = m ? Number(m[1]) : NaN;
  return m && Number.isSafeInteger(thread) && thread > 0 ? { thread, station: m[2] ?? null } : null;
}

/// Who a person is, as Comma counts them: their email, so one heard in the app and in a chat app adds up to one, else
/// their name, else the station's reference.
function who(person: Json, ref: string | null): string | null {
  if (typeof person?.email === "string" && person.email !== "") return person.email;
  if (typeof person?.name === "string" && person.name !== "") return person.name;
  return ref;
}

const cut = (value: unknown, max: number): string | null => (typeof value === "string" && value !== "" ? [...value].slice(0, max).join("") : null);

/// A chat's state as a Comma Task's status: at work, waiting for a person, done, archived.
function statusOf(chat: Json): string {
  if (chat.archived === true) return "archived";
  if (chat.state === "need_human") return "needs_review";
  if (chat.state === "all_done" || chat.state === "ended") return "done";
  return "in_progress";
}

/// One station's Stats index rows, by key.
export function statsRowsOf(given: StationRows, fromDay: string): Map<string, { kind: string; json: string }> {
  const at = given.station === undefined ? [] : [`@${given.station}`];
  const station = given.station === undefined ? {} : { station: given.station };
  const people = given.usage?.people ?? {};
  const rows = new Map<string, { kind: string; json: string }>();
  for (const r of Array.isArray(given.usage?.rows) ? given.usage.rows : []) {
    if (typeof r?.day !== "string" || typeof r?.session !== "string" || r.day < fromDay) continue;
    const row = {
      day: r.day, session: r.session, thread: r.thread ?? null, person: who(people[r.person], r.person ?? null), personRef: r.person ?? null,
      account: r.account ?? null, runtime: r.runtime, model: r.model ?? null, calls: r.calls, input: r.input, cacheRead: r.cacheRead,
      cacheWrite: r.cacheWrite, output: r.output, cost: r.cost ?? null, ...station,
    };
    rows.set([SOURCE, "usage", ...at, r.day, r.session, r.person ?? "", r.account ?? "", r.runtime, r.model ?? ""].join(SEP), { kind: "usage", json: JSON.stringify(row) });
  }
  for (const c of given.chats) {
    if (typeof c?.thread !== "number") continue;
    const row = {
      thread: c.thread, surface: c.surface ?? "unknown", title: c.title ?? "", state: c.state ?? null,
      creator: c.creator === null || c.creator === undefined ? null : who(c.creator, c.creator.ref ?? null),
      createdAt: c.createdAt ?? 0, lastActiveAt: c.lastActiveAt ?? 0, archived: c.archived === true, agents: c.agents ?? [], ...station,
    };
    rows.set([SOURCE, "task", ...at, String(c.thread)].join(SEP), { kind: "task", json: JSON.stringify(row) });
  }
  return rows;
}

/// What a Task asks of someone, as Comma takes it: Comma's bounds on whom (`waits_for`), its sentence and its link.
const ATTENTION = ["need", "done", "failed"];
const MAX_WAITS = 8;
const MAX_NOTE = 300;
const MAX_URL = 500;

/// What a chat asks of whom now as a Task index row's fields (outflow.ts attentionOf): none for an archived chat, or
/// a station from before that says nothing; who it is for each a lowercase email, distinct, at most MAX_WAITS.
function attentionFields(chat: Json): Json {
  const a = chat.attention;
  if (chat.archived === true || typeof a?.kind !== "string" || !ATTENTION.includes(a.kind)) return {};
  const waits = new Set<string>();
  for (const w of Array.isArray(a.waitsFor) ? a.waitsFor : []) {
    const email = typeof w === "string" ? w.trim().toLowerCase() : "";
    if (/^[^\s@]+@[^\s@]+$/.test(email) && email.length <= MAX_TEXT && waits.size < MAX_WAITS) waits.add(email);
  }
  const note = cut(typeof a.note === "string" ? a.note.trim() : null, MAX_NOTE);
  return { attention: a.kind, ...(waits.size > 0 ? { waits_for: [...waits] } : {}), ...(note === null ? {} : { note }) };
}

/// A chat's link in the app, as Comma takes one: https, at most MAX_URL.
const urlOf = (url: unknown): Json => (typeof url === "string" && url.startsWith("https://") && url.length <= MAX_URL ? { url } : {});

/// One station's Task index rows, by their chat's ref: what Comma lists of a Task, never its messages.
export function taskRowsOf(given: StationRows): Map<string, { kind: string; json: string }> {
  const rows = new Map<string, { kind: string; json: string }>();
  for (const c of given.chats) {
    if (typeof c?.thread !== "number") continue;
    const ref = chatRef(c.thread, given.station);
    const agent = Array.isArray(c.agents) ? c.agents[0] : undefined;
    const row = {
      task: ref, title: cut(c.title, MAX_TITLE) ?? "", status: statusOf(c), surface: c.surface ?? "unknown",
      created_by: cut(c.creator === null || c.creator === undefined ? null : who(c.creator, c.creator.ref ?? null), MAX_TEXT),
      created_at: c.createdAt ?? 0, last_activity_at: c.lastActiveAt ?? c.createdAt ?? 0,
      runtime: cut(agent?.runtime, 40), model: cut(agent?.model, 120), ...(given.station === undefined ? {} : { station: given.station }),
      ...attentionFields(c), ...urlOf(c.url), ...(c.router === true ? { router: true } : {}),
    };
    rows.set(ref, { kind: "task", json: JSON.stringify(row) });
  }
  return rows;
}

/// An index Comma keeps a copy of: rows numbered by `rev` within an `epoch`, a row gone leaving a tombstone until
/// every connection's Comma holds it.
export class RevIndex {
  readonly #db: DatabaseSync;
  readonly #name: string;
  readonly #listeners = new Set<() => void>();
  /// What each connection's Comma holds: tombstones go once every one holds them.
  readonly #held = new Map<string | symbol, number>();
  #guarded = false;
  readonly ready: Promise<void>;

  constructor(db: DatabaseSync, name: string, ready: Promise<void> = Promise.resolve()) {
    this.#db = db;
    this.#name = name;
    this.ready = ready;
    db.exec(`
      CREATE TABLE IF NOT EXISTS ${name} (key TEXT PRIMARY KEY, source TEXT NOT NULL, kind TEXT NOT NULL, rev INTEGER NOT NULL,
        json TEXT NOT NULL, removed INTEGER NOT NULL DEFAULT 0);
      CREATE INDEX IF NOT EXISTS ${name}_rev ON ${name} (rev);`);
  }

  /// Install after the old process exits: taking a schema write lock during startup could prevent handover itself.
  /// Once installed, the persistent trigger also records tombstones pruned by an older binary after a downgrade.
  #guardPrunes(): void {
    if (this.#guarded) return;
    const name = this.#name;
    this.#db.exec(`CREATE TRIGGER IF NOT EXISTS ${name}_pruned AFTER DELETE ON ${name}
      WHEN OLD.removed = 1 AND OLD.rev > COALESCE((SELECT CAST(value AS INTEGER) FROM meta WHERE key = '${name}.pruned'), 0)
      BEGIN
        INSERT INTO meta (key, value) VALUES ('${name}.pruned', CAST(OLD.rev AS TEXT))
          ON CONFLICT (key) DO UPDATE SET value = excluded.value;
      END;`);
    this.#guarded = true;
  }

  epoch(): string {
    let epoch = this.#meta("epoch");
    if (epoch === null) {
      epoch = randomBytes(16).toString("hex");
      this.#setMeta("epoch", epoch);
    }
    // Earlier senders truncated the NUL-delimited stats keys. A new wire epoch makes Comma rebuild its copy, while
    // an older process still handing over continues to see its own epoch in the shared database.
    // Earlier versions did not keep the prune floor. Reset their copies once, including any already missing a delete.
    return this.#name === "stats_index" ? `${epoch}.keys1.gc1` : `${epoch}.gc1`;
  }

  rev(): number {
    return Number(this.#meta("rev") ?? 0);
  }

  since(since: number, limit: number, omitRemovedBodies = false): IndexRow[] {
    // The built-in wire encoders never use a removed row's old body. Other readers still receive it.
    const body = omitRemovedBodies ? "CASE WHEN removed IS NOT 0 THEN '' ELSE json END AS json" : "json";
    return (this.#db.prepare(`SELECT CAST(key AS BLOB) AS key, source, kind, rev, removed, ${body} FROM ${this.#name} WHERE rev > ? ORDER BY rev LIMIT ?`).all(since, limit) as Json[]).map((r) => ({
      key: Buffer.from(r.key).toString("utf8"), source: r.source, kind: r.kind, rev: r.rev, removed: r.removed !== 0, json: r.json,
    }));
  }

  /// What connection `host`'s Comma holds now; tombstones every one holds go.
  held(host: string | symbol, through: number): void {
    this.#guardPrunes();
    this.#held.set(host, through);
    const throughAll = Math.min(...this.#held.values());
    // The trigger records the highest tombstone actually removed in the same statement's transaction, including
    // deletes from older processes. Avoid a separate search of all acknowledged rows when there is nothing to delete.
    this.#db.prepare(`DELETE FROM ${this.#name} WHERE removed = 1 AND rev <= ?`).run(throughAll);
  }

  /// A socket is a distinct reader even when it is replacing a previous socket of the same connect.
  following(): symbol { this.#guardPrunes(); const token = Symbol(); this.#held.set(token, 0); return token; }
  observed(token: symbol, through: number): void { if (this.#held.has(token)) this.#held.set(token, through); }

  /// Greatest revision of a tombstone already pruned; it survives disconnected senders and process restarts.
  pruned(): number { return Number(this.#meta("pruned") ?? 0); }

  /// Capture the floor, revision and page rows in one snapshot; callers encode only after the snapshot is released.
  snapshot<T>(read: () => T): T {
    this.#db.exec("SAVEPOINT comma_index_page");
    try { return read(); } finally { this.#db.exec("RELEASE comma_index_page"); }
  }

  /// A connection gone: what it held no longer keeps tombstones.
  gone(host: string | symbol): void {
    this.#held.delete(host);
  }

  listen(changed: () => void): () => void {
    this.#listeners.add(changed);
    return () => void this.#listeners.delete(changed);
  }

  /// The rows `given`, written where they changed; a row not given is tombstoned where `drop` says. Inside the
  /// caller's transaction; how many rows changed.
  write(given: Map<string, { kind: string; json: string }>, drop: (row: Json) => boolean,
    candidates?: () => { key: Uint8Array; json: string }[]): number {
    let rev = this.rev();
    let changed = 0;
    const get = this.#db.prepare(`SELECT json, removed FROM ${this.#name} WHERE key = ?`);
    const put = this.#db.prepare(
      `INSERT INTO ${this.#name} (key, source, kind, rev, json, removed) VALUES (?, ?, ?, ?, ?, 0) ON CONFLICT (key) DO UPDATE SET rev = excluded.rev, json = excluded.json, removed = 0`,
    );
    for (const [key, row] of given) {
      const had = get.get(key) as { json: string; removed: number } | undefined;
      if (had !== undefined && had.removed === 0 && had.json === row.json) continue;
      put.run(key, SOURCE, row.kind, ++rev, row.json);
      changed++;
    }
    // Node's SQLite text reader stops at NUL. Compare and update using the actual stored UTF-8 bytes instead.
    const keys = new Set([...given.keys()].map((key) => Buffer.from(key).toString("hex")));
    const kept = candidates?.() ?? this.#db.prepare(`SELECT CAST(key AS BLOB) AS key, json FROM ${this.#name} WHERE removed = 0`).all() as { key: Uint8Array; json: string }[];
    const tombstone = this.#db.prepare(`UPDATE ${this.#name} SET removed = 1, rev = ? WHERE key = CAST(? AS TEXT)`);
    for (const k of kept) {
      if (keys.has(Buffer.from(k.key).toString("hex")) || !drop(JSON.parse(k.json))) continue;
      tombstone.run(++rev, k.key);
      changed++;
    }
    if (changed > 0) this.#setMeta("rev", String(rev));
    return changed;
  }

  /// Tells those listening, after the transaction that changed it.
  changed(): void {
    for (const l of this.#listeners) l();
  }

  #meta(key: string): string | null {
    return (this.#db.prepare("SELECT value FROM meta WHERE key = ?").get(`${this.#name}.${key}`) as { value: string } | undefined)?.value ?? null;
  }

  #setMeta(key: string, value: string): void {
    this.#db.prepare("INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT (key) DO UPDATE SET value = excluded.value").run(`${this.#name}.${key}`, value);
  }
}

export class CommaStats {
  readonly #db: DatabaseSync;
  /// The Stats index and the Task index.
  readonly stats: RevIndex;
  readonly tasks: RevIndex;
  #building: Promise<void> | null = null;
  #again = false;
  #stops: (() => void)[] | null = null;
  #closed = false;
  #stopRetry: (() => void) | null = null;
  readonly #read: Read;
  readonly #changes: (changed: () => void) => () => void;

  /// `changes`: tells when the agents spent or a chat moved, until the function it answers is called.
  constructor(path: string, read: Read, changes: (changed: () => void) => () => void, ready: Promise<void> = Promise.resolve()) {
    this.#read = read;
    this.#changes = changes;
    // Shared with the process serving as a new one starts beside it (a handover): another's write waited for, as the
    // store's is, not refused at once ("database is locked" stopped a station's next process as it made this).
    this.#db = new DatabaseSync(path, { timeout: 5000 });
    this.#db.exec("CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)");
    this.stats = new RevIndex(this.#db, "stats_index", ready);
    this.tasks = new RevIndex(this.#db, "task_index", ready);
    this.#db.exec("CREATE TABLE IF NOT EXISTS said (key TEXT PRIMARY KEY, n INTEGER NOT NULL, at INTEGER NOT NULL)");
  }

  /// The message the Router's write `key` made here, if it made one: asked again, it is the same one.
  said(key: string): number | null {
    return (this.#db.prepare("SELECT n FROM said WHERE key = ?").get(key) as { n: number } | undefined)?.n ?? null;
  }

  /// A Task's current title, if it is in the index. A removed Task has no title for the Router.
  taskTitle(ref: string): Json {
    const row = this.#db.prepare("SELECT CAST(key AS BLOB) AS key, json FROM task_index WHERE key = ? AND rev > 0 AND removed = 0").get(ref) as { key: Uint8Array; json: string } | undefined;
    // The binding of an unpaired surrogate becomes U+FFFD; the ordered reader compared the decoded key to ref.
    return row === undefined || Buffer.from(row.key).toString("utf8") !== ref ? "" : JSON.parse(row.json).title;
  }

  /// Remembers what `key` made, for BUILD_DAYS (a write asked again later than that is not one Comma retries).
  remember(key: string, n: number): void {
    const now = wall.now();
    this.#db.prepare("INSERT INTO said (key, n, at) VALUES (?, ?, ?) ON CONFLICT (key) DO NOTHING").run(key, n, now);
    this.#db.prepare("DELETE FROM said WHERE at < ?").run(now - BUILD_DAYS * DAY_MS);
  }

  static at(data: string, read: Read, changes: (changed: () => void) => () => void, ready?: Promise<void>): CommaStats {
    mkdirSync(data, { recursive: true });
    return new CommaStats(join(data, "comma-stats.db"), read, changes, ready);
  }

  /// A workspace's index is never taken from the old, unscoped index: its owner is not known after a home change.
  static inWorkspace(data: string, workspace: string, read: Read, changes: (changed: () => void) => () => void): CommaStats {
    const dir = join(data, "comma-indexes");
    mkdirSync(dir, { recursive: true, mode: 0o700 });
    // Preserve JavaScript's whole string, including lone surrogates, rather than folding them to U+FFFD in UTF-8.
    const name = createHash("sha256").update(workspace, "utf16le").digest("hex");
    return new CommaStats(join(dir, `${name}.db`), read, changes);
  }

  /// Once Comma is connected first: builds now, a minute after a change, and every hour, until close.
  start(): void {
    if (this.#closed || this.#stops !== null) return;
    let settle: (() => void) | null = null;
    const stopChanges = this.#changes(() => {
      if (settle !== null) return;
      settle = wall.after(SETTLE_MS, () => {
        settle = null;
        this.build();
      });
    });
    const tick = () => {
      this.build();
      hourly = wall.after(EVERY_MS, tick);
    };
    let hourly = wall.after(EVERY_MS, tick);
    this.#stops = [stopChanges, () => settle?.(), () => hourly()];
    this.build();
  }

  close(): void {
    if (this.#closed) return;
    this.#closed = true;
    this.#stopRetry?.();
    for (const stop of this.#stops ?? []) stop();
    this.#stops = null;
    this.#db.close();
  }

  /// A build, after the one under way when there is one.
  build(): void {
    if (this.#closed) return;
    if (this.#building !== null) {
      this.#again = true;
      return;
    }
    const now = wall.now();
    this.#building = this.#read(now - BUILD_DAYS * DAY_MS, now)
      .then(({ stations, unread, valid }) => this.#applyBuild(stations, unread, now - BUILD_DAYS * DAY_MS, valid))
      .catch((e) => log.info("comma", "the statistics were not read this time", { error: (e as Error).message }))
      .finally(() => {
        this.#building = null;
        if (this.#again && !this.#closed) {
          this.#again = false;
          this.build();
        }
      });
  }

  /// Settles once the build under way (tests).
  async settled(): Promise<void> {
    while (this.#building !== null) await this.#building;
  }

  // Prepare only as a build needs it. Each batch commits and yields so a first build on an old database does not
  // parse its whole history in one turn; another station's older writer is followed by the index's triggers.
  async #applyBuild(stations: StationRows[], unread: string[], from: number, valid: () => boolean = () => true): Promise<void> {
    let installed = false;
    let retryMs = 25;
    let version: number | null = null;
    let activeTurns = 0;
    while (!this.#closed && valid()) {
      try {
        if (!installed) { installStatsAge(this.#db); installed = true; }
        const ready = statsAgeReady(this.#db, 0) || statsAgeStep(this.#db).done;
        // Apply as soon as a batch has caught up. Yielding here would let a steady older writer dirty one row on
        // every turn and keep the build waiting even though each batch had finished all of its work.
        let dirtyLimit: number | null = 0;
        if (!ready && statsAgeReady(this.#db, null)) {
          const current = (this.#db.prepare("PRAGMA data_version").get() as { data_version: number }).data_version;
          activeTurns = version !== null && current !== version ? activeTurns + 1 : 0;
          version = current;
          // Unchanged old rows still use the index; a sustained writer's remaining dirty rows are read as before.
          if (activeTurns >= ACTIVE_REPAIR_TURNS) dirtyLimit = null;
        } else if (!ready) { version = null; activeTurns = 0; }
        // A read can become obsolete while the age index is prepared over several turns.
        if (!valid()) return;
        if ((ready || dirtyLimit === null) && this.#apply(stations, unread, from, true, dirtyLimit) !== null) return;
        retryMs = 25;
        await new Promise<void>((resolve) => setImmediate(resolve));
      } catch (error) {
        const code = (error as { errcode?: number }).errcode;
        if (code === undefined || ((code & 0xff) !== 5 && (code & 0xff) !== 6)) throw error;
        // A previous station can still have the database locked during handover. Retrying the finite work after a
        // backoff keeps that lock from making this build silently disappear.
        await new Promise<void>((resolve) => {
          const finish = () => { this.#stopRetry = null; resolve(); };
          const stop = wall.after(retryMs, finish);
          this.#stopRetry = () => { stop(); finish(); };
        });
        retryMs = Math.min(retryMs * 2, 2_000);
      }
    }
  }

  /// The stations' rows from the day of `from` on, written where they changed. A usage row of those days no longer
  /// given is tombstoned, and so is a chat no longer among them, but not one of a station not read this time. How many
  /// rows of each index changed.
  apply(stations: StationRows[], unread: string[], from: number): { stats: number; tasks: number } {
    return this.#apply(stations, unread, from, false)!;
  }

  #apply(stations: StationRows[], unread: string[], from: number, indexed: boolean, dirtyLimit: number | null = 0): { stats: number; tasks: number } | null {
    const fromDay = new Date(Math.floor(from / DAY_MS) * DAY_MS).toISOString().slice(0, 10);
    const stats = new Map<string, { kind: string; json: string }>();
    const tasks = new Map<string, { kind: string; json: string }>();
    for (const s of stations) {
      for (const [key, row] of statsRowsOf(s, fromDay)) stats.set(key, row);
      for (const [key, row] of taskRowsOf(s)) tasks.set(key, row);
    }
    const skipped = new Set(unread);
    const read = (row: Json) => !skipped.has(row.station ?? "");
    let changed = { stats: 0, tasks: 0 };
    // (the write taken first: begun deferred, its read then write was refused at once while the process beside it wrote)
    this.#db.exec("BEGIN IMMEDIATE");
    try {
      // Recheck in this transaction's snapshot. If preparation is no longer usable, classify again without writing a
      // partial build; any dirty rows allowed here are included and checked by the original predicate.
      if (indexed && !statsAgeReady(this.#db, dirtyLimit)) {
        this.#db.exec("ROLLBACK");
        return null;
      }
      changed = {
        stats: this.stats.write(stats, (row) => row.day !== undefined && row.day >= fromDay && read(row),
          indexed ? () => statsAgeCandidates(this.#db, fromDay) : undefined),
        tasks: this.tasks.write(tasks, read),
      };
      this.#db.exec("COMMIT");
    } catch (e) {
      this.#db.exec("ROLLBACK");
      throw e;
    }
    if (changed.stats > 0) this.stats.changed();
    if (changed.tasks > 0) this.tasks.changed();
    return changed;
  }
}

// ── the pages a connection sends ───────────────────────────────────────────────────────────────────────────────────

/// What Comma holds of an index.
export type Held = { epoch: string | null; through: number };

/// A `stats.index` or `task.index` page.
export type Page = { epoch: string; reset: boolean; since: number; through: number; rows: Json[] };

/// Comma's bounds on a page: rows, and bytes of its rows as JSON.
export const PAGE_ROWS = 200;
export const PAGE_BYTES = 60 * 1024;

/// The page that only asks what Comma holds: applying it changes nothing.
export function probePage(index: RevIndex): Page {
  const rev = index.rev();
  return { epoch: index.epoch(), reset: false, since: rev, through: rev, rows: [] };
}

/// A Stats index row as `stats.index` carries it.
export function statsWire(row: IndexRow): Json | null {
  // Keys are opaque to Comma; PostgreSQL text cannot contain NUL and its key is limited to 512 bytes.
  const key = `sf1:${createHash("sha256").update(row.key).digest("hex")}`;
  if (row.removed) return { key, source: row.source, kind: row.kind, rev: row.rev, removed: true };
  try {
    return { key, source: row.source, kind: row.kind, rev: row.rev, row: JSON.parse(row.json) };
  } catch {
    return null;
  }
}

/// A Task index row as `task.index` carries it: the Task's facts, never its messages; what it asks of whom only when it
/// asks something, its agent's one sentence of it, its link when there is one, and `router` only when a Comma Router
/// wrote in it (a station from before says nothing: absent is not known to be false).
export function taskWire(row: IndexRow): Json | null {
  if (row.removed) return { thread: row.key, rev: row.rev, removed: true };
  try {
    const t = JSON.parse(row.json);
    return {
      thread: row.key, rev: row.rev, task: t.task, title: t.title, status: t.status, created_by: t.created_by, created_at: t.created_at,
      last_activity_at: t.last_activity_at, runtime: t.runtime, model: t.model, labels: [],
      ...(typeof t.attention === "string" ? { attention: t.attention } : {}),
      ...(typeof t.attention === "string" && Array.isArray(t.waits_for) && t.waits_for.length > 0 ? { waits_for: t.waits_for } : {}),
      ...(typeof t.attention === "string" && typeof t.note === "string" ? { note: t.note } : {}),
      ...(typeof t.url === "string" ? { url: t.url } : {}),
      ...(t.router === true ? { router: true } : {}),
    };
  } catch {
    return null;
  }
}

/// The next page to send after Comma answered `held`; null once it holds all of the index.
export function nextPage(index: RevIndex, held: Held, wire: (row: IndexRow) => Json | null = statsWire,
  resetIf?: (floor: number, rev: number, epoch: string) => boolean): Page | null {
  return readNextPage(index, held, wire, resetIf, PAGE_ROWS).page;
}

/// One snapshot per page, with an optional lower row limit for a sender that has recently seen large wire rows.
function readNextPage(index: RevIndex, held: Held, wire: (row: IndexRow) => Json | null,
  resetIf: ((floor: number, rev: number, epoch: string) => boolean) | undefined, requestedRows: number):
  { page: Page | null; limit: number; taken: number; byteLimited: boolean; rowLimited: boolean } {
  // A different connection can prune between reads. The floor, revision and rows must describe the same database
  // snapshot; release it before parsing and encoding the bodies, so those operations do not hold a SQLite read lock.
  const slice = index.snapshot(() => {
    const epoch = index.epoch();
    const rev = index.rev();
    // A restored or damaged database may have a floor ahead of its current revision; never restart a reset forever.
    const floor = Math.min(index.pruned(), rev);
    const forced = resetIf?.(floor, rev, epoch) === true;
    const reset = held.epoch !== epoch || forced;
    const since = reset ? 0 : held.through;
    let limit = reset ? PAGE_ROWS : requestedRows;
    const omitRemoved = wire === statsWire || wire === taskWire;
    let changed = !reset && since >= rev ? null : index.since(since, limit + 1, omitRemoved);
    // Do not introduce an earlier boundary within equal revisions: the receiver acknowledges only a revision.
    // Fall back in this same snapshot to the original page size when the adaptive boundary would split one.
    if (changed !== null && limit < PAGE_ROWS && changed.length > limit && changed[limit - 1].rev === changed[limit].rev) {
      limit = PAGE_ROWS;
      changed = index.since(since, limit + 1, omitRemoved);
    }
    return { epoch, rev, reset, since, limit, changed };
  });
  const { epoch, rev, reset, since, limit, changed } = slice;
  if (changed === null) return { page: null, limit, taken: 0, byteLimited: false, rowLimited: false };
  const rows: Json[] = [];
  let bytes = 2;
  let taken = 0;
  let last = since;
  let byteLimited = false;
  for (const row of changed.slice(0, limit)) {
    const sent = wire(row);
    const size = sent === null ? 0 : Buffer.byteLength(JSON.stringify(sent)) + 1;
    if (rows.length > 0 && bytes + size > PAGE_BYTES) { byteLimited = true; break; }
    if (sent !== null) rows.push(sent);
    bytes += size;
    taken += 1;
    last = row.rev;
  }
  // A page short of the end brings Comma to its last row; the last page to the index's rev, past pruned tombstones.
  const through = taken < changed.length ? last : rev;
  return { page: { epoch, reset, since, through, rows }, limit, taken, byteLimited,
    rowLimited: !byteLimited && taken === limit && changed.length > limit };
}

/// One socket following an index. A reset clears the receiver only on its first page; while it is paging, the socket
/// holds its acknowledged position so another sender cannot prune a tombstone it still needs.
export class IndexSync {
  readonly #index: RevIndex;
  readonly #wire: (row: IndexRow) => Json | null;
  readonly #token: symbol;
  #resetting = false;
  #resetFloor = 0;
  #pageRows = PAGE_ROWS;

  constructor(index: RevIndex, wire: (row: IndexRow) => Json | null = statsWire) {
    this.#index = index;
    this.#wire = wire;
    this.#token = index.following();
  }

  next(held: Held): Page | null {
    const index = this.#index;
    index.observed(this.#token, held.epoch === index.epoch() ? held.through : 0);
    let floor = 0;
    const resetIf = (seen: number, rev: number, epoch: string) => {
      floor = seen;
      return held.epoch === epoch && (held.through > rev ||
        (held.through < seen && (!this.#resetting || seen > this.#resetFloor)));
    };
    let result = readNextPage(index, held, this.#wire, resetIf, this.#pageRows);
    if ((this.#wire === statsWire || this.#wire === taskWire) && result.limit < PAGE_ROWS && result.rowLimited) {
      // Small rows have arrived. Discard the tentative page and read a complete page in a new snapshot, so the
      // receiver does not pay an extra page wait and no rows from different snapshots are combined.
      result = readNextPage(index, held, this.#wire, resetIf, PAGE_ROWS);
    }
    const page = result.page;
    if (this.#wire === statsWire || this.#wire === taskWire) {
      // Learn from wire size, not stored JSON size: a large Task body can make a small wire row.
      if (result.byteLimited) this.#pageRows = Math.min(PAGE_ROWS, Math.max(8, 2 * (result.taken + 1)));
      else this.#pageRows = PAGE_ROWS;
    }
    if (page?.reset === true) {
      this.#resetting = true;
      this.#resetFloor = floor;
      index.observed(this.#token, 0);
    } else if (page === null) {
      this.#resetting = false;
      index.held(this.#token, held.through);
    }
    return page;
  }

  close(): void { this.#index.gone(this.#token); }
}

/// Comma's answer to a page, or null when it is not one.
export function heldFrom(result: unknown): Held | null {
  if (typeof result !== "object" || result === null) return null;
  const { epoch, through } = result as Record<string, unknown>;
  if (epoch !== null && epoch !== undefined && typeof epoch !== "string") return null;
  return { epoch: (epoch as string | null | undefined) ?? null, through: typeof through === "number" && through >= 0 ? through : 0 };
}
