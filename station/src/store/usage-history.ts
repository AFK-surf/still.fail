// The usage page's year (GET /usage?history=1): what each workspace's chats spent, by quarter hour, and in all. A
// statistic of the `usage` table kept by the database itself: each call recorded, grown, moved or removed adds to or
// takes from its quarter in the same write (the triggers below), whichever station writes it. A read takes only the
// quarters it shows (read/usage.ts usageHistory), however long the station has been counting.
//
// An older station takes over its existing quarterly and compact summaries in bounded batches, without reading the
// raw call history. New stations count directly from their first call.
import type { DatabaseSync } from "node:sqlite";
import { historyOwnersCurrent, historyTransferPending, historyTransferStep, historyTransferTriggers, installHistoryOwners, installHistoryTransfer, moveHistoryOrphanScope, transferScope } from "./usage-history-transfer.ts";
import { advanceHistoryMoveEpoch, beginHistoryMove, createHistoryMoves, hasHistoryMoves, historyPhysical } from "./usage-history-moves.ts";

/// A quarter hour (15 minutes) as a number: the ms since the epoch over 900 000, rounded down.
const QUARTER_MS = 900_000;
const quarterOf = (r: string) => `(CASE WHEN ${r}.at >= 0 THEN ${r}.at / ${QUARTER_MS} ELSE -1 - ((-1 - ${r}.at) / ${QUARTER_MS}) END)`;
const tokensOf = (r: string) => `(${r}.input + ${r}.cache_read + ${r}.cache_write + ${r}.cache_write_long + ${r}.output)`;
/// A session's workspace as its usage is told apart (rows.ts `sees`): its chat's, '' for the home one's (and a session
/// gone, whose calls stay counted where they were).
const scopeOf = (r: string) => `COALESCE((SELECT ws FROM sessions WHERE key = ${r}.session), '')`;
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
END;`;

/// An incomplete old daily summary cannot tell which old calls it holds. Keep that summary as it was, and update it
/// only for calls represented by the complete old quarters or by compact usage. New calls enter compact usage.
const liveSchema = (transferred: boolean, routed = false, owners = transferred) => {
  const scope = (r: string) => {
    const logical = owners ? transferScope(r) : scopeOf(r);
    return routed ? historyPhysical(logical) : logical;
  };
  const kept = (r: string) => transferred ? `(${r}.compact_counted = 1 OR (SELECT old_days FROM usage_compact_since WHERE id = 1) = 1)` : "1";
  const change = (r: string, sign: string) => `INSERT INTO usage_history (scope, quarter, calls, tokens)
    SELECT ${scope(r)}, ${quarterOf(r)}, ${sign}${r}.calls, ${sign}${tokensOf(r)} WHERE ${kept(r)}
    ON CONFLICT (scope, quarter) DO UPDATE SET calls = calls + excluded.calls, tokens = tokens + excluded.tokens;`;
  // During a move the old quarter may not have reached the new partition yet. A delta must create that quarter if
  // necessary; folding its old contribution later then yields the same result as an in-place update.
  const grow = routed ? `INSERT INTO usage_history (scope, quarter, calls, tokens)
    VALUES (${scope("NEW")}, ${quarterOf("NEW")}, NEW.calls - OLD.calls, ${tokensOf("NEW")} - ${tokensOf("OLD")})
    ON CONFLICT (scope, quarter) DO UPDATE SET calls = calls + excluded.calls, tokens = tokens + excluded.tokens;`
    : `UPDATE usage_history SET calls = calls + NEW.calls - OLD.calls, tokens = tokens + ${tokensOf("NEW")} - ${tokensOf("OLD")}
    WHERE scope = ${scope("NEW")} AND quarter = ${quarterOf("NEW")};`;
  const columns = `at, session, calls, input, cache_read, cache_write, cache_write_long, output${transferred ? ", compact_counted" : ""}`;
  return `
CREATE TRIGGER usage_history_add AFTER INSERT ON usage BEGIN ${change("NEW", "")} END;
-- A response grown (the common change): its own quarter, one row.
CREATE TRIGGER usage_history_grow AFTER UPDATE OF ${columns} ON usage
  WHEN ${kept("OLD")} AND ${kept("NEW")} AND OLD.session = NEW.session AND ${quarterOf("OLD")} = ${quarterOf("NEW")}
    AND (OLD.calls IS NOT NEW.calls OR ${tokensOf("OLD")} IS NOT ${tokensOf("NEW")}) BEGIN
  ${grow}
END;
CREATE TRIGGER usage_history_move AFTER UPDATE OF ${columns} ON usage
  WHEN OLD.session IS NOT NEW.session OR ${quarterOf("OLD")} IS NOT ${quarterOf("NEW")} OR ${kept("OLD")} IS NOT ${kept("NEW")} BEGIN
  ${change("OLD", "-")} ${change("NEW", "")}
END;
CREATE TRIGGER usage_history_drop AFTER DELETE ON usage BEGIN ${change("OLD", "-")} END;`;
};

const has = (db: DatabaseSync, table: string) =>
  db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?").get(table) !== undefined;

export const hasUsageHistory = (db: DatabaseSync): boolean => has(db, "usage_history_since");

/// A new station has no calls or older summaries. Each existence check stops at its first row.
function hasHistorySource(db: DatabaseSync): boolean {
  return db.prepare("SELECT 1 FROM usage LIMIT 1").get() !== undefined
    || (has(db, "usage_day_quarters") && db.prepare("SELECT 1 FROM usage_day_quarters LIMIT 1").get() !== undefined)
    || (has(db, "usage_compact") && db.prepare("SELECT 1 FROM usage_compact LIMIT 1").get() !== undefined);
}

/// With no call or old summary yet (a new station's), install as the database opens.
export function installEmptyUsageHistory(db: DatabaseSync): void {
  if (!hasUsageHistory(db) && !hasHistorySource(db)) installUsageHistory(db, 0);
}

/// Install ownership, even if history is still awaiting installation; the caller holds a write transaction.
export function ensureHistoryOwners(db: DatabaseSync): void {
  const installed = has(db, "usage_history_orphans");
  const history = hasUsageHistory(db);
  installHistoryOwners(db, history);
  if (installed || !history) return;
  db.exec(`DROP TRIGGER IF EXISTS usage_history_add; DROP TRIGGER IF EXISTS usage_history_grow;
    DROP TRIGGER IF EXISTS usage_history_move; DROP TRIGGER IF EXISTS usage_history_drop;`);
  db.exec(liveSchema(false, hasHistoryMoves(db), true));
}

/// The previous station can still delete a session during handover, so install its ownership trigger before returning
/// from open. Both the initial setup and a source-list refresh read only schema metadata; subsequent opens do not write.
export function installHistoryOwnersAtOpen(db: DatabaseSync): void {
  if (historyOwnersCurrent(db)) return;
  db.exec("BEGIN IMMEDIATE");
  try {
    ensureHistoryOwners(db);
    db.exec("COMMIT");
  } catch (error) { db.exec("ROLLBACK"); throw error; }
}

/// Installs empty tables and the bounded transfer. It does not scan old calls or summaries under the installation lock.
export function installUsageHistory(db: DatabaseSync, now: number): void {
  if (hasUsageHistory(db)) return;
  db.exec("BEGIN IMMEDIATE");
  try {
    if (hasUsageHistory(db)) { db.exec("COMMIT"); return; }
    const empty = !hasHistorySource(db);
    const compact = has(db, "usage_compact_since")
      ? db.prepare("SELECT since, old_days FROM usage_compact_since WHERE id = 1").get() as { since: number; old_days: number } : undefined;
    if (!empty && compact === undefined) throw new Error("compact usage statistics are not installed");
    db.exec(SCHEMA);
    db.prepare("INSERT INTO usage_history_since VALUES (1, ?)").run(empty || compact?.old_days === 1 ? null : compact?.since ?? now);
    if (empty) {
      const owners = has(db, "usage_history_orphans");
      if (owners && !has(db, "usage_history_fresh_owners")) db.exec("CREATE TABLE usage_history_fresh_owners (id INTEGER PRIMARY KEY)");
      db.exec(liveSchema(false, false, owners));
    } else installHistoryTransfer(db);
    db.exec("COMMIT");
  } catch (error) { db.exec("ROLLBACK"); throw error; }
}

/// Conversion can be interrupted between any two batches; live writes are accounted for by the transfer triggers.
export function convertUsageHistoryStep(db: DatabaseSync, batch = 256): boolean {
  return historyTransferStep(db, () => db.exec(liveSchema(true, hasHistoryMoves(db))), batch);
}

export { historyTransferPending };

/// The calls of workspace `from` ('' the home one) are `to`'s from now on: when the station's home workspace changes,
/// all its sessions go together (store.ts setSessionsWs), and so do their quarters. In the caller's write.
export function moveUsageHistory(db: DatabaseSync, from: string, to: string): void {
  if (from === to) return;
  if (!hasUsageHistory(db)) {
    if (has(db, "usage_history_orphans")) moveHistoryOrphanScope(db, from, to);
    return;
  }
  if (!hasHistoryMoves(db)) {
    // With no old partition, future calls already follow their sessions. Keep readers' move detection, but do not
    // add routing to every future usage write just because an empty workspace moved.
    if (db.prepare("SELECT 1 FROM usage_history WHERE scope = ? LIMIT 1").get(from) === undefined) {
      if (has(db, "usage_history_orphans")) moveHistoryOrphanScope(db, from, to);
      advanceHistoryMoveEpoch(db);
      db.prepare("DELETE FROM usage_history_total WHERE scope = ?").run(from);
      return;
    }
    createHistoryMoves(db);
    if (historyTransferPending(db)) historyTransferTriggers(db, true);
    else {
      db.exec(`DROP TRIGGER IF EXISTS usage_history_add; DROP TRIGGER IF EXISTS usage_history_grow;
        DROP TRIGGER IF EXISTS usage_history_move; DROP TRIGGER IF EXISTS usage_history_drop;`);
      db.exec(liveSchema(has(db, "usage_history_orphans") && !has(db, "usage_history_fresh_owners"), true, has(db, "usage_history_orphans")));
    }
  }
  if (has(db, "usage_history_orphans")) moveHistoryOrphanScope(db, from, to);
  beginHistoryMove(db, from, to);
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
