// The recent chat index's four parts and their writers (station/src/store/chat-list-index.ts, chat-list-scope-journal.ts,
// chat-list-home-index.ts, chat-list-home-overlap.ts): the same tables and triggers, made when a part is first asked
// for, each with its version (`recent_chat_versions`, chat-list-schema.ts) in the transaction that makes it.

///|
let version_query : String = "SELECT (SELECT version = 1 FROM recent_chat_versions WHERE part = ?1) AS current, EXISTS (SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?2) AS component"

///|
let tables_query : String = "SELECT EXISTS (SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?1) AS component, EXISTS (SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'recent_chat_versions') AS versions"

///|
fn component(part : String) -> String {
  match part {
    "global" => "recent_chat_meta"
    "scope" => "recent_scope_tracked"
    "home" => "recent_home_meta"
    _ => "recent_home_overlap_meta"
  }
}

///|
/// The part there, of this version (`recentChatIndexInstalled`); a part without its version, or of another, fails.
fn installed(db : @sql.Db, part : String) -> Bool raise {
  let ask = () => {
    one(db, version_query, [Json::string(part), Json::string(component(part))])
  }
  let marker = ask() catch {
    e => {
      guard e is @wire.ShellError(m) &&
        m.contains("no such table: recent_chat_versions") else {
        raise e
      }
      let found = one(db, tables_query, [Json::string(component(part))])
      if int(found, "versions") != 1 {
        if int(found, "component") != 1 {
          return false
        }
        fail("recent chat \{part} index has an incompatible or missing version")
      }
      // (another connection made the versions after the first statement failed: both read again on one snapshot)
      ask()
    }
  }
  let current = marker.get("current").unwrap_or(Json::null())
  if int(marker, "component") != 1 && current is Null {
    return false
  }
  if int(marker, "component") != 1 || int(marker, "current") != 1 {
    fail("recent chat \{part} index has an incompatible or missing version")
  }
  true
}

///|
fn mark_installed(db : @sql.Db, part : String) -> Unit raise {
  db.exec(
    "CREATE TABLE IF NOT EXISTS recent_chat_versions (part TEXT PRIMARY KEY, version INTEGER NOT NULL) WITHOUT ROWID",
  )
  ignore(
    db.run("INSERT INTO recent_chat_versions(part, version) VALUES (?, 1)", [
      Json::string(part),
    ]),
  )
}

///|
/// A part made when it is not there: `ddl`, then `more` (in the same transaction), then its version.
fn install(
  db : @sql.Db,
  part : String,
  ddl : String,
  more~ : () -> Unit raise = () => (),
) -> Unit raise {
  if installed(db, part) {
    return
  }
  write(db, () => {
    if !installed(db, part) {
      db.exec(ddl)
      more()
      mark_installed(db, part)
    }
  })
}

// Shared pieces of the writers.

///|
/// The chat a REPLACE evicts by its unique surface, channel and thread.
let conflicting_thread : String = "(SELECT t.id FROM threads t WHERE t.surface = NEW.surface AND t.channel = NEW.channel AND t.thread_ts = NEW.thread_ts AND t.id IS NOT NEW.id)"

///|
/// A message that makes a chat's selected number resolve (inserted with it, or by its timestamp).
let inserted_said : String = "EXISTS (SELECT 1 FROM thread_state s WHERE s.thread = NEW.thread AND (s.said_n = NEW.n OR (NEW.ts IS NOT NULL AND EXISTS (SELECT 1 FROM entries e WHERE e.thread = s.thread AND e.n = s.said_n AND e.kind = 'message' AND e.ts = NEW.ts))))"

///|
/// A changed message that replaces a chat's selected one.
let displaced_said : String = "EXISTS (SELECT 1 FROM thread_state s JOIN entries e ON e.thread = s.thread AND e.n = s.said_n AND e.kind = 'message' WHERE s.thread = NEW.thread AND (e.n = NEW.n OR (NEW.ts IS NOT NULL AND e.ts = NEW.ts)) AND (e.thread IS NOT OLD.thread OR e.n IS NOT OLD.n))"

///|
/// The chat whose selected message a write evicts through its rowid (chat-list-entry-rowid.ts).
let displaced_entry : String = "SELECT e.thread FROM entries e JOIN thread_state s ON s.thread = e.thread AND s.said_n = e.n WHERE e.rowid = NEW.rowid AND e.kind = 'message'"

///|
let evicted_thread : String = "(SELECT thread FROM entries WHERE rowid = NEW.rowid)"

// The station-wide ordering (chat-list-index.ts).

///|
fn global_dirty(thread : String) -> String {
  "INSERT INTO recent_chat_dirty (thread) SELECT \{thread} WHERE \{thread} IS NOT NULL AND NOT EXISTS (SELECT 1 FROM recent_chat_dirty WHERE thread = \{thread});"
}

///|
pub fn global_schema() -> String {
  let d = global_dirty
  [
    "CREATE TABLE recent_chat_rows (thread INTEGER PRIMARY KEY, at INTEGER NOT NULL, said_at INTEGER NOT NULL, created_at INTEGER NOT NULL);",
    "CREATE INDEX recent_chat_order ON recent_chat_rows (at DESC, said_at DESC, created_at DESC, thread DESC);",
    "CREATE TABLE recent_chat_dirty (thread INTEGER PRIMARY KEY);",
    "CREATE TABLE recent_chat_meta (id INTEGER PRIMARY KEY CHECK (id = 1), cursor INTEGER, through INTEGER, total INTEGER NOT NULL, complete INTEGER NOT NULL, prefer_dirty INTEGER NOT NULL);",
    "INSERT INTO recent_chat_meta SELECT 1, NULL, (SELECT MAX(id) FROM threads), 0, NOT EXISTS (SELECT 1 FROM threads LIMIT 1), 1;",
    // (REPLACE can evict a different row without running that row's DELETE trigger: the evicted id first)
    "CREATE TRIGGER recent_chat_thread_before_add BEFORE INSERT ON threads BEGIN \{d(conflicting_thread)} END;",
    "CREATE TRIGGER recent_chat_thread_before_change BEFORE UPDATE OF id, surface, channel, thread_ts ON threads BEGIN \{d(conflicting_thread)} END;",
    "CREATE TRIGGER recent_chat_thread_add AFTER INSERT ON threads BEGIN \{d("NEW.id")} END;",
    "CREATE TRIGGER recent_chat_thread_change AFTER UPDATE OF id, created_at ON threads BEGIN \{d("OLD.id")} \{d("NEW.id")} END;",
    "CREATE TRIGGER recent_chat_thread_drop AFTER DELETE ON threads BEGIN \{d("OLD.id")} END;",
    "CREATE TRIGGER recent_chat_state_add AFTER INSERT ON thread_state BEGIN \{d("NEW.thread")} END;",
    "CREATE TRIGGER recent_chat_state_change AFTER UPDATE OF thread, said_n ON thread_state WHEN OLD.thread IS NOT NEW.thread OR OLD.said_n IS NOT NEW.said_n BEGIN \{d("OLD.thread")} \{d("NEW.thread")} END;",
    "CREATE TRIGGER recent_chat_state_drop AFTER DELETE ON thread_state WHEN OLD.said_n IS NOT NULL BEGIN \{d("OLD.thread")} END;",
    "CREATE TRIGGER recent_chat_entry_before_add BEFORE INSERT ON entries WHEN \{inserted_said} BEGIN \{d("NEW.thread")} END;",
    "CREATE TRIGGER recent_chat_entry_before_change BEFORE UPDATE OF thread, n, ts ON entries WHEN \{displaced_said} BEGIN \{d("NEW.thread")} END;",
    "CREATE TRIGGER recent_chat_entry_before_rowid_add BEFORE INSERT ON entries WHEN EXISTS (\{displaced_entry}) BEGIN \{d(evicted_thread)} END;",
    "CREATE TRIGGER recent_chat_entry_before_rowid_change BEFORE UPDATE ON entries WHEN OLD.rowid IS NOT NEW.rowid AND EXISTS (\{displaced_entry}) BEGIN \{d(evicted_thread)} END;",
    "CREATE TRIGGER recent_chat_entry_change AFTER UPDATE OF thread, n, kind, at ON entries BEGIN \{d("OLD.thread")} \{d("NEW.thread")} END;",
    "CREATE TRIGGER recent_chat_entry_drop AFTER DELETE ON entries BEGIN \{d("OLD.thread")} END;",
  ].join("\n")
}

///|
pub fn install_global(db : @sql.Db) -> Unit raise {
  install(db, "global", global_schema())
}

// The workspaces' journals (chat-list-scope-journal.ts). No INSERT OR IGNORE in a trigger: an outer old writer's
// INSERT OR REPLACE would override it; the existence checks coalesce work and keep the revision a builder compares.

///|
fn mark_session(
  key : String,
  workspace : String,
  home_when~ : String = "1",
) -> String {
  let refs = "((\{home_when}) AND (EXISTS (SELECT 1 FROM thread_sessions INDEXED BY thread_sessions_session WHERE session = \{key} LIMIT 1) OR EXISTS (SELECT 1 FROM threads INDEXED BY threads_home WHERE home = \{key} LIMIT 1)))"
  "UPDATE recent_scope_session_dirty SET revision = revision + 1 WHERE kind = 1 AND ws = \{workspace} AND session = \{key}; INSERT INTO recent_scope_session_dirty(kind, ws, session, revision) SELECT 1, \{workspace}, \{key}, 1 WHERE \{key} IS NOT NULL AND \{workspace} IS NOT NULL AND EXISTS (SELECT 1 FROM recent_scope_tracked WHERE kind = 1 AND ws = \{workspace}) AND NOT EXISTS (SELECT 1 FROM recent_scope_session_dirty WHERE kind = 1 AND ws = \{workspace} AND session = \{key}); UPDATE recent_scope_session_dirty SET revision = revision + 1 WHERE kind = 0 AND ws = '' AND session = \{key} AND \{refs}; INSERT INTO recent_scope_session_dirty(kind, ws, session, revision) SELECT 0, '', \{key}, 1 WHERE \{key} IS NOT NULL AND \{refs} AND EXISTS (SELECT 1 FROM recent_scope_tracked WHERE kind = 0 AND ws = '') AND NOT EXISTS (SELECT 1 FROM recent_scope_session_dirty WHERE kind = 0 AND ws = '' AND session = \{key});"
}

///|
/// A session another one conflicts with, by `by` (key, token or rowid): its `column`.
fn session_conflict(column : String, by : String, extra : String) -> String {
  "(SELECT \{column} FROM sessions WHERE \{by} = NEW.\{by} \{extra})"
}

///|
fn mark_session_conflict(by : String, extra : String) -> String {
  mark_session(
    session_conflict("key", by, extra),
    session_conflict("ws", by, extra),
  )
}

///|
let changes_home : String = "OLD.key IS NOT NEW.key OR (OLD.ws IS NULL AND NEW.ws IS NOT NULL) OR (OLD.ws IS NOT NULL AND NEW.ws IS NULL)"

///|
fn mark_member(
  thread : String,
  session : String,
  home~ : Bool = false,
) -> String {
  let ws = "(SELECT ws FROM sessions WHERE key = \{session})"
  let relevant = if home {
    "1"
  } else {
    "(EXISTS (SELECT 1 FROM threads WHERE id = \{thread} AND home IS NULL) OR EXISTS (SELECT 1 FROM recent_scope_visibility_dirty WHERE thread = \{thread}))"
  }
  "UPDATE recent_scope_member_dirty SET revision = revision + 1 WHERE ws = \{ws} AND thread = \{thread} AND session = \{session} AND \{relevant}; INSERT INTO recent_scope_member_dirty(ws, thread, session, revision) SELECT \{ws}, \{thread}, \{session}, 1 WHERE \{ws} IS NOT NULL AND \{thread} IS NOT NULL AND \{session} IS NOT NULL AND \{relevant} AND EXISTS (SELECT 1 FROM recent_scope_tracked WHERE kind = 1 AND ws = \{ws}) AND NOT EXISTS (SELECT 1 FROM recent_scope_member_dirty WHERE ws = \{ws} AND thread = \{thread} AND session = \{session});"
}

///|
fn member_conflict(column : String, extra : String) -> String {
  "(SELECT \{column} FROM thread_sessions WHERE rowid = NEW.rowid \{extra})"
}

///|
/// (also memberships hidden by a named home: if that home changes, a workspace can check this key directly)
fn add_candidate(thread : String, session : String) -> String {
  "INSERT INTO recent_scope_candidates(ws, thread, session) SELECT s.ws, \{thread}, \{session} FROM sessions s JOIN recent_scope_tracked t ON t.kind = 1 AND t.ws = s.ws WHERE s.key = \{session} AND \{thread} IS NOT NULL AND NOT EXISTS (SELECT 1 FROM recent_scope_candidates c WHERE c.ws = s.ws AND c.thread = \{thread} AND c.session = \{session});"
}

///|
fn remove_candidate(thread : String, session : String) -> String {
  "DELETE FROM recent_scope_candidates WHERE ws = (SELECT ws FROM sessions WHERE key = \{session}) AND thread = \{thread} AND session = \{session};"
}

///|
/// A chat's first 64 members in tracked workspaces, journaled (`recentScopeHomeMemberQueries`).
fn home_member_queries(thread : String) -> String {
  let members = "SELECT s.ws AS ws, \{thread} AS thread, m.session AS session FROM (SELECT session FROM thread_sessions WHERE thread = \{thread} ORDER BY session LIMIT 64) m JOIN sessions s ON s.key = m.session JOIN recent_scope_tracked r ON r.kind = 1 AND r.ws = s.ws"
  "UPDATE recent_scope_member_dirty SET revision = revision + 1 WHERE (ws, thread, session) IN (\{members}); INSERT INTO recent_scope_member_dirty(ws, thread, session, revision) SELECT m.ws, m.thread, m.session, 1 FROM (\{members}) m WHERE NOT EXISTS (SELECT 1 FROM recent_scope_member_dirty d WHERE d.ws = m.ws AND d.thread = m.thread AND d.session = m.session);"
}

///|
let many_home_members : String = "EXISTS (SELECT 1 FROM thread_sessions WHERE thread = NEW.id LIMIT 1 OFFSET 64)"

///|
fn mark_visibility(thread : String, needs_new~ : String = "1") -> String {
  let home = "(SELECT s.ws FROM threads t JOIN sessions s ON s.key = t.home WHERE t.id = \{thread})"
  let ambiguous = "EXISTS (SELECT 1 FROM threads t WHERE t.id = \{thread} AND t.home IS NULL AND EXISTS (SELECT 1 FROM thread_sessions m WHERE m.thread = t.id LIMIT 1))"
  "UPDATE recent_scope_visibility_dirty SET revision = revision + 1, home_ws = \{home}, ambiguous = \{ambiguous} WHERE thread = \{thread}; INSERT INTO recent_scope_visibility_dirty(thread, revision, home_ws, ambiguous) SELECT \{thread}, 1, \{home}, \{ambiguous} WHERE \{thread} IS NOT NULL AND (\{needs_new}) AND EXISTS (SELECT 1 FROM recent_scope_tracked LIMIT 1) AND NOT EXISTS (SELECT 1 FROM recent_scope_visibility_dirty WHERE thread = \{thread});"
}

///|
let new_visibility : String = "EXISTS (SELECT 1 FROM sessions s JOIN recent_scope_tracked r ON r.kind = 1 AND r.ws = s.ws WHERE s.key = NEW.home) OR (NEW.home IS NULL AND EXISTS (SELECT 1 FROM thread_sessions WHERE thread = NEW.id LIMIT 1)) OR EXISTS (SELECT 1 FROM recent_scope_sources INDEXED BY recent_scope_sources_thread WHERE thread = NEW.id LIMIT 1)"

///|
fn member_makes_ambiguous(thread : String) -> String {
  "UPDATE recent_scope_visibility_dirty SET ambiguous = 1 WHERE thread = \{thread} AND EXISTS (SELECT 1 FROM threads WHERE id = \{thread} AND home IS NULL);"
}

///|
/// A chat's order change for its workspaces; one in more than 64 deferred to the dispatch.
fn mark_order(thread : String) -> String {
  let many = "EXISTS (SELECT 1 FROM recent_scope_rows INDEXED BY recent_scope_rows_thread WHERE thread = \{thread} LIMIT 1 OFFSET 64)"
  "INSERT INTO recent_scope_order_dirty(ws, thread) SELECT r.ws, r.thread FROM (SELECT ws, thread FROM recent_scope_rows INDEXED BY recent_scope_rows_thread WHERE thread = \{thread} ORDER BY ws LIMIT 64) r WHERE NOT (\{many}) AND NOT EXISTS (SELECT 1 FROM recent_scope_order_dirty d WHERE d.ws = r.ws AND d.thread = r.thread); INSERT INTO recent_scope_order_dispatch(thread, after_ws) SELECT \{thread}, NULL WHERE \{thread} IS NOT NULL AND (\{many}) AND NOT EXISTS (SELECT 1 FROM recent_scope_order_dispatch WHERE thread = \{thread});"
}

///|
pub fn scope_schema() -> String {
  let o = mark_order
  let not_old_key = "AND key IS NOT OLD.key"
  let not_old_rowid = "AND rowid IS NOT OLD.rowid"
  let session_changed = "OLD.key IS NOT NEW.key OR OLD.ws IS NOT NEW.ws OR OLD.token IS NOT NEW.token OR OLD.connect IS NOT NEW.connect"
  let member_changed = "OLD.thread IS NOT NEW.thread OR OLD.session IS NOT NEW.session OR OLD.rowid IS NOT NEW.rowid"
  [
    "CREATE TABLE recent_scope_tracked (kind INTEGER NOT NULL, ws TEXT NOT NULL, total INTEGER NOT NULL DEFAULT 0, complete INTEGER NOT NULL DEFAULT 0, scan_connect TEXT, scan_after INTEGER, scan_done INTEGER NOT NULL DEFAULT 0, scan_high INTEGER, scan_connections INTEGER NOT NULL DEFAULT 0, scan_rowids INTEGER NOT NULL DEFAULT 0, scan_session TEXT, scan_phase TEXT, scan_thread_after INTEGER, PRIMARY KEY(kind, ws)) WITHOUT ROWID;",
    "CREATE TABLE recent_scope_session_dirty (kind INTEGER NOT NULL, ws TEXT NOT NULL, session TEXT NOT NULL, revision INTEGER NOT NULL, PRIMARY KEY(kind, ws, session)) WITHOUT ROWID;",
    "CREATE TABLE recent_scope_session_work (ws TEXT NOT NULL, session TEXT NOT NULL, revision INTEGER NOT NULL, phase TEXT NOT NULL, after INTEGER, PRIMARY KEY(ws, session)) WITHOUT ROWID;",
    "CREATE TABLE recent_scope_candidates (ws TEXT NOT NULL, thread INTEGER NOT NULL, session TEXT NOT NULL, PRIMARY KEY(ws, thread, session)) WITHOUT ROWID;",
    "CREATE INDEX recent_scope_candidates_session ON recent_scope_candidates(ws, session, thread);",
    "CREATE TABLE recent_scope_member_dirty (ws TEXT NOT NULL, thread INTEGER NOT NULL, session TEXT NOT NULL, revision INTEGER NOT NULL, PRIMARY KEY(ws, thread, session)) WITHOUT ROWID;",
    "CREATE TABLE recent_scope_order_dirty (ws TEXT NOT NULL, thread INTEGER NOT NULL, PRIMARY KEY(ws, thread)) WITHOUT ROWID;",
    "CREATE TABLE recent_scope_order_dispatch (thread INTEGER PRIMARY KEY, after_ws TEXT);",
    "CREATE TABLE recent_scope_order_turn (id INTEGER PRIMARY KEY CHECK (id = 1), after_thread INTEGER, through_thread INTEGER);",
    "INSERT INTO recent_scope_order_turn VALUES (1, NULL, NULL);",
    "CREATE TABLE recent_scope_visibility_dirty (thread INTEGER PRIMARY KEY, revision INTEGER NOT NULL, home_ws TEXT, ambiguous INTEGER NOT NULL);",
    "CREATE INDEX recent_scope_visibility_home ON recent_scope_visibility_dirty(home_ws) WHERE home_ws IS NOT NULL;",
    "CREATE TABLE recent_scope_visibility_work (thread INTEGER PRIMARY KEY, revision INTEGER NOT NULL, phase TEXT NOT NULL, after_ws TEXT, after_session TEXT);",
    "CREATE TABLE recent_scope_visibility_turn (id INTEGER PRIMARY KEY CHECK (id = 1), after_thread INTEGER, through_thread INTEGER);",
    "INSERT INTO recent_scope_visibility_turn VALUES (1, NULL, NULL);",
    "CREATE TABLE recent_scope_sources (ws TEXT NOT NULL, thread INTEGER NOT NULL, session TEXT NOT NULL, PRIMARY KEY(ws, thread, session)) WITHOUT ROWID;",
    "CREATE INDEX recent_scope_sources_session ON recent_scope_sources(ws, session, thread);",
    "CREATE INDEX recent_scope_sources_thread ON recent_scope_sources(thread, ws, session);",
    "CREATE TABLE recent_scope_rows (ws TEXT NOT NULL, thread INTEGER NOT NULL, at INTEGER NOT NULL, said_at INTEGER NOT NULL, created_at INTEGER NOT NULL, PRIMARY KEY(ws, thread)) WITHOUT ROWID;",
    "CREATE INDEX recent_scope_order ON recent_scope_rows(ws, at DESC, said_at DESC, created_at DESC, thread DESC);",
    "CREATE INDEX recent_scope_rows_thread ON recent_scope_rows(thread, ws);",
    // (REPLACE can remove another session without a DELETE trigger, whether it conflicts by key or token)
    "CREATE TRIGGER recent_scope_session_before_add BEFORE INSERT ON sessions BEGIN \{mark_session_conflict("key", "")} \{mark_session_conflict("token", "")} \{mark_session_conflict("rowid", "")} END;",
    "CREATE TRIGGER recent_scope_session_add AFTER INSERT ON sessions BEGIN \{mark_session("NEW.key", "NEW.ws")} END;",
    "CREATE TRIGGER recent_scope_session_before_change BEFORE UPDATE OF key, ws, token, connect ON sessions WHEN \{session_changed} BEGIN \{mark_session("OLD.key", "OLD.ws", home_when=changes_home)} \{mark_session_conflict("key", not_old_key)} \{mark_session_conflict("token", not_old_key)} END;",
    "CREATE TRIGGER recent_scope_session_change AFTER UPDATE OF key, ws, token, connect ON sessions WHEN \{session_changed} BEGIN \{mark_session("NEW.key", "NEW.ws", home_when=changes_home)} END;",
    // (the initial scan also uses rowid: its aliases can move a row across the saved boundary, or REPLACE another)
    "CREATE TRIGGER recent_scope_session_before_rowid BEFORE UPDATE ON sessions WHEN OLD.rowid IS NOT NEW.rowid BEGIN \{mark_session("OLD.key", "OLD.ws", home_when="0")} \{mark_session_conflict("rowid", not_old_rowid)} END;",
    "CREATE TRIGGER recent_scope_session_after_rowid AFTER UPDATE ON sessions WHEN OLD.rowid IS NOT NEW.rowid BEGIN \{mark_session("NEW.key", "NEW.ws", home_when="0")} END;",
    "CREATE TRIGGER recent_scope_session_drop BEFORE DELETE ON sessions BEGIN \{mark_session("OLD.key", "OLD.ws")} END;",
    // (a rowid REPLACE can evict a different membership without firing its DELETE trigger)
    "CREATE TRIGGER recent_scope_member_before_add BEFORE INSERT ON thread_sessions BEGIN \{mark_member(member_conflict("thread", ""), member_conflict("session", ""), home=true)} END;",
    "CREATE TRIGGER recent_scope_member_add AFTER INSERT ON thread_sessions BEGIN \{add_candidate("NEW.thread", "NEW.session")} \{mark_member("NEW.thread", "NEW.session")} \{member_makes_ambiguous("NEW.thread")} END;",
    "CREATE TRIGGER recent_scope_member_before_change BEFORE UPDATE ON thread_sessions WHEN \{member_changed} BEGIN \{mark_member("OLD.thread", "OLD.session", home=true)} \{mark_member(member_conflict("thread", not_old_rowid), member_conflict("session", not_old_rowid), home=true)} END;",
    "CREATE TRIGGER recent_scope_member_change AFTER UPDATE ON thread_sessions WHEN \{member_changed} BEGIN \{remove_candidate("OLD.thread", "OLD.session")} \{add_candidate("NEW.thread", "NEW.session")} \{mark_member("NEW.thread", "NEW.session")} \{member_makes_ambiguous("NEW.thread")} END;",
    "CREATE TRIGGER recent_scope_member_drop BEFORE DELETE ON thread_sessions BEGIN \{mark_member("OLD.thread", "OLD.session")} \{remove_candidate("OLD.thread", "OLD.session")} END;",
    // (rows added behind a running distributor's cursor are marked too)
    "CREATE TRIGGER recent_scope_order_row_add AFTER INSERT ON recent_scope_rows WHEN EXISTS (SELECT 1 FROM recent_scope_order_dispatch WHERE thread = NEW.thread) BEGIN INSERT INTO recent_scope_order_dirty(ws, thread) SELECT NEW.ws, NEW.thread WHERE NOT EXISTS (SELECT 1 FROM recent_scope_order_dirty WHERE ws = NEW.ws AND thread = NEW.thread); END;",
    "CREATE TRIGGER recent_scope_order_thread_before_add BEFORE INSERT ON threads BEGIN \{o("NEW.id")} \{o(conflicting_thread)} \{mark_visibility("(SELECT id FROM threads WHERE id = NEW.id)")} \{mark_visibility(conflicting_thread)} END;",
    "CREATE TRIGGER recent_scope_order_thread_before_change BEFORE UPDATE OF id, surface, channel, thread_ts ON threads BEGIN \{o(conflicting_thread)} \{mark_visibility(conflicting_thread)} END;",
    "CREATE TRIGGER recent_scope_order_thread_add AFTER INSERT ON threads BEGIN \{o("NEW.id")} \{mark_visibility("NEW.id", needs_new=new_visibility)} END;",
    "CREATE TRIGGER recent_scope_order_thread_change AFTER UPDATE OF id, created_at ON threads BEGIN \{o("OLD.id")} END;",
    "CREATE TRIGGER recent_scope_order_thread_move AFTER UPDATE OF id ON threads WHEN OLD.id IS NOT NEW.id BEGIN \{o("NEW.id")} END;",
    "CREATE TRIGGER recent_scope_visibility_thread_change AFTER UPDATE OF id, home ON threads WHEN (OLD.id IS NOT NEW.id OR OLD.home IS NOT NEW.home) AND (OLD.id IS NOT NEW.id OR ((OLD.home IS NULL OR NEW.home IS NULL) AND \{many_home_members}) OR EXISTS (SELECT 1 FROM recent_scope_visibility_dirty WHERE thread = OLD.id)) BEGIN \{mark_visibility("OLD.id")} END;",
    // (with two named homes only those sessions can contribute: each journaled directly)
    "CREATE TRIGGER recent_scope_named_home_change AFTER UPDATE OF home ON threads WHEN OLD.id IS NEW.id AND OLD.home IS NOT NULL AND NEW.home IS NOT NULL AND OLD.home IS NOT NEW.home BEGIN \{mark_member("NEW.id", "OLD.home", home=true)} \{mark_member("NEW.id", "NEW.home", home=true)} END;",
    // (a small shared chat marks its old and new home and each member directly; a larger one takes the visibility pass)
    "CREATE TRIGGER recent_scope_small_shared_home_change AFTER UPDATE OF home ON threads WHEN OLD.id IS NEW.id AND OLD.home IS NOT NEW.home AND (OLD.home IS NULL OR NEW.home IS NULL) AND NOT \{many_home_members} AND NOT EXISTS (SELECT 1 FROM recent_scope_visibility_dirty WHERE thread = OLD.id) BEGIN \{mark_member("NEW.id", "OLD.home", home=true)} \{mark_member("NEW.id", "NEW.home", home=true)} \{home_member_queries("NEW.id")} END;",
    "CREATE TRIGGER recent_scope_visibility_thread_move AFTER UPDATE OF id ON threads WHEN OLD.id IS NOT NEW.id BEGIN \{mark_visibility("NEW.id")} END;",
    "CREATE TRIGGER recent_scope_order_thread_drop AFTER DELETE ON threads BEGIN \{o("OLD.id")} \{mark_visibility("OLD.id")} END;",
    "CREATE TRIGGER recent_scope_order_state_add AFTER INSERT ON thread_state BEGIN \{o("NEW.thread")} END;",
    "CREATE TRIGGER recent_scope_order_state_change AFTER UPDATE OF thread, said_n ON thread_state WHEN OLD.thread IS NOT NEW.thread OR OLD.said_n IS NOT NEW.said_n BEGIN \{o("OLD.thread")} END;",
    "CREATE TRIGGER recent_scope_order_state_move AFTER UPDATE OF thread ON thread_state WHEN OLD.thread IS NOT NEW.thread BEGIN \{o("NEW.thread")} END;",
    "CREATE TRIGGER recent_scope_order_state_drop AFTER DELETE ON thread_state WHEN OLD.said_n IS NOT NULL BEGIN \{o("OLD.thread")} END;",
    "CREATE TRIGGER recent_scope_order_entry_before_add BEFORE INSERT ON entries WHEN \{inserted_said} BEGIN \{o("NEW.thread")} END;",
    "CREATE TRIGGER recent_scope_order_entry_before_change BEFORE UPDATE OF thread, n, ts ON entries WHEN \{displaced_said} BEGIN \{o("NEW.thread")} END;",
    "CREATE TRIGGER recent_scope_order_entry_before_rowid_add BEFORE INSERT ON entries WHEN EXISTS (\{displaced_entry}) BEGIN \{o(evicted_thread)} END;",
    "CREATE TRIGGER recent_scope_order_entry_before_rowid_change BEFORE UPDATE ON entries WHEN OLD.rowid IS NOT NEW.rowid AND EXISTS (\{displaced_entry}) BEGIN \{o(evicted_thread)} END;",
    "CREATE TRIGGER recent_scope_order_entry_change AFTER UPDATE OF thread, n, kind, at ON entries BEGIN \{o("OLD.thread")} END;",
    "CREATE TRIGGER recent_scope_order_entry_move AFTER UPDATE OF thread ON entries WHEN OLD.thread IS NOT NEW.thread BEGIN \{o("NEW.thread")} END;",
    "CREATE TRIGGER recent_scope_order_entry_drop AFTER DELETE ON entries BEGIN \{o("OLD.thread")} END;",
  ].join("\n")
}

///|
pub fn install_scope(db : @sql.Db) -> Unit raise {
  install(db, "scope", scope_schema())
}

///|
/// A scope's work begun (kind 0: the default home; 1: the workspace `ws`), its scan bounded by the sessions now.
fn track(db : @sql.Db, kind : Int, ws : String) -> Unit raise {
  ignore(
    db.run(
      "INSERT INTO recent_scope_tracked(kind, ws, scan_high, scan_done) SELECT ?1, ?2, (SELECT MAX(rowid) FROM sessions), CASE WHEN ?1 = 1 AND NOT EXISTS (SELECT 1 FROM sessions LIMIT 1) THEN 1 ELSE 0 END WHERE NOT EXISTS (SELECT 1 FROM recent_scope_tracked WHERE kind = ?1 AND ws = ?2)",
      [Json::number(kind.to_double()), Json::string(ws)],
    ),
  )
}

// The default part of home (chat-list-home-index.ts).

///|
fn home_mark(thread : String, when~ : String = "1") -> String {
  "UPDATE recent_home_dirty SET revision = revision + 1 WHERE thread = \{thread} AND (\{when}); INSERT INTO recent_home_dirty(thread, revision) SELECT \{thread}, 1 WHERE \{thread} IS NOT NULL AND (\{when}) AND NOT EXISTS (SELECT 1 FROM recent_home_dirty WHERE thread = \{thread});"
}

///|
/// (once a chat has a home, that session alone decides default-home membership)
fn home_mark_member(thread : String) -> String {
  home_mark(
    thread,
    when="EXISTS (SELECT 1 FROM threads WHERE id = \{thread} AND home IS NULL)",
  )
}

///|
fn home_mark_order(thread : String) -> String {
  "INSERT INTO recent_home_order_dirty(thread) SELECT \{thread} WHERE \{thread} IS NOT NULL AND EXISTS (SELECT 1 FROM recent_home_rows WHERE thread = \{thread}) AND NOT EXISTS (SELECT 1 FROM recent_home_order_dirty WHERE thread = \{thread});"
}

///|
pub fn home_schema() -> String {
  let m = home_mark_member
  let o = home_mark_order
  let conflicting_member = "(SELECT thread FROM thread_sessions WHERE rowid = NEW.rowid)"
  [
    "CREATE TABLE recent_home_meta (id INTEGER PRIMARY KEY CHECK (id = 1), cursor INTEGER, through INTEGER, scan_done INTEGER NOT NULL, total INTEGER NOT NULL);",
    "INSERT INTO recent_home_meta SELECT 1, NULL, (SELECT MAX(id) FROM threads), NOT EXISTS (SELECT 1 FROM threads LIMIT 1), 0;",
    "CREATE TABLE recent_home_dirty (thread INTEGER PRIMARY KEY, revision INTEGER NOT NULL);",
    "CREATE TABLE recent_home_order_dirty (thread INTEGER PRIMARY KEY);",
    "CREATE TABLE recent_home_work (thread INTEGER PRIMARY KEY, revision INTEGER NOT NULL, after_session TEXT, seen INTEGER NOT NULL);",
    "CREATE TABLE recent_home_session_work (session TEXT PRIMARY KEY, revision INTEGER NOT NULL, phase TEXT NOT NULL, after INTEGER);",
    "CREATE TABLE recent_home_rows (thread INTEGER PRIMARY KEY, at INTEGER NOT NULL, said_at INTEGER NOT NULL, created_at INTEGER NOT NULL);",
    "CREATE INDEX recent_home_order ON recent_home_rows(at DESC, said_at DESC, created_at DESC, thread DESC);",
    "CREATE TRIGGER recent_home_thread_before_add BEFORE INSERT ON threads BEGIN \{home_mark("(SELECT id FROM threads WHERE id = NEW.id)")} \{home_mark(conflicting_thread)} END;",
    "CREATE TRIGGER recent_home_thread_before_change BEFORE UPDATE OF id, surface, channel, thread_ts ON threads BEGIN \{home_mark(conflicting_thread)} END;",
    "CREATE TRIGGER recent_home_thread_add AFTER INSERT ON threads BEGIN \{home_mark("NEW.id")} END;",
    "CREATE TRIGGER recent_home_thread_change AFTER UPDATE OF id, home ON threads WHEN OLD.id IS NOT NEW.id OR (OLD.home IS NOT NEW.home AND (OLD.home IS NULL OR NEW.home IS NULL OR NOT EXISTS (SELECT 1 FROM sessions WHERE key = OLD.home AND ws IS NOT NULL) OR NOT EXISTS (SELECT 1 FROM sessions WHERE key = NEW.home AND ws IS NOT NULL))) BEGIN \{home_mark("OLD.id")} END;",
    "CREATE TRIGGER recent_home_thread_move AFTER UPDATE OF id ON threads WHEN OLD.id IS NOT NEW.id BEGIN \{home_mark("NEW.id")} END;",
    "CREATE TRIGGER recent_home_thread_order AFTER UPDATE OF created_at ON threads BEGIN \{o("NEW.id")} END;",
    "CREATE TRIGGER recent_home_thread_drop AFTER DELETE ON threads BEGIN \{home_mark("OLD.id")} END;",
    "CREATE TRIGGER recent_home_member_before_add BEFORE INSERT ON thread_sessions BEGIN \{m(conflicting_member)} END;",
    "CREATE TRIGGER recent_home_member_add AFTER INSERT ON thread_sessions BEGIN \{m("NEW.thread")} END;",
    "CREATE TRIGGER recent_home_member_before_change BEFORE UPDATE OF thread, session, rowid ON thread_sessions WHEN OLD.thread IS NOT NEW.thread OR OLD.session IS NOT NEW.session OR OLD.rowid IS NOT NEW.rowid BEGIN \{m("OLD.thread")} \{m(conflicting_member)} END;",
    "CREATE TRIGGER recent_home_member_change AFTER UPDATE OF thread, session ON thread_sessions WHEN OLD.thread IS NOT NEW.thread OR OLD.session IS NOT NEW.session BEGIN \{m("NEW.thread")} END;",
    "CREATE TRIGGER recent_home_member_drop BEFORE DELETE ON thread_sessions BEGIN \{m("OLD.thread")} END;",
    "CREATE TRIGGER recent_home_state_add AFTER INSERT ON thread_state BEGIN \{o("NEW.thread")} END;",
    "CREATE TRIGGER recent_home_state_change AFTER UPDATE OF thread, said_n ON thread_state WHEN OLD.thread IS NOT NEW.thread OR OLD.said_n IS NOT NEW.said_n BEGIN \{o("OLD.thread")} END;",
    "CREATE TRIGGER recent_home_state_move AFTER UPDATE OF thread ON thread_state WHEN OLD.thread IS NOT NEW.thread BEGIN \{o("NEW.thread")} END;",
    "CREATE TRIGGER recent_home_state_drop AFTER DELETE ON thread_state WHEN OLD.said_n IS NOT NULL BEGIN \{o("OLD.thread")} END;",
    "CREATE TRIGGER recent_home_entry_before_add BEFORE INSERT ON entries WHEN \{inserted_said} BEGIN \{o("NEW.thread")} END;",
    "CREATE TRIGGER recent_home_entry_before_change BEFORE UPDATE OF thread, n, ts ON entries WHEN \{displaced_said} BEGIN \{o("NEW.thread")} END;",
    "CREATE TRIGGER recent_home_entry_before_rowid_add BEFORE INSERT ON entries WHEN EXISTS (\{displaced_entry}) BEGIN \{o(evicted_thread)} END;",
    "CREATE TRIGGER recent_home_entry_before_rowid_change BEFORE UPDATE ON entries WHEN OLD.rowid IS NOT NEW.rowid AND EXISTS (\{displaced_entry}) BEGIN \{o(evicted_thread)} END;",
    "CREATE TRIGGER recent_home_entry_change AFTER UPDATE OF thread, n, kind, at ON entries BEGIN \{o("OLD.thread")} END;",
    "CREATE TRIGGER recent_home_entry_move AFTER UPDATE OF thread ON entries WHEN OLD.thread IS NOT NEW.thread BEGIN \{o("NEW.thread")} END;",
    "CREATE TRIGGER recent_home_entry_drop AFTER DELETE ON entries BEGIN \{o("OLD.thread")} END;",
  ].join("\n")
}

///|
/// The default home's index, its sessions journaled from the same transaction on (`installRecentHomeIndex`).
pub fn install_home(db : @sql.Db) -> Unit raise {
  install_scope(db)
  install(db, "home", home_schema(), more=() => track(db, 0, ""))
}

// Home's intersection with a named workspace (chat-list-home-overlap.ts).

///|
fn overlap_mark(thread : String) -> String {
  "UPDATE recent_home_overlap_dirty SET revision = revision + 1 WHERE thread = \{thread}; INSERT INTO recent_home_overlap_dirty(thread, revision) SELECT \{thread}, 1 WHERE \{thread} IS NOT NULL AND NOT EXISTS (SELECT 1 FROM recent_home_overlap_dirty WHERE thread = \{thread});"
}

///|
pub fn overlap_schema() -> String {
  [
    "CREATE TABLE recent_home_overlap_meta (id INTEGER PRIMARY KEY CHECK (id = 1), cursor INTEGER, through INTEGER, scan_done INTEGER NOT NULL);",
    "INSERT INTO recent_home_overlap_meta SELECT 1, NULL, (SELECT MAX(thread) FROM recent_home_rows), NOT EXISTS (SELECT 1 FROM recent_home_rows LIMIT 1);",
    "CREATE TABLE recent_home_overlap_dirty (thread INTEGER PRIMARY KEY, revision INTEGER NOT NULL);",
    "CREATE TABLE recent_home_overlap_work (thread INTEGER PRIMARY KEY, revision INTEGER NOT NULL, after_ws TEXT);",
    "CREATE TABLE recent_home_overlap_rows (ws TEXT NOT NULL, thread INTEGER NOT NULL, PRIMARY KEY(ws, thread)) WITHOUT ROWID;",
    "CREATE INDEX recent_home_overlap_by_thread ON recent_home_overlap_rows(thread, ws);",
    "CREATE TABLE recent_home_overlap_totals (ws TEXT PRIMARY KEY, total INTEGER NOT NULL) WITHOUT ROWID;",
    "CREATE TRIGGER recent_home_overlap_add AFTER INSERT ON recent_home_overlap_rows BEGIN INSERT INTO recent_home_overlap_totals(ws, total) SELECT NEW.ws, 0 WHERE NOT EXISTS (SELECT 1 FROM recent_home_overlap_totals WHERE ws = NEW.ws); UPDATE recent_home_overlap_totals SET total = total + 1 WHERE ws = NEW.ws; END;",
    "CREATE TRIGGER recent_home_overlap_drop AFTER DELETE ON recent_home_overlap_rows BEGIN UPDATE recent_home_overlap_totals SET total = total - 1 WHERE ws = OLD.ws; END;",
    "CREATE TRIGGER recent_home_overlap_scope_add AFTER INSERT ON recent_scope_rows BEGIN INSERT INTO recent_home_overlap_rows(ws, thread) SELECT NEW.ws, NEW.thread WHERE EXISTS (SELECT 1 FROM recent_home_rows WHERE thread = NEW.thread) AND NOT EXISTS (SELECT 1 FROM recent_home_overlap_rows WHERE ws = NEW.ws AND thread = NEW.thread); END;",
    "CREATE TRIGGER recent_home_overlap_scope_drop AFTER DELETE ON recent_scope_rows BEGIN DELETE FROM recent_home_overlap_rows WHERE ws = OLD.ws AND thread = OLD.thread; END;",
    "CREATE TRIGGER recent_home_overlap_home_add AFTER INSERT ON recent_home_rows BEGIN \{overlap_mark("NEW.thread")} END;",
    "CREATE TRIGGER recent_home_overlap_home_drop AFTER DELETE ON recent_home_rows BEGIN \{overlap_mark("OLD.thread")} END;",
  ].join("\n")
}

///|
pub fn install_overlap(db : @sql.Db) -> Unit raise {
  install_home(db)
  install(db, "overlap", overlap_schema())
}
