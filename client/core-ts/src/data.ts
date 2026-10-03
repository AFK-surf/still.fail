// The core's data center (docs/core-db.md): every piece of business data still.fail cloud and the stations said, as
// records by table and key, in memory and written through to the host's database (one writer fiber, batches in the
// order they were made). Topics of this data have no value of their own: their value is read from here, and a change
// here tells the store, which pushes what changed.
//
// The tables the Rust core has keep its keys and JSON (either core opens the other's database). The TS core adds:
// - `confirmed`: when each record was last confirmed by its source (`<table>␁<key>` → ms);
// - `entry`: a thread's entries, `<station>␁<thread>␁<n, 12 digits>`; `transcript`: a session's transcript items,
//   `<station>␁<session>␁<i, 12 digits>` — what kept.rs kept in storage chunks;
// - `outbox`: messages sent from this device not yet in their thread, `<station>␁<thread>␁<local id>`;
// - `archived_row`, `job_open`, `job`, `slack_app`, `usage`, `footprint`, `login_sessions`, `admin`: the rest of what
//   the topics show, so every topic is read from here.
import { Deferred, Effect, Queue } from "effect";
import type { DbOp, Host } from "./host.ts";
import type { Topic } from "./protocol.ts";
import type { Runner } from "./runtime.ts";
import { compareKeys, equal, isObject, parseJson, toJsonBytes } from "./util.ts";

/// Between the parts of a key: sorts before every character a part can hold.
export const SEP = "\u0001";

/// The tables loaded whole at start (entries and transcripts are loaded a thread at a time).
const TABLES = [
  "me",
  "workspace",
  "overview",
  "session",
  "row",
  "session_summary",
  "thread",
  "list",
  "draft",
  "chat_ref",
  "choice",
  "prefs",
  "changelog",
  "confirmed",
  "outbox",
  "archived_row",
  "job_open",
  "job",
  "slack_app",
  "usage",
  "footprint",
  "login_sessions",
  "admin",
  "pending",
];

export function join(parts: (string | number)[]): string {
  return parts.join(SEP);
}

/// A number in a key, so keys sort as numbers do.
export function num(n: number): string {
  return String(n).padStart(12, "0");
}

type Shape = { one: { table: string; key: string } } | { list: { table: string; scope: string; idField: string } };

function shape(topic: Topic): Shape | null {
  const s = (k: string) => String(topic[k]);
  switch (topic.topic) {
    case "workspace":
      return { one: { table: "workspace", key: s("workspace") } };
    case "overview":
      return { one: { table: "overview", key: s("station") } };
    case "session":
      return { one: { table: "session", key: join([s("station"), s("key")]) } };
    case "chatRows":
      return { list: { table: "row", scope: s("station"), idField: "id" } };
    case "sessions":
      return { list: { table: "session_summary", scope: s("station"), idField: "key" } };
    case "threads":
      return { list: { table: "thread", scope: s("station"), idField: "id" } };
    case "archivedRows":
      return { list: { table: "archived_row", scope: s("station"), idField: "id" } };
    case "jobs":
      return { list: { table: "job_open", scope: s("station"), idField: "id" } };
    case "job":
      return { one: { table: "job", key: join([s("station"), s("id")]) } };
    case "slackApp":
      return { one: { table: "slack_app", key: join([s("station"), s("connect")]) } };
    case "stationUsage":
      return { one: { table: "usage", key: s("station") } };
    case "footprint":
      return { one: { table: "footprint", key: s("station") } };
    case "loginSessions":
      return { one: { table: "login_sessions", key: s("account") } };
    case "admin":
      return { one: { table: "admin", key: join([s("account"), s("list")]) } };
    case "draft":
      return { one: { table: "draft", key: join([s("station"), s("chat")]) } };
    case "prefs":
      return { one: { table: "prefs", key: "device" } };
    default:
      return null;
  }
}

/// Whether a topic's value is held here.
export function holds(topic: Topic): boolean {
  return shape(topic) !== null;
}

/// How long a record changing as it is typed waits before it is written.
export const SOON_MS = 300;

function idText(id: unknown): string | null {
  if (typeof id === "string") return id;
  if (typeof id === "number") return String(id);
  return null;
}

function copy<T>(v: T): T {
  return v === null || v === undefined || typeof v !== "object" ? v : structuredClone(v);
}

/// What was asked of the writer: a batch, or a mark to tell once every batch before it is written.
type Write = { ops: DbOp[] } | { mark: Deferred.Deferred<void> };

/// A log of a thread or a transcript, loaded: its items by number.
type Items = Map<number, unknown>;

export class Data {
  readonly #host: Host;
  readonly #runner: Runner;
  readonly #records = new Map<string, Map<string, unknown>>();
  #changed: ((topic: Topic) => void) | null = null;
  readonly #writes: Queue.Queue<Write>;
  readonly #soon = new Map<string, [string, string, Uint8Array]>();
  #flushing = false;
  readonly #modelEdits = new Map<string, [unknown, unknown]>();
  /// Threads' entries and sessions' transcripts loaded from the database, by `<table>␁<station>␁<thread or session>`.
  readonly #logs = new Map<string, Items>();
  /// Told when entries or transcript items of a log change: `(table, station, id)`.
  #logChanged: ((table: string, station: string, id: string) => void) | null = null;

  constructor(host: Host, runner: Runner) {
    this.#host = host;
    this.#runner = runner;
    this.#writes = Effect.runSync(Queue.unbounded<Write>());
    // The one writer: batches in the order they were made, a failed one left (the next change writes it again).
    runner.fork(
      Effect.forever(
        Effect.flatMap(Queue.take(this.#writes), (w) =>
          "ops" in w ? Effect.ignore(Effect.suspend(() => host.dbWrite(w.ops))) : Deferred.succeed(w.mark, undefined),
        ),
      ),
    );
  }

  onChange(listener: (topic: Topic) => void): void {
    this.#changed = listener;
  }

  onLogChange(listener: (table: string, station: string, id: string) => void): void {
    this.#logChanged = listener;
  }

  #table(table: string): Map<string, unknown> {
    let t = this.#records.get(table);
    if (!t) {
      t = new Map();
      this.#records.set(table, t);
    }
    return t;
  }

  /// Reads every record from the host's database (all but the logs, read a thread at a time). What arrived meanwhile
  /// is newer and stays.
  get load(): Effect.Effect<void> {
    return Effect.gen({ self: this }, function* () {
      const found: [string, string, unknown][] = [];
      for (const table of TABLES) {
        const rows = yield* Effect.orElseSucceed(this.#host.dbRead({ table, from: "", to: "\u{10ffff}" }), () => [] as [string, Uint8Array][]);
        for (const [key, bytes] of rows) {
          const value = parseJson(bytes);
          if (value !== undefined) found.push([table, key, value]);
        }
      }
      for (const [table, key, value] of found) {
        const t = this.#table(table);
        if (!t.has(key)) t.set(key, value);
      }
      this.#tellAll();
    });
  }

  /// A held topic's value; undefined while nothing is known of it.
  get(topic: Topic): unknown {
    const s = shape(topic);
    if (!s) return undefined;
    if ("one" in s) return copy(this.#records.get(s.one.table)?.get(s.one.key));
    const { table, scope } = s.list;
    const ids = this.#records.get("list")?.get(join([table, scope]));
    if (!Array.isArray(ids)) return undefined;
    const items = this.#records.get(table);
    const out: unknown[] = [];
    for (const id of ids) {
      if (typeof id !== "string") continue;
      const item = items?.get(join([scope, id]));
      if (item !== undefined) out.push(copy(item));
    }
    return out;
  }

  /// The visible selection over confirmed data (a profile's models being saved shown as picked).
  shown(topic: Topic): unknown {
    const value = this.get(topic);
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
    return value;
  }

  beginModels(station: string, id: string, models: unknown): boolean {
    const key = join([station, id]);
    const overview = this.get({ topic: "overview", station });
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

  #put(ops: DbOp[], table: string, key: string, value: unknown): void {
    const t = this.#table(table);
    if (t.has(key) && equal(t.get(key), value)) return;
    ops.push({ put: { table, key, value: toJsonBytes(value) } });
    t.set(key, copy(value));
  }

  /// When the record was last confirmed by its source; null if never.
  confirmedAt(table: string, key: string): number | null {
    const at = this.#records.get("confirmed")?.get(join([table, key]));
    return typeof at === "number" ? at : null;
  }

  /// A held topic's new value (read, or as an event left it): its records that differ are written, those of items no
  /// longer in a list removed. `confirmed`: it came from its source just now (else it is the core's own change).
  set(topic: Topic, value: unknown, confirmed = true): void {
    const s = shape(topic);
    if (!s) return;
    const ops: DbOp[] = [];
    let at: [string, string];
    if ("one" in s) {
      this.#put(ops, s.one.table, s.one.key, value);
      at = [s.one.table, s.one.key];
    } else {
      const { table, scope, idField } = s.list;
      const items = Array.isArray(value) ? value : [];
      const ids: string[] = [];
      for (const item of items) {
        const id = idText(isObject(item) ? item[idField] : undefined);
        if (id === null) continue;
        ids.push(id);
        this.#put(ops, table, join([scope, id]), item);
      }
      const kept = new Set(ids.map((id) => join([scope, id])));
      const prefix = scope + SEP;
      const t = this.#table(table);
      for (const key of [...t.keys()].sort(compareKeys)) {
        if (key.startsWith(prefix) && !kept.has(key)) {
          t.delete(key);
          ops.push({ delete: { table, key } });
        }
      }
      this.#put(ops, "list", join([table, scope]), ids);
      at = ["list", join([table, scope])];
    }
    if (confirmed) this.#put(ops, "confirmed", join(at), this.#host.nowMs());
    if (ops.length > 0) {
      this.#write(ops);
      if (ops.some((op) => !("put" in op && op.put.table === "confirmed"))) this.#tell(topic);
    }
  }

  /// A held topic's new value, as it is typed (a draft): there at once, written a moment after its last change.
  setSoon(topic: Topic, value: unknown): void {
    const s = shape(topic);
    if (!s || !("one" in s)) return this.set(topic, value, false);
    const { table, key } = s.one;
    const t = this.#table(table);
    if (t.has(key) && equal(t.get(key), value)) return;
    this.#soon.set(join([table, key]), [table, key, toJsonBytes(value)]);
    t.set(key, copy(value));
    this.#tell(topic);
    if (this.#flushing) return;
    this.#flushing = true;
    this.#runner.fork(
      Effect.sleep(SOON_MS).pipe(
        Effect.andThen(
          Effect.sync(() => {
            this.#flushing = false;
            const ops: DbOp[] = [...this.#soon.values()].map(([table, key, value]) => ({ put: { table, key, value } }));
            this.#soon.clear();
            if (ops.length > 0) this.#write(ops);
          }),
        ),
      ),
    );
  }

  /// Changes a held topic's value in place (an event); does nothing while nothing is known of it.
  update(topic: Topic, change: (value: unknown) => unknown): void {
    const value = this.get(topic);
    if (value === undefined) return;
    const next = change(value);
    this.set(topic, next === undefined ? value : next);
  }

  /// A record the core keeps itself, by table and key.
  record(table: string, key: string): unknown {
    return copy(this.#records.get(table)?.get(key));
  }

  put(table: string, key: string, value: unknown, confirmed = true): void {
    const ops: DbOp[] = [];
    this.#put(ops, table, key, value);
    if (ops.length === 0) return;
    if (confirmed) this.#put(ops, "confirmed", join([table, key]), this.#host.nowMs());
    this.#write(ops);
  }

  /// Every record of a table, by key, in key order.
  records(table: string): [string, unknown][] {
    const t = this.#records.get(table);
    if (!t) return [];
    return [...t.keys()].sort(compareKeys).map((k) => [k, copy(t.get(k))]);
  }

  /// Keeps only the stations `keep` picks and, where given, the `workspaces`: what no signed-in account reaches goes.
  retain(keep: (station: string) => boolean, workspaces: Set<string> | null): void {
    const stationOf = (table: string, key: string): string | null => {
      const at = key.indexOf(SEP);
      switch (table) {
        case "overview":
        case "usage":
        case "footprint":
          return key;
        case "list":
          return at >= 0 ? key.slice(at + 1) : null;
        case "confirmed": {
          const [t, ...rest] = key.split(SEP);
          return stationOf(t, rest.join(SEP));
        }
        case "session":
        case "row":
        case "session_summary":
        case "thread":
        case "archived_row":
        case "job_open":
        case "job":
        case "slack_app":
        case "outbox":
        case "entry":
        case "transcript":
          return at >= 0 ? key.slice(0, at) : null;
        default:
          return null;
      }
    };
    this.#forget((table, key) => {
      if (table === "workspace") return workspaces !== null && !workspaces.has(key);
      if (table === "confirmed" && key.startsWith(`workspace${SEP}`)) return workspaces !== null && !workspaces.has(key.slice(10));
      const station = stationOf(table, key);
      return station !== null && !keep(station);
    });
    // What is not loaded is gone from the database too.
    this.#runner.fork(
      Effect.gen({ self: this }, function* () {
        for (const table of ["entry", "transcript"]) {
          const rows = yield* Effect.orElseSucceed(this.#host.dbRead({ table, from: "", to: "\u{10ffff}" }), () => [] as [string, Uint8Array][]);
          const gone = rows.filter(([key]) => !keep(key.slice(0, key.indexOf(SEP))));
          if (gone.length > 0) this.#write(gone.map(([key]) => ({ delete: { table, key } })));
        }
      }),
    );
    for (const name of [...this.#logs.keys()]) {
      const [, station] = name.split(SEP);
      if (!keep(station)) this.#logs.delete(name);
    }
  }

  /// A held topic known no more (a draft sent or emptied).
  forgetTopic(topic: Topic): void {
    const s = shape(topic);
    if (!s || !("one" in s)) return;
    const { table, key } = s.one;
    this.#soon.delete(join([table, key]));
    if (this.#records.get(table)?.delete(key)) {
      this.#write([{ delete: { table, key } }]);
      this.#tell(topic);
    }
  }

  forgetRecord(table: string, key: string): void {
    this.#forget((t, k) => (t === table && k === key) || (t === "confirmed" && k === join([table, key])));
  }

  #forget(doomed: (table: string, key: string) => boolean): void {
    const gone: [string, string][] = [];
    for (const table of [...this.#records.keys()].sort(compareKeys)) {
      for (const key of [...this.#records.get(table)!.keys()].sort(compareKeys)) if (doomed(table, key)) gone.push([table, key]);
    }
    if (gone.length === 0) return;
    for (const [table, key] of gone) this.#records.get(table)!.delete(key);
    this.#write(gone.map(([table, key]) => ({ delete: { table, key } })));
    this.#tellAll();
  }

  // ── logs: threads' entries, sessions' transcripts ──

  /// A log's items, loaded from the database the first time.
  log(table: "entry" | "transcript", station: string, id: string): Effect.Effect<Items> {
    return Effect.suspend(() => {
      const name = join([table, station, id]);
      const loaded = this.#logs.get(name);
      if (loaded) return Effect.succeed(loaded);
      const prefix = join([station, id]) + SEP;
      return Effect.orElseSucceed(this.#host.dbRead({ table, from: prefix, to: join([station, id]) + "\u0002" }), () => [] as [string, Uint8Array][]).pipe(
        Effect.map((rows) => {
          // Loaded meanwhile (and told of what came since): that one.
          const again = this.#logs.get(name);
          if (again) return again;
          const items: Items = new Map();
          for (const [key, bytes] of rows) {
            const value = parseJson(bytes);
            if (value !== undefined) items.set(Number(key.slice(prefix.length)), value);
          }
          this.#logs.set(name, items);
          return items;
        }),
      );
    });
  }

  /// A log's items if it is loaded (synchronously; views read what is there).
  loaded(table: "entry" | "transcript", station: string, id: string): Items | null {
    return this.#logs.get(join([table, station, id])) ?? null;
  }

  /// Items into a log, by number (an entry's `n`, a transcript item's index); those it has that are the same change
  /// nothing. `truncate`: nothing after them is kept (a transcript written anew from `from`).
  putItems(table: "entry" | "transcript", station: string, id: string, items: [number, unknown][], truncate = false): Effect.Effect<void> {
    return Effect.map(this.log(table, station, id), (log) => {
      const ops: DbOp[] = [];
      for (const [n, value] of items) {
        const before = log.get(n);
        if (before !== undefined && equal(before, value)) continue;
        log.set(n, copy(value));
        ops.push({ put: { table, key: join([station, id, num(n)]), value: toJsonBytes(value) } });
      }
      if (truncate && items.length > 0) {
        const last = Math.max(...items.map(([n]) => n));
        for (const n of [...log.keys()]) {
          if (n > last) {
            log.delete(n);
            ops.push({ delete: { table, key: join([station, id, num(n)]) } });
          }
        }
      }
      if (ops.length > 0) {
        this.#write(ops);
        this.#logChanged?.(table, station, id);
      }
    });
  }

  /// A log known no more (its thread or session went).
  forgetLog(table: "entry" | "transcript", station: string, id: string): Effect.Effect<void> {
    return Effect.map(this.log(table, station, id), (log) => {
      const ops: DbOp[] = [...log.keys()].map((n) => ({ delete: { table, key: join([station, id, num(n)]) } }));
      log.clear();
      if (ops.length > 0) {
        this.#write(ops);
        this.#logChanged?.(table, station, id);
      }
    });
  }

  #tell(topic: Topic): void {
    this.#changed?.(topic);
  }

  #tellAll(): void {
    const topics = new Map<string, Topic>();
    for (const [table, rows] of this.#records) {
      for (const key of rows.keys()) {
        const topic = topicOf(table, key);
        if (topic) topics.set(JSON.stringify(topic), topic);
      }
    }
    for (const topic of topics.values()) this.#tell(topic);
  }

  #write(ops: DbOp[]): void {
    Queue.offerUnsafe(this.#writes, { ops });
  }

  /// Resolves once every write asked for so far is done.
  get written(): Effect.Effect<void> {
    return Effect.gen({ self: this }, function* () {
      const mark = yield* Deferred.make<void>();
      Queue.offerUnsafe(this.#writes, { mark });
      yield* Deferred.await(mark);
    });
  }
}

/// The topic a record is (part) of.
function topicOf(table: string, key: string): Topic | null {
  const parts = key.split(SEP);
  switch (table) {
    case "workspace":
      return { topic: "workspace", workspace: key };
    case "overview":
      return { topic: "overview", station: key };
    case "usage":
      return { topic: "stationUsage", station: key };
    case "footprint":
      return { topic: "footprint", station: key };
    case "session":
      return parts.length === 2 ? { topic: "session", station: parts[0], key: parts[1] } : null;
    case "job":
      return parts.length === 2 ? { topic: "job", station: parts[0], id: parts[1] } : null;
    case "slack_app":
      return parts.length === 2 ? { topic: "slackApp", station: parts[0], connect: parts[1] } : null;
    case "login_sessions":
      return { topic: "loginSessions", account: key };
    case "admin":
      return parts.length === 2 ? { topic: "admin", account: parts[0], list: parts[1] } : null;
    case "row":
      return { topic: "chatRows", station: parts[0] };
    case "session_summary":
      return { topic: "sessions", station: parts[0] };
    case "thread":
      return { topic: "threads", station: parts[0] };
    case "archived_row":
      return { topic: "archivedRows", station: parts[0] };
    case "job_open":
      return { topic: "jobs", station: parts[0] };
    case "list": {
      if (parts.length !== 2) return null;
      const [t, scope] = parts;
      const of: Record<string, string> = { row: "chatRows", session_summary: "sessions", thread: "threads", archived_row: "archivedRows", job_open: "jobs" };
      return of[t] ? { topic: of[t], station: scope } : null;
    }
    default:
      return null;
  }
}
