// The usage page's year (GET /usage?history=1): what each workspace's chats spent, by quarter hour, and in all. A
// statistic of the `usage` table kept by the database itself: each call recorded, grown, moved or removed adds to or
// takes from its quarter in the same write (the triggers below), whichever station writes it. A read takes only the
// quarters it shows (read/usage.ts usageHistory), however long the station has been counting.
//
// Installed once. What came before is taken from the statistics already kept then (the old daily quarters), and the
// calls since those stopped being kept; never the station's whole history of calls (installUsageHistory).
import type { DatabaseSync } from "node:sqlite";

/// A quarter hour (15 minutes) as a number: the ms since the epoch over 900 000, rounded down.
const QUARTER_MS = 900_000;
const quarterOf = (r: string) => `(CASE WHEN ${r}.at >= 0 THEN ${r}.at / ${QUARTER_MS} ELSE -1 - ((-1 - ${r}.at) / ${QUARTER_MS}) END)`;
const tokensOf = (r: string) => `(${r}.input + ${r}.cache_read + ${r}.cache_write + ${r}.cache_write_long + ${r}.output)`;
/// A session's workspace as its usage is told apart (rows.ts `sees`): its chat's, '' for the home one's (and a session
/// gone, whose calls stay counted where they were).
const scopeOf = (r: string) => `COALESCE((SELECT ws FROM sessions WHERE key = ${r}.session), '')`;
const addTo = (scope: string, quarter: string, calls: string, tokens: string) => `INSERT INTO usage_history (scope, quarter, calls, tokens)
    VALUES (${scope}, ${quarter}, ${calls}, ${tokens})
    ON CONFLICT (scope, quarter) DO UPDATE SET calls = calls + excluded.calls, tokens = tokens + excluded.tokens;`;

/// The calls from `?1` (ms) on, by workspace and quarter: those the old statistics did not hold, by the index on their
/// time (the hours or days since those stopped).
export const HISTORY_SEED_CALLS = `SELECT ${scopeOf("u")}, ${quarterOf("u")}, SUM(u.calls), SUM(${tokensOf("u")}) FROM usage u INDEXED BY usage_at
  WHERE u.at >= ?1 GROUP BY 1, 2`;

const SCHEMA = `
CREATE TABLE usage_history (scope TEXT NOT NULL, quarter INTEGER NOT NULL, calls INTEGER NOT NULL, tokens INTEGER NOT NULL,
  PRIMARY KEY (scope, quarter)) WITHOUT ROWID;
-- Each workspace's in all, as its quarters add up (kept by their triggers, so a seed or a move keeps it too).
CREATE TABLE usage_history_total (scope TEXT PRIMARY KEY, calls INTEGER NOT NULL, tokens INTEGER NOT NULL) WITHOUT ROWID;
-- since: from when the quarters hold every call (ms); NULL, from the first. Only an older station whose statistics did
-- not hold its whole history says a time.
CREATE TABLE usage_history_since (id INTEGER PRIMARY KEY CHECK (id = 1), since INTEGER);
CREATE TRIGGER usage_history_total_add AFTER INSERT ON usage_history BEGIN
  INSERT INTO usage_history_total VALUES (NEW.scope, NEW.calls, NEW.tokens)
    ON CONFLICT (scope) DO UPDATE SET calls = calls + excluded.calls, tokens = tokens + excluded.tokens;
END;
CREATE TRIGGER usage_history_total_change AFTER UPDATE ON usage_history BEGIN
  UPDATE usage_history_total SET calls = calls + NEW.calls - OLD.calls, tokens = tokens + NEW.tokens - OLD.tokens WHERE scope = NEW.scope;
END;
CREATE TRIGGER usage_history_total_drop AFTER DELETE ON usage_history BEGIN
  UPDATE usage_history_total SET calls = calls - OLD.calls, tokens = tokens - OLD.tokens WHERE scope = OLD.scope;
END;
CREATE TRIGGER usage_history_add AFTER INSERT ON usage BEGIN
  ${addTo(scopeOf("NEW"), quarterOf("NEW"), "NEW.calls", tokensOf("NEW"))}
END;
-- A response grown (the common change): its own quarter, one row.
CREATE TRIGGER usage_history_grow AFTER UPDATE OF at, session, calls, input, cache_read, cache_write, cache_write_long, output ON usage
  WHEN OLD.session = NEW.session AND ${quarterOf("OLD")} = ${quarterOf("NEW")}
    AND (OLD.calls IS NOT NEW.calls OR ${tokensOf("OLD")} IS NOT ${tokensOf("NEW")}) BEGIN
  UPDATE usage_history SET calls = calls + NEW.calls - OLD.calls, tokens = tokens + ${tokensOf("NEW")} - ${tokensOf("OLD")}
    WHERE scope = ${scopeOf("NEW")} AND quarter = ${quarterOf("NEW")};
END;
CREATE TRIGGER usage_history_move AFTER UPDATE OF at, session ON usage
  WHEN OLD.session IS NOT NEW.session OR ${quarterOf("OLD")} IS NOT ${quarterOf("NEW")} BEGIN
  UPDATE usage_history SET calls = calls - OLD.calls, tokens = tokens - ${tokensOf("OLD")}
    WHERE scope = ${scopeOf("OLD")} AND quarter = ${quarterOf("OLD")};
  ${addTo(scopeOf("NEW"), quarterOf("NEW"), "NEW.calls", tokensOf("NEW"))}
END;
CREATE TRIGGER usage_history_drop AFTER DELETE ON usage BEGIN
  UPDATE usage_history SET calls = calls - OLD.calls, tokens = tokens - ${tokensOf("OLD")}
    WHERE scope = ${scopeOf("OLD")} AND quarter = ${quarterOf("OLD")};
END;`;

const has = (db: DatabaseSync, table: string) =>
  db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?").get(table) !== undefined;

export const hasUsageHistory = (db: DatabaseSync): boolean => has(db, "usage_history_since");

/// With no call recorded yet (a new station's) there is nothing to take over: installed as the database opens.
export function installEmptyUsageHistory(db: DatabaseSync): void {
  if (!hasUsageHistory(db) && db.prepare("SELECT 1 FROM usage LIMIT 1").get() === undefined) installUsageHistory(db, 0);
}

/// Installs the history in one write, taking over what was counted before it (`now`: when, ms):
/// - the old daily quarters (usage_day_quarters), where they hold every call: those kept with the calls until now
///   (none newer than this), or, once the compact statistics took over (usage-compact.ts), those before the time
///   they went on being kept from (`since`, or where an emergency stop left them: their last quarter, its calls read
///   again);
/// - the calls since then, read by the index on their time: the hours or days since those quarters stopped, not the
///   station's whole history.
/// A station whose old quarters never held every call (their fill not done) counts from when the compact statistics
/// began, or from now; the page says the days before are not known until usage-fill.ts has counted them.
export function installUsageHistory(db: DatabaseSync, now: number): void {
  if (hasUsageHistory(db)) return;
  db.exec("BEGIN IMMEDIATE");
  try {
    if (hasUsageHistory(db)) { db.exec("COMMIT"); return; }
    db.exec(SCHEMA);
    const empty = db.prepare("SELECT 1 FROM usage LIMIT 1").get() === undefined;
    const complete = empty || has(db, "usage_minute_all") && has(db, "usage_day_quarters")
      && (db.prepare("SELECT done FROM usage_minute_all WHERE id = 1").get() as { done: number } | undefined)?.done === 1;
    const compact = has(db, "usage_compact_since")
      ? db.prepare("SELECT since, old_days FROM usage_compact_since WHERE id = 1").get() as { since: number; old_days: number } : undefined;
    // Whether the old quarters are still kept with every call: by their own triggers (no compact statistics yet), or
    // by the compact ones' for the calls before them (old_days).
    const kept = compact === undefined
      ? db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'trigger' AND name IN ('usage_minute_add', 'usage_daily_detail_add')").get() !== undefined
      : compact.old_days === 1;
    // The quarter from which the calls themselves are read (null: none are). Before it, the old quarters.
    let from: number | null;
    let since: number | null = null;
    if (!complete) {
      from = compact === undefined ? null : Math.floor(compact.since / QUARTER_MS);
      since = compact?.since ?? now;
    } else if (kept) from = compact === undefined ? null : Math.floor(compact.since / QUARTER_MS);
    else {
      // Stopped at a time not written down: their last quarter may hold only some of its calls, so it is read again
      // from the calls, and all after it. None at all: every call came after they stopped.
      from = (db.prepare("SELECT MAX(quarter) AS q FROM usage_day_quarters").get() as { q: number | null }).q ?? 0;
    }
    if (complete && !empty) {
      db.prepare(`INSERT INTO usage_history (scope, quarter, calls, tokens)
        SELECT COALESCE(s.ws, ''), q.quarter, SUM(q.calls), SUM(q.tokens) FROM usage_day_quarters q LEFT JOIN sessions s ON s.key = q.session
        WHERE ?1 IS NULL OR q.quarter < ?1 GROUP BY 1, 2`).run(from);
    }
    if (from !== null && !empty) {
      db.prepare(`INSERT INTO usage_history (scope, quarter, calls, tokens) ${HISTORY_SEED_CALLS}
        ON CONFLICT (scope, quarter) DO UPDATE SET calls = calls + excluded.calls, tokens = tokens + excluded.tokens`).run(from * QUARTER_MS);
    }
    db.prepare("INSERT INTO usage_history_since VALUES (1, ?)").run(since);
    db.exec("COMMIT");
  } catch (error) { db.exec("ROLLBACK"); throw error; }
}

/// The calls of workspace `from` ('' the home one) are `to`'s from now on: when the station's home workspace changes,
/// all its sessions go together (store.ts setSessionsWs), and so do their quarters. In the caller's write.
export function moveUsageHistory(db: DatabaseSync, from: string, to: string): void {
  if (from === to || !hasUsageHistory(db)) return;
  db.prepare(`INSERT INTO usage_history (scope, quarter, calls, tokens) SELECT ?2, quarter, calls, tokens FROM usage_history WHERE scope = ?1
    ON CONFLICT (scope, quarter) DO UPDATE SET calls = calls + excluded.calls, tokens = tokens + excluded.tokens`).run(from, to);
  db.prepare("DELETE FROM usage_history WHERE scope = ?").run(from);
  db.prepare("DELETE FROM usage_history_total WHERE scope = ?").run(from);
}

/// One workspace's quarters from `from` until `to` (quarters, `to` not included), added up by day `offset` minutes east
/// of UTC: by its primary key, these quarters and no others.
export const HISTORY_DAYS = `SELECT strftime('%Y-%m-%d', quarter * 900 + ?4 * 60, 'unixepoch') AS day, SUM(calls) AS calls, SUM(tokens) AS tokens
  FROM usage_history WHERE scope = ?1 AND quarter >= ?2 AND quarter < ?3 GROUP BY day`;
/// One workspace's tokens from quarter `?2` on: what its total holds of the days after the page's.
export const HISTORY_AFTER = "SELECT SUM(tokens) AS tokens FROM usage_history WHERE scope = ?1 AND quarter >= ?2";
export const HISTORY_SCOPES = "SELECT scope, tokens FROM usage_history_total";
export const HISTORY_TOTAL = "SELECT tokens FROM usage_history_total WHERE scope = ?1";

/// The quarter `at` (ms) is in.
export const quarter = (at: bigint): bigint => (at >= 0n ? at / 900_000n : -1n - (-1n - at) / 900_000n);

/// The quarters from `start` until `end` as their calls say, whatever they held: in the caller's write.
export function setUsageHistoryQuarters(db: DatabaseSync, start: number, end: number): void {
  db.prepare("DELETE FROM usage_history WHERE scope IN (SELECT scope FROM usage_history_total) AND quarter >= ? AND quarter < ?").run(start, end);
  db.prepare(`INSERT INTO usage_history (scope, quarter, calls, tokens) SELECT ${scopeOf("u")}, ${quarterOf("u")}, SUM(u.calls), SUM(${tokensOf("u")})
    FROM usage u INDEXED BY usage_at WHERE u.at >= ? AND u.at < ? GROUP BY 1, 2`).run(start * QUARTER_MS, end * QUARTER_MS);
}

export function setUsageHistorySince(db: DatabaseSync, since: number | null): void {
  db.prepare("UPDATE usage_history_since SET since = ? WHERE id = 1").run(since);
}

/// From when the history holds every call (ms); null, from the first.
export function usageHistorySince(db: DatabaseSync): number | null {
  return (db.prepare("SELECT since FROM usage_history_since WHERE id = 1").get() as { since: number | null }).since;
}
