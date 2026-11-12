// The reads of the `chat` table a view makes, declared once each: its statement, what bounds the work SQLite does for it
// (rows by a key, the first rows of an order through an index, counts of an index alone: held of each one's plan by
// test/chat-plans.test.ts, an index it needs made in schema.ts ensureChatColumns), the keys its answer is told by, and the
// keys a written row tells (before and after it was written). Data's accessor (`Data.chatRead`) reads by them and is
// told by them; Data.#committed tells each read what a burst wrote; nothing else reads the table to answer a view
// (scripts/whole-lists.ts refuses a view reading a station's chats whole). A new read is a declaration here.
//
// A read whose answer can change by a row coming into it or leaving it by a column it does not key by (the window as
// a row is hidden, made the viewer's, archived; a count as one is archived) is keyed by its station alone: any row of
// the station written, listed (`archived` 0) or archived as the read is of, tells it. Those keyed finer (one row by its
// id, its session, its thread, its key, an agent's session) are told by the row's own key before and after, so a row
// that leaves the key (its session another) tells the old key too.
//
// Rows a read finds come back as (station, archived, id) first, then its own columns; the records of those it shows
// are taken from the database's cache by those keys, their JSON read only where none is held (account.ts #byKey).
import type { SqlValue } from "../host.ts";

// deno-lint-ignore no-explicit-any
type J = any;

/// What a written chat row says that the reads are told by, of its record as the writer puts its columns (account.ts
/// #chatCols): before or after it was written.
export type ChatKeys = {
  station: string;
  archived: boolean;
  id: string;
  thread: number | null;
  session: string | null;
  clientKey: string | null;
  /// It asks something of its person or is unread for them (its `tone` or `asks` column).
  marked: boolean;
  /// The sessions among its agents (`chat_agent`).
  agents: readonly string[];
};

/// A read's key: its station, then what else it is found by.
export type ReadKey = readonly [station: string, ...rest: (string | number)[]];

export type ChatRead<P> = {
  /// The topic its readers are told by (Data.#readQuery), with its key.
  readonly name: string;
  /// What bounds the work SQLite does for it, held of its plan by chat-plans.test.ts: `one`, rows by a key (one, or
  /// each of a few keys given), every row of `chat` it reads found by that key through an index; `first`, the first
  /// rows of an order (LIMIT), walked in the order of an index so that the LIMIT stops the walk; `count`, counts,
  /// small aggregates or the keys of the rows marked so, made of an index alone (no row of the table read).
  readonly bound: "one" | "first" | "count";
  /// Whether what it finds are rows whose records are read with them (its first three columns: station, archived, id).
  readonly records: boolean;
  readonly sql: string;
  readonly params: (p: P) => SqlValue[];
  /// The keys an answer depends on.
  readonly keys: (p: P) => ReadKey[];
  /// The keys a written row (before or after) tells.
  readonly of: (c: ChatKeys) => ReadKey[];
};

const u64 = (v: unknown): number | null => (typeof v === "number" && Number.isInteger(v) && v >= 0 ? v : null);
const str = (v: unknown): string | null => (typeof v === "string" ? v : null);
const listed = (c: ChatKeys) => !c.archived;
/// A station's rows, listed (or archived), told by the station: what reads a station's rows by their columns.
const station = (archived: boolean) => (c: ChatKeys): ReadKey[] => (c.archived === archived ? [[c.station]] : []);
/// Several stations' (`stations`, as one JSON array param: one statement whatever their number).
type Stations = { stations: string[] };
const each = (p: Stations): ReadKey[] => p.stations.map((s) => [s] as ReadKey);

/// The keys of a record as its row's columns say them (account.ts #chatCols): `marked`, as its `tone` and `asks` columns.
export function chatKeys(station: string, archived: boolean, id: string, record: J, marked: boolean): ChatKeys {
  const agents: string[] = [];
  for (const a of Array.isArray(record?.agents) ? record.agents : []) {
    const key = a !== null && typeof a === "object" && !Array.isArray(a) ? a.key : undefined;
    if (typeof key === "string") agents.push(key);
  }
  return { station, archived, id, thread: u64(record?.thread), session: str(record?.session), clientKey: str(record?.clientKey), marked, agents };
}

export const CHAT_READS = {
  /// A listed chat by its id.
  row: {
    name: "$chat-row", bound: "one", records: true,
    sql: "SELECT station, archived, id FROM chat WHERE station = ? AND archived = 0 AND id = ?",
    params: (p: { station: string; id: string }) => [p.station, p.id],
    keys: (p: { station: string; id: string }): ReadKey[] => [[p.station, p.id]],
    of: (c: ChatKeys): ReadKey[] => (listed(c) ? [[c.station, c.id]] : []),
  } satisfies ChatRead<{ station: string; id: string }>,
  /// A listed chat by its agent's session (the first in the list's order), with its title.
  session: {
    name: "$chat-session", bound: "one", records: true,
    // (`+archived`: found by its session, `chat_session`, not by walking the station's rows in their order)
    sql: "SELECT station, archived, id, title FROM chat WHERE station = ? AND +archived = 0 AND session = ? ORDER BY ord, id LIMIT 1",
    params: (p: { station: string; session: string }) => [p.station, p.session],
    keys: (p: { station: string; session: string }): ReadKey[] => [[p.station, p.session]],
    of: (c: ChatKeys): ReadKey[] => (listed(c) && c.session !== null ? [[c.station, c.session]] : []),
  } satisfies ChatRead<{ station: string; session: string }>,
  /// A listed chat by its thread.
  thread: {
    name: "$chat-thread", bound: "one", records: true,
    // (`+archived`: found by its thread, `chat_thread`, as `session` is)
    sql: "SELECT station, archived, id FROM chat WHERE station = ? AND +archived = 0 AND thread = ? ORDER BY ord, id LIMIT 1",
    params: (p: { station: string; thread: number }) => [p.station, p.thread],
    keys: (p: { station: string; thread: number }): ReadKey[] => [[p.station, p.thread]],
    of: (c: ChatKeys): ReadKey[] => (listed(c) && c.thread !== null ? [[c.station, c.thread]] : []),
  } satisfies ChatRead<{ station: string; thread: number }>,
  /// A listed chat by the key it was asked for here by (views/local.ts).
  client: {
    name: "$chat-client", bound: "one", records: true,
    // (`+archived`: found by its key, `chat_client`, as `session` is)
    sql: "SELECT station, archived, id FROM chat WHERE station = ? AND +archived = 0 AND client_key = ? LIMIT 1",
    params: (p: { station: string; key: string }) => [p.station, p.key],
    keys: (p: { station: string; key: string }): ReadKey[] => [[p.station, p.key]],
    of: (c: ChatKeys): ReadKey[] => (listed(c) && c.clientKey !== null ? [[c.station, c.clientKey]] : []),
  } satisfies ChatRead<{ station: string; key: string }>,
  /// The chat a link names (its id, else its agent's session), listed before archived, by its id before its session;
  /// with its title.
  named: {
    name: "$chat-named", bound: "one", records: true,
    // (by its id, listed or archived, through the primary key, and by its session through `chat_session`: the two found
    // apart, so that neither walks the station's rows; one found both ways is the same first either way)
    sql: `SELECT station, archived, id, title FROM (
        SELECT station, archived, id, title, ord FROM chat WHERE station = ? AND archived IN (0, 1) AND id = ?
        UNION ALL SELECT station, archived, id, title, ord FROM chat WHERE station = ? AND session = ?)
      ORDER BY archived, id IS NOT ?, ord, id LIMIT 1`,
    params: (p: { station: string; id: string }) => [p.station, p.id, p.station, p.id, p.id],
    keys: (p: { station: string; id: string }): ReadKey[] => [[p.station, p.id]],
    of: (c: ChatKeys): ReadKey[] => [[c.station, c.id], ...(c.session !== null && c.session !== c.id ? [[c.station, c.session] as ReadKey] : [])],
  } satisfies ChatRead<{ station: string; id: string }>,
  /// The listed chat an agent's session is among the agents of, the first in the list's order (`chat_agent`), with its
  /// title.
  agent: {
    name: "$chat-agent", bound: "one", records: true,
    sql: "SELECT c.station, c.archived, c.id, c.title FROM chat_agent AS a JOIN chat AS c ON c.station = a.station AND c.archived = a.archived AND c.id = a.id WHERE a.station = ? AND a.session = ? AND a.archived = 0 ORDER BY c.ord, c.id LIMIT 1",
    params: (p: { station: string; session: string }) => [p.station, p.session],
    keys: (p: { station: string; session: string }): ReadKey[] => [[p.station, p.session]],
    of: (c: ChatKeys): ReadKey[] => (listed(c) ? c.agents.map((k) => [c.station, k] as ReadKey) : []),
  } satisfies ChatRead<{ station: string; session: string }>,
  /// The chats of `stations` (listed, or archived) a thread's or a session's on its station matches (`apart`, each
  /// `station␁thread` or `station␁session`: what is changing, archived or asked here, views/local.ts), read as their
  /// lists read them: few, by their keys (a thread's through `chat_thread`, a session's through `chat_session`), in the
  /// order of `stations` and then each station's; with each one's place in its station's order (`ord`).
  overlaid: {
    name: "$chat-overlaid", bound: "one", records: true,
    sql: `SELECT c.station, c.archived, c.id, c.ord FROM chat AS c
      WHERE c.rowid IN (
          SELECT k.rowid FROM json_each(?) AS t JOIN chat AS k ON k.station = substr(t.value, 1, instr(t.value, char(1)) - 1)
            AND k.thread = CAST(substr(t.value, instr(t.value, char(1)) + 1) AS INTEGER) AND +k.archived = ?
          UNION SELECT k.rowid FROM json_each(?) AS t JOIN chat AS k ON k.station = substr(t.value, 1, instr(t.value, char(1)) - 1)
            AND k.session = substr(t.value, instr(t.value, char(1)) + 1) AND +k.archived = ?)
        AND c.station IN (SELECT value FROM json_each(?))
      ORDER BY (SELECT s.key FROM json_each(?) AS s WHERE s.value = c.station), c.ord, c.id`,
    params: (p: Overlaid) => [JSON.stringify(p.threads), p.archived ? 1 : 0, JSON.stringify(p.sessions), p.archived ? 1 : 0, JSON.stringify(p.stations), JSON.stringify(p.stations)],
    keys: each,
    of: (c: ChatKeys): ReadKey[] => [[c.station]],
  } satisfies ChatRead<Overlaid>,
  /// The first `limit` rows of the chat list over `stations`, in its order (the pinned by when, then the latest active;
  /// in a tie, by station as given, then the station's order), of those it shows by their columns (`mine`, its
  /// visibility, `watching`), but those `apart` (overlaid here: read apart, views.ts #chats); with whether a row is kept
  /// beside each under its station's key in force (`keys`: only whether, none of it read here), and its place in its
  /// station's order (`ord`). The rows and the limit are found of columns alone (the inner select), walking `chat_recent`
  /// in its order (`pinned_at DESC` puts the pinned first, NULL being the least), the station's place among `stations`
  /// and its own order sorted only among the rows tied on those (`+c.station`: not each station's rows found and sorted
  /// whole); what each found is joined to (its kept row's key, of `keys`) is worked out for those alone. Its order is by
  /// `last_active`, the list's by each row's local day first (views.ts #days): the two differ only where a zone's clock
  /// went back across midnight (a day-saving change at 24:00) between two rows, both within that hour; the list sorts
  /// what this gives by its own rule.
  window: {
    name: "$chat-window", bound: "first", records: true,
    sql: `SELECT w.station, w.archived, w.id, w.pinned_at, w.last_active, r.key IS NOT NULL AND r.key = json_extract(?, '$."' || w.station || '"'), w.ord
      FROM (SELECT c.station, c.archived, c.id, c.pinned_at, c.last_active, c.ord, (SELECT s.key FROM json_each(?) AS s WHERE s.value = c.station) AS at
        FROM chat AS c
        WHERE c.archived = 0 AND +c.station IN (SELECT value FROM json_each(?)) AND (? = 0 OR c.mine = 1) AND (? = 2 OR coalesce(c.hidden, 0) = ?) AND (? = 0 OR c.watched = 1)
          AND (c.thread IS NULL OR (c.station || char(1) || c.thread) NOT IN (SELECT value FROM json_each(?)))
          AND (c.session IS NULL OR (c.station || char(1) || c.session) NOT IN (SELECT value FROM json_each(?)))
        ORDER BY c.pinned_at DESC, c.last_active DESC, at, c.ord, c.id LIMIT ?) AS w
      LEFT JOIN chat_row AS r ON r.station = w.station AND r.id = w.id
      ORDER BY w.pinned_at DESC, w.last_active DESC, w.at, w.ord, w.id`,
    params: (p: ListWindow) => [JSON.stringify(p.keys), JSON.stringify(p.stations), JSON.stringify(p.stations), p.mine ? 1 : 0, p.hidden, p.hidden, p.watching ? 1 : 0, JSON.stringify(p.threads), JSON.stringify(p.sessions), p.limit],
    keys: each,
    of: station(false),
  } satisfies ChatRead<ListWindow>,
  /// Of the same rows (the window's but its limit), each station's count, whether one of them runs (`state`) and how many:
  /// of `chat_listed` alone.
  counts: {
    name: "$chat-window", bound: "count", records: false,
    sql: `SELECT c.station, count(*), max(c.state IS 'run'), sum(c.state IS 'run')
      FROM chat AS c
      WHERE c.archived = 0 AND c.station IN (SELECT value FROM json_each(?)) AND (? = 0 OR c.mine = 1) AND (? = 2 OR coalesce(c.hidden, 0) = ?) AND (? = 0 OR c.watched = 1)
        AND (c.thread IS NULL OR (c.station || char(1) || c.thread) NOT IN (SELECT value FROM json_each(?)))
        AND (c.session IS NULL OR (c.station || char(1) || c.session) NOT IN (SELECT value FROM json_each(?)))
      GROUP BY c.station`,
    params: (p: ListWindow) => [JSON.stringify(p.stations), p.mine ? 1 : 0, p.hidden, p.hidden, p.watching ? 1 : 0, JSON.stringify(p.threads), JSON.stringify(p.sessions)],
    keys: each,
    of: station(false),
  } satisfies ChatRead<ListWindow>,
  /// Of a station's listed chats, those whose agents run (`state`: their ids and sessions), and whether any was last
  /// active from `from` to before `to` (fleet.ts: the chats at work, the stations used today): of `chat_listed` alone.
  atWork: {
    name: "$chat-window", bound: "count", records: false,
    sql: "SELECT id, session, NULL FROM chat WHERE station = ? AND archived = 0 AND state IS 'run' UNION ALL SELECT NULL, NULL, EXISTS (SELECT 1 FROM chat WHERE station = ? AND archived = 0 AND last_active >= ? AND last_active < ?)",
    params: (p: { station: string; from: number; to: number }) => [p.station, p.station, p.from, p.to],
    keys: (p: { station: string }): ReadKey[] => [[p.station]],
    of: station(false),
  } satisfies ChatRead<{ station: string; from: number; to: number }>,
  /// The rows that ask something of their person or are unread (views/marks.ts), every one: their columns say which,
  /// and `chat_marks` holds those alone.
  marked: {
    name: "$marked", bound: "count", records: true,
    sql: "SELECT station, archived, id FROM chat WHERE archived = 0 AND station IN (SELECT value FROM json_each(?)) AND (tone IS NOT NULL OR asks = 1)",
    params: (p: Stations) => [JSON.stringify(p.stations)],
    keys: each,
    of: (c: ChatKeys): ReadKey[] => (listed(c) && c.marked ? [[c.station]] : []),
  } satisfies ChatRead<Stations>,
  /// The archived chats of `stations` marked so, the newest `limit` by when they were archived (archive.ts: in a tie, by
  /// station as given, then the station's order), with what the archive shows of each (SQLite reading it of their JSON:
  /// the rows and the limit found of columns alone, the inner select, walking `chat_archive` in its order as the window
  /// walks `chat_recent`, so that only theirs is read); but those `apart` (overlaid here, as the window's). `INDEXED BY`:
  /// the native apps' SQLite (3.50.2) walked `chat_recent` and sorted every archived row of the device whole once its
  /// parameters were bound, where the tests' (Node's) took `chat_archive`.
  archived: {
    name: "$chat-archived", bound: "first", records: false,
    sql: `SELECT c.station, c.archived, c.id, w.at, CASE json_type(c.json, '$.session') WHEN 'text' THEN json_extract(c.json, '$.session') END, CASE json_type(c.json, '$.thread') WHEN 'integer' THEN json_extract(c.json, '$.thread') END, c.title,
        CASE json_type(c.json, '$.last.text') WHEN 'text' THEN json_extract(c.json, '$.last.text') END, CASE json_type(c.json, '$.archived.by') WHEN 'text' THEN json_extract(c.json, '$.archived.by') END, json_type(c.json, '$.archived.alone') IS 'true', c.ord
      FROM (SELECT c.rowid AS r, coalesce(c.archived_at, 0) AS at, (SELECT s.key FROM json_each(?) AS s WHERE s.value = c.station) AS pos, c.ord AS ord, c.id AS id
        FROM chat AS c INDEXED BY chat_archive
        WHERE c.archived = 1 AND c.archived_mark = 1 AND +c.station IN (SELECT value FROM json_each(?))
          AND (c.thread IS NULL OR (c.station || char(1) || c.thread) NOT IN (SELECT value FROM json_each(?)))
          AND (c.session IS NULL OR (c.station || char(1) || c.session) NOT IN (SELECT value FROM json_each(?)))
        ORDER BY at DESC, pos, ord, id LIMIT ?) AS w
      JOIN chat AS c ON c.rowid = w.r
      ORDER BY w.at DESC, w.pos, w.ord, w.id`,
    params: (p: Archived) => [JSON.stringify(p.stations), JSON.stringify(p.stations), JSON.stringify(p.threads), JSON.stringify(p.sessions), p.limit],
    keys: each,
    of: station(true),
  } satisfies ChatRead<Archived>,
  /// How many those are (the archive's but its limit), by station (rows with no day); and how many of every archived
  /// chat marked so were archived on each local day from `from` on, by station (a day's number: its start `offset` ms
  /// east of UTC, in days of `day` ms; format.ts localDay): of `chat_archived_at` alone.
  archivedCount: {
    name: "$chat-archived", bound: "count", records: false,
    sql: `SELECT station, NULL, count(*) FROM chat WHERE station IN (SELECT value FROM json_each(?)) AND archived = 1 AND archived_mark = 1
        AND (thread IS NULL OR (station || char(1) || thread) NOT IN (SELECT value FROM json_each(?)))
        AND (session IS NULL OR (station || char(1) || session) NOT IN (SELECT value FROM json_each(?)))
        GROUP BY station
      UNION ALL SELECT station, CAST((archived_at + ?) / ? AS INTEGER) AS day, count(*) FROM chat WHERE station IN (SELECT value FROM json_each(?)) AND archived = 1 AND archived_mark = 1 AND archived_at >= ? GROUP BY station, day`,
    params: (p: ArchivedCount) => [JSON.stringify(p.stations), JSON.stringify(p.threads), JSON.stringify(p.sessions), p.offset, p.day, JSON.stringify(p.stations), p.from],
    keys: each,
    of: station(true),
  } satisfies ChatRead<ArchivedCount>,
} as const;

export type ListWindow = Stations & {
  /// Each station's key in force for its rows kept beside their records (views.ts listRowKey).
  keys: Record<string, string>;
  mine: boolean;
  /// 0 the visible, 1 the hidden, 2 both.
  hidden: 0 | 1 | 2;
  watching: boolean;
  limit: number;
} & Apart;

/// Rows read apart from a read by their keys on their station (`station␁thread`, `station␁session`).
type Apart = { threads: string[]; sessions: string[] };
export type Overlaid = Stations & Apart & { archived: boolean };
export type Archived = Stations & Apart & { limit: number };
export type ArchivedCount = Stations & Apart & { from: number; offset: number; day: number };
