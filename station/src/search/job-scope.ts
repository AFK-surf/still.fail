import type { DatabaseSync } from "node:sqlite";
import type { Asker } from "./match.ts";

// Small workspaces can use the already-maintained session list without scanning other workspaces' jobs. Limit the
// session side before checking for jobs: a workspace with many sessions but few jobs should keep the original path.
const LIMIT = 64;
const ascii = (value: unknown): value is string => typeof value === "string" && /^[\x20-\x7e]*$/.test(value);
export const JOB_SCOPE_SESSIONS = `SELECT session, instr(session, char(0)) AS nul FROM session_list_rows WHERE kind = ? AND ws = ?
  ORDER BY archived, connect, session LIMIT ?`;
// Some Node SQLite versions read text only up to its first NUL. Include those workspace values whose visible prefix is
// the asked workspace, so JavaScript visibility makes the final decision on the same values as before.
export const JOB_SCOPE_NUL_WORKSPACES = `SELECT session, instr(session, char(0)) AS nul FROM session_list_rows
  WHERE kind = 1 AND ws >= (?1 || char(0)) AND ws < (?1 || char(1)) ORDER BY ws, archived, connect, session LIMIT ?2`;

/// Null means use the original jobs-by-session walk. Read the index's completeness and its rows from one snapshot.
export function smallJobScope(db: DatabaseSync, asker: Asker, end: unknown, onPending?: () => void): string[] | null {
  if (!ascii(asker.workspace) || !ascii(end)) return null;
  db.exec("SAVEPOINT search_job_scope");
  try {
    if (db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'session_list_meta'").get() === undefined) return null;
    const meta = db.prepare("SELECT version, complete FROM session_list_meta WHERE id = 1").get() as
      { version: number; complete: number } | undefined;
    if (!meta || meta.version !== 1) return null;
    if (meta.complete !== 1) { onPending?.(); return null; }
    const scopes: [number, string][] = [[1, asker.workspace]];
    if (asker.workspace !== "*") scopes.push([1, "*"]);
    if (asker.home) scopes.push([0, ""]);
    const query = db.prepare(JOB_SCOPE_SESSIONS), nulWorkspaces = db.prepare(JOB_SCOPE_NUL_WORKSPACES), keys = new Set<string>();
    let read = 0;
    const take = (rows: { session: unknown; nul: number }[]): boolean => {
      read += rows.length;
      if (read > LIMIT) return false;
      for (const row of rows) {
        if (!ascii(row.session) || row.nul !== 0) return false;
        keys.add(row.session);
      }
      return true;
    };
    for (const [kind, ws] of scopes) {
      if (!take(query.all(kind, ws, LIMIT + 1 - read) as { session: unknown; nul: number }[])) return null;
      if (kind === 1 && !take(nulWorkspaces.all(ws, LIMIT + 1 - read) as { session: unknown; nul: number }[])) return null;
    }
    // Large or unusual scopes cannot use the shortcut even after the audit; do not start that work for them alone.
    if (db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'search_job_session_audit'").get() === undefined) {
      onPending?.(); return null;
    }
    const audit = db.prepare("SELECT version, complete FROM search_job_session_audit WHERE id = 1").get() as
      { version: number; complete: number } | undefined;
    if (!audit || audit.version !== 1) return null;
    if (audit.complete !== 1) { onPending?.(); return null; }
    return [...keys].filter((key) => key <= end).sort();
  } finally { db.exec("RELEASE search_job_scope"); }
}
