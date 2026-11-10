// The search's candidate scopes (station/src/search/scope-index.ts), installed empty with their writers, and their old
// state prepared and repaired in bounded steps (scope-prepare.ts `SearchScopePreparation`), here for the MoonBit
// builder. Thread ids and rowids are read and bound as text (an id past 2^53 kept exact); a membership's or a session's
// key is bound as SQLite has it, by its bytes and storage class, so a repair seeks exactly what it marked.

///|
fn safe(value : String) -> String {
  "(typeof(\{value}) = 'text' AND instr(\{value}, char(0)) = 0 AND \{value} NOT GLOB '*[^ -~]*')"
}

///|
fn member_kind() -> String {
  "CASE WHEN NOT \{safe("m.session")} THEN 2\n  WHEN s.key IS NULL OR s.ws IS NULL THEN 0 WHEN NOT \{safe("s.ws")} THEN 2 ELSE 1 END"
}

///|
fn member_ws() -> String {
  "CASE WHEN \{safe("m.session")} AND s.key IS NOT NULL AND s.ws IS NOT NULL AND \{safe("s.ws")}\n  THEN s.ws ELSE '' END"
}

///|
/// scope-index.ts `INSERT_SEARCH_SCOPE_MEMBER`: `?1` the thread, `?2` the session.
fn insert_member_sql() -> String {
  "INSERT INTO search_scope_members(thread, session, kind, ws)\n  SELECT m.thread, m.session, \{member_kind()}, \{member_ws()} FROM thread_sessions m LEFT JOIN sessions s ON s.key = m.session\n  WHERE m.thread = ?1 AND m.session = ?2 AND NOT EXISTS\n    (SELECT 1 FROM search_scope_members x WHERE x.thread = m.thread AND x.session = m.session)"
}

///|
fn update_orphan(thread : String) -> String {
  "\n  DELETE FROM search_scope_orphans WHERE thread = \{thread};\n  INSERT INTO search_scope_orphans(thread) SELECT \{thread} WHERE \{thread} IS NOT NULL\n    AND EXISTS (SELECT 1 FROM threads WHERE id = \{thread})\n    AND NOT EXISTS (SELECT 1 FROM thread_sessions WHERE thread = \{thread})\n    AND NOT EXISTS (SELECT 1 FROM search_scope_orphans WHERE thread = \{thread});"
}

///|
fn mark_member(thread : String, session : String) -> String {
  "\n  INSERT INTO search_scope_members_dirty(thread, session) SELECT \{thread}, \{session}\n    WHERE \{thread} IS NOT NULL AND \{session} IS NOT NULL AND NOT EXISTS\n      (SELECT 1 FROM search_scope_members_dirty WHERE thread = \{thread} AND session = \{session});"
}

///|
fn mark_thread(thread : String) -> String {
  "\n  INSERT INTO search_scope_threads_dirty(thread) SELECT \{thread} WHERE \{thread} IS NOT NULL\n    AND NOT EXISTS (SELECT 1 FROM search_scope_threads_dirty WHERE thread = \{thread});"
}

///|
fn mark_session(session : String) -> String {
  "\n  UPDATE search_scope_sessions_dirty SET after_rowid = NULL WHERE session = \{session};\n  INSERT INTO search_scope_sessions_dirty(session, after_rowid) SELECT \{session}, NULL\n    WHERE \{session} IS NOT NULL AND EXISTS (SELECT 1 FROM thread_sessions INDEXED BY thread_sessions_session WHERE session = \{session})\n      AND NOT EXISTS (SELECT 1 FROM search_scope_sessions_dirty WHERE session = \{session});"
}

///|
fn member_by_rowid(part : String, condition? : String = "") -> String {
  "(SELECT \{part} FROM thread_sessions WHERE rowid = NEW.rowid \{condition})"
}

///|
fn member_by_key(part : String) -> String {
  "(SELECT \{part} FROM thread_sessions WHERE thread = NEW.thread AND session = NEW.session)"
}

///|
fn session_by(condition : String) -> String {
  "(SELECT key FROM sessions WHERE \{condition})"
}

///|
let thread_by_address : String = "(SELECT id FROM threads WHERE surface = NEW.surface AND channel = NEW.channel AND thread_ts = NEW.thread_ts)"

///|
fn insert_member(thread : String, session : String) -> String {
  insert_member_sql().replace_all(old="?1", new=thread).replace_all(old="?2", new=session)
}

///|
fn refresh_member(thread : String, session : String) -> String {
  "\n  DELETE FROM search_scope_members WHERE thread = \{thread} AND session = \{session};\n  \{insert_member(thread, session)};"
}

///|
fn schema() -> String {
  [
    "CREATE TABLE search_scope_meta (id INTEGER PRIMARY KEY CHECK(id = 1), version INTEGER NOT NULL,\n  thread_after INTEGER, thread_through INTEGER, threads_done INTEGER NOT NULL,\n  member_after INTEGER, member_through INTEGER, members_done INTEGER NOT NULL);",
    "INSERT INTO search_scope_meta SELECT 1, 1, NULL, (SELECT MAX(id) FROM threads),\n  NOT EXISTS (SELECT 1 FROM threads LIMIT 1), NULL, (SELECT MAX(rowid) FROM thread_sessions),\n  NOT EXISTS (SELECT 1 FROM thread_sessions LIMIT 1);",
    "CREATE TABLE search_scope_members (thread INTEGER NOT NULL, session NOT NULL, kind INTEGER NOT NULL,\n  ws TEXT NOT NULL, PRIMARY KEY(thread, session)) WITHOUT ROWID;",
    "CREATE TABLE search_scope_threads (kind INTEGER NOT NULL, ws TEXT NOT NULL, thread INTEGER NOT NULL,\n  refs INTEGER NOT NULL, PRIMARY KEY(kind, ws, thread)) WITHOUT ROWID;",
    "CREATE TABLE search_scope_orphans (thread INTEGER PRIMARY KEY);",
    "CREATE TABLE search_scope_members_dirty (thread INTEGER NOT NULL, session NOT NULL,\n  PRIMARY KEY(thread, session)) WITHOUT ROWID;",
    "CREATE TABLE search_scope_threads_dirty (thread INTEGER PRIMARY KEY);",
    "CREATE TABLE search_scope_sessions_dirty (session PRIMARY KEY, after_rowid INTEGER) WITHOUT ROWID;",
    "CREATE TRIGGER search_scope_member_added AFTER INSERT ON search_scope_members BEGIN\n  INSERT INTO search_scope_threads(kind, ws, thread, refs) SELECT NEW.kind, NEW.ws, NEW.thread, 0\n    WHERE NOT EXISTS (SELECT 1 FROM search_scope_threads WHERE kind = NEW.kind AND ws = NEW.ws AND thread = NEW.thread);\n  UPDATE search_scope_threads SET refs = refs + 1 WHERE kind = NEW.kind AND ws = NEW.ws AND thread = NEW.thread;\nEND;",
    "CREATE TRIGGER search_scope_member_removed AFTER DELETE ON search_scope_members BEGIN\n  UPDATE search_scope_threads SET refs = refs - 1 WHERE kind = OLD.kind AND ws = OLD.ws AND thread = OLD.thread;\n  DELETE FROM search_scope_threads WHERE kind = OLD.kind AND ws = OLD.ws AND thread = OLD.thread AND refs = 0;\nEND;",
    "CREATE TRIGGER search_scope_membership_before_add BEFORE INSERT ON thread_sessions BEGIN\n  \{mark_member(member_by_rowid("thread"), member_by_rowid("session"))}\nEND;",
    "CREATE TRIGGER search_scope_membership_add AFTER INSERT ON thread_sessions BEGIN\n  \{refresh_member("NEW.thread", "NEW.session")}\n  \{update_orphan("NEW.thread")}\nEND;",
    "CREATE TRIGGER search_scope_membership_before_change BEFORE UPDATE ON thread_sessions\n  WHEN OLD.thread IS NOT NEW.thread OR OLD.session IS NOT NEW.session OR OLD.rowid IS NOT NEW.rowid BEGIN\n    \{mark_member(member_by_rowid("thread", condition="AND rowid IS NOT OLD.rowid"), member_by_rowid("session", condition="AND rowid IS NOT OLD.rowid"))}\n    \{mark_member(member_by_key("thread"), member_by_key("session"))}\nEND;",
    "CREATE TRIGGER search_scope_membership_change AFTER UPDATE OF thread, session ON thread_sessions\n  WHEN OLD.thread IS NOT NEW.thread OR OLD.session IS NOT NEW.session BEGIN\n    DELETE FROM search_scope_members WHERE thread = OLD.thread AND session = OLD.session;\n    \{refresh_member("NEW.thread", "NEW.session")}\n    \{update_orphan("OLD.thread")} \{update_orphan("NEW.thread")}\nEND;",
    "CREATE TRIGGER search_scope_membership_drop AFTER DELETE ON thread_sessions BEGIN\n  DELETE FROM search_scope_members WHERE thread = OLD.thread AND session = OLD.session;\n  \{update_orphan("OLD.thread")}\nEND;",
    "CREATE TRIGGER search_scope_thread_before_add BEFORE INSERT ON threads BEGIN\n  \{mark_thread("(SELECT id FROM threads WHERE id = NEW.id)")} \{mark_thread(thread_by_address)}\nEND;",
    "CREATE TRIGGER search_scope_thread_before_change BEFORE UPDATE OF id, surface, channel, thread_ts ON threads BEGIN\n  \{mark_thread("(SELECT id FROM threads WHERE id = NEW.id AND id IS NOT OLD.id)")}\n  \{mark_thread("(SELECT id FROM threads WHERE surface = NEW.surface AND channel = NEW.channel\n    AND thread_ts = NEW.thread_ts AND id IS NOT OLD.id)")}\nEND;",
    "CREATE TRIGGER search_scope_thread_add AFTER INSERT ON threads BEGIN \{update_orphan("NEW.id")} END;",
    "CREATE TRIGGER search_scope_thread_change AFTER UPDATE OF id ON threads WHEN OLD.id IS NOT NEW.id BEGIN\n  \{update_orphan("OLD.id")} \{update_orphan("NEW.id")}\nEND;",
    "CREATE TRIGGER search_scope_thread_drop AFTER DELETE ON threads BEGIN \{update_orphan("OLD.id")} END;",
    "CREATE TRIGGER search_scope_session_before_add BEFORE INSERT ON sessions BEGIN\n  \{mark_session(session_by("key = NEW.key"))} \{mark_session(session_by("token = NEW.token"))}\n  \{mark_session(session_by("rowid = NEW.rowid"))}\nEND;",
    "CREATE TRIGGER search_scope_session_add AFTER INSERT ON sessions BEGIN \{mark_session("NEW.key")} END;",
    "CREATE TRIGGER search_scope_session_before_change BEFORE UPDATE ON sessions\n  WHEN OLD.key IS NOT NEW.key OR OLD.ws IS NOT NEW.ws OR OLD.token IS NOT NEW.token OR OLD.rowid IS NOT NEW.rowid BEGIN\n    \{mark_session("OLD.key")} \{mark_session(session_by("key = NEW.key AND rowid IS NOT OLD.rowid"))}\n    \{mark_session(session_by("token = NEW.token AND rowid IS NOT OLD.rowid"))}\n    \{mark_session(session_by("rowid = NEW.rowid AND rowid IS NOT OLD.rowid"))}\nEND;",
    "CREATE TRIGGER search_scope_session_change AFTER UPDATE OF key, ws ON sessions\n  WHEN OLD.key IS NOT NEW.key OR OLD.ws IS NOT NEW.ws BEGIN \{mark_session("NEW.key")} END;",
    "CREATE TRIGGER search_scope_session_drop BEFORE DELETE ON sessions BEGIN \{mark_session("OLD.key")} END;",
  ].join("\n")
}

///|
fn installed(db : @sql.Db) -> Bool raise {
  db.all("SELECT 1 AS x FROM sqlite_master WHERE type = 'table' AND name = 'search_scope_meta'", []).length() > 0
}

///|
fn check_version(db : @sql.Db) -> Unit raise {
  let rows = db.all("SELECT version FROM search_scope_meta WHERE id = 1", [])
  guard rows is [row, ..] && row.get("version") is Some(Number(1.0, ..)) else {
    fail("search scope index has an incompatible version")
  }
}

///|
/// scope-index.ts `installSearchScopeIndex`: only empty state and writers.
fn install(db : @sql.Db) -> Unit raise {
  if installed(db) {
    check_version(db)
    return
  }
  db.exec("BEGIN IMMEDIATE")
  errdefer (db.exec("ROLLBACK") catch { _ => () })
  if !installed(db) {
    db.exec(schema())
  }
  db.exec("COMMIT")
}

///|
fn text_key(storage : String, parameter : String) -> String {
  if storage == "text" {
    "CAST(\{parameter} AS TEXT)"
  } else {
    parameter
  }
}

///|
fn field(row : Map[String, Json], name : String) -> Json {
  row.get(name).unwrap_or(Json::null())
}

///|
fn storage_of(row : Map[String, Json]) -> String {
  match row.get("storage") {
    Some(String(s)) => s
    _ => ""
  }
}

///|
fn repair_orphan(db : @sql.Db, thread : Json) -> Unit raise {
  ignore(db.run("DELETE FROM search_scope_orphans WHERE thread = CAST(? AS INTEGER)", [thread]))
  ignore(
    db.run(
      "INSERT INTO search_scope_orphans(thread) SELECT CAST(?1 AS INTEGER) WHERE EXISTS (SELECT 1 FROM threads WHERE id = CAST(?1 AS INTEGER))\n    AND NOT EXISTS (SELECT 1 FROM thread_sessions WHERE thread = CAST(?1 AS INTEGER))\n    AND NOT EXISTS (SELECT 1 FROM search_scope_orphans WHERE thread = CAST(?1 AS INTEGER))",
      [thread],
    ),
  )
}

///|
/// A membership's scope row made again; `thread` as text, `bytes` the session's as SQLite has it.
fn repair_member(db : @sql.Db, thread : Json, bytes : Json, storage : String) -> Unit raise {
  let key = text_key(storage, "?2")
  ignore(db.run("DELETE FROM search_scope_members WHERE thread = CAST(?1 AS INTEGER) AND session = \{key}", [thread, bytes]))
  ignore(db.run(put_member(storage), [thread, bytes]))
}

///|
fn put_member(storage : String) -> String {
  insert_member_sql()
  .replace_all(old="?1", new="CAST(?1 AS INTEGER)")
  .replace_all(old="?2", new=text_key(storage, "?2"))
}

///|
/// One bounded step (scope-prepare.ts `step`), the lanes taken in turn from `turn`: whether all was done, and the turn
/// after.
pub fn step(db : @sql.Db, turn : Int, limit? : Int = 64) -> (Bool, Int) raise {
  install(db)
  db.exec("BEGIN IMMEDIATE")
  errdefer (db.exec("ROLLBACK") catch { _ => () })
  let metas = db.all(
    "SELECT CAST(thread_after AS TEXT) AS thread_after, CAST(thread_through AS TEXT) AS thread_through, threads_done, CAST(member_after AS TEXT) AS member_after, CAST(member_through AS TEXT) AS member_through, members_done FROM search_scope_meta WHERE id = 1 AND version = 1",
    [],
  )
  guard metas is [meta, ..] else { fail("search scope index has an incompatible version") }
  let session = db.all(
    "SELECT CAST(session AS BLOB) AS bytes, typeof(session) AS storage, CAST(after_rowid AS TEXT) AS after_rowid FROM search_scope_sessions_dirty ORDER BY session LIMIT 1",
    [],
  ).get(0)
  let member = db.all(
    "SELECT CAST(thread AS TEXT) AS thread, CAST(session AS BLOB) AS bytes, typeof(session) AS storage FROM search_scope_members_dirty d ORDER BY d.thread, d.session LIMIT 1",
    [],
  ).get(0)
  let thread = db.all("SELECT CAST(thread AS TEXT) AS thread FROM search_scope_threads_dirty d ORDER BY d.thread LIMIT 1", []).get(
    0,
  )
  let done = (v : Json) => v is Number(1.0, ..)
  let pending = [
    session is Some(_),
    member is Some(_),
    thread is Some(_),
    !done(field(meta, "threads_done")),
    !done(field(meta, "members_done")),
  ]
  if !pending.contains(true) {
    db.exec("COMMIT")
    return (true, turn)
  }
  let mut lane = 0
  for i in 0..<pending.length() {
    lane = (turn + i) % pending.length()
    if pending[lane] {
      break
    }
  }
  let next_turn = (lane + 1) % pending.length()
  let lim = Json::number(limit.to_double())
  match (lane, session, member, thread) {
    (0, Some(s), _, _) => {
      let storage = storage_of(s)
      let bytes = field(s, "bytes")
      let key = text_key(storage, "?1")
      let after = field(s, "after_rowid")
      let rows = if after is Null {
        db.all(
          "SELECT CAST(rowid AS TEXT) AS n, CAST(thread AS TEXT) AS thread FROM thread_sessions INDEXED BY thread_sessions_session WHERE session = \{key} ORDER BY rowid LIMIT ?2",
          [bytes, lim],
        )
      } else {
        db.all(
          "SELECT CAST(rowid AS TEXT) AS n, CAST(thread AS TEXT) AS thread FROM thread_sessions INDEXED BY thread_sessions_session WHERE session = \{key} AND rowid > CAST(?2 AS INTEGER) ORDER BY rowid LIMIT ?3",
          [bytes, after, lim],
        )
      }
      for row in rows {
        repair_member(db, field(row, "thread"), bytes, storage)
      }
      if rows.length() < limit {
        ignore(db.run("DELETE FROM search_scope_sessions_dirty WHERE session = \{key}", [bytes]))
      } else {
        ignore(
          db.run("UPDATE search_scope_sessions_dirty SET after_rowid = CAST(?2 AS INTEGER) WHERE session = \{key}", [
            bytes,
            field(rows[rows.length() - 1], "n"),
          ]),
        )
      }
    }
    (1, _, Some(m), _) => {
      let storage = storage_of(m)
      let t = field(m, "thread")
      let bytes = field(m, "bytes")
      repair_member(db, t, bytes, storage)
      repair_orphan(db, t)
      ignore(
        db.run(
          "DELETE FROM search_scope_members_dirty WHERE thread = CAST(?1 AS INTEGER) AND session = \{text_key(storage, "?2")}",
          [t, bytes],
        ),
      )
    }
    (2, _, _, Some(t)) => {
      repair_orphan(db, field(t, "thread"))
      ignore(db.run("DELETE FROM search_scope_threads_dirty WHERE thread = CAST(? AS INTEGER)", [field(t, "thread")]))
    }
    (3, _, _, _) => {
      let after = field(meta, "thread_after")
      let through = field(meta, "thread_through")
      let rows = if through is Null {
        []
      } else if after is Null {
        db.all("SELECT CAST(id AS TEXT) AS id FROM threads WHERE id <= CAST(?1 AS INTEGER) ORDER BY threads.id LIMIT ?2", [
          through, lim,
        ])
      } else {
        db.all(
          "SELECT CAST(id AS TEXT) AS id FROM threads WHERE id > CAST(?1 AS INTEGER) AND id <= CAST(?2 AS INTEGER) ORDER BY threads.id LIMIT ?3",
          [after, through, lim],
        )
      }
      for row in rows {
        repair_orphan(db, field(row, "id"))
      }
      let reached = match rows.last() {
        Some(r) => field(r, "id")
        None => after
      }
      ignore(
        db.run("UPDATE search_scope_meta SET thread_after = CAST(? AS INTEGER), threads_done = ? WHERE id = 1", [
          reached,
          Json::number(if rows.length() < limit { 1.0 } else { 0.0 }),
        ]),
      )
    }
    (4, _, _, _) => {
      let after = field(meta, "member_after")
      let through = field(meta, "member_through")
      let rows = if through is Null {
        []
      } else if after is Null {
        db.all(
          "SELECT CAST(rowid AS TEXT) AS n, CAST(thread AS TEXT) AS thread, CAST(session AS BLOB) AS bytes, typeof(session) AS storage FROM thread_sessions WHERE rowid <= CAST(?1 AS INTEGER) ORDER BY rowid LIMIT ?2",
          [through, lim],
        )
      } else {
        db.all(
          "SELECT CAST(rowid AS TEXT) AS n, CAST(thread AS TEXT) AS thread, CAST(session AS BLOB) AS bytes, typeof(session) AS storage FROM thread_sessions WHERE rowid > CAST(?1 AS INTEGER) AND rowid <= CAST(?2 AS INTEGER) ORDER BY rowid LIMIT ?3",
          [after, through, lim],
        )
      }
      for row in rows {
        ignore(db.run(put_member(storage_of(row)), [field(row, "thread"), field(row, "bytes")]))
      }
      let reached = match rows.last() {
        Some(r) => field(r, "n")
        None => after
      }
      ignore(
        db.run("UPDATE search_scope_meta SET member_after = CAST(? AS INTEGER), members_done = ? WHERE id = 1", [
          reached,
          Json::number(if rows.length() < limit { 1.0 } else { 0.0 }),
        ]),
      )
    }
    _ => ()
  }
  db.exec("COMMIT")
  (false, next_turn)
}
