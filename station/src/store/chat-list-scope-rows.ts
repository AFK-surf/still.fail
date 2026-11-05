// Incremental contributions to a prepared explicit workspace. These primitives do not yet account for membership
// or thread changes by themselves; a builder must keep the scope pending until all such changes have been settled.
import type { DatabaseSync } from "node:sqlite";
import type { RecentChatPage } from "./chat-list-index.ts";

type Current = { at: bigint; said_at: bigint; created_at: bigint };

// A small number of undistributed order changes can be checked against this workspace without waiting for other
// workspaces. Cap the input before probing; above the cap, wait rather than reading an unbounded number of jobs.
export const RECENT_SCOPE_ORDER_PENDING = `SELECT COUNT(*) AS n,
  MAX(EXISTS (SELECT 1 FROM recent_scope_rows r WHERE r.ws = ?1 AND r.thread = d.thread)) AS affects
  FROM (SELECT thread FROM recent_scope_order_dispatch ORDER BY thread LIMIT 65) d`;

function atomic<T>(db: DatabaseSync, f: () => T): T {
  db.exec("SAVEPOINT recent_scope_contribution");
  try { const result = f(); db.exec("RELEASE recent_scope_contribution"); return result; }
  catch (error) { db.exec("ROLLBACK TO recent_scope_contribution; RELEASE recent_scope_contribution"); throw error; }
}

/// Add or refresh one session's contribution. Multiple sessions in the same workspace count the chat only once.
export function putRecentScopeSource(db: DatabaseSync, ws: string, thread: bigint, session: string): boolean {
  return atomic(db, () => {
    if (db.prepare("SELECT 1 FROM recent_scope_tracked WHERE kind = 1 AND ws = ?").get(ws) === undefined)
      throw new Error("recent scope is not tracked");
    const current = db.prepare(`SELECT COALESCE(e.at, t.created_at) AS at, COALESCE(e.at, 0) AS said_at, t.created_at
      FROM threads t LEFT JOIN thread_state s ON s.thread = t.id
      LEFT JOIN entries e ON e.thread = t.id AND e.n = s.said_n AND e.kind = 'message' WHERE t.id = ?`);
    current.setReadBigInts(true);
    const row = current.get(thread) as Current | undefined;
    if (row === undefined) return false;
    const had = db.prepare("SELECT 1 FROM recent_scope_rows WHERE ws = ? AND thread = ?").get(ws, thread) !== undefined;
    db.prepare(`INSERT INTO recent_scope_sources(ws, thread, session) SELECT ?1, ?2, ?3
      WHERE NOT EXISTS (SELECT 1 FROM recent_scope_sources WHERE ws = ?1 AND thread = ?2 AND session = ?3)`).run(ws, thread, session);
    db.prepare(`INSERT INTO recent_scope_rows(ws, thread, at, said_at, created_at) VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(ws, thread) DO UPDATE SET at = excluded.at, said_at = excluded.said_at, created_at = excluded.created_at
      WHERE at IS NOT excluded.at OR said_at IS NOT excluded.said_at OR created_at IS NOT excluded.created_at`)
      .run(ws, thread, row.at, row.said_at, row.created_at);
    if (!had) db.prepare("UPDATE recent_scope_tracked SET total = total + 1 WHERE kind = 1 AND ws = ?").run(ws);
    return true;
  });
}

/// Remove just one source; the chat remains until its final source in this workspace is gone.
export function removeRecentScopeSource(db: DatabaseSync, ws: string, thread: bigint, session: string): void {
  atomic(db, () => {
    const removed = db.prepare("DELETE FROM recent_scope_sources WHERE ws = ? AND thread = ? AND session = ?").run(ws, thread, session).changes;
    if (removed === 0 || db.prepare("SELECT 1 FROM recent_scope_sources WHERE ws = ? AND thread = ? LIMIT 1").get(ws, thread) !== undefined) return;
    if (db.prepare("DELETE FROM recent_scope_rows WHERE ws = ? AND thread = ?").run(ws, thread).changes !== 0)
      db.prepare("UPDATE recent_scope_tracked SET total = total - 1 WHERE kind = 1 AND ws = ?").run(ws);
  });
}

/// Only a builder that has checked all change journals may mark a scope complete. This is not connected to a reader.
export function readPreparedRecentWorkspace(db: DatabaseSync, ws: string, limit: number): RecentChatPage | null {
  if (limit === 0) return { ids: [], total: 0 };
  db.exec("SAVEPOINT recent_scope_page");
  try {
    const meta = db.prepare("SELECT total, complete FROM recent_scope_tracked WHERE kind = 1 AND ws = ?").get(ws) as
      { total: number; complete: number } | undefined;
    if (!meta || meta.complete !== 1 || db.prepare("SELECT 1 FROM recent_scope_session_dirty WHERE kind = 1 AND ws = ? LIMIT 1").get(ws) !== undefined ||
        db.prepare("SELECT 1 FROM recent_scope_member_dirty WHERE ws = ? LIMIT 1").get(ws) !== undefined ||
        db.prepare("SELECT 1 FROM recent_scope_order_dirty WHERE ws = ? LIMIT 1").get(ws) !== undefined ||
        db.prepare("SELECT 1 FROM recent_scope_visibility_dirty LIMIT 1").get() !== undefined)
      return null;
    const pending = db.prepare(RECENT_SCOPE_ORDER_PENDING).get(ws) as { n: number; affects: number | null };
    if (pending.n > 64 || pending.affects === 1) return null;
    const rows = db.prepare(`SELECT thread FROM recent_scope_rows INDEXED BY recent_scope_order WHERE ws = ?
      ORDER BY at DESC, said_at DESC, created_at DESC, thread DESC LIMIT ?`).all(ws, limit) as { thread: number }[];
    return { ids: rows.map((row) => row.thread), total: meta.total };
  } finally { db.exec("RELEASE recent_scope_page"); }
}
