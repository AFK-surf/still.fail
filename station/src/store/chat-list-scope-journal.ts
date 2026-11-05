// A workspace being prepared needs to see session changes that occur behind its scan cursor.
import type { DatabaseSync } from "node:sqlite";

export type RecentScope = { kind: "home" } | { kind: "workspace"; workspace: string };

// Do not use INSERT OR IGNORE: an outer old writer's INSERT OR REPLACE can override it inside a trigger. The
// existence check coalesces work without discarding the revision a builder uses to notice an interleaved change.
const markSession = (key: string, workspace: string, homeWhen = "1") => {
  const refs = `((${homeWhen}) AND (EXISTS (SELECT 1 FROM thread_sessions INDEXED BY thread_sessions_session WHERE session = ${key} LIMIT 1)
    OR EXISTS (SELECT 1 FROM threads INDEXED BY threads_home WHERE home = ${key} LIMIT 1)))`;
  return `
    UPDATE recent_scope_session_dirty SET revision = revision + 1 WHERE kind = 1 AND ws = ${workspace} AND session = ${key};
    INSERT INTO recent_scope_session_dirty(kind, ws, session, revision)
      SELECT 1, ${workspace}, ${key}, 1 WHERE ${key} IS NOT NULL AND ${workspace} IS NOT NULL
        AND EXISTS (SELECT 1 FROM recent_scope_tracked WHERE kind = 1 AND ws = ${workspace})
        AND NOT EXISTS (SELECT 1 FROM recent_scope_session_dirty WHERE kind = 1 AND ws = ${workspace} AND session = ${key});
    UPDATE recent_scope_session_dirty SET revision = revision + 1 WHERE kind = 0 AND ws = '' AND session = ${key} AND ${refs};
    INSERT INTO recent_scope_session_dirty(kind, ws, session, revision)
      SELECT 0, '', ${key}, 1 WHERE ${key} IS NOT NULL AND ${refs}
        AND EXISTS (SELECT 1 FROM recent_scope_tracked WHERE kind = 0 AND ws = '')
        AND NOT EXISTS (SELECT 1 FROM recent_scope_session_dirty WHERE kind = 0 AND ws = '' AND session = ${key});`;
};
const keyConflict = (extra: string) => `(SELECT key FROM sessions WHERE key = NEW.key ${extra})`;
const keyConflictWs = (extra: string) => `(SELECT ws FROM sessions WHERE key = NEW.key ${extra})`;
const tokenConflict = (extra: string) => `(SELECT key FROM sessions WHERE token = NEW.token ${extra})`;
const tokenConflictWs = (extra: string) => `(SELECT ws FROM sessions WHERE token = NEW.token ${extra})`;
const changesHome = `OLD.key IS NOT NEW.key OR (OLD.ws IS NULL AND NEW.ws IS NOT NULL)
  OR (OLD.ws IS NOT NULL AND NEW.ws IS NULL)`;
const markMember = (thread: string, session: string) => {
  const ws = `(SELECT ws FROM sessions WHERE key = ${session})`;
  const relevant = `(EXISTS (SELECT 1 FROM threads WHERE id = ${thread} AND home IS NULL)
    OR EXISTS (SELECT 1 FROM recent_scope_visibility_dirty WHERE thread = ${thread}))`;
  return `
    UPDATE recent_scope_member_dirty SET revision = revision + 1
      WHERE ws = ${ws} AND thread = ${thread} AND session = ${session} AND ${relevant};
    INSERT INTO recent_scope_member_dirty(ws, thread, session, revision)
      SELECT ${ws}, ${thread}, ${session}, 1 WHERE ${ws} IS NOT NULL AND ${thread} IS NOT NULL AND ${session} IS NOT NULL
        AND ${relevant} AND EXISTS (SELECT 1 FROM recent_scope_tracked WHERE kind = 1 AND ws = ${ws})
        AND NOT EXISTS (SELECT 1 FROM recent_scope_member_dirty WHERE ws = ${ws} AND thread = ${thread} AND session = ${session});`;
};
const memberConflictThread = (extra: string) => `(SELECT thread FROM thread_sessions WHERE rowid = NEW.rowid ${extra})`;
const memberConflictSession = (extra: string) => `(SELECT session FROM thread_sessions WHERE rowid = NEW.rowid ${extra})`;
// A home-less chat with members may affect scopes without an existing row. Record that uncertainty; a named home
// and an orphan can instead be checked against a workspace without blocking unrelated pages.
const markVisibility = (thread: string) => {
  const home = `(SELECT s.ws FROM threads t JOIN sessions s ON s.key = t.home WHERE t.id = ${thread})`;
  const ambiguous = `EXISTS (SELECT 1 FROM threads t WHERE t.id = ${thread} AND t.home IS NULL
    AND EXISTS (SELECT 1 FROM thread_sessions m WHERE m.thread = t.id LIMIT 1))`;
  return `
    UPDATE recent_scope_visibility_dirty SET revision = revision + 1, home_ws = ${home}, ambiguous = ${ambiguous} WHERE thread = ${thread};
    INSERT INTO recent_scope_visibility_dirty(thread, revision, home_ws, ambiguous)
      SELECT ${thread}, 1, ${home}, ${ambiguous} WHERE ${thread} IS NOT NULL AND EXISTS (SELECT 1 FROM recent_scope_tracked LIMIT 1)
        AND NOT EXISTS (SELECT 1 FROM recent_scope_visibility_dirty WHERE thread = ${thread});`;
};
// A member can arrive after a job recorded an orphan. Preserve uncertainty until that job has rebuilt its sources.
const memberMakesVisibilityAmbiguous = (thread: string) => `UPDATE recent_scope_visibility_dirty SET ambiguous = 1
  WHERE thread = ${thread} AND EXISTS (SELECT 1 FROM threads WHERE id = ${thread} AND home IS NULL);`;
// Most chats belong to a few workspaces. For a highly shared chat, defer distributing the change so a single write
// cannot walk an arbitrary number of workspaces; readers wait while that distribution is incomplete.
const markOrder = (thread: string) => {
  const many = `EXISTS (SELECT 1 FROM recent_scope_rows INDEXED BY recent_scope_rows_thread WHERE thread = ${thread} LIMIT 1 OFFSET 64)`;
  return `
    INSERT INTO recent_scope_order_dirty(ws, thread)
      SELECT r.ws, r.thread FROM (SELECT ws, thread FROM recent_scope_rows INDEXED BY recent_scope_rows_thread
        WHERE thread = ${thread} ORDER BY ws LIMIT 64) r
      WHERE NOT (${many}) AND NOT EXISTS
        (SELECT 1 FROM recent_scope_order_dirty d WHERE d.ws = r.ws AND d.thread = r.thread);
    INSERT INTO recent_scope_order_dispatch(thread, after_ws)
      SELECT ${thread}, NULL WHERE ${thread} IS NOT NULL AND (${many}) AND NOT EXISTS
        (SELECT 1 FROM recent_scope_order_dispatch WHERE thread = ${thread});`;
};
const insertedSaid = `EXISTS (SELECT 1 FROM thread_state s WHERE s.thread = NEW.thread AND
  (s.said_n = NEW.n OR (NEW.ts IS NOT NULL AND EXISTS (SELECT 1 FROM entries e WHERE e.thread = s.thread
    AND e.n = s.said_n AND e.kind = 'message' AND e.ts = NEW.ts))))`;
const displacedSaid = `EXISTS (SELECT 1 FROM thread_state s JOIN entries e ON e.thread = s.thread AND e.n = s.said_n AND e.kind = 'message'
  WHERE s.thread = NEW.thread AND (e.n = NEW.n OR (NEW.ts IS NOT NULL AND e.ts = NEW.ts))
    AND (e.thread IS NOT OLD.thread OR e.n IS NOT OLD.n))`;
const displacedThread = `(SELECT t.id FROM threads t WHERE t.surface = NEW.surface AND t.channel = NEW.channel
  AND t.thread_ts = NEW.thread_ts AND t.id IS NOT NEW.id)`;

export function installRecentScopeJournal(db: DatabaseSync): void {
  const installed = () => db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'recent_scope_tracked'").get() !== undefined;
  if (installed()) return;
  db.exec("BEGIN IMMEDIATE");
  try {
    if (!installed()) db.exec(`
      CREATE TABLE recent_scope_tracked (kind INTEGER NOT NULL, ws TEXT NOT NULL, total INTEGER NOT NULL DEFAULT 0,
        complete INTEGER NOT NULL DEFAULT 0, scan_connect TEXT, scan_after INTEGER, scan_done INTEGER NOT NULL DEFAULT 0,
        scan_session TEXT, scan_phase TEXT, scan_thread_after INTEGER, PRIMARY KEY(kind, ws)) WITHOUT ROWID;
      CREATE TABLE recent_scope_session_dirty (kind INTEGER NOT NULL, ws TEXT NOT NULL, session TEXT NOT NULL,
        revision INTEGER NOT NULL, PRIMARY KEY(kind, ws, session)) WITHOUT ROWID;
      CREATE TABLE recent_scope_session_work (ws TEXT NOT NULL, session TEXT NOT NULL, revision INTEGER NOT NULL,
        phase TEXT NOT NULL, after INTEGER, PRIMARY KEY(ws, session)) WITHOUT ROWID;
      CREATE TABLE recent_scope_member_dirty (ws TEXT NOT NULL, thread INTEGER NOT NULL, session TEXT NOT NULL,
        revision INTEGER NOT NULL, PRIMARY KEY(ws, thread, session)) WITHOUT ROWID;
      CREATE TABLE recent_scope_order_dirty (ws TEXT NOT NULL, thread INTEGER NOT NULL, PRIMARY KEY(ws, thread)) WITHOUT ROWID;
      CREATE TABLE recent_scope_order_dispatch (thread INTEGER PRIMARY KEY, after_ws TEXT);
      CREATE TABLE recent_scope_visibility_dirty (thread INTEGER PRIMARY KEY, revision INTEGER NOT NULL,
        home_ws TEXT, ambiguous INTEGER NOT NULL);
      CREATE TABLE recent_scope_visibility_work (thread INTEGER PRIMARY KEY, revision INTEGER NOT NULL,
        phase TEXT NOT NULL, after_ws TEXT, after_session TEXT);
      CREATE TABLE recent_scope_visibility_turn (id INTEGER PRIMARY KEY CHECK (id = 1), after_thread INTEGER, through_thread INTEGER);
      INSERT INTO recent_scope_visibility_turn VALUES (1, NULL, NULL);
      CREATE TABLE recent_scope_sources (ws TEXT NOT NULL, thread INTEGER NOT NULL, session TEXT NOT NULL,
        PRIMARY KEY(ws, thread, session)) WITHOUT ROWID;
      CREATE INDEX recent_scope_sources_session ON recent_scope_sources(ws, session, thread);
      CREATE INDEX recent_scope_sources_thread ON recent_scope_sources(thread, ws, session);
      CREATE TABLE recent_scope_rows (ws TEXT NOT NULL, thread INTEGER NOT NULL, at INTEGER NOT NULL,
        said_at INTEGER NOT NULL, created_at INTEGER NOT NULL, PRIMARY KEY(ws, thread)) WITHOUT ROWID;
      CREATE INDEX recent_scope_order ON recent_scope_rows(ws, at DESC, said_at DESC, created_at DESC, thread DESC);
      CREATE INDEX recent_scope_rows_thread ON recent_scope_rows(thread, ws);
      -- REPLACE can remove another session without a DELETE trigger, whether it conflicts by key or token.
      CREATE TRIGGER recent_scope_session_before_add BEFORE INSERT ON sessions BEGIN
        ${markSession(keyConflict(""), keyConflictWs(""))}
        ${markSession(tokenConflict(""), tokenConflictWs(""))}
      END;
      CREATE TRIGGER recent_scope_session_add AFTER INSERT ON sessions BEGIN ${markSession("NEW.key", "NEW.ws")} END;
      CREATE TRIGGER recent_scope_session_before_change BEFORE UPDATE OF key, ws, token ON sessions
        WHEN OLD.key IS NOT NEW.key OR OLD.ws IS NOT NEW.ws OR OLD.token IS NOT NEW.token BEGIN
          ${markSession("OLD.key", "OLD.ws", changesHome)}
          ${markSession(keyConflict("AND key IS NOT OLD.key"), keyConflictWs("AND key IS NOT OLD.key"))}
          ${markSession(tokenConflict("AND key IS NOT OLD.key"), tokenConflictWs("AND key IS NOT OLD.key"))}
      END;
      CREATE TRIGGER recent_scope_session_change AFTER UPDATE OF key, ws, token ON sessions
        WHEN OLD.key IS NOT NEW.key OR OLD.ws IS NOT NEW.ws OR OLD.token IS NOT NEW.token BEGIN ${markSession("NEW.key", "NEW.ws", changesHome)} END;
      CREATE TRIGGER recent_scope_session_drop BEFORE DELETE ON sessions BEGIN ${markSession("OLD.key", "OLD.ws")} END;
      -- A rowid REPLACE can evict a different membership without firing its DELETE trigger.
      CREATE TRIGGER recent_scope_member_before_add BEFORE INSERT ON thread_sessions BEGIN
        ${markMember(memberConflictThread(""), memberConflictSession(""))}
      END;
      CREATE TRIGGER recent_scope_member_add AFTER INSERT ON thread_sessions BEGIN
        ${markMember("NEW.thread", "NEW.session")} ${memberMakesVisibilityAmbiguous("NEW.thread")}
      END;
      CREATE TRIGGER recent_scope_member_before_change BEFORE UPDATE OF thread, session, rowid ON thread_sessions
        WHEN OLD.thread IS NOT NEW.thread OR OLD.session IS NOT NEW.session OR OLD.rowid IS NOT NEW.rowid BEGIN
          ${markMember("OLD.thread", "OLD.session")}
          ${markMember(memberConflictThread("AND rowid IS NOT OLD.rowid"), memberConflictSession("AND rowid IS NOT OLD.rowid"))}
      END;
      CREATE TRIGGER recent_scope_member_change AFTER UPDATE OF thread, session, rowid ON thread_sessions
        WHEN OLD.thread IS NOT NEW.thread OR OLD.session IS NOT NEW.session OR OLD.rowid IS NOT NEW.rowid BEGIN
          ${markMember("NEW.thread", "NEW.session")}
          ${memberMakesVisibilityAmbiguous("NEW.thread")}
      END;
      CREATE TRIGGER recent_scope_member_drop BEFORE DELETE ON thread_sessions BEGIN ${markMember("OLD.thread", "OLD.session")} END;
      -- Rows inserted behind a running distributor's cursor must also be marked. Existing dirty rows remain
      -- pending until this thread's distribution finishes, so another message need not restart the scan.
      CREATE TRIGGER recent_scope_order_row_add AFTER INSERT ON recent_scope_rows
        WHEN EXISTS (SELECT 1 FROM recent_scope_order_dispatch WHERE thread = NEW.thread) BEGIN
        INSERT INTO recent_scope_order_dirty(ws, thread) SELECT NEW.ws, NEW.thread WHERE NOT EXISTS
          (SELECT 1 FROM recent_scope_order_dirty WHERE ws = NEW.ws AND thread = NEW.thread);
      END;
      CREATE TRIGGER recent_scope_order_thread_before_add BEFORE INSERT ON threads BEGIN
        ${markOrder("NEW.id")} ${markOrder(displacedThread)}
        ${markVisibility("(SELECT id FROM threads WHERE id = NEW.id)")} ${markVisibility(displacedThread)}
      END;
      CREATE TRIGGER recent_scope_order_thread_before_change BEFORE UPDATE OF id, surface, channel, thread_ts ON threads BEGIN
        ${markOrder(displacedThread)}
        ${markVisibility(displacedThread)}
      END;
      CREATE TRIGGER recent_scope_order_thread_add AFTER INSERT ON threads BEGIN ${markOrder("NEW.id")} ${markVisibility("NEW.id")} END;
      CREATE TRIGGER recent_scope_order_thread_change AFTER UPDATE OF id, created_at ON threads BEGIN ${markOrder("OLD.id")} END;
      CREATE TRIGGER recent_scope_order_thread_move AFTER UPDATE OF id ON threads WHEN OLD.id IS NOT NEW.id BEGIN ${markOrder("NEW.id")} END;
      CREATE TRIGGER recent_scope_visibility_thread_change AFTER UPDATE OF id, home ON threads
        WHEN OLD.id IS NOT NEW.id OR OLD.home IS NOT NEW.home BEGIN ${markVisibility("OLD.id")} END;
      CREATE TRIGGER recent_scope_visibility_thread_move AFTER UPDATE OF id ON threads
        WHEN OLD.id IS NOT NEW.id BEGIN ${markVisibility("NEW.id")} END;
      CREATE TRIGGER recent_scope_order_thread_drop AFTER DELETE ON threads BEGIN ${markOrder("OLD.id")} ${markVisibility("OLD.id")} END;
      CREATE TRIGGER recent_scope_order_state_add AFTER INSERT ON thread_state BEGIN ${markOrder("NEW.thread")} END;
      CREATE TRIGGER recent_scope_order_state_change AFTER UPDATE OF thread, said_n ON thread_state
        WHEN OLD.thread IS NOT NEW.thread OR OLD.said_n IS NOT NEW.said_n BEGIN ${markOrder("OLD.thread")} END;
      CREATE TRIGGER recent_scope_order_state_move AFTER UPDATE OF thread ON thread_state
        WHEN OLD.thread IS NOT NEW.thread BEGIN ${markOrder("NEW.thread")} END;
      CREATE TRIGGER recent_scope_order_state_drop AFTER DELETE ON thread_state WHEN OLD.said_n IS NOT NULL BEGIN ${markOrder("OLD.thread")} END;
      CREATE TRIGGER recent_scope_order_entry_before_add BEFORE INSERT ON entries WHEN ${insertedSaid} BEGIN ${markOrder("NEW.thread")} END;
      CREATE TRIGGER recent_scope_order_entry_before_change BEFORE UPDATE OF thread, n, ts ON entries
        WHEN ${displacedSaid} BEGIN ${markOrder("NEW.thread")} END;
      CREATE TRIGGER recent_scope_order_entry_change AFTER UPDATE OF thread, n, kind, at ON entries BEGIN ${markOrder("OLD.thread")} END;
      CREATE TRIGGER recent_scope_order_entry_move AFTER UPDATE OF thread ON entries WHEN OLD.thread IS NOT NEW.thread BEGIN ${markOrder("NEW.thread")} END;
      CREATE TRIGGER recent_scope_order_entry_drop AFTER DELETE ON entries BEGIN ${markOrder("OLD.thread")} END;
    `);
    db.exec("COMMIT");
  } catch (error) { db.exec("ROLLBACK"); throw error; }
}

/// The caller starts a scope and its scan in the same transaction. Unrequested workspaces need no journal entries.
export function trackRecentScope(db: DatabaseSync, scope: RecentScope): void {
  const kind = scope.kind === "home" ? 0 : 1;
  const ws = scope.kind === "home" ? "" : scope.workspace;
  db.prepare(`INSERT INTO recent_scope_tracked(kind, ws) SELECT ?1, ?2
    WHERE NOT EXISTS (SELECT 1 FROM recent_scope_tracked WHERE kind = ?1 AND ws = ?2)`).run(kind, ws);
}

/// A builder may clear only the revision it actually accounted. An older writer changing the session between
/// batches increments the revision, leaving it pending for another pass.
export function acknowledgeRecentScopeSession(db: DatabaseSync, scope: RecentScope, session: string, revision: number | bigint): boolean {
  const kind = scope.kind === "home" ? 0 : 1;
  const ws = scope.kind === "home" ? "" : scope.workspace;
  return db.prepare("DELETE FROM recent_scope_session_dirty WHERE kind = ? AND ws = ? AND session = ? AND revision = ?")
    .run(kind, ws, session, revision).changes === 1;
}
