// Incremental usage summaries. Calls remain in usage; only one minute bucket per set of dimensions is maintained.
import type { DatabaseSync } from "node:sqlite";
import type { InWorkspace } from "./rows.ts";
import { COMPACTED_FROM } from "./rows.ts";
import type { ContextCall, UsageCall, UsageFor } from "./usage.ts";

const minute = (r: string) => `(CASE WHEN ${r}.at >= 0 THEN ${r}.at / 60000 ELSE -1 - ((-1 - ${r}.at) / 60000) END)`;
const cols = ["calls", "input", "cache_read", "cache_write", "cache_write_long", "output"] as const;
// A signed SQLite millisecond timestamp fits in 49 bits once rounded down to a minute and shifted by this bias.
// Seven base-256 levels cover that space, with at most 255 nodes per level in a prefix.
const MINUTE_BIAS = 2 ** 48;
const TREE_LEVELS = 7;
const TOTALS_BATCH = 64;
const scopeOf = (value: string) => `(CASE WHEN ${value} IS NULL THEN 'H' ELSE 'W' || ${value} END)`;
const sessionScope = (r: string) => scopeOf(`(SELECT ws FROM sessions WHERE key = ${r}.session)`);
const fields = (r: string) => `${r}.session, ${minute(r)}, COALESCE(${r}.thread, 0), COALESCE(${r}.person, ''),
  COALESCE(${r}.profile, ''), ${r}.runtime, COALESCE(${r}.model, ''), ${r}.fast`;
const key = (r: string) => `session = ${r}.session AND minute = ${minute(r)} AND thread = COALESCE(${r}.thread, 0)
  AND person = COALESCE(${r}.person, '') AND profile = COALESCE(${r}.profile, '') AND runtime = ${r}.runtime
  AND model = COALESCE(${r}.model, '') AND fast = ${r}.fast`;
const add = (r: string) => `INSERT INTO usage_compact
  (session, minute, thread, person, profile, runtime, model, fast, records, ${cols.join(", ")}, scope)
  SELECT ${fields(r)}, 1, ${cols.map((c) => `${r}.${c}`).join(", ")}, ${sessionScope(r)}
  WHERE ${r}.compact_counted = 1 ON CONFLICT (session, minute, thread, person, profile, runtime, model, fast) DO UPDATE SET
  records = records + 1, ${cols.map((c) => `${c} = ${c} + excluded.${c}`).join(", ")};`;
const remove = (r: string) => `UPDATE usage_compact SET records = records - 1, ${cols.map((c) => `${c} = ${c} - ${r}.${c}`).join(", ")}
  WHERE ${r}.compact_counted = 1 AND ${key(r)};`;
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
const invalidateContext = (session: string, when = "1") => `
  UPDATE usage_totals SET compact_context = NULL WHERE session = ${session} AND (${when})
    AND (runtime, model, fast) = (SELECT context_runtime, context_model, context_fast FROM usage_minute_scope WHERE session = ${session})
    AND compact_context IS NOT NULL;
  UPDATE usage_minute_scope SET context_runtime = NULL, context_model = NULL, context_fast = NULL, context_uncertain = 1,
    context_after = (SELECT at FROM usage INDEXED BY usage_session WHERE session = ${session} ORDER BY at DESC LIMIT 1)
    WHERE session = ${session} AND (${when});`;
const contextColumns = ["id", "at", "session", "turn", "profile", "runtime", "model", "subagent", "fast", "context", "context_window", "cache_write", "cache_write_long"];
const contextChanged = contextColumns.map((c) => `OLD.${c} IS NOT NEW.${c}`).join(" OR ");
const contextChange = `CREATE TRIGGER usage_compact_context_change AFTER UPDATE OF ${contextColumns.join(", ")} ON usage
        WHEN (OLD.subagent = 0 OR NEW.subagent = 0) AND (${contextChanged}) BEGIN
          ${invalidateContext("OLD.session")}
          ${invalidateContext("NEW.session")}
      END;`;

export function hasCompactUsage(db: DatabaseSync): boolean {
  if (compactInstalled.has(db)) return true;
  const installed = db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'usage_compact_since'").get() !== undefined;
  // Once there, known for that connection and not asked again at each usage record: the schema migrates forward only,
  // and nothing drops it. Not there is asked again: another connection (the process before, at a handover) may make it.
  if (installed) compactInstalled.add(db);
  return installed;
}
const compactInstalled = new WeakSet<DatabaseSync>();

/// A bounded journal of future changes lets a reader reuse its own snapshot of unchanged hours. It starts empty:
/// installing it neither walks nor modifies existing statistics. A NULL minute invalidates a session's ownership.
export function installUsageSummaryChanges(db: DatabaseSync): void {
  const installed = () => db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'usage_summary_changes'").get() !== undefined;
  if (!hasCompactUsage(db) || installed()) return;
  const changed = ["scope", "session", "minute", "thread", "person", "profile", "runtime", "model", "fast"];
  const sameBucket = "OLD.scope IS NEW.scope AND OLD.session IS NEW.session AND OLD.minute IS NEW.minute";
  const insert = (r: string, value: string) => `INSERT INTO usage_summary_changes (scope, session, minute) VALUES (${value}, ${r}.session, ${r}.minute);`;
  db.exec("BEGIN IMMEDIATE");
  try {
    if (!installed()) db.exec(`
      CREATE TABLE usage_summary_changes (seq INTEGER PRIMARY KEY, scope TEXT NOT NULL, session TEXT NOT NULL, minute INTEGER);
      CREATE TRIGGER usage_summary_prune AFTER INSERT ON usage_summary_changes WHEN NEW.seq % 64 = 0 BEGIN
        DELETE FROM usage_summary_changes WHERE seq <= NEW.seq - 4096;
      END;
      -- REPLACE need not fire DELETE triggers. Remember a conflicting bucket's former scope before it is replaced.
      CREATE TRIGGER usage_summary_replace BEFORE INSERT ON usage_compact BEGIN
        INSERT INTO usage_summary_changes (scope, session, minute)
          SELECT scope, session, minute FROM usage_compact WHERE session = NEW.session AND minute = NEW.minute
            AND thread = NEW.thread AND person = NEW.person AND profile = NEW.profile AND runtime = NEW.runtime
            AND model = NEW.model AND fast = NEW.fast AND scope IS NOT NEW.scope AND (records > 0 OR pending = 1);
      END;
      CREATE TRIGGER usage_summary_add AFTER INSERT ON usage_compact WHEN NEW.pending = 0 BEGIN ${insert("NEW", "NEW.scope")} END;
      CREATE TRIGGER usage_summary_change AFTER UPDATE OF ${changed.join(", ")} ON usage_compact
        WHEN ${changed.map((c) => `OLD.${c} IS NOT NEW.${c}`).join(" OR ")} BEGIN
          ${insert("OLD", "OLD.scope")}
          INSERT INTO usage_summary_changes (scope, session, minute)
            SELECT NEW.scope, NEW.session, NEW.minute WHERE NOT (${sameBucket});
      END;
      -- Inserts and value changes make the bucket pending. Readers check that index on each reuse; accounting the
      -- bucket records its final state before it leaves the index, in the total worker's already-batched transaction.
      CREATE TRIGGER usage_summary_accounted AFTER UPDATE OF pending ON usage_compact
        WHEN OLD.pending = 1 AND NEW.pending = 0 BEGIN ${insert("NEW", "NEW.scope")} END;
      CREATE TRIGGER usage_summary_drop AFTER DELETE ON usage_compact WHEN OLD.records > 0 OR OLD.pending = 1 BEGIN ${insert("OLD", "OLD.scope")} END;
      CREATE TRIGGER usage_summary_owner_replace BEFORE INSERT ON usage_minute_scope BEGIN
        INSERT INTO usage_summary_changes (scope, session, minute)
          SELECT ${scopeOf("ws")}, session, NULL FROM usage_minute_scope
            WHERE session = NEW.session AND ws IS NOT NEW.ws;
      END;
      CREATE TRIGGER usage_summary_owner_add AFTER INSERT ON usage_minute_scope BEGIN
        INSERT INTO usage_summary_changes (scope, session, minute) VALUES (${scopeOf("NEW.ws")}, NEW.session, NULL);
      END;
      CREATE TRIGGER usage_summary_owner_change AFTER UPDATE OF ws ON usage_minute_scope WHEN OLD.ws IS NOT NEW.ws BEGIN
        INSERT INTO usage_summary_changes (scope, session, minute) VALUES (${scopeOf("OLD.ws")}, OLD.session, NULL);
        INSERT INTO usage_summary_changes (scope, session, minute) VALUES (${scopeOf("NEW.ws")}, NEW.session, NULL);
      END;
      CREATE TRIGGER usage_summary_owner_drop AFTER DELETE ON usage_minute_scope BEGIN
        INSERT INTO usage_summary_changes (scope, session, minute) VALUES (${scopeOf("OLD.ws")}, OLD.session, NULL);
      END;
    `);
    db.exec("COMMIT");
  } catch (error) { db.exec("ROLLBACK"); throw error; }
}

export function compactCoverageSince(db: DatabaseSync): number {
  return (db.prepare("SELECT since FROM usage_compact_since WHERE id = 1").get() as { since: number }).since;
}

export function setCompactCoverageSince(db: DatabaseSync, since: number): void {
  db.prepare("UPDATE usage_compact_since SET since = ? WHERE id = 1").run(since);
}

/// An old call taken in (usage-fill.ts) says nothing new of a session's context. A station whose trigger came before
/// this would lose the context of every session it has old calls of. In the caller's write.
export function keepContextOnFill(db: DatabaseSync): void {
  const trigger = db.prepare("SELECT sql FROM sqlite_master WHERE type = 'trigger' AND name = 'usage_compact_context_change'").get() as { sql: string } | undefined;
  if (trigger === undefined || !trigger.sql.includes("compact_counted")) return;
  db.exec(`DROP TRIGGER usage_compact_context_change; ${contextChange}`);
}

export function compactUsageSince(db: DatabaseSync): number {
  const row = db.prepare("SELECT since, first_at, first_unknown FROM usage_compact_since WHERE id = 1").get() as
    { since: number; first_at: number | null; first_unknown: number };
  return row.first_unknown || row.first_at === null ? row.since : Math.max(row.since, row.first_at);
}

// Existing databases can have the older positional totals INSERT. Adding a column without changing that trigger
// would make the next call fail. Keep the old totals logic, but name its columns and retain a row that owns context.
function adaptTotalsWriters(db: DatabaseSync): void {
  for (const name of ["usage_totals_add", "usage_totals_source_aggregate_add", "usage_totals_source_aggregate_change", "usage_totals_source_aggregate_drop"]) {
    const row = db.prepare("SELECT sql FROM sqlite_master WHERE type = 'trigger' AND name = ?").get(name) as { sql: string } | undefined;
    if (!row) continue;
    let sql = row.sql;
    if (name.endsWith("_add")) {
      sql = sql.replace(/INSERT\s+INTO\s+usage_totals\s+VALUES\s*\(/i,
        "INSERT INTO usage_totals (session, runtime, model, fast, calls, input, cache_read, cache_write, cache_write_long, output) VALUES (");
      if (!/INSERT\s+INTO\s+usage_totals\s*\(/i.test(sql)) throw new Error(`cannot adapt ${name}`);
    } else {
      const deletion = /DELETE\s+FROM\s+usage_totals\b[^;]*;/i;
      const match = sql.match(deletion);
      if (!match) throw new Error(`cannot adapt ${name}`);
      if (!/\bcompact_context\b/i.test(match[0])) sql = sql.replace(deletion, (statement) => `${statement.slice(0, -1)} AND compact_context IS NULL;`);
    }
    if (sql !== row.sql) db.exec(`DROP TRIGGER "${name}"; ${sql}`);
  }
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
      ALTER TABLE usage_totals ADD COLUMN compact_context TEXT;
      ALTER TABLE usage_minute_scope ADD COLUMN context_runtime TEXT;
      ALTER TABLE usage_minute_scope ADD COLUMN context_model TEXT;
      ALTER TABLE usage_minute_scope ADD COLUMN context_fast INTEGER;
      ALTER TABLE usage_minute_scope ADD COLUMN context_uncertain INTEGER NOT NULL DEFAULT 0;
      ALTER TABLE usage_minute_scope ADD COLUMN context_after INTEGER;
      CREATE TABLE usage_compact_since (id INTEGER PRIMARY KEY CHECK (id = 1), since INTEGER NOT NULL, old_days INTEGER NOT NULL,
        old_minutes INTEGER NOT NULL, first_at INTEGER, first_unknown INTEGER NOT NULL DEFAULT 0);
      CREATE TABLE usage_compact (session TEXT NOT NULL, minute INTEGER NOT NULL, thread INTEGER NOT NULL, person TEXT NOT NULL,
        profile TEXT NOT NULL, runtime TEXT NOT NULL, model TEXT NOT NULL, fast INTEGER NOT NULL, records INTEGER NOT NULL,
        calls INTEGER NOT NULL, input INTEGER NOT NULL, cache_read INTEGER NOT NULL, cache_write INTEGER NOT NULL,
        cache_write_long INTEGER NOT NULL, output INTEGER NOT NULL, scope TEXT NOT NULL,
        accounted_scope TEXT, accounted_calls INTEGER NOT NULL DEFAULT 0, accounted_tokens INTEGER NOT NULL DEFAULT 0,
        pending INTEGER NOT NULL DEFAULT 1,
        PRIMARY KEY (session, minute, thread, person, profile, runtime, model, fast)) WITHOUT ROWID;
      CREATE INDEX usage_compact_time ON usage_compact (minute, session);
      CREATE INDEX usage_compact_scope_time ON usage_compact (scope, minute, session);
      CREATE INDEX usage_compact_pending_scope ON usage_compact (scope, session) WHERE pending = 1;
      CREATE INDEX usage_compact_pending_session ON usage_compact (session) WHERE pending = 1;
      -- 'G' is all scopes, 'H' is the home-only scope and 'W' prefixes a workspace id. New buckets start empty, so
      -- this total is maintained only from later writes; installing it never reads or reconstructs old usage.
      CREATE TABLE usage_compact_total (scope TEXT PRIMARY KEY, calls INTEGER NOT NULL, tokens INTEGER NOT NULL) WITHOUT ROWID;
      CREATE TABLE usage_compact_total_tree (scope TEXT NOT NULL, level INTEGER NOT NULL, bucket INTEGER NOT NULL,
        calls INTEGER NOT NULL, tokens INTEGER NOT NULL, PRIMARY KEY (scope, level, bucket)) WITHOUT ROWID;
      CREATE TRIGGER usage_compact_total_dirty AFTER UPDATE OF scope, records, calls, input, cache_read, cache_write, cache_write_long, output ON usage_compact
        WHEN OLD.pending = 0 AND (OLD.scope IS NOT NEW.scope OR OLD.records IS NOT NEW.records OR OLD.calls IS NOT NEW.calls
          OR ${cols.slice(1).map((c) => `OLD.${c} IS NOT NEW.${c}`).join(" OR ")}) BEGIN
        UPDATE usage_compact SET pending = 1 WHERE session = NEW.session AND minute = NEW.minute AND thread = NEW.thread
          AND person = NEW.person AND profile = NEW.profile AND runtime = NEW.runtime AND model = NEW.model AND fast = NEW.fast;
      END;
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
      -- Older stations omit compact_counted and grow responses with an upsert. Route their new calls through the
      -- compact writers and preserve their output-only update semantics, even after this station is replaced.
      CREATE TRIGGER usage_compact_legacy_insert BEFORE INSERT ON usage WHEN NEW.compact_counted = 0 BEGIN
        INSERT INTO usage_minute_scope (session, ws, done)
          SELECT NEW.session, (SELECT ws FROM sessions WHERE key = NEW.session), 1
          WHERE NEW.subagent = 0 AND NOT EXISTS (SELECT 1 FROM usage WHERE id = NEW.id)
          ON CONFLICT (session) DO UPDATE SET ws = excluded.ws WHERE ws IS NOT excluded.ws;
        ${invalidateContext("NEW.session", "NEW.subagent = 0 AND NOT EXISTS (SELECT 1 FROM usage WHERE id = NEW.id)")}
        UPDATE usage_minute_scope SET context_after = MAX(COALESCE(context_after, NEW.at), NEW.at)
          WHERE session = NEW.session AND NEW.subagent = 0 AND NOT EXISTS (SELECT 1 FROM usage WHERE id = NEW.id);
        UPDATE usage SET output = NEW.output WHERE id = NEW.id AND output < NEW.output;
        INSERT INTO usage (id, at, session, turn, thread, person, profile, runtime, model, subagent, fast, input, cache_read,
          cache_write, cache_write_long, output, calls, context, context_window, compact_counted)
          SELECT NEW.id, NEW.at, NEW.session, NEW.turn, NEW.thread, NEW.person, NEW.profile, NEW.runtime, NEW.model,
            NEW.subagent, NEW.fast, NEW.input, NEW.cache_read, NEW.cache_write, NEW.cache_write_long, NEW.output,
            NEW.calls, NEW.context, NEW.context_window, 1 WHERE NOT EXISTS (SELECT 1 FROM usage WHERE id = NEW.id);
        SELECT RAISE(IGNORE);
      END;
      -- REPLACE can delete a call without running DELETE triggers. New writers update existing calls in place,
      -- so reject their duplicate inserts rather than letting the raw row and its statistics disagree.
      CREATE TRIGGER usage_compact_no_replace BEFORE INSERT ON usage
        WHEN NEW.compact_counted = 1 AND EXISTS (SELECT 1 FROM usage WHERE id = NEW.id) BEGIN
          SELECT RAISE(ABORT, 'recorded usage must be updated in place');
      END;
      -- A bounded tail cannot reconstruct a removed or edited main call. Stop presenting the old context as current;
      -- later main calls build a new tail without reading the history.
      CREATE TRIGGER usage_compact_context_drop AFTER DELETE ON usage WHEN OLD.subagent = 0 BEGIN
        ${invalidateContext("OLD.session")}
      END;
      CREATE TRIGGER usage_compact_context_old_add AFTER INSERT ON usage WHEN NEW.compact_counted = 0 AND NEW.subagent = 0 BEGIN
        ${invalidateContext("NEW.session")}
      END;
      ${contextChange}
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
    adaptTotalsWriters(db);
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
    compactInstalled.add(db);
  } catch (error) { db.exec("ROLLBACK"); throw error; }
}

/// A moved session is unavailable in both affected workspaces until its buckets have been re-scoped in small batches.
export function compactScopeReady(db: DatabaseSync, viewer: InWorkspace | null): boolean {
  if (viewer === null) return db.prepare("SELECT 1 FROM usage_compact_moving LIMIT 1").get() === undefined;
  const ws = `W${viewer.workspace}`;
  const sql = viewer.home !== false ? "SELECT 1 FROM usage_compact_moving_scope WHERE scope IN (?, 'H') LIMIT 1"
    : "SELECT 1 FROM usage_compact_moving_scope WHERE scope = ? LIMIT 1";
  return db.prepare(sql).get(ws) === undefined;
}

/// The lifetime total of compacted calls alone, with readiness and value read from the same snapshot: what accounting
/// the pending buckets (compactTotalsStep) keeps, which the summary cache relies on (usage-batched.ts).
export function compactTotalQuery(viewer: InWorkspace | null, before?: bigint): { sql: string; args: string[] } {
  const scope = viewer === null ? "scope = 'G'" : viewer.home !== false ? "scope IN (?1, 'H')" : "scope = ?1";
  const moving = viewer === null ? "SELECT 1 FROM usage_compact_moving LIMIT 1"
    : `SELECT 1 FROM usage_compact_moving_scope WHERE ${scope} LIMIT 1`;
  const dirty = viewer === null ? "SELECT 1 FROM usage_compact INDEXED BY usage_compact_pending_session WHERE pending = 1 LIMIT 1"
    : `SELECT 1 FROM usage_compact INDEXED BY usage_compact_pending_scope WHERE pending = 1 AND ${scope} LIMIT 1`;
  // Cover [the earliest possible minute, before) with at most seven runs of at most 255 tree nodes. A request
  // therefore does not visit either earlier calls or arbitrarily many future-dated buckets.
  const bias = BigInt(MINUTE_BIAS);
  const edge = before === undefined ? 2n * bias : before + bias;
  const ranges: [number, number, number][] | null = edge >= 2n * bias ? null : [];
  if (ranges !== null) {
    const end = edge < 0n ? 0n : edge;
    let covered = 0n;
    for (let level = TREE_LEVELS - 1; level >= 0; level--) {
      const width = 1n << BigInt(8 * level);
      const count = (end - covered) / width;
      if (count > 0n) ranges.push([level, Number(covered / width), Number(covered / width + count)]);
      covered += count * width;
    }
  }
  const treeScope = viewer === null ? "t.scope = 'G'" : viewer.home !== false ? "t.scope IN (?1, 'H')" : "t.scope = ?1";
  const treeRanges = viewer === null ? "?1" : "?2";
  const prefix = ranges === null ? "" : `WITH ranges AS MATERIALIZED (
    SELECT json_extract(value, '$[0]') AS level, json_extract(value, '$[1]') AS lo, json_extract(value, '$[2]') AS hi
    FROM json_each(${treeRanges})
  ), prefix AS MATERIALIZED (
    SELECT COALESCE(SUM(t.calls), 0) AS calls, COALESCE(SUM(t.tokens), 0) AS tokens
    FROM ranges r CROSS JOIN usage_compact_total_tree t
    WHERE ${treeScope} AND t.level = r.level AND t.bucket >= r.lo AND t.bucket < r.hi
  )`;
  const value = (column: string) => ranges === null
    ? `(SELECT COALESCE(SUM(${column}), 0) FROM usage_compact_total WHERE ${scope})` : `(SELECT ${column} FROM prefix)`;
  return {
    sql: `${prefix} SELECT NOT EXISTS (${moving}) AND NOT EXISTS (${dirty}) AS ready,
      ${value("calls")} AS calls, ${value("tokens")} AS tokens`,
    args: [...(viewer === null ? [] : [`W${viewer.workspace}`]), ...(ranges === null ? [] : [JSON.stringify(ranges)])],
  };
}

/// Never serve a total until its pending buckets and scope moves finish.
export function compactTotal(db: DatabaseSync, viewer: InWorkspace | null, before?: bigint): { calls: number; tokens: number } | null {
  const query = compactTotalQuery(viewer, before);
  const row = db.prepare(query.sql).get(...query.args) as { ready: number; calls: number; tokens: number };
  return row.ready ? { calls: Number(row.calls), tokens: Number(row.tokens) } : null;
}

type Moving = { session: string; target: string; phase: number; after_minute: number | null; after_thread: number | null;
  after_person: string | null; after_profile: string | null; after_runtime: string | null; after_model: string | null; after_fast: number | null };
type Bucket = { minute: number; thread: number; person: string; profile: string; runtime: string; model: string; fast: number; scope: string };
type PendingBucket = Bucket & { session: string; records: number; calls: number; tokens: number;
  accounted_scope: string | null; accounted_calls: number; accounted_tokens: number };

// Called within an IMMEDIATE transaction. Each bucket keeps its previously applied contribution, so repeated writes
// coalesce and a removed bucket remains as a tombstone until its contribution is subtracted.
function accountCompactBuckets(db: DatabaseSync, batch: number, session?: string, scope?: string): { count: number; sessions: string[]; from?: number } {
  const selected = session !== undefined ? `INDEXED BY usage_compact_pending_session WHERE pending = 1 AND session = ? LIMIT ?`
    : scope !== undefined ? `INDEXED BY usage_compact_pending_scope WHERE pending = 1 AND scope = ? LIMIT ?`
    : `INDEXED BY usage_compact_pending_scope WHERE pending = 1 LIMIT ?`;
  const rows = db.prepare(`SELECT session, minute, thread, person, profile, runtime, model, fast, scope, records, calls,
    ${tokens("usage_compact")} AS tokens, accounted_scope, accounted_calls, accounted_tokens FROM usage_compact ${selected}`)
    .all(...(session !== undefined ? [session, batch] : scope !== undefined ? [scope, batch] : [batch])) as PendingBucket[];
  type Delta = { calls: number; tokens: number };
  const changes = new Map<string, Delta>();
  const trees = new Map<string, Map<string, Delta & { level: number; bucket: number }>>();
  const add = (scope: string, calls: number, tokens: number, minute: number) => {
    if (calls === 0 && tokens === 0) return;
    const prior = changes.get(scope) ?? { calls: 0, tokens: 0 };
    prior.calls += calls;
    prior.tokens += tokens;
    changes.set(scope, prior);
    let nodes = trees.get(scope);
    if (nodes === undefined) { nodes = new Map(); trees.set(scope, nodes); }
    const shifted = minute + MINUTE_BIAS;
    for (let level = 0; level < TREE_LEVELS; level++) {
      const bucket = Math.floor(shifted / 256 ** level);
      const key = `${level}:${bucket}`;
      const node = nodes.get(key) ?? { level, bucket, calls: 0, tokens: 0 };
      node.calls += calls;
      node.tokens += tokens;
      nodes.set(key, node);
    }
  };
  const update = db.prepare(`UPDATE usage_compact SET accounted_scope = scope, accounted_calls = calls,
    accounted_tokens = ${tokens("usage_compact")}, pending = 0 WHERE session = ? AND minute = ? AND thread = ?
    AND person = ? AND profile = ? AND runtime = ? AND model = ? AND fast = ?`);
  const drop = db.prepare(`DELETE FROM usage_compact WHERE session = ? AND minute = ? AND thread = ? AND person = ?
    AND profile = ? AND runtime = ? AND model = ? AND fast = ? AND records = 0`);
  for (const row of rows) {
    if (row.accounted_scope !== null) {
      add(row.accounted_scope, -row.accounted_calls, -row.accounted_tokens, row.minute);
      add("G", -row.accounted_calls, -row.accounted_tokens, row.minute);
    }
    add(row.scope, row.calls, row.tokens, row.minute);
    add("G", row.calls, row.tokens, row.minute);
    const key = [row.session, row.minute, row.thread, row.person, row.profile, row.runtime, row.model, row.fast] as const;
    update.run(...key);
    if (row.records === 0) drop.run(...key);
  }
  const put = db.prepare(`INSERT INTO usage_compact_total (scope, calls, tokens) VALUES (?, ?, ?)
    ON CONFLICT (scope) DO UPDATE SET calls = calls + excluded.calls, tokens = tokens + excluded.tokens`);
  const clean = db.prepare("DELETE FROM usage_compact_total WHERE scope = ? AND calls = 0 AND tokens = 0");
  for (const [scope, delta] of changes) {
    if (delta.calls !== 0 || delta.tokens !== 0) put.run(scope, delta.calls, delta.tokens);
    clean.run(scope);
  }
  const putNode = db.prepare(`INSERT INTO usage_compact_total_tree (scope, level, bucket, calls, tokens) VALUES (?, ?, ?, ?, ?)
    ON CONFLICT (scope, level, bucket) DO UPDATE SET calls = calls + excluded.calls, tokens = tokens + excluded.tokens`);
  const cleanNode = db.prepare("DELETE FROM usage_compact_total_tree WHERE scope = ? AND level = ? AND bucket = ? AND calls = 0 AND tokens = 0");
  for (const [scope, nodes] of trees) for (const node of nodes.values()) {
    if (node.calls === 0 && node.tokens === 0) continue;
    putNode.run(scope, node.level, node.bucket, node.calls, node.tokens);
    cleanNode.run(scope, node.level, node.bucket);
  }
  const from = rows.length === 0 ? undefined : Math.min(...rows.map((row) => row.minute * 60_000));
  return { count: rows.length, sessions: [...new Set(rows.map((row) => row.session))],
    ...(from !== undefined && Number.isSafeInteger(from) ? { from } : {}) };
}

/// Apply at most one batch of new buckets; this never reads or reconstructs original calls.
export function compactTotalsStep(db: DatabaseSync, batch = 256, scope?: string): { done: boolean; sessions: string[]; from?: number } {
  if (!Number.isSafeInteger(batch) || batch < 1) throw new RangeError("compact totals batch must be positive");
  batch = Math.min(batch, TOTALS_BATCH);
  db.exec("BEGIN IMMEDIATE");
  try {
    const { count, sessions, from } = accountCompactBuckets(db, batch, undefined, scope);
    db.exec("COMMIT");
    return { done: count < batch, sessions, ...(from !== undefined ? { from } : {}) };
  } catch (error) { db.exec("ROLLBACK"); throw error; }
}

/// Re-scope at most one batch. The cursor is reset if the session moves again; writes during a move use its current scope.
export function moveCompactStep(db: DatabaseSync, batch = 256, scope?: string): { done: boolean; session?: string } {
  if (!Number.isSafeInteger(batch) || batch < 1) throw new RangeError("compact workspace batch must be positive");
  batch = Math.min(batch, 256);
  db.exec("BEGIN IMMEDIATE");
  try {
    const move = (scope === undefined ? db.prepare("SELECT * FROM usage_compact_moving ORDER BY session LIMIT 1").get()
      : db.prepare(`SELECT m.* FROM usage_compact_moving_scope sc CROSS JOIN usage_compact_moving m ON m.session = sc.session
          WHERE sc.scope = ? ORDER BY sc.session LIMIT 1`).get(scope)) as Moving | undefined;
    if (move === undefined) { db.exec("COMMIT"); return { done: true }; }
    if (move.phase === 1) {
      // Keep every old scope unavailable until the session's pending contributions have actually left its totals.
      if (accountCompactBuckets(db, Math.min(batch, TOTALS_BATCH), move.session).count > 0) {
        db.exec("COMMIT");
        return { done: false };
      }
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

export function compactQuery(from: bigint, to: bigint, offset: bigint, viewer: InWorkspace | null, countParts = false,
  trackSelection = false): { sql: string; args: (string | bigint)[] } {
  // Minute totals cannot answer a partial minute exactly. Read original calls only at those two edges, after the
  // statistics have identified which sessions have calls there; the complete minutes still use their totals.
  if (from < to && (from % 60_000n !== 0n || (to !== 9223372036854775807n && to % 60_000n !== 0n))) {
    return compactQueryWithEdges(from, to, offset, viewer, countParts);
  }
  const floor = (n: bigint) => n >= 0n ? n / 60_000n : -1n - ((-1n - n) / 60_000n);
  const start = from >= to ? 0n : floor(from);
  const end = from >= to ? 0n : to === 9223372036854775807n ? 9223372036854775807n : floor(to);
  const args: (string | bigint)[] = [offset, start, end];
  if (viewer !== null) args.push(`W${viewer.workspace}`, viewer.workspace);
  const scope = viewer === null ? "" : viewer.home === false ? "scope = ?4 AND " : "scope IN (?4, 'H') AND ";
  const bucketScope = viewer === null ? "" : viewer.home === false ? "c.scope = ?4 AND " : "c.scope IN (?4, 'H') AND ";
  const index = viewer === null ? "usage_compact_time" : "usage_compact_scope_time";
  const eligible = viewer === null ? "SELECT session FROM selected" : `SELECT p.session FROM selected p
    CROSS JOIN usage_minute_scope sc ON sc.session = p.session
    WHERE ${viewer.home === false ? "sc.ws = ?5" : "(sc.ws = ?5 OR sc.ws IS NULL)"}`;
  // These callbacks touch no rows beyond those the query already reads. The marker runs once after selection, before
  // the first selected session's buckets; the counter sees candidates including buckets that later contribute nothing.
  const countCandidate = trackSelection ? " AND usage_summary_candidate()" : "";
  const marker = trackSelection ? ", selected_marker AS MATERIALIZED (SELECT usage_summary_selected() AS ready)" : "";
  const markerJoin = trackSelection ? " CROSS JOIN selected_marker marker" : "";
  const markerWhere = trackSelection ? "marker.ready = 1 AND " : "";
  // Find sessions through the covering time index, then read each session's buckets together in primary-key order.
  // Materializing the eligible sessions keeps the workspace check from being repeated for every minute.
  const sql = `WITH selected AS MATERIALIZED (
    SELECT DISTINCT session FROM usage_compact INDEXED BY ${index}
    WHERE ${scope}minute >= ?2 AND minute < ?3${countCandidate}
  ), eligible AS MATERIALIZED (${eligible})${marker}
    SELECT strftime('%Y-%m-%d', (c.minute + ?1) * 60, 'unixepoch') AS day,
    c.session, NULLIF(c.thread, 0) AS thread, NULLIF(c.person, '') AS person, NULLIF(c.profile, '') AS profile,
    c.runtime, NULLIF(c.model, '') AS model, c.fast, SUM(c.calls) AS calls, SUM(c.input) AS input,
    SUM(c.cache_read) AS cache_read, SUM(c.cache_write) AS cache_write, SUM(c.cache_write_long) AS cache_write_long, SUM(c.output) AS output${countParts ? ", COUNT(*) AS source_parts" : ""}
    FROM eligible p${markerJoin} CROSS JOIN usage_compact c ON c.session = p.session AND c.minute >= ?2 AND c.minute < ?3
    WHERE ${markerWhere}${bucketScope}c.records > 0
    GROUP BY day, c.session, c.thread, c.person, c.profile, c.runtime, c.model, c.fast`;
  return { sql, args };
}

function compactQueryWithEdges(from: bigint, to: bigint, offset: bigint, viewer: InWorkspace | null, countParts: boolean): { sql: string; args: (string | bigint)[] } {
  const size = 60_000n;
  const max = 9223372036854775807n;
  const floor = (n: bigint) => n >= 0n ? n / size : -1n - ((-1n - n) / size);
  const first = floor(from);
  const last = floor(to);
  const args: (string | bigint)[] = [offset];
  const bind = (value: string | bigint) => { args.push(value); return `?${args.length}`; };
  let selectedScope = "";
  let bucketScope = "";
  let eligible = "SELECT session FROM selected";
  if (viewer !== null) {
    const scope = bind(`W${viewer.workspace}`);
    const ws = bind(viewer.workspace);
    selectedScope = viewer.home !== false ? `scope IN (${scope}, 'H') AND ` : `scope = ${scope} AND `;
    bucketScope = viewer.home !== false ? `c.scope IN (${scope}, 'H') AND ` : `c.scope = ${scope} AND `;
    eligible = `SELECT p.session FROM selected p CROSS JOIN usage_minute_scope sc ON sc.session = p.session
      WHERE ${viewer.home !== false ? `(sc.ws = ${ws} OR sc.ws IS NULL)` : `sc.ws = ${ws}`}`;
  }
  // Include both partial edges when selecting sessions; their original calls are read below only if their bucket exists.
  const index = viewer === null ? "usage_compact_time" : "usage_compact_scope_time";
  const selectedStart = bind(first);
  const selectedEnd = bind(to === max ? max : last + (to === last * size ? 0n : 1n));
  const start = bind(first + (from === first * size ? 0n : 1n));
  const end = bind(to === max ? max : last);
  const parts = [`SELECT c.minute, c.session, c.thread, c.person, c.profile, c.runtime, c.model, c.fast,
    c.calls, c.input, c.cache_read, c.cache_write, c.cache_write_long, c.output
    FROM eligible p CROSS JOIN usage_compact c ON c.session = p.session AND c.minute >= ${start} AND c.minute < ${end}
    WHERE ${bucketScope}c.records > 0`];
  const edge = (minute: bigint, begin: bigint, until: bigint) => {
    if (begin >= until) return;
    const bucket = bind(minute);
    const low = bind(begin);
    const high = bind(until);
    parts.push(`SELECT e.minute, u.session, COALESCE(u.thread, 0), COALESCE(u.person, ''), COALESCE(u.profile, ''),
      u.runtime, COALESCE(u.model, ''), u.fast, u.calls, u.input, u.cache_read, u.cache_write, u.cache_write_long, u.output
      FROM (SELECT DISTINCT c.session, c.minute FROM usage_compact c INDEXED BY ${index}
        CROSS JOIN eligible p ON p.session = c.session
        WHERE ${bucketScope}c.minute = ${bucket} AND c.records > 0) e
      CROSS JOIN usage u INDEXED BY usage_session ON u.session = e.session AND u.at >= ${low} AND u.at < ${high}
      WHERE u.compact_counted = 1`);
  };
  if (from !== first * size) edge(first, from, (first + 1n) * size < to ? (first + 1n) * size : to);
  if (to !== max && to !== last * size && (last !== first || from === first * size)) edge(last, last * size, to);
  const sql = `WITH selected AS MATERIALIZED (
      SELECT DISTINCT session FROM usage_compact INDEXED BY ${index}
      WHERE ${selectedScope}minute >= ${selectedStart} AND minute < ${selectedEnd}
    ), eligible AS MATERIALIZED (${eligible}), parts AS (${parts.join(" UNION ALL ")})
    SELECT strftime('%Y-%m-%d', (minute + ?1) * 60, 'unixepoch') AS day,
      session, NULLIF(thread, 0) AS thread, NULLIF(person, '') AS person, NULLIF(profile, '') AS profile,
      runtime, NULLIF(model, '') AS model, fast, SUM(calls) AS calls, SUM(input) AS input,
      SUM(cache_read) AS cache_read, SUM(cache_write) AS cache_write, SUM(cache_write_long) AS cache_write_long, SUM(output) AS output${countParts ? ", COUNT(*) AS source_parts" : ""}
    FROM parts GROUP BY day, session, thread, person, profile, runtime, model, fast`;
  return { sql, args };
}

type RecentCall = ContextCall & { id: string };
type SavedContext = { runtimeSession: string; model: string | null; contextWindow: number | null; lastCallAt: number;
  contextTokens?: number; cacheMs?: number; rereadCost?: number };
type Recent = { calls: RecentCall[]; turns: { id: string | null; compacted: boolean }[]; uncertain: boolean; saved?: SavedContext };
type ContextOwner = { runtime: string; model: string; fast: number };
/// `owner`: which totals row holds it now (none: none does).
export type ContextSnapshot = { state: Recent; stored: boolean; invalid: boolean; after: number | null; owner: ContextOwner | null };

function contextOwner(db: DatabaseSync, session: string): ContextOwner | undefined {
  return db.prepare(`SELECT context_runtime AS runtime, context_model AS model, context_fast AS fast
    FROM usage_minute_scope WHERE session = ? AND context_runtime IS NOT NULL`).get(session) as ContextOwner | undefined;
}

function contextSnapshot(db: DatabaseSync, session: string): ContextSnapshot {
  const row = db.prepare(`SELECT t.compact_context AS state, sc.context_uncertain AS invalid, sc.context_after AS after,
      sc.context_runtime AS runtime, sc.context_model AS model, sc.context_fast AS fast
    FROM usage_minute_scope sc LEFT JOIN usage_totals t ON t.session = sc.session AND t.runtime = sc.context_runtime
      AND t.model = sc.context_model AND t.fast = sc.context_fast WHERE sc.session = ?`).get(session) as
    { state: string | null; invalid: number; after: number | null; runtime: string | null; model: string; fast: number } | undefined;
  const invalid = row?.invalid === 1;
  return { state: row?.state == null ? { calls: [], turns: [], uncertain: invalid } : JSON.parse(row.state) as Recent,
    stored: row?.state != null, invalid, after: row?.after ?? null,
    owner: row == null || row.runtime == null ? null : { runtime: row.runtime, model: row.model, fast: row.fast } };
}

// After an edit, there may be a later main call among the old rows. The session/time index gives an upper bound on
// those rows; once five new calls are later than it, they form a complete tail without walking that history.
function reliableTail(snapshot: ContextSnapshot): boolean {
  return !snapshot.invalid || snapshot.after === null
    || (snapshot.state.calls.length >= 5 && snapshot.state.calls[0]!.at > snapshot.after);
}

// Put context on the same totals row that this call already changed. The pointer changes only when the model,
// runtime or speed changes, so recording the next call does not dirty a separate context page.
/// `previous`: the owner as a snapshot of this transaction read it (none given: read here).
function keepRecent(db: DatabaseSync, session: string, owner: ContextOwner, state: Recent, previous: ContextOwner | null = contextOwner(db, session) ?? null): void {
  const same = previous !== null && previous.runtime === owner.runtime && previous.model === owner.model && previous.fast === owner.fast;
  if (previous && !same) {
    db.prepare(`UPDATE usage_totals SET compact_context = NULL WHERE session = ? AND runtime = ? AND model = ? AND fast = ?`)
      .run(session, previous.runtime, previous.model, previous.fast);
  }
  db.prepare(`INSERT INTO usage_totals (session, runtime, model, fast, calls, input, cache_read, cache_write, cache_write_long, output, compact_context)
    VALUES (?, ?, ?, ?, 0, 0, 0, 0, 0, 0, ?)
    ON CONFLICT (session, runtime, model, fast) DO UPDATE SET compact_context = excluded.compact_context`)
    .run(session, owner.runtime, owner.model, owner.fast, JSON.stringify(state));
  // The pointer to it already says it: nothing to write.
  if (same) return;
  db.prepare(`INSERT INTO usage_minute_scope (session, ws, done, context_runtime, context_model, context_fast)
    VALUES (?, (SELECT ws FROM sessions WHERE key = ?), 1, ?, ?, ?)
    ON CONFLICT (session) DO UPDATE SET context_runtime = excluded.context_runtime, context_model = excluded.context_model,
      context_fast = excluded.context_fast
    WHERE context_runtime IS NOT excluded.context_runtime OR context_model IS NOT excluded.context_model OR context_fast IS NOT excluded.context_fast`)
    .run(session, session, owner.runtime, owner.model, owner.fast);
}

/// A saved summary can seed a context only while it still represents every call and the current runtime session.
/// This is one session's existing summary and totals, not a read of its old calls. An uncertain snapshot is left out.
/// The snapshot it read, where it wrote none (the same transaction's next step reads on from it: `noteCompactContexts`).
export function seedCompactContext(db: DatabaseSync, session: string): ContextSnapshot | null {
  const snapshot = contextSnapshot(db, session);
  if (snapshot.stored || snapshot.invalid) return snapshot;
  const row = db.prepare(`SELECT u.usage, s.runtime_session_id AS runtime, r.at AS began
    FROM session_usage u JOIN sessions s ON s.key = u.session
    LEFT JOIN runtime_sessions r ON r.session_key = s.key AND r.id = s.runtime_session_id WHERE u.session = ?`).get(session) as
    { usage: string; runtime: string | null; began: number | null } | undefined;
  if (row === undefined || row.runtime === null || row.began === null) return snapshot;
  const old = JSON.parse(row.usage) as Record<string, unknown>;
  const total = db.prepare("SELECT COALESCE(SUM(calls), 0) AS n FROM usage_totals WHERE session = ? AND calls > 0").get(session) as { n: number };
  if (old.modelCalls !== total.n || typeof old.lastCallAt !== "number" || old.lastCallAt < row.began
    || (old.model !== null && typeof old.model !== "string")
    || (old.contextWindow !== null && typeof old.contextWindow !== "number")) return snapshot;
  const saved: SavedContext = { runtimeSession: row.runtime, model: old.model as string | null,
    contextWindow: old.contextWindow as number | null, lastCallAt: old.lastCallAt };
  for (const name of ["contextTokens", "cacheMs", "rereadCost"] as const) {
    if (typeof old[name] === "number") saved[name] = old[name];
  }
  const owner = db.prepare("SELECT runtime, model, fast FROM usage_totals WHERE session = ? ORDER BY runtime, model, fast LIMIT 1")
    .get(session) as ContextOwner | undefined;
  if (!owner) return snapshot;
  const state: Recent = { calls: [], turns: [], uncertain: false, saved };
  keepRecent(db, session, owner, state, snapshot.owner);
  return null;
}

export function savedCompactContext(db: DatabaseSync, session: string): SavedContext | null {
  const snapshot = contextSnapshot(db, session);
  if (snapshot.invalid) return null;
  const saved = snapshot.state.saved;
  if (saved === undefined) return null;
  const row = db.prepare("SELECT runtime_session_id AS id FROM sessions WHERE key = ?").get(session) as { id: string | null } | undefined;
  return row?.id === saved.runtimeSession ? saved : null;
}

/// The last five contexts and whether the last two turns compacted are bounded session statistics, not a copy of every call.
/// `read`: the snapshot this transaction read of it already (`seedCompactContext`'s), the calls since inserted with
/// compact_counted, which no trigger takes the context back for.
export function noteCompactContexts(db: DatabaseSync, session: string, runtime: string, calls: [UsageCall, UsageFor][], read: ContextSnapshot | null = null): void {
  const snapshot = read ?? contextSnapshot(db, session);
  const state = snapshot.state;
  let changed = false;
  let target: UsageCall | undefined;
  for (const [call, of] of calls) {
    if (state.saved && call.at < state.saved.lastCallAt) {
      // A late call cannot be the saved latest call. It can change which cache write was in the last five, though.
      if (state.saved.cacheMs !== undefined || state.saved.rereadCost !== undefined) {
        delete state.saved.cacheMs;
        delete state.saved.rereadCost;
        changed = true;
      }
      continue;
    }
    if (state.saved && call.at === state.saved.lastCallAt) {
      // The saved summary did not keep an id, so the order of two calls at the same time is unknown.
      delete state.saved;
      state.calls = [];
      state.turns = [];
      state.uncertain = true;
      db.prepare(`UPDATE usage_minute_scope SET context_uncertain = 1,
        context_after = (SELECT at FROM usage INDEXED BY usage_session WHERE session = ? ORDER BY at DESC LIMIT 1)
        WHERE session = ?`).run(session, session);
    }
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
    changed = true;
    target = call;
  }
  const owner = target ? { runtime, model: target.model ?? "", fast: target.fast ? 1 : 0 } : snapshot.owner;
  if (changed && owner) keepRecent(db, session, owner, state, snapshot.owner);
}

export function compactContexts(db: DatabaseSync, session: string, limit: number): ContextCall[] {
  if (limit <= 0) return [];
  const snapshot = contextSnapshot(db, session);
  return reliableTail(snapshot) ? snapshot.state.calls.slice(-limit).map(({ id: _id, ...call }) => call) : [];
}

export function compactRecentlyCompacted(db: DatabaseSync, session: string): boolean {
  const snapshot = contextSnapshot(db, session);
  return reliableTail(snapshot) && !snapshot.state.uncertain && snapshot.state.turns.some((turn) => turn.compacted);
}
