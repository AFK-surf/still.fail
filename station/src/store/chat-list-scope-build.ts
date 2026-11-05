// The initial explicit-workspace source scan. This is not a complete builder: session, membership, thread and
// ordering changes must be accounted before a scope can be marked complete and exposed to a reader.
import type { DatabaseSync } from "node:sqlite";
import { putRecentScopeSource } from "./chat-list-scope-rows.ts";
import { recentScopeSessionThreadsStep, recentScopeSessionsStep, type RecentScopeThreadCursor } from "./chat-list-scope-source.ts";

type Progress = { scan_connect: string | null; scan_after: bigint | null; scan_done: bigint; scan_session: string | null;
  scan_phase: "home" | "members" | null; scan_thread_after: bigint | null };

/// One write transaction advances at most one session source or `limit` of that session's chat sources. A crash
/// leaves the rows and cursor at the same committed point. Completion here means only the initial scan is finished.
export function scanRecentWorkspaceStep(db: DatabaseSync, ws: string, limit = 64): { sourceDone: boolean; visited: number } {
  if (!Number.isSafeInteger(limit) || limit < 1) throw new RangeError("recent workspace scan batch must be positive");
  db.exec("BEGIN IMMEDIATE");
  try {
    const get = db.prepare(`SELECT scan_connect, scan_after, scan_done, scan_session, scan_phase, scan_thread_after
      FROM recent_scope_tracked WHERE kind = 1 AND ws = ?`);
    get.setReadBigInts(true);
    const progress = get.get(ws) as Progress | undefined;
    if (progress === undefined) throw new Error("recent scope is not tracked");
    if (progress.scan_session !== null) {
      const cursor: RecentScopeThreadCursor = { phase: progress.scan_phase ?? "home", after: progress.scan_thread_after };
      const batch = recentScopeSessionThreadsStep(db, progress.scan_session, cursor, limit);
      for (const thread of batch.threads) putRecentScopeSource(db, ws, thread, progress.scan_session);
      if (batch.cursor.phase === "done") db.prepare(`UPDATE recent_scope_tracked SET scan_session = NULL,
        scan_phase = NULL, scan_thread_after = NULL WHERE kind = 1 AND ws = ?`).run(ws);
      else db.prepare(`UPDATE recent_scope_tracked SET scan_phase = ?, scan_thread_after = ? WHERE kind = 1 AND ws = ?`)
        .run(batch.cursor.phase, batch.cursor.after, ws);
      db.exec("COMMIT");
      return { sourceDone: batch.cursor.phase === "done" && progress.scan_done === 1n, visited: batch.visited };
    }
    if (progress.scan_done === 1n) { db.exec("COMMIT"); return { sourceDone: true, visited: 0 }; }
    const batch = recentScopeSessionsStep(db, ws, { connect: progress.scan_connect, after: progress.scan_after, done: false }, 1);
    const session = batch.sessions[0]?.key ?? null;
    db.prepare(`UPDATE recent_scope_tracked SET scan_connect = ?, scan_after = ?, scan_done = ?, scan_session = ?,
      scan_phase = ?, scan_thread_after = NULL WHERE kind = 1 AND ws = ?`)
      .run(batch.cursor.connect, batch.cursor.after, batch.cursor.done ? 1 : 0, session, session === null ? null : "home", ws);
    db.exec("COMMIT");
    return { sourceDone: batch.cursor.done && session === null, visited: batch.sessions.length };
  } catch (error) { db.exec("ROLLBACK"); throw error; }
}
