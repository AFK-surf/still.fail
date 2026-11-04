// A maintained ordering for the recent chat tool. This first part keeps the unscoped ordering; workspace visibility
// and its independently prepared counts are built on it separately.
import type { DatabaseSync } from "node:sqlite";

export type RecentChatPage = { ids: number[]; total: number };

// Do not use INSERT OR IGNORE inside a trigger: an outer INSERT OR REPLACE can override that conflict policy. The
// existence test keeps one pending entry even when an older process writes with its own conflict mode.
const dirty = (thread: string) => `INSERT INTO recent_chat_dirty (thread)
  SELECT ${thread} WHERE ${thread} IS NOT NULL AND NOT EXISTS
    (SELECT 1 FROM recent_chat_dirty WHERE thread = ${thread});`;

const SCHEMA = `
CREATE TABLE recent_chat_rows (thread INTEGER PRIMARY KEY, at INTEGER NOT NULL, said_at INTEGER NOT NULL, created_at INTEGER NOT NULL);
CREATE INDEX recent_chat_order ON recent_chat_rows (at DESC, said_at DESC, created_at DESC, thread DESC);
CREATE TABLE recent_chat_dirty (thread INTEGER PRIMARY KEY);
CREATE TABLE recent_chat_meta (id INTEGER PRIMARY KEY CHECK (id = 1), cursor INTEGER, through INTEGER,
  total INTEGER NOT NULL, complete INTEGER NOT NULL, prefer_dirty INTEGER NOT NULL);
INSERT INTO recent_chat_meta SELECT 1, NULL, (SELECT MAX(id) FROM threads), 0,
  NOT EXISTS (SELECT 1 FROM threads LIMIT 1), 1;

CREATE TRIGGER recent_chat_thread_add AFTER INSERT ON threads BEGIN ${dirty("NEW.id")} END;
CREATE TRIGGER recent_chat_thread_change AFTER UPDATE OF id, created_at ON threads BEGIN ${dirty("OLD.id")} ${dirty("NEW.id")} END;
CREATE TRIGGER recent_chat_thread_drop AFTER DELETE ON threads BEGIN ${dirty("OLD.id")} END;
CREATE TRIGGER recent_chat_state_add AFTER INSERT ON thread_state BEGIN ${dirty("NEW.thread")} END;
CREATE TRIGGER recent_chat_state_change AFTER UPDATE OF thread, said_n ON thread_state BEGIN ${dirty("OLD.thread")} ${dirty("NEW.thread")} END;
CREATE TRIGGER recent_chat_state_drop AFTER DELETE ON thread_state BEGIN ${dirty("OLD.thread")} END;
CREATE TRIGGER recent_chat_entry_add AFTER INSERT ON entries BEGIN ${dirty("NEW.thread")} END;
CREATE TRIGGER recent_chat_entry_change AFTER UPDATE OF thread, n, kind, at ON entries BEGIN ${dirty("OLD.thread")} ${dirty("NEW.thread")} END;
CREATE TRIGGER recent_chat_entry_drop AFTER DELETE ON entries BEGIN ${dirty("OLD.thread")} END;
`;

/// Install empty tables and writers without reading historical chats. Old rows are added by bounded later steps.
export function installRecentChatIndex(db: DatabaseSync): void {
  const installed = () => db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'recent_chat_meta'").get() !== undefined;
  if (installed()) return;
  db.exec("BEGIN IMMEDIATE");
  try {
    if (!installed()) db.exec(SCHEMA);
    db.exec("COMMIT");
  } catch (error) {
    db.exec("ROLLBACK");
    throw error;
  }
}

type Meta = { cursor: number | null; through: number | null; total: number; complete: number; prefer_dirty: number };
type Current = { id: number; at: number; said_at: number; created_at: number };

/// Account at most `limit` old or changed chats, atomically with the cursor. New writes coalesce by thread. Alternate
/// old and changed work while both exist so a stream of new messages cannot indefinitely postpone old chats.
export function stepRecentChatIndex(db: DatabaseSync, limit = 64): { done: boolean; processed: number } {
  if (!Number.isSafeInteger(limit) || limit < 1) throw new RangeError("recent chat batch must be positive");
  db.exec("BEGIN IMMEDIATE");
  try {
    const meta = db.prepare("SELECT cursor, through, total, complete, prefer_dirty FROM recent_chat_meta WHERE id = 1").get() as Meta;
    const pending = db.prepare("SELECT thread FROM recent_chat_dirty ORDER BY thread LIMIT ?").all(limit) as { thread: number }[];
    const useDirty = pending.length > 0 && (meta.complete === 1 || meta.prefer_dirty === 1);
    const old = !useDirty && meta.complete === 0 && meta.through !== null
      ? (meta.cursor === null
        ? db.prepare("SELECT id AS thread FROM threads WHERE id <= ? ORDER BY id LIMIT ?").all(meta.through, limit)
        : db.prepare("SELECT id AS thread FROM threads WHERE id > ? AND id <= ? ORDER BY id LIMIT ?").all(meta.cursor, meta.through, limit)) as { thread: number }[]
      : [];
    const rows = useDirty ? pending : old;
    const current = db.prepare(`SELECT t.id, COALESCE(e.at, t.created_at) AS at, COALESCE(e.at, 0) AS said_at, t.created_at
      FROM threads t LEFT JOIN thread_state s ON s.thread = t.id
      LEFT JOIN entries e ON e.thread = t.id AND e.n = s.said_n AND e.kind = 'message' WHERE t.id = ?`);
    const exists = db.prepare("SELECT 1 FROM recent_chat_rows WHERE thread = ?");
    const put = db.prepare(`INSERT INTO recent_chat_rows (thread, at, said_at, created_at) VALUES (?, ?, ?, ?)
      ON CONFLICT (thread) DO UPDATE SET at = excluded.at, said_at = excluded.said_at, created_at = excluded.created_at
      WHERE at IS NOT excluded.at OR said_at IS NOT excluded.said_at OR created_at IS NOT excluded.created_at`);
    const remove = db.prepare("DELETE FROM recent_chat_rows WHERE thread = ?");
    const clean = db.prepare("DELETE FROM recent_chat_dirty WHERE thread = ?");
    let delta = 0;
    for (const row of rows) {
      const had = exists.get(row.thread) !== undefined;
      const now = current.get(row.thread) as Current | undefined;
      if (now === undefined) {
        if (had) { remove.run(row.thread); delta--; }
      } else {
        put.run(now.id, now.at, now.said_at, now.created_at);
        if (!had) delta++;
      }
      clean.run(row.thread);
    }
    if (useDirty) db.prepare("UPDATE recent_chat_meta SET total = total + ?, prefer_dirty = 0 WHERE id = 1").run(delta);
    else db.prepare("UPDATE recent_chat_meta SET cursor = ?, total = total + ?, complete = ?, prefer_dirty = 1 WHERE id = 1")
      .run(rows.at(-1)?.thread ?? meta.cursor, delta, meta.complete === 1 || rows.length < limit ? 1 : 0);
    const done = (db.prepare("SELECT complete FROM recent_chat_meta WHERE id = 1").get() as { complete: number }).complete === 1 &&
      db.prepare("SELECT 1 FROM recent_chat_dirty LIMIT 1").get() === undefined;
    db.exec("COMMIT");
    return { done, processed: rows.length };
  } catch (error) {
    db.exec("ROLLBACK");
    throw error;
  }
}

/// Null means old or changed chats are still being accounted. The caller waits outside the reader and asks again.
export function readGlobalRecentChatIndex(db: DatabaseSync, limit: number): RecentChatPage | null {
  if (limit === 0) return { ids: [], total: 0 };
  db.exec("SAVEPOINT recent_chat_page");
  try {
    const meta = db.prepare("SELECT total, complete FROM recent_chat_meta WHERE id = 1").get() as { total: number; complete: number };
    if (meta.complete !== 1 || db.prepare("SELECT 1 FROM recent_chat_dirty LIMIT 1").get() !== undefined) return null;
    const rows = db.prepare("SELECT thread FROM recent_chat_rows INDEXED BY recent_chat_order ORDER BY at DESC, said_at DESC, created_at DESC, thread DESC LIMIT ?")
      .all(limit) as { thread: number }[];
    return { ids: rows.map((row) => row.thread), total: meta.total };
  } finally { db.exec("RELEASE recent_chat_page"); }
}
