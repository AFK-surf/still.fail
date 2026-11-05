// An incremental default-home index. Message ordering, overlap with the explicit home workspace, and the real
// reader are not connected yet: this module cannot certify a complete page.
import type { DatabaseSync } from "node:sqlite";
import { recentHomeChatStep } from "./chat-list-home-source.ts";
import { acknowledgeRecentScopeSession, installRecentScopeJournal, trackRecentScope } from "./chat-list-scope-journal.ts";
import { recentScopeSessionThreadsStep } from "./chat-list-scope-source.ts";

const mark = (thread: string) => `
  UPDATE recent_home_dirty SET revision = revision + 1 WHERE thread = ${thread};
  INSERT INTO recent_home_dirty(thread, revision) SELECT ${thread}, 1 WHERE ${thread} IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM recent_home_dirty WHERE thread = ${thread});`;
const conflictingThread = `(SELECT t.id FROM threads t WHERE t.surface = NEW.surface AND t.channel = NEW.channel
  AND t.thread_ts = NEW.thread_ts AND t.id IS NOT NEW.id)`;
const conflictingMember = `(SELECT thread FROM thread_sessions WHERE rowid = NEW.rowid)`;

/// Install empty tables and triggers, and track session changes in the same transaction as the initial boundary.
export function installRecentHomeIndex(db: DatabaseSync): void {
  installRecentScopeJournal(db);
  const installed = () => db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'recent_home_meta'").get() !== undefined;
  if (installed()) return;
  db.exec("BEGIN IMMEDIATE");
  try {
    if (!installed()) {
      db.exec(`
        CREATE TABLE recent_home_meta (id INTEGER PRIMARY KEY CHECK (id = 1), cursor INTEGER, through INTEGER,
          scan_done INTEGER NOT NULL, total INTEGER NOT NULL);
        INSERT INTO recent_home_meta SELECT 1, NULL, (SELECT MAX(id) FROM threads),
          NOT EXISTS (SELECT 1 FROM threads LIMIT 1), 0;
        CREATE TABLE recent_home_dirty (thread INTEGER PRIMARY KEY, revision INTEGER NOT NULL);
        CREATE TABLE recent_home_work (thread INTEGER PRIMARY KEY, revision INTEGER NOT NULL, after_session TEXT, seen INTEGER NOT NULL);
        CREATE TABLE recent_home_session_work (session TEXT PRIMARY KEY, revision INTEGER NOT NULL, phase TEXT NOT NULL, after INTEGER);
        CREATE TABLE recent_home_rows (thread INTEGER PRIMARY KEY, at INTEGER NOT NULL, said_at INTEGER NOT NULL, created_at INTEGER NOT NULL);
        CREATE INDEX recent_home_order ON recent_home_rows(at DESC, said_at DESC, created_at DESC, thread DESC);
        CREATE TRIGGER recent_home_thread_before_add BEFORE INSERT ON threads BEGIN
          ${mark("(SELECT id FROM threads WHERE id = NEW.id)")} ${mark(conflictingThread)}
        END;
        CREATE TRIGGER recent_home_thread_before_change BEFORE UPDATE OF id, surface, channel, thread_ts ON threads BEGIN
          ${mark(conflictingThread)}
        END;
        CREATE TRIGGER recent_home_thread_add AFTER INSERT ON threads BEGIN ${mark("NEW.id")} END;
        CREATE TRIGGER recent_home_thread_change AFTER UPDATE OF id, home ON threads
          WHEN OLD.id IS NOT NEW.id OR OLD.home IS NOT NEW.home BEGIN ${mark("OLD.id")} END;
        CREATE TRIGGER recent_home_thread_move AFTER UPDATE OF id ON threads WHEN OLD.id IS NOT NEW.id BEGIN ${mark("NEW.id")} END;
        CREATE TRIGGER recent_home_thread_drop AFTER DELETE ON threads BEGIN ${mark("OLD.id")} END;
        CREATE TRIGGER recent_home_member_before_add BEFORE INSERT ON thread_sessions BEGIN ${mark(conflictingMember)} END;
        CREATE TRIGGER recent_home_member_add AFTER INSERT ON thread_sessions BEGIN ${mark("NEW.thread")} END;
        CREATE TRIGGER recent_home_member_before_change BEFORE UPDATE OF thread, session, rowid ON thread_sessions
          WHEN OLD.thread IS NOT NEW.thread OR OLD.session IS NOT NEW.session OR OLD.rowid IS NOT NEW.rowid BEGIN
            ${mark("OLD.thread")} ${mark(conflictingMember)}
        END;
        CREATE TRIGGER recent_home_member_change AFTER UPDATE OF thread, session ON thread_sessions
          WHEN OLD.thread IS NOT NEW.thread OR OLD.session IS NOT NEW.session BEGIN ${mark("NEW.thread")} END;
        CREATE TRIGGER recent_home_member_drop BEFORE DELETE ON thread_sessions BEGIN ${mark("OLD.thread")} END;
      `);
      trackRecentScope(db, { kind: "home" });
    }
    db.exec("COMMIT");
  } catch (error) { db.exec("ROLLBACK"); throw error; }
}

/// A session becoming known, disappearing, or moving into/out of the default workspace can change many chats.
/// Journal their ids in bounded source batches; the caller must wait for this and the per-chat journal to drain.
export function settleRecentHomeSessionStep(db: DatabaseSync, limit = 64): { sessionsDone: boolean; visited: number } {
  if (!Number.isSafeInteger(limit) || limit < 1) throw new RangeError("recent home session batch must be positive");
  db.exec("BEGIN IMMEDIATE");
  try {
    const next = db.prepare("SELECT session, revision FROM recent_scope_session_dirty WHERE kind = 0 AND ws = '' ORDER BY session LIMIT 1");
    next.setReadBigInts(true);
    const pending = next.get() as { session: string; revision: bigint } | undefined;
    if (!pending) { db.exec("COMMIT"); return { sessionsDone: true, visited: 0 }; }
    const getWork = db.prepare("SELECT revision, phase, after FROM recent_home_session_work WHERE session = ?");
    getWork.setReadBigInts(true);
    let work = getWork.get(pending.session) as { revision: bigint; phase: "home" | "members"; after: bigint | null } | undefined;
    if (!work || work.revision !== pending.revision) {
      db.prepare(`INSERT INTO recent_home_session_work(session, revision, phase, after) VALUES (?, ?, 'home', NULL)
        ON CONFLICT(session) DO UPDATE SET revision = excluded.revision, phase = 'home', after = NULL`)
        .run(pending.session, pending.revision);
      work = { revision: pending.revision, phase: "home", after: null };
    }
    const batch = recentScopeSessionThreadsStep(db, pending.session, { phase: work.phase, after: work.after }, limit);
    const update = db.prepare("UPDATE recent_home_dirty SET revision = revision + 1 WHERE thread = ?");
    const insert = db.prepare(`INSERT INTO recent_home_dirty(thread, revision) SELECT ?1, 1
      WHERE NOT EXISTS (SELECT 1 FROM recent_home_dirty WHERE thread = ?1)`);
    for (const thread of batch.threads) { update.run(thread); insert.run(thread); }
    if (batch.cursor.phase === "done") {
      db.prepare("DELETE FROM recent_home_session_work WHERE session = ?").run(pending.session);
      acknowledgeRecentScopeSession(db, { kind: "home" }, pending.session, pending.revision);
    } else db.prepare("UPDATE recent_home_session_work SET phase = ?, after = ? WHERE session = ?")
      .run(batch.cursor.phase, batch.cursor.after, pending.session);
    const done = db.prepare("SELECT 1 FROM recent_scope_session_dirty WHERE kind = 0 AND ws = '' LIMIT 1").get() === undefined;
    db.exec("COMMIT");
    return { sessionsDone: done, visited: batch.visited };
  } catch (error) { db.exec("ROLLBACK"); throw error; }
}

/// Add at most `limit` old chats to the journal. New or replaced chats are independently marked by the writers.
export function scanRecentHomeChatsStep(db: DatabaseSync, limit = 64): { scanDone: boolean; visited: number } {
  if (!Number.isSafeInteger(limit) || limit < 1) throw new RangeError("recent home scan batch must be positive");
  db.exec("BEGIN IMMEDIATE");
  try {
    const get = db.prepare("SELECT cursor, through, scan_done FROM recent_home_meta WHERE id = 1");
    get.setReadBigInts(true);
    const meta = get.get() as { cursor: bigint | null; through: bigint | null; scan_done: bigint };
    if (meta.scan_done === 1n || meta.through === null) { db.exec("COMMIT"); return { scanDone: true, visited: 0 }; }
    const query = db.prepare(meta.cursor === null
      ? "SELECT id FROM threads WHERE id <= ?1 ORDER BY id LIMIT ?2"
      : "SELECT id FROM threads WHERE id > ?1 AND id <= ?2 ORDER BY id LIMIT ?3");
    query.setReadBigInts(true);
    const rows = (meta.cursor === null ? query.all(meta.through, limit) : query.all(meta.cursor, meta.through, limit)) as { id: bigint }[];
    const add = db.prepare(`INSERT INTO recent_home_dirty(thread, revision) SELECT ?1, 1 WHERE NOT EXISTS
      (SELECT 1 FROM recent_home_dirty WHERE thread = ?1)`);
    for (const row of rows) add.run(row.id);
    const done = rows.length < limit;
    db.prepare("UPDATE recent_home_meta SET cursor = ?, scan_done = ? WHERE id = 1")
      .run(rows.at(-1)?.id ?? meta.cursor, done ? 1 : 0);
    db.exec("COMMIT");
    return { scanDone: done, visited: rows.length };
  } catch (error) { db.exec("ROLLBACK"); throw error; }
}

/// Account one changed chat using bounded membership batches. The revision prevents changes during a long scan
/// from being lost; writes to the row, count, cursor and marker are committed together.
export function settleRecentHomeChatStep(db: DatabaseSync, limit = 64): { chatsDone: boolean; visited: number } {
  if (!Number.isSafeInteger(limit) || limit < 1) throw new RangeError("recent home chat batch must be positive");
  db.exec("BEGIN IMMEDIATE");
  try {
    const next = db.prepare("SELECT thread, revision FROM recent_home_dirty ORDER BY thread LIMIT 1");
    next.setReadBigInts(true);
    const pending = next.get() as { thread: bigint; revision: bigint } | undefined;
    if (!pending) { db.exec("COMMIT"); return { chatsDone: true, visited: 0 }; }
    const getWork = db.prepare("SELECT revision, after_session, seen FROM recent_home_work WHERE thread = ?");
    getWork.setReadBigInts(true);
    let work = getWork.get(pending.thread) as { revision: bigint; after_session: string | null; seen: bigint } | undefined;
    if (!work || work.revision !== pending.revision) {
      db.prepare(`INSERT INTO recent_home_work(thread, revision, after_session, seen) VALUES (?, ?, NULL, 0)
        ON CONFLICT(thread) DO UPDATE SET revision = excluded.revision, after_session = NULL, seen = 0`)
        .run(pending.thread, pending.revision);
      work = { revision: pending.revision, after_session: null, seen: 0n };
    }
    const batch = recentHomeChatStep(db, pending.thread, { after: work.after_session, seen: work.seen === 1n }, limit);
    if (!batch.done) {
      db.prepare("UPDATE recent_home_work SET after_session = ?, seen = ? WHERE thread = ?")
        .run(batch.cursor.after, batch.cursor.seen ? 1 : 0, pending.thread);
      db.exec("COMMIT");
      return { chatsDone: false, visited: batch.visited };
    }
    const had = db.prepare("SELECT 1 FROM recent_home_rows WHERE thread = ?").get(pending.thread) !== undefined;
    if (batch.included) {
      const current = db.prepare(`SELECT COALESCE(e.at, t.created_at) AS at, COALESCE(e.at, 0) AS said_at, t.created_at
        FROM threads t LEFT JOIN thread_state s ON s.thread = t.id
        LEFT JOIN entries e ON e.thread = t.id AND e.n = s.said_n AND e.kind = 'message' WHERE t.id = ?`);
      current.setReadBigInts(true);
      const row = current.get(pending.thread) as { at: bigint; said_at: bigint; created_at: bigint } | undefined;
      if (!row) throw new Error("recent home chat disappeared inside a write transaction");
      db.prepare(`INSERT INTO recent_home_rows(thread, at, said_at, created_at) VALUES (?, ?, ?, ?)
        ON CONFLICT(thread) DO UPDATE SET at = excluded.at, said_at = excluded.said_at, created_at = excluded.created_at`)
        .run(pending.thread, row.at, row.said_at, row.created_at);
      if (!had) db.prepare("UPDATE recent_home_meta SET total = total + 1 WHERE id = 1").run();
    } else if (had) {
      db.prepare("DELETE FROM recent_home_rows WHERE thread = ?").run(pending.thread);
      db.prepare("UPDATE recent_home_meta SET total = total - 1 WHERE id = 1").run();
    }
    db.prepare("DELETE FROM recent_home_work WHERE thread = ?").run(pending.thread);
    db.prepare("DELETE FROM recent_home_dirty WHERE thread = ? AND revision = ?").run(pending.thread, pending.revision);
    const done = db.prepare("SELECT 1 FROM recent_home_dirty LIMIT 1").get() === undefined;
    db.exec("COMMIT");
    return { chatsDone: done, visited: batch.visited };
  } catch (error) { db.exec("ROLLBACK"); throw error; }
}
