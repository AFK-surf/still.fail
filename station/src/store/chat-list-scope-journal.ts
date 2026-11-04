// A workspace being prepared needs to see session changes that occur behind its scan cursor.
import type { DatabaseSync } from "node:sqlite";

export type RecentScope = { kind: "home" } | { kind: "workspace"; workspace: string };

export function installRecentScopeJournal(db: DatabaseSync): void {
  const installed = () => db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'recent_scope_tracked'").get() !== undefined;
  if (installed()) return;
  db.exec("BEGIN IMMEDIATE");
  try {
    if (!installed()) db.exec(`
      CREATE TABLE recent_scope_tracked (kind INTEGER NOT NULL, ws TEXT NOT NULL, PRIMARY KEY(kind, ws)) WITHOUT ROWID;
      CREATE TABLE recent_scope_session_dirty (kind INTEGER NOT NULL, ws TEXT NOT NULL, session TEXT NOT NULL,
        revision INTEGER NOT NULL, PRIMARY KEY(kind, ws, session)) WITHOUT ROWID;
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
