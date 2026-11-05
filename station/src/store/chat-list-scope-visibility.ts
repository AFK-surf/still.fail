// Rebuild one chat's explicit-workspace contributions after its home changes. The home/default scope and its
// overlap with an explicit workspace are separate work; this prototype must not certify a complete reader yet.
import type { DatabaseSync } from "node:sqlite";
import { putRecentScopeSource, removeRecentScopeSource } from "./chat-list-scope-rows.ts";

type Work = { revision: bigint; phase: "remove" | "add"; after_ws: string | null; after_session: string | null };

/// The source scan and its cursor commit together. A home changed again between batches restarts the pass; member
/// and session changes have their own journals, including while this pass is in progress.
export function settleRecentScopeVisibilityStep(db: DatabaseSync, limit = 64): { visibilityDone: boolean; visited: number } {
  if (!Number.isSafeInteger(limit) || limit < 1) throw new RangeError("recent scope visibility batch must be positive");
  db.exec("BEGIN IMMEDIATE");
  try {
    // Walk a finite round of pending chats, rather than repeatedly taking the smallest id or letting new larger
    // ids postpone a wrap forever. Commit the turn with its work so a rollback or worker restart preserves it.
    const turn = db.prepare("SELECT after_thread, through_thread FROM recent_scope_visibility_turn WHERE id = 1");
    turn.setReadBigInts(true);
    const progress = turn.get() as { after_thread: bigint | null; through_thread: bigint | null };
    let through = progress.through_thread;
    let pending: { thread: bigint; revision: bigint } | undefined;
    if (through !== null) {
      const next = db.prepare(progress.after_thread === null
        ? "SELECT thread, revision FROM recent_scope_visibility_dirty WHERE thread <= ? ORDER BY thread LIMIT 1"
        : "SELECT thread, revision FROM recent_scope_visibility_dirty WHERE thread > ? AND thread <= ? ORDER BY thread LIMIT 1");
      next.setReadBigInts(true);
      pending = (progress.after_thread === null ? next.get(through) : next.get(progress.after_thread, through)) as typeof pending;
    }
    if (!pending) {
      const last = db.prepare("SELECT MAX(thread) AS thread FROM recent_scope_visibility_dirty");
      last.setReadBigInts(true);
      through = (last.get() as { thread: bigint | null }).thread;
      if (through === null) { db.exec("COMMIT"); return { visibilityDone: true, visited: 0 }; }
      const first = db.prepare("SELECT thread, revision FROM recent_scope_visibility_dirty WHERE thread <= ? ORDER BY thread LIMIT 1");
      first.setReadBigInts(true);
      pending = first.get(through) as { thread: bigint; revision: bigint };
    }
    db.prepare("UPDATE recent_scope_visibility_turn SET after_thread = ?, through_thread = ? WHERE id = 1").run(pending.thread, through);
    // A home session can move while this job waits. Refresh the hint before removing any old contributions, so
    // a reader of the new workspace cannot mistake that intermediate state for a finished page.
    db.prepare(`UPDATE recent_scope_visibility_dirty SET
      home_ws = (SELECT s.ws FROM threads t JOIN sessions s ON s.key = t.home WHERE t.id = ?1),
      ambiguous = EXISTS (SELECT 1 FROM threads t WHERE t.id = ?1 AND t.home IS NULL
        AND EXISTS (SELECT 1 FROM thread_sessions m WHERE m.thread = t.id LIMIT 1)) WHERE thread = ?1`).run(pending.thread);
    const getWork = db.prepare("SELECT revision, phase, after_ws, after_session FROM recent_scope_visibility_work WHERE thread = ?");
    getWork.setReadBigInts(true);
    let work = getWork.get(pending.thread) as Work | undefined;
    if (!work || work.revision !== pending.revision) {
      db.prepare(`INSERT INTO recent_scope_visibility_work(thread, revision, phase, after_ws, after_session)
        VALUES (?, ?, 'remove', NULL, NULL) ON CONFLICT(thread) DO UPDATE SET revision = excluded.revision,
        phase = 'remove', after_ws = NULL, after_session = NULL`).run(pending.thread, pending.revision);
      work = { revision: pending.revision, phase: "remove", after_ws: null, after_session: null };
    }
    if (work.phase === "remove") {
      const query = db.prepare(work.after_ws === null
        ? "SELECT ws, session FROM recent_scope_sources INDEXED BY recent_scope_sources_thread WHERE thread = ?1 ORDER BY ws, session LIMIT ?2"
        : "SELECT ws, session FROM recent_scope_sources INDEXED BY recent_scope_sources_thread WHERE thread = ?1 AND (ws, session) > (?2, ?3) ORDER BY ws, session LIMIT ?4");
      const sources = (work.after_ws === null ? query.all(pending.thread, limit)
        : query.all(pending.thread, work.after_ws, work.after_session, limit)) as { ws: string; session: string }[];
      for (const source of sources) removeRecentScopeSource(db, source.ws, pending.thread, source.session);
      if (sources.length === limit) db.prepare("UPDATE recent_scope_visibility_work SET after_ws = ?, after_session = ? WHERE thread = ?")
        .run(sources.at(-1)!.ws, sources.at(-1)!.session, pending.thread);
      else db.prepare("UPDATE recent_scope_visibility_work SET phase = 'add', after_ws = NULL, after_session = NULL WHERE thread = ?")
        .run(pending.thread);
      db.exec("COMMIT");
      return { visibilityDone: false, visited: sources.length };
    }
    const thread = db.prepare("SELECT home FROM threads WHERE id = ?").get(pending.thread) as { home: string | null } | undefined;
    let visited = 0;
    if (thread && thread.home !== null) {
      const session = db.prepare("SELECT ws FROM sessions WHERE key = ?").get(thread.home) as { ws: string | null } | undefined;
      if (session?.ws !== null && session?.ws !== undefined &&
          db.prepare("SELECT 1 FROM recent_scope_tracked WHERE kind = 1 AND ws = ?").get(session.ws) !== undefined)
        putRecentScopeSource(db, session.ws, pending.thread, thread.home);
      visited = 1;
    } else if (thread) {
      const members = (work.after_session === null
        ? db.prepare("SELECT session FROM thread_sessions WHERE thread = ?1 ORDER BY session LIMIT ?2").all(pending.thread, limit)
        : db.prepare("SELECT session FROM thread_sessions WHERE thread = ?1 AND session > ?2 ORDER BY session LIMIT ?3")
          .all(pending.thread, work.after_session, limit)) as { session: string }[];
      const session = db.prepare("SELECT ws FROM sessions WHERE key = ?");
      const tracked = db.prepare("SELECT 1 FROM recent_scope_tracked WHERE kind = 1 AND ws = ?");
      for (const member of members) {
        const row = session.get(member.session) as { ws: string | null } | undefined;
        if (row?.ws !== null && row?.ws !== undefined && tracked.get(row.ws) !== undefined)
          putRecentScopeSource(db, row.ws, pending.thread, member.session);
      }
      visited = members.length;
      if (members.length === limit) {
        db.prepare("UPDATE recent_scope_visibility_work SET after_session = ? WHERE thread = ?")
          .run(members.at(-1)!.session, pending.thread);
        db.exec("COMMIT");
        return { visibilityDone: false, visited };
      }
    }
    db.prepare("DELETE FROM recent_scope_visibility_work WHERE thread = ?").run(pending.thread);
    db.prepare("DELETE FROM recent_scope_visibility_dirty WHERE thread = ? AND revision = ?").run(pending.thread, pending.revision);
    const done = db.prepare("SELECT 1 FROM recent_scope_visibility_dirty LIMIT 1").get() === undefined;
    db.exec("COMMIT");
    return { visibilityDone: done, visited };
  } catch (error) { db.exec("ROLLBACK"); throw error; }
}
