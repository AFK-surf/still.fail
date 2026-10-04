// An account's database (docs/core-db.md): its tables, and the migrations that bring a database to this version, in
// order, by `PRAGMA user_version`. A database a newer core wrote (its version past ours) is opened to be read only.
//
// Each table keeps the station's payload of a row as JSON (`json`), passed through as it is, so a field a station adds
// needs no migration; next to it, the columns the core finds, sorts and filters rows by, and the fields that change
// often on their own (a thread's read position), which are columns only and updated in place.
import type { Sql } from "../host.ts";

/// The version this core writes.
export const VERSION = 1;

/// Each migration takes a database from the version before it to its own (index + 1).
export const MIGRATIONS: string[] = [
  `
  CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);

  -- The account's own: its /v1/me ('me'), its signed-in devices ('login_sessions'), an operator's lists ('admin/<list>').
  CREATE TABLE IF NOT EXISTS account_doc (name TEXT PRIMARY KEY, json TEXT NOT NULL, confirmed INTEGER);
  CREATE TABLE IF NOT EXISTS workspace (id TEXT PRIMARY KEY, json TEXT NOT NULL, confirmed INTEGER);

  -- A station's single answers: its overview, footprint, usage.
  CREATE TABLE IF NOT EXISTS station (
    address TEXT NOT NULL, kind TEXT NOT NULL, json TEXT NOT NULL, confirmed INTEGER,
    PRIMARY KEY (address, kind)
  );
  CREATE TABLE IF NOT EXISTS slack_app (station TEXT NOT NULL, connect TEXT NOT NULL, json TEXT NOT NULL, confirmed INTEGER, PRIMARY KEY (station, connect));

  -- Which of a station's lists have been read (an empty one is not one never read), when, and how often its rows changed.
  CREATE TABLE IF NOT EXISTS list (station TEXT NOT NULL, list TEXT NOT NULL, confirmed INTEGER, rev INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (station, list));

  -- The chats the viewer's sidebar lists (archived = 0) and the archived ones (1), as GET /chats gives them.
  CREATE TABLE IF NOT EXISTS chat (
    station TEXT NOT NULL, id TEXT NOT NULL, archived INTEGER NOT NULL, ord REAL NOT NULL,
    thread INTEGER, session TEXT, client_key TEXT,
    last_active INTEGER NOT NULL DEFAULT 0, pinned_at INTEGER,
    unread INTEGER, mine INTEGER NOT NULL DEFAULT 0, running INTEGER NOT NULL DEFAULT 0,
    tone TEXT, asks INTEGER NOT NULL DEFAULT 0, desk INTEGER NOT NULL DEFAULT 0,
    json TEXT NOT NULL,
    PRIMARY KEY (station, archived, id)
  );
  CREATE INDEX IF NOT EXISTS chat_recent ON chat (archived, pinned_at DESC, last_active DESC);
  CREATE INDEX IF NOT EXISTS chat_ord ON chat (station, archived, ord);
  CREATE INDEX IF NOT EXISTS chat_thread ON chat (station, thread) WHERE thread IS NOT NULL;
  CREATE INDEX IF NOT EXISTS chat_session ON chat (station, session);
  CREATE INDEX IF NOT EXISTS chat_running ON chat (station) WHERE running = 1;
  CREATE INDEX IF NOT EXISTS chat_marked ON chat (station) WHERE archived = 0 AND (tone IS NOT NULL OR asks = 1);
  CREATE INDEX IF NOT EXISTS chat_desk ON chat (station) WHERE archived = 0 AND desk = 1;

  -- Agents: the summary (GET /sessions, session events), listed while not archived; the detail (GET /sessions/:key) but
  -- its threads, which are the thread rows it takes part in (thread_member).
  CREATE TABLE IF NOT EXISTS session (
    station TEXT NOT NULL, key TEXT NOT NULL, listed INTEGER NOT NULL DEFAULT 0, ord REAL NOT NULL DEFAULT 0,
    last_active INTEGER, process TEXT, connect TEXT, archived_at INTEGER, turns INTEGER,
    summary TEXT, detail TEXT,
    PRIMARY KEY (station, key)
  );
  CREATE INDEX IF NOT EXISTS session_listed ON session (station, listed, ord);

  -- Threads (GET /threads, a session's detail, thread events); last, read and unread are columns only.
  CREATE TABLE IF NOT EXISTS thread (
    station TEXT NOT NULL, id INTEGER NOT NULL, listed INTEGER NOT NULL DEFAULT 0,
    last INTEGER, read INTEGER, unread INTEGER,
    sort_at INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL DEFAULT 0,
    surface TEXT, first_member TEXT,
    json TEXT NOT NULL,
    PRIMARY KEY (station, id)
  );
  CREATE INDEX IF NOT EXISTS thread_listed ON thread (station, listed, sort_at DESC, created_at DESC, id DESC);
  CREATE INDEX IF NOT EXISTS thread_first ON thread (station, first_member);
  CREATE TABLE IF NOT EXISTS thread_member (station TEXT NOT NULL, session TEXT NOT NULL, thread INTEGER NOT NULL, PRIMARY KEY (station, session, thread));
  CREATE INDEX IF NOT EXISTS thread_member_thread ON thread_member (station, thread);

  -- A thread's messages and a session's transcript, item by item.
  CREATE TABLE IF NOT EXISTS entry (station TEXT NOT NULL, thread INTEGER NOT NULL, n INTEGER NOT NULL, json TEXT NOT NULL, PRIMARY KEY (station, thread, n)) WITHOUT ROWID;
  CREATE TABLE IF NOT EXISTS transcript (station TEXT NOT NULL, session TEXT NOT NULL, i INTEGER NOT NULL, json TEXT NOT NULL, PRIMARY KEY (station, session, i)) WITHOUT ROWID;

  -- Jobs: as each is now (job events, a session's detail), open = among the station's open ones (GET /jobs, with chat).
  CREATE TABLE IF NOT EXISTS job (
    station TEXT NOT NULL, id TEXT NOT NULL, session TEXT, open INTEGER NOT NULL DEFAULT 0, ord REAL NOT NULL DEFAULT 0,
    chat TEXT, json TEXT NOT NULL,
    PRIMARY KEY (station, id)
  );
  CREATE INDEX IF NOT EXISTS job_open ON job (station, open, ord);

  -- What this device did and its station has not confirmed yet (views/local.ts), and what is being written here.
  CREATE TABLE IF NOT EXISTS outbox (station TEXT NOT NULL, thread INTEGER NOT NULL, json TEXT NOT NULL, PRIMARY KEY (station, thread));
  CREATE TABLE IF NOT EXISTS pending (key TEXT PRIMARY KEY, station TEXT NOT NULL, json TEXT NOT NULL);
  CREATE TABLE IF NOT EXISTS first (station TEXT NOT NULL, session TEXT NOT NULL, json TEXT NOT NULL, PRIMARY KEY (station, session));
  CREATE TABLE IF NOT EXISTS changing (station TEXT NOT NULL, id INTEGER NOT NULL, json TEXT NOT NULL, PRIMARY KEY (station, id));
  CREATE TABLE IF NOT EXISTS draft (station TEXT NOT NULL, chat TEXT NOT NULL, json TEXT NOT NULL, PRIMARY KEY (station, chat));

  -- What this device keeps of a workspace: a new chat's picks (choose.ts), chats' links (refs.ts).
  CREATE TABLE IF NOT EXISTS workspace_pref (workspace TEXT NOT NULL, key TEXT NOT NULL, json TEXT NOT NULL, PRIMARY KEY (workspace, key));
  `,
];

// An entry's part in what was said (`e` the entry row): whether it says something (a message, or an edit of one), the
// message it is of, when that was said (a message's own time), and its words.
const kind = (e: string) => `json_extract(${e}.json, '$.kind')`;
const SAYS = (e: string) => `(${kind(e)} = 'message' OR (${kind(e)} = 'edit' AND json_type(${e}.json, '$.target') = 'integer'))`;
const SEQ = (e: string) => `(CASE ${kind(e)} WHEN 'message' THEN ${e}.n ELSE json_extract(${e}.json, '$.target') END)`;
const AT = (e: string) => `(CASE ${kind(e)} WHEN 'message' THEN json_extract(${e}.json, '$.at') END)`;
const TEXT = (e: string) => `coalesce(CASE json_type(${e}.json, '$.text') WHEN 'text' THEN json_extract(${e}.json, '$.text') END, '')`;
// The latest words win, whichever came first (a thread's older pages are read after its newer ones).
const UPSERT = `ON CONFLICT (station, thread, seq) DO UPDATE SET
  text = CASE WHEN excluded.n >= said.n THEN excluded.text ELSE said.text END,
  n = max(said.n, excluded.n),
  at = coalesce(excluded.at, said.at)`;

/// What was said in the threads, for finding messages by their words (`said`): each message's latest text (an edit's
/// replaces it), kept by triggers on `entry`, so whatever writes entries keeps it, a core that knows nothing of it too;
/// and SQLite's full-text index of it (`said_index`: FTS5, trigram, so any three characters match, Chinese too) where
/// the build has FTS5. Not a migration (a version bump would leave an older core the database only to read): made
/// where missing at every open, filled once from the entries held. Answers whether the index is there.
export function ensureSaid(sql: Sql): boolean {
  const had = sql.all("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'said'").length > 0;
  sql.exec("BEGIN IMMEDIATE");
  try {
    sql.exec(`
      CREATE TABLE IF NOT EXISTS said (
        id INTEGER PRIMARY KEY, station TEXT NOT NULL, thread INTEGER NOT NULL, seq INTEGER NOT NULL,
        n INTEGER NOT NULL, at INTEGER, text TEXT NOT NULL,
        UNIQUE (station, thread, seq)
      );
      -- A message's edits, by the message (for when the entry its words came from goes).
      CREATE INDEX IF NOT EXISTS entry_edit ON entry (station, thread, json_extract(json, '$.target')) WHERE json_extract(json, '$.kind') = 'edit';
      CREATE TRIGGER IF NOT EXISTS said_put AFTER INSERT ON entry WHEN ${SAYS("new")}
      BEGIN
        INSERT INTO said (station, thread, seq, n, at, text) VALUES (new.station, new.thread, ${SEQ("new")}, new.n, ${AT("new")}, ${TEXT("new")})
        ${UPSERT};
      END;
      -- The entry a message's words came from gone: its words are those of what is left of it (nothing, when it went).
      CREATE TRIGGER IF NOT EXISTS said_drop AFTER DELETE ON entry WHEN ${SAYS("old")}
      BEGIN
        DELETE FROM said WHERE station = old.station AND thread = old.thread AND seq = ${SEQ("old")} AND n = old.n;
        INSERT INTO said (station, thread, seq, n, at, text)
        SELECT * FROM (
          SELECT e.station, e.thread, e.n AS seq, e.n, ${AT("e")}, ${TEXT("e")} FROM entry e
          WHERE e.station = old.station AND e.thread = old.thread AND e.n = ${SEQ("old")} AND ${kind("e")} = 'message'
          UNION ALL
          SELECT e.station, e.thread, json_extract(e.json, '$.target'), e.n, NULL, ${TEXT("e")} FROM entry e
          WHERE e.station = old.station AND e.thread = old.thread AND json_extract(e.json, '$.target') = ${SEQ("old")} AND json_extract(e.json, '$.kind') = 'edit'
        )
        WHERE NOT EXISTS (SELECT 1 FROM said WHERE station = old.station AND thread = old.thread AND seq = ${SEQ("old")})
        ORDER BY 4
        ${UPSERT};
      END;
    `);
    if (!had) {
      // Oldest first, as they came.
      sql.exec(`
        INSERT INTO said (station, thread, seq, n, at, text)
        SELECT e.station, e.thread, ${SEQ("e")}, e.n, ${AT("e")}, ${TEXT("e")} FROM entry e
        WHERE ${SAYS("e")}
        ORDER BY e.station, e.thread, e.n
        ${UPSERT};
      `);
    }
    sql.exec("COMMIT");
  } catch (e) {
    try {
      sql.exec("ROLLBACK");
    } catch {
      // Rolled back already.
    }
    throw e;
  }
  return ensureSaidIndex(sql);
}

/// What is kept of each log (a thread's entries, `entry`; an agent's transcript, `transcript`) as the device holds
/// within its room (data.ts KEPT): when its chat was last opened here, and whether its items were let go for room.
/// Made where missing at every open, as `said`.
export function ensureKept(sql: Sql): void {
  sql.exec("CREATE TABLE IF NOT EXISTS log_use (kind TEXT NOT NULL, station TEXT NOT NULL, id TEXT NOT NULL, opened INTEGER, evicted INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (kind, station, id))");
}

/// What agents sent to Slack, read from their transcripts as they are written (elsewhere.ts): kept beyond the
/// transcript's items (let go for room, they are still shown in their chats). Made where missing at every open, as
/// `said`; answers whether it was made now (to be filled from the transcripts held).
export function ensureSent(sql: Sql): boolean {
  const had = sql.all("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'sent'").length > 0;
  sql.exec("CREATE TABLE IF NOT EXISTS sent (station TEXT NOT NULL, session TEXT NOT NULL, i INTEGER NOT NULL, call TEXT, at INTEGER NOT NULL, dest TEXT NOT NULL, text TEXT NOT NULL, failed INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (station, session, i))");
  return !had;
}

/// The full-text index of `said`, made and filled where missing. A build without FTS5 (or its trigram tokenizer) has
/// none, and its triggers are taken away if an earlier one left them: `said` is then searched by scanning it.
function ensureSaidIndex(sql: Sql): boolean {
  const has = (name: string) => sql.all("SELECT 1 FROM sqlite_master WHERE name = ?", [name]).length > 0;
  let fts = true;
  try {
    sql.exec("CREATE VIRTUAL TABLE IF NOT EXISTS temp.said_probe USING fts5(text, tokenize = 'trigram'); DROP TABLE temp.said_probe;");
  } catch {
    fts = false;
  }
  if (!fts) {
    for (const trigger of ["said_index_put", "said_index_drop", "said_index_set"]) if (has(trigger)) sql.exec(`DROP TRIGGER ${trigger}`);
    return false;
  }
  if (has("said_index") && has("said_index_put")) return true;
  sql.exec("BEGIN IMMEDIATE");
  try {
    sql.exec(`
      CREATE VIRTUAL TABLE IF NOT EXISTS said_index USING fts5(text, content = 'said', content_rowid = 'id', tokenize = 'trigram');
      CREATE TRIGGER IF NOT EXISTS said_index_put AFTER INSERT ON said BEGIN
        INSERT INTO said_index (rowid, text) VALUES (new.id, new.text);
      END;
      CREATE TRIGGER IF NOT EXISTS said_index_drop AFTER DELETE ON said BEGIN
        INSERT INTO said_index (said_index, rowid, text) VALUES ('delete', old.id, old.text);
      END;
      CREATE TRIGGER IF NOT EXISTS said_index_set AFTER UPDATE OF text ON said WHEN old.text IS NOT new.text BEGIN
        INSERT INTO said_index (said_index, rowid, text) VALUES ('delete', old.id, old.text);
        INSERT INTO said_index (rowid, text) VALUES (new.id, new.text);
      END;
      INSERT INTO said_index (said_index) VALUES ('rebuild');
    `);
    sql.exec("COMMIT");
  } catch {
    try {
      sql.exec("ROLLBACK");
    } catch {
      // Rolled back already.
    }
    return false;
  }
  return true;
}

/// The database's version.
export function versionOf(sql: Sql): number {
  const v = sql.all("PRAGMA user_version")[0]?.[0];
  return typeof v === "number" ? v : 0;
}

/// Brings the database to VERSION, each migration in a transaction of its own. A database past it is left as it is:
/// false then (it is read only).
export function migrate(sql: Sql): boolean {
  let version = versionOf(sql);
  if (version > VERSION) return false;
  while (version < VERSION) {
    sql.exec("BEGIN IMMEDIATE");
    try {
      sql.exec(MIGRATIONS[version]);
      sql.exec(`PRAGMA user_version = ${version + 1}`);
      sql.exec("COMMIT");
    } catch (e) {
      try {
        sql.exec("ROLLBACK");
      } catch {
        // Rolled back already.
      }
      throw e;
    }
    version++;
  }
  return true;
}
