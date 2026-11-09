// Bounded distribution and reconciliation for changes to a chat's ordering. Other visibility journals must also
// be settled before a workspace can be exposed.
import type { DatabaseSync } from "node:sqlite";
import { removeRecentScopeSource } from "./chat-list-scope-rows.ts";

/// Move one highly shared chat's change to its workspaces. Already marked workspaces stay pending until this chat's
/// dispatch is complete, so repeated messages do not force the cursor back to the beginning.
export function dispatchRecentScopeOrderStep(db: DatabaseSync, limit = 64): { dispatchDone: boolean; visited: number } {
  if (!Number.isSafeInteger(limit) || limit < 1) throw new RangeError("recent scope dispatch batch must be positive");
  db.exec("BEGIN IMMEDIATE");
  try {
    // A finite round gives other chats a turn even if an earlier one is updated again immediately after dispatch.
    // The boundary and turn commit with each batch, including across rollback and worker restarts.
    const turn = db.prepare("SELECT after_thread, through_thread FROM recent_scope_order_turn WHERE id = 1");
    turn.setReadBigInts(true);
    const progress = turn.get() as { after_thread: bigint | null; through_thread: bigint | null };
    let through = progress.through_thread;
    let pending: { thread: bigint; after_ws: string | null } | undefined;
    if (through !== null) {
      const next = db.prepare(progress.after_thread === null
        ? "SELECT thread, after_ws FROM recent_scope_order_dispatch WHERE thread <= ? ORDER BY thread LIMIT 1"
        : "SELECT thread, after_ws FROM recent_scope_order_dispatch WHERE thread > ? AND thread <= ? ORDER BY thread LIMIT 1");
      next.setReadBigInts(true);
      pending = (progress.after_thread === null ? next.get(through) : next.get(progress.after_thread, through)) as typeof pending;
    }
    if (!pending) {
      const last = db.prepare("SELECT MAX(thread) AS thread FROM recent_scope_order_dispatch");
      last.setReadBigInts(true);
      through = (last.get() as { thread: bigint | null }).thread;
      if (through === null) { db.exec("COMMIT"); return { dispatchDone: true, visited: 0 }; }
      const first = db.prepare("SELECT thread, after_ws FROM recent_scope_order_dispatch WHERE thread <= ? ORDER BY thread LIMIT 1");
      first.setReadBigInts(true);
      pending = first.get(through) as { thread: bigint; after_ws: string | null };
    }
    db.prepare("UPDATE recent_scope_order_turn SET after_thread = ?, through_thread = ? WHERE id = 1").run(pending.thread, through);
    const query = db.prepare(pending.after_ws === null
      ? "SELECT ws FROM recent_scope_rows INDEXED BY recent_scope_rows_thread WHERE thread = ?1 ORDER BY ws LIMIT ?2"
      : "SELECT ws FROM recent_scope_rows INDEXED BY recent_scope_rows_thread WHERE thread = ?1 AND ws > ?2 ORDER BY ws LIMIT ?3");
    const rows = (pending.after_ws === null ? query.all(pending.thread, limit) : query.all(pending.thread, pending.after_ws, limit)) as { ws: string }[];
    const mark = db.prepare(`INSERT INTO recent_scope_order_dirty(ws, thread) SELECT ?1, ?2 WHERE NOT EXISTS
      (SELECT 1 FROM recent_scope_order_dirty WHERE ws = ?1 AND thread = ?2)`);
    for (const row of rows) mark.run(row.ws, pending.thread);
    if (rows.length === limit) db.prepare("UPDATE recent_scope_order_dispatch SET after_ws = ? WHERE thread = ?")
      .run(rows.at(-1)!.ws, pending.thread);
    else db.prepare("DELETE FROM recent_scope_order_dispatch WHERE thread = ?").run(pending.thread);
    const done = db.prepare("SELECT 1 FROM recent_scope_order_dispatch LIMIT 1").get() === undefined;
    db.exec("COMMIT");
    return { dispatchDone: done, visited: rows.length };
  } catch (error) { db.exec("ROLLBACK"); throw error; }
}

type Current = { at: bigint; said_at: bigint; created_at: bigint };

/// Recalculate one dirty chat, or remove a deleted chat's sources in bounded batches. A marker for a chat being
/// distributed cannot be cleared early: a later message would otherwise be missed by the completed portion.
export function settleRecentWorkspaceOrderStep(db: DatabaseSync, ws: string, limit = 64): { ordersDone: boolean; visited: number } {
  if (!Number.isSafeInteger(limit) || limit < 1) throw new RangeError("recent scope order batch must be positive");
  db.exec("BEGIN IMMEDIATE");
  try {
    if (db.prepare("SELECT 1 FROM recent_scope_tracked WHERE kind = 1 AND ws = ?").get(ws) === undefined)
      throw new Error("recent scope is not tracked");
    const next = db.prepare("SELECT thread FROM recent_scope_order_dirty WHERE ws = ? ORDER BY thread LIMIT 1");
    next.setReadBigInts(true);
    const pending = next.get(ws) as { thread: bigint } | undefined;
    if (!pending) { db.exec("COMMIT"); return { ordersDone: true, visited: 0 }; }
    if (db.prepare("SELECT 1 FROM recent_scope_order_dispatch WHERE thread = ?").get(pending.thread) !== undefined) {
      db.exec("COMMIT");
      return { ordersDone: false, visited: 0 };
    }
    const current = db.prepare(`SELECT COALESCE(e.at, t.created_at) AS at, COALESCE(e.at, 0) AS said_at, t.created_at
      FROM threads t LEFT JOIN thread_state s ON s.thread = t.id
      LEFT JOIN entries e ON e.thread = t.id AND e.n = s.said_n AND e.kind = 'message' WHERE t.id = ?`);
    current.setReadBigInts(true);
    const row = current.get(pending.thread) as Current | undefined;
    let visited = 1;
    if (row) {
      db.prepare(`UPDATE recent_scope_rows SET at = ?, said_at = ?, created_at = ? WHERE ws = ? AND thread = ?
        AND (at IS NOT ? OR said_at IS NOT ? OR created_at IS NOT ?)`)
        .run(row.at, row.said_at, row.created_at, ws, pending.thread, row.at, row.said_at, row.created_at);
    } else {
      const sources = db.prepare("SELECT session FROM recent_scope_sources WHERE ws = ? AND thread = ? ORDER BY session LIMIT ?")
        .all(ws, pending.thread, limit) as { session: string }[];
      for (const source of sources) removeRecentScopeSource(db, ws, pending.thread, source.session);
      visited = Math.max(1, sources.length);
      if (sources.length === limit) {
        db.exec("COMMIT");
        return { ordersDone: false, visited };
      }
      // A row without sources can occur if a chat disappeared while its initial scan was in progress.
      if (db.prepare("DELETE FROM recent_scope_rows WHERE ws = ? AND thread = ?").run(ws, pending.thread).changes !== 0)
        db.prepare("UPDATE recent_scope_tracked SET total = total - 1 WHERE kind = 1 AND ws = ?").run(ws);
    }
    db.prepare("DELETE FROM recent_scope_order_dirty WHERE ws = ? AND thread = ?").run(ws, pending.thread);
    const done = db.prepare("SELECT 1 FROM recent_scope_order_dirty WHERE ws = ? LIMIT 1").get(ws) === undefined;
    db.exec("COMMIT");
    return { ordersDone: done, visited };
  } catch (error) { db.exec("ROLLBACK"); throw error; }
}
