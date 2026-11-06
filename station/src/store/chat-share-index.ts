// The share table keeps lapsed grants so another workspace can be told why access ended. Prepare their deadlines in
// bounded batches; an older station's writes only journal keys and never parse a chat's shares in its transaction.
import type { DatabaseSync } from "node:sqlite";
import { type Json, XSHARE_IDLE_MS, shareLive, toChatShare } from "./rows.ts";

const VERSION = 1;
const EXISTS = "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'chat_share_index_meta'";
const DIRTY_LIMIT = 64;
const SHARE_CHARS_LIMIT = 16_384;
const SHARE_TARGET_LIMIT = 16;
const dirty = (key: string) => `INSERT INTO chat_share_dirty (session)
  SELECT ${key} WHERE ${key} IS NOT NULL AND NOT EXISTS (SELECT 1 FROM chat_share_dirty d WHERE d.session = ${key});`;
const conflicts = `INSERT INTO chat_share_dirty (session)
  SELECT s.session FROM chat_shares s WHERE s.rowid = NEW.rowid AND s.session IS NOT NEW.session
    AND s.session IS NOT NULL AND NOT EXISTS (SELECT 1 FROM chat_share_dirty d WHERE d.session = s.session);`;

export const SHARE_FIRST = "SELECT session FROM chat_shares WHERE session <= ? ORDER BY session LIMIT ?";
export const SHARE_NEXT = "SELECT session FROM chat_shares WHERE session > ? AND session <= ? ORDER BY session LIMIT ?";
export const SHARE_DIRTY = "SELECT session FROM chat_share_dirty ORDER BY session LIMIT ?";
export const SHARE_MANY = "SELECT 1 FROM chat_shares LIMIT 1 OFFSET 32";
const OVERLAY = `SELECT c.* FROM (SELECT session FROM chat_share_dirty UNION SELECT session FROM chat_share_uncertain) k
  CROSS JOIN chat_shares c ON c.session = k.session`;
const CLEAN = "NOT EXISTS (SELECT 1 FROM chat_share_dirty d WHERE d.session = t.session)";
export const SHARE_LIVE = `WITH keys AS (
  SELECT t.session FROM chat_share_targets t INDEXED BY chat_share_target_time WHERE t.used > ?1 AND ${CLEAN}
  UNION SELECT session FROM chat_share_dirty UNION SELECT session FROM chat_share_uncertain
)
SELECT c.* FROM keys k CROSS JOIN chat_shares c ON c.session = k.session ORDER BY c.rowid`;
export const SHARE_DUE = `WITH keys AS (
  SELECT t.session FROM chat_share_targets t INDEXED BY chat_share_target_time WHERE t.used > ?1 AND t.used <= ?2 AND ${CLEAN}
  UNION SELECT session FROM chat_share_dirty UNION SELECT session FROM chat_share_uncertain
)
SELECT c.* FROM keys k CROSS JOIN chat_shares c ON c.session = k.session ORDER BY c.rowid`;
export const SHARE_NEXT_TIME = `SELECT t.used FROM chat_share_targets t INDEXED BY chat_share_target_time
  WHERE t.used > ? AND ${CLEAN} ORDER BY t.used LIMIT 1`;
export const SHARE_LAPSED_WORKSPACE = `SELECT 1 FROM chat_share_targets t INDEXED BY chat_share_target_workspace
  WHERE t.workspace = ? AND t.used <= ? AND ${CLEAN} LIMIT 1`;

export const hasChatShareIndex = (db: DatabaseSync) => db.prepare(EXISTS).get() !== undefined;

export function installChatShareIndex(db: DatabaseSync): void {
  if (hasChatShareIndex(db)) {
    const meta = db.prepare("SELECT version FROM chat_share_index_meta WHERE id = 1").get() as { version: number } | undefined;
    if (meta?.version !== VERSION) throw new Error(`chat share index version ${meta?.version ?? "missing"} is incompatible with ${VERSION}`);
    return;
  }
  db.exec("BEGIN IMMEDIATE");
  try {
    if (!hasChatShareIndex(db)) db.exec(`
      CREATE TABLE chat_share_index_meta (id INTEGER PRIMARY KEY CHECK (id = 1), version INTEGER NOT NULL,
        phase INTEGER NOT NULL, cursor TEXT, end_session TEXT) WITHOUT ROWID;
      INSERT INTO chat_share_index_meta VALUES (1, ${VERSION}, 0, NULL,
        (SELECT session FROM chat_shares WHERE session IS NOT NULL ORDER BY session DESC LIMIT 1));
      CREATE TABLE chat_share_targets (session TEXT NOT NULL, ordinal INTEGER NOT NULL, workspace TEXT NOT NULL,
        used INTEGER NOT NULL, PRIMARY KEY(session, ordinal)) WITHOUT ROWID;
      CREATE INDEX chat_share_target_time ON chat_share_targets (used, session);
      CREATE INDEX chat_share_target_workspace ON chat_share_targets (workspace, used, session);
      CREATE TABLE chat_share_uncertain (session TEXT PRIMARY KEY) WITHOUT ROWID;
      CREATE TABLE chat_share_dirty (session TEXT PRIMARY KEY) WITHOUT ROWID;
      CREATE TRIGGER chat_share_index_before_add BEFORE INSERT ON chat_shares BEGIN ${dirty("NEW.session")} ${conflicts} END;
      CREATE TRIGGER chat_share_index_before_change BEFORE UPDATE ON chat_shares
        WHEN OLD.rowid IS NOT NEW.rowid OR OLD.session IS NOT NEW.session OR OLD.shared IS NOT NEW.shared OR OLD.at IS NOT NEW.at
        BEGIN ${dirty("OLD.session")} ${dirty("NEW.session")} ${conflicts} END;
      CREATE TRIGGER chat_share_index_before_drop BEFORE DELETE ON chat_shares BEGIN ${dirty("OLD.session")} END;
    `);
    else {
      const meta = db.prepare("SELECT version FROM chat_share_index_meta WHERE id = 1").get() as { version: number } | undefined;
      if (meta?.version !== VERSION) throw new Error(`chat share index version ${meta?.version ?? "missing"} is incompatible with ${VERSION}`);
    }
    db.exec("COMMIT");
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

export function chatShareIndexReady(db: DatabaseSync): boolean {
  return hasChatShareIndex(db) && db.prepare(`SELECT 1 FROM chat_share_index_meta WHERE id = 1 AND version = ? AND phase = 1
    AND NOT EXISTS (SELECT 1 FROM chat_share_dirty LIMIT 1)`).get(VERSION) !== undefined;
}

function shareValues(row: Json): ReturnType<typeof toChatShare>["to"] | null {
  try {
    if (typeof row.shared !== "string" || row.shared.length > SHARE_CHARS_LIMIT) return null;
    const values = toChatShare(row).to;
    return values.length <= SHARE_TARGET_LIMIT && values.every((t) => Number.isSafeInteger(t.used) && Number.isSafeInteger(t.used + XSHARE_IDLE_MS))
      ? values : null;
  } catch { return null; }
}

/// At most `limit` chat keys are processed under one writer transaction. Unusual old values remain on a short list
/// that keeps reads on the original JavaScript rules, including excessively large or noncanonical saved shares.
export function chatShareIndexStep(db: DatabaseSync, limit = 64): { done: boolean; visited: number } {
  if (!Number.isSafeInteger(limit) || limit < 1) throw new RangeError("chat share batch must be positive");
  db.exec("BEGIN IMMEDIATE");
  try {
    const meta = db.prepare("SELECT version, phase, cursor, end_session FROM chat_share_index_meta WHERE id = 1").get() as
      { version: number; phase: number; cursor: string | null; end_session: string | null } | undefined;
    if (meta?.version !== VERSION) throw new Error(`chat share index version ${meta?.version ?? "missing"} is incompatible with ${VERSION}`);
    const source = db.prepare("SELECT * FROM chat_shares WHERE session = ?");
    const remove = db.prepare("DELETE FROM chat_share_targets WHERE session = ?");
    const removeUncertain = db.prepare("DELETE FROM chat_share_uncertain WHERE session = ?");
    const add = db.prepare("INSERT INTO chat_share_targets (session, ordinal, workspace, used) VALUES (?, ?, ?, ?)");
    const uncertain = db.prepare("INSERT INTO chat_share_uncertain (session) VALUES (?)");
    const clear = db.prepare("DELETE FROM chat_share_dirty WHERE session = ?");
    let { phase, cursor } = meta;
    let visited = 0;
    while (visited < limit) {
      const keys = phase === 0 ? (meta.end_session === null ? [] : (cursor === null
        ? db.prepare(SHARE_FIRST).all(meta.end_session, limit - visited)
        : db.prepare(SHARE_NEXT).all(cursor, meta.end_session, limit - visited)))
        : db.prepare(SHARE_DIRTY).all(limit - visited);
      if (keys.length === 0) { if (phase === 0) { phase = 1; cursor = null; continue; } break; }
      for (const { session } of keys as { session: string }[]) {
        remove.run(session); removeUncertain.run(session);
        const row = source.get(session) as Json | undefined;
        if (row !== undefined) {
          const values = shareValues(row);
          if (values === null) uncertain.run(session);
          else for (let i = 0; i < values.length; i++) {
            const target = values[i]!;
            add.run(session, i, target.workspace, target.used);
          }
        }
        clear.run(session);
        if (phase === 0) cursor = session;
        visited++;
      }
    }
    db.prepare("UPDATE chat_share_index_meta SET phase = ?, cursor = ? WHERE id = 1").run(phase, cursor);
    const done = phase === 1 && db.prepare("SELECT 1 FROM chat_share_dirty LIMIT 1").get() === undefined;
    db.exec("COMMIT");
    return { done, visited };
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

function snapshot<T>(db: DatabaseSync, now: number, read: () => T): T | null {
  if (!Number.isSafeInteger(now) || !Number.isSafeInteger(now - XSHARE_IDLE_MS) || !hasChatShareIndex(db)) return null;
  db.exec("BEGIN");
  try {
    const prepared = db.prepare("SELECT 1 FROM chat_share_index_meta WHERE id = 1 AND version = ? AND phase = 1").get(VERSION);
    const dirtyKeys = db.prepare(SHARE_DIRTY).all(DIRTY_LIMIT + 1) as { session: string }[];
    // An old SQLite table can contain a null primary key. Preserve the old answer until it is removed.
    const nullKey = db.prepare("SELECT 1 FROM chat_shares WHERE session IS NULL LIMIT 1").get();
    const uncertain = db.prepare("SELECT 1 FROM chat_share_uncertain LIMIT 1").get();
    if (prepared === undefined || dirtyKeys.length > DIRTY_LIMIT || nullKey !== undefined || uncertain !== undefined) {
      db.exec("COMMIT"); return null;
    }
    const source = db.prepare("SELECT * FROM chat_shares WHERE session = ?");
    for (const { session } of dirtyKeys) {
      const row = source.get(session) as Json | undefined;
      if (row !== undefined && shareValues(row) === null) { db.exec("COMMIT"); return null; }
    }
    const result = read();
    db.exec("COMMIT");
    return result;
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

export function liveChatShareRows(db: DatabaseSync, now: number): Json[] | null {
  return snapshot(db, now, () => db.prepare(SHARE_LIVE).all(now - XSHARE_IDLE_MS) as Json[]);
}

export function dueChatShareRows(db: DatabaseSync, since: number, now: number): { rows: Json[]; next: number | null } | null {
  if (!Number.isSafeInteger(since) || !Number.isSafeInteger(since - XSHARE_IDLE_MS)) return null;
  return snapshot(db, now, () => {
    const rows = db.prepare(SHARE_DUE).all(since - XSHARE_IDLE_MS, now - XSHARE_IDLE_MS) as Json[];
    const earliest = db.prepare(SHARE_NEXT_TIME).get(now - XSHARE_IDLE_MS) as { used: number } | undefined;
    return { rows, next: earliest === undefined ? null : earliest.used + XSHARE_IDLE_MS };
  });
}

/// Only guests already known to the sharing service can be forgotten; seek each one's earliest retained grant.
export function lapsedChatShareWorkspaces(db: DatabaseSync, workspaces: readonly string[], now: number): Set<string> | null {
  return snapshot(db, now, () => {
    const found = new Set<string>();
    const wanted = new Set(workspaces);
    const lookup = db.prepare(SHARE_LAPSED_WORKSPACE);
    for (const workspace of wanted) if (lookup.get(workspace, now - XSHARE_IDLE_MS) !== undefined) found.add(workspace);
    for (const row of db.prepare(OVERLAY).all() as Json[]) for (const t of toChatShare(row).to)
      if (wanted.has(t.workspace) && !shareLive(t, now)) found.add(t.workspace);
    return found;
  });
}
