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

export function installRecentScopeJournal(db: DatabaseSync): void {
  const installed = () => db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'recent_scope_tracked'").get() !== undefined;
  if (installed()) return;
  db.exec("BEGIN IMMEDIATE");
  try {
    if (!installed()) db.exec(`
      CREATE TABLE recent_scope_tracked (kind INTEGER NOT NULL, ws TEXT NOT NULL, total INTEGER NOT NULL DEFAULT 0,
        complete INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(kind, ws)) WITHOUT ROWID;
      CREATE TABLE recent_scope_session_dirty (kind INTEGER NOT NULL, ws TEXT NOT NULL, session TEXT NOT NULL,
        revision INTEGER NOT NULL, PRIMARY KEY(kind, ws, session)) WITHOUT ROWID;
      CREATE TABLE recent_scope_sources (ws TEXT NOT NULL, thread INTEGER NOT NULL, session TEXT NOT NULL,
        PRIMARY KEY(ws, thread, session)) WITHOUT ROWID;
      CREATE INDEX recent_scope_sources_session ON recent_scope_sources(ws, session, thread);
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
