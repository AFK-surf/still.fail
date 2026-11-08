// What Comma keeps of the workspace through a Comma connect, as a Comma station sends of its own (Cue's
// systems/station/src/stats and connector/task-index.ts), of this station and of the other stations of its workspace
// (read of them as `outflow.read`, peer.ts):
// - the Stats index (`stats.index`), source `stillfail`: what the agents spent, by day, chat, person, account and
//   model, and the chats they worked in;
// - the Task index (`task.index`): the chats as Comma lists the Tasks its stations host, which the Router reads and
//   writes in through the connect (`task.read`, `task.say`, surface.ts).
// Both cover the last BUILD_DAYS, are kept in <data>/comma-stats.db numbered as their rows change, and each
// connection sends Comma what it does not hold yet, a page at a time.
//
// Built as Comma first connects, a minute after the agents' spending was recorded, as a chat moves (a minute after
// too), and every hour (another station's changes reach it so); one build at a time.
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
export type Read = (from: number, to: number) => Promise<{ stations: StationRows[]; unread: string[] }>;

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
  readonly #held = new Map<string, number>();

  constructor(db: DatabaseSync, name: string) {
    this.#db = db;
    this.#name = name;
    db.exec(`
      CREATE TABLE IF NOT EXISTS ${name} (key TEXT PRIMARY KEY, source TEXT NOT NULL, kind TEXT NOT NULL, rev INTEGER NOT NULL,
        json TEXT NOT NULL, removed INTEGER NOT NULL DEFAULT 0);
      CREATE INDEX IF NOT EXISTS ${name}_rev ON ${name} (rev);`);
  }

  epoch(): string {
    let epoch = this.#meta("epoch");
    if (epoch === null) {
      epoch = randomBytes(16).toString("hex");
      this.#setMeta("epoch", epoch);
    }
    // Earlier senders truncated the NUL-delimited stats keys. A new wire epoch makes Comma rebuild its copy, while
    // an older process still handing over continues to see its own epoch in the shared database.
    return this.#name === "stats_index" ? `${epoch}.keys1` : epoch;
  }

  rev(): number {
    return Number(this.#meta("rev") ?? 0);
  }

  since(since: number, limit: number): IndexRow[] {
    return (this.#db.prepare(`SELECT CAST(key AS BLOB) AS key, source, kind, rev, removed, json FROM ${this.#name} WHERE rev > ? ORDER BY rev LIMIT ?`).all(since, limit) as Json[]).map((r) => ({
      key: Buffer.from(r.key).toString("utf8"), source: r.source, kind: r.kind, rev: r.rev, removed: r.removed !== 0, json: r.json,
    }));
  }

  /// What connection `host`'s Comma holds now; tombstones every one holds go.
  held(host: string, through: number): void {
    this.#held.set(host, through);
    this.#db.prepare(`DELETE FROM ${this.#name} WHERE removed = 1 AND rev <= ?`).run(Math.min(...this.#held.values()));
  }

  /// A connection gone: what it held no longer keeps tombstones.
  gone(host: string): void {
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
  constructor(path: string, read: Read, changes: (changed: () => void) => () => void) {
    this.#read = read;
    this.#changes = changes;
    this.#db = new DatabaseSync(path);
    this.#db.exec("CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)");
    this.stats = new RevIndex(this.#db, "stats_index");
    this.tasks = new RevIndex(this.#db, "task_index");
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

  static at(data: string, read: Read, changes: (changed: () => void) => () => void): CommaStats {
    mkdirSync(data, { recursive: true });
    return new CommaStats(join(data, "comma-stats.db"), read, changes);
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
      .then(({ stations, unread }) => this.#applyBuild(stations, unread, now - BUILD_DAYS * DAY_MS))
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
  async #applyBuild(stations: StationRows[], unread: string[], from: number): Promise<void> {
    let installed = false;
    let retryMs = 25;
    while (!this.#closed) {
      try {
        if (!installed) { installStatsAge(this.#db); installed = true; }
        if (!statsAgeReady(this.#db, 0)) statsAgeStep(this.#db);
        else if (this.#apply(stations, unread, from, true) !== null) return;
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

  #apply(stations: StationRows[], unread: string[], from: number, indexed: boolean): { stats: number; tasks: number } | null {
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
    this.#db.exec("BEGIN");
    try {
      // The other writer may have changed rows after preparation. Check this transaction's snapshot before using
      // the index; classify any changed rows in another batch without writing a partial build.
      if (indexed && !statsAgeReady(this.#db, 0)) {
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

/// A Task index row as `task.index` carries it: the Task's facts, never its text.
export function taskWire(row: IndexRow): Json | null {
  if (row.removed) return { thread: row.key, rev: row.rev, removed: true };
  try {
    const t = JSON.parse(row.json);
    return {
      thread: row.key, rev: row.rev, task: t.task, title: t.title, status: t.status, created_by: t.created_by, created_at: t.created_at,
      last_activity_at: t.last_activity_at, runtime: t.runtime, model: t.model, labels: [],
    };
  } catch {
    return null;
  }
}

/// The next page to send after Comma answered `held`; null once it holds all of the index.
export function nextPage(index: RevIndex, held: Held, wire: (row: IndexRow) => Json | null = statsWire): Page | null {
  const epoch = index.epoch();
  const rev = index.rev();
  const reset = held.epoch !== epoch;
  const since = reset ? 0 : held.through;
  if (!reset && since >= rev) return null;
  const changed = index.since(since, PAGE_ROWS + 1);
  const rows: Json[] = [];
  let bytes = 2;
  let taken = 0;
  let last = since;
  for (const row of changed.slice(0, PAGE_ROWS)) {
    const sent = wire(row);
    const size = sent === null ? 0 : Buffer.byteLength(JSON.stringify(sent)) + 1;
    if (rows.length > 0 && bytes + size > PAGE_BYTES) break;
    if (sent !== null) rows.push(sent);
    bytes += size;
    taken += 1;
    last = row.rev;
  }
  // A page short of the end brings Comma to its last row; the last page to the index's rev, past pruned tombstones.
  const through = taken < changed.length ? last : rev;
  return { epoch, reset, since, through, rows };
}

/// Comma's answer to a page, or null when it is not one.
export function heldFrom(result: unknown): Held | null {
  if (typeof result !== "object" || result === null) return null;
  const { epoch, through } = result as Record<string, unknown>;
  if (epoch !== null && epoch !== undefined && typeof epoch !== "string") return null;
  return { epoch: (epoch as string | null | undefined) ?? null, through: typeof through === "number" && through >= 0 ? through : 0 };
}
