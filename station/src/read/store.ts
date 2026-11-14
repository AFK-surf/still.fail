// The station's database as the admin API reads it (once ported from the Rust station's store.rs): the store's SQL over
// the same file, opened read-only, and the same rows.
//
// serde's reading of a stored value is kept where it shows: a list of files or quotes that does not read is none, a
// card or identity that does not parse is none.
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { wall } from "../ops/fibers.ts";
import { Refused } from "../api/request.ts";
import { retiredUsage } from "../store/usage-retire.ts";
import { findRuntimeSource, type RuntimeSource } from "../store/runtime-source.ts";
import { detailQuery, usageDetailGeneration, usageDetailReady, usageDetailScopeBySession, usageDetailSince, USAGE_DETAIL_PENDING } from "../store/usage-detail.ts";
import { compactQuery, compactScopeReady, compactUsageSince, hasCompactUsage } from "../store/usage-compact.ts";
import { type UsageChatCoverage, usageCardOutcomesComplete, usageChatStatsReady } from "../store/usage-chat-stats.ts";
import { REMOTE_RUNS_ALL, REMOTE_RUNS_OF } from "../store/remote-runs.ts";
import { hasRuntimeOrderIndex } from "../store/schema.ts";
import { CC_INDEX_VERSION, CC_SESSIONS_PENDING, CcSessionsUnavailable, ccSessionReady, indexedCcThreads } from "../store/cc-thread-index.ts";
import { CARD_POSTS_PENDING, CARD_POST_BEFORE, CARD_POST_LATEST, CARD_POST_NEXT, CARD_POST_SAMPLE, cardPostsReady } from "../store/card-post-index.ts";
import { CLOSED_CARDS_INDEXED, CLOSED_CARDS_PENDING, CLOSED_CHAT_SAMPLE, CLOSED_SAMPLE_LIMIT, CLOSED_TIME_SAMPLE,
  LEGACY_CLOSED_CARDS, closedCardsReady, hasClosedCardsTimeIndex, hasLegacyClosedCards, hasNativeClosedCards } from "../store/legacy-closed-cards.ts";
import { LEGACY_FIRST_PERSON_SINCE, LEGACY_HAS_PEOPLE_SINCE, LEGACY_PEOPLE_AFTER, PEOPLE_TIME_PENDING, PEOPLE_TIME_SAMPLE_LIMIT,
  SMALL_PEOPLE_AFTER, SMALL_PEOPLE_FIRST, SMALL_PEOPLE_HAS, hasLegacyPeopleSince, hasNativePeopleSince, peopleSinceReady } from "../store/legacy-people-since.ts";
import { SESSION_LIST_CONNECT, SESSION_LIST_PENDING, SESSION_LIST_SCOPE, SESSION_LIST_SCOPE_CONNECT, sessionListReady } from "../store/session-list-index.ts";
import { SESSION_BINDINGS_PENDING, SESSION_BINDINGS_SELECTED, sessionBindingsReady } from "../store/session-bindings-index.ts";
import { sessionUpJobsReady } from "../store/session-up-jobs.ts";
import { WORKSPACE_UP_JOBS, workspaceUpJobsReady } from "../store/workspace-up-jobs.ts";
import { JOB_NAME_FIRST_LARGE, JOB_NAME_FIRST_PENDING, JOB_NAME_FIRST_ROW, checkJobNameFirst } from "../store/job-name-first.ts";
import { SAID_BATCH_SIZE, SAID_LATEST, SAID_SCAN, SAID_STATE, saidBoundary } from "../store/said-state.ts";
import { archiveLastKey } from "../store/archive-last.ts";
import { PAGE_LETTER_KEYS, PAGE_LETTER_KEYS_AFTER, pageLetterReady } from "../store/page-letter-index.ts";
import { legacyMergedNeedsRepair, legacyMergedReadReady } from "../store/legacy-edits-build.ts";
import { boundedEditKey as readBoundedEditKey, LAST_MESSAGE_WITH_EDIT } from "../store/legacy-edits-read.ts";
import { hasLegacySaid, legacySaidPageState, legacySaidReadBoundary, legacySaidReadHead, legacySaidThreadNeedsDrain, LEGACY_HAS_UNREAD, LEGACY_SAID_SCAN, LEGACY_UNREAD } from "../store/legacy-said-build.ts";
import { hasLegacyAgent, LEGACY_ASKED_DURING } from "../store/legacy-agent-build.ts";
import { TURN_COUNT_BATCH } from "../store/turn-state.ts";
import { type UsageGroup, usageGroupOf } from "../store/usage.ts";
import * as rows from "../store/rows.ts";
import {
  type CardAnswer, type DeliveryCardState, type EntryRow, type InWorkspace, JOBS_RUNNING, LEGACY_MESSAGE_KEYS_BEFORE, LEGACY_MESSAGES_BEFORE, MESSAGE_KEYS_BEFORE, MESSAGE_PAGE_ENTRIES, MESSAGES_BEFORE, type Membership, type MessageRow, type PendingMessage,
  PEOPLE_AT, SESSION_JOBS, SESSION_OF_RUNTIME, STILLFAIL_SURFACE, type ThreadRow, I64_MAX, MANUAL, authorKind, cardOf, liveShare,
  ending, parsed, saidBefore, sees, takeChars, toChatShare, toEntry, letterEntry, letterMessage, toMembership, toMessage, toThread,
} from "../store/rows.ts";

export type Json = any;

// The rows (camelCase) and how they are read from the database are the station's own (store/rows.ts): the readers'
// leave out what is not for the pages (a session's and a job's token).
export { I64_MAX, MANUAL, STILLFAIL_SURFACE, ending, optionsCard, saidBefore, takeChars } from "../store/rows.ts";
export type { AuthorKind, CardAnswer, EntryRow, Membership, MessageRow, ThreadRow } from "../store/rows.ts";

/// Archived threads whose entries are kept decompressed, the most recently read last.

/// The readers' threads have no clock of their own: the machine's time.
export const nowMs = () => wall.now();

// ---- rows ----

/// A session as the pages are given it: without its token.
export type SessionRow = Omit<rows.SessionRow, "token">;

/// A thread for listings: who takes part, the last thing said, and how much the viewer has not read.
export type ThreadSummary = {
  thread: ThreadRow; sessions: Membership[]; last: number; lastMessage: MessageRow | null; read: number; unread: number;
  people: string[]; firstText: string | null;
  /// How many letters it has (store/rows.ts Letter), in either way.
  letters: number;
  /// Its own log of letters' last (store/schema.ts LETTERS; 0: none).
  lettersLast: number;
};

/// TurnSummary, as serde writes it (camelCase, the skipped Nones left out).
export type TurnSummary = Record<string, Json>;

export type SessionStats = { turns: number; workMs: number | null; pending: number; firstText: string | null; lastTurn: TurnSummary | null };

/// A job as the pages are given it: without its token (nor the sandbox it asked for).
export type JobRow = Omit<rows.JobRow, "token" | "size">;

function toSession(r: Json): SessionRow {
  const { token: _, ...session } = rows.toSession(r);
  return session;
}


// ---- the store ----

export type Store = {
  db: DatabaseSync;
  /// The station's data directory: stillfail.db, archive/, config.json.
  dataDir: string;
  /// People's names by email, as their credentials say them (the admin API's `deps.names`, filled as members ask).
  names: Map<string, string>;
  /// What only the hub knows, as it was when the read was asked: each session's process state (`process_state`;
  /// "cold" for one not listed) and the client keys sessions were made with (`client_key`).
  processes: Map<string, string>;
  clientKeys: Map<string, string>;
  /// An old session whose up-job lookup should be prepared after this read returns.
  prepareUpJobs: string | null;
  /// An old workspace up-job lookup should be prepared after this read returns.
  prepareWorkspaceUpJobs: boolean;
  /// This connection uses the already-published lookup on an older database.
  legacySaid: boolean;
  /// This connection uses the time lookup prepared for an older database.
  legacyAgent: boolean;
};

/// The store over an open database, with the data directory its archive is in.
export function makeStore(db: DatabaseSync, dataDir: string): Store {
  return { db, dataDir, names: new Map(), processes: new Map(), clientKeys: new Map(), prepareUpJobs: null, prepareWorkspaceUpJobs: false,
    legacySaid: hasLegacySaid(db), legacyAgent: hasLegacyAgent(db) };
}

/// A station's store: `<dataDir>/stillfail.db`, opened read-only.
export function openStore(dataDir: string): Store {
  return makeStore(new DatabaseSync(join(dataDir, "stillfail.db"), { readOnly: true, timeout: 5000 }), dataDir);
}

const one = (s: Store, sql: string, ...args: Json[]): Json | undefined => s.db.prepare(sql).get(...args);
const all = (s: Store, sql: string, ...args: Json[]): Json[] => s.db.prepare(sql).all(...args);

// ── sessions ──

export function getSession(s: Store, key: string): SessionRow | null {
  const r = one(s, "SELECT * FROM sessions WHERE key = ?", key);
  return r ? toSession(r) : null;
}

/// Each session's workspace, by the index of them (store/schema.ts sessions_ws, named: by key, SQLite took the sessions'
/// own), not from the sessions themselves.
export const SEEN_OF = "SELECT key, ws FROM sessions INDEXED BY sessions_ws";

/// Which sessions `viewer` sees: those whose chat is in their workspace (one not there: the
/// home one's). A read made for no one (null) sees every one. For a viewer, `keys` limits the work and the predicate
/// to those keys, including missing sessions (which still count as the home workspace's).
export function seenBy(s: Store, viewer: InWorkspace | null | undefined, keys?: readonly string[]): (key: string) => boolean {
  if (!viewer) return () => true;
  const wanted = keys === undefined ? null : new Set(keys);
  if (wanted?.size === 0) return () => false;
  const read = (sql: string) => (wanted === null ? all(s, sql) : all(s, `${sql} WHERE key IN (SELECT value FROM json_each(?))`, JSON.stringify([...wanted])));
  let rows: Json[];
  try {
    rows = read(SEEN_OF);
  } catch {
    // A database from before has no `ws` (every chat its home workspace's).
    rows = read("SELECT * FROM sessions");
  }
  const ws = new Map<string, string | null>(rows.map((r) => [r.key, r.ws ?? null]));
  return (key) => (wanted === null || wanted.has(key)) && sees(viewer, ws.get(key) ?? null);
}

/// Whether `viewer` sees a thread: one of its sessions is in their workspace (a thread with none: the home one's).
export function seesThread(s: Store, viewer: InWorkspace | null | undefined, thread: number): boolean {
  if (!viewer) return true;
  const members = threadSessions(s, thread);
  if (members.length === 0) return sees(viewer, null);
  return members.some((m) => {
    const row = getSession(s, m.session);
    return row !== null && sees(viewer, row.ws);
  });
}

/// Every session, most recently active first.
export function listSessions(s: Store): SessionRow[] {
  return all(s, "SELECT * FROM sessions ORDER BY last_active_at DESC").map(toSession);
}

/// Histories visible in a search. The existing index is ordered by connect, then workspace, so first seek the distinct
/// connects and then only the rows in the viewer's workspaces. The public workspace is included once even when asked
/// for as the viewer's own. Preserve the old whole-table ordering when activity times tie.
const historySessionsQuery = (columns: string) => `WITH RECURSIVE connects(connect) AS (
  VALUES ((SELECT connect FROM sessions INDEXED BY sessions_by_connect ORDER BY connect LIMIT 1))
  UNION ALL SELECT (SELECT connect FROM sessions INDEXED BY sessions_by_connect WHERE connect > c.connect ORDER BY connect LIMIT 1)
    FROM connects c WHERE c.connect IS NOT NULL
), workspaces(ws) AS (SELECT ?1 UNION SELECT '*' UNION SELECT NULL WHERE ?2)
SELECT ${columns} FROM connects c CROSS JOIN workspaces w CROSS JOIN sessions s INDEXED BY sessions_by_connect
WHERE c.connect IS NOT NULL AND s.connect = c.connect AND s.ws IS w.ws
ORDER BY s.last_active_at DESC, s.rowid ASC`;
export const HISTORY_SESSIONS = historySessionsQuery("s.*");
export function historySessions(s: Store, viewer: { workspace: string; home: boolean }): SessionRow[] {
  return all(s, HISTORY_SESSIONS, viewer.workspace, Number(viewer.home)).map(toSession);
}

export type HistorySession = Pick<SessionRow, "key" | "workspace" | "cwd" | "title">;
const HISTORY_SESSION_SNAPSHOT = historySessionsQuery("s.key, s.workspace, s.cwd, s.title");
const HISTORY_SESSION_BATCH = 128;
let historySnapshotId = 0;

/// Capture the original order and the fields a history needs, without holding a main-database snapshot during file I/O.
/// Sorting still visits every visible session. Only one bounded page of session objects is brought into JavaScript.
export function historySessionSnapshot(s: Store, viewer: { workspace: string; home: boolean }):
  Iterable<HistorySession> & { length: number; close(): void } {
  const table = `history_session_snapshot_${++historySnapshotId}`;
  try { s.db.prepare(`CREATE TEMP TABLE ${table} AS ${HISTORY_SESSION_SNAPSHOT}`).run(viewer.workspace, Number(viewer.home)); }
  catch (error) {
    // A query-only connection forbids even temporary tables. Its original read remains available.
    const code = (error as { errcode?: number }).errcode;
    if (code === undefined || (code & 255) !== 8) throw error;
    const rows = historySessions(s, viewer);
    return { length: rows.length, [Symbol.iterator]: () => rows[Symbol.iterator](), close() {} };
  }
  try {
    const length = (s.db.prepare(`SELECT COUNT(*) AS n FROM temp.${table}`).get() as { n: number }).n;
    const page = s.db.prepare(`SELECT rowid AS position, key, workspace, cwd, title FROM temp.${table}
      WHERE rowid > ? ORDER BY rowid LIMIT ${HISTORY_SESSION_BATCH}`);
    return { length,
      *[Symbol.iterator]() {
        let after = 0;
        for (;;) {
          const rows = page.all(after) as (HistorySession & { position: number })[];
          for (const row of rows) { after = row.position; yield row; }
          if (rows.length < HISTORY_SESSION_BATCH) return;
        }
      },
      close() { s.db.exec(`DROP TABLE temp.${table}`); },
    };
  } catch (error) { s.db.exec(`DROP TABLE temp.${table}`); throw error; }
}

/// The session list's active or archived rows: do not bring the other kind out of the database just to discard it.
/// The old whole-table order put equal timestamps in rowid order; retain that when using either partial index.
export function listedSessions(s: Store, connect: string | null, archived: boolean, viewer: InWorkspace | null): SessionRow[] {
  if (viewer === null && connect === null) {
    const where = archived ? "archived_at IS NOT NULL" : "archived_at IS NULL";
    const sql = `SELECT * FROM sessions INDEXED BY ${archived ? "sessions_put_away" : "sessions_live"} WHERE ${where} ORDER BY last_active_at DESC, rowid ASC`;
    return all(s, sql).map(toSession);
  }
  if (!sessionListReady(s.db)) throw new Error(SESSION_LIST_PENDING);
  if (viewer === null) return all(s, SESSION_LIST_CONNECT, Number(archived), connect).map(toSession);
  const args: Json[] = [viewer.workspace, Number(viewer.home !== false), Number(archived)];
  if (connect !== null) args.push(connect);
  return all(s, connect === null ? SESSION_LIST_SCOPE : SESSION_LIST_SCOPE_CONNECT, ...args).map(toSession);
}

/// The sessions not archived (the sidebar's), the latest active first, by the index of those alone (schema.ts
/// sessions_live): each read of the sidebar went over every session the station ever had (many on a station, many of them
/// archived) to pick out its 107 (2026-11-03).
export const SHOWN_SESSIONS = "SELECT * FROM sessions INDEXED BY sessions_live WHERE archived_at IS NULL ORDER BY last_active_at DESC";
export function shownSessions(s: Store): SessionRow[] {
  return all(s, SHOWN_SESSIONS).map(toSession);
}

/// The archive a page at a time: archived sessions and chats archived alone, the latest archived first, before `(?1, ?2)`
/// (when, and its key or chat id as text), `?3` of them; each by the index of those archived.
export const ARCHIVED_PAGE = `SELECT kind, id, at FROM (
    SELECT 's' AS kind, key AS id, archived_at AS at FROM sessions INDEXED BY sessions_put_away WHERE archived_at IS NOT NULL AND (archived_at < ?1 OR (archived_at = ?1 AND key < ?2))
    UNION ALL
    SELECT 't' AS kind, CAST(id AS TEXT) AS id, hidden_at AS at FROM threads INDEXED BY threads_put_away WHERE hidden_at IS NOT NULL AND (hidden_at < ?1 OR (hidden_at = ?1 AND CAST(id AS TEXT) < ?2))
  ) ORDER BY at DESC, id DESC LIMIT ?3`;
export function archivedPage(s: Store, before: [number, string], limit: number): { kind: "s" | "t"; id: string; at: number }[] {
  return all(s, ARCHIVED_PAGE, before[0], before[1], limit) as { kind: "s" | "t"; id: string; at: number }[];
}

/// Store::sessionOfRuntime: the session that went on with `runtime`'s session `id`, the latest active if more did.
export function sessionOfRuntime(s: Store, runtime: string, id: string): string | null {
  try {
    return one(s, SESSION_OF_RUNTIME, runtime, id)?.key ?? null;
  } catch {
    try {
      // A station with per-transcript runtimes may still be running while this version opens its database.
      return one(s, `SELECT key FROM (
        SELECT key, last_active_at FROM sessions s WHERE runtime_session_id = ?2 AND runtime = ?1
          AND NOT EXISTS (SELECT 1 FROM runtime_sessions r WHERE r.session_key = s.key AND r.id = ?2 AND r.runtime IS NOT NULL AND r.runtime != ?1)
        UNION ALL SELECT s.key, s.last_active_at FROM runtime_sessions r JOIN sessions s ON s.key = r.session_key WHERE r.id = ?2 AND COALESCE(r.runtime, s.runtime) = ?1
      ) ORDER BY last_active_at DESC LIMIT 1`, runtime, id)?.key ?? null;
    } catch {
      try {
        return one(s, `SELECT key FROM (
          SELECT key, last_active_at FROM sessions WHERE runtime_session_id = ?2 AND runtime = ?1
          UNION ALL SELECT s.key, s.last_active_at FROM runtime_sessions r JOIN sessions s ON s.key = r.session_key WHERE r.id = ?2 AND s.runtime = ?1
        ) ORDER BY last_active_at DESC LIMIT 1`, runtime, id)?.key ?? null;
      } catch (error) {
        // An older store may not have kept previous runtime sessions at all; its current one is still readable.
        if (!/no such table: runtime_sessions/.test((error as Error).message)) throw error;
        return one(s, "SELECT key FROM sessions WHERE runtime_session_id = ?2 AND runtime = ?1 ORDER BY last_active_at DESC LIMIT 1", runtime, id)?.key ?? null;
      }
    }
  }
}

/// Store::runtimeSessions: the runtime sessions a session has run in, the first first, ending with its current one.
export function runtimeSessions(s: Store, key: string): string[] {
  const current = getSession(s, key)?.runtimeSessionId ?? null;
  let ids: string[] = [];
  try {
    ids = all(s, "SELECT id FROM runtime_sessions WHERE session_key = ? ORDER BY at, rowid", key).map((r) => r.id);
  } catch {} // a database no station of this version has opened yet
  return current === null ? ids : [...ids.filter((id) => id !== current), current];
}

const RUNTIME_SESSION_SOURCES = `SELECT r.id, COALESCE(r.runtime, s.original_runtime, s.runtime) AS runtime, r.profile
  FROM sessions s CROSS JOIN runtime_sessions r ON r.session_key = s.key WHERE s.key = ? ORDER BY r.at, r.rowid`;

/// The runtime and profile of each transcript, including those from before runtime changes were supported.
export function runtimeSessionSources(s: Store, key: string): { id: string; runtime: string; profile: string | null }[] {
  const row = getSession(s, key);
  if (!row) return [];
  let sources: { id: string; runtime: string; profile: string | null }[] = [];
  try {
    sources = all(s, RUNTIME_SESSION_SOURCES, key)
      .map((r) => ({ id: r.id, runtime: r.runtime, profile: r.profile ?? null }));
  } catch {
    try {
      sources = all(s, "SELECT id, runtime, profile FROM runtime_sessions WHERE session_key = ? ORDER BY at, rowid", key)
        .map((r) => ({ id: r.id, runtime: r.runtime ?? row.runtime, profile: r.profile ?? null }));
    } catch {
      sources = runtimeSessions(s, key).map((id) => ({ id, runtime: row.runtime, profile: row.profile }));
    }
  }
  if (row.runtimeSessionId === null) return sources;
  const current = sources.find((x) => x.id === row.runtimeSessionId) ?? { id: row.runtimeSessionId, runtime: row.runtime, profile: row.profile };
  return [...sources.filter((x) => x.id !== row.runtimeSessionId), current];
}

/// The source whose JavaScript id is `id`, as runtimeSessionSources would return it. A reader may decode distinct
/// NUL-suffixed ids alike, so detect those by their indexed byte range and use the original reader for that case.
export function runtimeSessionSource(s: Store, key: string, id: string): RuntimeSource | null {
  return findRuntimeSource(key, id, (sql, ...args) => one(s, sql, ...args),
    () => runtimeSessionSources(s, key).find((source) => source.id === id) ?? null);
}

const HISTORY_RUNTIME_BATCH = 128;
let historyRuntimeSnapshotId = 0;

/// A history's sources in conversation order. A small history stays in one read; a large one keeps its order in a
/// connection-local snapshot so the reader can resolve its paths in batches without holding a main-database snapshot.
/// SQLite still sorts the session's recorded sources before either read can return.
export function historyRuntimeSources(s: Store, key: string): Iterable<RuntimeSource | null> & { close(): void } {
  const array = (rows: RuntimeSource[]) => ({ [Symbol.iterator]: () => rows[Symbol.iterator](), close() {} });
  const row = getSession(s, key);
  if (!row) return array([]);
  let first: RuntimeSource[];
  try { first = s.db.prepare(`${RUNTIME_SESSION_SOURCES} LIMIT ${HISTORY_RUNTIME_BATCH + 1}`).all(key) as RuntimeSource[]; }
  catch { return array(runtimeSessionSources(s, key)); } // An old database uses the original reader's fallbacks.
  const normalize = (source: RuntimeSource): RuntimeSource => ({ id: source.id, runtime: source.runtime, profile: source.profile ?? null });
  if (first.length <= HISTORY_RUNTIME_BATCH) {
    const sources = first.map(normalize);
    if (row.runtimeSessionId === null) return array(sources);
    const current = sources.find((source) => source.id === row.runtimeSessionId)
      ?? { id: row.runtimeSessionId, runtime: row.runtime, profile: row.profile };
    return array([...sources.filter((source) => source.id !== row.runtimeSessionId), current]);
  }
  const ordered = function* (sources: Iterable<RuntimeSource>): Generator<RuntimeSource | null> {
    let current: RuntimeSource | undefined;
    for (const raw of sources) {
      const source = normalize(raw);
      // Yield a marker for skipped duplicates too: older SQLite readers can decode distinct NUL-suffixed ids alike.
      if (row.runtimeSessionId !== null && source.id === row.runtimeSessionId) { current ??= source; yield null; continue; }
      yield source;
    }
    if (row.runtimeSessionId !== null)
      yield current ?? { id: row.runtimeSessionId, runtime: row.runtime, profile: row.profile };
  };
  const table = `history_runtime_snapshot_${++historyRuntimeSnapshotId}`;
  try { s.db.prepare(`CREATE TEMP TABLE ${table} AS ${RUNTIME_SESSION_SOURCES}`).run(key); }
  catch (error) {
    const code = (error as { errcode?: number }).errcode;
    if (code === undefined || (code & 255) !== 8) throw error;
    return array(runtimeSessionSources(s, key)); // query_only connections cannot create even temporary tables.
  }
  try {
    const page = s.db.prepare(`SELECT rowid AS position, id, runtime, profile FROM temp.${table}
      WHERE rowid > ? ORDER BY rowid LIMIT ${HISTORY_RUNTIME_BATCH}`);
    const rows = function* (): Generator<RuntimeSource> {
      let after = 0;
      for (;;) {
        const batch = page.all(after) as (RuntimeSource & { position: number })[];
        for (const source of batch) { after = source.position; yield source; }
        if (batch.length < HISTORY_RUNTIME_BATCH) return;
      }
    };
    return { [Symbol.iterator]: () => ordered(rows()), close() { s.db.exec(`DROP TABLE temp.${table}`); } };
  } catch (error) { s.db.exec(`DROP TABLE temp.${table}`); throw error; }
}

/// Before per-message runtime was recorded, every message belonged to the session's first runtime.
export const ORIGINAL_RUNTIME = "SELECT COALESCE(original_runtime, runtime) AS runtime FROM sessions WHERE key = ?";
export const ORIGINAL_RUNTIME_ORDERED = `SELECT COALESCE(s.original_runtime,
  (SELECT r.runtime FROM runtime_sessions r INDEXED BY runtime_sessions_ordered WHERE r.session_key = s.key ORDER BY r.at, r.rowid LIMIT 1),
  s.runtime) AS runtime FROM sessions s WHERE s.key = ?`;
export function originalRuntime(s: Store, key: string): string | null {
  try {
    return one(s, hasRuntimeOrderIndex(s.db) ? ORIGINAL_RUNTIME_ORDERED : ORIGINAL_RUNTIME, key)?.runtime ?? null;
  } catch {
    if (hasRuntimeOrderIndex(s.db)) {
      try {
        return one(s, "SELECT runtime FROM runtime_sessions INDEXED BY runtime_sessions_ordered WHERE session_key = ? ORDER BY at, rowid LIMIT 1", key)?.runtime
          ?? one(s, "SELECT runtime FROM sessions WHERE key = ?", key)?.runtime ?? null;
      } catch {} // a database from before per-transcript runtimes
    }
    return one(s, "SELECT runtime FROM sessions WHERE key = ?", key)?.runtime ?? null;
  }
}

/// How many entries sessions' transcripts have, as the station last read them while they were at work (one, those
/// named, or every one when `key` is null): none for a session not read since.
export function transcriptLengths(s: Store, key: string | string[] | null): Map<string, number> {
  if (Array.isArray(key) && key.length === 0) return new Map();
  try {
    const sql = `SELECT session, n FROM transcript_lengths ${Array.isArray(key) ? "WHERE session IN (SELECT value FROM json_each(?))" : key !== null ? "WHERE session = ?" : ""}`;
    const rows = Array.isArray(key) ? all(s, sql, JSON.stringify(key)) : key !== null ? all(s, sql, key) : all(s, sql);
    return new Map(rows.map((r) => [r.session as string, Number(r.n)]));
  } catch {
    return new Map();
  }
}

/// What sessions' calls used, as the station keeps it (store.ts `setSessionUsage`; one, those named, or every one
/// known when `key` is null): none for a session that has made no call.
export function sessionUsages(s: Store, key: string | string[] | null): Map<string, Json> {
  if (Array.isArray(key) && key.length === 0) return new Map();
  try {
    const incremental = s.db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'usage_totals_incremental'").get() !== undefined;
    const source = incremental ? "session_usage u JOIN usage_totals_source_sessions c ON c.session = u.session AND c.done = 1" : "session_usage u";
    const sql = `SELECT u.session, u.usage FROM ${source} ${Array.isArray(key) ? "WHERE u.session IN (SELECT value FROM json_each(?))" : key !== null ? "WHERE u.session = ?" : ""}`;
    const rows = Array.isArray(key) ? all(s, sql, JSON.stringify(key)) : key !== null ? all(s, sql, key) : all(s, sql);
    return new Map(rows.map((r) => [r.session as string, JSON.parse(r.usage as string)]));
  } catch {
    return new Map();
  }
}

// ── threads ──

export function getThread(s: Store, id: number): ThreadRow | null {
  const r = one(s, "SELECT * FROM threads WHERE id = ?", id);
  return r ? toThread(r) : null;
}

/// The threads a session is in, the one it joined last first (store.rs session_threads).
/// `surface`: only those there; `limit`: the first few.
export function sessionThreads(s: Store, session: string, surface: string | null = null, limit = -1): ThreadRow[] {
  const order = "ORDER BY ts.joined_at DESC, ts.rowid DESC LIMIT ?";
  const rows = surface === null
    ? all(s, `SELECT t.* FROM thread_sessions ts JOIN threads t ON t.id = ts.thread WHERE ts.session = ? ${order}`, session, limit)
    : all(s, `SELECT t.* FROM thread_sessions ts JOIN threads t ON t.id = ts.thread WHERE ts.session = ? AND t.surface = ? ${order}`, session, surface, limit);
  return rows.map(toThread);
}

/// A page listing many chats asks for all their pending copy destinations together before constructing the views.
export function requireCcSessions(s: Store, sessions: readonly string[]): void {
  const missing = [...new Set(sessions)].filter((session) => !ccSessionReady(s.db, session));
  if (missing.length) throw new Refused(503, CC_SESSIONS_PENDING + JSON.stringify(missing));
}

/// The threads a still.fail chat can copy people's messages to (rows.ts CC_THREADS_SQL), with the connect posting
/// in each.
export function ccThreads(s: Store, thread: number): { thread: ThreadRow; connect: string }[] {
  try { return indexedCcThreads(s.db, thread).map((r) => ({ thread: toThread(r), connect: r.connect as string })); }
  catch (error) {
    if (error instanceof CcSessionsUnavailable) throw new Refused(503, CC_SESSIONS_PENDING + JSON.stringify(error.sessions));
    throw error;
  }
}

export function threadSessions(s: Store, thread: number): Membership[] {
  return all(s, "SELECT * FROM thread_sessions WHERE thread = ? ORDER BY joined_at, rowid", thread).map(toMembership);
}

/// For a named, shown own chat of the only job session, its first member is enough when that member is the live job
/// session. Short chats use the original reader; only a large requested chat needs the on-demand first-member lookup.
export function jobNameFirstMembers(s: Store, owner: string, thread: number): Membership[] | null {
  if (s.db.prepare(JOB_NAME_FIRST_LARGE).get(thread) === undefined) return null;
  try {
    checkJobNameFirst(s.db);
    const scope = s.db.prepare("SELECT thread,ready,restart FROM job_name_first WHERE owner=?").get(owner) as
      { thread: number; ready: number; restart: number } | undefined;
    if (scope) {
      if (scope.thread !== thread) return null;
      if (scope.ready !== 1 || scope.restart !== 0) throw new Refused(503, JOB_NAME_FIRST_PENDING + JSON.stringify([owner, thread]));
      const first = s.db.prepare(JOB_NAME_FIRST_ROW).get(owner, thread) as Json | undefined;
      return first?.session === owner ? [toMembership(first)] : null;
    }
    // One owner and one chat can each hold at most one lookup. Do not wait for a lookup owned by another job.
    if (s.db.prepare("SELECT 1 FROM job_name_first WHERE thread=?").get(thread) !== undefined ||
        s.db.prepare("SELECT 1 FROM session_up_job_rows WHERE session=? LIMIT 1").get(owner) === undefined) return null;
    throw new Refused(503, JOB_NAME_FIRST_PENDING + JSON.stringify([owner, thread]));
  } catch (error) {
    // An older store (or one opened without the job index) keeps its existing reader.
    if (error instanceof Error && /^no such table: (?:main\.)?(?:job_name_first_meta|job_name_first|session_up_job_rows)$/.test(error.message)) return null;
    throw error;
  }
}

/// The threads sessions take part in (each once).
export function threadsOfSessions(s: Store, keys: string[]): number[] {
  if (keys.length === 0) return [];
  return all(s, `SELECT DISTINCT thread FROM thread_sessions WHERE session IN (${keys.map(() => "?").join(", ")})`, ...keys).map((r) => r.thread as number);
}

/// Of these sessions' threads, those on the station's own surface or those on an external surface.
export function threadsOfSessionsOnSurface(s: Store, keys: string[], own: boolean): number[] {
  if (keys.length === 0) return [];
  // Starting from the surface would inspect every station chat even when these sessions have only one.
  return all(s, `SELECT DISTINCT t.id FROM thread_sessions m CROSS JOIN threads t ON t.id = m.thread
    WHERE m.session IN (SELECT value FROM json_each(?1)) AND t.surface ${own ? "=" : "IS NOT"} ?2`, JSON.stringify(keys), STILLFAIL_SURFACE).map((r) => r.id as number);
}

/// Whether a member has an external thread visible to the shared chat reader. A thread containing only missing
/// sessions cannot name a chat. Reuse the prepared lookup for members of the same job read.
export const HAS_NAMING_ORIGIN = `SELECT 1 FROM thread_sessions origin
  CROSS JOIN threads t ON t.id = origin.thread
  WHERE origin.session = ?1 AND t.surface IS NOT ?2 AND EXISTS (
    SELECT 1 FROM thread_sessions member
    CROSS JOIN sessions live ON live.key = member.session
    WHERE member.thread = t.id
  ) LIMIT 1`;

// An existing copy-destination index already separates external memberships. Its order is different from naming
// order, but existence needs no order. A live member itself makes each of its external threads visible.
export const HAS_NAMING_ORIGIN_PREPARED = `SELECT 1 FROM cc_session_rows INDEXED BY cc_session_order
  WHERE session = ?1 AND surface != 'ember' LIMIT 1`;
// A short membership list is cheaper to check directly than to verify the prepared projection's journals.
export const HAS_NAMING_ORIGIN_POSSIBLE = `SELECT 1 FROM cc_sessions c CROSS JOIN sessions live ON live.key = c.session
      WHERE c.session = ?1 AND c.complete = 1 AND EXISTS (
        SELECT 1 FROM thread_sessions INDEXED BY thread_sessions_session WHERE session = c.session LIMIT 1 OFFSET 8
      )`;

const missingOriginIndex = (error: unknown): boolean => {
  const message = error instanceof Error ? error.message : "";
  return /^no such (?:table|index): (?:main\.)?(?:cc_index_meta|cc_sessions|cc_session_rows|cc_session_dirty|cc_order_dispatch|cc_session_order|thread_sessions_session)$/.test(message);
};

const preparedOriginIndexAvailable = (s: Store): boolean => {
  // A missing thread has a NULL surface in cc_session_rows. Older schemas that also permit a real thread with a
  // NULL surface cannot distinguish those cases in the partial index, so they retain the original check.
  const surface = s.db.prepare(`SELECT "notnull" AS required FROM pragma_table_info('threads') WHERE name = 'surface'`).get();
  if (surface?.required !== 1) return false;
  return s.db.prepare("SELECT version FROM cc_index_meta WHERE id = 1").get()?.version === CC_INDEX_VERSION;
};

export function namingOriginProbe(s: Store): (session: string) => boolean {
  const lookup = s.db.prepare(HAS_NAMING_ORIGIN);
  const original = (session: string) => lookup.get(session, STILLFAIL_SURFACE) !== undefined;
  let possible: ReturnType<DatabaseSync["prepare"]>;
  let prepared: ReturnType<DatabaseSync["prepare"]>;
  try {
    if (!preparedOriginIndexAvailable(s)) return original;
    possible = s.db.prepare(HAS_NAMING_ORIGIN_POSSIBLE);
    prepared = s.db.prepare(HAS_NAMING_ORIGIN_PREPARED);
  } catch (error) {
    if (missingOriginIndex(error)) return original;
    throw error;
  }
  return (session) => {
    if (possible.get(session) === undefined) return original(session);
    // A direct caller need not already hold a read transaction. Check the live member and index readiness again
    // under the same snapshot as the answer, since a writer may change either after the initial fast-path probe.
    s.db.exec("SAVEPOINT naming_origin_probe");
    try {
      if (possible.get(session) === undefined || !ccSessionReady(s.db, session)) return original(session);
      return prepared.get(session) !== undefined;
    } catch (error) {
      if (missingOriginIndex(error) || (error instanceof Error && error.message.startsWith("copy destination index version "))) return original(session);
      throw error;
    } finally { s.db.exec("RELEASE naming_origin_probe"); }
  };
}

/// Each session's external origin in the order of threadsForChatNames, excluding missing-only origins as in
/// sharedChats. Find them together before loading their details rather than loading every older origin's members.
export const LATEST_NAMING_ORIGIN = `SELECT (SELECT t.id FROM thread_sessions m
  CROSS JOIN threads t ON t.id = m.thread
  LEFT JOIN thread_state st ON st.thread = t.id
  LEFT JOIN entries e ON e.thread = t.id AND e.n = st.said_n AND e.kind = 'message'
  WHERE m.session = requested.value AND t.surface IS NOT ?2 AND EXISTS (
    SELECT 1 FROM thread_sessions member CROSS JOIN sessions live ON live.key = member.session
    WHERE member.thread = t.id
  ) ORDER BY COALESCE(e.at, 0) DESC, t.created_at DESC, t.id DESC LIMIT 1) AS id
  FROM json_each(?1) requested`;

// Classify the requested members together, keeping their array positions even when a session is repeated.
export const LATEST_NAMING_ORIGIN_POSSIBLE = `SELECT requested.key AS ordinal FROM json_each(?1) requested
  CROSS JOIN cc_sessions c ON c.session=requested.value CROSS JOIN sessions live ON live.key=c.session
  WHERE c.complete=1 AND EXISTS (SELECT 1 FROM thread_sessions INDEXED BY thread_sessions_session
    WHERE session=c.session LIMIT 1 OFFSET 8)`;

// The copy index orders by the last entry, not the last message. Sort a bounded set in naming order and retain the
// original batch query when there are more external origins; the index is useful here only for a live, ready member.
export const LATEST_NAMING_ORIGIN_PREPARED = `WITH candidates AS MATERIALIZED (
    SELECT thread FROM cc_session_rows INDEXED BY cc_session_order
    WHERE session=?1 AND surface != 'ember' LIMIT 9
  ) SELECT (SELECT COUNT(*) FROM candidates) AS count,
    CASE WHEN (SELECT COUNT(*) FROM candidates)<9 THEN (SELECT t.id FROM candidates r
      CROSS JOIN threads t ON t.id=r.thread LEFT JOIN thread_state st ON st.thread=t.id
      LEFT JOIN entries e ON e.thread=t.id AND e.n=st.said_n AND e.kind='message'
      ORDER BY COALESCE(e.at,0) DESC,t.created_at DESC,t.id DESC LIMIT 1) END AS id`;

export function latestNamingOrigins(s: Store, sessions: string[]): number[] {
  if (sessions.length === 0) return [];
  const original = (keys: string[]) => all(s, LATEST_NAMING_ORIGIN, JSON.stringify(keys), STILLFAIL_SURFACE);
  // The fast and fallback reads, including liveness and index readiness, must share the old query's one snapshot.
  s.db.exec("SAVEPOINT latest_naming_origins");
  try {
    if (!preparedOriginIndexAvailable(s)) return original(sessions).flatMap((row) => row.id === null ? [] : [row.id as number]);
    const possible = new Set(s.db.prepare(LATEST_NAMING_ORIGIN_POSSIBLE).all(JSON.stringify(sessions))
      .map((row) => row.ordinal as number));
    const prepared = s.db.prepare(LATEST_NAMING_ORIGIN_PREPARED);
    const ids: (number | null)[] = new Array(sessions.length).fill(null);
    const pending: string[] = [], positions: number[] = [];
    for (let i=0; i<sessions.length; i++) {
      const session = sessions[i]!;
      if (possible.has(i) && ccSessionReady(s.db, session)) {
        const candidate = prepared.get(session) as { count: number; id: number | null };
        if (candidate.count < 9) { ids[i] = candidate.id; continue; }
      }
      pending.push(session); positions.push(i);
    }
    if (pending.length) for (const [i, row] of original(pending).entries()) ids[positions[i]!] = row.id as number | null;
    return ids.filter((id): id is number => id !== null);
  } catch (error) {
    if (missingOriginIndex(error) || (error instanceof Error && error.message.startsWith("copy destination index version ")))
      return original(sessions).flatMap((row) => row.id === null ? [] : [row.id as number]);
    throw error;
  } finally { s.db.exec("RELEASE latest_naming_origins"); }
}

/// Of `threads`, those with something new since `since` (ms): made, or a message said, then.
export function threadsActiveSince(s: Store, threads: number[], since: number): number[] {
  if (threads.length === 0 || since <= 0) return threads;
  return all(
    s,
    `SELECT t.id FROM threads t LEFT JOIN thread_state st ON st.thread = t.id LEFT JOIN entries e ON e.thread = t.id AND e.n = st.said_n
     WHERE t.id IN (${threads.map(() => "?").join(", ")}) AND (t.created_at >= ? OR e.at >= ?)`,
    ...threads, since, since,
  ).map((r) => r.id as number);
}

/// The chat a session is in: the thread it first joined, or null.
export function threadOfSession(s: Store, key: string): number | null {
  return one(s, "SELECT thread FROM thread_sessions WHERE session = ? ORDER BY joined_at, rowid LIMIT 1", key)?.thread ?? null;
}

/// The thread at a chat app's address (`channel`, `ts`: a Slack channel and its thread's first message), or null.
export function threadAt(s: Store, channel: string, ts: string): number | null {
  return one(s, "SELECT id FROM threads WHERE channel = ? AND thread_ts = ? ORDER BY id LIMIT 1", channel, ts)?.id ?? null;
}

/// The threads the sidebar is made of (views.ts `chats`): those of the sessions in lists, and every thread of a session
/// in one of those (the Slack threads their agents came from among them). The archive's others, most of a station's
/// threads, are none of it.
export function threadsOfShown(s: Store): number[] {
  return all(
    s,
    `SELECT DISTINCT thread FROM thread_sessions WHERE session IN (SELECT session FROM thread_sessions WHERE thread IN (
       SELECT ts.thread FROM thread_sessions ts JOIN sessions x ON x.key = ts.session WHERE x.archived_at IS NULL))`,
  ).map((r) => r.thread as number);
}

/// Threads with their sessions, last entry, latest message and the viewer's unread count, most recently said in
/// first: those of one session, one thread (or those named), or all. A list that only needs to know whether there are
/// unread messages can ask for existence instead of their exact count. A workspace-scoped list checks membership
/// before reading each thread's message and other details.
export function listThreads(s: Store, viewer: string, session: string | null, thread: number | number[] | null, unread: "count" | "exists" | "none" = "count", visibleTo?: InWorkspace): ThreadSummary[] {
  const base = "SELECT t.*, COALESCE(r.n, 0) AS read_n FROM threads t LEFT JOIN reads r ON r.thread = t.id AND r.viewer = ?1";
  const where: string[] = [], args: Json[] = [viewer];
  if (Array.isArray(thread)) {
    if (thread.length === 0) return [];
    where.push(`t.id IN (${thread.map((_, i) => `?${i + 2}`).join(", ")})`);
    args.push(...thread);
  } else if (thread !== null) {
    where.push("t.id = ?2");
    args.push(thread);
  } else if (session !== null) {
    where.push("t.id IN (SELECT thread FROM thread_sessions WHERE session = ?2)");
    args.push(session);
  }
  const selected = where.length === 0 ? base : `${base} WHERE ${where.join(" AND ")}`;
  const and = where.length === 0 ? " WHERE " : " AND ";
  let rows: Json[];
  if (visibleTo !== undefined) {
    const scope = `EXISTS (SELECT 1 FROM thread_sessions visible_member
      LEFT JOIN sessions visible_session ON visible_session.key = visible_member.session
      WHERE visible_member.thread = t.id AND (visible_session.ws = ?${args.length + 1}
        OR (?${args.length + 2} AND visible_session.ws IS NULL)))`;
    try { rows = all(s, selected + and + scope, ...args, visibleTo.workspace, visibleTo.home !== false ? 1 : 0); }
    catch (error) {
      // Before sessions had `ws`, every session (including a missing one) belonged to the home workspace.
      if (!(error instanceof Error) || !error.message.includes("no such column: visible_session.ws")) throw error;
      if (visibleTo.home === false) return [];
      rows = all(s, selected + and + "EXISTS (SELECT 1 FROM thread_sessions visible_member WHERE visible_member.thread = t.id)", ...args);
    }
  } else rows = all(s, selected, ...args);
  if (rows.length === 0) return [];
  // Who the viewer is: themselves, and in a Slack thread the Slack users they are too.
  const selves = { own: [viewer], slack: [viewer, ...slackIdentities(s, viewer)] };
  const summaries: ThreadSummary[] = rows.map((r) => {
    const t = toThread(r);
    const read: number = r.read_n;
    return {
      sessions: threadSessions(s, t.id),
      last: lastEntry(s, t.id),
      lastMessage: lastSaid(s, t.id),
      read,
      unread: unread === "none" ? 0 : unreadOf(s, t.id, read, t.surface !== STILLFAIL_SURFACE ? selves.slack : selves.own, unread),
      people: threadPeople(s, t.id, t.surface),
      firstText: firstText(s, t.id),
      letters: letterCount(s, t.id),
      lettersLast: lastLetter(s, t.id),
      thread: t,
    };
  });
  const said = (t: ThreadSummary) => t.lastMessage?.createdAt ?? 0;
  summaries.sort((a, b) => said(b) - said(a) || b.thread.createdAt - a.thread.createdAt || b.thread.id - a.thread.id);
  return summaries;
}

/// The members and message times needed to select chat names for jobs. Message bodies and edits are not needed to
/// order them; an external thread's first text is read only if that thread actually supplies a name.
export function threadsForChatNames(s: Store, ids: number[] | null,
  members?: ReadonlyMap<number, Membership[]>): { thread: ThreadRow; sessions: Membership[]; lastAt: number }[] {
  if (ids !== null && ids.length === 0) return [];
  const selected = ids === null ? all(s, "SELECT * FROM threads")
    : all(s, `SELECT * FROM threads WHERE id IN (${ids.map(() => "?").join(", ")})`, ...ids);
  const threads = selected.map((row) => {
    const thread = toThread(row);
    return { thread, sessions: members?.get(thread.id) ?? threadSessions(s, thread.id), lastAt: lastSaidAt(s, thread.id) ?? 0 };
  });
  threads.sort((a, b) => b.lastAt - a.lastAt || b.thread.createdAt - a.thread.createdAt || b.thread.id - a.thread.id);
  return threads;
}

export const LAST_MESSAGE_PENDING = "last message pending: ";
export class LastMessageUnavailable extends Refused {
  readonly threads: number[];
  constructor(threads: number[]) { super(503, LAST_MESSAGE_PENDING + JSON.stringify(threads)); this.threads = threads; }
}
export const LAST_MESSAGE_KEYED = "SELECT * FROM merged WHERE thread=?1 AND n=CAST(?2 AS INTEGER)";
export { LAST_MESSAGE_RECENT_EDIT, LAST_MESSAGE_OLD_EDITS, LAST_MESSAGE_WITH_EDIT } from "../store/legacy-edits-read.ts";
export const LEGACY_EDITS_PENDING = "legacy edit lookup pending";
export class LegacyEditsUnavailable extends Refused {
  constructor() { super(503, LEGACY_EDITS_PENDING); }
}

// The caller holds the message and edit lookup in one snapshot. Without a prepared lookup, a recent edit (or a
// short chat) proves the latest edit; an old index can prove it when at most one bounded batch matches.
function boundedEditKey(s: Store, thread: number, n: string): string | null {
  const edit = readBoundedEditKey(s.db, thread, n);
  if (edit === undefined) throw new LegacyEditsUnavailable();
  return edit;
}

function mergedWithBoundedEdit(s: Store, thread: number, n: string): MessageRow | null {
  const r = one(s, LAST_MESSAGE_WITH_EDIT, thread, n, boundedEditKey(s, thread, n));
  return r ? toMessage(r) : null;
}

/// A session's undelivered messages and letters, in the order the actor gives them to its runtime. A key and its
/// merged text, and both delivery logs, must describe the same snapshot.
export function pendingDeliveries(s: Store, session: string): PendingMessage[] {
  s.db.exec("SAVEPOINT pending_delivery_read");
  try {
    let said: PendingMessage[];
    if (legacyMergedReadReady(s.db)) {
      said = all(s, `SELECT m.*, t.surface, t.channel, t.thread_ts, ts.connect FROM deliveries d
        JOIN merged m ON m.thread = d.thread AND m.n = d.n JOIN threads t ON t.id = d.thread
        JOIN thread_sessions ts ON ts.thread = t.id AND ts.session = d.session
        WHERE d.session = ? AND d.delivered_at IS NULL ORDER BY d.rowid`, session)
        .map((r) => ({ message: toMessage(r), surface: r.surface, channel: r.channel, threadTs: r.thread_ts, connect: r.connect }));
    } else {
      const keys = all(s, `SELECT d.thread, CAST(d.n AS TEXT) AS n, t.surface, t.channel, t.thread_ts, ts.connect FROM deliveries d
        JOIN entries e ON e.thread = d.thread AND e.n = d.n AND e.kind = 'message' JOIN threads t ON t.id = d.thread
        JOIN thread_sessions ts ON ts.thread = t.id AND ts.session = d.session
        WHERE d.session = ? AND d.delivered_at IS NULL ORDER BY d.rowid`, session);
      said = keys.flatMap((r) => {
        const message = mergedWithBoundedEdit(s, r.thread, r.n);
        return message === null ? [] : [{ message, surface: r.surface, channel: r.channel, threadTs: r.thread_ts, connect: r.connect }];
      });
    }
    const letters = all(s, `SELECT l.*, t.surface, t.channel, t.thread_ts, ts.connect FROM letter_deliveries d
      JOIN letters l ON l.thread = d.thread AND l.n = d.n JOIN threads t ON t.id = d.thread
      JOIN thread_sessions ts ON ts.thread = t.id AND ts.session = d.session
      WHERE d.session = ? AND d.delivered_at IS NULL ORDER BY d.rowid`, session)
      .map((r) => ({ message: letterMessage(r), surface: r.surface, channel: r.channel, threadTs: r.thread_ts, connect: r.connect }));
    const out: PendingMessage[] = [];
    let i = 0, j = 0;
    while (i < said.length || j < letters.length) {
      if (j >= letters.length || (i < said.length && said[i]!.message.createdAt <= letters[j]!.message.createdAt)) out.push(said[i++]!);
      else out.push(letters[j++]!);
    }
    return out;
  } finally { s.db.exec("RELEASE pending_delivery_read"); }
}

/// The thread's latest message as merged. The key and edited text must come from the same snapshot.
export function lastMessage(s: Store, thread: number): MessageRow | null {
  s.db.exec("SAVEPOINT last_message_read");
  try {
    const last = archiveLastKey(s.db, thread);
    if (!last.known) throw new LastMessageUnavailable([thread]);
    if (last.n === null) return null;
    if (!legacyMergedReadReady(s.db)) return mergedWithBoundedEdit(s, thread, last.n);
    const r = one(s, LAST_MESSAGE_KEYED, thread, last.n);
    return r ? toMessage(r) : null;
  } finally { s.db.exec("RELEASE last_message_read"); }
}

/// How many letters the thread has (isLetter), in either way: those kept as entries before letters had their own log,
/// and those of it.
export function letterCount(s: Store, thread: number): number {
  const apart = lastLetter(s, thread);
  return apart + (one(s, "SELECT letters FROM thread_state WHERE thread = ?", thread)?.letters ?? 0);
}

/// The last letter of the thread's own log of them (store/schema.ts LETTERS; 0: none).
export function lastLetter(s: Store, thread: number): number {
  return one(s, "SELECT MAX(n) AS n FROM letters WHERE thread = ?", thread)?.n ?? 0;
}

/// Letters of the thread's own log from n = `from` to n = `to`, both included, up to `limit` when given.
export function lettersBetween(s: Store, thread: number, from: bigint, to: bigint, limit?: number): EntryRow[] {
  const sql = "SELECT * FROM letters WHERE thread = ? AND n >= ? AND n <= ? ORDER BY n";
  return (limit === undefined ? all(s, sql, thread, from, to) : all(s, `${sql} LIMIT ?`, thread, from, to, limit)).map(letterEntry);
}

/// The latest `limit` letters of the thread's own log before n (the latest of all without it), oldest first.
export function lettersBefore(s: Store, thread: number, n: bigint | null, limit: number): EntryRow[] {
  return all(s, "SELECT * FROM letters WHERE thread = ? AND n < ? ORDER BY n DESC LIMIT ?", thread, n ?? I64_MAX, limit).map(letterEntry).reverse();
}

/// The thread's latest message that is not a letter (isLetter), for lists: what they show and sort by.
export function lastSaid(s: Store, thread: number): MessageRow | null {
  s.db.exec("SAVEPOINT last_said_read");
  try {
    if (legacyMergedReadReady(s.db)) {
      const r = one(s, "SELECT m.* FROM thread_state t JOIN merged m ON m.thread = t.thread AND m.n = t.said_n WHERE t.thread = ?", thread);
      return r ? toMessage(r) : null;
    }
    const n = one(s, "SELECT CAST(said_n AS TEXT) AS n FROM thread_state WHERE thread=?", thread)?.n as string | null | undefined;
    return n == null ? null : mergedWithBoundedEdit(s, thread, n);
  } finally { s.db.exec("RELEASE last_said_read"); }
}

/// The latest said text for searching, without decoding a message's other fields.
export function lastSaidText(s: Store, thread: number): string | null {
  s.db.exec("SAVEPOINT last_said_text_read");
  try {
    if (legacyMergedReadReady(s.db)) {
      const r = one(s, "SELECT m.text AS t FROM thread_state t JOIN merged m ON m.thread = t.thread AND m.n = t.said_n WHERE t.thread = ?", thread);
      return r ? r.t : null;
    }
    const n = one(s, "SELECT CAST(said_n AS TEXT) AS n FROM thread_state WHERE thread=?", thread)?.n as string | null | undefined;
    if (n == null) return null;
    const edit = boundedEditKey(s, thread, n);
    const r = one(s, `SELECT CASE WHEN e.n IS NULL THEN m.text ELSE e.text END AS t
      FROM entries m LEFT JOIN entries e ON e.thread=m.thread AND e.n=CAST(?3 AS INTEGER)
      WHERE m.thread=?1 AND m.n=CAST(?2 AS INTEGER) AND m.kind='message'`, thread, n, edit);
    return r ? r.t : null;
  } finally { s.db.exec("RELEASE last_said_text_read"); }
}

/// When the latest message was written, without loading its text or edits.
export function lastSaidAt(s: Store, thread: number): number | null {
  return one(s, "SELECT e.at FROM thread_state t JOIN entries e ON e.thread = t.thread AND e.n = t.said_n AND e.kind = 'message' WHERE t.thread = ?", thread)?.at ?? null;
}

/// Messages after the read position that are not the viewer's own (nor of a Slack user they are).
function unreadCount(s: Store, viewer: string, thread: number, read: number): number {
  const t = getThread(s, thread);
  const slack = t ? t.surface !== STILLFAIL_SURFACE : true;
  const selves = [viewer];
  if (slack) selves.push(...slackIdentities(s, viewer));
  return unreadOf(s, thread, read, selves);
}

/// Messages after `read` that are not of `selves`, nor letters (isLetter).
/// A chat's latest message that counts as unread (no letter) and the latest before it its author did not write (`other`:
/// that one is what is unread for its author), by the index of its messages (store/schema.ts entries_said): what a
/// viewer's unread is made of with where they read (client/core-ts/src/chat-row.ts), for everyone at once.
export { SAID_LATEST, SAID_SCAN, SAID_STATE };
export const SAID_PENDING = "sidebar said state pending: ";
export class SaidUnavailable extends Refused {
  readonly threads: number[];
  constructor(threads: number[]) { super(503, SAID_PENDING + JSON.stringify(threads)); this.threads = threads; }
}
export const LEGACY_SAID_PENDING = "legacy said lookup pending";
export class LegacySaidUnavailable extends Refused {
  constructor() { super(503, LEGACY_SAID_PENDING); }
}

export function saidOf(s: Store, thread: number): { n: number; authorKind: string; author: string; other: number | null } | null {
  // On old stores the bounded head probe, dirty-key check and boundary read must see the same snapshot.
  if (s.legacySaid) s.db.exec("SAVEPOINT said_read");
  try {
    const head = s.legacySaid ? legacySaidReadHead(s.db, thread) : { known: true, row: one(s, SAID_LATEST, thread) };
    if (!head.known) throw new SaidUnavailable([thread]);
    const r = head.row;
    if (!r) return null;
    const state = r.author_kind === "person" ? one(s, SAID_STATE, thread) : null;
    const boundary = saidBoundary(state, r);
    let other = boundary.other;
    if (!boundary.known) {
      // Most old chats can answer from a few nearby messages without recording any history at all. For a longer run,
      // leave the reader and prepare only this chat in bounded slices before trying the snapshot again.
      if (s.legacySaid && legacySaidThreadNeedsDrain(s.db, thread)) {
        const near = legacySaidReadBoundary(s.db,thread,r.n,r.author);
        if (!near.known) throw new SaidUnavailable([thread]);
        other = near.other;
      } else {
        const nearby = all(s, s.legacySaid ? LEGACY_SAID_SCAN : SAID_SCAN, thread, r.n, SAID_BATCH_SIZE);
        const previous = nearby.find((p) => p.author_kind !== "person" || p.author !== r.author);
        if (previous) other = previous.n;
        else if (nearby.length === SAID_BATCH_SIZE) throw new SaidUnavailable([thread]);
      }
    }
    return { n: r.n, authorKind: r.author_kind, author: r.author, other };
  } finally { if (s.legacySaid) s.db.exec("RELEASE said_read"); }
}

/// Where a viewer read each of these chats to (none: nothing of it).
export function readsOf(s: Store, viewer: string, threads: number[]): Map<number, number> {
  const out = new Map<number, number>();
  if (threads.length === 0) return out;
  for (const r of all(s, `SELECT thread, n FROM reads WHERE viewer = ?1 AND thread IN (SELECT value FROM json_each(?2))`, viewer, JSON.stringify(threads))) out.set(r.thread, r.n);
  return out;
}

/// A viewer's hidden chats, limited to the threads this read can name.
export function hiddenChats(s: Store, viewer: string, threads: number[]): Set<number> {
  if (threads.length === 0) return new Set();
  return new Set(all(s, "SELECT thread FROM hidden_chats WHERE viewer = ?1 AND thread IN (SELECT value FROM json_each(?2))", viewer, JSON.stringify(threads)).map((r) => r.thread));
}

/// A viewer's muted chats and, for a notice, which of its recipients muted that chat.
export function mutedChats(s: Store, viewer: string, threads: number[]): Set<number> {
  if (threads.length === 0) return new Set();
  return new Set(all(s, "SELECT thread FROM muted_chats WHERE viewer = ?1 AND thread IN (SELECT value FROM json_each(?2))", viewer.toLowerCase(), JSON.stringify(threads)).map((r) => r.thread));
}

export function mutedViewers(s: Store, thread: number, viewers: string[]): Set<string> {
  if (viewers.length === 0) return new Set();
  return new Set(all(s, "SELECT viewer FROM muted_chats WHERE viewer IN (SELECT value FROM json_each(?1)) AND thread = ?2", JSON.stringify(viewers), thread).map((r) => r.viewer));
}

function unreadOf(s: Store, thread: number, read: number, selves: string[], mode: "count" | "exists" = "count"): number {
  const sql = s.legacySaid ? (mode === "exists" ? LEGACY_HAS_UNREAD : LEGACY_UNREAD) : (mode === "exists" ? HAS_UNREAD : UNREAD);
  return one(s, sql, thread, read, JSON.stringify(selves)).c;
}

/// A chat's messages after where a viewer read (`?2`) but their own (`?3`, a JSON list) and letters, counted from the
/// index of its messages alone (store/schema.ts entries_said): from the messages themselves, each was a page read.
const UNREAD_MESSAGES = `FROM entries WHERE thread = ?1 AND n > ?2 AND kind = 'message' AND letter IS NULL
  AND NOT (author_kind = 'person' AND author IN (SELECT value FROM json_each(?3)))`;
export const UNREAD = `SELECT COUNT(*) AS c ${UNREAD_MESSAGES}`;
export const HAS_UNREAD = `SELECT EXISTS (SELECT 1 ${UNREAD_MESSAGES}) AS c`;

/// Everyone who wrote in a thread, as creator references (a Slack user through a connect in it), earliest first.
export function threadPeople(s: Store, thread: number, surface: string): string[] {
  const connect: string | null = one(s, "SELECT MIN(connect) AS c FROM thread_sessions WHERE thread = ?", thread).c;
  const authors: string[] = all(s, "SELECT author FROM thread_people WHERE thread = ? ORDER BY first_n", thread).map((r) => r.author);
  if (surface === STILLFAIL_SURFACE) return authors;
  return connect === null ? [] : authors.map((a) => `slack:${connect}:${a}`);
}

/// The first thing a person said in it (up to 300 characters).
export function firstText(s: Store, thread: number): string | null {
  s.db.exec("SAVEPOINT first_text_read");
  try {
    if (legacyMergedReadReady(s.db)) {
      const r = one(s, "SELECT substr(m.text, 1, 300) AS t FROM thread_state t JOIN merged m ON m.thread = t.thread AND m.n = t.person_n WHERE t.thread = ?", thread);
      return r ? r.t : null;
    }
    const n = one(s, "SELECT CAST(person_n AS TEXT) AS n FROM thread_state WHERE thread=?", thread)?.n as string | null | undefined;
    if (n == null) return null;
    const edit = boundedEditKey(s, thread, n);
    const r = one(s, `SELECT substr(CASE WHEN e.n IS NULL THEN m.text ELSE e.text END,1,300) AS t
      FROM entries m LEFT JOIN entries e ON e.thread=m.thread AND e.n=CAST(?3 AS INTEGER)
      WHERE m.thread=?1 AND m.n=CAST(?2 AS INTEGER) AND m.kind='message'`, thread, n, edit);
    return r ? r.t : null;
  } finally { s.db.exec("RELEASE first_text_read"); }
}

// ── entries ──

/// The thread's last entry number, 0 before anything is said.
export function lastEntry(s: Store, thread: number): number {
  return one(s, "SELECT MAX(n) AS n FROM entries WHERE thread = ?", thread).n ?? 0;
}

/// Entries after n, up to `limit` when given (`n + 1` wraps at i64::MAX, as a release build's does).
export function entriesAfter(s: Store, thread: number, n: bigint, limit?: number): EntryRow[] {
  return entriesBetween(s, thread, BigInt.asIntN(64, n + 1n), I64_MAX, limit);
}

/// The latest `limit` entries before n (the latest of all without it), oldest first.
export function entriesBefore(s: Store, thread: number, n: bigint | null, limit: number): EntryRow[] {
  const before = n ?? I64_MAX;
  return all(s, "SELECT * FROM entries WHERE thread = ? AND n < ? ORDER BY n DESC LIMIT ?", thread, before, limit).map(toEntry).reverse();
}

/// Entries from n = `from` to n = `to`, both included: a gap, up to `limit` when given.
export function entriesBetween(s: Store, thread: number, from: bigint, to: bigint, limit?: number): EntryRow[] {
  const sql = "SELECT * FROM entries WHERE thread = ? AND n >= ? AND n <= ? ORDER BY n";
  return (limit === undefined ? all(s, sql, thread, from, to) : all(s, `${sql} LIMIT ?`, thread, from, to, limit)).map(toEntry);
}

// During old lookup preparation or a large changed-key backlog, the raw tail can still prove a page.
// Keep keys as text until the keyed reads: an unrelated entry may have a number beyond JavaScript's exact range.
export const LEGACY_SAID_PAGE_TAIL = `SELECT CAST(e.n AS TEXT) AS n,e.kind FROM entries e
  WHERE e.thread=?1 AND e.n<?2 ORDER BY e.n DESC LIMIT ?3`;
export const MESSAGES_FROM_KEYS = `SELECT * FROM merged WHERE thread=?1 AND n IN
  (SELECT CAST(value AS INTEGER) FROM json_each(?2)) ORDER BY n DESC`;

export const PAGE_LETTER_PENDING = "page letter lookup pending: ";
export class PageLetterUnavailable extends Refused {
  constructor(thread: number) { super(503, PAGE_LETTER_PENDING + JSON.stringify([thread])); }
}

// Select ordered integer keys before casting: a text ORDER BY would sort every message in the chat.
export const PAGE_ORDINARY_KEYS = `SELECT CAST(p.n AS TEXT) AS n FROM (
  SELECT n FROM entries INDEXED BY entries_said WHERE thread=?1 AND n<?2 AND kind='message' AND letter IS NULL
  ORDER BY n DESC LIMIT ?3) p ORDER BY p.n DESC`;
export const LEGACY_PAGE_ORDINARY_KEYS = `SELECT CAST(p.n AS TEXT) AS n FROM (
  SELECT n FROM legacy_said WHERE thread=?1 AND n<?2 ORDER BY n DESC LIMIT ?3) p ORDER BY p.n DESC`;
export const PAGE_LETTER_CANDIDATES = `SELECT CAST(e.n AS TEXT) AS n,e.kind FROM entries e INDEXED BY entries_letters
  WHERE e.thread=?1 AND e.n<?2 AND e.letter IS NOT NULL ORDER BY e.n DESC LIMIT ?3`;

/// Ascending counterparts used by the Router's message page. Integer ordering precedes conversion to text.
export const PAGE_ORDINARY_KEYS_AFTER = `SELECT CAST(p.n AS TEXT) AS n FROM (
  SELECT n FROM entries INDEXED BY entries_said WHERE thread=?1 AND n>?2 AND kind='message' AND letter IS NULL
  ORDER BY n LIMIT ?3) p ORDER BY p.n`;
export const LEGACY_PAGE_ORDINARY_KEYS_AFTER = `SELECT CAST(p.n AS TEXT) AS n FROM (
  SELECT n FROM legacy_said WHERE thread=?1 AND n>?2 ORDER BY n LIMIT ?3) p ORDER BY p.n`;
export const PAGE_LETTER_CANDIDATES_AFTER = `SELECT CAST(e.n AS TEXT) AS n,e.kind FROM entries e INDEXED BY entries_letters
  WHERE e.thread=?1 AND e.n>?2 AND e.letter IS NOT NULL ORDER BY e.n LIMIT ?3`;
export const LEGACY_SAID_PAGE_HEAD = `SELECT CAST(e.n AS TEXT) AS n,e.kind FROM entries e
  WHERE e.thread=?1 AND e.n>?2 ORDER BY e.n LIMIT ?3`;

const letterIndexes = new WeakMap<DatabaseSync, { version: number; ready: boolean }>();
function hasPageLetterIndex(db: DatabaseSync): boolean {
  const version = Number(db.prepare("PRAGMA schema_version").get()!.schema_version);
  let cached = letterIndexes.get(db);
  if (!cached || cached.version !== version) {
    cached = { version, ready: db.prepare("SELECT 1 FROM sqlite_master WHERE type='index' AND name='entries_letters'").get() !== undefined };
    letterIndexes.set(db, cached);
  }
  return cached.ready;
}

const descendingKeys = (keys: string[]) => keys.sort((a, b) => BigInt(a) > BigInt(b) ? -1 : BigInt(a) < BigInt(b) ? 1 : 0);

// With an indexed letter candidate tail, only non-message letters can make a page need more than its requested number
// of keys. Never look below a truncated candidate tail: there could be an older letter-message above an ordinary key.
function boundedMessagePageKeys(s: Store, thread: number, before: number | bigint, limit: number): string[] {
  const token = pageLetterReady(s.db, thread);
  if (!token && !hasPageLetterIndex(s.db)) {
    const cap = limit + 64;
    const tail = all(s, LEGACY_SAID_PAGE_TAIL, thread, before, cap);
    const keys = tail.filter((r) => r.kind === "message").slice(0, limit).map((r) => r.n as string);
    if (keys.length < limit && tail.length === cap) throw new PageLetterUnavailable(thread);
    return keys;
  }
  const ordinary = all(s, s.legacySaid ? LEGACY_PAGE_ORDINARY_KEYS : PAGE_ORDINARY_KEYS, thread, before, limit)
    .map((r) => r.n as string);
  if (token) {
    const letters = all(s, PAGE_LETTER_KEYS, thread, token, before, limit).map((r) => r.n as string);
    return descendingKeys([...ordinary, ...letters]).slice(0, limit);
  }
  const cap = limit + 64;
  const candidates = all(s, PAGE_LETTER_CANDIDATES, thread, before, cap);
  const floor = candidates.length === cap ? BigInt(candidates.at(-1)!.n as string) : null;
  const letters = candidates.filter((r) => r.kind === "message").map((r) => r.n as string);
  const knownOrdinary = floor === null ? ordinary : ordinary.filter((key) => BigInt(key) >= floor);
  const keys = descendingKeys([...knownOrdinary, ...letters]);
  if (keys.length < limit && floor !== null) throw new PageLetterUnavailable(thread);
  return keys.slice(0, limit);
}

// While the old ordinary-message lookup is being built or reconciled, a short source tail can still prove the page.
function unpreparedMessagePageKeys(s: Store, thread: number, before: number | bigint, limit: number,
  old: { preparing: boolean; needsDrain: boolean }): string[] {
  const pending = () => { throw old.preparing ? new LegacySaidUnavailable() : new SaidUnavailable([thread]); };
  if (!Number.isSafeInteger(limit) || limit < 0 || limit > Number.MAX_SAFE_INTEGER - 64) return pending();
  if (limit === 0) return [];
  const cap = limit + 64;
  const tail = all(s, LEGACY_SAID_PAGE_TAIL, thread, before, cap);
  const keys = tail.filter((r) => r.kind === "message").slice(0, limit).map((r) => r.n as string);
  if (keys.length < limit && tail.length === cap) return pending();
  return keys;
}

const ascendingKeys = (keys: string[]) => keys.sort((a, b) => BigInt(a) < BigInt(b) ? -1 : BigInt(a) > BigInt(b) ? 1 : 0);

// As with the descending message page, a capped raw probe proves a short page while an old lookup is preparing.
// A full probe with too few messages asks the existing background builder to prepare the needed lookup.
function messagePageKeysAfter(s: Store, thread: number, after: number | bigint, limit: number): string[] {
  const old = s.legacySaid ? legacySaidPageState(s.db, thread) : null;
  if (old && (old.preparing || old.needsDrain)) {
    const cap = limit + 64;
    const head = all(s, LEGACY_SAID_PAGE_HEAD, thread, after, cap);
    const keys = head.filter((r) => r.kind === "message").slice(0, limit).map((r) => r.n as string);
    if (keys.length < limit && head.length === cap)
      throw old.preparing ? new LegacySaidUnavailable() : new SaidUnavailable([thread]);
    return keys;
  }
  const token = pageLetterReady(s.db, thread);
  if (!token && !hasPageLetterIndex(s.db)) {
    const cap = limit + 64;
    const head = all(s, LEGACY_SAID_PAGE_HEAD, thread, after, cap);
    const keys = head.filter((r) => r.kind === "message").slice(0, limit).map((r) => r.n as string);
    if (keys.length < limit && head.length === cap) throw new PageLetterUnavailable(thread);
    return keys;
  }
  const ordinary = all(s, s.legacySaid ? LEGACY_PAGE_ORDINARY_KEYS_AFTER : PAGE_ORDINARY_KEYS_AFTER, thread, after, limit)
    .map((r) => r.n as string);
  if (token) {
    const letters = all(s, PAGE_LETTER_KEYS_AFTER, thread, token, after, limit).map((r) => r.n as string);
    return ascendingKeys([...ordinary, ...letters]).slice(0, limit);
  }
  const cap = limit + 64;
  const candidates = all(s, PAGE_LETTER_CANDIDATES_AFTER, thread, after, cap);
  const ceiling = candidates.length === cap ? BigInt(candidates.at(-1)!.n as string) : null;
  const letters = candidates.filter((r) => r.kind === "message").map((r) => r.n as string);
  const knownOrdinary = ceiling === null ? ordinary : ordinary.filter((key) => BigInt(key) <= ceiling);
  const keys = ascendingKeys([...knownOrdinary, ...letters]);
  if (keys.length < limit && ceiling !== null) throw new PageLetterUnavailable(thread);
  return keys.slice(0, limit);
}

/// Original message entries after a position, ordered and bounded without reading intervening edits.
export function messageEntriesAfter(s: Store, thread: number, after: number | bigint, limit: number): EntryRow[] {
  if (!Number.isSafeInteger(limit) || limit < 0 || limit > Number.MAX_SAFE_INTEGER - 64)
    throw new RangeError("message page limit is invalid");
  if (limit === 0) return [];
  s.db.exec("SAVEPOINT message_entries_after_read");
  try {
    const keys = messagePageKeysAfter(s, thread, after, limit);
    return keys.length === 0 ? [] : all(s, MESSAGE_PAGE_ENTRIES, thread, JSON.stringify(keys)).map(toEntry);
  } finally { s.db.exec("RELEASE message_entries_after_read"); }
}

/// The latest `limit` messages before n (the latest of all without it), as merged, oldest first.
export function messagesBefore(s: Store, thread: number, n: number | bigint | null, limit: number): MessageRow[] {
  const before = n ?? I64_MAX;
  s.db.exec("SAVEPOINT messages_before_read");
  try {
    const old = s.legacySaid ? legacySaidPageState(s.db, thread) : null;
    if (old && (old.preparing || old.needsDrain)) {
      const keys = unpreparedMessagePageKeys(s, thread, before, limit, old);
      if (keys.length === 0) return [];
      if (legacyMergedReadReady(s.db))
        return all(s, MESSAGES_FROM_KEYS, thread, JSON.stringify(keys)).map(toMessage).reverse();
      return keys.flatMap((key) => {
        const message = mergedWithBoundedEdit(s, thread, key);
        return message === null ? [] : [message];
      }).reverse();
    }
    // A negative limit is SQLite's request for every message. Preserve that existing contract; bounded pages use the
    // two key lookups so non-message letters and an absent letter index cannot make the reader walk a long history.
    if (limit < 0 || !Number.isSafeInteger(limit) || limit > Number.MAX_SAFE_INTEGER - 64) {
      if (legacyMergedReadReady(s.db))
        return all(s, s.legacySaid ? LEGACY_MESSAGES_BEFORE : MESSAGES_BEFORE, thread, before, limit).map(toMessage).reverse();
      const keys = s.legacySaid ? LEGACY_MESSAGE_KEYS_BEFORE : MESSAGE_KEYS_BEFORE;
      const page = all(s, `SELECT CAST(p.n AS TEXT) AS n FROM (${keys}) p ORDER BY p.n DESC`, thread, before, limit);
      return page.flatMap((r) => {
        const message = mergedWithBoundedEdit(s, thread, r.n);
        return message === null ? [] : [message];
      }).reverse();
    }
    if (limit === 0) return [];
    const page = boundedMessagePageKeys(s, thread, before, limit);
    if (page.length === 0) return [];
    if (legacyMergedReadReady(s.db))
      return all(s, MESSAGES_FROM_KEYS, thread, JSON.stringify(page)).map(toMessage).reverse();
    return page.flatMap((key) => {
      const message = mergedWithBoundedEdit(s, thread, key);
      return message === null ? [] : [message];
    }).reverse();
  } finally { s.db.exec("RELEASE messages_before_read"); }
}

// Whether an opener appears among the latest 200 messages. Author and author_kind are properties of the original
// entry, so this needs neither the merged view nor the history of its edits.
export function openedChatSaid(s: Store, thread: number, author: string, agentOnly: boolean): boolean {
  s.db.exec("SAVEPOINT opened_chat_said_read");
  try {
    const old = s.legacySaid ? legacySaidPageState(s.db, thread) : null;
    const keys = old && (old.preparing || old.needsDrain)
      ? unpreparedMessagePageKeys(s, thread, I64_MAX, 200, old)
      : boundedMessagePageKeys(s, thread, I64_MAX, 200);
    if (keys.length === 0) return false;
    return one(s, `SELECT 1 FROM json_each(?2) j CROSS JOIN entries e
      ON e.thread=?1 AND e.n=CAST(j.value AS INTEGER)
      WHERE e.author=?3 AND (?4=0 OR e.author_kind='agent') LIMIT 1`,
      thread, JSON.stringify(keys), author, agentOnly ? 1 : 0) !== undefined;
  } finally { s.db.exec("RELEASE opened_chat_said_read"); }
}

// The boundary identifies a message, so resolving it does not need the merged view's edit lookup.
export const CHAT_HISTORY_BOUNDARY = "SELECT CAST(n AS TEXT) AS n FROM entries WHERE thread = ? AND ts = ? AND kind = 'message'";

/// A chat_history page and its before-message lookup in one snapshot. Null means the requested boundary was not found.
export function chatHistoryMessages(s: Store, thread: number, before: string | null, limit: number): MessageRow[] | null {
  s.db.exec("SAVEPOINT chat_history_messages_read");
  try {
    const boundary = before === null ? null : one(s, CHAT_HISTORY_BOUNDARY, thread, before);
    if (before !== null && !boundary) return null;
    return messagesBefore(s, thread, boundary ? BigInt(boundary.n) : null, limit);
  } finally { s.db.exec("RELEASE chat_history_messages_read"); }
}

// ── the archive review ──

/// Whether the decision recommended the thread for the archive as it stands now (its last entry then is its last now).
/// Of `threads`, those the archive review suggested or judged (archive_suggestions, archive_verdicts): what
/// `archiveSuggested` and `archiveVerdict` say anything of.
export function reviewedThreads(s: Store, threads: number[]): number[] {
  const list = JSON.stringify(threads);
  return all(s, `SELECT thread FROM archive_suggestions WHERE thread IN (SELECT value FROM json_each(?1))
    UNION SELECT thread FROM archive_verdicts WHERE thread IN (SELECT value FROM json_each(?1))`, list).map((r) => r.thread as number);
}

export function archiveSuggested(s: Store, thread: number): boolean {
  const version = one(s, "SELECT version FROM archive_suggestions WHERE thread = ?", thread)?.version ?? null;
  return version !== null && version === lastEntry(s, thread);
}

/// What the latest review found for the thread, while it stands as it was then: the option picked (`option`, `name`,
/// `archive`) or the failure (`error`), and when.
export function archiveVerdict(s: Store, thread: number): Json | null {
  const r = one(s, "SELECT version, at, verdict FROM archive_verdicts WHERE thread = ?", thread);
  if (!r || r.version !== lastEntry(s, thread)) return null;
  const v = parsed(r.verdict);
  return v && typeof v === "object" ? { ...v, at: r.at } : null;
}

// ── chats shared with other workspaces (chat_shares) ──

// What a sidebar's items a change touched, or a chat, are read by: theirs alone, each by its key (`?`: a JSON list of
// them). The rows of every chat ever shared or opened were read at each sidebar change and each chat told.
export const SHARES_OF = "SELECT * FROM chat_shares WHERE session IN (SELECT value FROM json_each(?))";
const OPENERS = "SELECT o.child, o.parent_station, o.parent, o.opener_title, p.title AS parent_title FROM opened_chats o LEFT JOIN sessions p ON o.parent_station = '' AND p.key = o.parent";
export const OPENERS_OF = `${OPENERS} WHERE o.child_station = '' AND o.child IN (SELECT value FROM json_each(?))`;
const OPENED = "SELECT o.parent, o.child_station, o.child, o.title, c.title AS child_title FROM opened_chats o LEFT JOIN sessions c ON o.child_station = '' AND c.key = o.child";
export const OPENED_OF = `${OPENED} WHERE o.parent_station = '' AND o.parent IN (SELECT value FROM json_each(?)) ORDER BY o.created_at, o.rowid`;

/// What each chat shared with other workspaces is shared with now (its shares not lapsed, store/rows.ts), by the
/// session key its link names (none on a database from before the table): of those `sessions` name alone (a sidebar's
/// items a change touched, a chat), or of all.
export function chatShares(s: Store, sessions: string[] | null = null): Map<string, { to: { workspace: string; name: string }[]; write: boolean; by: string; at: number }> {
  let rows: Json[];
  try {
    rows = sessions === null ? all(s, "SELECT * FROM chat_shares") : all(s, SHARES_OF, JSON.stringify(sessions));
  } catch {
    return new Map();
  }
  const now = nowMs();
  return new Map(
    rows.flatMap((r) => {
      const share = liveShare(toChatShare(r), now);
      return share === null ? [] : [[r.session, { ...share, to: share.to.map(({ workspace, name }) => ({ workspace, name })) }] as const];
    }),
  );
}

// ── chats an agent opened (opened_chats) ──

/// The chats of this station another agent opened (chat_create), by their session's key: the session that opened each,
/// on its station (null: this one), and what it was called then, else (one of this station's, opened before that was
/// kept) its session's title. None on a database from before the table or the column.
/// Of those `children` name alone (a sidebar's items a change touched), or of all.
export function openers(s: Store, children: string[] | null = null): Map<string, { station: string | null; session: string; title: string | null }> {
  let rows: Json[];
  try {
    rows = children === null ? all(s, `${OPENERS} WHERE o.child_station = ''`) : all(s, OPENERS_OF, JSON.stringify(children));
  } catch {
    return new Map();
  }
  return new Map(
    rows.map((r) => [
      r.child as string,
      { station: r.parent_station === "" ? null : (r.parent_station as string), session: r.parent as string, title: (r.opener_title ?? r.parent_title ?? null) as string | null },
    ]),
  );
}

/// The chats each session of this station opened (chat_create), by its key, the first first: each on its station
/// (null: this one), its session, and its title as given then, else (one of this station's) its session's.
/// Of those `parents` name alone (a sidebar's items a change touched), or of all.
export function openedChats(s: Store, parents: string[] | null = null): Map<string, { station: string | null; session: string; title: string | null }[]> {
  let rows: Json[];
  try {
    rows = parents === null ? all(s, `${OPENED} WHERE o.parent_station = '' ORDER BY o.created_at, o.rowid`) : all(s, OPENED_OF, JSON.stringify(parents));
  } catch {
    return new Map();
  }
  const out = new Map<string, { station: string | null; session: string; title: string | null }[]>();
  for (const r of rows) {
    const list = out.get(r.parent) ?? [];
    list.push({ station: r.child_station === "" ? null : (r.child_station as string), session: r.child as string, title: (r.title ?? r.child_title ?? null) as string | null });
    out.set(r.parent, list);
  }
  return out;
}

// ── pins, kept chats ──

/// The chats a viewer pinned (by their session's key), with when. For an incremental read, seek only its keys.
export const PINS_OF = "SELECT session, at FROM pins WHERE viewer = ?1 AND session IN (SELECT value FROM json_each(?2))";
export function pins(s: Store, viewer: string, sessions: string[] | null = null): Map<string, number> {
  const found = sessions === null ? all(s, "SELECT session, at FROM pins WHERE viewer = ?", viewer)
    : sessions.length === 0 ? [] : all(s, PINS_OF, viewer, JSON.stringify(sessions));
  return new Map(found.map((r) => [r.session, r.at]));
}

/// Chats kept instead of offered for archiving. Null selects every viewer.
export function keptChats(s: Store, viewer: string | null, threads: number[] | null = null): Set<number> {
  const rows = viewer === null ? all(s, "SELECT DISTINCT thread FROM kept_chats")
    : threads === null ? all(s, "SELECT thread FROM kept_chats WHERE viewer = ?1", viewer)
    : [...new Set(threads)].flatMap((thread) => all(s, "SELECT thread FROM kept_chats WHERE viewer = ? AND thread = ?", viewer, thread));
  return new Set(rows.map((r) => r.thread));
}

// ── cards ──

/// The thread's card still pending, if any: its latest post with a card, as long as no person has written in the
/// thread since (nor was it closed). The post as merged, and its card.
export function pendingCard(s: Store, thread: number): [MessageRow, Json] | null {
  s.db.exec("SAVEPOINT pending_card_read");
  try {
    if (!cardPostsReady(s.db, thread)) {
      if (threadsWithCards(s, [thread]).length === 0) return null;
      throw new Refused(503, CARD_POSTS_PENDING + JSON.stringify([thread]));
    }
    const asked = one(s, CARD_POST_LATEST, thread);
    return asked === undefined ? null : cardAt(s, thread, asked.n);
  } finally { s.db.exec("RELEASE pending_card_read"); }
}

/// The pending post's number for chat history. Its merged text is not needed to mark a card as pending.
export function pendingCardNumber(s: Store, thread: number): number | null {
  s.db.exec("SAVEPOINT pending_card_number_read");
  try {
    if (!cardPostsReady(s.db, thread)) {
      // An older connection can remove either old index while this thread is still being prepared. In that case
      // prepare the card-post index by bounded primary-key pages instead of probing an index that no longer exists.
      const indexed = one(s, "SELECT COUNT(*) AS n FROM sqlite_master WHERE type = 'index' AND name IN ('entries_cards', 'entries_options')")?.n === 2;
      if (indexed && threadsWithCards(s, [thread]).length === 0) return null;
      throw new Refused(503, CARD_POSTS_PENDING + JSON.stringify([thread]));
    }
    const asked = one(s, CARD_POST_LATEST, thread);
    if (asked === undefined) return null;
    const post = one(s, "SELECT card, options FROM entries WHERE thread = ? AND n = ? AND kind = 'message'", thread, asked.n);
    if (!post || cardOf(post.card, post.options) === undefined) return null;
    if (one(s, "SELECT 1 FROM entries WHERE thread = ? AND kind = 'message' AND author_kind = 'person' AND n > ? LIMIT 1", thread, asked.n)) return null;
    if (one(s, "SELECT 1 FROM closed_cards WHERE thread = ? AND n = ?", thread, asked.n)) return null;
    return asked.n;
  } finally { s.db.exec("RELEASE pending_card_number_read"); }
}

/// The latest pending card a need can point to. Its original timestamp and time never depend on edits.
export function statePendingCard(s: Store, threads: number[]): [number, number, string] | null {
  s.db.exec("SAVEPOINT state_pending_card_read");
  try {
    const cards: { thread: number; n: number; ts: string; at: number }[] = [];
    for (const thread of threads) {
      const n = pendingCardNumber(s, thread);
      if (n === null) continue;
      const row = one(s, "SELECT ts, at FROM entries WHERE thread = ? AND n = ? AND kind = 'message'", thread, n);
      if (row) cards.push({ thread, n, ts: row.ts ?? "", at: row.at });
    }
    cards.sort((a, b) => a.at - b.at);
    const last = cards.at(-1);
    return last ? [last.thread, last.n, last.ts] : null;
  } finally { s.db.exec("RELEASE state_pending_card_read"); }
}

/// The visible question a need names, checked together with whether it is still answerable.
export type StateQuestion =
  | { kind: "missing" }
  | { kind: "invalid" }
  | { kind: "answered" }
  | { kind: "found"; about: [number, number, string] };

export function stateQuestion(s: Store, key: string, threads: number[], ts: string): StateQuestion {
  s.db.exec("SAVEPOINT state_question_read");
  try {
    for (const thread of threads) {
      const entry = one(s, "SELECT n, card, options FROM entries WHERE thread = ? AND ts = ? AND kind = 'message'", thread, ts);
      if (!entry) continue;
      // A missing native index must be replaced even if the recent tail could answer this one question: confirmation
      // after unrelated concurrent writes also needs a bounded lookup.
      if (legacyMergedNeedsRepair(s.db)) throw new LegacyEditsUnavailable();
      let m: MessageRow | null;
      if (legacyMergedReadReady(s.db)) {
        const row = one(s, "SELECT * FROM merged WHERE thread = ? AND n = ?", thread, entry.n);
        m = row ? toMessage(row) : null;
      } else m = mergedWithBoundedEdit(s, thread, String(entry.n));
      if (!m) continue;
      if (m.authorKind !== "agent" || m.author !== key || m.text.trim() === "") return { kind: "invalid" };
      const carded = entry.card != null || entry.options != null;
      const answered = carded ? pendingCardNumber(s, thread) !== m.n
        : one(s, "SELECT 1 FROM entries WHERE thread = ? AND kind = 'message' AND author_kind = 'person' AND n > ? LIMIT 1", thread, m.n) !== undefined;
      return answered ? { kind: "answered" } : { kind: "found", about: [m.thread, m.n, m.ts] };
    }
    return { kind: "missing" };
  } finally { s.db.exec("RELEASE state_question_read"); }
}

/// The card state delivered with a person's message. Its author, timestamp and original card do not depend on edits.
export function deliveryCardState(s: Store, thread: number, n: number): DeliveryCardState | null {
  s.db.exec("SAVEPOINT delivery_card_state_read");
  try {
    if (!one(s, "SELECT 1 FROM entries WHERE thread = ? AND n = ? AND kind = 'message' AND author_kind = 'person'", thread, n)) return null;
    if (!cardPostsReady(s.db, thread)) {
      if (threadsWithCards(s, [thread]).length === 0) return null;
      throw new Refused(503, CARD_POSTS_PENDING + JSON.stringify([thread]));
    }
    const asked = one(s, CARD_POST_BEFORE, thread, n)?.n;
    if (asked === null || asked === undefined) return null;
    if (one(s, "SELECT 1 FROM entries WHERE thread = ? AND kind = 'message' AND author_kind = 'person' AND n > ? AND n < ? LIMIT 1", thread, asked, n)) return null;
    if (one(s, "SELECT 1 FROM closed_cards WHERE thread = ? AND n = ?", thread, asked)) return null;
    const post = one(s, "SELECT ts, author, card, options FROM entries WHERE thread = ? AND n = ? AND kind = 'message'", thread, asked);
    if (!post) return null;
    const card = cardOf(post.card, post.options);
    if (card === undefined) return null;
    const currentN = pendingCardNumber(s, thread);
    const current = currentN === null ? null : one(s, "SELECT ts FROM entries WHERE thread = ? AND n = ? AND kind = 'message'", thread, currentN) ?? null;
    return { ended: { author: post.author, ts: post.ts ?? "" }, card, current: current === null ? null : { ts: current.ts ?? "" } };
  } finally { s.db.exec("RELEASE delivery_card_state_read"); }
}

/// Prepare only threads a read will actually ask about, together so a list is not rebuilt once per old chat.
export function requireCardPosts(s: Store, threads: readonly number[]): void {
  const missing = [...new Set(threads)].filter((thread) => !cardPostsReady(s.db, thread));
  if (missing.length) throw new Refused(503, CARD_POSTS_PENDING + JSON.stringify(missing));
}

/// The cards `threads` wait on as kept (store/schema.ts PENDING_CARDS): by thread, the post's entry (`at`); and those of
/// them with a card posted before it was kept (`before`), whose card is read as `pendingCard` reads it. Null where a
/// database from before keeps none.
export function pendingCards(s: Store, threads: number[]): { at: Map<number, number>; before: Set<number> } | null {
  let from: number;
  try {
    from = one(s, "SELECT entry FROM pending_cards_from WHERE id = 1")?.entry ?? 0;
  } catch {
    return null;
  }
  const list = JSON.stringify(threads);
  const at = new Map<number, number>(all(s, "SELECT thread, n FROM pending_cards WHERE thread IN (SELECT value FROM json_each(?))", list).map((r) => [r.thread, r.n]));
  // A card or options posted before the cards were kept, by their own indexes: the chat's first of each.
  const before = new Set<number>(
    threads.filter((t) => !at.has(t) && (
      one(s, "SELECT rowid FROM entries INDEXED BY entries_cards WHERE thread = ? AND card IS NOT NULL ORDER BY n LIMIT 1", t)?.rowid <= from ||
      one(s, "SELECT rowid FROM entries INDEXED BY entries_options WHERE thread = ? AND options IS NOT NULL ORDER BY n LIMIT 1", t)?.rowid <= from)),
  );
  return { at, before };
}

/// Of `threads`, those that ever had a card or options posted, each by their own indexes.
export function threadsWithCards(s: Store, threads: number[]): number[] {
  return threads.filter((t) =>
    one(s, "SELECT 1 FROM entries INDEXED BY entries_cards WHERE thread = ? AND card IS NOT NULL LIMIT 1", t) !== undefined ||
    one(s, "SELECT 1 FROM entries INDEXED BY entries_options WHERE thread = ? AND options IS NOT NULL LIMIT 1", t) !== undefined);
}

/// The card a thread waits on as kept (`n`, pendingCards), as `pendingCard` gives it; null where it no longer waits
/// (closed, or a person wrote since).
export function cardAt(s: Store, thread: number, n: number): [MessageRow, Json] | null {
  s.db.exec("SAVEPOINT card_at_read");
  try {
    const asked = one(s, "SELECT card, options FROM entries WHERE thread = ? AND n = ?", thread, n);
    if (!asked) return null;
    const answered = one(s, "SELECT 1 FROM entries WHERE thread = ? AND kind = 'message' AND author_kind = 'person' AND n > ? LIMIT 1", thread, n) !== undefined;
    const closed = one(s, "SELECT 1 FROM closed_cards WHERE thread = ? AND n = ?", thread, n) !== undefined;
    if (answered || closed) return null;
    const card = cardOf(asked.card, asked.options);
    if (card === undefined) return null;
    if (!legacyMergedReadReady(s.db)) {
      const message = mergedWithBoundedEdit(s, thread, String(n));
      return message ? [message, card] : null;
    }
    const m = one(s, "SELECT * FROM merged WHERE thread = ? AND n = ?", thread, n);
    return m ? [toMessage(m), card] : null;
  } finally { s.db.exec("RELEASE card_at_read"); }
}

/// An agent's latest message in a chat during a turn (`?2` to `?3`, ms), by the index of agents' messages by time (store/
/// schema.ts entries_agent_at): by the chat alone, all it had was read for it.
export const ASKED_DURING = "SELECT max(n) AS n FROM entries WHERE thread = ? AND kind = 'message' AND author_kind = 'agent' AND at >= ? AND at <= ?";

/// The message an agent's need without a card asks with, while no person has written after it: the one its turn is
/// about (`about`), else the agent's latest message during the turn; with the two messages before it.
export function askingMessage(s: Store, thread: number, about: number | null, during: [number, number | bigint]): [MessageRow, MessageRow[]] | null {
  const n: number | null = about ?? one(s, s.legacyAgent ? LEGACY_ASKED_DURING : ASKED_DURING, thread, during[0], during[1]).n;
  if (n === null) return null;
  const answered = one(s, "SELECT 1 FROM entries WHERE thread = ? AND kind = 'message' AND author_kind = 'person' AND n > ? LIMIT 1", thread, n) !== undefined;
  // A post with a card is pending_card's: one no longer pending was answered, closed or withdrawn.
  const carded = one(s, "SELECT 1 FROM entries WHERE thread = ? AND n = ? AND (card IS NOT NULL OR options IS NOT NULL)", thread, n) !== undefined;
  if (answered || carded) return null;
  const messages = messagesBefore(s, thread, n + 1, 3);
  const m = messages.pop();
  return m && m.n === n && m.authorKind === "agent" ? [m, messages] : null;
}

/// A turn of a session that ended blocked between two times (ms), in any of the words a turn's end is kept in (today's,
/// need_help and need_decision, and block from before: store/rows.ts `saidBefore`), by the index of its turns by their
/// end. Asked as `block` alone, none of today's matched (each blocked ask was told again at every turn that ended on
/// it), and by the session's turns from its first, every turn it had was read: many for one on a station (2026-11-02).
export const TOLD_BLOCKED =
  "SELECT 1 FROM turns WHERE session_key = ? AND ended_at >= ? AND ended_at < ? AND declared IN ('block', 'need_help', 'need_human', 'need_decision') LIMIT 1";

/// What a turn of `key` that ended blocked asks the thread's people, as the sidebar and 待处理 show it, and whether it is
/// new: its card still pending, else the message its need asks with (`askingMessage`); null when nothing there waits
/// for them (answered since, or never asked in it). Not new when an earlier turn of `key` ended blocked after it was
/// posted: it has waited since, and they were told then.
export function blockedAsk(s: Store, thread: number, key: string, turn: TurnSummary): { asked: MessageRow; fresh: boolean } | null {
  const about = turn.about as Json;
  const seq = about !== null && typeof about === "object" && about.thread === thread && Number.isInteger(about.seq) ? about.seq : null;
  const started = Number.isInteger(turn.startedAt) ? (turn.startedAt as number) : 0;
  const ended: number | bigint = Number.isInteger(turn.endedAt) ? (turn.endedAt as number) : I64_MAX;
  const asked = pendingCard(s, thread)?.[0] ?? askingMessage(s, thread, seq, [started, ended])?.[0] ?? null;
  if (asked === null) return null;
  const told = one(s, TOLD_BLOCKED, key, asked.createdAt, started) !== undefined;
  return { asked, fresh: !told };
}

/// A short card history can be checked by its cards; beyond this, look at recent people instead of all old cards.
const ANSWER_CARD_SAMPLE_SIZE = 65;
export const HAS_ANSWER_PEOPLE_SINCE = `SELECT 1 FROM entries INDEXED BY entries_people_since
  WHERE thread = ? AND author_kind = 'person' AND kind = 'message' AND at >= ? LIMIT 1`;
export const FIRST_ANSWER_PERSON_SINCE = `SELECT MIN(n) AS n FROM entries INDEXED BY entries_people_since
  WHERE thread = ? AND author_kind = 'person' AND kind = 'message' AND at >= ?`;
export const ANSWER_PEOPLE_AFTER = `SELECT thread, n FROM entries INDEXED BY entries_people_since
  WHERE thread = ? AND author_kind = 'person' AND kind = 'message' AND at >= ? AND n > ? ORDER BY n`;
export const ANSWER_NEXT_PERSON = `SELECT n, at FROM entries INDEXED BY entries_people_by_n
  WHERE thread = ? AND author_kind = 'person' AND kind = 'message' AND n > ? ORDER BY n LIMIT 1`;

type PeopleTimeMode = "native" | "legacy" | "small";
type AnswerMode = PeopleTimeMode | "cards";
const peopleTimePending = (threads: number[]): never => { throw new Refused(503,PEOPLE_TIME_PENDING + JSON.stringify(threads)); };
const smallPeople = (s: Store, thread: number, since: number): Json => {
  const row = one(s,SMALL_PEOPLE_HAS,thread,since)!;
  if (row.seen >= PEOPLE_TIME_SAMPLE_LIMIT) peopleTimePending([thread]);
  return row;
};
const hasRecentPeople = (s: Store, thread: number, since: number, mode: PeopleTimeMode): boolean =>
  mode === "small" ? smallPeople(s,thread,since).yes === 1
    : one(s,mode === "native" ? HAS_ANSWER_PEOPLE_SINCE : LEGACY_HAS_PEOPLE_SINCE,thread,since) !== undefined;
const firstRecentPerson = (s: Store, thread: number, since: number, mode: PeopleTimeMode): number | null => {
  const row = one(s,mode === "native" ? FIRST_ANSWER_PERSON_SINCE : mode === "legacy" ? LEGACY_FIRST_PERSON_SINCE : SMALL_PEOPLE_FIRST,thread,since)!;
  if (mode === "small" && row.seen >= PEOPLE_TIME_SAMPLE_LIMIT) peopleTimePending([thread]);
  return row.n as number | null;
};
const peopleAfter = (s: Store, thread: number, since: number, n: number, mode: PeopleTimeMode): { thread: number; n: number }[] => {
  const result = all(s,mode === "native" ? ANSWER_PEOPLE_AFTER : mode === "legacy" ? LEGACY_PEOPLE_AFTER : SMALL_PEOPLE_AFTER,thread,since,n);
  if (mode === "small" && result.some((row) => row.seen >= PEOPLE_TIME_SAMPLE_LIMIT)) peopleTimePending([thread]);
  return result.filter((row) => row.n !== null).map((row) => ({ thread: row.thread, n: row.n }));
};

/// The people's messages since `since` (ms) in a thread that each are the first after a card (the last before it), in
/// order. With many old cards, seek from a person to the next card and its first person, skipping ordinary messages.
function answersOf(s: Store, thread: number, since: number, mode: AnswerMode): { thread: number; n: number }[] {
  if (mode !== "cards" && !hasRecentPeople(s,thread,since,mode)) return [];
  const cardRows = all(s, CARD_POST_SAMPLE, thread);
  if (cardRows.length >= ANSWER_CARD_SAMPLE_SIZE) {
    // Direct callers need not hold a read snapshot: a new card could have arrived since the short-card probe.
    const timeMode: PeopleTimeMode = mode === "cards" ? peopleTimePending([thread]) : mode;
    const nextCard = (n: number): number | null => {
      return (one(s, CARD_POST_NEXT, thread, n)?.n as number | undefined) ?? null;
    };
    const firstCard = nextCard(0);
    if (firstCard === null) return [];
    const firstPerson = one(s, ANSWER_NEXT_PERSON, thread, firstCard);
    if (firstPerson === undefined) return [];
    // If the first answer is already recent, no earlier answer exists. Otherwise find the first recent person by
    // the time index, so old answered cards do not have to be visited. Times need not follow entry order.
    const first = firstPerson.at >= since ? firstPerson.n as number : firstRecentPerson(s,thread,since,timeMode);
    if (first === null) return [];
    const out = [{ thread, n: first }];
    let n = first;
    let older = 0;
    for (;;) {
      // Include a card carried by the person's own message; it can be answered by the next person.
      const card = nextCard(n);
      if (card === null) return out;
      const person = one(s, ANSWER_NEXT_PERSON, thread, card);
      if (person === undefined) return out;
      n = person.n as number;
      if (person.at >= since) out.push({ thread, n });
      else if (++older >= ANSWER_CARD_SAMPLE_SIZE) {
        // If timestamps are far out of sequence, finish by the time index instead of walking old answers.
        return out.concat(peopleAfter(s,thread,since,n,timeMode));
      }
    }
  }
  const cards = cardRows.map((r) => r.n as number);
  const out: { thread: number; n: number }[] = [];
  cards.forEach((card, i) => {
    const next = one(s, "SELECT n, at FROM entries WHERE thread = ? AND author_kind = 'person' AND kind = 'message' AND n > ? ORDER BY n LIMIT 1", thread, card);
    if (next === undefined || next.at < since) return;
    if (i + 1 < cards.length && cards[i + 1]! < next.n) return;
    out.push({ thread, n: next.n });
  });
  return out;
}

/// The cards answered since `since` (ms), whoever answered them: each a person's first message after a card, or a
/// choice that closed it (closed_cards, by a person: not its agent withdrawing it).
export function answersSince(s: Store, since: number, threads: number[]): CardAnswer[] {
  if (threads.length === 0) return [];
  s.db.exec("SAVEPOINT answers_since_read");
  try { return answersSinceInSnapshot(s, since, threads); }
  finally { s.db.exec("RELEASE answers_since_read"); }
}

function answersSinceInSnapshot(s: Store, since: number, threads: number[]): CardAnswer[] {
  const out: CardAnswer[] = [];
  // Only the requested chats (the items a sidebar change touched) are read.
  const scope = [...new Set(threads)];
  if (!scope.length) return out;
  const nativeClosed = hasNativeClosedCards(s.db);
  const legacyClosed = !nativeClosed && hasLegacyClosedCards(s.db);
  const smallClosed = new Map<number, Json[]>();
  let recentClosed: Json[] | null = null;
  if (!nativeClosed) {
    const missing = scope.filter((thread) => !closedCardsReady(s.db, thread));
    if (missing.length && hasClosedCardsTimeIndex(s.db)) {
      // An existing older index is useful when the whole recent window is small, but never walk an unbounded window.
      try {
        const recent = all(s, CLOSED_TIME_SAMPLE, since, JSON.stringify(scope));
        if (recent.length < CLOSED_SAMPLE_LIMIT) {
          const wanted = new Set(scope);
          const byThread = new Map<number, Json[]>();
          for (const row of recent) if (wanted.has(row.thread)) {
            const found = byThread.get(row.thread) ?? [];
            found.push(row); byThread.set(row.thread, found);
          }
          recentClosed = scope.flatMap((thread) => byThread.get(thread) ?? []);
        }
      } catch (error) {
        if (!(error as Error).message.includes("no such index: closed_cards_at")) throw error;
      }
    }
    if (recentClosed === null) {
      const waiting: number[] = [];
      for (const thread of missing) {
        const sample = all(s, CLOSED_CHAT_SAMPLE, thread, since);
        if (sample.length < CLOSED_SAMPLE_LIMIT) smallClosed.set(thread, sample.filter((row) => row.n !== null));
        else waiting.push(thread);
      }
      if (waiting.length) throw new Refused(503, CLOSED_CARDS_PENDING + JSON.stringify(waiting));
    }
  }
  const nativePeople = hasNativePeopleSince(s.db);
  const modes = new Map<number,AnswerMode>();
  let said: { thread: number; n: number }[];
  try {
    let relevant: number[];
    if (nativePeople) {
      const withPeople = scope.filter((thread) => hasRecentPeople(s,thread,since,"native"));
      const carded = new Set(threadsWithCards(s,withPeople));
      relevant = withPeople.filter((thread) => carded.has(thread));
      for (const thread of relevant) modes.set(thread,"native");
    } else {
      // A cardless chat needs no people lookup. Short chats can answer from at most 65 entries without waiting.
      const carded = threadsWithCards(s,scope), waiting: number[] = [];
      relevant = [];
      for (const thread of carded) {
        // When the card-post lookup is ready and small, seek the first person after each card. Its cost is bounded
        // by the cards, even if this chat has a long history and the old people-time lookup is not prepared yet.
        if (cardPostsReady(s.db,thread) && all(s,CARD_POST_SAMPLE,thread).length < ANSWER_CARD_SAMPLE_SIZE) {
          modes.set(thread,"cards"); relevant.push(thread); continue;
        }
        const mode: PeopleTimeMode = hasLegacyPeopleSince(s.db) && peopleSinceReady(s.db,thread) ? "legacy" : "small";
        if (mode === "small") {
          const probe = one(s,SMALL_PEOPLE_HAS,thread,since)!;
          if (probe.seen >= PEOPLE_TIME_SAMPLE_LIMIT) { waiting.push(thread); continue; }
          if (probe.yes !== 1) continue;
        } else if (!hasRecentPeople(s,thread,since,mode)) continue;
        modes.set(thread,mode); relevant.push(thread);
      }
      if (waiting.length) peopleTimePending(waiting);
    }
    requireCardPosts(s,relevant);
    said = relevant.flatMap((thread) => answersOf(s,thread,since,modes.get(thread)!));
  } catch (error) {
    // A direct caller need not hold the worker's snapshot; an older connection may have removed the native index.
    if (nativePeople && (error as Error).message.includes("no such index: entries_people_since")) peopleTimePending(scope);
    throw error;
  }
  const askedBefore = (thread: number, n: number): number | null => {
    return one(s, CARD_POST_BEFORE, thread, n).n as number | null;
  };
  let mergedReady: boolean | undefined;
  const messageAt = (thread: number, n: number): MessageRow | null => {
    mergedReady ??= legacyMergedReadReady(s.db);
    if (!mergedReady) return mergedWithBoundedEdit(s, thread, String(n));
    const m = one(s, "SELECT * FROM merged WHERE thread = ? AND n = ?", thread, n);
    return m ? toMessage(m) : null;
  };
  const cardAt = (thread: number, n: number): [MessageRow, Json] | null => {
    const row = one(s, "SELECT card, options FROM entries WHERE thread = ? AND n = ?", thread, n);
    const card = row ? cardOf(row.card, row.options) : undefined;
    if (card === undefined) return null;
    const m = messageAt(thread, n);
    return m ? [m, card] : null;
  };
  for (const { thread, n } of said) {
    const asked = askedBefore(thread, n);
    if (asked === null) continue;
    // Only the first word after it answers it; one closed (by a choice or withdrawn) was answered then.
    const earlier = one(s, "SELECT 1 FROM entries WHERE thread = ? AND kind = 'message' AND author_kind = 'person' AND n > ? AND n < ? LIMIT 1", thread, asked, n) !== undefined;
    const closed = one(s, "SELECT 1 FROM closed_cards WHERE thread = ? AND n = ?", thread, asked) !== undefined;
    if (earlier || closed) continue;
    const found = cardAt(thread, asked);
    if (!found) continue;
    const answer = messageAt(thread, n);
    if (!answer) continue;
    out.push({ question: found[0], card: found[1], by: answer.author, at: answer.createdAt, answer });
  }
  let closedRows: Json[];
  try {
    closedRows = recentClosed ?? scope.flatMap((thread) => nativeClosed ? all(s, CLOSED_CARDS_INDEXED, thread, since)
      : smallClosed.get(thread) ?? (legacyClosed ? all(s, LEGACY_CLOSED_CARDS, thread, since) : []));
  } catch (error) {
    // A direct caller need not hold the reader worker's snapshot; an older connection may have dropped the index.
    if (nativeClosed && (error as Error).message.includes("no such index: closed_cards_thread_at"))
      throw new Refused(503, CLOSED_CARDS_PENDING + JSON.stringify(scope));
    throw error;
  }
  closedRows.sort((a, b) => a.at - b.at || a.ordering - b.ordering);
  for (const { thread, n, viewer: by, at } of closedRows) {
    const found = cardAt(thread, n);
    if (!found) continue;
    // Withdrawn by its own agent: no one answered it.
    if (found[0].author === by) continue;
    out.push({ question: found[0], card: found[1], by, at, answer: null });
  }
  return out;
}

/// The cards a viewer dismissed, as "thread:n".
export function dismissed(s: Store, viewer: string, threads: number[] | null = null): Set<string> {
  const rows = threads === null
    ? all(s, "SELECT thread, n FROM dismissed WHERE viewer = ?", viewer)
    : [...new Set(threads)].flatMap((thread) => all(s, "SELECT thread, n FROM dismissed WHERE viewer = ? AND thread = ?", viewer, thread));
  return new Set(rows.map((r) => `${r.thread}:${r.n}`));
}

// ── identities ──

/// The Slack users a viewer said are them: their messages are the viewer's own.
export function slackIdentities(s: Store, viewer: string): string[] {
  return all(s, "SELECT slack_user FROM identities WHERE viewer = ? ORDER BY at", viewer).map((r) => r.slack_user);
}

// ── turns ──

/// TurnSummary from a turns row (or session_stats' `l.*`), as serde writes it.
function turnSummary(r: Json, startedAt: number): TurnSummary {
  const v: TurnSummary = {
    kind: r.kind,
    outcome: r.outcome,
    declared: r.declared === null ? null : saidBefore(r.declared),
  };
  if (r.declared !== null) v.ending = ending(r.declared);
  if (r.need !== null) v.need = r.need;
  if (r.about_thread !== null && r.about_n !== null && r.about_ts !== null) v.about = { thread: r.about_thread, seq: r.about_n, ts: r.about_ts };
  if (r.wait_seconds !== null) v.waitSeconds = r.wait_seconds;
  if (r.wait_for !== null) v.waitFor = r.wait_for;
  if (r.wait_watch !== null && r.wait_watch !== undefined) v.waitWatch = r.wait_watch === 1;
  v.detail = r.detail;
  v.startedAt = startedAt;
  v.endedAt = r.ended_at;
  return v;
}

/// Each session's counts and last turn (`sessionStats`), each by a lookup the size of what it finds: its turns as the
/// database keeps them counted (store/schema.ts SESSION_TURNS), its messages not delivered yet by the index of those
/// alone (as store.ts STATS_OF), its first words and its latest turn. Its every turn counted and its every delivery read
/// (the deliveries by session and thread), each summary of a long session read some 65 pages, from the disk on a station
/// short of memory (2026-11-02), as often as the session changed.
const SESSION_PENDING = `((SELECT COUNT(*) FROM deliveries d INDEXED BY deliveries_pending WHERE d.session = s.key AND d.delivered_at IS NULL) +
         (SELECT COUNT(*) FROM letter_deliveries d WHERE d.session = s.key AND d.delivered_at IS NULL)) AS pending`;
const SESSION_LAST_FIELDS = `l.id AS turn_id, l.kind, l.outcome, l.declared, l.wait_seconds, l.wait_for, l.wait_watch, l.need, l.about_thread, l.about_n, l.about_ts, l.detail, l.started_at, l.ended_at`;
const SESSION_LAST_FROM = `FROM sessions s
     LEFT JOIN turns l ON l.id = (SELECT id FROM turns t2 WHERE t2.session_key = s.key ORDER BY t2.started_at DESC LIMIT 1)`;

export const SESSION_STATS = `SELECT s.key,
       COALESCE((SELECT c.n FROM session_turns c WHERE c.session = s.key),
         (SELECT CASE WHEN COUNT(*) <= ${TURN_COUNT_BATCH} THEN COUNT(*) END FROM
           (SELECT 1 FROM turns old INDEXED BY turns_by_session WHERE old.session_key = s.key LIMIT ${TURN_COUNT_BATCH + 1}))) AS turns,
       -- How long its turns ran, where every one ended since that was kept (schema.ts SESSION_WORK); else none.
       CASE WHEN NOT EXISTS (SELECT 1 FROM turns o INDEXED BY turns_by_end WHERE o.session_key = s.key AND o.ended_at <= (SELECT f.at FROM session_work_from f WHERE f.id = 1))
         THEN COALESCE((SELECT w.ms FROM session_work w WHERE w.session = s.key), 0) END AS work_ms,
       ${SESSION_PENDING},
       (SELECT substr(m.text, 1, 300) FROM session_first f JOIN merged m ON m.thread = f.thread AND m.n = f.n WHERE f.session = s.key) AS first_text,
       ${SESSION_LAST_FIELDS}
     ${SESSION_LAST_FROM}`;

/// What the sidebar actually shows: the latest turn and pending deliveries, without asking for a count or first words.
export const SESSION_ACTIVITY = `SELECT s.key, ${SESSION_PENDING}, ${SESSION_LAST_FIELDS} ${SESSION_LAST_FROM}`;
export const TURN_COUNT_PENDING = "turn count pending: ";
export class TurnCountUnavailable extends Refused {
  readonly sessions: string[];
  constructor(sessions: string[]) { super(503, TURN_COUNT_PENDING + JSON.stringify(sessions)); this.sessions = sessions; }
}

/// A session's latest turn, as `sessionStats` has it, by the index of its turns alone.
export const LAST_TURN = "SELECT * FROM turns WHERE session_key = ? ORDER BY started_at DESC LIMIT 1";

function sessionRows(s: Store, key: string | string[] | null, select: string): Json[] {
  if (Array.isArray(key) && key.length === 0) return [];
  const sql = `${select} ${Array.isArray(key) ? "WHERE s.key IN (SELECT value FROM json_each(?))" : key !== null ? "WHERE s.key = ?" : ""}`;
  return Array.isArray(key) ? all(s, sql, JSON.stringify(key)) : key !== null ? all(s, sql, key) : all(s, sql);
}
const latestTurn = (r: Json): TurnSummary | null => r.started_at === null ? null : { ...turnSummary(r, r.started_at), id: r.turn_id };

/// Per session (or for one): turn count and how long its ended turns ran, the latest turn (with its id: a client holding
/// the turns puts it in place rather than read them all again), undelivered messages and the first one it heard.
/// Each session's counts and last turn: one's, those named (`keys`), or all (null).
export function sessionStats(s: Store, key: string | string[] | null): Map<string, SessionStats> {
  const rows = sessionRows(s, key, SESSION_STATS);
  const unknown = rows.filter((r) => r.turns === null).map((r) => r.key as string);
  if (unknown.length) throw new TurnCountUnavailable(unknown);
  return new Map(
    rows.map((r) => [
      r.key as string,
      { turns: r.turns, workMs: r.work_ms, pending: r.pending, firstText: r.first_text, lastTurn: latestTurn(r) },
    ]),
  );
}

export function sessionActivity(s: Store, key: string | string[] | null): Map<string, { pending: number; lastTurn: TurnSummary | null }> {
  return new Map(sessionRows(s, key, SESSION_ACTIVITY).map((r) => [r.key as string, { pending: r.pending, lastTurn: latestTurn(r) }]));
}

/// A session's latest turn (as `sessionStats` has it, with its id), without the counts: what a notice of how it ended
/// needs.
export function lastTurn(s: Store, key: string): TurnSummary | null {
  const r = one(s, LAST_TURN, key);
  return r ? { ...turnSummary(r, r.started_at), id: r.id } : null;
}

// ── jobs ──

const toJob = (r: Json): JobRow => {
  const { token: _, sandbox: __, ...job } = rows.toJob(r);
  return job;
};

// SQLite compares the stored bytes; seenBy compares strings decoded by the Node SQLite driver. Different Node versions
// may stop decoding at a NUL, and old writers can have left non-UTF-8 bytes. Keep unusual values for seenBy to decide.
const JOB_WORKSPACE_CANDIDATE = `(s.ws = ?1 OR (?2 AND s.ws IS NULL)
  OR typeof(j.session_key) <> 'text' OR instr(CAST(j.session_key AS BLOB), x'00') > 0
  OR j.session_key GLOB '*[^ -~]*'
  OR (s.ws IS NOT NULL AND (typeof(s.ws) <> 'text' OR instr(CAST(s.ws AS BLOB), x'00') > 0
    OR s.ws GLOB '*[^ -~]*')))`;

/// A superset of the viewer's up jobs, filtered before their records leave SQLite. seenBy makes the final decision.
export const JOBS_UP_IN_WORKSPACE = `SELECT j.* FROM jobs j LEFT JOIN sessions s ON s.key = j.session_key
  WHERE j.state = 'running' AND ${JOB_WORKSPACE_CANDIDATE}
  UNION ALL
  SELECT j.* FROM jobs j LEFT JOIN sessions s ON s.key = j.session_key
  WHERE j.state = 'exited' AND j.port IS NOT NULL AND ${JOB_WORKSPACE_CANDIDATE}
  ORDER BY started_at DESC`;

/// The jobs up (running, or a service stopped on its own that holds its port), newest first. The state index still
/// visits other workspaces' up jobs; the join avoids loading those records and their session keys into the reader.
export function upJobs(s: Store, visibleTo: InWorkspace | null = null): JobRow[] {
  if (visibleTo === null) return all(s, rows.JOBS_UP).map(toJob);
  // Binding an unusual viewer can normalize it before SQLite compares it. Preserve the old JavaScript path for it.
  if (!/^[\x20-\x7e]*$/.test(visibleTo.workspace)) return all(s, rows.JOBS_UP).map(toJob);
  try {
    if (workspaceUpJobsReady(s.db)) return all(s, WORKSPACE_UP_JOBS, visibleTo.workspace, visibleTo.home !== false ? 1 : 0).map(toJob);
    s.prepareWorkspaceUpJobs = true;
  } catch (error) {
    // A reader can be opened on a database from before the index was installed.
    if (!(error instanceof Error) || !error.message.includes("no such table: workspace_up_meta")) throw error;
  }
  try {
    return all(s, JOBS_UP_IN_WORKSPACE, visibleTo.workspace, visibleTo.home !== false ? 1 : 0).map(toJob);
  } catch (error) {
    // Before sessions had workspaces, every session (including a missing one) belonged to the home workspace.
    if (!(error instanceof Error) || !error.message.includes("no such column: s.ws")) throw error;
    return visibleTo.home !== false ? all(s, rows.JOBS_UP).map(toJob) : [];
  }
}

/// How many of a session's latest jobs its detail lists for a device (`?jobs=now`, `jobsNow`).
export const JOBS_NOW = 50;
/// A session's latest jobs by when they were made (the index on their session, from its end), and those of it still up
/// (running, or a service being started again: by the index of those up): what a device's list of them shows, those
/// that matter now (client/core-ts jobs.ts `isCurrent`). Its every job was read for it, with each one's notices and
/// log: 378 of one session on a station (2026-11-03).
export const LATEST_JOBS = "SELECT * FROM jobs INDEXED BY jobs_by_session WHERE session_key = ? ORDER BY rowid DESC LIMIT ?";
export const UP_JOBS_OF = "SELECT * FROM jobs INDEXED BY jobs_up WHERE state = 'running' AND session_key = ?1 UNION ALL SELECT * FROM jobs INDEXED BY jobs_up WHERE state = 'exited' AND port IS NOT NULL AND session_key = ?1";
/// Keep the old lookup's running-then-restarting and port/rowid order for equal start times.
export const PREPARED_UP_JOBS_OF = `SELECT j.* FROM session_up_job_rows i CROSS JOIN jobs j ON j.rowid = i.job_rowid
  WHERE i.session = ? ORDER BY (j.state <> 'running'), j.port, j.rowid`;
export function jobsNow(s: Store, session: string): JobRow[] {
  // When every job fits, the recent page already contains every job still up. One extra row makes that certain.
  const latest = all(s, LATEST_JOBS, session, JOBS_NOW + 1);
  if (latest.length <= JOBS_NOW) return latest.sort((a, b) => b.started_at - a.started_at).map(toJob);
  let ready = false;
  try {
    ready = sessionUpJobsReady(s.db, session);
    if (!ready) s.prepareUpJobs = session;
  } catch (error) {
    // A reader can also be given a database from before the lookup was installed.
    if (!(error instanceof Error) || !error.message.includes("no such table: session_up_job_meta")) throw error;
  }
  const byId = new Map<string, Json>();
  for (const r of [...latest.slice(0, JOBS_NOW), ...all(s, ready ? PREPARED_UP_JOBS_OF : UP_JOBS_OF, session)]) byId.set(r.id, r);
  return [...byId.values()].sort((a, b) => b.started_at - a.started_at).map(toJob);
}

/// A session's jobs (all sessions' with null), newest first.
export function listJobs(s: Store, session: string | null): JobRow[] {
  return (session === null ? all(s, "SELECT * FROM jobs ORDER BY started_at DESC") : all(s, SESSION_JOBS, session)).map(toJob);
}

/// A job's notices, newest first (at most `limit`).
export function jobNotices(s: Store, id: string, limit: number): { at: number; text: string }[] {
  return all(s, "SELECT at, text FROM job_notices WHERE job_id = ? ORDER BY at DESC, rowid DESC LIMIT ?", id, limit).map((r) => ({ at: r.at, text: r.text }));
}

/// The jobs running of some sessions (`?`: a JSON list of their keys), the latest first, by an index (of the jobs running).
export const RUNNING_OF = "SELECT * FROM jobs WHERE session_key IN (SELECT value FROM json_each(?)) AND state = 'running' ORDER BY started_at DESC";

/// Active watches of the named sessions, using their lookup instead of reading every running job or a session's old jobs.
export const WATCHING_OF = `SELECT j.* FROM active_watch_jobs w INDEXED BY active_watch_jobs_session
  CROSS JOIN jobs j ON j.id = w.job WHERE w.session IN (SELECT value FROM json_each(?)) ORDER BY j.started_at DESC, j.rowid`;
export const WATCHING_ALL = `SELECT j.* FROM active_watch_jobs w
  CROSS JOIN jobs j ON j.id = w.job ORDER BY j.started_at DESC, j.rowid`;

/// jobs.rs `watching`: the sessions keeping watch (a watch job running), each with its watches' names, since when, and
/// when one last said something: of `sessions` alone (a session's summary, the sidebar items a change touched), or of
/// all. Of all, each summary and sidebar change read every job running and the notices of every watch.
export function watching(s: Store, sessions: string[] | null = null): Map<string, Json> {
  if (sessions !== null && sessions.length === 0) return new Map();
  const by = new Map<string, JobRow[]>();
  let running: Json[];
  try { running = sessions === null ? all(s, WATCHING_ALL) : all(s, WATCHING_OF, JSON.stringify(sessions)); }
  catch (error) {
    // A reader can also open a database from before active watches were kept.
    if (!(error instanceof Error) || !error.message.includes("no such table: active_watch_jobs")) throw error;
    running = sessions === null ? all(s, JOBS_RUNNING) : all(s, RUNNING_OF, JSON.stringify(sessions));
  }
  for (const job of running.map(toJob).filter((j) => j.watch)) {
    by.set(job.sessionKey, [...(by.get(job.sessionKey) ?? []), job]);
  }
  const out = new Map<string, Json>();
  for (const [key, jobs] of by) {
    jobs.sort((a, b) => a.startedAt - b.startedAt);
    const at = Math.max(...jobs.map((j) => Math.max(jobNotices(s, j.id, 1)[0]?.at ?? j.startedAt, j.startedAt)));
    out.set(key, { names: jobs.map((j) => j.name), since: jobs[0]!.startedAt, at });
  }
  return out;
}

// ── usage (store/usage.rs) ──

/// The calls of one day for one thread, person, profile and model, added up (store/usage.ts).
export type { UsageGroup };

/// A page of one session's original calls, newest first. Seek a timestamp tie by rowid before seeking older times:
/// a tuple comparison alone can start at the range's end and revisit every call newer than the cursor.
const USAGE_CALL_COLUMNS = `SELECT CAST(rowid AS TEXT) AS seq, id, CAST(at AS TEXT) AS at, session, turn, thread, person, profile, runtime, model, subagent, fast,
  input, cache_read, cache_write, cache_write_long, output, calls, context, context_window FROM usage INDEXED BY usage_session`;
export const USAGE_CALLS_SAME = `${USAGE_CALL_COLUMNS} WHERE session = ?1 AND at = ?2 AND rowid < ?3 ORDER BY rowid DESC LIMIT ?4`;
export const USAGE_CALLS_EARLIER = `${USAGE_CALL_COLUMNS} WHERE session = ?1 AND at >= ?2 AND at < ?3 ORDER BY usage.at DESC, rowid DESC LIMIT ?4`;
export function usageCallsPage(s: Store, session: string, from: bigint, to: bigint, before: [bigint, bigint], limit: number,
  viewer: InWorkspace | null): { rows: Json[]; next: { at: string; seq: string } | null } {
  const row = viewer === null ? undefined : one(s, "SELECT ws FROM sessions WHERE key = ?", session);
  if (viewer !== null && (row === undefined || !sees(viewer, row.ws))) return { rows: [], next: null };
  const size = Math.max(1, Math.min(limit, 200));
  const page: Json[] = [];
  if (before[0] >= from && before[0] < to) page.push(...all(s, USAGE_CALLS_SAME, session, before[0], before[1], size));
  const end = before[0] < to ? before[0] : to;
  if (page.length < size && end > from) page.push(...all(s, USAGE_CALLS_EARLIER, session, from, end, size - page.length));
  const rows = page.map((r) => ({ id: r.id, at: Number(r.at), session: r.session, turn: r.turn, thread: r.thread,
    person: r.person, profile: r.profile, runtime: r.runtime, model: r.model, subagent: r.subagent !== 0, fast: r.fast !== 0,
    input: Number(r.input), cacheRead: Number(r.cache_read), cacheWrite: Number(r.cache_write), cacheWriteLong: Number(r.cache_write_long),
    output: Number(r.output), calls: Number(r.calls), context: r.context, contextWindow: r.context_window }));
  const last = page.at(-1);
  return { rows, next: last === undefined || page.length < size ? null : { at: String(last.at), seq: String(last.seq) } };
}

/// usage_groups: the calls from `from` until `to` (ms), added up by day in the asker's time zone (`utcOffsetMin`) and by
/// thread, person, profile and model. Bounds are i64s (bigint), bound as integers as rusqlite binds them.
export { USAGE_DETAIL_PENDING };
export function usageGroups(s: Store, from: bigint, to: bigint, utcOffsetMin: bigint, viewer: InWorkspace | null = null,
  diagnostics?: { parts?: number; candidates?: number; selectedMs?: number }): UsageGroup[] {
  if (hasCompactUsage(s.db)) {
    if (!compactScopeReady(s.db, viewer)) throw new Refused(503, "usage statistics are moving between workspaces");
    const query = compactQuery(from, to, utcOffsetMin, viewer, diagnostics !== undefined, diagnostics !== undefined);
    if (diagnostics !== undefined && query.sql.includes("usage_summary_candidate()")) {
      diagnostics.candidates = 0;
      const started = performance.now();
      s.db.function("usage_summary_candidate", () => { diagnostics.candidates!++; return 1; });
      s.db.function("usage_summary_selected", () => { diagnostics.selectedMs = Math.round(performance.now() - started); return 1; });
    }
    const rows = all(s, query.sql, ...query.args);
    // Count only rows already used by this read; asking the database for another count would repeat the slow work.
    if (diagnostics !== undefined) diagnostics.parts = rows.reduce((n, row) => n + Number(row.source_parts), 0);
    return rows.map(usageGroupOf);
  }
  if (retiredUsage(s.db)) throw new Refused(503, "usage detail statistics are unavailable");
  const generation = usageDetailGeneration(s.db);
  if (!usageDetailReady(s.db, viewer, generation)) throw new Error(USAGE_DETAIL_PENDING);
  const query = detailQuery(from, to, utcOffsetMin, viewer, generation, usageDetailScopeBySession(s.db, viewer, generation));
  return query === null ? [] : all(s, query.sql, ...query.args).map(usageGroupOf);
}

export { batchedUsageQueries, usageGroupsBatched, UsageSummaryCache } from "./usage-batched.ts";
export type { BatchedUsage } from "./usage-batched.ts";

/// usage_threads: the threads usage names, each with the first thing a person said in it (for its title; none where
/// its archive cannot be read). Those gone are left out.
export function usageThreads(s: Store, ids: number[]): [ThreadRow, string | null][] {
  const out: [ThreadRow, string | null][] = [];
  for (const id of ids) {
    const thread = getThread(s, id);
    if (thread === null) continue;
    let first: string | null = null;
    if (thread.surface !== STILLFAIL_SURFACE && thread.title === null && thread.autoTitle === null) {
      try {
        first = firstText(s, id);
      } catch {
        // `.ok().flatten()`: an archive that does not read gives none.
      }
    }
    out.push([thread, first]);
  }
  return out;
}

/// The threads visible through sessions in this workspace. A thread with no sessions belongs to the home workspace.
/// Drive memberships from the matching sessions, so another workspace's growing card history is never visited.
export const VISIBLE_USAGE_THREADS = `WITH visible(thread) AS (
  SELECT ts.thread FROM sessions s INDEXED BY sessions_ws
  CROSS JOIN thread_sessions ts INDEXED BY thread_sessions_session ON ts.session = s.key
  WHERE s.ws = ?1 OR (?2 AND s.ws IS NULL)
  UNION
  SELECT t.id FROM threads t WHERE ?2 AND NOT EXISTS (SELECT 1 FROM thread_sessions ts WHERE ts.thread = t.id)
)`;
export const VISIBLE_USAGE_CARDS = `${VISIBLE_USAGE_THREADS}
  SELECT t.home AS home, c.said OR EXISTS (SELECT 1 FROM closed_cards x WHERE x.thread = c.thread AND x.n = c.n AND x.viewer != c.author) AS picked
  FROM visible v CROSS JOIN card_outcomes c ON c.thread = v.thread JOIN threads t ON t.id = c.thread`;

/// Chats by where they are and whether they were archived: only those the viewer's workspace can see.
export function threadsByPlace(s: Store, viewer: InWorkspace | null = null): { surface: string; home: string | null; archived: boolean }[] {
  const found = viewer === null
    ? all(s, "SELECT surface, home, hidden_at IS NOT NULL AS archived FROM threads")
    : all(s, `${VISIBLE_USAGE_THREADS} SELECT t.surface, t.home, t.hidden_at IS NOT NULL AS archived FROM visible v JOIN threads t ON t.id = v.thread`, viewer.workspace, viewer.home === false ? 0 : 1);
  return found.map((r) => ({
    surface: String(r.surface),
    home: r.home ?? null,
    archived: r.archived === 1,
  }));
}

/// Every decision card an agent posted (an options card, or options from before cards) and how it was answered: by an
/// option pressed (a person's next message in the thread is one of its labels, or a person closed it with one), or
/// not (answered in their own words, or not yet): the usage page's 决策点击率. With the session its thread is at home in.
/// As the database keeps them (store/schema.ts CARD_OUTCOMES): no entry is read.
export function decisionCards(s: Store, viewer: InWorkspace | null = null): { home: string | null; picked: boolean }[] {
  if (!usageCardOutcomesComplete(s.db)) throw new Error(USAGE_CHATS_PENDING);
  const found = viewer === null
    ? all(s, `SELECT t.home AS home, c.said OR EXISTS (SELECT 1 FROM closed_cards x WHERE x.thread = c.thread AND x.n = c.n AND x.viewer != c.author) AS picked
       FROM card_outcomes c LEFT JOIN threads t ON t.id = c.thread`)
    : all(s, VISIBLE_USAGE_CARDS, viewer.workspace, viewer.home === false ? 0 : 1);
  return found.map((r) => ({ home: r.home ?? null, picked: r.picked === 1 }));
}

export const USAGE_CHATS_PENDING = "usage chat statistics are still being filled";

export function usageChatsReady(s: Store, viewer: InWorkspace | null, options: UsageChatCoverage = {}): void {
  if (!usageChatStatsReady(s.db, viewer, options)) throw new Error(USAGE_CHATS_PENDING);
}

/// The totals are kept by place and visibility, not gathered from every chat and card on each request.
export function usageChatTotals(s: Store, viewer: InWorkspace | null, options: UsageChatCoverage = {}): { places: Record<string, number>; archived: number; cards: number; picked: number } {
  usageChatsReady(s, viewer, options);
  const places: Record<string, number> = {};
  let archived = 0, cards = 0, picked = 0;
  const scopes: [number, string, number][] = viewer === null ? [[0, "", 1]] : viewer.home === false
    ? [[2, viewer.workspace, 1]] : [[1, "", 1], [2, viewer.workspace, 1], [3, viewer.workspace, -1]];
  for (const [kind, workspace, sign] of scopes) {
    for (const row of all(s, "SELECT place, chats, archived, cards, picked FROM usage_chat_totals WHERE kind = ? AND ws = ?", kind, workspace)) {
      places[row.place] = (places[row.place] ?? 0) + sign * Number(row.chats);
      archived += sign * Number(row.archived);
      cards += sign * Number(row.cards);
      picked += sign * Number(row.picked);
    }
  }
  for (const place of Object.keys(places)) if (places[place] === 0) delete places[place];
  return { places, archived, cards, picked };
}

/// usage_since: when the earliest call recorded was made.
export function usageSince(s: Store): number | null {
  if (hasCompactUsage(s.db)) return compactUsageSince(s.db);
  const first = one(s, "SELECT first_at FROM usage_span WHERE id = 1").first_at as number | null;
  const cutover = usageDetailSince(s.db);
  return cutover === null ? first : Math.max(first ?? cutover, cutover);
}

/// The tasks other stations' chats ran here since `from` (remote_runs), oldest first: when, and whose session.
export const REMOTE_RUNS_PENDING = "remote task statistics are still being filled";

export function remoteRunsReady(s: Store): void {
  if (one(s, "SELECT done FROM remote_run_progress WHERE id = 1")?.done !== 1) throw new Error(REMOTE_RUNS_PENDING);
}

export function remoteRunsSince(s: Store, from: bigint, viewer: InWorkspace | null = null): { at: number; session: string }[] {
  remoteRunsReady(s);
  const rows = viewer === null ? all(s, REMOTE_RUNS_ALL, from)
    : all(s, REMOTE_RUNS_OF, viewer.workspace, from);
  return rows.map((r) => ({ at: Number(r.at), session: String(r.session) }));
}

/// The all-time card needs a count, not every task. Like remoteRunsSince(s, 0), it excludes negative timestamps.
export function remoteRunCount(s: Store, viewer: InWorkspace | null): number {
  remoteRunsReady(s);
  return viewer === null ? Number(one(s, "SELECT n FROM remote_run_total WHERE id = 1")?.n ?? 0)
    : Number(one(s, "SELECT n FROM remote_run_counts WHERE ws = ?", viewer.workspace)?.n ?? 0);
}

// ── what the session and job reads add (session, threads) ──

/// Rust's ordering of String keys (a BTreeMap's): by their UTF-8 bytes.
export const byBytes = (a: string, b: string) => Buffer.compare(Buffer.from(a), Buffer.from(b));

/// Store::list_bindings: the connects bound to each session.
export function listBindings(s: Store, keys?: readonly string[]): Map<string, string[]> {
  const out = new Map<string, string[]>();
  if (keys !== undefined && keys.length === 0) return out;
  if (keys !== undefined && !sessionBindingsReady(s.db)) throw new Error(SESSION_BINDINGS_PENDING);
  const rows = keys === undefined ? all(s, "SELECT connect, session_key AS session FROM bindings")
    : all(s, SESSION_BINDINGS_SELECTED, JSON.stringify([...new Set(keys)]));
  for (const r of rows) out.set(r.session, [...(out.get(r.session) ?? []), r.connect]);
  return out;
}

/// Store::participants: everyone who wrote in each session's threads (one, those named, or all), as creator references,
/// earliest first; a session no one wrote to has none.
export function participants(s: Store, session: string | string[] | null): Map<string, string[]> {
  if (Array.isArray(session) && session.length === 0) return new Map();
  const sql = `SELECT ts.session, ts.connect, t.id, t.surface FROM thread_sessions ts JOIN threads t ON t.id = ts.thread ${Array.isArray(session) ? "WHERE ts.session IN (SELECT value FROM json_each(?))" : session !== null ? "WHERE ts.session = ?" : ""}`;
  const rows = Array.isArray(session) ? all(s, sql, JSON.stringify(session)) : session !== null ? all(s, sql, session) : all(s, sql);
  // Each person once per session, at the first time they wrote in any of its threads.
  const firsts = new Map<string, Map<string, number>>();
  for (const r of rows) {
    const authors: [string, number][] = all(s, PEOPLE_AT, r.id).map((a) => [a.author, a.at]);
    const refs = firsts.get(r.session) ?? new Map<string, number>();
    firsts.set(r.session, refs);
    for (const [author, at] of authors) {
      const reference = r.surface === STILLFAIL_SURFACE ? author : `slack:${r.connect}:${author}`;
      const first = refs.get(reference);
      if (first === undefined || at < first) refs.set(reference, at);
    }
  }
  const out = new Map<string, string[]>();
  for (const [key, refs] of firsts) {
    if (refs.size === 0) continue;
    // In the BTreeMap's order, then (stably) by when.
    const sorted = [...refs].sort(([a], [b]) => byBytes(a, b)).sort(([, a], [, b]) => a - b);
    out.set(key, sorted.map(([r]) => r));
  }
  return out;
}

/// Store::list_turns: a session's turns, oldest first, each its summary and id.
/// A session's turns, the first first; `last`: only that many of the latest (by the index of its turns, read from its
/// end), none of those before them read.
export function listTurns(s: Store, session: string, last: number | null = null): Json[] {
  const rows = last === null
    ? all(s, "SELECT * FROM turns WHERE session_key = ? ORDER BY started_at", session)
    : all(s, LATEST_TURNS, session, last).reverse();
  return rows.map((r) => ({ ...turnSummary(r, r.started_at), id: r.id }));
}

/// A session's latest turns (`listTurns`), the latest first.
export const LATEST_TURNS = "SELECT * FROM turns WHERE session_key = ? ORDER BY started_at DESC LIMIT ?";

export function getJob(s: Store, id: string): JobRow | null {
  const r = one(s, "SELECT * FROM jobs WHERE id = ?", id);
  return r ? toJob(r) : null;
}

/// Store::widget_state: what a widget in one of the session's messages holds, as kept (JSON text).
export function widgetState(s: Store, session: string, path: string): string | null {
  const r = one(s, "SELECT state FROM widget_states WHERE session = ? AND path = ?", session, path);
  return r ? r.state : null;
}
