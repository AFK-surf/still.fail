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
import { PENDING_MINUTE_SESSION } from "../store/usage-minutes.ts";
import { detailQuery, usageDetailGeneration, usageDetailReady, usageDetailScopeBySession, usageDetailSince, USAGE_DETAIL_PENDING } from "../store/usage-detail.ts";
import { compactHistory, compactQuery, compactScopeReady, compactUsageSince, hasCompactUsage } from "../store/usage-compact.ts";
import { usageChatStatsReady } from "../store/usage-chat-stats.ts";
import { REMOTE_RUNS_ALL, REMOTE_RUNS_OF } from "../store/remote-runs.ts";
import { hasRuntimeOrderIndex } from "../store/schema.ts";
import { type UsageGroup, usageGroupOf } from "../store/usage.ts";
import * as rows from "../store/rows.ts";
import {
  CARD_BEFORE, CC_THREADS_SQL, CLOSED_SINCE, CLOSED_THREAD_SINCE, type CardAnswer, type EntryRow, type InWorkspace, JOBS_RUNNING, type Membership, type MessageRow, OPTIONS_BEFORE,
  PEOPLE_AT, SESSION_JOBS, SESSION_OF_RUNTIME, STILLFAIL_SURFACE, type ThreadRow, I64_MAX, MANUAL, authorKind, cardOf, liveShare,
  ending, parsed, saidBefore, sees, takeChars, toChatShare, toEntry, letterEntry, toMembership, toMessage, toThread,
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
};

/// The store over an open database, with the data directory its archive is in.
export function makeStore(db: DatabaseSync, dataDir: string): Store {
  return { db, dataDir, names: new Map(), processes: new Map(), clientKeys: new Map() };
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

/// Which sessions `viewer` sees (docs/multi-workspace.md): those whose chat is in their workspace (one not there: the
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

/// The sessions not archived (the sidebar's), the latest active first, by the index of those alone (schema.ts
/// sessions_live): each read of the sidebar went over every session the station ever had (1,505 on ccvm, 1,398 of them
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

/// The runtime and profile of each transcript, including those from before runtime changes were supported.
export function runtimeSessionSources(s: Store, key: string): { id: string; runtime: string; profile: string | null }[] {
  const row = getSession(s, key);
  if (!row) return [];
  let sources: { id: string; runtime: string; profile: string | null }[] = [];
  try {
    sources = all(s, `SELECT r.id, COALESCE(r.runtime, s.original_runtime, s.runtime) AS runtime, r.profile
      FROM sessions s CROSS JOIN runtime_sessions r ON r.session_key = s.key WHERE s.key = ? ORDER BY r.at, r.rowid`, key)
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

/// How many entries sessions' transcripts have, as the station last read them while they were at work (one, or every
/// one known when `key` is null): none for a session not read since (or a database no station of this version opened).
export function transcriptLengths(s: Store, key: string | null): Map<string, number> {
  try {
    const rows = key !== null ? all(s, "SELECT session, n FROM transcript_lengths WHERE session = ?", key) : all(s, "SELECT session, n FROM transcript_lengths");
    return new Map(rows.map((r) => [r.session as string, Number(r.n)]));
  } catch {
    return new Map();
  }
}

/// What sessions' calls used, as the station keeps it (store.ts `setSessionUsage`; one, or every one known when `key` is
/// null): none for a session that has made no call (or a database no station of this version opened).
export function sessionUsages(s: Store, key: string | null): Map<string, Json> {
  try {
    const incremental = s.db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'usage_totals_incremental'").get() !== undefined;
    const source = incremental ? "session_usage u JOIN usage_totals_source_sessions c ON c.session = u.session AND c.done = 1" : "session_usage u";
    const rows = key !== null ? all(s, `SELECT u.session, u.usage FROM ${source} WHERE u.session = ?`, key)
      : all(s, `SELECT u.session, u.usage FROM ${source}`);
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
export function sessionThreads(s: Store, session: string): ThreadRow[] {
  return all(s, "SELECT t.* FROM thread_sessions ts JOIN threads t ON t.id = ts.thread WHERE ts.session = ? ORDER BY ts.joined_at DESC, ts.rowid DESC", session).map(toThread);
}

/// The threads a still.fail chat can copy people's messages to (rows.ts CC_THREADS_SQL), with the connect posting
/// in each.
export function ccThreads(s: Store, thread: number): { thread: ThreadRow; connect: string }[] {
  return all(s, CC_THREADS_SQL, thread).map((r) => ({ thread: toThread(r), connect: r.connect }));
}

export function threadSessions(s: Store, thread: number): Membership[] {
  return all(s, "SELECT * FROM thread_sessions WHERE thread = ? ORDER BY joined_at, rowid", thread).map(toMembership);
}

/// The threads sessions take part in (each once).
export function threadsOfSessions(s: Store, keys: string[]): number[] {
  if (keys.length === 0) return [];
  return all(s, `SELECT DISTINCT thread FROM thread_sessions WHERE session IN (${keys.map(() => "?").join(", ")})`, ...keys).map((r) => r.thread as number);
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
/// first: those of one session, one thread (or those named), or all.
export function listThreads(s: Store, viewer: string, session: string | null, thread: number | number[] | null): ThreadSummary[] {
  const base = "SELECT t.*, COALESCE(r.n, 0) AS read_n FROM threads t LEFT JOIN reads r ON r.thread = t.id AND r.viewer = ?1";
  const rows: Json[] =
    Array.isArray(thread)
      ? thread.length === 0
        ? []
        : all(s, `${base} WHERE t.id IN (${thread.map((_, i) => `?${i + 2}`).join(", ")})`, viewer, ...thread)
      : thread !== null
      ? all(s, `${base} WHERE t.id = ?2`, viewer, thread)
      : session !== null
        ? all(s, `${base} WHERE t.id IN (SELECT thread FROM thread_sessions WHERE session = ?2)`, viewer, session)
        : all(s, base, viewer);
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
      unread: unreadOf(s, t.id, read, t.surface !== STILLFAIL_SURFACE ? selves.slack : selves.own),
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

/// The thread's latest message as merged, for lists.
export function lastMessage(s: Store, thread: number): MessageRow | null {
  const r = one(s, "SELECT * FROM merged WHERE thread = ? ORDER BY n DESC LIMIT 1", thread);
  return r ? toMessage(r) : null;
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
  const r = one(s, "SELECT m.* FROM thread_state t JOIN merged m ON m.thread = t.thread AND m.n = t.said_n WHERE t.thread = ?", thread);
  return r ? toMessage(r) : null;
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
function unreadOf(s: Store, thread: number, read: number, selves: string[]): number {
  return one(s, UNREAD, thread, read, JSON.stringify(selves)).c;
}

/// A chat's messages after where a viewer read (`?2`) but their own (`?3`, a JSON list) and letters, counted from the
/// index of its messages alone (store/schema.ts entries_said): from the messages themselves, each was a page read.
export const UNREAD = `SELECT COUNT(*) AS c FROM entries WHERE thread = ?1 AND n > ?2 AND kind = 'message' AND letter IS NULL
  AND NOT (author_kind = 'person' AND author IN (SELECT value FROM json_each(?3)))`;

/// Everyone who wrote in a thread, as creator references (a Slack user through a connect in it), earliest first.
export function threadPeople(s: Store, thread: number, surface: string): string[] {
  const connect: string | null = one(s, "SELECT MIN(connect) AS c FROM thread_sessions WHERE thread = ?", thread).c;
  const authors: string[] = all(s, "SELECT author FROM thread_people WHERE thread = ? ORDER BY first_n", thread).map((r) => r.author);
  if (surface === STILLFAIL_SURFACE) return authors;
  return connect === null ? [] : authors.map((a) => `slack:${connect}:${a}`);
}

/// The first thing a person said in it (up to 300 characters).
export function firstText(s: Store, thread: number): string | null {
  const r = one(s, "SELECT substr(m.text, 1, 300) AS t FROM thread_state t JOIN merged m ON m.thread = t.thread AND m.n = t.person_n WHERE t.thread = ?", thread);
  return r ? r.t : null;
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

/// The latest `limit` messages before n (the latest of all without it), as merged, oldest first.
export function messagesBefore(s: Store, thread: number, n: number | null, limit: number): MessageRow[] {
  const before = n ?? I64_MAX;
  return all(s, "SELECT * FROM merged WHERE thread = ? AND n < ? ORDER BY n DESC LIMIT ?", thread, before, limit).map(toMessage).reverse();
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
// them). The rows of every chat ever shared, opened or published were read at each sidebar change and each chat told.
export const SHARES_OF = "SELECT * FROM chat_shares WHERE session IN (SELECT value FROM json_each(?))";
const OPENERS = "SELECT o.child, o.parent_station, o.parent, o.opener_title, p.title AS parent_title FROM opened_chats o LEFT JOIN sessions p ON o.parent_station = '' AND p.key = o.parent";
export const OPENERS_OF = `${OPENERS} WHERE o.child_station = '' AND o.child IN (SELECT value FROM json_each(?))`;
const OPENED = "SELECT o.parent, o.child_station, o.child, o.title, c.title AS child_title FROM opened_chats o LEFT JOIN sessions c ON o.child_station = '' AND c.key = o.child";
export const OPENED_OF = `${OPENED} WHERE o.parent_station = '' AND o.parent IN (SELECT value FROM json_each(?)) ORDER BY o.created_at, o.rowid`;
export const PUBLISHED_OF = "SELECT * FROM published WHERE thread IN (SELECT value FROM json_each(?)) ORDER BY created_at DESC, id";

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

// ── chats published as snapshots (published) ──

/// Each chat's published snapshots, the latest first, by thread (none on a database from before the table): of those
/// `threads` name alone (a chat), or of all.
export function publishedByThread(s: Store, threads: number[] | null = null): Map<number, { id: string; key: string; title: string; by: string; byName: string; at: number; upto: number; size: number }[]> {
  let rows: Json[];
  try {
    rows = threads === null ? all(s, "SELECT * FROM published ORDER BY created_at DESC, id") : all(s, PUBLISHED_OF, JSON.stringify(threads));
  } catch {
    return new Map();
  }
  const out = new Map<number, { id: string; key: string; title: string; by: string; byName: string; at: number; upto: number; size: number }[]>();
  for (const r of rows) {
    const list = out.get(r.thread) ?? [];
    list.push({ id: r.id, key: r.key, title: r.title, by: r.created_by, byName: r.by_name, at: r.created_at, upto: r.upto, size: r.size });
    out.set(r.thread, list);
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
  const rows = threads === null || viewer === null
    ? all(s, "SELECT DISTINCT thread FROM kept_chats WHERE ?1 IS NULL OR viewer = ?1", viewer)
    : [...new Set(threads)].flatMap((thread) => all(s, "SELECT thread FROM kept_chats WHERE viewer = ? AND thread = ?", viewer, thread));
  return new Set(rows.map((r) => r.thread));
}

// ── cards ──

/// The thread's card still pending, if any: its latest post with a card, as long as no person has written in the
/// thread since (nor was it closed). The post as merged, and its card.
export function pendingCard(s: Store, thread: number): [MessageRow, Json] | null {
  // The latest of each kind (cards, and options from before cards), each read by its own index.
  const latest = (column: string): Json | undefined =>
    one(s, `SELECT n, card, options FROM entries WHERE thread = ? AND kind = 'message' AND ${column} IS NOT NULL ORDER BY n DESC LIMIT 1`, thread);
  const a = latest("card");
  const b = latest("options");
  const asked = a && b ? (a.n >= b.n ? a : b) : (a ?? b);
  if (!asked) return null;
  const n: number = asked.n;
  const answered = one(s, "SELECT 1 FROM entries WHERE thread = ? AND kind = 'message' AND author_kind = 'person' AND n > ? LIMIT 1", thread, n) !== undefined;
  const closed = one(s, "SELECT 1 FROM closed_cards WHERE thread = ? AND n = ?", thread, n) !== undefined;
  if (answered || closed) return null;
  const card = cardOf(asked.card, asked.options);
  if (card === undefined) return null;
  const m = one(s, "SELECT * FROM merged WHERE thread = ? AND n = ?", thread, n);
  return m ? [toMessage(m), card] : null;
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
  const asked = one(s, "SELECT card, options FROM entries WHERE thread = ? AND n = ?", thread, n);
  if (!asked) return null;
  const answered = one(s, "SELECT 1 FROM entries WHERE thread = ? AND kind = 'message' AND author_kind = 'person' AND n > ? LIMIT 1", thread, n) !== undefined;
  const closed = one(s, "SELECT 1 FROM closed_cards WHERE thread = ? AND n = ?", thread, n) !== undefined;
  if (answered || closed) return null;
  const card = cardOf(asked.card, asked.options);
  if (card === undefined) return null;
  const m = one(s, "SELECT * FROM merged WHERE thread = ? AND n = ?", thread, n);
  return m ? [toMessage(m), card] : null;
}

/// An agent's latest message in a chat during a turn (`?2` to `?3`, ms), by the index of agents' messages by time (store/
/// schema.ts entries_agent_at): by the chat alone, all it had was read for it.
export const ASKED_DURING = "SELECT max(n) AS n FROM entries WHERE thread = ? AND kind = 'message' AND author_kind = 'agent' AND at >= ? AND at <= ?";

/// The message an agent's need without a card asks with, while no person has written after it: the one its turn is
/// about (`about`), else the agent's latest message during the turn; with the two messages before it.
export function askingMessage(s: Store, thread: number, about: number | null, during: [number, number | bigint]): [MessageRow, MessageRow[]] | null {
  const n: number | null = about ?? one(s, ASKED_DURING, thread, during[0], during[1]).n;
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
/// it), and by the session's turns from its first, every turn it had was read: 1,891 for one on ccvm (2026-11-02).
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

/// The people's messages since `since` (ms) in a thread that each are the first after a card (the last before it), in
/// order: by its cards, each with the first person's message after it (none between: a card after it is the one asked).
function answersOf(s: Store, thread: number, since: number): { thread: number; n: number }[] {
  const cards = [...new Set([
    ...all(s, "SELECT n FROM entries WHERE thread = ? AND kind = 'message' AND card IS NOT NULL", thread),
    ...all(s, "SELECT n FROM entries WHERE thread = ? AND kind = 'message' AND options IS NOT NULL", thread),
  ].map((r) => r.n as number))].sort((a, b) => a - b);
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
export function answersSince(s: Store, since: number, threads: number[] | null = null): CardAnswer[] {
  const out: CardAnswer[] = [];
  // Of some threads alone (the items of a sidebar a change touched), each by its cards (a few) and the first person's
  // message after each: every person's message of the last day and a half on the station, each with a few lookups, was
  // some 2,600 statements; one chat's 76 of them, with its 3 cards, 1 to 1.5 s on ccvm short of memory (2026-11-03).
  const said: Json[] =
    threads === null
      ? all(s, "SELECT thread, n FROM entries WHERE author_kind = 'person' AND kind = 'message' AND at >= ?", since)
      : threads.flatMap((thread) => answersOf(s, thread, since));
  const of = threads === null ? null : new Set(threads);
  const askedBefore = (thread: number, n: number): number | null => {
    const card: number | null = one(s, CARD_BEFORE, thread, n).n;
    const options: number | null = one(s, OPTIONS_BEFORE, thread, n).n;
    // Option's max: None below any Some.
    return card === null ? options : options === null ? card : Math.max(card, options);
  };
  const cardAt = (thread: number, n: number): [MessageRow, Json] | null => {
    const row = one(s, "SELECT card, options FROM entries WHERE thread = ? AND n = ?", thread, n);
    const card = row ? cardOf(row.card, row.options) : undefined;
    if (card === undefined) return null;
    const m = one(s, "SELECT * FROM merged WHERE thread = ? AND n = ?", thread, n);
    return m ? [toMessage(m), card] : null;
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
    const answer = one(s, "SELECT * FROM merged WHERE thread = ? AND n = ?", thread, n);
    if (!answer) continue;
    const a = toMessage(answer);
    out.push({ question: found[0], card: found[1], by: a.author, at: a.createdAt, answer: a });
  }
  const closedRows = threads === null
    ? all(s, CLOSED_SINCE, since)
    : [...new Set(threads)].flatMap((thread) => all(s, CLOSED_THREAD_SINCE, thread, since))
      .sort((a, b) => a.at - b.at || a.ordering - b.ordering);
  for (const { thread, n, viewer: by, at } of closedRows) {
    if (of !== null && !of.has(thread)) continue;
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
/// (the deliveries by session and thread), each summary of a long session read some 65 pages, from the disk on ccvm
/// short of memory (2026-11-02), as often as the session changed.
export const SESSION_STATS = `SELECT s.key,
       COALESCE((SELECT c.n FROM session_turns c WHERE c.session = s.key), 0) AS turns,
       -- How long its turns ran, where every one ended since that was kept (schema.ts SESSION_WORK); else none.
       CASE WHEN NOT EXISTS (SELECT 1 FROM turns o INDEXED BY turns_by_end WHERE o.session_key = s.key AND o.ended_at <= (SELECT f.at FROM session_work_from f WHERE f.id = 1))
         THEN COALESCE((SELECT w.ms FROM session_work w WHERE w.session = s.key), 0) END AS work_ms,
       ((SELECT COUNT(*) FROM deliveries d INDEXED BY deliveries_pending WHERE d.session = s.key AND d.delivered_at IS NULL) +
         (SELECT COUNT(*) FROM letter_deliveries d WHERE d.session = s.key AND d.delivered_at IS NULL)) AS pending,
       (SELECT substr(m.text, 1, 300) FROM session_first f JOIN merged m ON m.thread = f.thread AND m.n = f.n WHERE f.session = s.key) AS first_text,
       l.id AS turn_id, l.kind, l.outcome, l.declared, l.wait_seconds, l.wait_for, l.wait_watch, l.need, l.about_thread, l.about_n, l.about_ts, l.detail, l.started_at, l.ended_at
     FROM sessions s
     LEFT JOIN turns l ON l.id = (SELECT id FROM turns t2 WHERE t2.session_key = s.key ORDER BY t2.started_at DESC LIMIT 1)`;

/// A session's latest turn, as `sessionStats` has it, by the index of its turns alone.
export const LAST_TURN = "SELECT * FROM turns WHERE session_key = ? ORDER BY started_at DESC LIMIT 1";

/// Per session (or for one): turn count and how long its ended turns ran, the latest turn (with its id: a client holding
/// the turns puts it in place rather than read them all again), undelivered messages and the first one it heard.
/// Each session's counts and last turn: one's, those named (`keys`), or all (null).
export function sessionStats(s: Store, key: string | string[] | null): Map<string, SessionStats> {
  if (Array.isArray(key) && key.length === 0) return new Map();
  const sql = `${SESSION_STATS}
     ${Array.isArray(key) ? `WHERE s.key IN (${key.map(() => "?").join(", ")})` : key !== null ? "WHERE s.key = ?" : ""}`;
  const rows = Array.isArray(key) ? all(s, sql, ...key) : key !== null ? all(s, sql, key) : all(s, sql);
  return new Map(
    rows.map((r) => [
      r.key as string,
      { turns: r.turns, workMs: r.work_ms, pending: r.pending, firstText: r.first_text, lastTurn: r.started_at === null ? null : { ...turnSummary(r, r.started_at), id: r.turn_id } },
    ]),
  );
}

/// A session's latest turn (as `sessionStats` has it, with its id), without the counts: what a notice of how it ended
/// needs.
export function lastTurn(s: Store, key: string): TurnSummary | null {
  const r = one(s, LAST_TURN, key);
  return r ? { ...turnSummary(r, r.started_at), id: r.id } : null;
}

// ── jobs ──

const toJob = (r: Json): JobRow => {
  const { token: _, size: __, ...job } = rows.toJob(r);
  return job;
};

/// The jobs up (running, or a service stopped on its own that holds its port), newest first: by the index of their
/// states, not every job the station ever ran.
export function upJobs(s: Store): JobRow[] {
  return all(s, rows.JOBS_UP).map(toJob);
}

/// How many of a session's latest jobs its detail lists for a device (`?jobs=now`, `jobsNow`).
export const JOBS_NOW = 50;
/// A session's latest jobs by when they were made (the index on their session, from its end), and those of it still up
/// (running, or a service being started again: by the index of those up): what a device's list of them shows, those
/// that matter now (client/core-ts jobs.ts `isCurrent`). Its every job was read for it, with each one's notices and
/// log: 378 of one session on ccvm (2026-11-03).
export const LATEST_JOBS = "SELECT * FROM jobs INDEXED BY jobs_by_session WHERE session_key = ? ORDER BY rowid DESC LIMIT ?";
export const UP_JOBS_OF = "SELECT * FROM jobs INDEXED BY jobs_up WHERE state = 'running' AND session_key = ?1 UNION ALL SELECT * FROM jobs INDEXED BY jobs_up WHERE state = 'exited' AND port IS NOT NULL AND session_key = ?1";
export function jobsNow(s: Store, session: string): JobRow[] {
  const byId = new Map<string, Json>();
  for (const r of [...all(s, LATEST_JOBS, session, JOBS_NOW), ...all(s, UP_JOBS_OF, session)]) byId.set(r.id, r);
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

/// jobs.rs `watching`: the sessions keeping watch (a watch job running), each with its watches' names, since when, and
/// when one last said something: of `sessions` alone (a session's summary, the sidebar items a change touched), or of
/// all. Of all, each summary and sidebar change read every job running and the notices of every watch.
export function watching(s: Store, sessions: string[] | null = null): Map<string, Json> {
  const by = new Map<string, JobRow[]>();
  // (The jobs running, by their state's index: every summary and list asks this, not every job ever.)
  const running = sessions === null ? all(s, JOBS_RUNNING) : all(s, RUNNING_OF, JSON.stringify(sessions));
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

/// Sent back to the pool if a session entered a workspace while its old minutes were being filled; it retries after
/// that session is ready. The check and the read use the same SQLite snapshot in the reader.
export const USAGE_MINUTES_PENDING = "usage minutes are still being indexed";
const QUARTERS_ALL = `FROM usage_day_quarters q`;
const QUARTERS_SCOPED = `FROM usage_minute_scope sc INDEXED BY usage_minute_scope_ws
  CROSS JOIN usage_day_quarters q ON q.session = sc.session`;
const QUARTERS_HOME = `FROM (
  SELECT session FROM usage_minute_scope INDEXED BY usage_minute_scope_ws WHERE ws = ?2
  UNION ALL SELECT session FROM usage_minute_scope INDEXED BY usage_minute_scope_ws WHERE ws IS NULL
) sc CROSS JOIN usage_day_quarters q ON q.session = sc.session`;
// Each quarter is entirely within one local day except one crossing midnight. Keep those quarters' minutes separate;
// all the others are read once regardless of how many calls or occupied minutes they contain.
const CROSSES_DAY = `((q.quarter * 15 + CAST(?1 AS INTEGER)) % 1440 + 1440) % 1440 > 1425`;
function quartersByDay(from: string, visible: string): string {
  return `SELECT strftime('%Y-%m-%d', (q.quarter * 15 + CAST(?1 AS INTEGER)) * 60, 'unixepoch') AS day,
    q.session, q.runtime, NULLIF(q.model, '') AS model, SUM(q.tokens) AS tokens, SUM(q.calls) AS calls
    ${from} WHERE ${visible} GROUP BY day, q.session, q.runtime, q.model`;
}
function minutesAtDayEdges(from: string, visible: string): string {
  return `WITH edge(session, quarter) AS (
      SELECT DISTINCT q.session, q.quarter ${from} WHERE ${visible} AND ${CROSSES_DAY}
    ), parts AS (
      SELECT q.session, q.quarter * 15 AS minute, q.runtime, q.model, q.tokens, q.calls
        ${from} WHERE ${visible} AND NOT (${CROSSES_DAY})
      UNION ALL
      SELECT m.session, m.minute, m.runtime, m.model, m.tokens, m.calls
        FROM edge e CROSS JOIN usage_minute m ON m.session = e.session
          AND m.minute >= e.quarter * 15 AND m.minute < (e.quarter + 1) * 15
    )
    SELECT strftime('%Y-%m-%d', (p.minute + CAST(?1 AS INTEGER)) * 60, 'unixepoch') AS day,
      p.session, p.runtime, NULLIF(p.model, '') AS model, SUM(p.tokens) AS tokens, SUM(p.calls) AS calls
      FROM parts p GROUP BY day, p.session, p.runtime, p.model`;
}
export const USAGE_QUARTERS_ALL = quartersByDay(QUARTERS_ALL, "1");
export const USAGE_QUARTERS_SCOPED = quartersByDay(QUARTERS_SCOPED, "sc.ws = ?2");
export const USAGE_QUARTERS_HOME = quartersByDay(QUARTERS_HOME, "1");
export const USAGE_DAY_ALL = minutesAtDayEdges(QUARTERS_ALL, "1");
export const USAGE_DAY_SCOPED = minutesAtDayEdges(QUARTERS_SCOPED, "sc.ws = ?2");
export const USAGE_DAY_HOME = minutesAtDayEdges(QUARTERS_HOME, "1");

// Once detailed statistics supply the minutes, their scope follows session moves without rewriting old buckets.
const DETAIL_QUARTERS_SCOPED = QUARTERS_SCOPED.replaceAll("usage_minute_scope", "usage_detail_scope");
const DETAIL_QUARTERS_HOME = QUARTERS_HOME.replaceAll("usage_minute_scope", "usage_detail_scope");
function detailMinutesAtDayEdges(from: string, visible: string): string {
  return `WITH edge(session, quarter) AS (
      SELECT DISTINCT q.session, q.quarter ${from} WHERE ${visible} AND ${CROSSES_DAY}
    ), parts AS (
      SELECT q.session, q.quarter * 15 AS minute, q.runtime, q.model, q.tokens, q.calls
        ${from} WHERE ${visible} AND NOT (${CROSSES_DAY})
      UNION ALL
      SELECT d.session, d.bucket AS minute, d.runtime, d.model,
        d.input + d.cache_read + d.cache_write + d.cache_write_long + d.output AS tokens, d.calls
        FROM edge e CROSS JOIN usage_detail d ON d.session = e.session AND d.level = 1
          AND d.bucket >= e.quarter * 15 AND d.bucket < (e.quarter + 1) * 15
    )
    SELECT strftime('%Y-%m-%d', (p.minute + CAST(?1 AS INTEGER)) * 60, 'unixepoch') AS day,
      p.session, p.runtime, NULLIF(p.model, '') AS model, SUM(p.tokens) AS tokens, SUM(p.calls) AS calls
      FROM parts p GROUP BY day, p.session, p.runtime, p.model`;
}
export const USAGE_DETAIL_DAY_ALL = detailMinutesAtDayEdges(QUARTERS_ALL, "1");
export const USAGE_DETAIL_DAY_SCOPED = detailMinutesAtDayEdges(DETAIL_QUARTERS_SCOPED, "sc.ws = ?2");
export const USAGE_DETAIL_DAY_HOME = detailMinutesAtDayEdges(DETAIL_QUARTERS_HOME, "1");
export const USAGE_DETAIL_QUARTERS_SCOPED = quartersByDay(DETAIL_QUARTERS_SCOPED, "sc.ws = ?2");
export const USAGE_DETAIL_QUARTERS_HOME = quartersByDay(DETAIL_QUARTERS_HOME, "1");

/// Calls added up by local day and session without rereading the calls, including in non-quarter-hour time zones.
export function usageByDay(s: Store, utcOffsetMin: bigint, viewer: InWorkspace | null = null, partial = false,
  range?: { from: bigint; to: bigint }): { day: string; session: string; runtime: string; model: string | null; tokens: number; calls: number }[] {
  if (hasCompactUsage(s.db)) {
    const rows = compactHistory(s.db, utcOffsetMin, viewer, partial, range);
    if (rows === null) throw new Error(USAGE_MINUTES_PENDING);
    return rows;
  }
  if (retiredUsage(s.db)) throw new Error(USAGE_MINUTES_PENDING);
  const fromDetail = one(s, "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'usage_history_from_detail'") !== undefined;
  if (fromDetail) {
    const generation = usageDetailGeneration(s.db);
    if (generation !== "legacy" || !usageDetailReady(s.db, viewer, generation)) throw new Error(USAGE_MINUTES_PENDING);
    const aligned = utcOffsetMin % 15n === 0n;
    const rows = viewer === null ? all(s, aligned ? USAGE_QUARTERS_ALL : USAGE_DETAIL_DAY_ALL, utcOffsetMin)
      : all(s, viewer.home === false ? (aligned ? USAGE_DETAIL_QUARTERS_SCOPED : USAGE_DETAIL_DAY_SCOPED)
        : (aligned ? USAGE_DETAIL_QUARTERS_HOME : USAGE_DETAIL_DAY_HOME), utcOffsetMin, viewer.workspace);
    return rows.map((r) => ({ day: r.day, session: r.session, runtime: r.runtime, model: r.model, tokens: Number(r.tokens), calls: Number(r.calls) }));
  }
  // Before the old fill completed, an old session might have no scope row at all. An empty scope is therefore not
  // proof that this workspace's historical total is complete.
  if (one(s, "SELECT done FROM usage_minute_all WHERE id = 1")?.done !== 1) throw new Error(USAGE_MINUTES_PENDING);
  if (viewer !== null && viewer.home === false && one(s, PENDING_MINUTE_SESSION, viewer.workspace)) {
    throw new Error(USAGE_MINUTES_PENDING);
  }
  const aligned = utcOffsetMin % 15n === 0n;
  const found = viewer === null ? all(s, aligned ? USAGE_QUARTERS_ALL : USAGE_DAY_ALL, utcOffsetMin)
    : all(s, viewer.home === false ? (aligned ? USAGE_QUARTERS_SCOPED : USAGE_DAY_SCOPED) : (aligned ? USAGE_QUARTERS_HOME : USAGE_DAY_HOME), utcOffsetMin, viewer.workspace);
  return found.map((r) => ({ day: r.day, session: r.session, runtime: r.runtime, model: r.model, tokens: Number(r.tokens), calls: Number(r.calls) }));
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
  const found = viewer === null
    ? all(s, `SELECT t.home AS home, c.said OR EXISTS (SELECT 1 FROM closed_cards x WHERE x.thread = c.thread AND x.n = c.n AND x.viewer != c.author) AS picked
       FROM card_outcomes c LEFT JOIN threads t ON t.id = c.thread`)
    : all(s, VISIBLE_USAGE_CARDS, viewer.workspace, viewer.home === false ? 0 : 1);
  return found.map((r) => ({ home: r.home ?? null, picked: r.picked === 1 }));
}

export const USAGE_CHATS_PENDING = "usage chat statistics are still being filled";

export function usageChatsReady(s: Store, viewer: InWorkspace | null): void {
  if (!usageChatStatsReady(s.db, viewer)) throw new Error(USAGE_CHATS_PENDING);
}

/// The totals are kept by place and visibility, not gathered from every chat and card on each request.
export function usageChatTotals(s: Store, viewer: InWorkspace | null): { places: Record<string, number>; archived: number; cards: number; picked: number } {
  usageChatsReady(s, viewer);
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

// ── what the session and job reads add (admin/views.rs sessions, session, threads; jobs.rs) ──

/// Rust's ordering of String keys (a BTreeMap's): by their UTF-8 bytes.
export const byBytes = (a: string, b: string) => Buffer.compare(Buffer.from(a), Buffer.from(b));

/// Store::list_bindings: the connects bound to each session.
export function listBindings(s: Store): Map<string, string[]> {
  const out = new Map<string, string[]>();
  for (const r of all(s, "SELECT connect, session_key FROM bindings")) out.set(r.session_key, [...(out.get(r.session_key) ?? []), r.connect]);
  return out;
}

/// Store::participants: everyone who wrote in each session's threads (or one session's), as creator references,
/// earliest first; a session no one wrote to has none.
export function participants(s: Store, session: string | null): Map<string, string[]> {
  const sql = `SELECT ts.session, ts.connect, t.id, t.surface FROM thread_sessions ts JOIN threads t ON t.id = ts.thread ${session !== null ? "WHERE ts.session = ?" : ""}`;
  const rows = session !== null ? all(s, sql, session) : all(s, sql);
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

/// Store::list_turns: a session's turns, oldest first, each its summary and id (as views.rs `session` shows them).
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
