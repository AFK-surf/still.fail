// One signed-in account's database: the tables of db/schema.ts, read by indexed queries, written by
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
import { lowerBound, upperBound } from "../ordered.ts";
import { glanced, work } from "../work.ts";
import { LogIndex, LogIndices } from "./log-index.ts";
import { Deferred, Effect, type Fiber, Queue } from "effect";
import type { Sql, SqlRow, SqlValue } from "../host.ts";
import { SqlError, sqlError } from "../host.ts";
import { topicKey, type Topic } from "../protocol.ts";
import type { Runner } from "../runtime.ts";
import { equal, isObject } from "../util.ts";
import { CHAT_COLUMNS, CHAT_MADE, type ChatColumnsMade, ensureChatColumns, ensureFilesKept, ensureKept, ensureLetters, ensureMdKept, ensureOverviewParts, ensureSaid, ensureSlackSaid, giveBackRoom, migrate, overviewProfilesOf, PART_COLUMNS, partRev, versionOf } from "./schema.ts";
import { CHAT_READS, rowColumns, type ChatRead } from "./chat-reads.ts";
import { KEPT, KEPT_ALL, KeptValues, type ListRow } from "./kept.ts";
import { readItem, type Said } from "../elsewhere.ts";
import { timed } from "../spent.ts";
import { OWN_SURFACES } from "../titles.ts";

/// The station's own chats' surfaces, as SQL's list.
const OWN_IN = OWN_SURFACES.map((s) => `'${s}'`).join(", ");

// deno-lint-ignore no-explicit-any
type J = any;

/// What the core finds a chat row by that only it can say (views/marks.ts, decisions.ts): how urgent the row is for
/// its person, whether it asks something.
/// `state`: what its agents are doing as its list's row says it (present.rowState: "block", "run", "failed", or null), of its
/// `agents` alone (a row derived again at open is given those alone: schema.ts ensureChatColumns); `watched`, whether one
/// of its agents keeps watch (present.watches), of them too.
export type Derive = { tone(row: J): string | null; asks(row: J): boolean; state(row: J): string | null; watched(row: J): boolean };

/// What a list reads first of a chat (listHead): its row kept beside it under the key in force, else its record.
export type HeadRow = { station: string; id: string; pinnedAt: number | null; row: ListRow | null; record: J };
export type { ListRow };

/// A chat row before and after a burst (undefined: not there).
export type RowChange = { id: string; before: J | undefined; after: J | undefined };
/// A row written, for the declared reads (chat-reads.ts): its records and its place (`ord`) before and after.
type ReadChatChange = RowChange & { archived: boolean; between?: J[]; ordBefore: number | undefined; ordAfter: number | undefined };

/// What a burst changed.
export type Changes = {
  /// The held topics whose values changed.
  topics: Map<string, Topic>;
  /// Each station's sidebar rows (archived = 0) that changed.
  chats: Map<string, Map<string, RowChange>>;
  /// Changed rows, including archived ones: indexed readers must refresh after a commit or a rollback.
  readChats: Map<string, Map<string, ReadChatChange>>;
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
export class Collection {
  readonly items = new Map<string, J>();
  readonly sort = new Map<string, number[]>();
  /// The rows in order, and their ids: made once, then each change put in its place on copies of them (one row of 1400
  /// changed sorted all of them again, as each chat's new message did, 2026-11-08).
  #array: J[] | null = null;
  #ids: string[] | null = null;
  readonly descending: boolean;
  constructor(descending: boolean) {
    this.descending = descending;
  }

  #before(x: number[], a: string, y: number[], b: string): number {
    const d = this.descending ? -1 : 1;
    for (let i = 0; i < x.length; i++) if (x[i] !== y[i]) return (x[i]! - y[i]!) * d;
    return a < b ? -1 : a > b ? 1 : 0;
  }

  /// Where id with `sort` is, or goes, in the ids in order.
  #at(ids: string[], id: string, sort: number[]): number {
    let lo = 0;
    let hi = ids.length;
    while (lo < hi) {
      const mid = (lo + hi) >> 1;
      if (this.#before(this.sort.get(ids[mid]!)!, ids[mid]!, sort, id) < 0) lo = mid + 1;
      else hi = mid;
    }
    return lo;
  }

  #out(id: string): { ids: string[]; rows: J[] } | null {
    if (!this.#ids || !this.#array) return null;
    const ids = this.#ids.slice();
    const rows = this.#array.slice();
    const was = this.sort.get(id);
    if (was !== undefined) {
      const at = this.#at(ids, id, was);
      if (ids[at] === id) {
        ids.splice(at, 1);
        rows.splice(at, 1);
      } else return null;
    }
    return { ids, rows };
  }

  set(id: string, row: J, sort: number[]): void {
    const kept = this.#out(id);
    this.items.set(id, row);
    this.sort.set(id, sort);
    if (kept === null) {
      this.#array = null;
      this.#ids = null;
      return;
    }
    const at = this.#at(kept.ids, id, sort);
    kept.ids.splice(at, 0, id);
    kept.rows.splice(at, 0, row);
    this.#ids = kept.ids;
    this.#array = kept.rows;
  }

  delete(id: string): void {
    if (!this.items.has(id)) return;
    const kept = this.#out(id);
    this.items.delete(id);
    this.sort.delete(id);
    this.#ids = kept?.ids ?? null;
    this.#array = kept?.rows ?? null;
  }

  /// The rows in order (the same array while nothing changed).
  array(): J[] {
    if (this.#array) return this.#array;
    const ids = [...this.items.keys()];
    ids.sort((a, b) => this.#before(this.sort.get(a)!, a, this.sort.get(b)!, b));
    this.#ids = ids;
    this.#array = ids.map((id) => this.items.get(id));
    return this.#array;
  }
}

/// How many items of a log a read takes from SQLite one by one, beside those parsed already; more, it reads the range.
const LOG_READ_ALONE = 16;
/// How many changes of a log are kept said (`logPutSince`), and of how many logs.
const LOG_PUTS_KEPT = 64;
const LOG_PUTS_LOGS = 512;

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
/// A word looked for, as `LIKE ? ESCAPE '\'` takes it: anywhere in the text, its own `%` `_` `\` as they are.
const like = (term: string) => `%${term.replace(/[\\%_]/g, (c) => `\\${c}`)}%`;
/// What chats show small, kept (`file_kept`, in characters of base64): at most this much, let go to FILES_KEPT_TO of it
/// past that; one larger than FILE_KEPT_MOST is not kept (a thumbnail is a few dozen KB). When one was shown is noted
/// at most once in FILE_SHOWN_EVERY: a note writes its row again, the image with it.
const FILES_KEPT = 64 * 1024 * 1024;
const FILES_KEPT_TO = 0.8;
const FILE_KEPT_MOST = 1024 * 1024;
const FILE_SHOWN_EVERY = 86_400_000;
/// The trees of agents' words kept (`md_kept`, in characters of their JSON), as file_kept's: at most this much, let go
/// to MD_KEPT_TO of it past that, when one was shown noted at most once in MD_SHOWN_EVERY.
const MD_KEPT = 32 * 1024 * 1024;
const MD_KEPT_TO = 0.8;
const MD_SHOWN_EVERY = 86_400_000;

/// The tables of what this device did itself: written again on their own when a burst could not be (a full disk).
const PRECIOUS = /^(INSERT|DELETE|UPDATE)[^(]*\b(outbox|pending|first|changing|draft|workspace_pref)\b/i;

/// Where a document is kept (#putDoc): its table, the columns of its key and their values, and when its source confirmed
/// it (null: not now; undefined: the table keeps none).
type Doc = { table: string; keys: string[]; of: SqlValue[]; confirmed?: number | null };

/// The chat columns of a row, and its JSON without them.
type ChatCols = { json: string; unread: number | null; thread: number | null; session: string | null; clientKey: string | null; lastActive: number; pinnedAt: number | null; mine: number; running: number; tone: string | null; asks: number; state: string | null; watched: number };

/// A chat row a declared read found (chat-reads.ts): its keys, the read's own columns after them (`cols`, from the
/// fourth), and its record where the read asked for it (read by its key, from the cache where held).
export type ChatFound = { station: string; archived: boolean; id: string; cols: SqlRow; record: J | undefined };

/// The rows a declared read's statement gave, each a ChatFound of its own (its record not read).
export const foundOf = (rows: readonly SqlRow[]): ChatFound[] => rows.map((r) => ({ station: String(r[0]), archived: r[1] === 1, id: String(r[2]), cols: r.slice(3), record: undefined }));

/// The statement that puts a chat's record: the columns every core writes, `state` and `made` this core's, and those
/// SQLite makes of its JSON (schema.ts CHAT_COLUMNS), of the JSON given last.
const PUT_CHAT = `INSERT OR REPLACE INTO chat (station, id, archived, ord, thread, session, client_key, last_active, pinned_at, unread, mine, running, tone, asks, state, watched, made, json, ${CHAT_COLUMNS.map(([c]) => c).join(", ")})
  SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ${CHAT_MADE}, r.json, ${CHAT_COLUMNS.map(([, of]) => of("r.json")).join(", ")} FROM (SELECT ? AS json) AS r`;


/// A chat row as a station's list was last written (`setChats`): the row as it was given (null: only read), and its
/// place.
type HeldChat = { row: J; ord: number };

/// The most rows of a list given that `setChats` compares with what is written by reading them by their keys: more,
/// and it reads the list once.
const CHATS_COMPARED_BY_KEY = 8;

/// The logs a station's channels are held in (station/channel-kinds.ts): a thread's entries, its letters (their own log
/// beside its entries), a session's transcript.
export type LogTable = "entry" | "letter" | "transcript";

/// A log's id column and item number column.
const logColumns = (table: LogTable): [string, string] => (table === "transcript" ? ["session", "i"] : ["thread", "n"]);

/// A log's id as its id column holds it (a thread's a number).
const logId = (table: LogTable, id: string): SqlValue => (table === "transcript" ? id : Number(id));

export class AccountDb {
  readonly sub: string;
  readonly name: string;
  readonly sql: Sql;
  /// Written by a newer core: read, never written.
  readonly readOnly: boolean;
  /// Its version as found (before migrating): 0 for a database made now.
  readonly found: number;
  /// Whether what was said can be found (`said` is there; it could not be made without room).
  readonly #said: boolean = false;
  /// Whether each overview's part the chat list reads is kept (`station_part`; it could not be made without room).
  #parts = false;
  /// The columns of each overview's part this database keeps (schema.ts PART_COLUMNS: `station_part`'s).
  #columns = new Set<string>();
  /// The profiles read of each station's overview, one by one (overviewProfile): let go of as its profiles change.
  readonly #profilesRead = new Map<string, Set<string>>();
  /// What is made of a record and kept beside it (db/kept.ts): a chat list's rows, the overviews' verdicts, the
  /// accounts' rows.
  readonly kept: KeptValues;
  /// The logs let go for room (`log_use`), by K(kind, station, id).
  readonly #evicted = new Set<string>();
  /// Each station's chat list (`chats`, `archived`) as it was last written, by K(list, station), each row by its id
  /// (HeldChat): the row object given and its place, nothing that grows with the row (its JSON would be the list again
  /// in memory, for every station the sync touches, the whole run, to save a read that is seldom needed). So `setChats`
  /// takes a row given that is the one written before (the same object, frozen) at the same place as written, reading
  /// nothing; the few others are read by their keys to be compared, many the list once. Kept true by every write of
  /// the table here (#putChatRow, #deleteChatRow), let go where it could not be (a burst rolled back, a station
  /// forgotten): then the next `setChats` reads the list once.
  readonly #chatsHeld = new Map<string, Map<string, HeldChat>>();
  readonly #runner: Runner;
  readonly #derive: Derive;
  #inTx = false;
  /// What failed in this burst: it is rolled back.
  #failed: SqlError | null = null;
  #changes: Changes = { topics: new Map(), chats: new Map(), readChats: new Map(), logs: new Map(), firstChats: new Set() };
  /// The statements of this burst that are what the device did itself, to be written again if the burst fails.
  #precious: [string, readonly SqlValue[]][] = [];
  /// What could not be written even so, written again with the next burst.
  #unwritten: [string, readonly SqlValue[]][] = [];
  readonly #bursts: Queue.Queue<void>;
  readonly #writer: Fiber.Fiber<never, never>;
  #waiting: Deferred.Deferred<void>[] = [];
  readonly #cache = new Cache(4096);
  readonly #logCache = new Cache(8192);
  readonly #logIndices = new LogIndices();
  /// Each log's span (`logSpan`) as read, kept as items are put in it (putLog), let go as anything else changes it:
  /// a long chat's count was read from SQLite again on every view of it (four times to open one, 2026-11-08).
  readonly #logSpans = new Map<string, { min: number; max: number; count: number } | null>();
  readonly #lists = new Map<string, Collection>();
  /// What was put in each log lately (`logPutSince`), so what is made of a long log reads again only what changed: by
  /// the log, each change's number (`#logRev`, one count for every log) and the numbers it put (null: another change,
  /// a cut or a delete). Of the changes before `from` (a log's, else `#logPutsFrom`) nothing is known.
  #logRev = 0;
  #logPutsFrom = 0;
  readonly #logPuts = new Map<string, { from: number; puts: { rev: number; put: number[] | null }[] }>();
  #closed = false;
  /// Told after each burst is written, with what it changed.
  onCommit: (changes: Changes) => void = () => {};
  /// Told when a burst could not be written for want of room (true), and once one could again (false).
  onFull: (full: boolean, error: string | null) => void = () => {};
  #full = false;
  /// What deriving the chat columns again took as this database was opened (schema.ts ensureChatColumns).
  chatColumnsMade: ChatColumnsMade | null = null;

  constructor(sub: string, name: string, sql: Sql, runner: Runner, derive: Derive) {
    this.sub = sub;
    this.name = name;
    this.sql = sql;
    this.#runner = runner;
    this.#derive = derive;
    this.found = versionOf(sql);
    this.kept = new KeptValues({
      sql,
      write: (fn) => this.#write(fn),
      run: (q, params) => void this.#run(q, params),
      cache: this.#cache,
      held: (source, owner) => {
        const v = this.#cache.get(source === "chat" ? K("chat", owner[0], 0, owner[1]) : source === "station" ? K("st", owner[0], "overview") : K("profiled", owner[0]));
        return v === null ? undefined : v;
      },
      record: (source, owner) => (source === "chat" ? this.chat(owner[0], owner[1]) : source === "station" ? this.stationDoc(owner[0], "overview") : this.overviewProfiled(owner[0])),
    });
    this.readOnly = !migrate(sql);
    if (!this.readOnly) {
      const was = this.sql.all("SELECT value FROM meta WHERE key = 'account'")[0]?.[0];
      if (was === undefined) this.sql.run("INSERT INTO meta (key, value) VALUES ('account', ?)", [sub]);
      ensureLetters(sql);
      try {
        ensureSaid(sql);
        this.#said = true;
      } catch {
        // No room to make it: messages are not found by their words this time.
      }
      try {
        ensureOverviewParts(sql);
        this.#parts = true;
        for (const [column] of PART_COLUMNS) this.#columns.add(column);
      } catch {
        // No room to make it: each part is read of its overview, by SQLite, this time.
      }
      // (after the tables they are kept beside, station_part's: ensureOverviewParts)
      this.kept.open(KEPT_ALL);
      try {
        this.chatColumnsMade = ensureChatColumns(sql, (agents) => ({ state: derive.state({ agents }), watched: derive.watched({ agents }) }));
      } catch (e) {
        // No room to derive them: the rows another core wrote are read by the columns they have, this time.
        console.error("still.fail core: a chat's columns could not be derived:", e instanceof Error ? e.message : String(e));
      }
      try {
        if (ensureSlackSaid(sql)) this.#fillSlackSaid();
      } catch {
        // No room to make it: what agents said in Slack is not shown in their chats this time.
      }
      try {
        ensureKept(sql);
        // A chat's messages are no longer let go for room: those an earlier core let go are the sync's to bring again.
        sql.run("UPDATE log_use SET evicted = 0 WHERE kind = 'entry' AND evicted = 1");
        for (const r of sql.all("SELECT kind, station, id FROM log_use WHERE evicted = 1")) this.#evicted.add(K(String(r[0]), String(r[1]), String(r[2])));
      } catch {
        // No room to make it: nothing is let go this time.
      }
      try {
        giveBackRoom(sql);
      } catch {
        // No room to rewrite it in: the file stays as large this time.
      }
      // Made as the first file is kept: a database that keeps none has no room taken for it.
      this.#filesKept = sql.all("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'file_kept'").length > 0;
      this.#mdKept = sql.all("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'md_kept'").length > 0;
    } else if (this.sql.all("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'said'").length > 0) {
      this.#said = true;
    }
    if (this.readOnly) {
      this.#parts = this.sql.all("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'station_part'").length > 0;
      for (const r of this.#parts ? this.sql.all("PRAGMA table_info(station_part)") : []) this.#columns.add(String(r[1]));
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
    timed("db.commit", () => this.#commitNow());
  }

  #commitNow(): void {
    if (!this.#inTx) return this.#settled();
    const changes = this.#changes;
    const precious = this.#precious;
    this.#changes = { topics: new Map(), chats: new Map(), readChats: new Map(), logs: new Map(), firstChats: new Set() };
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
      // A row change tells noticing what was committed. The retry below only keeps this device's own tables, not
      // the station's chat rows, so none of the rolled-back rows or first-list marker can be announced.
      changes.chats.clear();
      changes.firstChats.clear();
      // What was read is not what is kept any more.
      this.#cache.clear();
      this.kept.forget();
      this.#logCache.clear();
      this.#logIndices.clear();
      this.#logSpans.clear();
      this.#logPutsForgotten();
      this.#lists.clear();
      this.#chatsHeld.clear();
      this.#slackNames.clear();
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

  #tellChatRead(station: string, archived: number, id: string, before: J | undefined, after: J | undefined, ordBefore: number | undefined, ordAfter: number | undefined): void {
    let rows = this.#changes.readChats.get(station);
    if (!rows) {
      rows = new Map();
      this.#changes.readChats.set(station, rows);
    }
    const key = K(String(archived), id);
    const was = rows.get(key);
    if (was) {
      if (was.after !== undefined) (was.between ??= []).push(was.after);
      was.after = after;
      was.ordAfter = ordAfter;
    } else rows.set(key, { id, archived: archived !== 0, before, after, ordBefore, ordAfter });
  }

  /// A log changed: `put` the numbers put in it, null for anything else.
  #tellLog(table: string, station: string, id: string, put: number[] | null = null): void {
    this.#logIndices.delete(K(table, station, id));
    this.#logSpans.delete(K(table, station, id));
    this.#changes.logs.set(K(table, station, id), [table, station, id]);
    if (table === "slack") this.#slackNames.delete(station);
    const key = K(table, station, id);
    const was = this.#logPuts.get(key);
    const log = was ?? { from: this.#logPutsFrom, puts: [] };
    log.puts.push({ rev: ++this.#logRev, put });
    if (log.puts.length > LOG_PUTS_KEPT) log.from = log.puts.shift()!.rev;
    this.#logPuts.delete(key);
    this.#logPuts.set(key, log);
    // (the least lately changed logs' let go: of every log's changes up to theirs nothing is known then)
    while (this.#logPuts.size > LOG_PUTS_LOGS) {
      const [oldest, gone] = this.#logPuts.entries().next().value!;
      this.#logPuts.delete(oldest);
      this.#logPutsFrom = Math.max(this.#logPutsFrom, gone.puts[gone.puts.length - 1]?.rev ?? 0);
    }
  }

  /// Nothing known of what was put in any log until now (what is held changed otherwise: rolled back, a station forgotten).
  #logPutsForgotten(): void {
    this.#logPuts.clear();
    this.#logPutsFrom = ++this.#logRev;
  }

  /// The numbers put in a log since change `since` (`rev` of an answer before; 0: none), and the change it is at now;
  /// `put` null where that is not known (it changed otherwise, or long ago): all of it is to be read again.
  logPutSince(table: LogTable, station: string, id: string, since: number): { rev: number; put: number[] | null } {
    const rev = this.#logRev;
    const log = this.#logPuts.get(K(table, station, id));
    if (since <= 0 || since < (log?.from ?? this.#logPutsFrom)) return { rev, put: null };
    const put = new Set<number>();
    for (const p of log?.puts ?? []) {
      if (p.rev <= since) continue;
      if (p.put === null) return { rev, put: null };
      for (const n of p.put) put.add(n);
    }
    return { rev, put: [...put] };
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
    this.#putDoc(K("acct", name), value, { table: "account_doc", keys: ["name"], of: [name], confirmed }, topic);
  }

  dropAccountDoc(name: string, topic: Topic | null): void {
    this.#dropDoc(K("acct", name), "DELETE FROM account_doc WHERE name = ?", [name], topic);
  }

  workspace(id: string): J {
    return this.#doc(K("ws", id), "SELECT json FROM workspace WHERE id = ?", [id]);
  }

  putWorkspace(id: string, value: J, confirmed: number | null): void {
    this.#putDoc(K("ws", id), value, { table: "workspace", keys: ["id"], of: [id], confirmed }, { topic: "workspace", workspace: id });
  }

  dropWorkspace(id: string): void {
    this.#dropDoc(K("ws", id), "DELETE FROM workspace WHERE id = ?", [id], { topic: "workspace", workspace: id });
  }

  workspaceIds(): string[] {
    return this.sql.all("SELECT id FROM workspace").map((r) => String(r[0]));
  }

  /// A station's overview or usage.
  stationDoc(station: string, kind: string): J {
    const key = K("st", station, kind);
    const read = kind === "overview" && !this.#cache.has(key);
    const v = this.#doc(key, "SELECT json FROM station WHERE address = ? AND kind = ?", [station, kind]);
    if (read && v !== undefined) work.overviewsRead++;
    return v;
  }

  putStationDoc(station: string, kind: string, value: J, confirmed: number | null, topic: Topic | null): void {
    const doc = { table: "station", keys: ["address", "kind"], of: [station, kind], confirmed };
    this.#putDoc(K("st", station, kind), value, doc, topic, kind === "overview" ? (put) => this.#overviewWritten(station, put) : undefined);
  }

  dropStationDoc(station: string, kind: string, topic: Topic | null): void {
    const drop = () => this.#dropDoc(K("st", station, kind), "DELETE FROM station WHERE address = ? AND kind = ?", [station, kind], topic);
    if (kind === "overview") this.#overviewWritten(station, drop);
    else drop();
  }

  /// What the chat list reads of a station's overview (schema.ts overviewPartOf), undefined while none is held: kept
  /// beside it (`station_part`, by triggers), not the overview, which is not read.
  overviewPart(station: string): J {
    return this.#overviewColumn(station, "part");
  }

  /// What a station's row reads of its overview (schema.ts overviewRowOf), undefined while none is held or it is not an
  /// object: kept beside its part (`station_part.row`), not in it, so the chat list reads and parses what it did.
  overviewRow(station: string): J {
    return this.#overviewColumn(station, "row");
  }

  /// What a chat's page reads of its station's overview (schema.ts overviewChatOf), undefined while none is held or it
  /// is not an object: kept beside its part (`station_part.chat`), not the overview, which is not read.
  overviewChat(station: string): J {
    return this.#overviewColumn(station, "chat");
  }

  /// The stations a station took the place of (schema.ts overviewFormerlyOf), undefined while no overview is held:
  /// kept beside its part (`station_part.formerly`).
  overviewFormerly(station: string): J {
    return this.#overviewColumn(station, "formerly");
  }

  /// What the workspace's profiles read of a station's overview (schema.ts overviewProfiledOf), undefined while no
  /// overview is held: kept beside its part (`station_part.profiled`).
  overviewProfiled(station: string): J {
    return this.#overviewColumn(station, "profiled");
  }

  /// The profile `id` of a station's overview, whole, undefined where it has none such (schema.ts overviewProfilesOf):
  /// that one alone read out of the column of its profiles by SQLite, not the overview, nor its other profiles.
  overviewProfile(station: string, id: string): J {
    const key = K("profile", station, id);
    if (this.#cache.has(key)) return this.#cache.get(key) ?? undefined;
    let read = this.#profilesRead.get(station);
    if (read === undefined) this.#profilesRead.set(station, (read = new Set()));
    read.add(id);
    const path = `$.${JSON.stringify(id)}`;
    const kept = this.#columns.has("profiles") ? this.sql.all("SELECT profiles IS NOT NULL, profiles -> ? FROM station_part WHERE address = ?", [path, station])[0] : undefined;
    const r = kept !== undefined && kept[0] === 1
      ? kept[1]
      : this.sql.all(`SELECT (${overviewProfilesOf("st.json")}) -> ? FROM station AS st WHERE st.address = ? AND st.kind = 'overview' AND json_valid(st.json)`, [path, station])[0]?.[0];
    const text = typeof r === "string" ? r : undefined;
    if (text !== undefined) {
      work.overviewParts++;
      work.overviewPartChars += text.length;
    }
    const v = text === undefined ? undefined : frozen(JSON.parse(text));
    this.#cache.set(key, v ?? null);
    return v;
  }

  /// Column `column` of a station's part (schema.ts PART_COLUMNS), parsed, kept till it changes.
  #overviewColumn(station: string, column: string): J {
    const key = K(column, station);
    if (this.#cache.has(key)) return this.#cache.get(key) ?? undefined;
    const text = this.#columnText(station, column);
    if (text !== undefined) {
      work.overviewParts++;
      work.overviewPartChars += text.length;
    }
    const v = text === undefined ? undefined : frozen(JSON.parse(text));
    this.#cache.set(key, v ?? null);
    return v;
  }

  /// Column `column` of a station's part as the database holds it; where it holds none (it could not keep the parts,
  /// a database a newer core wrote, or a core from before the column keeps the parts now by its own triggers: a web
  /// page still open from before), made of the overview by SQLite as it is read.
  #columnText(station: string, column: string): string | undefined {
    const kept = this.#columns.has(column) ? this.sql.all(`SELECT ${column} FROM station_part WHERE address = ?`, [station])[0] : undefined;
    if (typeof kept?.[0] === "string") return kept[0];
    const of = PART_COLUMNS.find(([c]) => c === column)![1];
    const r = this.sql.all(`SELECT ${of("st.json")} FROM station AS st WHERE st.address = ? AND st.kind = 'overview' AND json_valid(st.json)`, [station])[0];
    return typeof r?.[0] === "string" ? r[0] : undefined;
  }

  /// Whether a station's overview is held: by its key alone, its JSON not read.
  overviewHeld(station: string): boolean {
    const held = this.#cache.get(K("st", station, "overview"));
    if (held !== undefined) return held !== null;
    return this.sql.all("SELECT 1 FROM station WHERE address = ? AND kind = 'overview'", [station]).length > 0;
  }

  /// What each column of a station's part is now, as its revision says it (schema.ts partRev): -1 where it holds no text
  /// (none held, or the overview not an object), its revision where it holds one, null where nothing says (a row a core
  /// that knows nothing of them put in, or a database that keeps no parts). A few numbers: no text read.
  #partRevs(station: string): (number | null)[] {
    if (!this.#parts) return PART_COLUMNS.map(() => null);
    const r = this.sql.all(`SELECT ${PART_COLUMNS.map(([c]) => `CASE WHEN ${partRev(c)} IS NOT NULL AND ${c} IS NULL THEN -1 ELSE ${partRev(c)} END`).join(", ")} FROM station_part WHERE address = ?`, [station])[0];
    return PART_COLUMNS.map((_, i) => (r === undefined ? -1 : typeof r[i] === "number" ? r[i] : null));
  }

  /// The overview written or dropped by `write`, its part with it (the triggers): said only where a column of the part
  /// changed (its revision moved, or nothing says it did not), as `$overview-<column>` (what the chat list reads,
  /// `$overview-part`; a station's row, `$overview-row`; a chat's page, `$overview-chat`; a link to a chat,
  /// `$overview-formerly`), what the cache holds of it let go and read again as a reader asks (#overviewColumn); and
  /// where the overview is not what it was, as `$overview-fit`. What is kept beside the overview and its part
  /// (db/kept.ts: its verdict, its accounts' rows) is made again of them as they are written, a column read for it only
  /// where a value kept is to be made again.
  #overviewWritten(station: string, write: () => void): void {
    this.#write(() => {
      const before = this.#partRevs(station);
      const key = K("st", station, "overview");
      const was = this.#cache.get(key);
      const overview = this.kept.writing("station", [station]);
      const profiled = this.kept.writing("station_part", [station]);
      write();
      const after = this.#partRevs(station);
      for (const [i, [column]] of PART_COLUMNS.entries()) {
        if (before[i] !== null && after[i] !== null && before[i] === after[i]) continue;
        // (its profiles read one by one, not parsed whole: each read again of them)
        if (column === "profiles") for (const id of this.#profilesRead.get(station) ?? []) this.#cache.delete(K("profile", station, id));
        else this.#cache.delete(K(column, station));
        if (column === "profiled") this.kept.wrote(profiled, () => this.#overviewColumn(station, column));
        this.#tell({ topic: `$overview-${column}`, station });
      }
      const now = this.#cache.get(key);
      if (now === was && now !== undefined) return;
      this.#tell({ topic: "$overview-fit", station });
      this.kept.wrote(overview, () => (isObject(now) ? now : undefined));
    });
  }

  /// At most `most` of a station's documents whose kind starts with `prefix`, the latest confirmed: the others go.
  boundStationDocs(station: string, prefix: string, most: number): void {
    const kinds = this.sql.all("SELECT kind FROM station WHERE address = ? AND substr(kind, 1, ?) = ? ORDER BY confirmed DESC", [station, prefix.length, prefix]);
    for (const [kind] of kinds.slice(most)) this.dropStationDoc(station, String(kind), null);
  }

  slackApp(station: string, connect: string): J {
    return this.#doc(K("slack", station, connect), "SELECT json FROM slack_app WHERE station = ? AND connect = ?", [station, connect]);
  }

  putSlackApp(station: string, connect: string, value: J, confirmed: number | null): void {
    this.#putDoc(K("slack", station, connect), value, { table: "slack_app", keys: ["station", "connect"], of: [station, connect], confirmed }, { topic: "slackApp", station, connect });
  }

  draft(station: string, chat: string): J {
    return this.#doc(K("draft", station, chat), "SELECT json FROM draft WHERE station = ? AND chat = ?", [station, chat]);
  }

  putDraft(station: string, chat: string, value: J | undefined): void {
    const topic = { topic: "draft", station, chat };
    if (value === undefined) this.#dropDoc(K("draft", station, chat), "DELETE FROM draft WHERE station = ? AND chat = ?", [station, chat], topic);
    else this.#putDoc(K("draft", station, chat), value, { table: "draft", keys: ["station", "chat"], of: [station, chat] }, topic);
  }

  workspacePref(workspace: string, key: string): J {
    return this.#doc(K("wpref", workspace, key), "SELECT json FROM workspace_pref WHERE workspace = ? AND key = ?", [workspace, key]);
  }

  putWorkspacePref(workspace: string, key: string, value: J | undefined, topic: Topic | null = null): void {
    if (value === undefined) this.#dropDoc(K("wpref", workspace, key), "DELETE FROM workspace_pref WHERE workspace = ? AND key = ?", [workspace, key], topic);
    else this.#putDoc(K("wpref", workspace, key), value, { table: "workspace_pref", keys: ["workspace", "key"], of: [workspace, key] }, topic);
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

  /// A document put (`doc`: its table, the columns of its key and their values, and when its source confirmed it where
  /// the table keeps that, null where it did not now), `around` the write where one is given (what its triggers make
  /// beside it: #overviewWritten). Whether it is the same as the one held is SQLite's to say, by a number: no document's
  /// text comes back to be compared. The same: only when it was confirmed changes. Another, or none held: it is put,
  /// kept in the cache as it is, and told.
  #putDoc(key: string, value: J, doc: Doc, topic: Topic | null, around?: (put: () => void) => void): void {
    this.#write(() => {
      const json = JSON.stringify(value);
      const where = doc.keys.map((c) => `${c} = ?`).join(" AND ");
      const same = this.sql.all(`SELECT json = ? FROM ${doc.table} WHERE ${where}`, [json, ...doc.of])[0]?.[0];
      if (same === 1) {
        if (doc.confirmed !== undefined && doc.confirmed !== null) this.#run(`UPDATE ${doc.table} SET confirmed = ? WHERE ${where}`, [doc.confirmed, ...doc.of]);
        return;
      }
      const columns = [...doc.keys, "json", ...(doc.confirmed === undefined ? [] : ["confirmed"])];
      const values = [...doc.of, json, ...(doc.confirmed === undefined ? [] : [doc.confirmed])];
      const put = () => {
        this.#run(
          doc.confirmed === undefined
            ? `INSERT OR REPLACE INTO ${doc.table} (${columns.join(", ")}) VALUES (${columns.map(() => "?").join(", ")})`
            : `INSERT INTO ${doc.table} (${columns.join(", ")}) VALUES (${columns.map(() => "?").join(", ")}) ON CONFLICT (${doc.keys.join(", ")}) DO UPDATE SET json = excluded.json, confirmed = coalesce(excluded.confirmed, confirmed)`,
          values,
        );
        this.#cache.set(key, frozen(JSON.parse(json)));
        if (topic) this.#tell(topic);
      };
      if (around === undefined) put();
      else around(put);
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
      case "archived": {
        // (each kept row as it is kept: account.ts #byKey)
        const a = kind === "archived" ? 1 : 0;
        const found = this.sql.all("SELECT station, id, ord FROM chat WHERE station = ? AND archived = ?", [station, a]);
        const made = this.#chatRowsFound(found, a, () => this.sql.all("SELECT station, id, json, unread FROM chat WHERE station = ? AND archived = ?", [station, a]));
        found.forEach((r, i) => {
          if (made[i] !== undefined) c.set(String(r[1]), made[i], [r[2] as number]);
        });
        break;
      }
      case "sessions": {
        const found = this.sql.all("SELECT key, ord FROM session WHERE station = ? AND listed = 1", [station]);
        const key = (r: SqlRow) => K("sum", station, String(r[0]));
        const made = this.#byKey(
          found.map((r) => [key(r), r[0]]),
          () => this.sql.all("SELECT key, summary FROM session WHERE station = ? AND listed = 1", [station]),
          (keys) => this.sql.all("SELECT s.key, s.summary FROM json_each(?) AS k CROSS JOIN session AS s WHERE s.station = ? AND s.key = k.value", [keys, station]),
          key,
          (r) => this.#cached(key(r), r[1]),
        );
        found.forEach((r, i) => c.set(String(r[0]), made[i], [r[1] as number]));
        break;
      }
      case "threads": {
        const found = this.sql.all("SELECT id, sort_at, created_at FROM thread WHERE station = ? AND listed = 1", [station]);
        const made = this.#threadsFound(station, found, () => this.sql.all("SELECT id, json, last, read, unread FROM thread WHERE station = ? AND listed = 1", [station]));
        found.forEach((r, i) => {
          if (made[i] !== undefined) c.set(String(r[0]), made[i], [r[1] as number, r[2] as number, r[0] as number]);
        });
        break;
      }
      case "jobs": {
        const found = this.sql.all("SELECT id, ord FROM job WHERE station = ? AND open = 1", [station]);
        const key = (r: SqlRow) => K("jobitem", station, String(r[0]));
        const made = this.#byKey(
          found.map((r) => [key(r), r[0]]),
          () => this.sql.all("SELECT id, json, chat FROM job WHERE station = ? AND open = 1", [station]),
          (keys) => this.sql.all("SELECT j.id, j.json, j.chat FROM json_each(?) AS k CROSS JOIN job AS j WHERE j.station = ? AND j.id = k.value", [keys, station]),
          key,
          (r) => this.#jobItem(station, String(r[0]), r[1], r[2]),
        );
        found.forEach((r, i) => {
          if (made[i] !== undefined) c.set(String(r[0]), made[i], [r[1] as number]);
        });
        break;
      }
    }
    this.#lists.set(key, c);
    return c;
  }

  /// The rows a query found by their keys alone (`found`: each one's key in the cache, and what `byKey` finds it again
  /// by), in its order, undefined where none was read: each one kept by its key as it is kept, read from the database
  /// only where none is. A list asked for again, a workspace's mark made again, read every row's JSON to take the one
  /// kept (5.6 ms in Hermes for a mark of 123 rows, every one kept, 2026-11-11). The JSON of those not kept is read by one
  /// more query: where they are most of what was found (more than half: a list read cold), `all`, the query again with
  /// its JSON, so that a cold read costs one query more of keys alone; otherwise `byKey`, given their keys as one JSON
  /// array (json_each: one statement whatever their number, never near SQLite's variable limit, and one statement kept
  /// prepared), each found by its primary key. Each row read: `keyOf` its key, `make` it into the row (which keeps it).
  #byKey(found: [string, unknown][], all: () => SqlRow[], byKey: (keys: string) => SqlRow[], keyOf: (r: SqlRow) => string, make: (r: SqlRow) => J): (J | undefined)[] {
    const out: (J | undefined)[] = found.map(([key]) => this.#cache.get(key) ?? undefined);
    let missing = 0;
    for (const v of out) if (v === undefined) missing++;
    if (missing === 0) return out;
    const whole = missing * 2 > found.length;
    const rows = whole ? all() : byKey(JSON.stringify(found.flatMap(([, at], i) => (out[i] === undefined ? [at] : []))));
    const read = new Map<string, SqlRow>();
    for (const r of rows) read.set(keyOf(r), r);
    for (let i = 0; i < found.length; i++) {
      if (out[i] !== undefined) {
        // (read again with the rest, for nothing)
        if (whole && read.has(found[i][0])) work.rowJson++;
        continue;
      }
      const r = read.get(found[i][0]);
      if (r !== undefined) out[i] = make(r);
    }
    return out;
  }

  /// Chat rows a query found (`found`: station, id), `archived` or not, in its order (account.ts #byKey); `all` the
  /// query again with their JSON (station, id, json, unread).
  #chatRowsFound(found: SqlRow[], archived: number, all: () => SqlRow[]): (J | undefined)[] {
    const key = (r: SqlRow) => K("chat", String(r[0]), archived, String(r[1]));
    return this.#byKey(
      found.map((r) => [key(r), [r[0], r[1]]]),
      all,
      (keys) => this.sql.all("SELECT c.station, c.id, c.json, c.unread FROM json_each(?) AS k CROSS JOIN chat AS c WHERE c.station = json_extract(k.value, '$[0]') AND c.archived = ? AND c.id = json_extract(k.value, '$[1]')", [keys, archived]),
      key,
      (r) => this.#chatRow(String(r[0]), archived, String(r[1]), r[2], r[3]),
    );
  }

  #loadedList(station: string, kind: ListKind): Collection | undefined {
    return this.#lists.get(K(kind, station));
  }

  /// A row parsed once and kept by its key until written. `json` as read from the database (counted: work.rowJson, read
  /// for nothing where the row is kept), else as written here (`read` false).
  #cached(key: string, json: SqlValue, make?: (parsed: J) => J, read = true): J {
    if (read && typeof json === "string") work.rowJson++;
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
    work.chatRowsSerialised++;
    const rest = { ...row };
    const unread = typeof rest.unread === "boolean" ? (rest.unread ? 1 : 0) : null;
    delete rest.unread;
    let running = 0;
    for (const a of Array.isArray(row.agents) ? row.agents : []) if (get(a, "process") === "running") running = 1;
    // (the columns the declared reads are told by as chat-reads.ts rowColumns says them: one rule)
    const c = rowColumns(row);
    return {
      json: JSON.stringify(rest),
      unread,
      thread: c.thread,
      session: c.session,
      clientKey: c.clientKey,
      lastActive: c.lastActive,
      pinnedAt: c.pinnedAt,
      mine: c.mine ? 1 : 0,
      running,
      tone: this.#derive.tone(row),
      asks: this.#derive.asks(row) ? 1 : 0,
      state: this.#derive.state(row),
      watched: this.#derive.watched(row) ? 1 : 0,
    };
  }

  /// (`c`: its columns, where they were made already)
  #putChatRow(station: string, archived: number, id: string, row: J, ord: number, before: J | undefined, ordBefore: number | undefined, c: ChatCols = this.#chatCols(row)): void {
    // (asked before the record is put: its triggers take the row kept beside it)
    const beside = this.kept.writing("chat", [station, id]);
    this.#run(PUT_CHAT, [station, id, archived, ord, c.thread, c.session, c.clientKey, c.lastActive, c.pinnedAt, c.unread, c.mine, c.running, c.tone, c.asks, c.state, c.watched, c.json]);
    this.#chatsHeld.get(K(archived ? "archived" : "chats", station))?.set(id, { row, ord });
    const kept = frozen(JSON.parse(JSON.stringify(row)));
    this.#cache.set(K("chat", station, archived, id), kept);
    // (its row kept beside it went with it, by the triggers: made again of it, where it is listed)
    this.kept.wrote(beside, () => (archived ? undefined : kept));
    this.#loadedList(station, archived ? "archived" : "chats")?.set(id, kept, [ord]);
    this.#tellChatRead(station, archived, id, before, kept, before === undefined ? undefined : ordBefore, ord);
    if (!archived) this.#tellChat(station, id, before, kept);
    this.#tell({ topic: archived ? "archivedRows" : "chatRows", station });
  }

  /// A row whose record is as written, at another place alone (a list whose places are of each row, setChats `places`,
  /// given where its rows were placed otherwise, once): its place written by its key, the record not put again, nothing
  /// serialised or parsed (schema.ts chatTriggers are not of `ord`; the row kept beside it goes, as at any update of its
  /// record, db/kept.ts, made again as it is read). The reads that order by place told of it (chatKeys before and after),
  /// the list held here put in its order. Not the list's revision (rowsRev, setChats `changed`): what waits on it is a
  /// change made here waiting for the station's rows to say it (views/local.ts `settle`), which no place says.
  #placeChatRow(station: string, archived: number, id: string, row: J, record: J, ord: number, ordBefore: number): void {
    const list = archived ? "archived" : "chats";
    this.#run("UPDATE chat SET ord = ? WHERE station = ? AND archived = ? AND id = ?", [ord, station, archived, id]);
    this.#chatsHeld.get(K(list, station))?.set(id, { row, ord });
    const loaded = this.#loadedList(station, list);
    if (loaded !== undefined) {
      loaded.set(id, loaded.items.get(id) ?? record, [ord]);
      this.#tell({ topic: TOPIC_OF[list], station });
    }
    this.#tellChatRead(station, archived, id, record, record, ordBefore, ord);
  }

  /// A station's chat list as read: rows that changed are written, those gone deleted, the list read. What was written
  /// before is held (#chatsHeld): only what must be compared is read. `places`: each row's place, where the list says
  /// them of each row (one its station makes, rows-made.ts `sharedPlace`), else they are found from those written
  /// (placesFor). A list written in other places takes those given at this write, once.
  setChats(station: string, archived: boolean, rows: J[], confirmed: number | null, places?: readonly number[]): void {
    this.#write(() => {
      const a = archived ? 1 : 0;
      const list = archived ? "archived" : "chats";
      const items: [string, J][] = [];
      const given: number[] = [];
      const seen = new Set<string>();
      glanced.chatRowsWalked += rows.length;
      rows.forEach((row, i) => {
        const id = idText(get(row, "id"));
        if (id === null || seen.has(id)) return;
        seen.add(id);
        items.push([id, row]);
        if (places !== undefined) given.push(places[i]!);
      });
      let held = this.#chatsHeld.get(K(list, station));
      // (the row written, frozen: it cannot have changed since)
      const asHeld = (id: string, row: J) => held?.get(id)?.row === row && Object.isFrozen(row);
      // What is written of those to compare and those gone (id, ord, json, unread): by their keys where they are few,
      // else the list.
      const stored = new Map<string, SqlRow>();
      const unsure = held === undefined ? [] : [...items.filter(([id, row]) => !asHeld(id, row)).map(([id]) => id), ...[...held.keys()].filter((id) => !seen.has(id))];
      if (held === undefined || unsure.length > CHATS_COMPARED_BY_KEY) {
        for (const r of this.sql.all("SELECT id, ord, json, unread FROM chat WHERE station = ? AND archived = ?", [station, a])) stored.set(String(r[0]), r);
        const was = held;
        held = new Map([...stored].map(([id, r]) => [id, { row: was?.get(id)?.row ?? null, ord: r[1] as number }]));
        this.#chatsHeld.set(K(list, station), held);
      } else if (unsure.length > 0) {
        for (const r of this.sql.all("SELECT c.id, c.ord, c.json, c.unread FROM json_each(?) AS k CROSS JOIN chat AS c WHERE c.station = ? AND c.archived = ? AND c.id = k.value", [JSON.stringify(unsure), station, a])) stored.set(String(r[0]), r);
      }
      const was = held;
      const at = places !== undefined ? given : placesFor(items.map(([id]) => was.get(id)?.ord ?? null));
      // (a record as written: read just now, else the row given again, written as it is)
      const before = (id: string, row: J): J => {
        const r = stored.get(id);
        if (r !== undefined) return this.#chatRow(station, a, id, r[2], r[3]);
        const kept = this.#cache.get(K("chat", station, a, id));
        return kept !== undefined && kept !== null ? kept : frozen(JSON.parse(JSON.stringify(row)));
      };
      let changed = false;
      items.forEach(([id, row], i) => {
        const h = was.get(id);
        if (h !== undefined && asHeld(id, row)) {
          if (h.ord === at[i]) {
            glanced.chatRowsSame++;
            return;
          }
          // (moved alone)
          return this.#placeChatRow(station, a, id, row, before(id, row), at[i]!, h.ord);
        }
        const c = this.#chatCols(row);
        const r = stored.get(id);
        if (h !== undefined && r !== undefined && r[2] === c.json && r[3] === c.unread) {
          if (h.ord !== at[i]) return this.#placeChatRow(station, a, id, row, before(id, row), at[i]!, h.ord);
          h.row = row;
          return;
        }
        changed = true;
        this.#putChatRow(station, a, id, row, at[i]!, h === undefined ? undefined : before(id, row), h?.ord, c);
      });
      // (those gone, in the list's order)
      const gone = [...was].filter(([id]) => !seen.has(id)).sort(([, x], [, y]) => x.ord - y.ord);
      for (const [id, h] of gone) {
        changed = true;
        this.#deleteChatRow(station, a, id, before(id, h.row), h.ord);
      }
      this.#markListed(station, list, confirmed, changed);
    });
  }

  #deleteChatRow(station: string, archived: number, id: string, before: J | undefined, ordBefore: number): void {
    const kept = this.kept.writing("chat", [station, id]);
    this.#run("DELETE FROM chat WHERE station = ? AND archived = ? AND id = ?", [station, archived, id]);
    this.#chatsHeld.get(K(archived ? "archived" : "chats", station))?.delete(id);
    this.#cache.delete(K("chat", station, archived, id));
    this.kept.wrote(kept, () => undefined);
    this.#loadedList(station, archived ? "archived" : "chats")?.delete(id);
    this.#tellChatRead(station, archived, id, before, undefined, ordBefore, undefined);
    if (!archived) this.#tellChat(station, id, before, undefined);
    this.#tell({ topic: archived ? "archivedRows" : "chatRows", station });
  }

  /// A sidebar row as an event has it: at `place` where its list says each row's (setChats `places`), else in place, or
  /// last when new. Nothing while the station's rows were never read. The row written before (the same object, frozen) at
  /// the same place writes nothing and reads nothing; another is read by its key to be compared.
  putChat(station: string, row: J, place?: number): void {
    const id = idText(get(row, "id"));
    if (id === null || !this.listed(station, "chats")) return;
    this.#write(() => {
      const h = this.#chatsHeld.get(K("chats", station))?.get(id);
      if (h !== undefined && h.row === row && Object.isFrozen(row)) {
        if (place === undefined || h.ord === place) return;
        // (as written, at another place: that alone)
        const kept = this.#cache.get(K("chat", station, 0, id));
        return this.#placeChatRow(station, 0, id, row, kept !== undefined && kept !== null ? kept : frozen(JSON.parse(JSON.stringify(row))), place, h.ord);
      }
      const r = this.sql.all("SELECT ord, json, unread FROM chat WHERE station = ? AND archived = 0 AND id = ?", [station, id])[0];
      const c = this.#chatCols(row);
      if (r && r[1] === c.json && r[2] === c.unread) {
        if (place !== undefined && r[0] !== place) return this.#placeChatRow(station, 0, id, row, this.#chatRow(station, 0, id, r[1], r[2]), place, r[0] as number);
        if (h !== undefined) h.row = row;
        return;
      }
      const ord = place ?? (r ? (r[0] as number) : ((this.sql.all("SELECT max(ord) FROM chat WHERE station = ? AND archived = 0", [station])[0]?.[0] as number | null) ?? -1) + 1);
      this.#putChatRow(station, 0, id, row, ord, r ? this.#chatRow(station, 0, id, r[1], r[2]) : undefined, r ? (r[0] as number) : undefined, c);
      this.#bumpRev(station, "chats");
    });
  }

  dropChat(station: string, id: string): void {
    // (not in the list as it was last written: nothing to drop, nothing read)
    const held = this.#chatsHeld.get(K("chats", station));
    if (held !== undefined && !held.has(id)) return;
    this.#write(() => {
      // (its record from the cache where it is held: only its place read)
      const kept = this.#cache.get(K("chat", station, 0, id));
      if (kept !== undefined && kept !== null) {
        const r = this.sql.all("SELECT ord FROM chat WHERE station = ? AND archived = 0 AND id = ?", [station, id])[0];
        if (!r) return;
        this.#deleteChatRow(station, 0, id, kept, r[0] as number);
        this.#bumpRev(station, "chats");
        return;
      }
      const r = this.sql.all("SELECT json, unread, ord FROM chat WHERE station = ? AND archived = 0 AND id = ?", [station, id])[0];
      if (!r) return;
      this.#deleteChatRow(station, 0, id, this.#chatRow(station, 0, id, r[0], r[1]), r[2] as number);
      this.#bumpRev(station, "chats");
    });
  }

  /// What a declared read finds (chat-reads.ts), each row with its record where `wants` says so (every row by default):
  /// read by its key, from the cache where it is held, its JSON read only where it is not.
  chatFound<P>(read: ChatRead<P>, p: P, wants: (cols: SqlRow) => boolean = () => true): ChatFound[] {
    const out = foundOf(this.chatCounted(read, p));
    if (read.records) this.chatRecords(out.filter((f) => wants(f.cols)));
    return out;
  }

  /// The records of rows a read found (`record` of each, undefined where it is gone): read by their keys, from the cache
  /// where held, their JSON read only where not.
  chatRecords(found: ChatFound[]): void {
    for (const archived of [0, 1]) {
      const of = found.filter((f) => (f.archived ? 1 : 0) === archived);
      if (of.length === 0) continue;
      const made = this.#records(of.map((f) => [f.station, f.id]), archived);
      of.forEach((f, i) => (f.record = made[i]));
    }
  }

  /// What a declared read of counts or columns answers (chat-reads.ts), as SQLite gives it.
  chatCounted<P>(read: ChatRead<P>, p: P): SqlRow[] {
    return this.sql.all(read.sql, read.params(p));
  }

  /// Chat records by their keys (station, id), `archived` or not, in that order (undefined: none): each kept by its key
  /// as it is kept, the JSON of those not kept read by one statement (json_each), by their primary keys.
  #records(found: [string, string][], archived: number): (J | undefined)[] {
    const out: (J | undefined)[] = found.map(([station, id]) => this.#cache.get(K("chat", station, archived, id)) ?? undefined);
    const missing = found.filter((_, i) => out[i] === undefined);
    if (missing.length === 0) return out;
    const read = new Map<string, SqlRow>();
    for (const r of this.sql.all("SELECT c.station, c.id, c.json, c.unread FROM json_each(?) AS k CROSS JOIN chat AS c WHERE c.station = json_extract(k.value, '$[0]') AND c.archived = ? AND c.id = json_extract(k.value, '$[1]')", [JSON.stringify(missing), archived])) {
      read.set(K(String(r[0]), String(r[1])), r);
    }
    found.forEach(([station, id], i) => {
      if (out[i] !== undefined) return;
      const r = read.get(K(station, id));
      if (r !== undefined) out[i] = this.#chatRow(station, archived, id, r[2], r[3]);
    });
    return out;
  }

  /// A sidebar row by its id where it is held in memory (read or written this run): nothing read.
  heldChat(station: string, id: string): J {
    const kept = this.#cache.get(K("chat", station, 0, id));
    return kept === null ? undefined : kept;
  }

  /// A sidebar row by its id.
  chat(station: string, id: string): J {
    // (a row kept by its key is the one in the database: written, it is kept anew; gone, let go)
    const kept = this.#cache.get(K("chat", station, 0, id));
    if (kept !== undefined && kept !== null) return kept;
    return this.chatFound(CHAT_READS.row, { station, id })[0]?.record;
  }

  /// The row of a chat a link names (its row's id, or its agent's session), listed or archived, and whether archived: a
  /// row read, not the station's lists.
  chatNamed(station: string, id: string): { row: J; archived: boolean } | undefined {
    const found = this.chatFound(CHAT_READS.named, { station, id })[0];
    return found?.record === undefined ? undefined : { row: found.record, archived: found.archived };
  }

  /// The sidebar row of a thread.
  chatOfThread(station: string, thread: number): J {
    return this.chatFound(CHAT_READS.thread, { station, thread })[0]?.record;
  }

  /// The sidebar rows a thread's or an agent's session's changes touch: the thread's chat's; the rows the session is
  /// among the agents of (its own, and the chats it takes part in).
  chatsOf(station: string, of: { thread: number } | { session: string }): J[] {
    const rows = "thread" in of
      ? this.sql.all("SELECT id, json, unread FROM chat WHERE station = ? AND archived = 0 AND thread = ?", [station, of.thread])
      : this.sql.all("SELECT id, json, unread FROM chat WHERE station = ? AND archived = 0 AND (session = ? OR instr(json, ?) > 0)", [station, of.session, JSON.stringify(of.session)]);
    const out = rows.map((r) => this.#chatRow(station, 0, String(r[0]), r[1], r[2]));
    return "thread" in of ? out : out.filter((row) => Array.isArray(get(row, "agents")) && (get(row, "agents") as J[]).some((a) => get(a, "key") === of.session));
  }

  /// The sidebar row of an agent's session.
  chatOfSession(station: string, session: string): J {
    return this.chatFound(CHAT_READS.session, { station, session })[0]?.record;
  }

  /// The sidebar row an agent's session is among the agents of (`chat_agent`), the first in the list's order.
  chatOfAgent(station: string, session: string): J {
    return this.chatFound(CHAT_READS.agent, { station, session })[0]?.record;
  }

  /// The sidebar row asked for here under a client key (views/local.ts).
  chatOfClientKey(station: string, key: string): J {
    return this.chatFound(CHAT_READS.client, { station, key })[0]?.record;
  }

  /// The rows of these stations a list shows first: the pinned, then the latest active, `limit` of them; `mine`, of the
  /// viewer's own alone (a list of them, whose first rows are not the first of all: its column, not a row read to see).
  chatHead(stations: string[], limit: number, mine = false): [string, J][] {
    if (stations.length === 0) return [];
    const marks = stations.map(() => "?").join(", ");
    const where = `archived = 0 AND station IN (${marks})${mine ? " AND mine = 1" : ""} ORDER BY pinned_at DESC, last_active DESC LIMIT ?`;
    const found = this.sql.all(`SELECT station, id FROM chat WHERE ${where}`, [...stations, limit]);
    const made = this.#chatRowsFound(found, 0, () => this.sql.all(`SELECT station, id, json, unread FROM chat WHERE ${where}`, [...stations, limit]));
    return found.flatMap((r, i): [string, J][] => (made[i] === undefined ? [] : [[String(r[0]), made[i]]]));
  }

  /// The rows of these stations a list shows first (chatHead's), each its row kept beside it under its station's key in
  /// force (`keys`), else its record: a record's JSON is read only where no row is kept under that key.
  listHead(stations: string[], limit: number, mine: boolean, keys: Map<string, string>): HeadRow[] {
    if (stations.length === 0) return [];
    const d = KEPT.listRow;
    if (!this.kept.keeps(d)) return this.chatHead(stations, limit, mine).map(([station, record]) => ({ station, id: String(get(record, "id")), pinnedAt: num(get(record, "pinned")), row: null, record }));
    const marks = stations.map(() => "?").join(", ");
    const where = `c.archived = 0 AND c.station IN (${marks})${mine ? " AND c.mine = 1" : ""} ORDER BY c.pinned_at DESC, c.last_active DESC LIMIT ?`;
    // (a row kept under another key not read: joined by the one in force)
    const j = this.kept.joined(d, "r", ["c.station", "c.id"], `json_extract(?, '$."' || c.station || '"')`);
    const found = this.sql.all(`SELECT c.station, c.id, c.pinned_at, ${j.columns} FROM chat AS c ${j.join} WHERE ${where}`, [JSON.stringify(Object.fromEntries(keys)), ...stations, limit]);
    const out: HeadRow[] = [];
    const missing: SqlRow[] = [];
    for (const r of found) {
      const station = String(r[0]);
      const id = String(r[1]);
      const key = keys.get(station);
      const row = key === undefined ? undefined : this.kept.taken(d, [station, id], key, r.slice(3));
      if (row === undefined) missing.push(r);
      out.push({ station, id, pinnedAt: typeof r[2] === "number" ? r[2] : null, row: row ?? null, record: undefined });
    }
    if (missing.length > 0) {
      // (theirs alone, by their keys, whatever their number: #byKey's `all` is these too)
      const theirs = () => this.sql.all("SELECT c.station, c.id, c.json, c.unread FROM json_each(?) AS k CROSS JOIN chat AS c WHERE c.station = json_extract(k.value, '$[0]') AND c.archived = 0 AND c.id = json_extract(k.value, '$[1]')", [JSON.stringify(missing.map((r) => [r[0], r[1]]))]);
      const records = this.#chatRowsFound(missing.map((r) => [r[0], r[1]]), 0, theirs);
      const by = new Map(missing.map((r, i) => [K(String(r[0]), String(r[1])), records[i]]));
      for (const h of out) if (h.row === null) h.record = by.get(K(h.station, h.id));
    }
    return out.filter((h) => h.row !== null || h.record !== undefined);
  }

  /// How many sidebar rows these stations have.
  chatCount(stations: string[]): number {
    if (stations.length === 0) return 0;
    return (this.sql.all(`SELECT count(*) FROM chat WHERE archived = 0 AND station IN (${stations.map(() => "?").join(", ")})`, stations)[0]?.[0] as number) ?? 0;
  }

  /// The rows of these stations that ask something of their person or are unread (views/marks.ts).
  marked(stations: string[]): [string, J][] {
    if (stations.length === 0) return [];
    return this.chatFound(CHAT_READS.marked, { stations }).flatMap((f): [string, J][] => (f.record === undefined ? [] : [[f.station, f.record]]));
  }

  /// The viewer read a thread up to `n`: its rows unread no more where that covers their last message.
  #readRows(station: string, thread: number, n: number): void {
    for (const r of this.sql.all("SELECT id, ord, json, unread FROM chat WHERE station = ? AND archived = 0 AND thread = ? AND unread = 1", [station, thread])) {
      const id = String(r[0]);
      const before = this.#chatRow(station, 0, id, r[2], r[3]);
      const last = u64(get(get(before, "last"), "seq"));
      if (last !== null && n < last) continue;
      const after = { ...before, unread: false };
      this.#putChatRow(station, 0, id, after, r[1] as number, before, r[1] as number);
      this.#bumpRev(station, "chats");
    }
  }

  // ── sessions ──

  #sessionCols(summary: J): SqlValue[] {
    return [num(get(summary, "lastActiveAt")), str(get(summary, "process")), str(get(summary, "connect")), num(get(summary, "archivedAt")), u64(get(summary, "turns"))];
  }

  /// A session's summary.
  summary(station: string, key: string): J {
    const kept = this.#cache.get(K("sum", station, key));
    if (kept !== undefined && kept !== null) return kept;
    const r = this.sql.all("SELECT summary FROM session WHERE station = ? AND key = ?", [station, key])[0];
    return r && r[0] !== null ? this.#cached(K("sum", station, key), r[0]) : undefined;
  }

  /// A session's summary if its station lists it (it is not archived).
  listedSummary(station: string, key: string): J {
    const r = this.sql.all("SELECT summary FROM session WHERE station = ? AND key = ? AND listed = 1", [station, key])[0];
    return r && r[0] !== null ? this.#cached(K("sum", station, key), r[0]) : undefined;
  }

  /// A station's sessions as read: summaries written where they changed, those no longer listed unlisted. `changed`: the
  /// keys of those its station said changed from the ones held (sync.ts #whole), the rest as written: then only those
  /// are compared with what is written, the others' places alone read.
  setSessions(station: string, list: J[], confirmed: number | null, changed?: ReadonlySet<string>): void {
    this.#write(() => {
      const was = new Map<string, SqlRow>();
      // Only listed sessions need comparing with the list. Unlisted ones keep their details but cannot be removed from
      // this list, and the details of listed ones are not needed to compare their summaries either.
      const read = changed === undefined ? "SELECT key, ord, summary, listed FROM session WHERE station = ? AND listed = 1" : "SELECT key, ord FROM session WHERE station = ? AND listed = 1";
      for (const r of this.sql.all(read, [station])) was.set(String(r[0]), r);
      const items: [string, J][] = [];
      const seen = new Set<string>();
      for (const s of list) {
        const key = str(get(s, "key"));
        if (key === null || seen.has(key)) continue;
        seen.add(key);
        items.push([key, s]);
      }
      const places = placesFor(items.map(([key]) => (was.has(key) ? (was.get(key)![1] as number) : null)));
      let wrote = false;
      items.forEach(([key, s], i) => {
        const r = was.get(key);
        // (as written, where it stays: none of it to compare)
        if (r && r[1] === places[i] && changed !== undefined && !changed.has(key)) return;
        const json = JSON.stringify(s);
        const summary = changed === undefined ? r?.[2] : r && changed.has(key) ? this.sql.all("SELECT summary FROM session WHERE station = ? AND key = ?", [station, key])[0]?.[0] : undefined;
        if (r && r[1] === places[i] && summary === json) return;
        wrote = true;
        this.#putSummary(station, key, s, json, 1, places[i]);
      });
      for (const [key] of was) {
        if (seen.has(key)) continue;
        wrote = true;
        this.#run("UPDATE session SET listed = 0 WHERE station = ? AND key = ?", [station, key]);
        this.#loadedList(station, "sessions")?.delete(key);
        this.#tell({ topic: "sessions", station });
        this.#tellSession(station, key);
      }
      this.#markListed(station, "sessions", confirmed, wrote);
    });
  }

  #putSummary(station: string, key: string, summary: J, json: string, listed: number, ord: number): void {
    const cols = this.#sessionCols(summary);
    // A newly listed session may already be held unlisted. Update the summary in place without replacing its detail.
    this.#run(
      `INSERT INTO session (station, key, listed, ord, last_active, process, connect, archived_at, turns, summary)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT (station, key) DO UPDATE SET listed = excluded.listed, ord = excluded.ord,
       last_active = excluded.last_active, process = excluded.process, connect = excluded.connect,
       archived_at = excluded.archived_at, turns = excluded.turns, summary = excluded.summary`,
      [station, key, listed, ord, ...cols, json],
    );
    const kept = frozen(JSON.parse(json));
    this.#cache.set(K("sum", station, key), kept);
    const list = this.#loadedList(station, "sessions");
    if (listed) list?.set(key, kept, [ord]);
    else list?.delete(key);
    this.#tell({ topic: "sessions", station });
    this.#tellSession(station, key);
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
      again = detail === undefined || (!counted(summary) && !sameTurns(get(detail, "turns"), summary));
      // One more turn, or the last one gone on, as the summary says it: put in place, not all its turns read again.
      const placed = again && detail !== undefined && placeTurn(detail, summary);
      if (placed) {
        again = false;
        this.#run("UPDATE session SET detail = ? WHERE station = ? AND key = ?", [JSON.stringify(detail), station, key]);
        this.#tellSession(station, key);
      }
      if (r && r[1] === json && r[2] === listed) return;
      // Its detail shows it as it is now too (`detail`).
      this.#putSummary(station, key, summary, json, listed, ord);
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

  /// A session's detail as a topic shows it: its turns and jobs as read, its summary as the station last said it (in its
  /// list or an event: one summary, so a field a station says since is in both; read with the detail alone, the detail's),
  /// and its threads as their rows are now: those it read as its own and those whose members it is among.
  detail(station: string, key: string): J {
    const ck = K("detail", station, key);
    const hit = this.#cache.get(ck);
    if (hit !== undefined) return hit ?? undefined;
    const r = this.sql.all("SELECT detail, summary FROM session WHERE station = ? AND key = ?", [station, key])[0];
    if (!r || r[0] === null) {
      this.#cache.set(ck, null);
      return undefined;
    }
    const detail = parse(r[0]);
    if (r[1] !== null) detail.session = parse(r[1]);
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
    const where = `station = ? AND (id IN (SELECT thread FROM thread_member WHERE station = ? AND session = ?)${ids.length > 0 ? ` OR id IN (${ids.map(() => "?").join(", ")})` : ""}) ORDER BY sort_at DESC, created_at DESC, id DESC`;
    const found = this.sql.all(`SELECT id FROM thread WHERE ${where}`, [station, station, key, ...ids]);
    const made = this.#threadsFound(station, found, () => this.sql.all(`SELECT id, json, last, read, unread FROM thread WHERE ${where}`, [station, station, key, ...ids]));
    return made.filter((t) => t !== undefined);
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

  /// The listed session keys, in order, so a sweep can inspect their details in bounded groups.
  sessionKeys(station: string): string[] {
    return this.sql.all("SELECT key FROM session WHERE station = ? AND listed = 1 ORDER BY ord", [station]).map((r) => String(r[0]));
  }

  /// A station's sessions with whether each one's detail is to be read again (none held, or its turns changed).
  /// Only the last turn matters; earlier turns and the rest of each detail stay in the database.
  sessionsToRead(station: string, keys?: readonly string[]): [string, boolean][] {
    if (keys?.length === 0) return [];
    const only = keys === undefined ? "" : ` AND key IN (${keys.map(() => "?").join(", ")})`;
    return this.sql.all(
      `SELECT key, summary, detail IS NOT NULL,
         CASE WHEN json_type(detail, '$.turns') = 'array' THEN json_array_length(detail, '$.turns') ELSE 0 END,
         CASE WHEN json_type(detail, '$.turns') = 'array' AND json_array_length(detail, '$.turns') > 0
              THEN json_quote(json_extract(detail, '$.turns[#-1]')) END
       FROM session WHERE station = ? AND listed = 1${only} ORDER BY ord`,
      [station, ...(keys ?? [])],
    ).map((r) => {
      const summary = parse(r[1]);
      return [String(r[0]), r[2] !== 1 || (!counted(summary) && !sameTurnEnd(Number(r[3]), r[4] === null ? null : parse(r[4]), summary))];
    });
  }

  // ── threads ──

  /// `read` false: `json` as written here, not read.
  #threadRow(station: string, id: number, json: SqlValue, last: SqlValue, read: SqlValue, unread: SqlValue, fromDb = true): J {
    return this.#cached(K("thread", station, id), json, (t) => {
      if (last !== null) t.last = last;
      if (read !== null) t.read = read;
      if (unread !== null) t.unread = unread;
      return t;
    }, fromDb);
  }

  /// A station's thread rows a query found (`found`: their ids first), in its order (account.ts #byKey); `all` the
  /// query again with their JSON (id, json, last, read, unread). A thread's `last`, `read` and `unread`, columns only,
  /// are in its row as kept: a change of them lets the row go (#threadChanged).
  #threadsFound(station: string, found: SqlRow[], all: () => SqlRow[]): (J | undefined)[] {
    const key = (r: SqlRow) => K("thread", station, r[0] as number);
    return this.#byKey(
      found.map((r) => [key(r), r[0]]),
      all,
      (keys) => this.sql.all("SELECT t.id, t.json, t.last, t.read, t.unread FROM json_each(?) AS k CROSS JOIN thread AS t WHERE t.station = ? AND t.id = k.value", [keys, station]),
      key,
      (r) => this.#threadRow(station, r[0] as number, r[1], r[2], r[3], r[4]),
    );
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
    const r = this.sql.all(`SELECT id FROM thread WHERE station = ? AND listed = 1 AND first_member = ? AND surface IN (${OWN_IN}) ORDER BY sort_at DESC, created_at DESC, id DESC LIMIT 1`, [station, session])[0];
    return r ? (r[0] as number) : null;
  }

  /// A station's listed threads' ids.
  threadIds(station: string): number[] {
    return this.sql.all("SELECT id FROM thread WHERE station = ? AND listed = 1 ORDER BY sort_at DESC, created_at DESC, id DESC", [station]).map((r) => r[0] as number);
  }

  /// A station's listed threads whose summary goes further than the entries held of them (none held, or fewer at the
  /// end): what the device has yet to bring of each one's latest.
  threadsBehind(station: string): number[] {
    return this.sql.all("SELECT id FROM thread WHERE station = ? AND listed = 1 AND last > COALESCE((SELECT max(n) FROM entry WHERE entry.station = thread.station AND entry.thread = thread.id), 0)", [station]).map((r) => r[0] as number);
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
    const row = this.#threadRow(station, id, c.json, c.last, c.read, c.unread, false);
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

  /// A station's threads as read. `changed`: the ids of those its station said changed from the ones held (sync.ts
  /// #whole), the rest as written: only those are compared with what is written.
  setThreads(station: string, list: J[], confirmed: number | null, changed?: ReadonlySet<string>): void {
    this.#write(() => {
      const seen = new Set<number>();
      for (const view of list) {
        const id = u64(get(view, "id"));
        if (id === null || seen.has(id)) continue;
        seen.add(id);
        if (changed === undefined || changed.has(String(id))) this.#putThreadRow(station, view, 1);
      }
      let wrote = false;
      for (const r of this.sql.all("SELECT id FROM thread WHERE station = ? AND listed = 1", [station])) {
        const id = r[0] as number;
        if (seen.has(id)) continue;
        wrote = true;
        const before = this.thread(station, id);
        this.#run("UPDATE thread SET listed = 0 WHERE station = ? AND id = ?", [station, id]);
        this.#loadedList(station, "threads")?.delete(String(id));
        this.#tell({ topic: "threads", station });
        this.#tell({ topic: "thread", station, thread: id });
        for (const member of membersOf(before)) this.#tellSession(station, member);
      }
      this.#markListed(station, "threads", confirmed, wrote);
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

  #jobItem(station: string, id: string, json: SqlValue, chat: SqlValue, fromDb = true): J {
    return this.#cached(K("jobitem", station, id), json, (job) => {
      if (chat !== null && chat !== undefined) job.chat = parse(chat);
      return job;
    }, fromDb);
  }

  /// A job as it is now.
  job(station: string, id: string): J {
    const kept = this.#cache.get(K("job", station, id));
    if (kept !== undefined && kept !== null) return kept;
    const r = this.sql.all("SELECT json FROM job WHERE station = ? AND id = ?", [station, id])[0];
    return r ? this.#cached(K("job", station, id), r[0]) : undefined;
  }

  /// A station's open jobs as read (GET /jobs), each with its chat.
  setJobs(station: string, list: J[], confirmed: number | null): void {
    this.#write(() => {
      const was = new Map<string, SqlRow>();
      // Only open jobs can be retained or need closing. An incoming closed job is written anew either way.
      for (const r of this.sql.all("SELECT id, ord, json, chat, open FROM job WHERE station = ? AND open = 1", [station])) was.set(String(r[0]), r);
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
    if (open) list?.set(id, this.#jobItem(station, id, json, chat, false), [ord]);
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

  /// The messages of these stations whose latest text has every one of `terms` (case aside), newest first.
  findSaid(stations: string[], terms: string[], limit: number): { station: string; thread: number; seq: number; at: number | null; text: string }[] {
    if (!this.#said || stations.length === 0 || terms.length === 0) return [];
    const where = [`s.station IN (${stations.map(() => "?").join(", ")})`, ...terms.map(() => "s.text LIKE ? ESCAPE '\\'")];
    const params: SqlValue[] = [...stations, ...terms.map(like), limit];
    return this.sql
      .all(`SELECT s.station, s.thread, s.seq, s.at, s.text FROM said s WHERE ${where.join(" AND ")} ORDER BY s.at IS NULL, s.at DESC, s.seq DESC LIMIT ?`, params)
      .map((r) => ({ station: String(r[0]), thread: Number(r[1]), seq: Number(r[2]), at: typeof r[3] === "number" ? r[3] : null, text: String(r[4]) }));
  }

  /// The messages of one thread whose latest text has every one of `terms` (case aside), oldest first, with their
  /// words (a chat's own find: all of them, as `findSaid` looks).
  findInThread(station: string, thread: number, terms: string[]): { seq: number; text: string }[] {
    if (!this.#said || terms.length === 0) return [];
    const where = ["s.station = ?", "s.thread = ?", ...terms.map(() => "s.text LIKE ? ESCAPE '\\'")];
    const params: SqlValue[] = [station, thread, ...terms.map(like)];
    return this.sql.all(`SELECT s.seq, s.text FROM said s WHERE ${where.join(" AND ")} ORDER BY s.seq`, params).map((r) => ({ seq: Number(r[0]), text: String(r[1]) }));
  }

  // ── what is kept within the device's room ──

  /// How much of the database is in use (its pages less the free ones), in bytes.
  used(): number {
    const n = (q: string) => Number(this.sql.all(q)[0]?.[0] ?? 0);
    return (n("PRAGMA page_count") - n("PRAGMA freelist_count")) * n("PRAGMA page_size");
  }

  /// Whether a log's items were let go for room (and not brought back since).
  evicted(kind: LogTable, station: string, id: string): boolean {
    return this.#evicted.has(K(kind, station, id));
  }

  /// A log's chat opened here: the most recently opened, and kept again (its items brought back by the sync). Answers
  /// whether they had been let go.
  opened(kind: LogTable, station: string, id: string, at: number): boolean {
    const was = this.#evicted.delete(K(kind, station, id));
    this.#write(() => {
      this.sql.run("INSERT INTO log_use (kind, station, id, opened, evicted) VALUES (?, ?, ?, ?, 0) ON CONFLICT (kind, station, id) DO UPDATE SET opened = excluded.opened, evicted = 0", [kind, station, id, at]);
    });
    return was;
  }

  /// When a log was last opened here (`opened`), null when it never was.
  lastOpened(kind: LogTable, station: string, id: string): number | null {
    const v = this.sql.all("SELECT opened FROM log_use WHERE kind = ? AND station = ? AND id = ?", [kind, station, id])[0]?.[0];
    return typeof v === "number" ? v : null;
  }

  /// The agents' transcripts held, least recently used first: by when their history was last opened here or their agent
  /// last active, whichever is later. (A chat's messages are never let go: they are the chat, and small.)
  transcriptsByUse(limit: number): { station: string; id: string }[] {
    // Seek to each next session in the transcript primary key; DISTINCT would scan every item of every transcript.
    return this.sql
      .all(
        `WITH RECURSIVE x(station, session) AS (
           SELECT station, session FROM (SELECT station, session FROM transcript ORDER BY station, session LIMIT 1)
           UNION ALL
           SELECT t.station, t.session FROM x JOIN transcript t ON (t.station, t.session, t.i) = (
             SELECT z.station, z.session, z.i FROM transcript z WHERE z.station = x.station AND z.session > x.session
             ORDER BY z.station, z.session, z.i LIMIT 1
           )
           UNION ALL
           SELECT t.station, t.session FROM x JOIN transcript t ON (t.station, t.session, t.i) = (
             SELECT z.station, z.session, z.i FROM transcript z WHERE z.station > x.station
             ORDER BY z.station, z.session, z.i LIMIT 1
           ) WHERE NOT EXISTS (SELECT 1 FROM transcript z WHERE z.station = x.station AND z.session > x.session)
         )
         SELECT x.station, x.session FROM x
         LEFT JOIN log_use u ON u.kind = 'transcript' AND u.station = x.station AND u.id = x.session
         LEFT JOIN session s ON s.station = x.station AND s.key = x.session
         ORDER BY max(coalesce(u.opened, 0), coalesce(s.last_active, 0)), x.station, x.session LIMIT ?`,
        [limit],
      )
      .map((r) => ({ station: String(r[0]), id: String(r[1]) }));
  }

  /// A transcript's items let go for room: they are read again when its history is opened. Its session stays.
  evict(station: string, session: string): void {
    this.#evicted.add(K("transcript", station, session));
    this.#write(() => {
      this.#logCache.clear();
      if (this.sql.run("DELETE FROM transcript WHERE station = ? AND session = ?", [station, session]) > 0) this.#tellLog("transcript", station, session);
      this.sql.run("INSERT INTO log_use (kind, station, id, evicted) VALUES ('transcript', ?, ?, 1) ON CONFLICT (kind, station, id) DO UPDATE SET evicted = 1", [station, session]);
    });
  }

  // ── a thread's entries and a session's transcript ──

  /// The numbers of a log's items held, in order.
  logNumbers(table: LogTable, station: string, id: string): readonly number[] {
    const cacheKey = K(table, station, id);
    const hit = this.#logIndices.get(cacheKey);
    if (hit) return hit.numbers;
    const [key, col] = logColumns(table);
    const numbers = this.sql.all(`SELECT ${col} FROM ${table} WHERE station = ? AND ${key} = ? ORDER BY ${col}`, [station, logId(table, id)]).map((r) => r[0] as number);
    work.logNumbers += numbers.length;
    this.#logIndices.set(cacheKey, new LogIndex(numbers));
    return numbers;
  }

  /// A log's items `from ..= to` held, by number.
  logRange(table: LogTable, station: string, id: string, from: number, to: number): Map<number, J> {
    const [key, col] = logColumns(table);
    const out = new Map<number, J>();
    // Which numbers it holds there: from its index where one is kept, else asked of SQLite (the numbers alone, not their
    // JSON), so a window read again is read from what is parsed (a chat's window read from SQLite on each of its new
    // messages was much of what one cost, 2026-11-08) and a long log's every number is not read to open it.
    const index = this.#logIndices.get(K(table, station, id));
    const numbers = index ? index.numbers : this.sql.all(`SELECT ${col} FROM ${table} WHERE station = ? AND ${key} = ? AND ${col} BETWEEN ? AND ? ORDER BY ${col}`, [station, logId(table, id), from, to]).map((r) => r[0] as number);
    if (!index) work.logNumbers += numbers.length;
    const first = index ? lowerBound(numbers, from) : 0;
    const end = index ? upperBound(numbers, to) : numbers.length;
    const missing: number[] = [];
    for (let i = first; i < end; i++) {
      const n = numbers[i]!;
      const item = this.#logCache.get(K(table, station, id, n));
      if (item === undefined) missing.push(n);
      else out.set(n, item);
    }
    // A hot window is already parsed: do not copy its JSON strings out of SQLite on every view update; what is not (a
    // new item, one let go from the cache) read alone.
    if (missing.length === 0) return out;
    if (missing.length <= LOG_READ_ALONE) {
      const rows = this.sql.all(`SELECT ${col}, json FROM ${table} WHERE station = ? AND ${key} = ? AND ${col} IN (${missing.map(() => "?").join(", ")})`, [station, logId(table, id), ...missing]);
      work.logRows += rows.length;
      const read = new Map(rows.map((r) => [r[0] as number, this.#logItem(table, station, id, r[0] as number, r[1])]));
      // (in order of number, as the range reads: those read alone put in their places)
      const ordered = new Map<number, J>();
      for (let i = first; i < end; i++) {
        const n = numbers[i]!;
        const item = out.get(n) ?? read.get(n);
        if (item !== undefined) ordered.set(n, item);
      }
      return ordered;
    }
    out.clear();
    const rows = this.sql.all(`SELECT ${col}, json FROM ${table} WHERE station = ? AND ${key} = ? AND ${col} BETWEEN ? AND ? ORDER BY ${col}`, [station, logId(table, id), from, to]);
    work.logRows += rows.length;
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
  logSpan(table: LogTable, station: string, id: string): { min: number; max: number; count: number } | null {
    const cacheKey = K(table, station, id);
    const index = this.#logIndices.get(cacheKey);
    if (index) return index.span;
    const kept = this.#logSpans.get(cacheKey);
    if (kept !== undefined) return kept === null ? null : { ...kept };
    const [key, col] = logColumns(table);
    const r = this.sql.all(`SELECT min(${col}), max(${col}), count(*) FROM ${table} WHERE station = ? AND ${key} = ?`, [station, logId(table, id)])[0];
    const span = r && r[2] !== 0 ? { min: r[0] as number, max: r[1] as number, count: r[2] as number } : null;
    work.logSpans += span?.count ?? 0;
    this.#logSpans.set(cacheKey, span);
    return span === null ? null : { ...span };
  }

  /// How many of `from ..= to` a log holds.
  logCount(table: LogTable, station: string, id: string, from: number, to: number): number {
    const index = this.#logIndices.get(K(table, station, id));
    if (index) return index.count(from, to);
    const [key, col] = logColumns(table);
    return (this.sql.all(`SELECT count(*) FROM ${table} WHERE station = ? AND ${key} = ? AND ${col} BETWEEN ? AND ?`, [station, logId(table, id), from, to])[0]?.[0] as number) ?? 0;
  }

  /// Items into a log, by number; those it holds the same are not written. `cutAfter`: nothing past it is kept.
  /// `keep`: what is held stays (an import: what the sync brought is newer).
  putLog(table: LogTable, station: string, id: string, items: [number, J][], cutAfter: number | null = null, keep = false): void {
    if (items.length === 0 && cutAfter === null) return;
    this.#write(() => {
      const cacheKey = K(table, station, id);
      const index = this.#logIndices.get(cacheKey);
      const span = this.#logSpans.get(cacheKey);
      // A failed SQL write must never leave a cached index (or span) of a different transaction state.
      this.#logIndices.delete(cacheKey);
      this.#logSpans.delete(cacheKey);
      const added: number[] = [];
      const [key, col] = logColumns(table);
      const k: SqlValue = logId(table, id);
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
          if (was === undefined) added.push(n);
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
      // (what was put, unless something was cut too)
      if (changed) this.#tellLog(table, station, id, cutAfter === null ? written.map(([n]) => n) : null);
      if (index) {
        index.put(written.map(([n]) => n), cutAfter);
        this.#logIndices.set(cacheKey, index);
      }
      // (only what was put in: a cut is read again)
      if (span !== undefined && cutAfter === null) {
        let next = span === null ? null : { ...span };
        for (const n of new Set(added)) next = next === null ? { min: n, max: n, count: 1 } : { min: Math.min(next.min, n), max: Math.max(next.max, n), count: next.count + 1 };
        this.#logSpans.set(cacheKey, next);
      }
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

  /// The Slack people a station's agents were given messages from, by Slack id: their names as last heard (a bot is said
  /// as its mention, `<@U…>`: its id out of it). Kept until `slack_said` changes.
  #slackNames = new Map<string, [string, string][]>();
  slackNames(station: string): [string, string][] {
    if (!this.#hasSlackSaid()) return [];
    let names = this.#slackNames.get(station);
    if (names === undefined) {
      const rows = this.sql.all("SELECT user, who FROM slack_said WHERE station = ? AND out = 0 AND user IS NOT NULL AND who IS NOT NULL AND who != '' ORDER BY at", [station]);
      names = [...new Map(rows.map((r) => [String(r[0]).replace(/^<@(.+)>$/, "$1"), String(r[1])])).entries()];
      this.#slackNames.set(station, names);
    }
    return names;
  }

  #forgetEntries(station: string, thread: number): void {
    if (this.sql.run("DELETE FROM entry WHERE station = ? AND thread = ?", [station, thread]) > 0) this.#tellLog("entry", station, String(thread));
    if (this.sql.run("DELETE FROM letter WHERE station = ? AND thread = ?", [station, thread]) > 0) this.#tellLog("letter", station, String(thread));
  }

  /// A log known no more.
  forgetLog(table: LogTable, station: string, id: string): void {
    this.#write(() => {
      if (table === "entry") this.#forgetEntries(station, Number(id));
      else if (table === "letter") {
        if (this.sql.run("DELETE FROM letter WHERE station = ? AND thread = ?", [station, Number(id)]) > 0) this.#tellLog("letter", station, id);
      } else {
        if (this.sql.run("DELETE FROM transcript WHERE station = ? AND session = ?", [station, id]) > 0) this.#tellLog("transcript", station, id);
        if (this.#hasSlackSaid() && this.sql.run("DELETE FROM slack_said WHERE station = ? AND session = ?", [station, id]) > 0) this.#tellLog("slack", station, id);
      }
    });
  }

  // ── what chats show small (thumbnails, posters) ──

  /// Whether `file_kept` is there (made as the first file is kept).
  #filesKept = false;

  /// What a chat shows small, as kept here (`kind`: thumb, poster): its type and bytes (base64), noted as shown `at`;
  /// null when it is not kept.
  keptFile(station: string, session: string, name: string, kind: string, at: number): { type: string; bytes: string } | null {
    if (!this.#filesKept) return null;
    let r: SqlRow | undefined;
    try {
      r = this.sql.all("SELECT type, used, bytes FROM file_kept WHERE station = ? AND session = ? AND name = ? AND kind = ?", [station, session, name, kind])[0];
    } catch {
      // Not made after all (the write that made it could not be kept): made again with the next one kept.
      this.#filesKept = false;
      return null;
    }
    if (r === undefined) return null;
    if (at - Number(r[1]) >= FILE_SHOWN_EVERY) this.#write(() => this.sql.run("UPDATE file_kept SET used = ? WHERE station = ? AND session = ? AND name = ? AND kind = ?", [at, station, session, name, kind]));
    return { type: String(r[0]), bytes: String(r[2]) };
  }

  /// Whether what a chat shows small is kept here (`kind`: thumb, poster), not noting it as shown.
  hasKeptFile(station: string, session: string, name: string, kind: string): boolean {
    if (!this.#filesKept) return false;
    try {
      return this.sql.all("SELECT 1 FROM file_kept WHERE station = ? AND session = ? AND name = ? AND kind = ?", [station, session, name, kind]).length > 0;
    } catch {
      return false;
    }
  }

  /// Keeps what a chat shows small as its station sent it; past FILES_KEPT, the least lately shown go.
  keepFile(station: string, session: string, name: string, kind: string, type: string, bytes: string, at: number): void {
    if (this.readOnly || bytes.length > FILE_KEPT_MOST) return;
    this.#write(() => {
      if (!this.#filesKept) {
        ensureFilesKept(this.sql);
        this.#filesKept = true;
      }
      this.sql.run("INSERT OR REPLACE INTO file_kept (station, session, name, kind, type, size, used, bytes) VALUES (?, ?, ?, ?, ?, ?, ?, ?)", [station, session, name, kind, type, bytes.length, at, bytes]);
      let total = Number(this.sql.all("SELECT coalesce(sum(size), 0) FROM file_kept")[0]?.[0] ?? 0);
      if (total <= FILES_KEPT) return;
      for (const r of this.sql.all("SELECT station, session, name, kind, size FROM file_kept ORDER BY used")) {
        if (total <= FILES_KEPT * FILES_KEPT_TO) break;
        this.sql.run("DELETE FROM file_kept WHERE station = ? AND session = ? AND name = ? AND kind = ?", [r[0], r[1], r[2], r[3]]);
        total -= Number(r[4] ?? 0);
      }
    });
  }

  // ── the trees of what agents said (markdown.ts) ──

  /// Whether `md_kept` is there (made as the first tree is kept), and what its trees take (counted at the first kept).
  #mdKept = false;
  #mdSize: number | null = null;

  /// Whether the tree of the text keyed `key` is kept here.
  hasMd(station: string, key: string): boolean {
    if (!this.#mdKept) return false;
    try {
      return this.sql.all("SELECT 1 FROM md_kept WHERE station = ? AND key = ?", [station, key]).length > 0;
    } catch {
      this.#mdKept = false;
      return false;
    }
  }

  /// Owners with cached trees from an older reading, in bounded pages, so updating them does not hold up the app.
  oldMdOwners(reading: number, after: { station: string; of: string }): { station: string; of: string }[] {
    if (!this.#mdKept) return [];
    return this.sql.all(
      `SELECT station, of FROM md_kept
       WHERE (station > ? OR (station = ? AND of > ?))
         AND CAST(substr(key, 1, instr(key, '.') - 1) AS INTEGER) < ?
       GROUP BY station, of ORDER BY station, of LIMIT 20`,
      [after.station, after.station, after.of, reading],
    ).map((r) => ({ station: String(r[0]), of: String(r[1]) }));
  }

  /// Stop looking through an owner's sources once none of its older trees remain.
  hasOldMd(station: string, of: string, reading: number): boolean {
    if (!this.#mdKept) return false;
    return this.sql.all("SELECT 1 FROM md_kept WHERE station = ? AND of = ? AND CAST(substr(key, 1, instr(key, '.') - 1) AS INTEGER) < ? LIMIT 1", [station, of, reading]).length > 0;
  }

  /// A bounded page of a cached tree owner's source entries, newest first. Sequence numbers need not be contiguous.
  mdSourcePage(station: string, of: string, before: number): { n: number; json: unknown }[] {
    const thread = of.startsWith("t:") ? Number(of.slice(2)) : null;
    const session = of.startsWith("s:") ? of.slice(2) : null;
    if (thread !== null && Number.isSafeInteger(thread)) {
      return this.sql.all("SELECT n, json FROM entry WHERE station = ? AND thread = ? AND n < ? ORDER BY n DESC LIMIT 50", [station, thread, before]).map((r) => ({ n: Number(r[0]), json: parse(r[1]) }));
    }
    if (session !== null) {
      return this.sql.all("SELECT i, json FROM transcript WHERE station = ? AND session = ? AND i < ? ORDER BY i DESC LIMIT 50", [station, session, before]).map((r) => ({ n: Number(r[0]), json: parse(r[1]) }));
    }
    return [];
  }

  /// The tree of the text keyed `key` (its JSON), noted as shown `at`; null when it is not kept.
  keptMd(station: string, key: string, at: number): string | null {
    if (!this.#mdKept) return null;
    let r: SqlRow | undefined;
    try {
      r = this.sql.all("SELECT used, json FROM md_kept WHERE station = ? AND key = ?", [station, key])[0];
    } catch {
      // Not made after all (the write that made it could not be kept): made again with the next one kept.
      this.#mdKept = false;
      return null;
    }
    if (r === undefined) return null;
    if (at - Number(r[0]) >= MD_SHOWN_EVERY) this.#write(() => this.sql.run("UPDATE md_kept SET used = ? WHERE station = ? AND key = ?", [at, station, key]));
    return String(r[1]);
  }

  /// Keeps the tree of the text keyed `key`, read for `of` (a chat, `t:<thread>`; an agent, `s:<session>`); past
  /// MD_KEPT, the least lately shown go.
  keepMd(station: string, of: string, key: string, json: string, at: number, replaces?: string): void {
    if (this.readOnly) return;
    this.#write(() => {
      if (!this.#mdKept) {
        ensureMdKept(this.sql);
        this.#mdKept = true;
      }
      // (what all of them take, counted once and then kept count of: a tree is kept with each reply read)
      this.#mdSize ??= Number(this.sql.all("SELECT coalesce(sum(size), 0) FROM md_kept")[0]?.[0] ?? 0);
      const was = Number(this.sql.all("SELECT size FROM md_kept WHERE station = ? AND key = ?", [station, key])[0]?.[0] ?? 0);
      if (replaces !== undefined && replaces !== key) {
        const old = Number(this.sql.all("SELECT size FROM md_kept WHERE station = ? AND key = ?", [station, replaces])[0]?.[0] ?? 0);
        this.sql.run("DELETE FROM md_kept WHERE station = ? AND key = ?", [station, replaces]);
        this.#mdSize -= old;
      }
      this.sql.run("INSERT OR REPLACE INTO md_kept (station, key, of, size, used, json) VALUES (?, ?, ?, ?, ?, ?)", [station, key, of, json.length, at, json]);
      this.#mdSize += json.length - was;
      if (this.#mdSize <= MD_KEPT) return;
      for (const r of this.sql.all("SELECT station, key, size FROM md_kept ORDER BY used")) {
        if (this.#mdSize <= MD_KEPT * MD_KEPT_TO) break;
        this.sql.run("DELETE FROM md_kept WHERE station = ? AND key = ?", [r[0], r[1]]);
        this.#mdSize -= Number(r[2] ?? 0);
      }
    });
  }

  /// The chats a station's agents last spoke in, the latest first, from `since` on: at most `most`.
  recentThreads(station: string, since: number, most: number): number[] {
    return this.sql.all("SELECT thread FROM chat WHERE station = ? AND archived = 0 AND thread IS NOT NULL AND last_active >= ? ORDER BY last_active DESC LIMIT ?", [station, since, most]).map((r) => r[0] as number);
  }

  /// What this database keeps of each chat (a thread): its entries, its sessions' transcripts and what it shows small, in
  /// characters of their JSON (near enough their bytes), with its sessions and its row as held (`view`, null when none
  /// is); what a session has counted with its first thread. For the device's page of what it keeps (`cache.usage`).
  cacheUsage(): { station: string; thread: number; view: J | null; sessions: string[]; bytes: number }[] {
    const out = new Map<string, { station: string; thread: number; view: J | null; sessions: string[]; bytes: number }>();
    const of = (station: string, thread: number) => {
      const k = `${station}\0${thread}`;
      let row = out.get(k);
      if (row === undefined) out.set(k, (row = { station, thread, view: null, sessions: [], bytes: 0 }));
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
    if (this.#filesKept) {
      for (const r of this.sql.all("SELECT station, session, sum(size) FROM file_kept GROUP BY station, session")) {
        const thread = firstThread.get(`${r[0] as string}\0${r[1] as string}`);
        if (thread !== undefined) of(r[0] as string, thread).bytes += Number(r[2] ?? 0);
      }
    }
    if (this.#mdKept) {
      for (const r of this.sql.all("SELECT station, of, sum(size) FROM md_kept GROUP BY station, of")) {
        const [station, at] = [r[0] as string, r[1] as string];
        const thread = at.startsWith("t:") ? Number(at.slice(2)) : firstThread.get(`${station}\0${at.slice(2)}`);
        if (thread !== undefined && Number.isInteger(thread)) of(station, thread).bytes += Number(r[2] ?? 0);
      }
    }
    for (const row of out.values()) {
      const json = this.sql.all("SELECT json FROM thread WHERE station = ? AND id = ?", [row.station, row.thread])[0]?.[0];
      if (json !== undefined) row.view = parse(json) as J;
    }
    return [...out.values()].filter((r) => r.bytes > 0);
  }

  /// Forgets what is kept of a chat: its entries, its sessions' transcripts and what it shows small (read again from its
  /// station when it is opened). What waits to be sent, drafts and the chat's row stay.
  forgetChat(station: string, thread: number): void {
    this.#write(() => {
      const sessions = this.sql.all("SELECT session FROM thread_member WHERE station = ? AND thread = ?", [station, thread]).map((r) => r[0] as string);
      this.#logCache.clear();
      this.#forgetEntries(station, thread);
      for (const session of sessions) if (this.sql.run("DELETE FROM transcript WHERE station = ? AND session = ?", [station, session]) > 0) this.#tellLog("transcript", station, session);
      if (this.#filesKept) for (const session of sessions) this.sql.run("DELETE FROM file_kept WHERE station = ? AND session = ?", [station, session]);
      if (this.#mdKept) {
        for (const of of [`t:${thread}`, ...sessions.map((s) => `s:${s}`)]) this.sql.run("DELETE FROM md_kept WHERE station = ? AND of = ?", [station, of]);
        this.#mdSize = null;
      }
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
      for (const [table, column] of [["station", "address"], ["slack_app", "station"], ["list", "station"], ["chat", "station"], ["session", "station"], ["thread", "station"], ["thread_member", "station"], ["entry", "station"], ["letter", "station"], ["transcript", "station"], ["job", "station"], ["outbox", "station"], ["pending", "station"], ["first", "station"], ["changing", "station"], ["draft", "station"]]) {
        this.sql.run(`DELETE FROM ${table} WHERE ${column} = ?`, [station]);
      }
      if (this.sql.all("SELECT 1 FROM sqlite_master WHERE name = 'log_use'").length > 0) this.sql.run("DELETE FROM log_use WHERE station = ?", [station]);
      if (this.#hasSlackSaid()) {
        const sessions = this.sql.all("SELECT DISTINCT session FROM slack_said WHERE station = ?", [station]);
        if (this.sql.run("DELETE FROM slack_said WHERE station = ?", [station]) > 0) {
          for (const [session] of sessions) this.#tellLog("slack", station, String(session));
        }
      }
      this.#slackNames.delete(station);
      if (this.#filesKept) this.sql.run("DELETE FROM file_kept WHERE station = ?", [station]);
      if (this.#mdKept) {
        this.sql.run("DELETE FROM md_kept WHERE station = ?", [station]);
        this.#mdSize = null;
      }
      for (const key of [...this.#evicted]) if (key.split("\u0001")[1] === station) this.#evicted.delete(key);
      this.kept.forgetStation(station);
      this.#cache.clear();
      this.#logPutsForgotten();
      this.#logCache.clear();
      this.#logIndices.clear();
      this.#logSpans.clear();
      for (const key of [...this.#lists.keys()]) if (key.endsWith(`\u0001${station}`)) this.#lists.delete(key);
      for (const list of ["chats", "archived"] as const) this.#chatsHeld.delete(K(list, station));
      this.#tell({ topic: "$station-reset", station });
      for (const topic of ["overview", "stationUsage", "chatRows", "archivedRows", "sessions", "threads", "jobs"]) this.#tell({ topic, station });
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

/// A session detail's turns brought to what its summary says, where that is one more turn or the last one gone on (the
/// summary's last turn, with its id); whether they were. A station from before names no last turn: they are read again.
export function placeTurn(detail: J, summary: unknown): boolean {
  const list = Array.isArray(detail?.turns) ? (detail.turns as unknown[]) : null;
  const last = get(summary, "lastTurn");
  const n = get(summary, "turns");
  if (list === null || !isObject(last) || typeof last.id !== "string" || typeof n !== "number") return false;
  if (n === list.length + 1 && !list.some((t) => get(t, "id") === last.id)) list.push(last);
  else if (n === list.length && list.length > 0 && get(list[list.length - 1], "id") === last.id) list[list.length - 1] = last;
  else return false;
  return true;
}

/// Whether a session's summary says what is shown of its turns (how many, how long they ran: `turns`, `workMs`, none for
/// one with turns from before that was kept, which shows how many alone), so
/// that its detail, read once, needs no reading again as they start and end: a detail listed every turn for that, read
/// again after each one, many of one session in 25 s on a station (2026-11-03). A station from before says none.
export function counted(summary: unknown): boolean {
  if (!isObject(summary) || !("workMs" in summary)) return false;
  return (typeof summary.workMs === "number" || summary.workMs === null) && typeof summary.turns === "number";
}

/// Whether the turns a session detail lists still end as its summary says.
export function sameTurns(turns: unknown, summary: unknown): boolean {
  const list = Array.isArray(turns) ? turns : [];
  return sameTurnEnd(list.length, list.length > 0 ? list[list.length - 1] : null, summary);
}

function sameTurnEnd(length: number, record: unknown, summary: unknown): boolean {
  if (get(summary, "turns") !== length) return false;
  const lastTurn = get(summary, "lastTurn") ?? null;
  if (record === null && lastTurn === null) return true;
  if (record === null || lastTurn === null) return false;
  return ["kind", "outcome", "declared", "detail", "startedAt", "endedAt"].every((k) => equal(get(record, k), get(lastTurn, k)));
}
