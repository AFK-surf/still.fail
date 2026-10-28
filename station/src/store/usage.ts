// What the agents spent, as the station records it (the Rust station's store/usage.rs): one row per model call, with the
// turn it was in, whom that turn worked for, in which thread and on which profile. The Store's usage methods call these.
import type { DatabaseSync } from "node:sqlite";
import { type Json, QUARTER_MS, STILLFAIL_SURFACE } from "./rows.ts";

/// A model call read from a transcript (or a turn's calls, told at once: `calls` of them). Tokens as the provider bills
/// them. `context`: of a main-thread call, what its session's context held after it (null: not told); `window`: the
/// model's context window, where the runtime tells it.
export type UsageCall = {
  id: string; at: number; model: string | null; subagent: boolean; fast: boolean; input: number; cacheRead: number;
  cacheWrite: number; cacheWriteLong: number; output: number; calls: number; context: number | null; window: number | null;
};

/// How far a transcript has been read, and for which session (null: none of the station's).
export type UsageFile = { session: string | null; offset: number; model: string | null };

/// What a call was for: the turn it was in, and whom that worked for, where, on what.
export type UsageFor = { turn: string | null; person: string | null; thread: number | null; profile: string | null };

/// A turn as usage takes it: when it started, and whom it worked for.
export type UsageTurn = { id: string; startedAt: number; of: UsageFor };

/// The calls of one day (in the asker's time zone) for one thread, person, profile and model, added up.
export type UsageGroup = {
  day: string; session: string; thread: number | null; person: string | null; profile: string | null; runtime: string;
  model: string | null; fast: boolean; calls: number; input: number; cacheRead: number; cacheWrite: number;
  cacheWriteLong: number; output: number;
};

/// Stands for i64::MIN as a turn's start: before every call.
const EARLIEST = Number.MIN_SAFE_INTEGER;

/// usage_files: every transcript read for usage so far, by path.
export function usageFiles(db: DatabaseSync): Map<string, UsageFile> {
  const rows = db.prepare("SELECT path, session, offset, model FROM usage_files").all() as Json[];
  return new Map(rows.map((r) => [r.path, { session: r.session, offset: r.offset, model: r.model }]));
}

/// record_usage: a transcript's calls read up to `file.offset`, each with what it was for; a call recorded before keeps
/// its row (its output grown). How many were new. Run in a transaction by the caller.
export function recordUsage(db: DatabaseSync, path: string, file: UsageFile, runtime: string, calls: [UsageCall, UsageFor][]): number {
  let added = 0;
  if (file.session !== null) {
    const insert = db.prepare(
      `INSERT INTO usage (id, at, session, turn, thread, person, profile, runtime, model, subagent, fast, input, cache_read, cache_write, cache_write_long, output, calls, context, context_window)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19)
       ON CONFLICT (id) DO UPDATE SET output = MAX(output, excluded.output)`,
    );
    const known = db.prepare("SELECT 1 FROM usage WHERE id = ?");
    for (const [c, of] of calls) {
      const was = known.get(c.id) !== undefined;
      insert.run(
        c.id, c.at, file.session, of.turn, of.thread, of.person, of.profile, runtime, c.model, c.subagent ? 1 : 0, c.fast ? 1 : 0,
        c.input, c.cacheRead, c.cacheWrite, c.cacheWriteLong, c.output, c.calls, c.context, c.window,
      );
      if (!was) added++;
    }
  }
  db.prepare(
    `INSERT INTO usage_files (path, session, offset, model) VALUES (?1, ?2, ?3, ?4)
     ON CONFLICT (path) DO UPDATE SET session = excluded.session, offset = excluded.offset, model = excluded.model`,
  ).run(path, file.session, file.offset, file.model);
  return added;
}

/// The turns running, then those ended since `?` (usageActiveSessions).
export const ACTIVE_SESSIONS = "SELECT session_key FROM turns WHERE ended_at IS NULL UNION ALL SELECT session_key FROM turns WHERE ended_at >= ?";

/// usage_active_sessions: sessions whose transcripts may have grown since `since`: a turn running, or ended since then.
export function usageActiveSessions(db: DatabaseSync, since: number): string[] {
  // Each half by the index on when turns ended, the sessions made distinct here: asked as one OR, or as a UNION or a
  // DISTINCT, the station's SQLite (node's, 3.53; not the sqlite3 command's) answers it in order of session by reading
  // every turn of the station's, 33 s on ccvm with its pages put out (2026-10-25).
  const rows = db.prepare(ACTIVE_SESSIONS).all(since) as Json[];
  return [...new Set(rows.map((r) => r.session_key as string))];
}

/// Where `usageTurns` begins for calls from `?2` on: the last of the session's turns to start by then (the first of all,
/// for calls before them all).
export const TURNS_FROM = `SELECT IFNULL((SELECT MAX(started_at) FROM turns WHERE session_key = ?1 AND started_at <= ?2),
  (SELECT MIN(started_at) FROM turns WHERE session_key = ?1)) AS at`;
/// A session's turns that began from `?2` until `?3`, oldest first, by the index on them (schema.ts turns_by_session).
export const TURNS_BETWEEN = "SELECT id, kind, started_at, profile, person, thread FROM turns WHERE session_key = ?1 AND started_at >= ?2 AND started_at <= ?3 ORDER BY started_at";
/// The people's messages a session took from `?3` on, as they were delivered (schema.ts deliveries_taken).
export const TAKEN_SINCE = `SELECT d.delivered_at AS at, CASE WHEN t.surface = ?2 THEN e.author ELSE 'slack:' || ts.connect || ':' || e.author END AS who, e.thread AS thread
  FROM deliveries d JOIN entries e ON e.thread = d.thread AND e.n = d.n JOIN threads t ON t.id = d.thread
  JOIN thread_sessions ts ON ts.thread = d.thread AND ts.session = d.session
  WHERE d.session = ?1 AND d.delivered_at IS NOT NULL AND d.delivered_at >= ?3 AND e.author_kind = 'person' ORDER BY d.delivered_at`;

/// usage_turns: the turns of a session calls made from `from` until `until` (ms) were made in, oldest first, each with
/// whom it worked for: the last to begin by `from` (the first of all, for calls before them all) and those after it
/// until `until`. A few rows, by the index on them: the usage counter asks at each part of a transcript it reads (every
/// few seconds while agents work), and read whole, a long session's thousand turns were each read where they lie.
/// A turn says whom it worked for as it began (store.ts startTurnFor). One from before turns said so is worked out: a
/// turn that answered messages is for the first person whose message it took, in that message's thread; any other goes
/// on with the work of the one before. What is still unknown is the session's: its creator, its own chat, its profile.
export function usageTurns(db: DatabaseSync, session: string, from: number, until: number): UsageTurn[] {
  const row = db.prepare("SELECT created_by, profile FROM sessions WHERE key = ?").get(session) as Json;
  const creator: string | null = row ? row.created_by : null;
  const profile: string = row ? row.profile : "";
  const homeRow = db
    .prepare("SELECT id FROM threads WHERE home = ?1 UNION ALL SELECT thread FROM (SELECT thread FROM thread_sessions WHERE session = ?1 ORDER BY joined_at LIMIT 1) LIMIT 1")
    .get(session) as Json;
  const home: number | null = homeRow ? homeRow.id : null;
  const begins: number | null = (db.prepare(TURNS_FROM).get(session, from) as Json).at;
  const turns = begins === null ? [] : (db.prepare(TURNS_BETWEEN).all(session, begins, Math.max(begins, until)) as Json[]);
  // The people's messages the session took, as they were delivered (only needed for turns from before).
  const delivered: [number, string, number][] = turns.some((t) => t.person === null)
    ? (db.prepare(TAKEN_SINCE).all(session, STILLFAIL_SURFACE, begins) as Json[]).map((r) => [r.at, r.who, r.thread])
    : [];
  const out: UsageTurn[] = [];
  let next = 0;
  turns.forEach((t, n) => {
    const end = n + 1 < turns.length ? turns[n + 1].started_at : Number.MAX_SAFE_INTEGER;
    while (next < delivered.length && delivered[next]![0] < t.started_at) next++;
    const candidate = delivered[next];
    const first = t.kind === "input" && candidate !== undefined && candidate[0] < end ? candidate : null;
    const previous = out.at(-1)?.of ?? null;
    const person = t.person ?? first?.[1] ?? previous?.person ?? creator;
    const thread = t.thread ?? first?.[2] ?? previous?.thread ?? home;
    out.push({ id: t.id, startedAt: t.started_at, of: { turn: t.id, person, thread, profile: t.profile ?? profile } });
  });
  if (out.length === 0) out.push({ id: "", startedAt: EARLIEST, of: { turn: null, person: creator, thread: home, profile } });
  return out;
}

/// A main-thread call as the pool weighs moving its session (sessions/pool.ts `cheapToLeave`) and as a session's usage
/// says where its context stands (usage/module.ts `usageNow`): the context it left (null: not told) and the model's window,
/// when it was made (ms), at which speed, and what it wrote to the cache for five minutes and for an hour.
export type ContextCall = {
  turn: string | null; profile: string | null; model: string | null; context: number | null; window: number | null;
  at: number; fast: boolean; cacheWrite: number; cacheWriteLong: number;
};

/// A session's last `limit` main-thread calls, oldest first.
export function lastContexts(db: DatabaseSync, session: string, limit: number): ContextCall[] {
  const rows = db
    .prepare("SELECT turn, profile, model, context, context_window, at, fast, cache_write, cache_write_long FROM usage WHERE session = ?1 AND subagent = 0 ORDER BY at DESC LIMIT ?2")
    .all(session, limit) as Json[];
  return rows.reverse().map((r) => ({
    turn: r.turn, profile: r.profile, model: r.model, context: r.context, window: r.context_window,
    at: r.at, fast: r.fast !== 0 && r.fast !== null, cacheWrite: r.cache_write, cacheWriteLong: r.cache_write_long,
  }));
}

/// Where each model's context was compacted on this station since `since`: the most a main-thread call sent before
/// the next, on the same account and model, sent under half of it (at least COMPACTED_FROM before), as the database
/// keeps them (schema.ts USAGE_COMPACTIONS): a few rows, by their time's index.
export function compactionPoints(db: DatabaseSync, since: number): Map<string, number> {
  const rows = db.prepare("SELECT model, MAX(point) AS point FROM usage_compactions WHERE at >= ? GROUP BY model").all(since) as Json[];
  return new Map(rows.map((r) => [r.model, r.point]));
}

/// The calls from `?1` until `?2` (ms), added up by day in the asker's time zone (`?3`, minutes east of UTC) and by
/// thread, person, profile and model: as the station adds them up and as its readers do for the usage page
/// (read/store.ts usageGroups). The whole quarters of an hour between them as kept added up (schema.ts USAGE_QUARTERS),
/// the calls before the first and from the last one by one; all of them one by one for a time zone that is not whole
/// quarters. Bounds said as numbers are bound as reals (node:sqlite): taken as the integers they are, as the quarters'
/// arithmetic needs.
export const USAGE_GROUPS = `WITH a AS (SELECT CAST(?1 AS INTEGER) AS f, CAST(?2 AS INTEGER) AS t, CAST(?3 AS INTEGER) AS tz),
  b AS (SELECT f, t, tz, tz % 15 = 0 AS whole, (MAX(f, 0) + ${QUARTER_MS} - 1) / ${QUARTER_MS} AS q0, t / ${QUARTER_MS} AS q1 FROM a)
  SELECT strftime('%Y-%m-%d', (at + tz * 60000) / 1000, 'unixepoch') AS day, session, thread, person, profile, runtime, model, fast,
    SUM(calls) AS calls, SUM(input) AS input, SUM(cache_read) AS cache_read, SUM(cache_write) AS cache_write,
    SUM(cache_write_long) AS cache_write_long, SUM(output) AS output
  FROM (
    SELECT quarter * ${QUARTER_MS} AS at, session, NULLIF(thread, 0) AS thread, NULLIF(person, '') AS person, NULLIF(profile, '') AS profile, runtime,
      NULLIF(model, '') AS model, fast, calls, input, cache_read, cache_write, cache_write_long, output
    FROM usage_quarters, b WHERE whole AND quarter >= q0 AND quarter < q1
    UNION ALL
    SELECT at, session, thread, person, profile, runtime, model, fast, calls, input, cache_read, cache_write, cache_write_long, output
    FROM usage, b WHERE at >= f AND at < CASE WHEN whole THEN MIN(t, q0 * ${QUARTER_MS}) ELSE t END
    UNION ALL
    SELECT at, session, thread, person, profile, runtime, model, fast, calls, input, cache_read, cache_write, cache_write_long, output
    FROM usage, b WHERE whole AND at >= MAX(f, q0 * ${QUARTER_MS}, q1 * ${QUARTER_MS}) AND at < t
  ), b
  GROUP BY day, session, thread, person, profile, runtime, model, fast`;

/// usage_groups: the calls from `from` until `to` (ms), added up by day in the asker's time zone (`utcOffsetMin`) and
/// by thread, person, profile and model.
export function usageGroups(db: DatabaseSync, from: number, to: number, utcOffsetMin: number): UsageGroup[] {
  return (db.prepare(USAGE_GROUPS).all(from, to, utcOffsetMin) as Json[]).map((r) => ({
    day: r.day, session: r.session, thread: r.thread, person: r.person, profile: r.profile, runtime: r.runtime, model: r.model,
    fast: r.fast !== 0 && r.fast !== null, calls: r.calls, input: r.input, cacheRead: r.cache_read, cacheWrite: r.cache_write,
    cacheWriteLong: r.cache_write_long, output: r.output,
  }));
}

/// A session's calls, added up by model (its day, thread, person and profile left empty): what its execution details
/// show of it. As the database keeps them added up (schema.ts USAGE_TOTALS): asked each time the live view of a session
/// at work tells its usage.
export function usageOfSession(db: DatabaseSync, session: string): UsageGroup[] {
  return (
    db
      .prepare(
        `SELECT runtime, NULLIF(model, '') AS model, fast, calls, input, cache_read, cache_write, cache_write_long, output
         FROM usage_totals WHERE session = ?1 AND calls > 0 ORDER BY runtime, model, fast`,
      )
      .all(session) as Json[]
  ).map((r) => ({
    day: "", session, thread: null, person: null, profile: null, runtime: r.runtime, model: r.model, fast: r.fast !== 0 && r.fast !== null,
    calls: r.calls, input: r.input, cacheRead: r.cache_read, cacheWrite: r.cache_write, cacheWriteLong: r.cache_write_long, output: r.output,
  }));
}

/// usage_since: when the earliest call recorded was made.
export function usageSince(db: DatabaseSync): number | null {
  return (db.prepare("SELECT MIN(at) AS at FROM usage").get() as Json).at ?? null;
}
