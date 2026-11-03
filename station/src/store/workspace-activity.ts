// The running or pending sessions of a workspace, maintained by the database so older writers keep it too.
// Installation reads no session history. An older database's active keys are brought across in bounded steps.
import type { DatabaseSync } from "node:sqlite";
import { byBytes } from "./rows.ts";

const active = (key: string) => `EXISTS (SELECT 1 FROM sessions z WHERE z.key = ${key} AND (z.running = 1
  OR EXISTS (SELECT 1 FROM deliveries d INDEXED BY deliveries_pending WHERE d.session = z.key AND d.delivered_at IS NULL)
  OR EXISTS (SELECT 1 FROM letter_deliveries d INDEXED BY letter_deliveries_pending WHERE d.session = z.key AND d.delivered_at IS NULL)))`;
const identity = (key: string) => `SELECT s.ws IS NULL, COALESCE(s.ws, ''), s.key FROM sessions s WHERE s.key = ${key}`;
const add = (key: string) => `INSERT OR IGNORE INTO workspace_activity (home, ws, session)
  SELECT s.ws IS NULL, COALESCE(s.ws, ''), s.key FROM sessions s WHERE s.key = ${key} AND ${active("s.key")};`;
const removeIdle = (key: string) => `DELETE FROM workspace_activity WHERE (home, ws, session) IN (${identity(key)}) AND NOT ${active(key)};`;
const cleanReplaced = `DELETE FROM workspace_activity
  WHERE (home, ws, session) IN (SELECT home, ws, session FROM workspace_activity_replaced)
    AND NOT EXISTS (SELECT 1 FROM sessions s WHERE s.key = workspace_activity.session
      AND (s.ws IS NULL) = workspace_activity.home AND COALESCE(s.ws, '') = workspace_activity.ws AND ${active("s.key")});
  DELETE FROM workspace_activity_replaced WHERE session IS NOT NULL;`;
const stageReplaced = `DELETE FROM workspace_activity_replaced WHERE session IS NOT NULL;
  INSERT OR IGNORE INTO workspace_activity_replaced
    SELECT a.home, a.ws, a.session FROM workspace_activity a
    WHERE (a.home, a.ws, a.session) IN (
      SELECT s.ws IS NULL, COALESCE(s.ws, ''), s.key FROM sessions s WHERE s.key = NEW.key OR s.token = NEW.token
    );`;

export const WORKSPACE_ACTIVITY = `SELECT s.* FROM workspace_activity a
  CROSS JOIN sessions s ON s.key = a.session
  WHERE a.home = 0 AND a.ws = ? AND s.ws = a.ws`;
const FIRST_RUNNING = "SELECT key AS session FROM sessions INDEXED BY sessions_running WHERE running = 1 ORDER BY key LIMIT 1";
const NEXT_RUNNING = "SELECT key AS session FROM sessions INDEXED BY sessions_running WHERE running = 1 AND key > ? ORDER BY key LIMIT 1";
const FIRST_MESSAGE = "SELECT session FROM deliveries INDEXED BY deliveries_pending WHERE delivered_at IS NULL ORDER BY session LIMIT 1";
const NEXT_MESSAGE = "SELECT session FROM deliveries INDEXED BY deliveries_pending WHERE delivered_at IS NULL AND session > ? ORDER BY session LIMIT 1";
const FIRST_LETTER = "SELECT session FROM letter_deliveries INDEXED BY letter_deliveries_pending WHERE delivered_at IS NULL ORDER BY session LIMIT 1";
const NEXT_LETTER = "SELECT session FROM letter_deliveries INDEXED BY letter_deliveries_pending WHERE delivered_at IS NULL AND session > ? ORDER BY session LIMIT 1";

export function installWorkspaceActivity(db: DatabaseSync): void {
  const installed = () => db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'workspace_activity_meta'").get() !== undefined;
  if (installed()) return;
  db.exec("BEGIN IMMEDIATE");
  try {
    if (!installed()) db.exec(`
      CREATE TABLE workspace_activity (home INTEGER NOT NULL, ws TEXT NOT NULL, session TEXT NOT NULL,
        PRIMARY KEY (home, ws, session)) WITHOUT ROWID;
      CREATE TABLE workspace_activity_replaced (home INTEGER NOT NULL, ws TEXT NOT NULL, session TEXT NOT NULL,
        PRIMARY KEY (home, ws, session)) WITHOUT ROWID;
      CREATE TABLE workspace_activity_meta (id INTEGER PRIMARY KEY CHECK (id = 1), cursor TEXT, complete INTEGER NOT NULL) WITHOUT ROWID;
      INSERT INTO workspace_activity_meta (id, cursor, complete) SELECT 1, NULL,
        NOT (EXISTS (${FIRST_RUNNING}) OR EXISTS (${FIRST_MESSAGE}) OR EXISTS (${FIRST_LETTER}));

      CREATE TRIGGER workspace_activity_before_session_add BEFORE INSERT ON sessions BEGIN ${stageReplaced} END;
      CREATE TRIGGER workspace_activity_session_add AFTER INSERT ON sessions BEGIN
        ${cleanReplaced}
        ${add("NEW.key")}
      END;
      CREATE TRIGGER workspace_activity_before_session_change BEFORE UPDATE OF key, token ON sessions
        WHEN OLD.key IS NOT NEW.key OR OLD.token IS NOT NEW.token BEGIN ${stageReplaced} END;
      CREATE TRIGGER workspace_activity_session_change AFTER UPDATE OF key, token, ws, running ON sessions
        WHEN OLD.key IS NOT NEW.key OR OLD.token IS NOT NEW.token OR OLD.ws IS NOT NEW.ws OR OLD.running IS NOT NEW.running BEGIN
        ${cleanReplaced}
        DELETE FROM workspace_activity WHERE home = (OLD.ws IS NULL) AND ws = COALESCE(OLD.ws, '') AND session = OLD.key
          AND (OLD.key IS NOT NEW.key OR OLD.ws IS NOT NEW.ws OR NOT ${active("NEW.key")});
        ${add("NEW.key")}
      END;
      CREATE TRIGGER workspace_activity_session_drop AFTER DELETE ON sessions BEGIN
        DELETE FROM workspace_activity WHERE home = (OLD.ws IS NULL) AND ws = COALESCE(OLD.ws, '') AND session = OLD.key;
      END;
      ${["deliveries", "letter_deliveries"].map((table, i) => `
        CREATE TRIGGER workspace_activity_${i}_add AFTER INSERT ON ${table} BEGIN
          ${removeIdle("NEW.session")}
          ${add("NEW.session")}
        END;
        CREATE TRIGGER workspace_activity_${i}_change AFTER UPDATE OF thread, n, session, delivered_at ON ${table}
          WHEN OLD.thread IS NOT NEW.thread OR OLD.n IS NOT NEW.n OR OLD.session IS NOT NEW.session OR OLD.delivered_at IS NOT NEW.delivered_at BEGIN
          ${removeIdle("OLD.session")}
          ${removeIdle("NEW.session")}
          ${add("OLD.session")}
          ${add("NEW.session")}
        END;
        CREATE TRIGGER workspace_activity_${i}_drop AFTER DELETE ON ${table} BEGIN
          ${removeIdle("OLD.session")}
        END;
      `).join("\n")}
    `);
    db.exec("COMMIT");
  } catch (error) {
    db.exec("ROLLBACK");
    throw error;
  }
}

export function workspaceActivityReady(db: DatabaseSync): boolean {
  return (db.prepare("SELECT complete FROM workspace_activity_meta WHERE id = 1").get() as { complete: number }).complete === 1;
}

/// Bring across at most `limit` distinct active session keys; all checks and progress commit atomically with the new
/// writers. A key added before the cursor is handled by its trigger, even if an older station wrote it.
export function workspaceActivityStep(db: DatabaseSync, limit = 64): { done: boolean; visited: number } {
  if (!Number.isSafeInteger(limit) || limit < 1) throw new RangeError("workspace activity batch must be positive");
  db.exec("BEGIN IMMEDIATE");
  try {
    const meta = db.prepare("SELECT cursor, complete FROM workspace_activity_meta WHERE id = 1").get() as { cursor: string | null; complete: number };
    if (meta.complete === 1) { db.exec("COMMIT"); return { done: true, visited: 0 }; }
    const first = [FIRST_RUNNING, FIRST_MESSAGE, FIRST_LETTER].map((sql) => db.prepare(sql));
    const next = [NEXT_RUNNING, NEXT_MESSAGE, NEXT_LETTER].map((sql) => db.prepare(sql));
    const put = db.prepare(add("?"));
    let cursor = meta.cursor;
    let visited = 0;
    let done = false;
    while (visited < limit) {
      const keys = (cursor === null ? first.map((s) => s.get()) : next.map((s) => s.get(cursor!)))
        .flatMap((row) => row === undefined ? [] : [row.session as string]).sort(byBytes);
      const key = keys[0];
      if (key === undefined) { done = true; break; }
      put.run(key);
      cursor = key;
      visited++;
    }
    db.prepare("UPDATE workspace_activity_meta SET cursor = ?, complete = ? WHERE id = 1").run(cursor, done ? 1 : 0);
    db.exec("COMMIT");
    return { done, visited };
  } catch (error) {
    try { db.exec("ROLLBACK"); } catch {}
    throw error;
  }
}
