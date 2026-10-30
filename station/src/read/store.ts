// The station's database as the admin API reads it, ported from the Rust station's store.rs: the same SQL over the same
// file (opened read-only), and the same rows. A thread whose sessions are all archived lives in a zstd file under the
// archive directory (`archive/threads/<id>.jsonl.zst` beside the database) and is read from there, as the Rust does.
//
// serde's reading of a stored value is kept where it shows: a list of files or quotes that does not read is none, a
// card or identity that does not parse is none, an archive file that does not read fails the request (one that is not
// there is a thread with nothing left in it).
import { readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { zstdDecompressSync } from "node:zlib";
import { wall } from "../ops/fibers.ts";
import { USAGE_GROUPS } from "../store/usage.ts";
import * as rows from "../store/rows.ts";
import {
  CARD_BEFORE, CC_THREADS_SQL, CLOSED_SINCE, type CardAnswer, type EntryRow, type InWorkspace, JOBS_RUNNING, LETTER_SQL, type Membership, type MessageRow, OPTIONS_BEFORE,
  PEOPLE_AT, SAID_SINCE, SESSION_JOBS, SESSION_OF_RUNTIME, STILLFAIL_SURFACE, type ThreadRow, I64_MAX, MANUAL, attachment, authorKind, cardOf, isLetter, liveShare, mergeEntries,
  ending, parsed, quote, saidBefore, sees, takeChars, toChatShare, toEntry, toMembership, toMessage, toThread, withLetter,
} from "../store/rows.ts";

export type Json = any;

// The rows (camelCase) and how they are read from the database are the station's own (store/rows.ts): the readers'
// leave out what is not for the pages (a session's and a job's token).
export { I64_MAX, MANUAL, STILLFAIL_SURFACE, ending, optionsCard, saidBefore, takeChars } from "../store/rows.ts";
export type { AuthorKind, CardAnswer, EntryRow, Membership, MessageRow, ThreadRow } from "../store/rows.ts";

/// Archived threads whose entries are kept decompressed, the most recently read last.
const ARCHIVE_CACHE = 32;

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
};

/// TurnSummary, as serde writes it (camelCase, the skipped Nones left out).
export type TurnSummary = Record<string, Json>;

export type SessionStats = { turns: number; pending: number; firstText: string | null; lastTurn: TurnSummary | null };

/// A job as the pages are given it: without its token (nor the sandbox it asked for).
export type JobRow = Omit<rows.JobRow, "token" | "size">;

function toSession(r: Json): SessionRow {
  const { token: _, ...session } = rows.toSession(r);
  return session;
}

/// An entry from an archive file, as serde reads EntryRow (null where an Option is: None).
function archivedEntry(e: Json): EntryRow {
  const kind = e.kind;
  if (kind !== "message" && kind !== "edit") throw new Error(`unknown entry kind ${kind}`);
  if (!["person", "agent", "ember", "stillfail"].includes(e.authorKind)) throw new Error(`unknown author kind ${e.authorKind}`);
  const some = (v: Json) => (v === undefined || v === null ? undefined : v);
  return {
    agentIdentity: some(e.agentIdentity), thread: e.thread, n: e.n, kind, target: e.target ?? null, ts: e.ts ?? null,
    authorKind: authorKind(e.authorKind), author: e.author, text: e.text ?? null, attachments: (e.attachments ?? []).map(attachment),
    quotes: (e.quotes ?? []).map(quote), declared: e.declared ?? null, client: e.client ?? null, profile: e.profile ?? null, runtime: e.runtime ?? null,
    options: some(e.options), card: some(e.card), at: e.at,
    ...withLetter(e.letter),
  };
}

// ---- the store ----

export type Store = {
  db: DatabaseSync;
  /// The station's data directory: stillfail.db, archive/, config.json.
  dataDir: string;
  /// Where archived threads are (`threads/`): `archive/` in the data directory, as Store::open has it by default.
  archiveDir: string;
  /// Entries of archived threads read lately, the most recent last, by thread and its file as it was (`fileVersion`).
  archived: [number, string, EntryRow[]][];
  /// What lists show of each archived thread, read from its file once (archivedSummary).
  summaries: Map<number, ArchivedSummary>;
  /// People's names by email, as their credentials say them (the admin API's `deps.names`, filled as members ask).
  names: Map<string, string>;
  /// What only the hub knows, as it was when the read was asked: each session's process state (`process_state`;
  /// "cold" for one not listed) and the client keys sessions were made with (`client_key`).
  processes: Map<string, string>;
  clientKeys: Map<string, string>;
};

/// The store over an open database, with the data directory its archive is in.
export function makeStore(db: DatabaseSync, dataDir: string): Store {
  return { db, dataDir, archiveDir: join(dataDir, "archive"), archived: [], summaries: new Map(), names: new Map(), processes: new Map(), clientKeys: new Map() };
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

/// Which sessions `viewer` sees (docs/multi-workspace.md): those whose chat is in their workspace (one not there: the
/// home one's). A read made for no one (null) sees every one.
export function seenBy(s: Store, viewer: InWorkspace | null | undefined): (key: string) => boolean {
  if (!viewer) return () => true;
  // `*`: a database from before has no `ws` (every chat its home workspace's).
  const ws = new Map<string, string | null>(all(s, "SELECT * FROM sessions").map((r) => [r.key, r.ws ?? null]));
  return (key) => sees(viewer, ws.get(key) ?? null);
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

/// Store::sessionOfRuntime: the session that went on with `runtime`'s session `id`, the latest active if more did.
export function sessionOfRuntime(s: Store, runtime: string, id: string): string | null {
  return one(s, SESSION_OF_RUNTIME, runtime, id)?.key ?? null;
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
    const rows = key !== null ? all(s, "SELECT session, usage FROM session_usage WHERE session = ?", key) : all(s, "SELECT session, usage FROM session_usage");
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

/// Of `threads`, those with something new since `since` (ms): made, or a message said, then. An archived one's
/// messages are in its archive: it stays among them, for its summary to tell.
export function threadsActiveSince(s: Store, threads: number[], since: number): number[] {
  if (threads.length === 0 || since <= 0) return threads;
  return all(
    s,
    `SELECT t.id FROM threads t LEFT JOIN thread_state st ON st.thread = t.id LEFT JOIN entries e ON e.thread = t.id AND e.n = st.said_n
     WHERE t.id IN (${threads.map(() => "?").join(", ")}) AND (t.archived_at IS NOT NULL OR t.created_at >= ? OR e.at >= ?)`,
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
    const at: number | null = r.archived_at;
    return {
      sessions: threadSessions(s, t.id),
      last: lastEntry(s, t.id, at),
      lastMessage: lastSaid(s, t.id, at),
      read,
      unread: unreadOf(s, t.id, read, t.surface !== STILLFAIL_SURFACE ? selves.slack : selves.own, at),
      people: threadPeople(s, t.id, t.surface, at),
      firstText: firstText(s, t.id, at),
      letters: letterCount(s, t.id, at),
      thread: t,
    };
  });
  const said = (t: ThreadSummary) => t.lastMessage?.createdAt ?? 0;
  summaries.sort((a, b) => said(b) - said(a) || b.thread.createdAt - a.thread.createdAt || b.thread.id - a.thread.id);
  return summaries;
}

/// What lists show of a thread a station before wrote out to its archive file (its last entry, latest message, messages'
/// authors, the first thing a person said), read from its file once: it does not change while there, and written out
/// again it is another file (`fileVersion`). Such files are read until the station brings each back into the database
/// (store.ts `bringInArchived`); archiving writes none any more.
export type ArchivedSummary = {
  version: string;
  last: number;
  lastMessage: MessageRow | null;
  /// Its latest message that is not a letter (isLetter).
  lastSaid: MessageRow | null;
  messages: { n: number; authorKind: string; author: string; letter: boolean }[];
  /// The people who wrote in it, in the order they first did, and with when they first did.
  authors: string[];
  firstAt: [string, number][];
  firstText: string | null;
};

/// An archived thread's summary (null for one not archived); `at`: its archived_at, when the caller has it.
function archivedSummary(s: Store, thread: number, at?: number | null): ArchivedSummary | null {
  const when: number | null = at === undefined ? (one(s, "SELECT archived_at FROM threads WHERE id = ?", thread)?.archived_at ?? null) : at;
  if (when === null) return null;
  const version = fileVersion(threadFile(s, thread));
  const kept = s.summaries.get(thread);
  if (kept !== undefined && kept.version === version) return kept;
  const entries = archivedEntries(s, thread);
  const merged = mergeEntries(entries);
  const firstAt = new Map<string, number>();
  for (const e of entries) {
    if (e.kind !== "message" || e.authorKind !== "person") continue;
    const at = firstAt.get(e.author);
    if (at === undefined || e.at < at) firstAt.set(e.author, e.at);
  }
  const first = merged.find((m) => m.authorKind === "person");
  const keys = new Set(threadSessions(s, thread).map((m) => m.session));
  const made: ArchivedSummary = {
    version,
    last: entries.at(-1)?.n ?? 0,
    lastMessage: merged.at(-1) ?? null,
    lastSaid: merged.findLast((m) => !isLetter(m, keys)) ?? null,
    messages: merged.map((m) => ({ n: m.n, authorKind: m.authorKind, author: m.author, letter: isLetter(m, keys) })),
    authors: [...firstAt.keys()],
    firstAt: [...firstAt],
    firstText: first ? takeChars(first.text, 300) : null,
  };
  s.summaries.set(thread, made);
  return made;
}

/// The thread's latest message as merged, for lists.
export function lastMessage(s: Store, thread: number, at?: number | null): MessageRow | null {
  const archived = archivedSummary(s, thread, at);
  if (archived !== null) return archived.lastMessage === null ? null : { ...archived.lastMessage };
  const r = one(s, "SELECT * FROM merged WHERE thread = ? ORDER BY n DESC LIMIT 1", thread);
  return r ? toMessage(r) : null;
}

/// How many letters the thread has (isLetter), in either way.
export function letterCount(s: Store, thread: number, at?: number | null): number {
  const archived = archivedSummary(s, thread, at);
  if (archived !== null) return archived.messages.filter((m) => m.letter).length;
  return one(s, "SELECT letters FROM thread_state WHERE thread = ?", thread)?.letters ?? 0;
}

/// The thread's latest message that is not a letter (isLetter), for lists: what they show and sort by.
export function lastSaid(s: Store, thread: number, at?: number | null): MessageRow | null {
  const archived = archivedSummary(s, thread, at);
  if (archived !== null) return archived.lastSaid === null ? null : { ...archived.lastSaid };
  const r = one(s, "SELECT m.* FROM thread_state t JOIN merged m ON m.thread = t.thread AND m.n = t.said_n WHERE t.thread = ?", thread);
  return r ? toMessage(r) : null;
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
function unreadOf(s: Store, thread: number, read: number, selves: string[], at?: number | null): number {
  const archived = archivedSummary(s, thread, at);
  if (archived !== null) return archived.messages.filter((m) => m.n > read && !m.letter && !(m.authorKind === "person" && selves.includes(m.author))).length;
  return one(
    s,
    `SELECT COUNT(*) AS c FROM entries WHERE thread = ? AND n > ? AND kind = 'message'
     AND NOT (author_kind = 'person' AND author IN (SELECT value FROM json_each(?))) AND NOT ${LETTER_SQL}`,
    thread,
    read,
    JSON.stringify(selves),
  ).c;
}

/// Everyone who wrote in a thread, as creator references (a Slack user through a connect in it), earliest first.
function threadPeople(s: Store, thread: number, surface: string, at?: number | null): string[] {
  const connect: string | null = one(s, "SELECT MIN(connect) AS c FROM thread_sessions WHERE thread = ?", thread).c;
  let authors: string[];
  const archived = archivedSummary(s, thread, at);
  if (archived !== null) {
    authors = archived.authors;
  } else {
    authors = all(s, "SELECT author FROM thread_people WHERE thread = ? ORDER BY first_n", thread).map((r) => r.author);
  }
  if (surface === STILLFAIL_SURFACE) return authors;
  return connect === null ? [] : authors.map((a) => `slack:${connect}:${a}`);
}

/// The first thing a person said in it (up to 300 characters).
function firstText(s: Store, thread: number, at?: number | null): string | null {
  const archived = archivedSummary(s, thread, at);
  if (archived !== null) return archived.firstText;
  const r = one(s, "SELECT substr(m.text, 1, 300) AS t FROM thread_state t JOIN merged m ON m.thread = t.thread AND m.n = t.person_n WHERE t.thread = ?", thread);
  return r ? r.t : null;
}

// ── entries ──

/// The thread's last entry number, 0 before anything is said.
export function lastEntry(s: Store, thread: number, at?: number | null): number {
  const archived = archivedSummary(s, thread, at);
  if (archived !== null) return archived.last;
  return one(s, "SELECT MAX(n) AS n FROM entries WHERE thread = ?", thread).n ?? 0;
}

/// Entries after n: what came since (`n + 1` wraps at i64::MAX, as a release build's does).
export function entriesAfter(s: Store, thread: number, n: bigint): EntryRow[] {
  return entriesBetween(s, thread, BigInt.asIntN(64, n + 1n), I64_MAX);
}

/// The latest `limit` entries before n (the latest of all without it), oldest first.
export function entriesBefore(s: Store, thread: number, n: bigint | null, limit: number): EntryRow[] {
  const before = n ?? I64_MAX;
  if (isArchived(s, thread)) {
    const entries = archivedEntries(s, thread).filter((e) => e.n < before);
    return entries.slice(Math.max(0, entries.length - limit));
  }
  return all(s, "SELECT * FROM entries WHERE thread = ? AND n < ? ORDER BY n DESC LIMIT ?", thread, before, limit).map(toEntry).reverse();
}

/// Entries from n = `from` to n = `to`, both included: a gap.
export function entriesBetween(s: Store, thread: number, from: bigint, to: bigint): EntryRow[] {
  if (isArchived(s, thread)) return archivedEntries(s, thread).filter((e) => e.n >= from && e.n <= to);
  return all(s, "SELECT * FROM entries WHERE thread = ? AND n >= ? AND n <= ? ORDER BY n", thread, from, to).map(toEntry);
}

/// The latest `limit` messages before n (the latest of all without it), as merged, oldest first.
export function messagesBefore(s: Store, thread: number, n: number | null, limit: number): MessageRow[] {
  const before = n ?? I64_MAX;
  if (isArchived(s, thread)) {
    const messages = mergeEntries(archivedEntries(s, thread)).filter((m) => m.n < before);
    return messages.slice(Math.max(0, messages.length - limit));
  }
  return all(s, "SELECT * FROM merged WHERE thread = ? AND n < ? ORDER BY n DESC LIMIT ?", thread, before, limit).map(toMessage).reverse();
}

// ── the archive review ──

/// Whether the decision recommended the thread for the archive as it stands now (its last entry then is its last now).
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

/// What each chat shared with other workspaces is shared with now (its shares not lapsed, store/rows.ts), by the
/// session key its link names (none on a database from before the table).
export function chatShares(s: Store): Map<string, { to: { workspace: string; name: string }[]; write: boolean; by: string; at: number }> {
  let rows: Json[];
  try {
    rows = all(s, "SELECT * FROM chat_shares");
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

// ── chats published as snapshots (published) ──

/// Each chat's published snapshots, the latest first, by thread (none on a database from before the table).
export function publishedByThread(s: Store): Map<number, { id: string; key: string; title: string; by: string; byName: string; at: number; upto: number; size: number }[]> {
  let rows: Json[];
  try {
    rows = all(s, "SELECT * FROM published ORDER BY created_at DESC, id");
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

/// The chats a viewer pinned (by their session's key), with when.
export function pins(s: Store, viewer: string): Map<string, number> {
  return new Map(all(s, "SELECT session, at FROM pins WHERE viewer = ?", viewer).map((r) => [r.session, r.at]));
}

/// Chats kept instead of offered for archiving. Null selects every viewer.
export function keptChats(s: Store, viewer: string | null): Set<number> {
  return new Set(all(s, "SELECT DISTINCT thread FROM kept_chats WHERE ?1 IS NULL OR viewer = ?1", viewer).map((r) => r.thread));
}

// ── cards ──

/// The thread's card still pending, if any: its latest post with a card, as long as no person has written in the
/// thread since (nor was it closed). The post as merged, and its card.
export function pendingCard(s: Store, thread: number): [MessageRow, Json] | null {
  if (isArchived(s, thread)) return null;
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

/// The message an agent's need without a card asks with, while no person has written after it: the one its turn is
/// about (`about`), else the agent's latest message during the turn; with the two messages before it.
export function askingMessage(s: Store, thread: number, about: number | null, during: [number, number | bigint]): [MessageRow, MessageRow[]] | null {
  if (isArchived(s, thread)) return null;
  const n: number | null =
    about ?? one(s, "SELECT max(n) AS n FROM entries WHERE thread = ? AND kind = 'message' AND author_kind = 'agent' AND at >= ? AND at <= ?", thread, during[0], during[1]).n;
  if (n === null) return null;
  const answered = one(s, "SELECT 1 FROM entries WHERE thread = ? AND kind = 'message' AND author_kind = 'person' AND n > ? LIMIT 1", thread, n) !== undefined;
  // A post with a card is pending_card's: one no longer pending was answered, closed or withdrawn.
  const carded = one(s, "SELECT 1 FROM entries WHERE thread = ? AND n = ? AND (card IS NOT NULL OR options IS NOT NULL)", thread, n) !== undefined;
  if (answered || carded) return null;
  const messages = messagesBefore(s, thread, n + 1, 3);
  const m = messages.pop();
  return m && m.n === n && m.authorKind === "agent" ? [m, messages] : null;
}

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
  const told = one(s, "SELECT 1 FROM turns WHERE session_key = ? AND declared = 'block' AND ended_at >= ? AND ended_at < ? LIMIT 1", key, asked.createdAt, started) !== undefined;
  return { asked, fresh: !told };
}

/// The cards answered since `since` (ms), whoever answered them: each a person's first message after a card, or a
/// choice that closed it (closed_cards, by a person: not its agent withdrawing it).
export function answersSince(s: Store, since: number, threads: number[] | null = null): CardAnswer[] {
  const out: CardAnswer[] = [];
  // Of some threads alone (the items of a sidebar a change touched), each by the index of its people's messages: every
  // person's message of the last day and a half on the station, each with a few lookups, was some 2,600 statements.
  const said: Json[] =
    threads === null
      ? all(s, "SELECT thread, n FROM entries WHERE author_kind = 'person' AND kind = 'message' AND at >= ?", since)
      : threads.flatMap((thread) => all(s, SAID_SINCE, thread, since));
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
  for (const { thread, n, viewer: by, at } of all(s, CLOSED_SINCE, since)) {
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
export function dismissed(s: Store, viewer: string): Set<string> {
  return new Set(all(s, "SELECT thread, n FROM dismissed WHERE viewer = ?", viewer).map((r) => `${r.thread}:${r.n}`));
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
  v.detail = r.detail;
  v.startedAt = startedAt;
  v.endedAt = r.ended_at;
  return v;
}

/// Per session (or for one): turn count, the latest turn (with its id: a client holding the turns puts it in place
/// rather than read them all again), undelivered messages and the first one it heard.
/// Each session's counts and last turn: one's, those named (`keys`), or all (null).
export function sessionStats(s: Store, key: string | string[] | null): Map<string, SessionStats> {
  if (Array.isArray(key) && key.length === 0) return new Map();
  const sql = `SELECT s.key,
       (SELECT COUNT(*) FROM turns t WHERE t.session_key = s.key) AS turns,
       (SELECT COUNT(*) FROM deliveries d WHERE d.session = s.key AND d.delivered_at IS NULL) AS pending,
       (SELECT substr(m.text, 1, 300) FROM session_first f JOIN merged m ON m.thread = f.thread AND m.n = f.n WHERE f.session = s.key) AS first_text,
       l.id AS turn_id, l.kind, l.outcome, l.declared, l.wait_seconds, l.wait_for, l.need, l.about_thread, l.about_n, l.about_ts, l.detail, l.started_at, l.ended_at
     FROM sessions s
     LEFT JOIN turns l ON l.id = (SELECT id FROM turns t2 WHERE t2.session_key = s.key ORDER BY t2.started_at DESC LIMIT 1)
     ${Array.isArray(key) ? `WHERE s.key IN (${key.map(() => "?").join(", ")})` : key !== null ? "WHERE s.key = ?" : ""}`;
  const rows = Array.isArray(key) ? all(s, sql, ...key) : key !== null ? all(s, sql, key) : all(s, sql);
  return new Map(
    rows.map((r) => [
      r.key as string,
      { turns: r.turns, pending: r.pending, firstText: r.first_text, lastTurn: r.started_at === null ? null : { ...turnSummary(r, r.started_at), id: r.turn_id } },
    ]),
  );
}

// ── jobs ──

const toJob = (r: Json): JobRow => {
  const { token: _, size: __, ...job } = rows.toJob(r);
  return job;
};

/// A session's jobs (all sessions' with null), newest first.
export function listJobs(s: Store, session: string | null): JobRow[] {
  return (session === null ? all(s, "SELECT * FROM jobs ORDER BY started_at DESC") : all(s, SESSION_JOBS, session)).map(toJob);
}

/// A job's notices, newest first (at most `limit`).
export function jobNotices(s: Store, id: string, limit: number): { at: number; text: string }[] {
  return all(s, "SELECT at, text FROM job_notices WHERE job_id = ? ORDER BY at DESC, rowid DESC LIMIT ?", id, limit).map((r) => ({ at: r.at, text: r.text }));
}

/// jobs.rs `watching`: the sessions keeping watch (a watch job running), each with its watches' names, since when, and
/// when one last said something.
export function watching(s: Store): Map<string, Json> {
  const by = new Map<string, JobRow[]>();
  // (The jobs running, by their state's index: every summary and list asks this, not every job ever.)
  for (const job of all(s, JOBS_RUNNING).map(toJob).filter((j) => j.watch)) {
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

// ── archive ──

export function isArchived(s: Store, thread: number): boolean {
  const r = one(s, "SELECT archived_at FROM threads WHERE id = ?", thread);
  return r !== undefined && r.archived_at !== null;
}

function threadFile(s: Store, thread: number): string {
  return join(s.archiveDir, "threads", `${thread}.jsonl.zst`);
}

/// An archived thread's entries, from its file.
export function archivedEntries(s: Store, thread: number): EntryRow[] {
  const path = threadFile(s, thread);
  const version = fileVersion(path);
  const at = s.archived.findIndex(([id, v]) => id === thread && v === version);
  if (at >= 0) {
    const [cached] = s.archived.splice(at, 1);
    s.archived.push(cached!);
    return cached![2];
  }
  s.archived = s.archived.filter(([id]) => id !== thread);
  const text = version === LOST ? "" : zstdDecompressSync(readFileSync(path)).toString("utf8");
  const entries = text
    .split("\n")
    .map((l) => (l.endsWith("\r") ? l.slice(0, -1) : l))
    .filter((l) => l !== "")
    .map((l) => archivedEntry(JSON.parse(l)));
  if (s.archived.length >= ARCHIVE_CACHE) s.archived.shift();
  s.archived.push([thread, version, entries]);
  return entries;
}

/// An archive file as it is now (its size and when it was written): one written anew (the thread brought back and
/// archived again) is another. Read from a reader, the writer's moving of threads to and from their files is only seen so.
/// One that is not there (lost with the disk it was on) is LOST: its thread reads as one with no entries, so the
/// lists it is in are still read.
function fileVersion(path: string): string {
  try {
    const st = statSync(path);
    return `${st.size}:${st.mtimeMs}`;
  } catch {
    return LOST;
  }
}

/// The version of an archive file that is not there.
const LOST = "lost";

// ── usage (store/usage.rs) ──

/// The calls of one day (in the asker's time zone) for one thread, person, profile and model, added up (UsageGroup).
export type UsageGroup = {
  day: string; session: string; thread: number | null; person: string | null; profile: string | null; runtime: string;
  model: string | null; fast: boolean; calls: number; input: number; cacheRead: number; cacheWrite: number;
  cacheWriteLong: number; output: number;
};

/// usage_groups: the calls from `from` until `to` (ms), added up by day in the asker's time zone (`utcOffsetMin`) and by
/// thread, person, profile and model. Bounds are i64s (bigint), bound as integers as rusqlite binds them.
export function usageGroups(s: Store, from: bigint, to: bigint, utcOffsetMin: bigint): UsageGroup[] {
  return all(s, USAGE_GROUPS, from, to, utcOffsetMin).map((r) => ({
    day: r.day, session: r.session, thread: r.thread, person: r.person, profile: r.profile, runtime: r.runtime, model: r.model,
    fast: r.fast !== 0 && r.fast !== null, calls: r.calls, input: r.input, cacheRead: r.cache_read, cacheWrite: r.cache_write,
    cacheWriteLong: r.cache_write_long, output: r.output,
  }));
}

/// usage_threads: the threads usage names, each with the first thing a person said in it (for its title; none where
/// its archive cannot be read). Those gone are left out.
export function usageThreads(s: Store, ids: number[]): [ThreadRow, string | null][] {
  const out: [ThreadRow, string | null][] = [];
  for (const id of ids) {
    const thread = getThread(s, id);
    if (thread === null) continue;
    let first: string | null = null;
    if (thread.title === null && thread.autoTitle === null) {
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

/// usage_since: when the earliest call recorded was made.
export function usageSince(s: Store): number | null {
  return one(s, "SELECT MIN(at) AS at FROM usage").at ?? null;
}

/// The tasks other stations' chats ran here since `from` (remote_runs), oldest first: when, and whose session.
export function remoteRunsSince(s: Store, from: bigint): { at: number; session: string }[] {
  return all(s, "SELECT at, session FROM remote_runs WHERE at >= ? ORDER BY at", from).map((r) => ({ at: Number(r.at), session: String(r.session) }));
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
  const sql = `SELECT ts.session, ts.connect, t.id, t.surface, t.archived_at FROM thread_sessions ts JOIN threads t ON t.id = ts.thread ${session !== null ? "WHERE ts.session = ?" : ""}`;
  const rows = session !== null ? all(s, sql, session) : all(s, sql);
  // Each person once per session, at the first time they wrote in any of its threads.
  const firsts = new Map<string, Map<string, number>>();
  for (const r of rows) {
    const authors: [string, number][] =
      r.archived_at !== null
        ? archivedSummary(s, r.id, r.archived_at)!.firstAt
        : all(s, PEOPLE_AT, r.id).map((a) => [a.author, a.at]);
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
export function listTurns(s: Store, session: string): Json[] {
  return all(s, "SELECT * FROM turns WHERE session_key = ? ORDER BY started_at", session).map((r) => ({ ...turnSummary(r, r.started_at), id: r.id }));
}

export function getJob(s: Store, id: string): JobRow | null {
  const r = one(s, "SELECT * FROM jobs WHERE id = ?", id);
  return r ? toJob(r) : null;
}

/// Store::widget_state: what a widget in one of the session's messages holds, as kept (JSON text).
export function widgetState(s: Store, session: string, path: string): string | null {
  const r = one(s, "SELECT state FROM widget_states WHERE session = ? AND path = ?", session, path);
  return r ? r.state : null;
}
