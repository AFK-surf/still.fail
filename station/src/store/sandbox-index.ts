// Names at the sandbox front door are hashes of session keys and cannot be looked up in sessions. Prepare the reverse
// lookup only for a station that uses sandboxes. Old writers put changed keys in a small journal; hashing and an old
// store's initial preparation happen in bounded batches, never in a trigger on an older connection.
import type { DatabaseSync } from "node:sqlite";
import { keyPart, sandboxName } from "../agents/sandbox-name.ts";

const VERSION = 1;
const EXISTS = "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'sandbox_name_meta'";
const DIRTY = (key: string) => `INSERT INTO sandbox_name_dirty (session)
  SELECT ${key} WHERE ${key} IS NOT NULL AND NOT EXISTS
    (SELECT 1 FROM sandbox_name_dirty d WHERE d.session = ${key});`;
const CONFLICTS = `INSERT INTO sandbox_name_dirty (session)
  SELECT s.key FROM sessions s WHERE (s.token = NEW.token OR s.rowid = NEW.rowid) AND s.key IS NOT NEW.key
    AND NOT EXISTS (SELECT 1 FROM sandbox_name_dirty d WHERE d.session = s.key);`;

export const hasSandboxIndex = (db: DatabaseSync): boolean => db.prepare(EXISTS).get() !== undefined;

/// The old query orders by activity descending and lets the last session of a colliding name win. The ascending
/// activity and descending rowid reproduce that choice without reading unrelated sessions.
export const SANDBOX_SESSION = `SELECT s.key FROM sandbox_name_rows n
  CROSS JOIN sessions s ON s.key = n.session
  WHERE n.name = ? ORDER BY s.last_active_at ASC, s.rowid DESC LIMIT 1`;
export const SANDBOX_SCAN_FIRST = "SELECT key AS session FROM sessions WHERE key <= ? ORDER BY key LIMIT ?";
export const SANDBOX_SCAN_NEXT = "SELECT key AS session FROM sessions WHERE key > ? AND key <= ? ORDER BY key LIMIT ?";
export const SANDBOX_PRUNE_FIRST = "SELECT session FROM sandbox_name_rows WHERE session <= ? ORDER BY session LIMIT ?";
export const SANDBOX_PRUNE_NEXT = "SELECT session FROM sandbox_name_rows WHERE session > ? AND session <= ? ORDER BY session LIMIT ?";
export const SANDBOX_DIRTY_BATCH = "SELECT session FROM sandbox_name_dirty ORDER BY session LIMIT ?";

export function enableSandboxIndex(db: DatabaseSync): void {
  if (db.prepare(EXISTS).get() !== undefined) {
    const meta = db.prepare("SELECT version, enabled FROM sandbox_name_meta WHERE id = 1").get() as
      { version: number; enabled: number } | undefined;
    if (meta?.version !== VERSION) throw new Error(`sandbox name index version ${meta?.version ?? "missing"} is incompatible with ${VERSION}`);
    if (meta.enabled === 1) return;
  }
  db.exec("BEGIN IMMEDIATE");
  try {
    if (db.prepare(EXISTS).get() === undefined) {
      db.exec(`
        CREATE TABLE sandbox_name_meta (id INTEGER PRIMARY KEY CHECK (id = 1), version INTEGER NOT NULL,
          enabled INTEGER NOT NULL, phase INTEGER NOT NULL, cursor TEXT, prune INTEGER NOT NULL,
          end_session TEXT, end_prune TEXT) WITHOUT ROWID;
        INSERT INTO sandbox_name_meta (id, version, enabled, phase, cursor, prune, end_session, end_prune)
          VALUES (1, ${VERSION}, 1, 0, NULL, 0,
            (SELECT key FROM sessions WHERE key IS NOT NULL ORDER BY key DESC LIMIT 1), NULL);
        CREATE TABLE sandbox_name_rows (session TEXT PRIMARY KEY, name TEXT NOT NULL) WITHOUT ROWID;
        CREATE INDEX sandbox_name_lookup ON sandbox_name_rows (name);
        CREATE TABLE sandbox_name_dirty (session TEXT PRIMARY KEY) WITHOUT ROWID;
        CREATE TRIGGER sandbox_name_before_add BEFORE INSERT ON sessions
          WHEN (SELECT enabled FROM sandbox_name_meta WHERE id = 1) = 1 BEGIN
          ${DIRTY("NEW.key")} ${CONFLICTS}
        END;
        CREATE TRIGGER sandbox_name_before_change BEFORE UPDATE ON sessions
          WHEN (OLD.rowid IS NOT NEW.rowid OR OLD.key IS NOT NEW.key OR OLD.token IS NOT NEW.token)
            AND (SELECT enabled FROM sandbox_name_meta WHERE id = 1) = 1 BEGIN
          ${DIRTY("OLD.key")} ${DIRTY("NEW.key")} ${CONFLICTS}
        END;
        CREATE TRIGGER sandbox_name_before_drop BEFORE DELETE ON sessions
          WHEN (SELECT enabled FROM sandbox_name_meta WHERE id = 1) = 1 BEGIN
          ${DIRTY("OLD.key")}
        END;
      `);
    } else {
      const meta = db.prepare("SELECT version, enabled FROM sandbox_name_meta WHERE id = 1").get() as
        { version: number; enabled: number } | undefined;
      if (meta?.version !== VERSION) throw new Error(`sandbox name index version ${meta?.version ?? "missing"} is incompatible with ${VERSION}`);
      // While switched off no changes were journalled. Check all existing keys again and prune deleted keys, in
      // batches; the old rows stay usable only after this preparation and the journal are both complete.
      if (meta.enabled === 0) db.exec(`UPDATE sandbox_name_meta SET enabled = 1, phase = 0, cursor = NULL, prune = 1,
        end_session = (SELECT key FROM sessions WHERE key IS NOT NULL ORDER BY key DESC LIMIT 1),
        end_prune = (SELECT session FROM sandbox_name_rows ORDER BY session DESC LIMIT 1) WHERE id = 1`);
    }
    db.exec("COMMIT");
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

/// Stop journalling while sandboxes are off. Their next use prepares the lookup again before relying on it.
export function disableSandboxIndex(db: DatabaseSync): void {
  if (db.prepare(EXISTS).get() === undefined) return;
  const meta = db.prepare("SELECT version, enabled FROM sandbox_name_meta WHERE id = 1").get() as
    { version: number; enabled: number } | undefined;
  if (meta?.version !== VERSION) throw new Error(`sandbox name index version ${meta?.version ?? "missing"} is incompatible with ${VERSION}`);
  if (meta.enabled === 1) db.exec("UPDATE sandbox_name_meta SET enabled = 0 WHERE id = 1");
}

export function sandboxIndexReady(db: DatabaseSync): boolean {
  return db.prepare(`SELECT 1 FROM sandbox_name_meta WHERE id = 1 AND version = ? AND enabled = 1 AND phase = 2
    AND NOT EXISTS (SELECT 1 FROM sandbox_name_dirty LIMIT 1)`).get(VERSION) !== undefined;
}

export function sandboxIndexEnabled(db: DatabaseSync): boolean {
  if (!hasSandboxIndex(db)) return false;
  const meta = db.prepare("SELECT version, enabled FROM sandbox_name_meta WHERE id = 1").get() as
    { version: number; enabled: number } | undefined;
  if (meta?.version !== VERSION) throw new Error(`sandbox name index version ${meta?.version ?? "missing"} is incompatible with ${VERSION}`);
  return meta.enabled === 1;
}

/// A single read snapshot keeps the readiness check and every name lookup together with older writers.
export function sandboxSessions(db: DatabaseSync, names: readonly string[]): Map<string, string> | null {
  db.exec("BEGIN");
  try {
    if (!sandboxIndexReady(db)) { db.exec("COMMIT"); return null; }
    const lookup = db.prepare(SANDBOX_SESSION);
    const found = new Map<string, string>();
    for (const name of names) {
      const row = lookup.get(name) as { key: string } | undefined;
      if (row !== undefined) found.set(name, row.key);
    }
    db.exec("COMMIT");
    return found;
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

/// At most `limit` session or journal keys are processed under one writer transaction. A key changed behind the
/// cursor is journalled by SQLite, including when an older station uses a statement prepared before installation.
export function sandboxIndexStep(db: DatabaseSync, limit = 64): { done: boolean; visited: number } {
  if (!Number.isSafeInteger(limit) || limit < 1) throw new RangeError("sandbox name batch must be positive");
  db.exec("BEGIN IMMEDIATE");
  try {
    const meta = db.prepare("SELECT version, enabled, phase, cursor, prune, end_session, end_prune FROM sandbox_name_meta WHERE id = 1").get() as
      { version: number; enabled: number; phase: number; cursor: string | null; prune: number; end_session: string | null; end_prune: string | null } | undefined;
    if (meta?.version !== VERSION) throw new Error(`sandbox name index version ${meta?.version ?? "missing"} is incompatible with ${VERSION}`);
    if (meta.enabled !== 1) { db.exec("COMMIT"); return { done: true, visited: 0 }; }
    const save = db.prepare(`INSERT INTO sandbox_name_rows (session, name) VALUES (?, ?)
      ON CONFLICT(session) DO UPDATE SET name = excluded.name WHERE name IS NOT excluded.name`);
    const remove = db.prepare("DELETE FROM sandbox_name_rows WHERE session = ?");
    const clear = db.prepare("DELETE FROM sandbox_name_dirty WHERE session = ?");
    const present = db.prepare("SELECT 1 FROM sessions WHERE key = ?");
    let { phase, cursor } = meta;
    let visited = 0;
    while (visited < limit) {
      let rows: { session: string }[];
      if (phase === 0) {
        rows = meta.end_session === null ? [] : (cursor === null
          ? db.prepare(SANDBOX_SCAN_FIRST).all(meta.end_session, limit - visited)
          : db.prepare(SANDBOX_SCAN_NEXT).all(cursor, meta.end_session, limit - visited)) as { session: string }[];
        if (rows.length === 0) { phase = meta.prune === 1 ? 1 : 2; cursor = null; continue; }
        for (const { session } of rows) {
          save.run(session, sandboxName(keyPart(session)));
          clear.run(session);
          cursor = session;
          visited++;
        }
      } else if (phase === 1) {
        rows = meta.end_prune === null ? [] : (cursor === null
          ? db.prepare(SANDBOX_PRUNE_FIRST).all(meta.end_prune, limit - visited)
          : db.prepare(SANDBOX_PRUNE_NEXT).all(cursor, meta.end_prune, limit - visited)) as { session: string }[];
        if (rows.length === 0) { phase = 2; cursor = null; continue; }
        for (const { session } of rows) {
          if (present.get(session) === undefined) remove.run(session);
          cursor = session;
          visited++;
        }
      } else {
        rows = db.prepare(SANDBOX_DIRTY_BATCH).all(limit - visited) as { session: string }[];
        if (rows.length === 0) break;
        for (const { session } of rows) {
          if (present.get(session) === undefined) remove.run(session);
          else save.run(session, sandboxName(keyPart(session)));
          clear.run(session);
          visited++;
        }
      }
    }
    db.prepare("UPDATE sandbox_name_meta SET phase = ?, cursor = ? WHERE id = 1").run(phase, cursor);
    const done = phase === 2 && db.prepare("SELECT 1 FROM sandbox_name_dirty LIMIT 1").get() === undefined;
    db.exec("COMMIT");
    return { done, visited };
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}
