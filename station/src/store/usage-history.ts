// The usage page's year (GET /usage?history=1): what each workspace's chats spent, by quarter hour, and in all. A
// statistic of the `usage` table kept by the database itself: each call recorded, grown, moved or removed adds to or
// takes from its quarter in the same write (the triggers below), whichever station writes it. A read takes only the
// quarters it shows (read/usage.ts usageHistory), however long the station has been counting.
//
// Installed once without reading or rebuilding earlier statistics. An older station counts from installation; a new
// one counts from its first call. Calls already recorded at installation remain in usage but are not counted here.
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

const SCHEMA = `
CREATE TABLE usage_history (scope TEXT NOT NULL, quarter INTEGER NOT NULL, calls INTEGER NOT NULL, tokens INTEGER NOT NULL,
  PRIMARY KEY (scope, quarter)) WITHOUT ROWID;
-- Each workspace's in all, as its quarters add up.
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
  -- An older writer may omit the marker; flag just this new row, never the records already in the table.
  UPDATE usage SET history_counted = 1 WHERE id = NEW.id AND history_counted = 0;
END;
-- A response grown (the common change): its own quarter, one row.
CREATE TRIGGER usage_history_grow AFTER UPDATE OF at, session, calls, input, cache_read, cache_write, cache_write_long, output ON usage
  WHEN OLD.history_counted = 1 AND OLD.session = NEW.session AND ${quarterOf("OLD")} = ${quarterOf("NEW")}
    AND (OLD.calls IS NOT NEW.calls OR ${tokensOf("OLD")} IS NOT ${tokensOf("NEW")}) BEGIN
  UPDATE usage_history SET calls = calls + NEW.calls - OLD.calls, tokens = tokens + ${tokensOf("NEW")} - ${tokensOf("OLD")}
    WHERE scope = ${scopeOf("NEW")} AND quarter = ${quarterOf("NEW")};
END;
CREATE TRIGGER usage_history_move AFTER UPDATE OF at, session ON usage
  WHEN OLD.history_counted = 1 AND (OLD.session IS NOT NEW.session OR ${quarterOf("OLD")} IS NOT ${quarterOf("NEW")}) BEGIN
  UPDATE usage_history SET calls = calls - OLD.calls, tokens = tokens - ${tokensOf("OLD")}
    WHERE scope = ${scopeOf("OLD")} AND quarter = ${quarterOf("OLD")};
  ${addTo(scopeOf("NEW"), quarterOf("NEW"), "NEW.calls", tokensOf("NEW"))}
END;
CREATE TRIGGER usage_history_drop AFTER DELETE ON usage WHEN OLD.history_counted = 1 BEGIN
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

/// Installs the history without reading old calls or quarters. The column's constant default marks existing rows
/// without rewriting them; insertions after the installation are marked by the trigger in their own writes.
/// On an older station the page says the days before `now` are incomplete.
export function installUsageHistory(db: DatabaseSync, now: number): void {
  if (hasUsageHistory(db)) return;
  db.exec("BEGIN IMMEDIATE");
  try {
    if (hasUsageHistory(db)) { db.exec("COMMIT"); return; }
    const empty = db.prepare("SELECT 1 FROM usage LIMIT 1").get() === undefined;
    db.exec("ALTER TABLE usage ADD COLUMN history_counted INTEGER NOT NULL DEFAULT 0");
    db.exec(SCHEMA);
    db.prepare("INSERT INTO usage_history_since VALUES (1, ?)").run(empty ? null : now);
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

/// From when the history holds every call (ms); null, from the first.
export function usageHistorySince(db: DatabaseSync): number | null {
  return (db.prepare("SELECT since FROM usage_history_since WHERE id = 1").get() as { since: number | null }).since;
}
