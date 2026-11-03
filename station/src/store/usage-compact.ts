// Incremental usage summaries. Calls remain in usage; only one minute bucket per set of dimensions is maintained.
import type { DatabaseSync } from "node:sqlite";
import type { InWorkspace } from "./rows.ts";
import { COMPACTED_FROM } from "./rows.ts";
import type { ContextCall, UsageCall, UsageFor } from "./usage.ts";

const minute = (r: string) => `(CASE WHEN ${r}.at >= 0 THEN ${r}.at / 60000 ELSE -1 - ((-1 - ${r}.at) / 60000) END)`;
const cols = ["calls", "input", "cache_read", "cache_write", "cache_write_long", "output"] as const;
const scopeOf = (value: string) => `(CASE WHEN ${value} IS NULL THEN 'H' ELSE 'W' || ${value} END)`;
const sessionScope = (r: string) => scopeOf(`(SELECT ws FROM sessions WHERE key = ${r}.session)`);
const fields = (r: string) => `${r}.session, ${minute(r)}, COALESCE(${r}.thread, 0), COALESCE(${r}.person, ''),
  COALESCE(${r}.profile, ''), ${r}.runtime, COALESCE(${r}.model, ''), ${r}.fast`;
const key = (r: string) => `session = ${r}.session AND minute = ${minute(r)} AND thread = COALESCE(${r}.thread, 0)
  AND person = COALESCE(${r}.person, '') AND profile = COALESCE(${r}.profile, '') AND runtime = ${r}.runtime
  AND model = COALESCE(${r}.model, '') AND fast = ${r}.fast`;
const add = (r: string) => `INSERT INTO usage_compact SELECT ${fields(r)}, 1, ${cols.map((c) => `${r}.${c}`).join(", ")}, ${sessionScope(r)}
  WHERE ${r}.compact_counted = 1 ON CONFLICT (session, minute, thread, person, profile, runtime, model, fast) DO UPDATE SET
  records = records + 1, ${cols.map((c) => `${c} = ${c} + excluded.${c}`).join(", ")};`;
const remove = (r: string) => `UPDATE usage_compact SET records = records - 1, ${cols.map((c) => `${c} = ${c} - ${r}.${c}`).join(", ")}
  WHERE ${r}.compact_counted = 1 AND ${key(r)};
  DELETE FROM usage_compact WHERE ${r}.compact_counted = 1 AND ${key(r)} AND records = 0;`;
const scope = (r: string) => `INSERT INTO usage_minute_scope (session, ws, done)
  SELECT ${r}.session, (SELECT ws FROM sessions WHERE key = ${r}.session), 1 WHERE ${r}.compact_counted = 1
  ON CONFLICT (session) DO UPDATE SET ws = excluded.ws WHERE ws IS NOT excluded.ws;`;
const dimensionsChanged = `OLD.at IS NOT NEW.at OR OLD.session IS NOT NEW.session OR OLD.thread IS NOT NEW.thread
  OR OLD.person IS NOT NEW.person OR OLD.profile IS NOT NEW.profile OR OLD.runtime IS NOT NEW.runtime
  OR OLD.model IS NOT NEW.model OR OLD.fast IS NOT NEW.fast OR OLD.compact_counted IS NOT NEW.compact_counted`;
const valuesChanged = cols.map((c) => `OLD.${c} IS NOT NEW.${c}`).join(" OR ");
const quarter = (r: string) => `(CASE WHEN ${r}.at >= 0 THEN ${r}.at / 900000 ELSE -1 - ((-1 - ${r}.at) / 900000) END)`;
const tokens = (r: string) => `(${r}.input + ${r}.cache_read + ${r}.cache_write + ${r}.cache_write_long + ${r}.output)`;
const legacyKey = (r: string, period: string, value: string) => `session = ${r}.session AND ${period} = ${value}
  AND runtime = ${r}.runtime AND model = COALESCE(${r}.model, '')`;
const oldAdd = (r: string, table: string, period: string, value: string, coverage: string) => `
  INSERT INTO ${table} SELECT ${r}.session, ${value}, ${r}.runtime, COALESCE(${r}.model, ''), ${r}.calls, ${tokens(r)}
  WHERE ${r}.compact_counted = 0 AND (SELECT ${coverage} FROM usage_compact_since WHERE id = 1) = 1
  ON CONFLICT (session, ${period}, runtime, model) DO UPDATE SET calls = calls + excluded.calls, tokens = tokens + excluded.tokens;`;
const oldRemove = (r: string, table: string, period: string, value: string, coverage: string) => `
  UPDATE ${table} SET calls = calls - ${r}.calls, tokens = tokens - ${tokens(r)} WHERE ${r}.compact_counted = 0
    AND (SELECT ${coverage} FROM usage_compact_since WHERE id = 1) = 1 AND ${legacyKey(r, period, value)};
  DELETE FROM ${table} WHERE ${r}.compact_counted = 0 AND (SELECT ${coverage} FROM usage_compact_since WHERE id = 1) = 1
    AND ${legacyKey(r, period, value)} AND calls = 0 AND tokens = 0;`;
const oldAddAll = (r: string) => oldAdd(r, "usage_day_quarters", "quarter", quarter(r), "old_days") + oldAdd(r, "usage_minute", "minute", minute(r), "old_minutes");
const oldRemoveAll = (r: string) => oldRemove(r, "usage_day_quarters", "quarter", quarter(r), "old_days") + oldRemove(r, "usage_minute", "minute", minute(r), "old_minutes");

export function hasCompactUsage(db: DatabaseSync): boolean {
  return db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'usage_compact_since'").get() !== undefined;
}

export function compactCoverageSince(db: DatabaseSync): number {
  return (db.prepare("SELECT since FROM usage_compact_since WHERE id = 1").get() as { since: number }).since;
}

export function compactUsageSince(db: DatabaseSync): number {
  const row = db.prepare("SELECT since, first_at, first_unknown FROM usage_compact_since WHERE id = 1").get() as
    { since: number; first_at: number | null; first_unknown: number };
  return row.first_unknown || row.first_at === null ? row.since : Math.max(row.since, row.first_at);
}

/// Switch only after the old process has gone. No old calls or old summaries are read to create the new source.
export function installCompactUsage(db: DatabaseSync, now: () => number): void {
  if (hasCompactUsage(db)) return;
  const has = (name: string) => db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?").get(name) !== undefined;
  db.exec("BEGIN IMMEDIATE");
  try {
    if (hasCompactUsage(db)) { db.exec("COMMIT"); return; }
    // The emergency retirement stopped the old writers. Without a record of every call during that gap, the old
    // summary cannot prove completeness and must not be merged into the new one as if it were current.
    const empty = db.prepare("SELECT 1 FROM usage LIMIT 1").get() === undefined;
    const oldDays = empty || (!has("usage_retired_detail") && has("usage_minute_all")
      && (db.prepare("SELECT done FROM usage_minute_all WHERE id = 1").get() as { done: number } | undefined)?.done === 1);
    const oldMinutes = empty || (oldDays && !has("usage_history_from_detail"));
    db.exec(`ALTER TABLE usage ADD COLUMN compact_counted INTEGER NOT NULL DEFAULT 0;
      CREATE TABLE usage_compact_since (id INTEGER PRIMARY KEY CHECK (id = 1), since INTEGER NOT NULL, old_days INTEGER NOT NULL,
        old_minutes INTEGER NOT NULL, first_at INTEGER, first_unknown INTEGER NOT NULL DEFAULT 0);
      CREATE TABLE usage_compact (session TEXT NOT NULL, minute INTEGER NOT NULL, thread INTEGER NOT NULL, person TEXT NOT NULL,
        profile TEXT NOT NULL, runtime TEXT NOT NULL, model TEXT NOT NULL, fast INTEGER NOT NULL, records INTEGER NOT NULL,
        calls INTEGER NOT NULL, input INTEGER NOT NULL, cache_read INTEGER NOT NULL, cache_write INTEGER NOT NULL,
        cache_write_long INTEGER NOT NULL, output INTEGER NOT NULL, scope TEXT NOT NULL,
        PRIMARY KEY (session, minute, thread, person, profile, runtime, model, fast)) WITHOUT ROWID;
      CREATE INDEX usage_compact_time ON usage_compact (minute, session);
      CREATE INDEX usage_compact_scope_time ON usage_compact (scope, minute, session);
      CREATE TABLE usage_compact_context (session TEXT PRIMARY KEY, state TEXT NOT NULL) WITHOUT ROWID;
      CREATE TABLE usage_compact_moving (session TEXT PRIMARY KEY, target TEXT NOT NULL, phase INTEGER NOT NULL DEFAULT 0, after_minute INTEGER,
        after_thread INTEGER, after_person TEXT, after_profile TEXT, after_runtime TEXT, after_model TEXT, after_fast INTEGER) WITHOUT ROWID;
      CREATE TABLE usage_compact_moving_scope (scope TEXT NOT NULL, session TEXT NOT NULL, PRIMARY KEY (scope, session)) WITHOUT ROWID;
      CREATE INDEX usage_compact_moving_by_session ON usage_compact_moving_scope (session, scope);
      CREATE TRIGGER usage_compact_session_move AFTER UPDATE OF ws ON sessions
        WHEN OLD.ws IS NOT NEW.ws AND EXISTS (SELECT 1 FROM usage_compact WHERE session = NEW.key LIMIT 1) BEGIN
          INSERT INTO usage_compact_moving (session, target) VALUES (NEW.key, ${scopeOf("NEW.ws")})
            ON CONFLICT (session) DO UPDATE SET target = excluded.target, phase = 0, after_minute = NULL;
          INSERT OR IGNORE INTO usage_compact_moving_scope VALUES (${scopeOf("OLD.ws")}, NEW.key), (${scopeOf("NEW.ws")}, NEW.key);
      END;
      CREATE TRIGGER usage_compact_session_drop AFTER DELETE ON sessions
        WHEN EXISTS (SELECT 1 FROM usage_compact WHERE session = OLD.key LIMIT 1) BEGIN
          INSERT INTO usage_compact_moving (session, target) VALUES (OLD.key, 'H')
            ON CONFLICT (session) DO UPDATE SET target = excluded.target, phase = 0, after_minute = NULL;
          INSERT OR IGNORE INTO usage_compact_moving_scope VALUES (${scopeOf("OLD.ws")}, OLD.key), ('H', OLD.key);
      END;
      CREATE TRIGGER usage_compact_session_add AFTER INSERT ON sessions
        WHEN EXISTS (SELECT 1 FROM usage_compact WHERE session = NEW.key LIMIT 1) BEGIN
          INSERT INTO usage_compact_moving (session, target) VALUES (NEW.key, ${scopeOf("NEW.ws")})
            ON CONFLICT (session) DO UPDATE SET target = excluded.target, phase = 0, after_minute = NULL;
          INSERT OR IGNORE INTO usage_compact_moving_scope VALUES ('H', NEW.key), (${scopeOf("NEW.ws")}, NEW.key);
      END;
      CREATE TRIGGER usage_compact_first_add AFTER INSERT ON usage WHEN NEW.compact_counted = 1
        AND (SELECT first_unknown FROM usage_compact_since WHERE id = 1) = 0
        AND ((SELECT first_at FROM usage_compact_since WHERE id = 1) IS NULL OR NEW.at < (SELECT first_at FROM usage_compact_since WHERE id = 1)) BEGIN
          UPDATE usage_compact_since SET first_at = NEW.at WHERE id = 1;
      END;
      CREATE TRIGGER usage_compact_first_drop AFTER DELETE ON usage WHEN OLD.compact_counted = 1
        AND OLD.at = (SELECT first_at FROM usage_compact_since WHERE id = 1) BEGIN
          UPDATE usage_compact_since SET first_at = NULL, first_unknown = 1 WHERE id = 1;
      END;
      CREATE TRIGGER usage_compact_first_move AFTER UPDATE OF at, compact_counted ON usage
        WHEN OLD.at IS NOT NEW.at OR OLD.compact_counted IS NOT NEW.compact_counted BEGIN
          UPDATE usage_compact_since SET first_at = NULL, first_unknown = 1 WHERE id = 1
            AND OLD.compact_counted = 1 AND OLD.at = first_at AND (OLD.at IS NOT NEW.at OR NEW.compact_counted <> 1);
          UPDATE usage_compact_since SET first_at = NEW.at WHERE id = 1 AND first_unknown = 0
            AND NEW.compact_counted = 1 AND (first_at IS NULL OR NEW.at < first_at);
      END;
      -- REPLACE can delete a call without running DELETE triggers. The station updates an existing call in place,
      -- so reject duplicate inserts rather than letting the raw row and its statistics disagree.
      CREATE TRIGGER usage_compact_no_replace BEFORE INSERT ON usage
        WHEN EXISTS (SELECT 1 FROM usage WHERE id = NEW.id) BEGIN
          SELECT RAISE(ABORT, 'recorded usage must be updated in place');
      END;
      CREATE TRIGGER usage_compact_add AFTER INSERT ON usage WHEN NEW.compact_counted = 1 BEGIN
        ${scope("NEW")}
        ${add("NEW")}
      END;
      CREATE TRIGGER usage_compact_drop BEFORE DELETE ON usage WHEN OLD.compact_counted = 1 BEGIN ${remove("OLD")} END;
      CREATE TRIGGER usage_compact_old_add AFTER INSERT ON usage WHEN NEW.compact_counted = 0 BEGIN ${oldAddAll("NEW")} END;
      CREATE TRIGGER usage_compact_old_drop BEFORE DELETE ON usage WHEN OLD.compact_counted = 0 BEGIN ${oldRemoveAll("OLD")} END;
      CREATE TRIGGER usage_compact_old_change BEFORE UPDATE OF at, session, runtime, model, calls, input, cache_read,
        cache_write, cache_write_long, output, compact_counted ON usage WHEN OLD.compact_counted = 0 BEGIN ${oldRemoveAll("OLD")} END;
      CREATE TRIGGER usage_compact_old_changed AFTER UPDATE OF at, session, runtime, model, calls, input, cache_read,
        cache_write, cache_write_long, output, compact_counted ON usage WHEN OLD.compact_counted = 0 BEGIN ${oldAddAll("NEW")} END;
      CREATE TRIGGER usage_compact_change AFTER UPDATE OF at, session, thread, person, profile, runtime, model, fast,
        calls, input, cache_read, cache_write, cache_write_long, output, compact_counted ON usage
        WHEN (OLD.compact_counted = 1 OR NEW.compact_counted = 1) AND (${dimensionsChanged}) BEGIN
          ${scope("NEW")} ${remove("OLD")} ${add("NEW")}
      END;
      CREATE TRIGGER usage_compact_adjust AFTER UPDATE OF calls, input, cache_read, cache_write, cache_write_long, output ON usage
        WHEN OLD.compact_counted = 1 AND NEW.compact_counted = 1 AND NOT (${dimensionsChanged}) AND (${valuesChanged}) BEGIN
          UPDATE usage_compact SET ${cols.map((c) => `${c} = ${c} + NEW.${c} - OLD.${c}`).join(", ")} WHERE ${key("NEW")};
      END;`);
    db.prepare("INSERT INTO usage_compact_since (id, since, old_days, old_minutes) VALUES (1, ?, ?, ?)")
      .run(now(), oldDays ? 1 : 0, oldMinutes ? 1 : 0);
    const triggers = db.prepare(`SELECT name FROM sqlite_master WHERE type = 'trigger' AND
      (name LIKE 'usage_detail_%' OR name LIKE 'usage_daily_detail_%' OR name LIKE 'usage_main_calls_%'
       OR name IN ('usage_minute_add', 'usage_minute_drop', 'usage_minute_grow', 'usage_quarters_add', 'usage_quarters_drop',
                   'usage_quarters_grow', 'usage_compactions_add', 'usage_span_add', 'usage_span_drop', 'usage_span_move'))`).all() as { name: string }[];
    for (const { name } of triggers) db.exec(`DROP TRIGGER "${name.replaceAll('"', '""')}"`);
    // Retire the old writers in the same transaction that starts the compact ones. Otherwise a call made between
    // those two operations can be missing from both the saved daily totals and the new statistics.
    if (!has("usage_retired_detail")) {
      db.exec("CREATE TABLE usage_retired_detail (id INTEGER PRIMARY KEY CHECK (id = 1)); INSERT INTO usage_retired_detail VALUES (1)");
    }
    db.exec("COMMIT");
  } catch (error) { db.exec("ROLLBACK"); throw error; }
}

/// Rows for complete minutes. The public usage page asks at local-day boundaries, all of which are minute-aligned.
export class PartialMinuteUsage extends Error {
  constructor() { super("partial-minute usage requires paged calls"); }
}

/// A moved session is unavailable in both affected workspaces until its buckets have been re-scoped in small batches.
export function compactScopeReady(db: DatabaseSync, viewer: InWorkspace | null): boolean {
  if (viewer === null) return db.prepare("SELECT 1 FROM usage_compact_moving LIMIT 1").get() === undefined;
  const ws = `W${viewer.workspace}`;
  const sql = viewer.home ? "SELECT 1 FROM usage_compact_moving_scope WHERE scope IN (?, 'H') LIMIT 1"
    : "SELECT 1 FROM usage_compact_moving_scope WHERE scope = ? LIMIT 1";
  return db.prepare(sql).get(ws) === undefined;
}

type Moving = { session: string; target: string; phase: number; after_minute: number | null; after_thread: number | null;
  after_person: string | null; after_profile: string | null; after_runtime: string | null; after_model: string | null; after_fast: number | null };
type Bucket = { minute: number; thread: number; person: string; profile: string; runtime: string; model: string; fast: number; scope: string };

/// Re-scope at most one batch. The cursor is reset if the session moves again; writes during a move use its current scope.
export function moveCompactStep(db: DatabaseSync, batch = 256): { done: boolean; session?: string } {
  db.exec("BEGIN IMMEDIATE");
  try {
    const move = db.prepare("SELECT * FROM usage_compact_moving ORDER BY session LIMIT 1").get() as Moving | undefined;
    if (move === undefined) { db.exec("COMMIT"); return { done: true }; }
    if (move.phase === 1) {
      const removed = db.prepare(`DELETE FROM usage_compact_moving_scope WHERE (scope, session) IN (
        SELECT scope, session FROM usage_compact_moving_scope INDEXED BY usage_compact_moving_by_session
        WHERE session = ? AND scope <> ? LIMIT ?)`).run(move.session, move.target, batch).changes;
      if (removed === 0) {
        db.prepare("DELETE FROM usage_compact_moving_scope WHERE scope = ? AND session = ?").run(move.target, move.session);
        db.prepare("DELETE FROM usage_compact_moving WHERE session = ?").run(move.session);
        db.exec("COMMIT");
        return { done: false, session: move.session };
      }
      db.exec("COMMIT");
      return { done: false };
    }
    const after = move.after_minute === null ? "" : " AND (minute, thread, person, profile, runtime, model, fast) > (?, ?, ?, ?, ?, ?, ?)";
    const args = move.after_minute === null ? [move.session, batch] : [move.session, move.after_minute, move.after_thread,
      move.after_person, move.after_profile, move.after_runtime, move.after_model, move.after_fast, batch];
    const rows = db.prepare(`SELECT minute, thread, person, profile, runtime, model, fast, scope FROM usage_compact
      WHERE session = ?${after} ORDER BY minute, thread, person, profile, runtime, model, fast LIMIT ?`).all(...args) as Bucket[];
    const update = db.prepare(`UPDATE usage_compact SET scope = ? WHERE session = ? AND minute = ? AND thread = ?
      AND person = ? AND profile = ? AND runtime = ? AND model = ? AND fast = ?`);
    for (const row of rows) if (row.scope !== move.target) update.run(move.target, move.session, row.minute, row.thread,
      row.person, row.profile, row.runtime, row.model, row.fast);
    if (rows.length < batch) {
      db.prepare("UPDATE usage_compact_moving SET phase = 1 WHERE session = ?").run(move.session);
      db.exec("COMMIT");
      return { done: false };
    }
    const last = rows.at(-1)!;
    db.prepare(`UPDATE usage_compact_moving SET after_minute = ?, after_thread = ?, after_person = ?, after_profile = ?,
      after_runtime = ?, after_model = ?, after_fast = ? WHERE session = ?`).run(last.minute, last.thread, last.person,
      last.profile, last.runtime, last.model, last.fast, move.session);
    db.exec("COMMIT");
    return { done: false };
  } catch (error) { db.exec("ROLLBACK"); throw error; }
}

export function compactQuery(from: bigint, to: bigint, offset: bigint, viewer: InWorkspace | null): { sql: string; args: (string | bigint)[] } {
  // Minute totals cannot answer a partial minute exactly. Callers needing those boundaries can page the original calls.
  if (from < to && (from % 60_000n !== 0n || (to !== 9223372036854775807n && to % 60_000n !== 0n))) {
    throw new PartialMinuteUsage();
  }
  const floor = (n: bigint) => n >= 0n ? n / 60_000n : -1n - ((-1n - n) / 60_000n);
  const start = from >= to ? 0n : floor(from);
  const end = from >= to ? 0n : to === 9223372036854775807n ? 9223372036854775807n : floor(to);
  const args: (string | bigint)[] = [offset, start, end];
  const scope = viewer === null ? "" : viewer.home === false ? "WHERE c.scope = ?4 AND sc.ws = ?5"
    : "WHERE c.scope IN (?4, 'H') AND (sc.ws = ?5 OR sc.ws IS NULL)";
  if (viewer !== null) args.push(`W${viewer.workspace}`, viewer.workspace);
  const source = viewer === null ? "FROM usage_compact c INDEXED BY usage_compact_time"
    : "FROM usage_compact c INDEXED BY usage_compact_scope_time CROSS JOIN usage_minute_scope sc ON sc.session = c.session";
  const condition = viewer === null ? "WHERE" : `${scope} AND`;
  const sql = `SELECT strftime('%Y-%m-%d', (c.minute + ?1) * 60, 'unixepoch') AS day,
    c.session, NULLIF(c.thread, 0) AS thread, NULLIF(c.person, '') AS person, NULLIF(c.profile, '') AS profile,
    c.runtime, NULLIF(c.model, '') AS model, c.fast, SUM(c.calls) AS calls, SUM(c.input) AS input,
    SUM(c.cache_read) AS cache_read, SUM(c.cache_write) AS cache_write, SUM(c.cache_write_long) AS cache_write_long, SUM(c.output) AS output
    ${source} ${condition} c.minute >= ?2 AND c.minute < ?3
    GROUP BY day, c.session, c.thread, c.person, c.profile, c.runtime, c.model, c.fast`;
  return { sql, args };
}

/// Preserve a complete old daily summary and add only the new minute buckets. If the old minute coverage was already
/// retired, a non-quarter-hour zone cannot infer where the old quarter crossed midnight.
export function compactHistory(db: DatabaseSync, offset: bigint, viewer: InWorkspace | null): { day: string; session: string; runtime: string; model: string | null; tokens: number; calls: number }[] | null {
  if (!compactScopeReady(db, viewer)) return null;
  const coverage = db.prepare("SELECT old_days, old_minutes FROM usage_compact_since WHERE id = 1").get() as { old_days: number; old_minutes: number };
  const aligned = offset % 15n === 0n;
  if (!coverage.old_days || (!aligned && !coverage.old_minutes)) return null;
  const args: (string | bigint)[] = [offset];
  const source = (table: string, alias: string) => viewer === null ? `FROM ${table} ${alias}`
    : `FROM usage_minute_scope sc INDEXED BY usage_minute_scope_ws CROSS JOIN ${table} ${alias} ON ${alias}.session = sc.session`;
  const where = viewer === null ? "" : viewer.home === false ? "WHERE sc.ws = ?2" : "WHERE (sc.ws = ?2 OR sc.ws IS NULL)";
  if (viewer !== null) args.push(viewer.workspace, `W${viewer.workspace}`);
  const old = aligned ? "usage_day_quarters" : "usage_minute";
  const oldMinute = aligned ? "q.quarter * 15" : "q.minute";
  const compactSource = viewer === null ? "FROM usage_compact c" :
    "FROM usage_compact c INDEXED BY usage_compact_scope_time CROSS JOIN usage_minute_scope sc ON sc.session = c.session";
  const compactWhere = viewer === null ? "" : viewer.home ? "WHERE c.scope IN (?3, 'H') AND (sc.ws = ?2 OR sc.ws IS NULL)"
    : "WHERE c.scope = ?3 AND sc.ws = ?2";
  const sql = `WITH parts AS (
    SELECT ${oldMinute} AS minute, q.session, q.runtime, q.model, q.calls, q.tokens ${source(old, "q")} ${where}
    UNION ALL
    SELECT c.minute, c.session, c.runtime, c.model, c.calls,
      c.input + c.cache_read + c.cache_write + c.cache_write_long + c.output AS tokens ${compactSource} ${compactWhere}
  ) SELECT strftime('%Y-%m-%d', (minute + ?1) * 60, 'unixepoch') AS day, session, runtime, NULLIF(model, '') AS model,
    SUM(tokens) AS tokens, SUM(calls) AS calls FROM parts GROUP BY day, session, runtime, model`;
  return (db.prepare(sql).all(...args) as { day: string; session: string; runtime: string; model: string | null; tokens: number; calls: number }[])
    .map((row) => ({ ...row, tokens: Number(row.tokens), calls: Number(row.calls) }));
}

type RecentCall = ContextCall & { id: string };
type SavedContext = { runtimeSession: string; model: string | null; contextWindow: number | null; lastCallAt: number;
  contextTokens?: number; cacheMs?: number; rereadCost?: number };
type Recent = { calls: RecentCall[]; turns: { id: string | null; compacted: boolean }[]; uncertain: boolean; saved?: SavedContext };
function recent(db: DatabaseSync, session: string): Recent {
  const row = db.prepare("SELECT state FROM usage_compact_context WHERE session = ?").get(session) as { state: string } | undefined;
  return row === undefined ? { calls: [], turns: [], uncertain: false } : JSON.parse(row.state) as Recent;
}

/// A saved summary can seed a context only while it still represents every call and the current runtime session.
/// This is one session's existing summary and totals, not a read of its old calls. An uncertain snapshot is left out.
export function seedCompactContext(db: DatabaseSync, session: string): void {
  if (db.prepare("SELECT 1 FROM usage_compact_context WHERE session = ?").get(session)) return;
  const row = db.prepare(`SELECT u.usage, s.runtime_session_id AS runtime, r.at AS began
    FROM session_usage u JOIN sessions s ON s.key = u.session
    LEFT JOIN runtime_sessions r ON r.session_key = s.key AND r.id = s.runtime_session_id WHERE u.session = ?`).get(session) as
    { usage: string; runtime: string | null; began: number | null } | undefined;
  if (row === undefined || row.runtime === null || row.began === null) return;
  const old = JSON.parse(row.usage) as Record<string, unknown>;
  const total = db.prepare("SELECT COALESCE(SUM(calls), 0) AS n FROM usage_totals WHERE session = ? AND calls > 0").get(session) as { n: number };
  if (old.modelCalls !== total.n || typeof old.lastCallAt !== "number" || old.lastCallAt < row.began
    || (old.model !== null && typeof old.model !== "string")
    || (old.contextWindow !== null && typeof old.contextWindow !== "number")) return;
  const saved: SavedContext = { runtimeSession: row.runtime, model: old.model as string | null,
    contextWindow: old.contextWindow as number | null, lastCallAt: old.lastCallAt };
  for (const name of ["contextTokens", "cacheMs", "rereadCost"] as const) {
    if (typeof old[name] === "number") saved[name] = old[name];
  }
  const state: Recent = { calls: [], turns: [], uncertain: false, saved };
  db.prepare("INSERT INTO usage_compact_context VALUES (?, ?)").run(session, JSON.stringify(state));
}

export function savedCompactContext(db: DatabaseSync, session: string): SavedContext | null {
  const saved = recent(db, session).saved;
  if (saved === undefined) return null;
  const row = db.prepare("SELECT runtime_session_id AS id FROM sessions WHERE key = ?").get(session) as { id: string | null } | undefined;
  return row?.id === saved.runtimeSession ? saved : null;
}

/// The last five contexts and whether the last two turns compacted are bounded session statistics, not a copy of every call.
export function noteCompactContexts(db: DatabaseSync, session: string, calls: [UsageCall, UsageFor][]): void {
  const state = recent(db, session);
  for (const [call, of] of calls) {
    const previous = state.calls.at(-1);
    const next: RecentCall = { id: call.id, turn: of.turn, profile: of.profile, model: call.model, context: call.context,
      window: call.window, at: call.at, fast: call.fast, cacheWrite: call.cacheWrite, cacheWriteLong: call.cacheWriteLong };
    const ordered = previous === undefined || call.at > previous.at || (call.at === previous.at && call.id > previous.id);
    if (!ordered) {
      // An out-of-order call cannot prove the transition between turns from a bounded tail; do not use it for moving an account.
      state.uncertain = true;
      state.turns = [];
    } else {
      if (state.turns.at(-1)?.id !== of.turn || state.turns.length === 0) {
        state.turns.push({ id: of.turn, compacted: false });
        if (state.turns.length > 2) { state.turns.shift(); state.uncertain = false; }
      }
      if (previous !== undefined && previous.context !== null && call.context !== null && call.model !== null
        && previous.context >= COMPACTED_FROM && call.context * 2 < previous.context
        && previous.profile === of.profile && previous.model === call.model) {
        state.turns[state.turns.length - 1]!.compacted = true;
      }
    }
    state.calls.push(next);
    state.calls.sort((a, b) => a.at - b.at || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
    state.calls = state.calls.slice(-5);
  }
  db.prepare("INSERT INTO usage_compact_context VALUES (?, ?) ON CONFLICT (session) DO UPDATE SET state = excluded.state")
    .run(session, JSON.stringify(state));
}

export function compactContexts(db: DatabaseSync, session: string, limit: number): ContextCall[] {
  return limit <= 0 ? [] : recent(db, session).calls.slice(-limit).map(({ id: _id, ...call }) => call);
}

export function compactRecentlyCompacted(db: DatabaseSync, session: string): boolean {
  const state = recent(db, session);
  return !state.uncertain && state.turns.some((turn) => turn.compacted);
}
