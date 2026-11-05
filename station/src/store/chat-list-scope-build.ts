// The initial explicit-workspace source scan. This is not a complete builder: session, membership, thread and
// ordering changes must be accounted before a scope can be marked complete and exposed to a reader.
import type { DatabaseSync } from "node:sqlite";
import { acknowledgeRecentScopeSession } from "./chat-list-scope-journal.ts";
import { putRecentScopeSource, removeRecentScopeSource } from "./chat-list-scope-rows.ts";
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

type SessionWork = { revision: bigint; phase: "remove" | "home" | "members"; after: bigint | null };

/// Reconcile one changed session after the initial scan, without losing changes made between batches. This still
/// cannot certify a whole workspace: membership, thread and ordering changes need their own journals first.
export function settleRecentWorkspaceSessionStep(db: DatabaseSync, ws: string, limit = 64): { sessionsDone: boolean; visited: number } {
  if (!Number.isSafeInteger(limit) || limit < 1) throw new RangeError("recent workspace session batch must be positive");
  db.exec("BEGIN IMMEDIATE");
  try {
    const progress = db.prepare("SELECT scan_done, scan_session FROM recent_scope_tracked WHERE kind = 1 AND ws = ?")
      .get(ws) as { scan_done: number; scan_session: string | null } | undefined;
    if (progress === undefined) throw new Error("recent scope is not tracked");
    if (progress.scan_done !== 1 || progress.scan_session !== null) throw new Error("recent scope source scan is unfinished");
    const next = db.prepare("SELECT session, revision FROM recent_scope_session_dirty WHERE kind = 1 AND ws = ? ORDER BY session LIMIT 1");
    next.setReadBigInts(true);
    const pending = next.get(ws) as { session: string; revision: bigint } | undefined;
    if (!pending) { db.exec("COMMIT"); return { sessionsDone: true, visited: 0 }; }
    const workQuery = db.prepare("SELECT revision, phase, after FROM recent_scope_session_work WHERE ws = ? AND session = ?");
    workQuery.setReadBigInts(true);
    let work = workQuery.get(ws, pending.session) as SessionWork | undefined;
    if (!work || work.revision !== pending.revision) {
      db.prepare(`INSERT INTO recent_scope_session_work(ws, session, revision, phase, after) VALUES (?, ?, ?, 'remove', NULL)
        ON CONFLICT(ws, session) DO UPDATE SET revision = excluded.revision, phase = 'remove', after = NULL`)
        .run(ws, pending.session, pending.revision);
      work = { revision: pending.revision, phase: "remove", after: null };
    }
    if (work.phase === "remove") {
      const query = db.prepare(work.after === null
        ? "SELECT thread FROM recent_scope_sources INDEXED BY recent_scope_sources_session WHERE ws = ?1 AND session = ?2 ORDER BY thread LIMIT ?3"
        : "SELECT thread FROM recent_scope_sources INDEXED BY recent_scope_sources_session WHERE ws = ?1 AND session = ?2 AND thread > ?3 ORDER BY thread LIMIT ?4");
      query.setReadBigInts(true);
      const rows = (work.after === null ? query.all(ws, pending.session, limit)
        : query.all(ws, pending.session, work.after, limit)) as { thread: bigint }[];
      for (const row of rows) removeRecentScopeSource(db, ws, row.thread, pending.session);
      if (rows.length === limit) db.prepare("UPDATE recent_scope_session_work SET after = ? WHERE ws = ? AND session = ?")
        .run(rows.at(-1)!.thread, ws, pending.session);
      else db.prepare("UPDATE recent_scope_session_work SET phase = 'home', after = NULL WHERE ws = ? AND session = ?")
        .run(ws, pending.session);
      db.exec("COMMIT");
      return { sessionsDone: false, visited: rows.length };
    }
    const current = db.prepare("SELECT ws FROM sessions WHERE key = ?").get(pending.session) as { ws: string | null } | undefined;
    if (current?.ws !== ws) {
      db.prepare("DELETE FROM recent_scope_session_work WHERE ws = ? AND session = ?").run(ws, pending.session);
      acknowledgeRecentScopeSession(db, { kind: "workspace", workspace: ws }, pending.session, pending.revision);
      const done = db.prepare("SELECT 1 FROM recent_scope_session_dirty WHERE kind = 1 AND ws = ? LIMIT 1").get(ws) === undefined;
      db.exec("COMMIT");
      return { sessionsDone: done, visited: 0 };
    }
    const batch = recentScopeSessionThreadsStep(db, pending.session, { phase: work.phase, after: work.after }, limit);
    for (const thread of batch.threads) putRecentScopeSource(db, ws, thread, pending.session);
    if (batch.cursor.phase === "done") {
      db.prepare("DELETE FROM recent_scope_session_work WHERE ws = ? AND session = ?").run(ws, pending.session);
      acknowledgeRecentScopeSession(db, { kind: "workspace", workspace: ws }, pending.session, pending.revision);
    } else db.prepare("UPDATE recent_scope_session_work SET phase = ?, after = ? WHERE ws = ? AND session = ?")
      .run(batch.cursor.phase, batch.cursor.after, ws, pending.session);
    const done = db.prepare("SELECT 1 FROM recent_scope_session_dirty WHERE kind = 1 AND ws = ? LIMIT 1").get(ws) === undefined;
    db.exec("COMMIT");
    return { sessionsDone: done, visited: batch.visited };
  } catch (error) { db.exec("ROLLBACK"); throw error; }
}

/// Reconcile only changed memberships, rather than rescanning all of an agent's other chats for each join or leave.
/// The caller still has to settle thread and ordering changes before it can certify the workspace.
export function settleRecentWorkspaceMemberStep(db: DatabaseSync, ws: string, limit = 64): { membersDone: boolean; visited: number } {
  if (!Number.isSafeInteger(limit) || limit < 1) throw new RangeError("recent workspace membership batch must be positive");
  db.exec("BEGIN IMMEDIATE");
  try {
    const progress = db.prepare("SELECT scan_done, scan_session FROM recent_scope_tracked WHERE kind = 1 AND ws = ?")
      .get(ws) as { scan_done: number; scan_session: string | null } | undefined;
    if (progress === undefined) throw new Error("recent scope is not tracked");
    if (progress.scan_done !== 1 || progress.scan_session !== null) throw new Error("recent scope source scan is unfinished");
    const query = db.prepare("SELECT thread, session, revision FROM recent_scope_member_dirty WHERE ws = ? ORDER BY thread, session LIMIT ?");
    query.setReadBigInts(true);
    const rows = query.all(ws, limit) as { thread: bigint; session: string; revision: bigint }[];
    const eligible = db.prepare(`SELECT 1 FROM threads t JOIN sessions s ON s.key = ?2
      WHERE t.id = ?1 AND s.ws = ?3 AND (t.home = s.key OR (t.home IS NULL AND EXISTS
        (SELECT 1 FROM thread_sessions m WHERE m.thread = t.id AND m.session = s.key)))`);
    const clean = db.prepare("DELETE FROM recent_scope_member_dirty WHERE ws = ? AND thread = ? AND session = ? AND revision = ?");
    for (const row of rows) {
      if (eligible.get(row.thread, row.session, ws) !== undefined) putRecentScopeSource(db, ws, row.thread, row.session);
      else removeRecentScopeSource(db, ws, row.thread, row.session);
      clean.run(ws, row.thread, row.session, row.revision);
    }
    const done = db.prepare("SELECT 1 FROM recent_scope_member_dirty WHERE ws = ? LIMIT 1").get(ws) === undefined;
    db.exec("COMMIT");
    return { membersDone: done, visited: rows.length };
  } catch (error) { db.exec("ROLLBACK"); throw error; }
}
