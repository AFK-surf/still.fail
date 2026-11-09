import type { DatabaseSync, StatementSync } from "node:sqlite";
import type { Asker } from "./match.ts";

// Each source is ordered by thread and bounded before merging. Duplicates can arise from a shared chat; filtering
// them before the final limit preserves the original thread order for equal-time search results.
export const SEARCH_SCOPE_FIRST = `SELECT thread FROM search_scope_threads WHERE kind = ?1 AND ws = ?2 AND thread <= ?3
  ORDER BY thread LIMIT ?4`;
export const SEARCH_SCOPE_NEXT = `SELECT thread FROM search_scope_threads WHERE kind = ?1 AND ws = ?2 AND thread > ?3 AND thread <= ?4
  ORDER BY thread LIMIT ?5`;
export const SEARCH_ORPHAN_FIRST = "SELECT thread FROM search_scope_orphans WHERE thread <= ?1 ORDER BY thread LIMIT ?2";
export const SEARCH_ORPHAN_NEXT = "SELECT thread FROM search_scope_orphans WHERE thread > ?1 AND thread <= ?2 ORDER BY thread LIMIT ?3";

type Queries = { meta: StatementSync; first: StatementSync; next: StatementSync; firstOrphan: StatementSync; nextOrphan: StatementSync };
const queries = new WeakMap<DatabaseSync, Queries>();

function scopeQueries(db: DatabaseSync): Queries | null {
  const saved = queries.get(db);
  if (saved) return saved;
  // A negative lookup is not cached: the background writer may install the index before the next page.
  if (db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'search_scope_meta'").get() === undefined) return null;
  const version = db.prepare("SELECT version FROM search_scope_meta WHERE id = 1").get() as { version: number } | undefined;
  if (version?.version !== 1) return null;
  const result = {
    meta: db.prepare(`SELECT version, threads_done, members_done,
      EXISTS (SELECT 1 FROM search_scope_sessions_dirty LIMIT 1) OR EXISTS (SELECT 1 FROM search_scope_members_dirty LIMIT 1)
        OR EXISTS (SELECT 1 FROM search_scope_threads_dirty LIMIT 1) AS dirty FROM search_scope_meta WHERE id = 1`),
    first: db.prepare(SEARCH_SCOPE_FIRST), next: db.prepare(SEARCH_SCOPE_NEXT),
    firstOrphan: db.prepare(SEARCH_ORPHAN_FIRST), nextOrphan: db.prepare(SEARCH_ORPHAN_NEXT),
  };
  queries.set(db, result);
  return result;
}

/// Null means the index is absent or being prepared: continue with the original bounded walk of all threads.
/// Readiness and candidates share a short snapshot; no transaction is held while a search yields or reads messages.
export function readSearchScopePage(db: DatabaseSync, asker: Asker, after: number | null, end: number, limit: number): number[] | null {
  db.exec("SAVEPOINT search_scope_page");
  try {
    const prepared = scopeQueries(db);
    if (!prepared) return null;
    const meta = prepared.meta.get() as { version: number; threads_done: number; members_done: number; dirty: number } | undefined;
    if (!meta || meta.version !== 1 || meta.threads_done !== 1 || meta.members_done !== 1 || meta.dirty === 1) return null;
    const scopes: [number, string][] = [[1, asker.workspace], [2, ""]];
    if (asker.workspace !== "*") scopes.push([1, "*"]);
    if (asker.home) scopes.push([0, ""]);
    const candidates: number[] = [];
    for (const [kind, ws] of scopes) {
      const query = after === null ? prepared.first : prepared.next;
      const rows = (after === null ? query.all(kind, ws, end, limit) : query.all(kind, ws, after, end, limit)) as { thread: number }[];
      candidates.push(...rows.map((row) => row.thread));
    }
    if (asker.home) {
      const query = after === null ? prepared.firstOrphan : prepared.nextOrphan;
      const rows = (after === null ? query.all(end, limit) : query.all(after, end, limit)) as { thread: number }[];
      candidates.push(...rows.map((row) => row.thread));
    }
    return [...new Set(candidates)].sort((a, b) => a - b).slice(0, limit);
  } finally { db.exec("RELEASE search_scope_page"); }
}
