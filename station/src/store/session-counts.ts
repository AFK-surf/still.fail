// Counts for the station overview. Old sessions are brought across in bounded transactions; triggers also account for
// writers from an older station, including changes made while that scan is in progress.
import type { DatabaseSync } from "node:sqlite";

const VERSION = 1;
function checkVersion(version: number): void {
  if (version !== VERSION) throw new Error(`session count index version ${version} is incompatible with ${VERSION}`);
}

export const SESSION_COUNT_FIRST = `SELECT CAST(rowid AS TEXT) AS position, key FROM sessions
  WHERE rowid <= CAST(? AS INTEGER) ORDER BY rowid LIMIT ?`;
export const SESSION_COUNT_NEXT = `SELECT CAST(rowid AS TEXT) AS position, key FROM sessions
  WHERE rowid > CAST(? AS INTEGER) AND rowid <= CAST(? AS INTEGER) ORDER BY rowid LIMIT ?`;
export const SESSION_COUNT_TOTAL = "SELECT n FROM session_count_totals WHERE kind = ? AND ws = ?";
export const SESSION_COUNT_CONNECT = "SELECT n FROM session_count_groups WHERE kind = ? AND ws = ? AND connect = ?";
export const SESSION_COUNTS = `SELECT connect, CASE kind WHEN 0 THEN NULL ELSE ws END AS ws, n
  FROM session_count_groups ORDER BY connect, ws`;
export const SESSION_COUNTS_VISIBLE = `SELECT connect, ws, n FROM session_count_groups
  WHERE kind = 1 AND ws = ? ORDER BY connect`;
export const SESSION_COUNTS_HOME = `SELECT connect, CASE kind WHEN 0 THEN NULL ELSE ws END AS ws, n
  FROM session_count_groups WHERE (kind = 1 AND ws = ?) OR kind = 0 ORDER BY connect, ws`;

const kind = (row: string) => `CASE WHEN ${row}.ws IS NULL THEN 0 ELSE 1 END`;
const ws = (row: string) => `COALESCE(${row}.ws, '')`;
const group = (row: string) => `kind = ${kind(row)} AND ws = ${ws(row)} AND connect = ${row}.connect`;
const total = (row: string) => `kind = ${kind(row)} AND ws = ${ws(row)}`;

// Do not use INSERT OR IGNORE inside a trigger: an outer INSERT OR REPLACE would override that policy.
const add = `UPDATE session_count_groups SET n = n + 1 WHERE ${group("NEW")};
  INSERT INTO session_count_groups (kind, ws, connect, n)
    SELECT ${kind("NEW")}, ${ws("NEW")}, NEW.connect, 1
    WHERE NOT EXISTS (SELECT 1 FROM session_count_groups WHERE ${group("NEW")});
  UPDATE session_count_totals SET n = n + 1 WHERE ${total("NEW")};
  INSERT INTO session_count_totals (kind, ws, n)
    SELECT ${kind("NEW")}, ${ws("NEW")}, 1
    WHERE NOT EXISTS (SELECT 1 FROM session_count_totals WHERE ${total("NEW")});`;
const remove = `UPDATE session_count_groups SET n = n - 1 WHERE ${group("OLD")};
  DELETE FROM session_count_groups WHERE ${group("OLD")} AND n = 0;
  UPDATE session_count_totals SET n = n - 1 WHERE ${total("OLD")};
  DELETE FROM session_count_totals WHERE ${total("OLD")} AND n = 0;`;

// REPLACE can displace a different key, token, or rowid without firing its DELETE trigger. Remember those keys before
// the write, then reconcile them against the actual rows afterward. An implicit NEW.rowid may be -1; if a real row has
// that rowid it is harmless to check it, since the reconciliation changes only rows that actually differ.
const displaced = (key: string, token: string, rowid: string) => `SELECT key FROM sessions WHERE key = ${key}
  UNION SELECT key FROM sessions WHERE token = ${token}
  UNION SELECT key FROM sessions WHERE rowid = ${rowid}`;
export const SESSION_COUNT_DISPLACED = displaced("?1", "?2", "?3");
const stage = (old: boolean) => `DELETE FROM session_count_replaced;
  INSERT INTO session_count_replaced (session)
    ${displaced("NEW.key", "NEW.token", "NEW.rowid")}
    ${old ? "UNION SELECT OLD.key" : ""};`;
const reconcile = `DELETE FROM session_count_seen
  WHERE session IN (SELECT session FROM session_count_replaced)
    AND NOT EXISTS (SELECT 1 FROM sessions s WHERE s.key = session_count_seen.session
      AND s.connect IS session_count_seen.connect AND s.ws IS session_count_seen.ws);
  INSERT INTO session_count_seen (session, connect, ws)
    SELECT s.key, s.connect, s.ws FROM session_count_replaced r CROSS JOIN sessions s ON s.key = r.session
    WHERE NOT EXISTS (SELECT 1 FROM session_count_seen c WHERE c.session = s.key);
  DELETE FROM session_count_replaced;`;
const see = (key: string) => `INSERT INTO session_count_seen (session, connect, ws)
  SELECT s.key, s.connect, s.ws FROM sessions s WHERE s.key = ${key}
    AND NOT EXISTS (SELECT 1 FROM session_count_seen c WHERE c.session = s.key);`;

export function installSessionCounts(db: DatabaseSync): void {
  const installed = () => db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'session_count_meta'").get() !== undefined;
  if (installed()) { sessionCountsReady(db); return; }
  db.exec("BEGIN IMMEDIATE");
  try {
    if (!installed()) db.exec(`
      CREATE TABLE session_count_meta (id INTEGER PRIMARY KEY CHECK (id = 1), version INTEGER NOT NULL, last_rowid INTEGER,
        end_rowid INTEGER, complete INTEGER NOT NULL) WITHOUT ROWID;
      INSERT INTO session_count_meta (id, version, last_rowid, end_rowid, complete)
        SELECT 1, ${VERSION}, NULL, (SELECT rowid FROM sessions ORDER BY rowid DESC LIMIT 1),
          NOT EXISTS (SELECT 1 FROM sessions LIMIT 1);
      CREATE TABLE session_count_seen (session TEXT PRIMARY KEY, connect TEXT NOT NULL, ws TEXT) WITHOUT ROWID;
      CREATE TABLE session_count_replaced (session TEXT PRIMARY KEY) WITHOUT ROWID;
      CREATE TABLE session_count_totals (kind INTEGER NOT NULL, ws TEXT NOT NULL, n INTEGER NOT NULL,
        PRIMARY KEY (kind, ws)) WITHOUT ROWID;
      CREATE TABLE session_count_groups (kind INTEGER NOT NULL, ws TEXT NOT NULL, connect TEXT NOT NULL, n INTEGER NOT NULL,
        PRIMARY KEY (kind, ws, connect)) WITHOUT ROWID;

      CREATE TRIGGER session_count_seen_add AFTER INSERT ON session_count_seen BEGIN ${add} END;
      CREATE TRIGGER session_count_seen_drop AFTER DELETE ON session_count_seen BEGIN ${remove} END;
      CREATE TRIGGER session_count_before_add BEFORE INSERT ON sessions BEGIN ${stage(false)} END;
      CREATE TRIGGER session_count_add AFTER INSERT ON sessions BEGIN ${reconcile} ${see("NEW.key")} END;
      CREATE TRIGGER session_count_before_change BEFORE UPDATE ON sessions
        WHEN OLD.key IS NOT NEW.key OR OLD.token IS NOT NEW.token OR OLD.rowid IS NOT NEW.rowid
          OR OLD.connect IS NOT NEW.connect OR OLD.ws IS NOT NEW.ws BEGIN ${stage(true)} END;
      CREATE TRIGGER session_count_change AFTER UPDATE ON sessions
        WHEN OLD.key IS NOT NEW.key OR OLD.token IS NOT NEW.token OR OLD.rowid IS NOT NEW.rowid
          OR OLD.connect IS NOT NEW.connect OR OLD.ws IS NOT NEW.ws BEGIN ${reconcile} ${see("NEW.key")} END;
      CREATE TRIGGER session_count_drop AFTER DELETE ON sessions BEGIN
        DELETE FROM session_count_seen WHERE session = OLD.key;
      END;
    `);
    else sessionCountsReady(db);
    db.exec("COMMIT");
  } catch (error) {
    db.exec("ROLLBACK");
    throw error;
  }
}

export function sessionCountsReady(db: DatabaseSync): boolean {
  const meta = db.prepare("SELECT version, complete FROM session_count_meta WHERE id = 1").get() as { version: number; complete: number } | undefined;
  if (meta === undefined) throw new Error("session count index version marker is missing");
  checkVersion(meta.version);
  return meta.complete === 1;
}

/// Advance at most `limit` old rows. The fixed rowid boundary prevents newly allocated rows from extending the scan;
/// triggers count new and changed sessions immediately, including those moved behind or beyond its cursor.
export function sessionCountsStep(db: DatabaseSync, limit = 256): { done: boolean; visited: number } {
  if (!Number.isSafeInteger(limit) || limit < 1) throw new RangeError("session count batch must be positive");
  db.exec("BEGIN IMMEDIATE");
  try {
    const meta = db.prepare(`SELECT version, CAST(last_rowid AS TEXT) AS last_rowid, CAST(end_rowid AS TEXT) AS end_rowid, complete
      FROM session_count_meta WHERE id = 1`).get() as { version: number; last_rowid: string | null; end_rowid: string | null; complete: number } | undefined;
    if (meta === undefined) throw new Error("session count index version marker is missing");
    checkVersion(meta.version);
    if (meta.complete === 1) { db.exec("COMMIT"); return { done: true, visited: 0 }; }
    const rows = (meta.last_rowid === null
      ? db.prepare(SESSION_COUNT_FIRST).all(meta.end_rowid, limit)
      : db.prepare(SESSION_COUNT_NEXT).all(meta.last_rowid, meta.end_rowid, limit)) as { position: string; key: string }[];
    const put = db.prepare(see("?"));
    for (const row of rows) put.run(row.key);
    const done = rows.length < limit;
    db.prepare("UPDATE session_count_meta SET last_rowid = CAST(? AS INTEGER), complete = ? WHERE id = 1")
      .run(rows.at(-1)?.position ?? meta.last_rowid, done ? 1 : 0);
    db.exec("COMMIT");
    return { done, visited: rows.length };
  } catch (error) {
    try { db.exec("ROLLBACK"); } catch {}
    throw error;
  }
}
