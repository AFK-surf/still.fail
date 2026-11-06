// Reverse lookup of the directories sessions use. Install only when a shared runtime needs it; the old rows and
// changes from older writers are prepared in bounded batches, without hashing or a long transaction in a trigger.
import type { DatabaseSync } from "node:sqlite";

const VERSION = 1;
const EXISTS = "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'session_dir_meta'";
const DIRTY = (key: string) => `INSERT INTO session_dir_dirty (session)
  SELECT ${key} WHERE ${key} IS NOT NULL AND NOT EXISTS
    (SELECT 1 FROM session_dir_dirty d WHERE d.session = ${key});`;
const CONFLICTS = `INSERT INTO session_dir_dirty (session)
  SELECT s.key FROM sessions s WHERE (s.token = NEW.token OR s.rowid = NEW.rowid) AND s.key IS NOT NEW.key
    AND NOT EXISTS (SELECT 1 FROM session_dir_dirty d WHERE d.session = s.key);`;

export const SESSION_DIR_FIRST = "SELECT key AS session FROM sessions WHERE key <= ? ORDER BY key LIMIT ?";
export const SESSION_DIR_NEXT = "SELECT key AS session FROM sessions WHERE key > ? AND key <= ? ORDER BY key LIMIT ?";
export const SESSION_DIR_DIRTY = "SELECT session FROM session_dir_dirty ORDER BY session LIMIT ?";
const DIRTY_LIMIT = 64;

/// The old live-session list is newest first (rowid descending on ties); the all-session list uses rowid ascending.
export const sessionDirectoryCandidate = (live: boolean) => `SELECT s.key FROM session_dir_rows d
  CROSS JOIN sessions s ON s.key = d.session
  WHERE d.root = ? AND s.archived_at IS ${live ? "" : "NOT "}NULL AND (s.workspace = d.root OR s.cwd = d.root)
  ORDER BY s.last_active_at DESC, s.rowid ${live ? "DESC" : "ASC"} LIMIT 1`;

export function sessionDirectoryChoice(count: number, live: boolean): string {
  if (!Number.isSafeInteger(count) || count < 1 || count > DIRTY_LIMIT + 1) throw new RangeError("bad directory candidate count");
  return `SELECT s.key FROM sessions s WHERE s.key IN (${Array(count).fill("?").join(", ")})
    AND s.archived_at IS ${live ? "" : "NOT "}NULL AND (s.workspace = ? OR s.cwd = ?)
    ORDER BY s.last_active_at DESC, s.rowid ${live ? "DESC" : "ASC"} LIMIT 1`;
}

export function installSessionDirectories(db: DatabaseSync): void {
  if (db.prepare(EXISTS).get() !== undefined) {
    const meta = db.prepare("SELECT version FROM session_dir_meta WHERE id = 1").get() as { version: number } | undefined;
    if (meta?.version !== VERSION) throw new Error(`session directory index version ${meta?.version ?? "missing"} is incompatible with ${VERSION}`);
    return;
  }
  db.exec("BEGIN IMMEDIATE");
  try {
    if (db.prepare(EXISTS).get() === undefined) db.exec(`
      CREATE TABLE session_dir_meta (id INTEGER PRIMARY KEY CHECK (id = 1), version INTEGER NOT NULL,
        phase INTEGER NOT NULL, cursor TEXT, end_session TEXT) WITHOUT ROWID;
      INSERT INTO session_dir_meta VALUES (1, ${VERSION}, 0, NULL,
        (SELECT key FROM sessions WHERE key IS NOT NULL ORDER BY key DESC LIMIT 1));
      CREATE TABLE session_dir_rows (session TEXT NOT NULL, root TEXT NOT NULL, PRIMARY KEY(session, root)) WITHOUT ROWID;
      CREATE INDEX session_dir_root ON session_dir_rows (root, session);
      CREATE TABLE session_dir_dirty (session TEXT PRIMARY KEY) WITHOUT ROWID;
      CREATE TRIGGER session_dir_before_add BEFORE INSERT ON sessions BEGIN
        ${DIRTY("NEW.key")} ${CONFLICTS}
      END;
      CREATE TRIGGER session_dir_before_change BEFORE UPDATE ON sessions
        WHEN OLD.rowid IS NOT NEW.rowid OR OLD.key IS NOT NEW.key OR OLD.token IS NOT NEW.token
          OR OLD.workspace IS NOT NEW.workspace OR OLD.cwd IS NOT NEW.cwd BEGIN
        ${DIRTY("OLD.key")} ${DIRTY("NEW.key")} ${CONFLICTS}
      END;
      CREATE TRIGGER session_dir_before_drop BEFORE DELETE ON sessions BEGIN
        ${DIRTY("OLD.key")}
      END;
    `);
    db.exec("COMMIT");
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

export function sessionDirectoriesReady(db: DatabaseSync): boolean {
  return db.prepare(EXISTS).get() !== undefined && db.prepare(`SELECT 1 FROM session_dir_meta
    WHERE id = 1 AND version = ? AND phase = 1 AND NOT EXISTS (SELECT 1 FROM session_dir_dirty LIMIT 1)`).get(VERSION) !== undefined;
}

/// Exactly those strings for which the old `sessionIn` considers `dir` to be at or below the root, longest first.
function rootsOf(dir: string): string[] {
  const roots = new Set<string>();
  if (dir) roots.add(dir);
  for (let i = 0; i < dir.length; i++) if (dir[i] === "/") {
    if (i > 0) roots.add(dir.slice(0, i));
    roots.add(dir.slice(0, i + 1));
  }
  return [...roots].sort((a, b) => b.length - a.length);
}

export type DirectorySession = { key: string | null; live: boolean };

/// Null means the old immediate lookup is needed. An answer and the small pending journal use one snapshot.
export function sessionDirectory(db: DatabaseSync, dir: string): DirectorySession | null {
  if (db.prepare(EXISTS).get() === undefined) return null;
  db.exec("BEGIN");
  try {
    const prepared = db.prepare("SELECT 1 FROM session_dir_meta WHERE id = 1 AND version = ? AND phase = 1").get(VERSION);
    if (prepared === undefined) { db.exec("COMMIT"); return null; }
    const dirty = db.prepare(SESSION_DIR_DIRTY).all(DIRTY_LIMIT + 1) as { session: string }[];
    if (dirty.length > DIRTY_LIMIT) { db.exec("COMMIT"); return null; }
    const roots = rootsOf(dir), wanted = new Set(roots), changed = new Map<string, string[]>();
    const read = db.prepare("SELECT workspace, cwd FROM sessions WHERE key = ?");
    for (const { session } of dirty) {
      const row = read.get(session) as { workspace: string; cwd: string | null } | undefined;
      if (row === undefined) continue;
      for (const root of new Set([row.workspace, row.cwd])) if (root && wanted.has(root))
        changed.set(root, [...(changed.get(root) ?? []), session]);
    }
    for (const live of [true, false]) {
      const candidate = db.prepare(sessionDirectoryCandidate(live));
      for (const root of roots) {
        let key = (candidate.get(root) as { key: string } | undefined)?.key;
        const updates = changed.get(root);
        if (updates !== undefined) {
          const choices = [...new Set(key === undefined ? updates : [key, ...updates])];
          key = (db.prepare(sessionDirectoryChoice(choices.length, live)).get(...choices, root, root) as { key: string } | undefined)?.key;
        }
        if (key !== undefined) { db.exec("COMMIT"); return { key, live }; }
      }
    }
    db.exec("COMMIT");
    return { key: null, live: false };
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

/// Each transaction visits at most `limit` historical or journalled sessions.
export function sessionDirectoriesStep(db: DatabaseSync, limit = 64): { done: boolean; visited: number } {
  if (!Number.isSafeInteger(limit) || limit < 1) throw new RangeError("session directory batch must be positive");
  db.exec("BEGIN IMMEDIATE");
  try {
    const meta = db.prepare("SELECT version, phase, cursor, end_session FROM session_dir_meta WHERE id = 1").get() as
      { version: number; phase: number; cursor: string | null; end_session: string | null } | undefined;
    if (meta?.version !== VERSION) throw new Error(`session directory index version ${meta?.version ?? "missing"} is incompatible with ${VERSION}`);
    const remove = db.prepare("DELETE FROM session_dir_rows WHERE session = ?");
    const insert = db.prepare(`INSERT INTO session_dir_rows (session, root)
      SELECT key, workspace FROM sessions WHERE key = ? AND workspace <> ''
      UNION SELECT key, cwd FROM sessions WHERE key = ? AND cwd IS NOT NULL AND cwd <> ''`);
    const clear = db.prepare("DELETE FROM session_dir_dirty WHERE session = ?");
    let { phase, cursor } = meta;
    let visited = 0;
    while (visited < limit) {
      let rows: { session: string }[];
      if (phase === 0) {
        rows = meta.end_session === null ? [] : (cursor === null
          ? db.prepare(SESSION_DIR_FIRST).all(meta.end_session, limit - visited)
          : db.prepare(SESSION_DIR_NEXT).all(cursor, meta.end_session, limit - visited)) as { session: string }[];
        if (rows.length === 0) { phase = 1; cursor = null; continue; }
      } else {
        rows = db.prepare(SESSION_DIR_DIRTY).all(limit - visited) as { session: string }[];
        if (rows.length === 0) break;
      }
      for (const { session } of rows) {
        remove.run(session);
        insert.run(session, session);
        clear.run(session);
        if (phase === 0) cursor = session;
        visited++;
      }
    }
    db.prepare("UPDATE session_dir_meta SET phase = ?, cursor = ? WHERE id = 1").run(phase, cursor);
    const done = phase === 1 && db.prepare("SELECT 1 FROM session_dir_dirty LIMIT 1").get() === undefined;
    db.exec("COMMIT");
    return { done, visited };
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}
