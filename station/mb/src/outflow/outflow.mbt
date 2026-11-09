// A program's chat page, ordered by the last message in each workspace (station/src/store/outflow-index.ts): the index
// made when it is first asked for (the same tables and triggers as `installOutflowChatIndex`), the old chats brought
// across in bounded batches and the changed ones of the asked scope settled, as `outflowChatIndexStep` does, here for
// the MoonBit builder.

///|
fn scope(ws : String) -> String {
  "(CASE WHEN \{ws} IS NULL THEN 'H' ELSE 'W' || \{ws} END)"
}

///|
/// The threads marked to be settled again (their order rows dirty, or made for the scopes they are in).
fn mark(threads : String) -> String {
  "UPDATE outflow_chat_order SET dirty = 1 WHERE dirty = 0 AND thread IN (\{threads}); INSERT INTO outflow_chat_order (thread, scope, at, dirty) SELECT DISTINCT m.thread, \{scope("s.ws")}, 0, 1 FROM thread_sessions m JOIN sessions s ON s.key = m.session WHERE m.thread IN (\{threads}) AND NOT EXISTS (SELECT 1 FROM outflow_chat_order o WHERE o.scope = \{scope("s.ws")} AND o.thread = m.thread);"
}

///|
fn session_threads(session : String) -> String {
  "SELECT thread FROM thread_sessions WHERE session = \{session}"
}

///|
let conflicting_threads : String = "SELECT thread FROM thread_sessions WHERE session IN (SELECT key FROM sessions WHERE key = NEW.key OR token = NEW.token)"

///|
let conflicting_chat : String = "SELECT id FROM threads WHERE id = NEW.id OR (surface = NEW.surface AND channel = NEW.channel AND thread_ts = NEW.thread_ts)"

///|
/// What `installOutflowChatIndex` makes: the order, its progress, and the triggers that mark what writers change
/// (an older station's as well, during a handover).
pub fn schema() -> String {
  let thread_changed = "OLD.id IS NOT NEW.id OR OLD.surface IS NOT NEW.surface OR OLD.channel IS NOT NEW.channel OR OLD.thread_ts IS NOT NEW.thread_ts OR OLD.created_at IS NOT NEW.created_at"
  let session_changed = "OLD.key IS NOT NEW.key OR OLD.ws IS NOT NEW.ws OR OLD.token IS NOT NEW.token"
  [
    "CREATE TABLE outflow_chat_order (thread INTEGER NOT NULL, scope TEXT NOT NULL, at INTEGER NOT NULL, dirty INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (thread, scope)) WITHOUT ROWID;",
    "CREATE INDEX outflow_chat_scope_order ON outflow_chat_order (scope, dirty, at DESC, thread DESC);",
    "CREATE TABLE outflow_chat_progress (id INTEGER PRIMARY KEY CHECK (id = 1), cursor INTEGER, last INTEGER, done INTEGER NOT NULL);",
    "INSERT INTO outflow_chat_progress SELECT 1, NULL, MAX(id), MAX(id) IS NULL FROM threads;",
    "CREATE TRIGGER outflow_thread_before_add BEFORE INSERT ON threads BEGIN \{mark(conflicting_chat)} END;",
    "CREATE TRIGGER outflow_thread_add AFTER INSERT ON threads BEGIN \{mark("SELECT NEW.id")} END;",
    "CREATE TRIGGER outflow_thread_before BEFORE UPDATE OF id, surface, channel, thread_ts, created_at ON threads WHEN \{thread_changed} BEGIN \{mark("SELECT OLD.id")} \{mark(conflicting_chat)} END;",
    "CREATE TRIGGER outflow_thread_after AFTER UPDATE OF id, surface, channel, thread_ts, created_at ON threads WHEN \{thread_changed} BEGIN \{mark("SELECT NEW.id")} END;",
    "CREATE TRIGGER outflow_thread_drop BEFORE DELETE ON threads BEGIN \{mark("SELECT OLD.id")} END;",
    "CREATE TRIGGER outflow_member_add AFTER INSERT ON thread_sessions BEGIN \{mark("SELECT NEW.thread")} END;",
    "CREATE TRIGGER outflow_member_before BEFORE UPDATE OF thread, session ON thread_sessions WHEN OLD.thread IS NOT NEW.thread OR OLD.session IS NOT NEW.session BEGIN \{mark("SELECT OLD.thread")} END;",
    "CREATE TRIGGER outflow_member_after AFTER UPDATE OF thread, session ON thread_sessions WHEN OLD.thread IS NOT NEW.thread OR OLD.session IS NOT NEW.session BEGIN \{mark("SELECT NEW.thread")} END;",
    "CREATE TRIGGER outflow_member_drop BEFORE DELETE ON thread_sessions BEGIN \{mark("SELECT OLD.thread")} END;",
    // (REPLACE can evict a different key by its unique token without a DELETE trigger: marked before it does)
    "CREATE TRIGGER outflow_session_before_add BEFORE INSERT ON sessions BEGIN \{mark(conflicting_threads)} END;",
    "CREATE TRIGGER outflow_session_add AFTER INSERT ON sessions BEGIN \{mark(session_threads("NEW.key"))} END;",
    "CREATE TRIGGER outflow_session_before BEFORE UPDATE OF key, ws, token ON sessions WHEN \{session_changed} BEGIN \{mark(session_threads("OLD.key"))} \{mark(conflicting_threads)} END;",
    "CREATE TRIGGER outflow_session_after AFTER UPDATE OF key, ws, token ON sessions WHEN \{session_changed} BEGIN \{mark(session_threads("NEW.key"))} END;",
    "CREATE TRIGGER outflow_session_drop BEFORE DELETE ON sessions BEGIN \{mark(session_threads("OLD.key"))} END;",
    "CREATE TRIGGER outflow_said_add AFTER INSERT ON thread_state BEGIN \{mark("SELECT NEW.thread")} END;",
    "CREATE TRIGGER outflow_said_change AFTER UPDATE OF thread, said_n ON thread_state WHEN OLD.thread IS NOT NEW.thread OR OLD.said_n IS NOT NEW.said_n BEGIN \{mark("SELECT OLD.thread")} \{mark("SELECT NEW.thread")} END;",
    "CREATE TRIGGER outflow_said_drop BEFORE DELETE ON thread_state BEGIN \{mark("SELECT OLD.thread")} END;",
    // (REPLACE can remove the last message without a DELETE trigger, its unique timestamp's too)
    "CREATE TRIGGER outflow_entry_before_add BEFORE INSERT ON entries WHEN EXISTS ( SELECT 1 FROM thread_state st WHERE st.thread = NEW.thread AND (st.said_n = NEW.n OR (NEW.ts IS NOT NULL AND EXISTS (SELECT 1 FROM entries e WHERE e.thread = st.thread AND e.n = st.said_n AND e.ts = NEW.ts))) ) BEGIN \{mark("SELECT NEW.thread")} END;",
    "CREATE TRIGGER outflow_entry_change AFTER UPDATE OF thread, n, at, kind ON entries BEGIN \{mark("SELECT OLD.thread")} \{mark("SELECT NEW.thread")} END;",
    "CREATE TRIGGER outflow_entry_drop AFTER DELETE ON entries BEGIN \{mark("SELECT OLD.thread")} END;",
  ].join("\n")
}

///|
fn installed(db : @sql.Db) -> Bool raise {
  db.all("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'outflow_chat_progress'", []).length() > 0
}

///|
/// The index made, once (`installOutflowChatIndex`).
pub fn install(db : @sql.Db) -> Unit raise {
  if installed(db) {
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
let last_at : String = "MAX(t.created_at, COALESCE((SELECT e.at FROM thread_state st JOIN entries e ON e.thread = st.thread AND e.n = st.said_n AND e.kind = 'message' WHERE st.thread = t.id), 0))"

///|
/// One thread settled in every scope it is in, the others' rows left as they are when their order is unchanged.
fn refresh(db : @sql.Db, thread : Json) -> Unit raise {
  ignore(
    db.run(
      "DELETE FROM outflow_chat_order WHERE thread = ?1 AND (NOT EXISTS (SELECT 1 FROM threads t WHERE t.id = ?1) OR NOT EXISTS (SELECT 1 FROM thread_sessions m JOIN sessions s ON s.key = m.session WHERE m.thread = ?1 AND \{scope("s.ws")} = outflow_chat_order.scope))",
      [thread],
    ),
  )
  ignore(
    db.run(
      "UPDATE outflow_chat_order SET at = (SELECT \{last_at} FROM threads t WHERE t.id = ?1), dirty = 0 WHERE thread = ?1 AND (dirty <> 0 OR at IS NOT (SELECT \{last_at} FROM threads t WHERE t.id = ?1))",
      [thread],
    ),
  )
  ignore(
    db.run(
      "INSERT INTO outflow_chat_order (thread, scope, at) SELECT DISTINCT m.thread, \{scope("s.ws")}, \{last_at} FROM thread_sessions m JOIN sessions s ON s.key = m.session JOIN threads t ON t.id = m.thread WHERE m.thread = ?1 AND NOT EXISTS (SELECT 1 FROM outflow_chat_order o WHERE o.thread = m.thread AND o.scope = \{scope("s.ws")})",
      [thread],
    ),
  )
}

///|
fn value(row : Map[String, Json], name : String) -> Json {
  match row.get(name) {
    Some(j) => j
    None => Json::null()
  }
}

///|
/// One batch of at most `limit` old chats, or of `requested`'s changed ones once the old are across; whether the
/// old are across and nothing of `requested` is left to settle then.
pub fn step(db : @sql.Db, requested : String, limit? : Int = 64) -> Bool raise {
  guard limit >= 1 else { fail("outflow index batch must be positive") }
  db.exec("BEGIN IMMEDIATE")
  errdefer (db.exec("ROLLBACK") catch { _ => () })
  guard db.all("SELECT cursor, last, done FROM outflow_chat_progress WHERE id = 1", []) is [state, ..] else {
    fail("outflow chat index progress is missing")
  }
  let lim = Json::number(limit.to_double())
  if state.get("done") is Some(Number(0.0, ..)) {
    let cursor = value(state, "cursor")
    let rows = if cursor is Null {
      db.all("SELECT id AS thread FROM threads WHERE id <= ?1 ORDER BY id LIMIT ?2", [value(state, "last"), lim])
    } else {
      db.all("SELECT id AS thread FROM threads WHERE id > ?3 AND id <= ?1 ORDER BY id LIMIT ?2", [
        value(state, "last"),
        lim,
        cursor,
      ])
    }
    for row in rows {
      refresh(db, value(row, "thread"))
    }
    let reached = match rows.last() {
      Some(r) => value(r, "thread")
      None => cursor
    }
    ignore(
      db.run("UPDATE outflow_chat_progress SET cursor = ?1, done = ?2 WHERE id = 1", [
        reached,
        Json::number(if rows.length() < limit { 1.0 } else { 0.0 }),
      ]),
    )
  } else {
    let rows = db.all(
      "SELECT thread FROM outflow_chat_order INDEXED BY outflow_chat_scope_order WHERE scope = ?1 AND dirty = 1 ORDER BY at DESC, thread DESC LIMIT ?2",
      [Json::string(requested), lim],
    )
    // (each thread settled in all its scopes in the same transaction)
    for row in rows {
      refresh(db, value(row, "thread"))
    }
  }
  let across = db.all("SELECT done FROM outflow_chat_progress WHERE id = 1", []) is [p, ..] &&
    p.get("done") is Some(Number(1.0, ..))
  let done = across &&
    db.all(
      "SELECT 1 FROM outflow_chat_order INDEXED BY outflow_chat_scope_order WHERE scope = ? AND dirty = 1 LIMIT 1",
      [Json::string(requested)],
    ).length() ==
    0
  db.exec("COMMIT")
  done
}
