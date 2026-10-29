// The core's data (docs/core-db.md): one SQLite database per signed-in account (db/account.ts, its tables in
// db/schema.ts), and the few values that are the device's (preferences, the changelog seen) in the host's storage.
// What is a station's or a workspace's is kept in the database of the account that reaches it (Workspaces' owner);
// what an account did is in its own. Signing out removes the account's database.
//
// Topics of this data have no value of their own: their value is read from here (`shared`), by query, when it goes
// out; each database's writer says which topics a burst changed, and the store pushes what changed (keyed deltas).
import { Effect, Fiber, Queue } from "effect";
import { AccountDb, LIST_OF, type Changes, type Derive, type ListKind, type RowChange, frozen } from "./db/account.ts";
import type { Host, Sql, SqlRow, SqlValue } from "./host.ts";
import { HostError, SqlError, sqlError } from "./host.ts";
import type { MdStore } from "./markdown.ts";
import type { Topic } from "./protocol.ts";
import type { Runner } from "./runtime.ts";
import { equal, get, isObject, parseJson, toJsonBytes } from "./util.ts";
import { ofAddress } from "./workspace.ts";

export { frozen };
export type { ListKind, RowChange };

/// Between the parts of a key: sorts before every character a part can hold.
export const SEP = "\u0001";

export function join(parts: (string | number)[]): string {
  return parts.join(SEP);
}

/// A number in a key, so keys sort as numbers do.
export function num(n: number): string {
  return String(n).padStart(12, "0");
}

/// How long a value changing as it is typed (a draft) waits before it is written.
export const SOON_MS = 300;

/// The topics whose values are held here.
const HELD = new Set(["workspace", "overview", "session", "chatRows", "sessions", "threads", "archivedRows", "jobs", "job", "slackApp", "stationUsage", "footprint", "loginSessions", "admin", "draft", "prefs", "drive", "drivePlace"]);

/// What a folder of a station's drive is kept as among the station's documents (the `drive` topic).
export const driveDoc = (root: string, path: string) => `drive\n${root}\n${path}`;
/// What a station said beyond the tables (station/memory.ts) is kept among its documents as `memory\n<key>`.
const MEMORY = "memory\n";
/// Where a file of a drive was left (the `drivePlace` topic), as the device keeps it.
const placeOf = (topic: Topic) => `${String(topic.station)}\n${String(topic.root)}\n${String(topic.path)}`;
/// The most places of files kept: the oldest go.
const PLACES_KEPT = 500;

/// Whether a topic's value is held here.
export function holds(topic: Topic): boolean {
  return HELD.has(topic.topic);
}

/// Where a station's overview has a sign-in for a new profile (`logins`): its job's state ("" with none); null, not
/// listed.
function loginAt(overview: unknown, id: string): string | null {
  const logins = get(overview, "logins");
  const login = Array.isArray(logins) ? logins.find((l) => isObject(l) && l.id === id) : undefined;
  if (!isObject(login)) return null;
  const state = get(login.job, "state");
  return typeof state === "string" ? state : "";
}

/// The workspace a station's address is in.
function workspaceOf(station: string): string {
  const at = station.indexOf("/");
  return at >= 0 ? station.slice(0, at) : station;
}

/// An account's database's name: its subject, with what a file name cannot hold as `_xx`.
export function dbName(sub: string): string {
  return `account-${[...new TextEncoder().encode(sub)].map((b) => (/[A-Za-z0-9-]/.test(String.fromCharCode(b)) ? String.fromCharCode(b) : `_${b.toString(16).padStart(2, "0")}`)).join("")}`;
}

/// The device's own values (not an account's): kept in the host's storage, one storage value per table, read at start.
export const DEVICE_TABLES = ["prefs", "changelog", "choice", "chat_ref", "drive_place"] as const;
export type DeviceTable = (typeof DEVICE_TABLES)[number];

class Device {
  readonly #host: Host;
  readonly #tables = new Map<string, Record<string, unknown>>();
  readonly #dirty = new Set<string>();
  readonly #writes: Queue.Queue<string>;
  readonly #writer: Fiber.Fiber<never, never>;

  constructor(host: Host, runner: Runner) {
    this.#host = host;
    this.#writes = Effect.runSync(Queue.unbounded<string>());
    // One writer: a table's latest value, in the order they changed. A write once begun is finished, though the core
    // closes: `close` writes what is left after it. One that fails leaves its table to be written again (by the next
    // change, or `close`, which says it failed).
    this.#writer = runner.fork(
      Effect.forever(
        Effect.flatMap(Queue.take(this.#writes), (table) =>
          Effect.uninterruptible(Effect.suspend(() => (this.#dirty.has(table) ? Effect.ignore(this.#write(table), { log: "Unhandled", message: "table written" }) : Effect.void))),
        ),
      ),
    );
  }

  /// A table's latest value written; still to be written if it fails.
  #write(table: string): Effect.Effect<void, HostError> {
    this.#dirty.delete(table);
    return Effect.tapError(this.#host.storageSet(`device/${table}`, toJsonBytes(this.#tables.get(table) ?? {})), () => Effect.sync(() => void this.#dirty.add(table)));
  }

  /// Stops the writer (once the write it began is done) and writes each table changed since: what a core closing does
  /// before its runner stops (Core.close). Fails with every table that could not be written.
  close(): Effect.Effect<void, HostError> {
    return Effect.gen({ self: this }, function* () {
      yield* Fiber.interrupt(this.#writer);
      const failed: string[] = [];
      for (const table of [...this.#dirty]) {
        const written = yield* Effect.result(this.#write(table));
        if (written._tag === "Failure") failed.push(`device/${table}: ${written.failure.message}`);
      }
      if (failed.length > 0) return yield* Effect.fail(new HostError(failed.join("; ")));
    });
  }

  load(host: Host): Effect.Effect<void> {
    return Effect.gen({ self: this }, function* () {
      for (const table of DEVICE_TABLES) {
        const bytes = yield* Effect.orElseSucceed(host.storageGet(`device/${table}`), () => null);
        const v = bytes ? parseJson(bytes) : undefined;
        if (!isObject(v) || this.#tables.has(table)) continue;
        // Each value frozen, as `put` keeps it: shared by whoever reads it (`shared`).
        for (const key of Object.keys(v)) frozen(v[key]);
        this.#tables.set(table, v as Record<string, unknown>);
      }
    });
  }

  get(table: string, key: string): unknown {
    return this.#tables.get(table)?.[key];
  }

  /// Puts a value (undefined: none); whether it changed.
  put(table: string, key: string, value: unknown): boolean {
    let t = this.#tables.get(table);
    if (!t) {
      t = {};
      this.#tables.set(table, t);
    }
    if (value === undefined) {
      if (!(key in t)) return false;
      delete t[key];
    } else {
      if (equal(t[key], value)) return false;
      t[key] = frozen(structuredClone(value));
    }
    this.#dirty.add(table);
    Queue.offerUnsafe(this.#writes, table);
    return true;
  }

  keys(table: string): string[] {
    return Object.keys(this.#tables.get(table) ?? {});
  }
}

export type DataOptions = {
  /// The signed-in account that reaches a workspace (Workspaces' owner): its database keeps the workspace's.
  owner: (workspace: string) => string | null;
  derive?: Derive;
  /// The most an account's database may take on the device (KEPT by default).
  kept?: number;
};

/// How much room an account's database may take on the device: past it, the agents' transcripts least recently used go,
/// down to KEPT_TO of it. A chat's messages, rows, threads, sessions, read positions and what was done here are small
/// and always kept (messages let go to make room for what could not go left 33 of 1388 chats on a Mac, each opened
/// waiting for the station); a transcript let go is read again once its history is opened. The database's file keeps
/// the room it took (its free pages are used again).
export const KEPT = 256 * 1024 * 1024;
const KEPT_TO = 0.8;
/// How often, at most, the room taken is looked at as logs are written.
const KEPT_CHECK_MS = 10_000;

/// What a database's state says through the `status` topic: a burst not written for want of room, a database a newer
/// core wrote (read only), one another process holds.
export type DbNote = { kind: "full" | "newer" | "busy" | "failed"; detail: string | null };

/// Where a database found damaged as the core ran is marked (the host's storage), to be made again as it is next
/// opened: a damaged page is found by a read, which ends the core (its next start opens it again).
const damagedKey = (name: string) => `db-damaged/${name}`;

/// What this device did itself, brought over from a damaged database to the one made again in its place (as far as it
/// can be read): the columns of each table, in schema.ts's order. The rest comes again from the stations and the cloud.
const RESCUED: [string, string[]][] = [
  ["outbox", ["station", "thread", "json"]],
  ["pending", ["key", "station", "json"]],
  ["first", ["station", "session", "json"]],
  ["changing", ["station", "id", "json"]],
  ["draft", ["station", "chat", "json"]],
  ["workspace_pref", ["workspace", "key", "json"]],
];

type Rescued = [table: string, columns: string[], rows: SqlRow[]][];

/// What of RESCUED a damaged database still gives: each table as far as it reads, none of one that does not.
function rescue(sql: Sql): Rescued {
  const out: Rescued = [];
  for (const [table, columns] of RESCUED) {
    try {
      out.push([table, columns, sql.all(`SELECT ${columns.join(", ")} FROM ${table}`)]);
    } catch {
      // Unreadable: lost with the file.
    }
  }
  return out;
}

/// An account's database as the core uses it: a damaged file (SQLITE_CORRUPT, SQLITE_NOTADB) found by any statement is
/// told (`onDamaged`), and the statement fails as it would.
class Watched implements Sql {
  readonly #inner: Sql;
  readonly #onDamaged: (error: SqlError) => void;

  constructor(inner: Sql, onDamaged: (error: SqlError) => void) {
    this.#inner = inner;
    this.#onDamaged = onDamaged;
  }

  #saw(e: unknown): never {
    const error = sqlError(e);
    if (error.kind === "corrupt") this.#onDamaged(error);
    throw e;
  }

  exec(sql: string): void {
    try {
      this.#inner.exec(sql);
    } catch (e) {
      this.#saw(e);
    }
  }

  run(sql: string, params?: readonly SqlValue[]): number {
    try {
      return this.#inner.run(sql, params);
    } catch (e) {
      return this.#saw(e);
    }
  }

  all(sql: string, params?: readonly SqlValue[]): SqlRow[] {
    try {
      return this.#inner.all(sql, params);
    } catch (e) {
      return this.#saw(e);
    }
  }

  close(): void {
    this.#inner.close();
  }
}

/// An account's database opened, or why not (`sql`: the file opened, its tables not read).
type Opened = { db: AccountDb; sql: Sql } | { db: null; sql: Sql | null; error: SqlError | HostError };

const NO_DERIVE: Derive = { tone: () => null, asks: () => false };

/// How long a session counts as used lately once its chat or history was opened (`usedLately`).
export const RECENT_MS = 3 * 86_400_000;

export class Data {
  readonly #host: Host;
  readonly #runner: Runner;
  readonly #owner: (workspace: string) => string | null;
  readonly #derive: Derive;
  readonly #dbs = new Map<string, AccountDb>();
  readonly device: Device;
  readonly #changed: ((topic: Topic) => void)[] = [];
  readonly #logChanged: ((table: string, station: string, id: string) => void)[] = [];
  readonly #chatsChanged: ((station: string, changes: RowChange[], first: boolean) => void)[] = [];
  readonly #modelEdits = new Map<string, [unknown, unknown]>();
  /// Sign-ins for new profiles as their station answered a step of them (`login.new`, `login.code`), by station and
  /// login: shown in its overview's `logins` while the overview still has the login where the step found it (`from`: the
  /// state it moved on from; null, not listed yet). A code sent showed its field again, empty, until the station's next
  /// overview came, most of a minute while the link came back (2026-10-25).
  readonly #loginSteps = new Map<string, { id: string; job: unknown; from: string | null }>();
  /// How far sessions' transcripts go as streams and reads said, past what their summaries say (`transcriptHead`).
  readonly #transcriptHeads = new Map<string, number>();
  /// Values as typed, there at once and written a moment after their last change (drafts).
  readonly #soon = new Map<string, [Topic, unknown]>();
  #flushing = false;
  /// What each database's state says, by account.
  readonly notes = new Map<string, DbNote>();
  onNote: () => void = () => {};
  /// Told of an account signed out, with its last `/v1/me`, before its database goes.
  onSignedOut: (sub: string, me: unknown) => void = () => {};
  /// Told once an account's database is opened (a sign-in), to bring in what it may (db/import.ts).
  onOpened: (db: AccountDb) => Effect.Effect<void> = () => Effect.void;
  /// The marks of databases found damaged as the core ran, as they are written (damageKept).
  readonly #damaged = new Map<string, Promise<void>>();

  /// The most a database may take (KEPT); the logs a UI shows now, with how many show each; when room was last looked at.
  readonly #kept: number;
  readonly #shown = new Map<string, number>();
  #keptAt = -Infinity;

  constructor(host: Host, runner: Runner, options: DataOptions) {
    this.#host = host;
    this.#runner = runner;
    this.#kept = options.kept ?? KEPT;
    this.#owner = options.owner;
    this.#derive = options.derive ?? NO_DERIVE;
    this.device = new Device(host, runner);
  }

  // ── the databases ──

  /// Opens the signed-in accounts' databases (and reads the device's values): what the first view is answered from.
  open(subs: string[]): Effect.Effect<void> {
    return Effect.gen({ self: this }, function* () {
      yield* this.device.load(this.#host);
      for (const sub of subs) yield* this.#open(sub);
    });
  }

  /// The accounts signed in now: a new one's database is opened; one signed out has its database removed.
  accounts(subs: string[]): Effect.Effect<void> {
    return Effect.gen({ self: this }, function* () {
      for (const [sub, db] of [...this.#dbs]) {
        if (subs.includes(sub)) continue;
        this.onSignedOut(sub, db.accountDoc("me"));
        this.#dbs.delete(sub);
        this.#setNote(sub, null);
        db.close();
        if (this.#host.deleteDb) yield* Effect.ignore(this.#host.deleteDb(db.name), { log: "Unhandled", message: "database deleted" });
        this.#tellAll();
      }
      for (const sub of subs) if (!this.#dbs.has(sub)) yield* this.#open(sub);
    });
  }

  #open(sub: string): Effect.Effect<void> {
    return Effect.gen({ self: this }, function* () {
      if (this.#dbs.has(sub)) return;
      const name = dbName(sub);
      let sql: Sql | null = null;
      let db: AccountDb | null = null;
      let note: DbNote | null = null;
      if (this.#host.openDb) {
        let opened = yield* this.#openFile(sub, name);
        // Damaged (found so now, or as an earlier core ran): made again, with what this device did itself.
        const mark = yield* Effect.orElseSucceed(this.#host.storageGet(damagedKey(name)), () => null);
        const damaged = opened.db === null ? opened.error instanceof SqlError && opened.error.kind === "corrupt" : mark !== null;
        if (damaged) opened = yield* this.#makeAgain(sub, name, opened, opened.db === null ? opened.error.message : `as it ran: ${String(get(mark ? parseJson(mark) : null, "error") ?? "")}`);
        if (opened.db !== null) db = opened.db;
        else {
          try {
            opened.sql?.close();
          } catch {
            // Let go however it can be.
          }
          const busy = opened.error instanceof SqlError && opened.error.kind === "busy";
          note = { kind: busy ? "busy" : "failed", detail: opened.error.message };
          this.#report(busy ? "LocalDbBusy" : "LocalDbFailed", opened.error.message);
        }
      }
      if (db === null) {
        // Nothing to keep it in (another process holds it, or this host keeps nothing): kept in memory this run.
        try {
          sql = this.#host.memoryDb?.() ?? null;
        } catch {
          sql = null;
        }
        if (sql === null) {
          if (note) this.#setNote(sub, note);
          return;
        }
        try {
          db = new AccountDb(sub, name, sql, this.#runner, this.#derive);
        } catch (e) {
          this.#setNote(sub, { kind: "failed", detail: e instanceof Error ? e.message : String(e) });
          return;
        }
      }
      if (db.readOnly) note = { kind: "newer", detail: null };
      db.onCommit = (changes) => this.#committed(changes);
      db.onFull = (full, error) => this.#setNote(sub, full ? { kind: "full", detail: error } : null);
      this.#dbs.set(sub, db);
      if (note) this.#setNote(sub, note);
      yield* this.onOpened(db);
      this.#keepWithin(db);
      this.#tellAll();
    });
  }

  /// An account's database file opened and read as the core uses it (Watched), or why not.
  #openFile(sub: string, name: string): Effect.Effect<Opened> {
    return Effect.gen({ self: this }, function* () {
      const opened = yield* Effect.result(this.#host.openDb!(name));
      if (opened._tag === "Failure") return { db: null, sql: null, error: opened.failure };
      const sql = opened.success;
      try {
        return { db: new AccountDb(sub, name, new Watched(sql, (error) => this.#sawDamage(name, error)), this.#runner, this.#derive), sql };
      } catch (e) {
        return { db: null, sql, error: sqlError(e) };
      }
    });
  }

  /// A damaged database made again: what this device did itself read from it as far as it can be, the file removed, a
  /// new one made with that in it. The rest comes again from the stations and the cloud, as for a new sign-in; what the
  /// device kept before the databases was brought into the damaged one already, and is not again.
  #makeAgain(sub: string, name: string, damaged: Opened, why: string): Effect.Effect<Opened> {
    return Effect.gen({ self: this }, function* () {
      const kept = damaged.sql ? rescue(damaged.sql) : [];
      try {
        if (damaged.db) damaged.db.close();
        else damaged.sql?.close();
      } catch {
        // Let go however it can be.
      }
      if (this.#host.deleteDb) {
        const gone = yield* Effect.result(this.#host.deleteDb(name));
        if (gone._tag === "Failure") return { db: null, sql: null, error: gone.failure };
      }
      const opened = yield* this.#openFile(sub, name);
      if (opened.db === null) return opened;
      const sql = opened.sql;
      let rows = 0;
      try {
        sql.exec("BEGIN IMMEDIATE");
        for (const [table, columns, found] of kept) {
          const insert = `INSERT OR REPLACE INTO ${table} (${columns.join(", ")}) VALUES (${columns.map(() => "?").join(", ")})`;
          for (const row of found) rows += sql.run(insert, row);
        }
        sql.run("INSERT OR REPLACE INTO meta (key, value) VALUES ('imported', ?)", ["made again"]);
        sql.exec("COMMIT");
      } catch {
        try {
          sql.exec("ROLLBACK");
        } catch {
          // Rolled back already.
        }
      }
      // The mark goes, after any made as the damaged one was read here.
      const marking = this.#damaged.get(name);
      if (marking) yield* Effect.promise(() => marking);
      this.#damaged.delete(name);
      yield* Effect.ignore(this.#host.storageDelete(damagedKey(name)), { log: "Unhandled", message: "damage mark removed" });
      this.#report("LocalDbMadeAgain", `${why}; ${rows} rows of this device's kept`);
      return opened;
    });
  }

  /// A damaged database found as the core ran: marked (once) to be made again as it is next opened. The core that found
  /// it waits for the mark before it ends (damageKept).
  #sawDamage(name: string, error: SqlError): void {
    if (this.#damaged.has(name)) return;
    this.#damaged.set(name, this.#runner.run(Effect.ignore(this.#host.storageSet(damagedKey(name), toJsonBytes({ error: error.message })), { log: "Unhandled", message: "damage mark kept" })));
  }

  /// Resolves once every damaged database found is marked so: what a core ending on a bug waits for (the hosts'
  /// onDefect), as the read that found the damage is what ends it.
  damageKept(): Promise<void> {
    return Promise.all(this.#damaged.values()).then(() => undefined);
  }

  /// An error the core goes on after, to the host's error tracking (`name` is what it is grouped by).
  #report(name: string, message: string): void {
    this.#host.report?.(Object.assign(new Error(message), { name }));
  }

  #setNote(sub: string, note: DbNote | null): void {
    const was = this.notes.get(sub);
    if (note === null ? was === undefined : equal(was, note)) return;
    if (note === null) this.notes.delete(sub);
    else this.notes.set(sub, note);
    this.onNote();
  }

  /// The database of an account.
  db(sub: string): AccountDb | undefined {
    return this.#dbs.get(sub);
  }

  /// The databases open now.
  dbs(): AccountDb[] {
    return [...this.#dbs.values()];
  }

  #ofWorkspace(workspace: string): AccountDb | undefined {
    const sub = this.#owner(workspace);
    return sub === null ? undefined : this.#dbs.get(sub);
  }

  /// The database that keeps a station's.
  of(station: string): AccountDb | undefined {
    return this.#ofWorkspace(workspaceOf(station));
  }

  #committed(changes: Changes): void {
    if (changes.logs.size > 0) {
      const now = this.#host.nowMs();
      if (now - this.#keptAt >= KEPT_CHECK_MS) {
        this.#keptAt = now;
        for (const db of this.#dbs.values()) this.#keepWithin(db);
      }
    }
    for (const topic of changes.topics.values()) this.#tell(topic);
    for (const [table, station, id] of changes.logs.values()) for (const l of this.#logChanged) l(table, station, id);
    for (const [station, rows] of changes.chats) {
      const list = [...rows.values()];
      for (const l of this.#chatsChanged) l(station, list, changes.firstChats.has(station));
    }
  }

  /// Hears every held topic that changes.
  onChange(listener: (topic: Topic) => void): void {
    this.#changed.push(listener);
  }

  /// Hears the entries or transcript items of a log that changed.
  onLogChange(listener: (table: string, station: string, id: string) => void): void {
    this.#logChanged.push(listener);
  }

  /// Hears a station's sidebar rows that changed in a burst, before and after (`first`: they were read for the first
  /// time).
  onChats(listener: (station: string, changes: RowChange[], first: boolean) => void): void {
    this.#chatsChanged.push(listener);
  }

  #tell(topic: Topic): void {
    for (const l of this.#changed) l(topic);
  }

  /// Every held topic may have changed (a database opened or gone): those live are read again.
  #tellAll(): void {
    this.#tell({ topic: "*" });
  }

  /// Resolves once every write asked for so far is committed.
  get written(): Effect.Effect<void> {
    return Effect.suspend(() => Effect.all([...this.#dbs.values()].map((db) => db.written), { discard: true }));
  }

  // ── held topics ──

  /// A held topic's value, kept as it is (frozen: shared, the same object while it does not change); undefined while
  /// nothing is known of it. A list is loaded the first time it is asked for.
  shared(topic: Topic): unknown {
    const s = (k: string) => String(topic[k]);
    if (topic.topic === "prefs") return this.device.get("prefs", "device");
    if (topic.topic === "drivePlace") return this.device.get("drive_place", placeOf(topic));
    if (topic.topic === "draft") {
      const soon = this.#soon.get(`${s("station")}${SEP}${s("chat")}`);
      if (soon) return soon[1];
      return this.of(s("station"))?.draft(s("station"), s("chat"));
    }
    if (topic.topic === "loginSessions") return this.#dbs.get(s("account"))?.accountDoc("login_sessions");
    if (topic.topic === "admin") return this.#dbs.get(s("account"))?.accountDoc(`admin/${s("list")}`);
    if (topic.topic === "workspace") return this.#ofWorkspace(s("workspace"))?.workspace(s("workspace"));
    const station = typeof topic.station === "string" ? topic.station : null;
    if (station === null) return undefined;
    const db = this.of(station);
    if (!db) return undefined;
    const kind = LIST_OF[topic.topic];
    if (kind) return db.list(station, kind);
    switch (topic.topic) {
      case "overview":
        if ([...this.#modelEdits.keys(), ...this.#loginSteps.keys()].some((k) => k.startsWith(station + SEP))) return this.shown(topic);
        return db.stationDoc(station, "overview");
      case "footprint":
        return db.stationDoc(station, "footprint");
      case "stationUsage":
        return db.stationDoc(station, "usage");
      case "drive":
        return db.stationDoc(station, driveDoc(s("root"), s("path")));
      case "session":
        return db.detail(station, s("key"));
      case "job":
        return db.job(station, s("id"));
      case "slackApp":
        return db.slackApp(station, s("connect"));
    }
    return undefined;
  }

  /// A held topic's value, a copy to change.
  get(topic: Topic): unknown {
    const v = topic.topic === "overview" ? this.#rawOverview(topic) : this.shared(topic);
    return v === undefined ? undefined : structuredClone(v);
  }

  #rawOverview(topic: Topic): unknown {
    const station = String(topic.station);
    return this.of(station)?.stationDoc(station, "overview");
  }

  /// Whether a list topic's rows are loaded (a view reads them at once), or it holds none.
  loaded(topic: Topic): boolean {
    const kind = LIST_OF[topic.topic];
    const station = typeof topic.station === "string" ? topic.station : null;
    if (!kind || station === null) return true;
    const db = this.of(station);
    return !db || !db.listed(station, kind) || db.loaded(station, kind);
  }

  /// A topic nobody reads any more: what was loaded for it goes.
  release(topic: Topic): void {
    const kind = LIST_OF[topic.topic];
    const station = typeof topic.station === "string" ? topic.station : null;
    if (kind && station !== null) this.of(station)?.release(station, kind);
  }

  /// The visible selection over confirmed data (a profile's models being saved shown as picked).
  shown(topic: Topic): unknown {
    const value = topic.topic === "overview" ? structuredClone(this.#rawOverview(topic)) : this.get(topic);
    if (value === undefined) return undefined;
    if (topic.topic === "overview" && isObject(value) && Array.isArray(value.profiles)) {
      for (const p of value.profiles) {
        if (!isObject(p)) continue;
        const edit = this.#modelEdits.get(join([String(topic.station), typeof p.id === "string" ? p.id : ""]));
        if (edit) {
          p.modelsSaving = edit[1] as never;
          p.models = edit[0] as never;
        }
      }
    }
    if (topic.topic === "overview" && isObject(value)) {
      const station = String(topic.station);
      for (const [key, step] of this.#loginSteps) {
        if (!key.startsWith(station + SEP) || loginAt(value, step.id) !== step.from) continue;
        const logins: unknown[] = Array.isArray(value.logins) ? value.logins : (value.logins = []);
        const i = logins.findIndex((l) => isObject(l) && l.id === step.id);
        if (i < 0) logins.push({ id: step.id, runtime: get(step.job, "runtime"), job: step.job, created: null, error: null });
        else logins[i] = { ...(logins[i] as object), job: step.job };
      }
    }
    return value;
  }

  /// A step of a sign-in for a new profile as its station answered it (`job`), taken from the state `from` (null: the
  /// login not listed yet): shown while the overview still has it there. No job (dropped): let go.
  stepLogin(station: string, id: string, job: unknown, from: string | null): void {
    const key = join([station, id]);
    this.#loginSteps.delete(key);
    if (isObject(job) && loginAt(this.#rawOverview({ topic: "overview", station }), id) === from) this.#loginSteps.set(key, { id, job, from });
    this.#tell({ topic: "overview", station });
  }

  /// The steps an overview of the station has gone past (or that it no longer has where they were): let go.
  #loginsMoved(station: string, overview: unknown): void {
    for (const [key, step] of [...this.#loginSteps]) if (key.startsWith(station + SEP) && loginAt(overview, step.id) !== step.from) this.#loginSteps.delete(key);
  }

  beginModels(station: string, id: string, models: unknown): boolean {
    const key = join([station, id]);
    const overview = this.#rawOverview({ topic: "overview", station });
    const profile = isObject(overview) && Array.isArray(overview.profiles) ? overview.profiles.find((p) => isObject(p) && p.id === id) : undefined;
    const before: unknown[] = isObject(profile) && Array.isArray(profile.models) ? profile.models : [];
    const after: unknown[] = Array.isArray(models) ? models : [];
    const has = (list: unknown[], m: unknown) => list.some((x) => equal(x, m));
    const changed = [...before, ...after].filter((m) => has(before, m) !== has(after, m));
    if (this.#modelEdits.has(key)) return false;
    this.#modelEdits.set(key, [models, changed]);
    this.#tell({ topic: "overview", station });
    return true;
  }

  endModels(station: string, id: string): void {
    this.#modelEdits.delete(join([station, id]));
    this.#tell({ topic: "overview", station });
  }

  /// A held topic's new value (read, or as an event left it). `confirmed`: it came from its source just now (else it
  /// is the core's own change).
  set(topic: Topic, value: unknown, confirmed = true): void {
    const s = (k: string) => String(topic[k]);
    const at = confirmed ? this.#host.nowMs() : null;
    if (topic.topic === "prefs") {
      if (this.device.put("prefs", "device", value)) this.#tell(topic);
      return;
    }
    if (topic.topic === "drivePlace") {
      if (this.device.put("drive_place", placeOf(topic), value)) this.#tell(topic);
      const keys = this.device.keys("drive_place");
      if (keys.length > PLACES_KEPT) {
        const changed = (k: string) => Number(get(this.device.get("drive_place", k), "changed") ?? 0);
        for (const k of keys.sort((a, b) => changed(a) - changed(b)).slice(0, keys.length - PLACES_KEPT)) this.device.put("drive_place", k, undefined);
      }
      return;
    }
    if (topic.topic === "draft") return this.of(s("station"))?.putDraft(s("station"), s("chat"), value);
    if (topic.topic === "loginSessions") return this.#dbs.get(s("account"))?.putAccountDoc("login_sessions", value, at, topic);
    if (topic.topic === "admin") return this.#dbs.get(s("account"))?.putAccountDoc(`admin/${s("list")}`, value, at, topic);
    if (topic.topic === "workspace") return this.#ofWorkspace(s("workspace"))?.putWorkspace(s("workspace"), value, at);
    const station = typeof topic.station === "string" ? topic.station : null;
    if (station === null) return;
    const db = this.of(station);
    if (!db) return;
    const list = Array.isArray(value) ? value : [];
    switch (topic.topic) {
      case "chatRows":
        return db.setChats(station, false, list, at);
      case "archivedRows":
        return db.setChats(station, true, list, at);
      case "sessions":
        return db.setSessions(station, list, at);
      case "threads":
        return db.setThreads(station, list, at);
      case "jobs":
        return db.setJobs(station, list, at);
      case "overview":
        this.#loginsMoved(station, value);
        return db.putStationDoc(station, "overview", value, at, topic);
      case "footprint":
        return db.putStationDoc(station, "footprint", value, at, topic);
      case "stationUsage":
        return db.putStationDoc(station, "usage", value, at, topic);
      case "drive":
        return db.putStationDoc(station, driveDoc(s("root"), s("path")), value, at, topic);
      case "session":
        return db.setDetail(station, s("key"), value);
      case "job":
        return void db.putJob(station, value, false);
      case "slackApp":
        return db.putSlackApp(station, s("connect"), value, at);
    }
  }

  /// A held value as it is typed (a draft): there at once, written a moment after its last change.
  setSoon(topic: Topic, value: unknown): void {
    const key = `${String(topic.station)}${SEP}${String(topic.chat)}`;
    const was = this.#soon.get(key)?.[1] ?? this.shared(topic);
    if (was !== undefined && equal(was, value)) return;
    this.#soon.set(key, [topic, frozen(structuredClone(value))]);
    this.#tell(topic);
    if (this.#flushing) return;
    this.#flushing = true;
    this.#runner.fork(
      Effect.sleep(SOON_MS).pipe(
        Effect.andThen(
          Effect.sync(() => {
            this.#flushing = false;
            const soon = [...this.#soon.values()];
            this.#soon.clear();
            for (const [t, v] of soon) this.set(t, v, false);
          }),
        ),
      ),
    );
  }

  /// What is held to be written a moment after its last change (setSoon), written now: the app's attention moved (a
  /// chat left, the app put behind), and the app may be gone before the moment is.
  flushSoon(): void {
    const soon = [...this.#soon.values()];
    this.#soon.clear();
    for (const [t, v] of soon) this.set(t, v, false);
  }

  /// Changes a held document in place (an event); does nothing while nothing is known of it.
  update(topic: Topic, change: (value: unknown) => unknown): void {
    if (LIST_OF[topic.topic]) throw new Error(`a list is changed row by row: ${topic.topic}`);
    const value = this.get(topic);
    if (value === undefined) return;
    const next = change(value);
    this.set(topic, next === undefined ? value : next);
  }

  /// A held topic known no more (a draft sent or emptied).
  forgetTopic(topic: Topic): void {
    if (topic.topic === "drive") {
      const station = String(topic.station);
      const kind = driveDoc(String(topic.root), String(topic.path));
      const db = this.of(station);
      if (db && db.stationDoc(station, kind) !== undefined) db.dropStationDoc(station, kind, topic);
      return;
    }
    if (topic.topic !== "draft") return;
    const key = `${String(topic.station)}${SEP}${String(topic.chat)}`;
    const soon = this.#soon.delete(key);
    const station = String(topic.station);
    const db = this.of(station);
    if (db && db.draft(station, String(topic.chat)) !== undefined) db.putDraft(station, String(topic.chat), undefined);
    else if (soon) this.#tell(topic);
  }

  // ── what a station said beyond the tables (station/memory.ts), among its documents ──

  stationMemory(station: string, key: string): unknown {
    return this.of(station)?.stationDoc(station, `${MEMORY}${key}`);
  }

  /// `undefined`: none any more.
  keepStationMemory(station: string, key: string, value: unknown): void {
    const db = this.of(station);
    if (!db) return;
    if (value !== undefined) db.putStationDoc(station, `${MEMORY}${key}`, value, this.#host.nowMs(), null);
    else if (db.stationDoc(station, `${MEMORY}${key}`) !== undefined) db.dropStationDoc(station, `${MEMORY}${key}`, null);
  }

  boundStationMemory(station: string, prefix: string, most: number): void {
    this.of(station)?.boundStationDocs(station, `${MEMORY}${prefix}`, most);
  }

  // ── records by table and key: the account's own and the device's ──

  /// A value the core keeps itself: `me` by account; a new chat's picks (`choice`) and chats' links (`chat_ref`), a
  /// workspace's in its account's database (`ws:<id>:…`, `links:<id>`), a station's (`place`, `link`) too; the rest the
  /// device's; the changelog's.
  record(table: string, key: string): unknown {
    const [db, k] = this.#recordAt(table, key);
    if (db === "device") return this.device.get(table, key);
    if (db === null) return undefined;
    if (table === "me") return db.accountDoc("me");
    return db.workspacePref(k[0], k[1]);
  }

  put(table: string, key: string, value: unknown, confirmed = true): void {
    const [db, k] = this.#recordAt(table, key);
    if (db === "device") return void this.device.put(table, key, value);
    if (db === null) return;
    if (table === "me") return db.putAccountDoc("me", value, confirmed ? this.#host.nowMs() : null, null);
    db.putWorkspacePref(k[0], k[1], value);
  }

  forgetRecord(table: string, key: string): void {
    const [db, k] = this.#recordAt(table, key);
    if (db === "device") return void this.device.put(table, key, undefined);
    if (db === null) return;
    if (table === "me") return db.dropAccountDoc("me", null);
    db.putWorkspacePref(k[0], k[1], undefined);
  }

  #recordAt(table: string, key: string): [AccountDb | "device" | null, [string, string]] {
    if (table === "me") return [this.#dbs.get(key) ?? null, ["", ""]];
    if (table === "choice" && key.startsWith("ws:")) {
      const at = key.indexOf(":", 3);
      const ws = at < 0 ? key.slice(3) : key.slice(3, at);
      return [this.#ofWorkspace(ws) ?? null, [ws, `choice:${at < 0 ? "" : key.slice(at + 1)}`]];
    }
    if (table === "chat_ref" && key.startsWith("links:")) {
      const ws = key.slice(6);
      return [this.#ofWorkspace(ws) ?? null, [ws, "links"]];
    }
    // A workspace's lock as the cloud keeps it (views/lock.ts): in the workspace's, by its id.
    if (table === "lock") return [this.#ofWorkspace(key) ?? null, [key, "lock"]];
    // A workspace's vaults as its stations hold them (views/vault.ts): the vaults, box certificates and requests by the
    // workspace's id; each vault's items by `<workspace>/<vault>`.
    if (table === "vault") return [this.#ofWorkspace(key) ?? null, [key, "vault"]];
    if (table === "vaultItems") {
      const ws = ofAddress(key);
      return [this.#ofWorkspace(ws) ?? null, [ws, `vaultItems:${key.slice(ws.length + 1)}`]];
    }
    if (table === "place" || table === "link" || table === "heard" || table === "memberships") {
      // A station's own, kept by its address (`<workspace>/<station>…`), in its workspace's: where a chat was left
      // (`place`, `<address>/<thread>`), how its link was last time (`link`), the last event its stream told (`heard`,
      // written with what it told), the workspaces it is in (`memberships`, views/memberships.ts). Read with what shows
      // them, not on the way.
      const ws = ofAddress(key);
      return [this.#ofWorkspace(ws) ?? null, [ws, `${table}:${key}`]];
    }
    return ["device", ["", ""]];
  }

  /// What is held of a workspace goes (it is gone, or the account left it).
  dropWorkspace(id: string): void {
    for (const db of this.#dbs.values()) if (db.workspace(id) !== undefined) db.dropWorkspace(id);
  }

  /// Every account's `me`, by account.
  mes(): [string, unknown][] {
    return [...this.#dbs].flatMap(([sub, db]) => {
      const me = db.accountDoc("me");
      return me === undefined ? [] : [[sub, me] as [string, unknown]];
    });
  }

  /// Keeps only the stations `keep` picks and, where given, the `workspaces`, each in the database of the account
  /// that reaches it: what no signed-in account reaches goes.
  retain(keep: (station: string) => boolean, workspaces: Set<string> | null): void {
    for (const [sub, db] of this.#dbs) {
      if (db.readOnly) continue;
      for (const id of db.workspaceIds()) if ((workspaces !== null && !workspaces.has(id)) || (this.#owner(id) !== null && this.#owner(id) !== sub)) db.dropWorkspace(id);
      for (const station of db.stations()) {
        const owner = this.#owner(workspaceOf(station));
        if (!keep(station) || (owner !== null && owner !== sub)) db.forgetStation(station);
      }
    }
  }

  // ── what this device did and its station has not confirmed (views/local.ts) ──

  /// Every row of one of those tables, of every account: [station, key, value].
  locals(table: "outbox" | "pending" | "first" | "changing"): [string, string, unknown][] {
    return [...this.#dbs.values()].flatMap((db) => db.locals(table));
  }

  putLocal(table: "outbox" | "pending" | "first" | "changing", station: string, key: string, value: unknown): void {
    this.of(station)?.putLocal(table, station, key, value);
  }

  // ── a station's rows ──

  /// Whether a station's list has been read.
  listed(station: string, kind: ListKind): boolean {
    return this.of(station)?.listed(station, kind) ?? false;
  }

  /// A sidebar row as an event has it.
  putChat(station: string, row: unknown): void {
    this.of(station)?.putChat(station, row);
  }

  dropChat(station: string, id: string): void {
    this.of(station)?.dropChat(station, id);
  }

  chat(station: string, id: string): unknown {
    return this.of(station)?.chat(station, id);
  }

  chatOfThread(station: string, thread: number): unknown {
    if (!Number.isInteger(thread)) return undefined;
    return this.of(station)?.chatOfThread(station, thread);
  }

  chatOfSession(station: string, session: string): unknown {
    return this.of(station)?.chatOfSession(station, session);
  }

  chatOfClientKey(station: string, key: string): unknown {
    return this.of(station)?.chatOfClientKey(station, key);
  }

  /// How often a station's sidebar rows changed.
  rowsRev(station: string): number {
    return this.of(station)?.rowsRev(station) ?? 0;
  }

  /// The rows of these stations a list shows first, across their databases.
  chatHead(stations: string[], limit: number): [string, any][] {
    const by = new Map<AccountDb, string[]>();
    for (const s of stations) {
      const db = this.of(s);
      if (!db) continue;
      by.set(db, [...(by.get(db) ?? []), s]);
    }
    return [...by].flatMap(([db, list]) => db.chatHead(list, limit));
  }

  /// How many sidebar rows these stations have.
  chatCount(stations: string[]): number {
    const by = new Map<AccountDb, string[]>();
    for (const s of stations) {
      const db = this.of(s);
      if (db) by.set(db, [...(by.get(db) ?? []), s]);
    }
    return [...by].reduce((n, [db, list]) => n + db.chatCount(list), 0);
  }

  /// The rows of these stations that ask something of their person or have something unread.
  marked(stations: string[]): [string, any][] {
    const by = new Map<AccountDb, string[]>();
    for (const s of stations) {
      const db = this.of(s);
      if (!db) continue;
      by.set(db, [...(by.get(db) ?? []), s]);
    }
    return [...by].flatMap(([db, list]) => db.marked(list));
  }

  /// The rows of these stations the 奏 page lists.
  desk(stations: string[]): [string, any][] {
    const by = new Map<AccountDb, string[]>();
    for (const s of stations) {
      const db = this.of(s);
      if (db) by.set(db, [...(by.get(db) ?? []), s]);
    }
    return [...by].flatMap(([db, list]) => db.desk(list));
  }

  /// The messages of one thread that have all of `terms`, oldest first (AccountDb.findInThread).
  findInThread(station: string, thread: number, terms: string[]): ReturnType<AccountDb["findInThread"]> {
    return this.of(station)?.findInThread(station, thread, terms) ?? [];
  }

  /// The messages of these stations that have all of `terms`, newest first, across their databases (AccountDb.findSaid).
  findSaid(stations: string[], terms: string[], limit: number): ReturnType<AccountDb["findSaid"]> {
    const by = new Map<AccountDb, string[]>();
    for (const s of stations) {
      const db = this.of(s);
      if (db) by.set(db, [...(by.get(db) ?? []), s]);
    }
    const found = [...by].flatMap(([db, list]) => db.findSaid(list, terms, limit));
    return by.size > 1 ? found.sort((a, b) => (b.at ?? -Infinity) - (a.at ?? -Infinity)).slice(0, limit) : found;
  }

  // ── what is kept within the device's room ──

  /// Whether a log's items were let go for room and its chat is not shown: the sync leaves it as it is.
  evicted(kind: "entry" | "transcript", station: string, id: string): boolean {
    return !this.#shown.has(`${kind}\u0001${station}\u0001${id}`) && (this.of(station)?.evicted(kind, station, id) ?? false);
  }

  /// A UI shows a log's chat (`open`), or no longer does: shown, it is the most recently opened and not let go. Answers
  /// whether its items had been let go (the sync is to bring them back).
  opened(kind: "entry" | "transcript", station: string, id: string, open: boolean): boolean {
    const key = `${kind}\u0001${station}\u0001${id}`;
    const count = (this.#shown.get(key) ?? 0) + (open ? 1 : -1);
    if (count > 0) this.#shown.set(key, count);
    else this.#shown.delete(key);
    const db = this.of(station);
    return db !== undefined && !db.readOnly ? db.opened(kind, station, id, this.#host.nowMs()) && open : false;
  }

  /// Past its room: the agents' transcripts not shown, least recently used first, let go down to KEPT_TO.
  #keepWithin(db: AccountDb): void {
    if (db.readOnly || db.used() <= this.#kept) return;
    const to = this.#kept * KEPT_TO;
    const gone = new Set<string>();
    for (;;) {
      const logs = db.transcriptsByUse(50).filter((l) => {
        const key = `transcript\u0001${l.station}\u0001${l.id}`;
        return !this.#shown.has(key) && !gone.has(key);
      });
      if (logs.length === 0) return;
      for (const l of logs) {
        gone.add(`transcript\u0001${l.station}\u0001${l.id}`);
        db.evict(l.station, l.id);
        if (db.used() <= to) return;
      }
    }
  }

  running(station: string): unknown[] {
    return this.of(station)?.running(station) ?? [];
  }

  putSummary(station: string, summary: unknown): boolean {
    return this.of(station)?.putSummary(station, summary) ?? false;
  }

  dropSession(station: string, key: string): void {
    this.of(station)?.dropSession(station, key);
  }

  summary(station: string, key: string): unknown {
    return this.of(station)?.summary(station, key);
  }

  /// How far a session's transcript goes as far as is known (0: nothing says): its summary's `transcriptLength`, or
  /// further where a stream or a read said so since (`raiseTranscript`, kept while the core runs: the next stream says
  /// where each session at work stands again).
  transcriptHead(station: string, key: string): number {
    const length = get(this.summary(station, key), "transcriptLength");
    const said = typeof length === "number" && Number.isInteger(length) && length > 0 ? length - 1 : 0;
    return Math.max(said, this.#transcriptHeads.get(`${station}\n${key}`) ?? 0);
  }

  /// Whether a session was used here lately (its chat or its history opened within RECENT_MS): its transcript is then
  /// kept whole, down to its first entry (channel-kinds.ts `whole`).
  usedLately(station: string, key: string): boolean {
    const db = this.of(station);
    if (db === undefined) return false;
    const since = this.#host.nowMs() - RECENT_MS;
    const thread = db.threadOf(station, key);
    return (db.lastOpened("transcript", station, key) ?? 0) >= since || (thread !== null && (db.lastOpened("entry", station, String(thread)) ?? 0) >= since);
  }

  raiseTranscript(station: string, key: string, n: number): void {
    const k = `${station}\n${key}`;
    if ((this.#transcriptHeads.get(k) ?? 0) < n) this.#transcriptHeads.set(k, n);
  }

  detail(station: string, key: string): unknown {
    return this.of(station)?.detail(station, key);
  }

  hasDetail(station: string, key: string): boolean {
    return this.of(station)?.hasDetail(station, key) ?? false;
  }

  patchDetail(station: string, key: string, change: (detail: any) => void): void {
    this.of(station)?.patchDetail(station, key, change);
  }

  sessionsToRead(station: string): [string, boolean][] {
    return this.of(station)?.sessionsToRead(station) ?? [];
  }

  listedThread(station: string, id: number): any {
    if (!Number.isInteger(id)) return undefined;
    return this.of(station)?.listedThread(station, id);
  }

  listedSummary(station: string, key: string): unknown {
    return this.of(station)?.listedSummary(station, key);
  }

  thread(station: string, id: number): unknown {
    if (!Number.isInteger(id)) return undefined;
    return this.of(station)?.thread(station, id);
  }

  threadOf(station: string, session: string): number | null {
    return this.of(station)?.threadOf(station, session) ?? null;
  }

  threadIds(station: string): number[] {
    return this.of(station)?.threadIds(station) ?? [];
  }

  /// The station's listed threads the device has yet to bring the latest of (db/account.ts `threadsBehind`).
  threadsBehind(station: string): number[] {
    return this.of(station)?.threadsBehind(station) ?? [];
  }

  threadLast(station: string, id: number): number {
    if (!Number.isInteger(id)) return 0;
    return this.of(station)?.threadLast(station, id) ?? 0;
  }

  putThread(station: string, view: unknown): void {
    this.of(station)?.putThread(station, view);
  }

  dropThread(station: string, id: number): void {
    this.of(station)?.dropThread(station, id);
  }

  unlistThread(station: string, id: number): void {
    this.of(station)?.unlistThread(station, id);
  }

  raiseLast(station: string, id: number, n: number): void {
    if (!Number.isInteger(id)) return;
    this.of(station)?.raiseLast(station, id, n);
  }

  setRead(station: string, id: number, n: number): boolean {
    if (!Number.isInteger(id)) return false;
    return this.of(station)?.setRead(station, id, n) ?? false;
  }

  readPosition(station: string, id: number): number | null {
    if (!Number.isInteger(id)) return null;
    return this.of(station)?.readPosition(station, id) ?? null;
  }

  job(station: string, id: string): unknown {
    return this.of(station)?.job(station, id);
  }

  putJob(station: string, job: unknown, open: boolean): boolean {
    return this.of(station)?.putJob(station, job, open) ?? false;
  }

  // ── logs: a thread's entries, a session's transcript ──

  logNumbers(table: "entry" | "transcript", station: string, id: string): readonly number[] {
    return this.of(station)?.logNumbers(table, station, id) ?? [];
  }

  logRange(table: "entry" | "transcript", station: string, id: string, from: number, to: number): Map<number, unknown> {
    return this.of(station)?.logRange(table, station, id, from, to) ?? new Map();
  }

  /// What a session said in Slack and heard from it, as read from its transcript when it was written (elsewhere.ts).
  slackSaid(station: string, session: string): ReturnType<AccountDb["slackSaid"]> {
    return this.of(station)?.slackSaid(station, session) ?? [];
  }

  /// The Slack people a station's agents heard from, by Slack id: their names, for mentions (`<@U…>`).
  slackNames(station: string): [string, string][] {
    return this.of(station)?.slackNames(station) ?? [];
  }

  logSpan(table: "entry" | "transcript", station: string, id: string): { min: number; max: number; count: number } | null {
    return this.of(station)?.logSpan(table, station, id) ?? null;
  }

  logCount(table: "entry" | "transcript", station: string, id: string, from: number, to: number): number {
    return this.of(station)?.logCount(table, station, id, from, to) ?? 0;
  }

  /// Items into a log, by number (an entry's `n`, a transcript item's index). `cutAfter`: nothing past it is kept.
  putItems(table: "entry" | "transcript", station: string, id: string, items: [number, unknown][], cutAfter: number | null = null): void {
    this.of(station)?.putLog(table, station, id, items, cutAfter);
  }

  forgetLog(table: "entry" | "transcript", station: string, id: string): void {
    this.of(station)?.forgetLog(table, station, id);
  }

  /// What every account's database keeps of each chat (AccountDb.cacheUsage).
  cacheUsage(): ReturnType<AccountDb["cacheUsage"]> {
    return this.dbs().flatMap((db) => db.cacheUsage());
  }

  /// Forgets what is kept of a chat (AccountDb.forgetChat).
  forgetChat(station: string, thread: number): void {
    this.of(station)?.forgetChat(station, thread);
  }

  /// What a chat shows small, as kept on the device (AccountDb.keptFile), noted as shown now.
  keptFile(station: string, session: string, name: string, kind: string): { type: string; bytes: string } | null {
    return this.of(station)?.keptFile(station, session, name, kind, this.#host.nowMs()) ?? null;
  }

  /// Whether what a chat shows small is kept on the device (AccountDb.hasKeptFile).
  hasKeptFile(station: string, session: string, name: string, kind: string): boolean {
    return this.of(station)?.hasKeptFile(station, session, name, kind) ?? false;
  }

  /// Keeps what a chat shows small (AccountDb.keepFile).
  keepFile(station: string, session: string, name: string, kind: string, type: string, bytes: string): void {
    this.of(station)?.keepFile(station, session, name, kind, type, bytes, this.#host.nowMs());
  }

  /// Where the trees of the Markdown `station`'s agents said for `of` (a chat, `t:<thread>`; an agent, `s:<session>`) are
  /// kept on the device (AccountDb.keptMd): none without its account's database.
  mdStore(station: string, of: string): MdStore | undefined {
    const db = this.of(station);
    if (db === undefined) return undefined;
    return {
      has: (key) => db.hasMd(station, key),
      get: (key) => db.keptMd(station, key, this.#host.nowMs()),
      put: (key, json) => db.keepMd(station, of, key, json, Math.floor(this.#host.nowMs())),
    };
  }

  /// The chats `station`'s agents last spoke in (AccountDb.recentThreads).
  recentThreads(station: string, since: number, most: number): number[] {
    return this.of(station)?.recentThreads(station, since, most) ?? [];
  }

  /// What a host error is, as a note's detail.
  static detail(e: unknown): string {
    return e instanceof HostError || e instanceof Error ? e.message : String(e);
  }
}
