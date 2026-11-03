// A program's chat page is ordered by the last message in each workspace. Build its index only when it is first
// requested; old chat metadata comes across in bounded batches, and later writes mark only affected workspaces.
import type { DatabaseSync } from "node:sqlite";
import type { InWorkspace } from "./rows.ts";

const scope = (ws: string) => `(CASE WHEN ${ws} IS NULL THEN 'H' ELSE 'W' || ${ws} END)`;
const mark = (threads: string) => `
  INSERT INTO outflow_chat_dirty (scope, thread)
    SELECT DISTINCT o.scope, o.thread FROM outflow_chat_order o WHERE o.thread IN (${threads}) AND NOT EXISTS
      (SELECT 1 FROM outflow_chat_dirty d WHERE d.scope = o.scope AND d.thread = o.thread);
  INSERT INTO outflow_chat_dirty (scope, thread)
    SELECT DISTINCT ${scope("s.ws")}, m.thread FROM thread_sessions m JOIN sessions s ON s.key = m.session
    WHERE m.thread IN (${threads}) AND NOT EXISTS
      (SELECT 1 FROM outflow_chat_dirty d WHERE d.scope = ${scope("s.ws")} AND d.thread = m.thread);`;
const sessionThreads = (session: string) => `SELECT thread FROM thread_sessions WHERE session = ${session}`;
const conflictingThreads = `SELECT thread FROM thread_sessions WHERE session IN
  (SELECT key FROM sessions WHERE key = NEW.key OR token = NEW.token)`;

/// No history is read or rewritten here. Triggers also cover an older station writing during handover.
export function installOutflowChatIndex(db: DatabaseSync): void {
  const installed = () => db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'outflow_chat_progress'").get() !== undefined;
  if (installed()) return;
  db.exec("BEGIN IMMEDIATE");
  try {
    if (!installed()) db.exec(`
      CREATE TABLE outflow_chat_order (thread INTEGER NOT NULL, scope TEXT NOT NULL, at INTEGER NOT NULL,
        PRIMARY KEY (thread, scope)) WITHOUT ROWID;
      CREATE INDEX outflow_chat_scope_order ON outflow_chat_order (scope, at DESC, thread DESC);
      CREATE TABLE outflow_chat_dirty (scope TEXT NOT NULL, thread INTEGER NOT NULL, PRIMARY KEY (scope, thread)) WITHOUT ROWID;
      CREATE INDEX outflow_chat_dirty_thread ON outflow_chat_dirty (thread, scope);
      CREATE TABLE outflow_chat_progress (id INTEGER PRIMARY KEY CHECK (id = 1), cursor INTEGER, last INTEGER, done INTEGER NOT NULL);
      INSERT INTO outflow_chat_progress SELECT 1, NULL, MAX(id), MAX(id) IS NULL FROM threads;

      CREATE TRIGGER outflow_thread_add AFTER INSERT ON threads BEGIN ${mark("SELECT NEW.id")} END;
      CREATE TRIGGER outflow_thread_before BEFORE UPDATE OF id, created_at ON threads
        WHEN OLD.id IS NOT NEW.id OR OLD.created_at IS NOT NEW.created_at BEGIN ${mark("SELECT OLD.id")} END;
      CREATE TRIGGER outflow_thread_after AFTER UPDATE OF id, created_at ON threads
        WHEN OLD.id IS NOT NEW.id OR OLD.created_at IS NOT NEW.created_at BEGIN ${mark("SELECT NEW.id")} END;
      CREATE TRIGGER outflow_thread_drop BEFORE DELETE ON threads BEGIN ${mark("SELECT OLD.id")} END;

      CREATE TRIGGER outflow_member_add AFTER INSERT ON thread_sessions BEGIN ${mark("SELECT NEW.thread")} END;
      CREATE TRIGGER outflow_member_before BEFORE UPDATE OF thread, session ON thread_sessions
        WHEN OLD.thread IS NOT NEW.thread OR OLD.session IS NOT NEW.session BEGIN ${mark("SELECT OLD.thread")} END;
      CREATE TRIGGER outflow_member_after AFTER UPDATE OF thread, session ON thread_sessions
        WHEN OLD.thread IS NOT NEW.thread OR OLD.session IS NOT NEW.session BEGIN ${mark("SELECT NEW.thread")} END;
      CREATE TRIGGER outflow_member_drop BEFORE DELETE ON thread_sessions BEGIN ${mark("SELECT OLD.thread")} END;

      -- REPLACE can evict a different key via the unique token without firing DELETE triggers. Mark before it does;
      -- an ignored insert only leaves a harmless pending check, never a premature change to the index.
      CREATE TRIGGER outflow_session_before_add BEFORE INSERT ON sessions BEGIN ${mark(conflictingThreads)} END;
      CREATE TRIGGER outflow_session_add AFTER INSERT ON sessions BEGIN ${mark(sessionThreads("NEW.key"))} END;
      CREATE TRIGGER outflow_session_before BEFORE UPDATE OF key, ws, token ON sessions
        WHEN OLD.key IS NOT NEW.key OR OLD.ws IS NOT NEW.ws OR OLD.token IS NOT NEW.token BEGIN
          ${mark(sessionThreads("OLD.key"))} ${mark(conflictingThreads)}
      END;
      CREATE TRIGGER outflow_session_after AFTER UPDATE OF key, ws, token ON sessions
        WHEN OLD.key IS NOT NEW.key OR OLD.ws IS NOT NEW.ws OR OLD.token IS NOT NEW.token BEGIN ${mark(sessionThreads("NEW.key"))} END;
      CREATE TRIGGER outflow_session_drop BEFORE DELETE ON sessions BEGIN ${mark(sessionThreads("OLD.key"))} END;

      CREATE TRIGGER outflow_said_add AFTER INSERT ON thread_state BEGIN ${mark("SELECT NEW.thread")} END;
      CREATE TRIGGER outflow_said_change AFTER UPDATE OF said_n ON thread_state WHEN OLD.said_n IS NOT NEW.said_n BEGIN ${mark("SELECT NEW.thread")} END;
      CREATE TRIGGER outflow_said_drop BEFORE DELETE ON thread_state BEGIN ${mark("SELECT OLD.thread")} END;
      CREATE TRIGGER outflow_entry_change AFTER UPDATE OF thread, n, at, kind ON entries BEGIN
        ${mark("SELECT OLD.thread")} ${mark("SELECT NEW.thread")}
      END;
      CREATE TRIGGER outflow_entry_drop AFTER DELETE ON entries BEGIN ${mark("SELECT OLD.thread")} END;
    `);
    db.exec("COMMIT");
  } catch (error) { db.exec("ROLLBACK"); throw error; }
}

const lastAt = `MAX(t.created_at, COALESCE((SELECT e.at FROM thread_state st JOIN entries e
  ON e.thread = st.thread AND e.n = st.said_n AND e.kind = 'message' WHERE st.thread = t.id), 0))`;

/// Refresh one thread without rewriting the other workspaces of a shared chat when their order is unchanged.
function refresh(db: DatabaseSync, thread: bigint): void {
  db.prepare(`DELETE FROM outflow_chat_order WHERE thread = ?1 AND
    (NOT EXISTS (SELECT 1 FROM threads t WHERE t.id = ?1) OR NOT EXISTS
      (SELECT 1 FROM thread_sessions m JOIN sessions s ON s.key = m.session WHERE m.thread = ?1 AND ${scope("s.ws")} = outflow_chat_order.scope))`).run(thread);
  db.prepare(`UPDATE outflow_chat_order SET at = (SELECT ${lastAt} FROM threads t WHERE t.id = ?1)
    WHERE thread = ?1 AND at IS NOT (SELECT ${lastAt} FROM threads t WHERE t.id = ?1)`).run(thread);
  db.prepare(`INSERT INTO outflow_chat_order (thread, scope, at)
    SELECT DISTINCT m.thread, ${scope("s.ws")}, ${lastAt} FROM thread_sessions m
      JOIN sessions s ON s.key = m.session JOIN threads t ON t.id = m.thread
    WHERE m.thread = ?1 AND NOT EXISTS (SELECT 1 FROM outflow_chat_order o WHERE o.thread = m.thread AND o.scope = ${scope("s.ws")})`).run(thread);
}

/// One transaction visits at most `limit` old threads or dirty threads of the requested scope.
export function outflowChatIndexStep(db: DatabaseSync, requested: string, limit = 64): { done: boolean; visited: number } {
  if (!Number.isSafeInteger(limit) || limit < 1) throw new RangeError("outflow index batch must be positive");
  db.exec("BEGIN IMMEDIATE");
  try {
    const progress = db.prepare("SELECT cursor, last, done FROM outflow_chat_progress WHERE id = 1");
    progress.setReadBigInts(true);
    const state = progress.get() as { cursor: bigint | null; last: bigint | null; done: bigint };
    let rows: { thread: bigint }[];
    if (state.done === 0n) {
      const query = db.prepare(state.cursor === null
        ? "SELECT id AS thread FROM threads WHERE id <= ?1 ORDER BY id LIMIT ?2"
        : "SELECT id AS thread FROM threads WHERE id > ?3 AND id <= ?1 ORDER BY id LIMIT ?2");
      query.setReadBigInts(true);
      rows = (state.cursor === null ? query.all(state.last, limit) : query.all(state.last, limit, state.cursor)) as { thread: bigint }[];
      for (const row of rows) refresh(db, row.thread);
      db.prepare("UPDATE outflow_chat_progress SET cursor = ?1, done = ?2 WHERE id = 1")
        .run(rows.at(-1)?.thread ?? state.cursor, rows.length < limit ? 1 : 0);
    } else {
      const query = db.prepare("SELECT thread FROM outflow_chat_dirty WHERE scope = ?1 ORDER BY thread LIMIT ?2");
      query.setReadBigInts(true);
      rows = query.all(requested, limit) as { thread: bigint }[];
      // Refresh derives every scope of this thread in the same transaction, so all its markers are settled.
      const remove = db.prepare("DELETE FROM outflow_chat_dirty WHERE thread = ?");
      for (const row of rows) { refresh(db, row.thread); remove.run(row.thread); }
    }
    const done = (db.prepare("SELECT done FROM outflow_chat_progress WHERE id = 1").get() as { done: number }).done === 1
      && db.prepare("SELECT 1 FROM outflow_chat_dirty WHERE scope = ? LIMIT 1").get(requested) === undefined;
    db.exec("COMMIT");
    return { done, visited: rows.length };
  } catch (error) { db.exec("ROLLBACK"); throw error; }
}

export const outflowChatScopes = (viewer: InWorkspace) => viewer.home === false ? ["W" + viewer.workspace] : ["H", "W" + viewer.workspace];
export function outflowChatIndexReady(db: DatabaseSync, viewer: InWorkspace): boolean {
  if (db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'outflow_chat_progress'").get() === undefined) return false;
  if ((db.prepare("SELECT done FROM outflow_chat_progress WHERE id = 1").get() as { done: number }).done !== 1) return false;
  const pending = db.prepare("SELECT 1 FROM outflow_chat_dirty WHERE scope = ? LIMIT 1");
  return outflowChatScopes(viewer).every((scope) => pending.get(scope) === undefined);
}
