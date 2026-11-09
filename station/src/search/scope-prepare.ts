// Bounded old-state preparation and repairs for the search candidate index.
import type { DatabaseSync } from "node:sqlite";
import { INSERT_SEARCH_SCOPE_MEMBER, installSearchScopeIndex } from "./scope-index.ts";

type Meta = { thread_after: bigint | null; thread_through: bigint | null; threads_done: bigint;
  member_after: bigint | null; member_through: bigint | null; members_done: bigint };
type Key = { thread: bigint; bytes: Uint8Array; storage: string };
type Session = { bytes: Uint8Array; storage: string; after_rowid: bigint | null };

// SQLite's original text bytes need not round-trip through a JavaScript string. Bind the raw bytes as the original
// SQLite storage class, so a repair seeks exactly the same membership or session it marked.
const textKey = (storage: string, parameter: string) => storage === "text" ? `CAST(${parameter} AS TEXT)` : parameter;

function repairOrphan(db: DatabaseSync, thread: bigint): void {
  db.prepare("DELETE FROM search_scope_orphans WHERE thread = ?").run(thread);
  db.prepare(`INSERT INTO search_scope_orphans(thread) SELECT ?1 WHERE EXISTS (SELECT 1 FROM threads WHERE id = ?1)
    AND NOT EXISTS (SELECT 1 FROM thread_sessions WHERE thread = ?1)
    AND NOT EXISTS (SELECT 1 FROM search_scope_orphans WHERE thread = ?1)`).run(thread);
}

function repairMember(db: DatabaseSync, thread: bigint, bytes: Uint8Array, storage: string): void {
  const key = textKey(storage, "?2");
  db.prepare(`DELETE FROM search_scope_members WHERE thread = ?1 AND session = ${key}`).run(thread, bytes);
  db.prepare(INSERT_SEARCH_SCOPE_MEMBER.replaceAll("?2", key)).run(thread, bytes);
}

/// A worker calls one step at a time, giving foreground writes and other preparation work a turn between steps.
export class SearchScopePreparation {
  readonly #db: DatabaseSync;
  readonly #limit: number;
  #installed = false;
  #turn = 0;

  constructor(db: DatabaseSync, limit = 64) {
    if (!Number.isSafeInteger(limit) || limit < 1) throw new RangeError("search scope batch must be positive");
    this.#db = db; this.#limit = limit;
  }

  step(): { done: boolean; visited: number } {
    const db = this.#db, limit = this.#limit;
    if (!this.#installed) { installSearchScopeIndex(db); this.#installed = true; }
    db.exec("BEGIN IMMEDIATE");
    try {
      const metaQuery = db.prepare(`SELECT thread_after, thread_through, threads_done, member_after, member_through, members_done
        FROM search_scope_meta WHERE id = 1 AND version = 1`);
      metaQuery.setReadBigInts(true);
      const meta = metaQuery.get() as Meta | undefined;
      if (!meta) throw new Error("search scope index has an incompatible version");
      const session = db.prepare(`SELECT CAST(session AS BLOB) AS bytes, typeof(session) AS storage, after_rowid
        FROM search_scope_sessions_dirty ORDER BY session LIMIT 1`);
      session.setReadBigInts(true);
      const pendingSession = session.get() as Session | undefined;
      const member = db.prepare(`SELECT thread, CAST(session AS BLOB) AS bytes, typeof(session) AS storage
        FROM search_scope_members_dirty ORDER BY thread, session LIMIT 1`);
      member.setReadBigInts(true);
      const pendingMember = member.get() as Key | undefined;
      const thread = db.prepare("SELECT thread FROM search_scope_threads_dirty ORDER BY thread LIMIT 1");
      thread.setReadBigInts(true);
      const pendingThread = thread.get() as { thread: bigint } | undefined;
      const pending = [pendingSession !== undefined, pendingMember !== undefined, pendingThread !== undefined,
        meta.threads_done !== 1n, meta.members_done !== 1n];
      if (!pending.some(Boolean)) { db.exec("COMMIT"); return { done: true, visited: 0 }; }
      let lane = 0;
      for (let i = 0; i < pending.length; i++) {
        lane = (this.#turn + i) % pending.length;
        if (pending[lane]) break;
      }
      this.#turn = (lane + 1) % pending.length;
      let visited = 0;
      if (lane === 0 && pendingSession) {
        const key = textKey(pendingSession.storage, "?1");
        const query = db.prepare(pendingSession.after_rowid === null
          ? `SELECT rowid AS n, thread FROM thread_sessions INDEXED BY thread_sessions_session WHERE session = ${key} ORDER BY rowid LIMIT ?2`
          : `SELECT rowid AS n, thread FROM thread_sessions INDEXED BY thread_sessions_session WHERE session = ${key} AND rowid > ?2 ORDER BY rowid LIMIT ?3`);
        query.setReadBigInts(true);
        const rows = (pendingSession.after_rowid === null ? query.all(pendingSession.bytes, limit)
          : query.all(pendingSession.bytes, pendingSession.after_rowid, limit)) as { n: bigint; thread: bigint }[];
        for (const row of rows) repairMember(db, row.thread, pendingSession.bytes, pendingSession.storage);
        visited = rows.length;
        if (rows.length < limit) db.prepare(`DELETE FROM search_scope_sessions_dirty WHERE session = ${key}`).run(pendingSession.bytes);
        else db.prepare(`UPDATE search_scope_sessions_dirty SET after_rowid = ?2 WHERE session = ${key}`)
          .run(pendingSession.bytes, rows.at(-1)!.n);
      } else if (lane === 1 && pendingMember) {
        repairMember(db, pendingMember.thread, pendingMember.bytes, pendingMember.storage);
        repairOrphan(db, pendingMember.thread);
        db.prepare(`DELETE FROM search_scope_members_dirty WHERE thread = ?1 AND session = ${textKey(pendingMember.storage, "?2")}`)
          .run(pendingMember.thread, pendingMember.bytes);
        visited = 1;
      } else if (lane === 2 && pendingThread) {
        repairOrphan(db, pendingThread.thread);
        db.prepare("DELETE FROM search_scope_threads_dirty WHERE thread = ?").run(pendingThread.thread);
        visited = 1;
      } else if (lane === 3) {
        const query = db.prepare(meta.thread_after === null
          ? "SELECT id FROM threads WHERE id <= ?1 ORDER BY id LIMIT ?2"
          : "SELECT id FROM threads WHERE id > ?1 AND id <= ?2 ORDER BY id LIMIT ?3");
        query.setReadBigInts(true);
        const rows = meta.thread_through === null ? [] : (meta.thread_after === null ? query.all(meta.thread_through, limit)
          : query.all(meta.thread_after, meta.thread_through, limit)) as { id: bigint }[];
        for (const row of rows) repairOrphan(db, row.id);
        db.prepare("UPDATE search_scope_meta SET thread_after = ?, threads_done = ? WHERE id = 1")
          .run(rows.at(-1)?.id ?? meta.thread_after, rows.length < limit ? 1 : 0);
        visited = rows.length;
      } else if (lane === 4) {
        const query = db.prepare(meta.member_after === null
          ? "SELECT rowid AS n, thread, CAST(session AS BLOB) AS bytes, typeof(session) AS storage FROM thread_sessions WHERE rowid <= ?1 ORDER BY rowid LIMIT ?2"
          : "SELECT rowid AS n, thread, CAST(session AS BLOB) AS bytes, typeof(session) AS storage FROM thread_sessions WHERE rowid > ?1 AND rowid <= ?2 ORDER BY rowid LIMIT ?3");
        query.setReadBigInts(true);
        const rows = meta.member_through === null ? [] : (meta.member_after === null ? query.all(meta.member_through, limit)
          : query.all(meta.member_after, meta.member_through, limit)) as (Key & { n: bigint })[];
        for (const row of rows) db.prepare(INSERT_SEARCH_SCOPE_MEMBER.replaceAll("?2", textKey(row.storage, "?2"))).run(row.thread, row.bytes);
        db.prepare("UPDATE search_scope_meta SET member_after = ?, members_done = ? WHERE id = 1")
          .run(rows.at(-1)?.n ?? meta.member_after, rows.length < limit ? 1 : 0);
        visited = rows.length;
      }
      db.exec("COMMIT");
      return { done: false, visited };
    } catch (error) { db.exec("ROLLBACK"); throw error; }
  }
}
