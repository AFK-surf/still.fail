// Search candidate scopes. Each member contributes its workspace, which is a superset of chatOf's selected home.
// Unknown text is always reconsidered in JavaScript; this keeps SQLite's text conversion out of the access decision.
import type { DatabaseSync } from "node:sqlite";

const safe = (value: string) => `(typeof(${value}) = 'text' AND instr(${value}, char(0)) = 0 AND ${value} NOT GLOB '*[^ -~]*')`;
const memberKind = `CASE WHEN NOT ${safe("m.session")} THEN 2
  WHEN s.key IS NULL OR s.ws IS NULL THEN 0 WHEN NOT ${safe("s.ws")} THEN 2 ELSE 1 END`;
const memberWs = `CASE WHEN ${safe("m.session")} AND s.key IS NOT NULL AND s.ws IS NOT NULL AND ${safe("s.ws")}
  THEN s.ws ELSE '' END`;

// The source is a real membership, not the index. A missing session is a default-workspace candidate. The existing
// scope row is removed first by a caller that is changing it, so its refcount triggers see a genuine change.
export const INSERT_SEARCH_SCOPE_MEMBER = `INSERT INTO search_scope_members(thread, session, kind, ws)
  SELECT m.thread, m.session, ${memberKind}, ${memberWs} FROM thread_sessions m LEFT JOIN sessions s ON s.key = m.session
  WHERE m.thread = ?1 AND m.session = ?2 AND NOT EXISTS
    (SELECT 1 FROM search_scope_members x WHERE x.thread = m.thread AND x.session = m.session)`;

const updateOrphan = (thread: string) => `
  DELETE FROM search_scope_orphans WHERE thread = ${thread};
  INSERT INTO search_scope_orphans(thread) SELECT ${thread} WHERE ${thread} IS NOT NULL
    AND EXISTS (SELECT 1 FROM threads WHERE id = ${thread})
    AND NOT EXISTS (SELECT 1 FROM thread_sessions WHERE thread = ${thread})
    AND NOT EXISTS (SELECT 1 FROM search_scope_orphans WHERE thread = ${thread});`;

const markMember = (thread: string, session: string) => `
  INSERT INTO search_scope_members_dirty(thread, session) SELECT ${thread}, ${session}
    WHERE ${thread} IS NOT NULL AND ${session} IS NOT NULL AND NOT EXISTS
      (SELECT 1 FROM search_scope_members_dirty WHERE thread = ${thread} AND session = ${session});`;
const markThread = (thread: string) => `
  INSERT INTO search_scope_threads_dirty(thread) SELECT ${thread} WHERE ${thread} IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM search_scope_threads_dirty WHERE thread = ${thread});`;
const markSession = (session: string) => `
  UPDATE search_scope_sessions_dirty SET after_rowid = NULL WHERE session = ${session};
  INSERT INTO search_scope_sessions_dirty(session, after_rowid) SELECT ${session}, NULL
    WHERE ${session} IS NOT NULL AND EXISTS (SELECT 1 FROM thread_sessions INDEXED BY thread_sessions_session WHERE session = ${session})
      AND NOT EXISTS (SELECT 1 FROM search_scope_sessions_dirty WHERE session = ${session});`;

const memberByRowid = (part: "thread" | "session", condition = "") =>
  `(SELECT ${part} FROM thread_sessions WHERE rowid = NEW.rowid ${condition})`;
const memberByKey = (part: "thread" | "session") =>
  `(SELECT ${part} FROM thread_sessions WHERE thread = NEW.thread AND session = NEW.session)`;
const sessionBy = (condition: string) => `(SELECT key FROM sessions WHERE ${condition})`;
const threadByAddress = `(SELECT id FROM threads WHERE surface = NEW.surface AND channel = NEW.channel AND thread_ts = NEW.thread_ts)`;

// Inline the same insertion used during old-data preparation, substituting source references in a trigger.
const insertMember = (thread: string, session: string) => INSERT_SEARCH_SCOPE_MEMBER.replaceAll("?1", thread).replaceAll("?2", session);
const refreshMember = (thread: string, session: string) => `
  DELETE FROM search_scope_members WHERE thread = ${thread} AND session = ${session};
  ${insertMember(thread, session)};`;

/// Install only empty state and writers. Old threads and memberships are copied separately in bounded batches.
export function installSearchScopeIndex(db: DatabaseSync): void {
  const installed = db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'search_scope_meta'").get() !== undefined;
  if (installed) {
    const version = db.prepare("SELECT version FROM search_scope_meta WHERE id = 1").get() as { version: number } | undefined;
    if (version?.version !== 1) throw new Error("search scope index has an incompatible version");
    return;
  }
  db.exec("BEGIN IMMEDIATE");
  try {
    if (db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'search_scope_meta'").get() === undefined) db.exec(`
      CREATE TABLE search_scope_meta (id INTEGER PRIMARY KEY CHECK(id = 1), version INTEGER NOT NULL,
        thread_after INTEGER, thread_through INTEGER, threads_done INTEGER NOT NULL,
        member_after INTEGER, member_through INTEGER, members_done INTEGER NOT NULL);
      INSERT INTO search_scope_meta SELECT 1, 1, NULL, (SELECT MAX(id) FROM threads),
        NOT EXISTS (SELECT 1 FROM threads LIMIT 1), NULL, (SELECT MAX(rowid) FROM thread_sessions),
        NOT EXISTS (SELECT 1 FROM thread_sessions LIMIT 1);
      CREATE TABLE search_scope_members (thread INTEGER NOT NULL, session NOT NULL, kind INTEGER NOT NULL,
        ws TEXT NOT NULL, PRIMARY KEY(thread, session)) WITHOUT ROWID;
      CREATE TABLE search_scope_threads (kind INTEGER NOT NULL, ws TEXT NOT NULL, thread INTEGER NOT NULL,
        refs INTEGER NOT NULL, PRIMARY KEY(kind, ws, thread)) WITHOUT ROWID;
      CREATE TABLE search_scope_orphans (thread INTEGER PRIMARY KEY);
      CREATE TABLE search_scope_members_dirty (thread INTEGER NOT NULL, session NOT NULL,
        PRIMARY KEY(thread, session)) WITHOUT ROWID;
      CREATE TABLE search_scope_threads_dirty (thread INTEGER PRIMARY KEY);
      CREATE TABLE search_scope_sessions_dirty (session PRIMARY KEY, after_rowid INTEGER) WITHOUT ROWID;

      CREATE TRIGGER search_scope_member_added AFTER INSERT ON search_scope_members BEGIN
        INSERT INTO search_scope_threads(kind, ws, thread, refs) SELECT NEW.kind, NEW.ws, NEW.thread, 0
          WHERE NOT EXISTS (SELECT 1 FROM search_scope_threads WHERE kind = NEW.kind AND ws = NEW.ws AND thread = NEW.thread);
        UPDATE search_scope_threads SET refs = refs + 1 WHERE kind = NEW.kind AND ws = NEW.ws AND thread = NEW.thread;
      END;
      CREATE TRIGGER search_scope_member_removed AFTER DELETE ON search_scope_members BEGIN
        UPDATE search_scope_threads SET refs = refs - 1 WHERE kind = OLD.kind AND ws = OLD.ws AND thread = OLD.thread;
        DELETE FROM search_scope_threads WHERE kind = OLD.kind AND ws = OLD.ws AND thread = OLD.thread AND refs = 0;
      END;

      -- An old INSERT OR REPLACE can evict a different rowid without its delete trigger.
      CREATE TRIGGER search_scope_membership_before_add BEFORE INSERT ON thread_sessions BEGIN
        ${markMember(memberByRowid("thread"), memberByRowid("session"))}
      END;
      CREATE TRIGGER search_scope_membership_add AFTER INSERT ON thread_sessions BEGIN
        ${refreshMember("NEW.thread", "NEW.session")}
        ${updateOrphan("NEW.thread")}
      END;
      CREATE TRIGGER search_scope_membership_before_change BEFORE UPDATE ON thread_sessions
        WHEN OLD.thread IS NOT NEW.thread OR OLD.session IS NOT NEW.session OR OLD.rowid IS NOT NEW.rowid BEGIN
          ${markMember(memberByRowid("thread", "AND rowid IS NOT OLD.rowid"), memberByRowid("session", "AND rowid IS NOT OLD.rowid"))}
          ${markMember(memberByKey("thread"), memberByKey("session"))}
      END;
      CREATE TRIGGER search_scope_membership_change AFTER UPDATE OF thread, session ON thread_sessions
        WHEN OLD.thread IS NOT NEW.thread OR OLD.session IS NOT NEW.session BEGIN
          DELETE FROM search_scope_members WHERE thread = OLD.thread AND session = OLD.session;
          ${refreshMember("NEW.thread", "NEW.session")}
          ${updateOrphan("OLD.thread")} ${updateOrphan("NEW.thread")}
      END;
      CREATE TRIGGER search_scope_membership_drop AFTER DELETE ON thread_sessions BEGIN
        DELETE FROM search_scope_members WHERE thread = OLD.thread AND session = OLD.session;
        ${updateOrphan("OLD.thread")}
      END;

      CREATE TRIGGER search_scope_thread_before_add BEFORE INSERT ON threads BEGIN
        ${markThread("(SELECT id FROM threads WHERE id = NEW.id)")} ${markThread(threadByAddress)}
      END;
      CREATE TRIGGER search_scope_thread_before_change BEFORE UPDATE OF id, surface, channel, thread_ts ON threads BEGIN
        ${markThread("(SELECT id FROM threads WHERE id = NEW.id AND id IS NOT OLD.id)")}
        ${markThread(`(SELECT id FROM threads WHERE surface = NEW.surface AND channel = NEW.channel
          AND thread_ts = NEW.thread_ts AND id IS NOT OLD.id)`)}
      END;
      CREATE TRIGGER search_scope_thread_add AFTER INSERT ON threads BEGIN ${updateOrphan("NEW.id")} END;
      CREATE TRIGGER search_scope_thread_change AFTER UPDATE OF id ON threads WHEN OLD.id IS NOT NEW.id BEGIN
        ${updateOrphan("OLD.id")} ${updateOrphan("NEW.id")}
      END;
      CREATE TRIGGER search_scope_thread_drop AFTER DELETE ON threads BEGIN ${updateOrphan("OLD.id")} END;

      -- Session changes may affect many memberships; journal the session and repair its members in batches.
      CREATE TRIGGER search_scope_session_before_add BEFORE INSERT ON sessions BEGIN
        ${markSession(sessionBy("key = NEW.key"))} ${markSession(sessionBy("token = NEW.token"))}
        ${markSession(sessionBy("rowid = NEW.rowid"))}
      END;
      CREATE TRIGGER search_scope_session_add AFTER INSERT ON sessions BEGIN ${markSession("NEW.key")} END;
      CREATE TRIGGER search_scope_session_before_change BEFORE UPDATE ON sessions
        WHEN OLD.key IS NOT NEW.key OR OLD.ws IS NOT NEW.ws OR OLD.token IS NOT NEW.token OR OLD.rowid IS NOT NEW.rowid BEGIN
          ${markSession("OLD.key")} ${markSession(sessionBy("key = NEW.key AND rowid IS NOT OLD.rowid"))}
          ${markSession(sessionBy("token = NEW.token AND rowid IS NOT OLD.rowid"))}
          ${markSession(sessionBy("rowid = NEW.rowid AND rowid IS NOT OLD.rowid"))}
      END;
      CREATE TRIGGER search_scope_session_change AFTER UPDATE OF key, ws ON sessions
        WHEN OLD.key IS NOT NEW.key OR OLD.ws IS NOT NEW.ws BEGIN ${markSession("NEW.key")} END;
      CREATE TRIGGER search_scope_session_drop BEFORE DELETE ON sessions BEGIN ${markSession("OLD.key")} END;
    `);
    db.exec("COMMIT");
  } catch (error) { db.exec("ROLLBACK"); throw error; }
}
