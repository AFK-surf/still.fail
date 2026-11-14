// A session's copy destinations, its chats by their last message (station/src/store/cc-thread-index.ts), and from
// them its chat names' order (session-chat-index.ts) and its latest conversation (latest-thread-index.ts): prepared a
// requested session at a time in bounded slices, as `CcIndexPreparation`, `SessionChatPreparation` and
// `prepareLatestThreadStep` do, here for the MoonBit builder. Row ids and thread ids are read and written as text:
// an old orphaned membership may hold an integer no double keeps. (Ordered by the column, never by its text alias.)

///|
let version : Int = 1

///|
fn value(row : Map[String, Json], name : String) -> Json {
  row.get(name).unwrap_or(Json::null())
}

///|
fn first_row(db : @sql.Db, sql : String, params : Array[Json]) -> Map[String, Json]? raise {
  match db.all(sql, params) {
    [r, ..] => Some(r)
    _ => None
  }
}

///|
fn exists(db : @sql.Db, sql : String, params : Array[Json]) -> Bool raise {
  db.all(sql, params).length() > 0
}

///|
fn is_one(v : Json) -> Bool {
  v is Number(n, ..) && n == 1.0
}

///|
fn check_version(db : @sql.Db, table : String, what : String) -> Unit raise {
  match first_row(db, "SELECT version FROM \{table} WHERE id=1", []) {
    Some(r) if value(r, "version") is Number(n, ..) && n.to_int() == version => ()
    Some(r) => fail("\{what} version \{value(r, "version").stringify()} is incompatible with \{version}")
    None => fail("\{what} version missing is incompatible with \{version}")
  }
}

///|
fn check_cc(db : @sql.Db) -> Unit raise {
  check_version(db, "cc_index_meta", "copy destination index")
}

///|
fn track(db : @sql.Db, session : Json, existing : Bool) -> Unit raise {
  check_cc(db)
  db.exec("BEGIN IMMEDIATE")
  errdefer (db.exec("ROLLBACK") catch { _ => () })
  ignore(
    db.run(
      "INSERT INTO cc_sessions(session,scan_end) SELECT ?1,(SELECT rowid FROM thread_sessions INDEXED BY thread_sessions_session WHERE session=?1 ORDER BY rowid DESC LIMIT 1) WHERE NOT EXISTS (SELECT 1 FROM cc_sessions WHERE session=?1) AND (?2=0 OR EXISTS (SELECT 1 FROM sessions WHERE key=?1))",
      [session, Json::number(if existing { 1.0 } else { 0.0 })],
    ),
  )
  db.exec("COMMIT")
}

///|
/// The session's row for one thread made as its membership is now (gone, or with the thread's surface and times).
fn reconcile(db : @sql.Db, session : Json, thread : Json) -> Unit raise {
  ignore(
    db.run(
      "DELETE FROM cc_session_rows WHERE session=?1 AND thread=CAST(?2 AS INTEGER) AND NOT EXISTS (SELECT 1 FROM thread_sessions WHERE session=?1 AND thread=CAST(?2 AS INTEGER))",
      [session, thread],
    ),
  )
  ignore(
    db.run(
      "INSERT INTO cc_session_rows(session,thread,surface,created_at,last_at) SELECT m.session,m.thread,t.surface,t.created_at,e.at FROM thread_sessions m LEFT JOIN threads t ON t.id=m.thread LEFT JOIN thread_state st ON st.thread=t.id LEFT JOIN entries e ON e.thread=st.thread AND e.n=st.last_n WHERE m.session=?1 AND m.thread=CAST(?2 AS INTEGER) ON CONFLICT(session,thread) DO UPDATE SET surface=excluded.surface, created_at=excluded.created_at,last_at=excluded.last_at WHERE surface IS NOT excluded.surface OR created_at IS NOT excluded.created_at OR last_at IS NOT excluded.last_at",
      [session, thread],
    ),
  )
}

///|
fn scan_step(db : @sql.Db, session : Json, limit : Int) -> Int raise {
  db.exec("BEGIN IMMEDIATE")
  errdefer (db.exec("ROLLBACK") catch { _ => () })
  check_cc(db)
  guard first_row(
      db,
      "SELECT CAST(scan_after AS TEXT) AS scan_after,CAST(scan_end AS TEXT) AS scan_end,complete FROM cc_sessions WHERE session=?",
      [session],
    )
    is Some(scope) else {
    fail("copy destination session is not tracked")
  }
  if is_one(value(scope, "complete")) {
    db.exec("COMMIT")
    return 0
  }
  let after = value(scope, "scan_after")
  let lim = Json::number(limit.to_double())
  let rows = if after is Null {
    db.all(
      "SELECT CAST(rowid AS TEXT) AS rowid,CAST(thread AS TEXT) AS thread FROM thread_sessions INDEXED BY thread_sessions_session WHERE session=?1 AND rowid<=CAST(?2 AS INTEGER) ORDER BY thread_sessions.rowid LIMIT ?3",
      [session, value(scope, "scan_end"), lim],
    )
  } else {
    db.all(
      "SELECT CAST(rowid AS TEXT) AS rowid,CAST(thread AS TEXT) AS thread FROM thread_sessions INDEXED BY thread_sessions_session WHERE session=?1 AND rowid>CAST(?2 AS INTEGER) AND rowid<=CAST(?3 AS INTEGER) ORDER BY thread_sessions.rowid LIMIT ?4",
      [session, after, value(scope, "scan_end"), lim],
    )
  }
  for row in rows {
    reconcile(db, session, value(row, "thread"))
  }
  let reached = match rows.last() {
    Some(r) => value(r, "rowid")
    None => after
  }
  ignore(
    db.run("UPDATE cc_sessions SET scan_after=CAST(? AS INTEGER),complete=? WHERE session=?", [
      reached,
      Json::number(if rows.length() < limit { 1.0 } else { 0.0 }),
      session,
    ]),
  )
  db.exec("COMMIT")
  rows.length()
}

///|
fn dispatch_step(db : @sql.Db, limit : Int) -> Int raise {
  db.exec("BEGIN IMMEDIATE")
  errdefer (db.exec("ROLLBACK") catch { _ => () })
  check_cc(db)
  guard first_row(
      db,
      "SELECT CAST(after_thread AS TEXT) AS after_thread,CAST(through_thread AS TEXT) AS through_thread FROM cc_order_turn WHERE id=1",
      [],
    )
    is Some(progress) else {
    fail("copy destination turn is missing")
  }
  let pick = "SELECT CAST(thread AS TEXT) AS thread,after_session,through_session FROM cc_order_dispatch"
  let mut through = value(progress, "through_thread")
  let mut pending = if through is Null {
    None
  } else if value(progress, "after_thread") is Null {
    first_row(db, "\{pick} WHERE thread<=CAST(? AS INTEGER) ORDER BY cc_order_dispatch.thread LIMIT 1", [through])
  } else {
    first_row(db, "\{pick} WHERE thread>CAST(? AS INTEGER) AND thread<=CAST(? AS INTEGER) ORDER BY cc_order_dispatch.thread LIMIT 1", [
      value(progress, "after_thread"),
      through,
    ])
  }
  if pending is None {
    through = first_row(db, "SELECT CAST(MAX(thread) AS TEXT) AS thread FROM cc_order_dispatch", []).map(r => value(
        r, "thread",
      )).unwrap_or(Json::null())
    if through is Null {
      db.exec("COMMIT")
      return 0
    }
    pending = first_row(db, "\{pick} WHERE thread<=CAST(? AS INTEGER) ORDER BY cc_order_dispatch.thread LIMIT 1", [through])
  }
  guard pending is Some(p) else { fail("copy destination dispatch disappeared") }
  let thread = value(p, "thread")
  ignore(
    db.run("UPDATE cc_order_turn SET after_thread=CAST(? AS INTEGER),through_thread=CAST(? AS INTEGER) WHERE id=1", [
      thread, through,
    ]),
  )
  let lim = Json::number(limit.to_double())
  let rows = if value(p, "after_session") is Null {
    db.all(
      "SELECT session FROM cc_session_rows INDEXED BY cc_rows_thread WHERE thread=CAST(?1 AS INTEGER) AND session<=?2 ORDER BY session LIMIT ?3",
      [thread, value(p, "through_session"), lim],
    )
  } else {
    db.all(
      "SELECT session FROM cc_session_rows INDEXED BY cc_rows_thread WHERE thread=CAST(?1 AS INTEGER) AND session>?2 AND session<=?3 ORDER BY session LIMIT ?4",
      [thread, value(p, "after_session"), value(p, "through_session"), lim],
    )
  }
  for row in rows {
    ignore(
      db.run(
        "INSERT INTO cc_session_dirty(session,thread) SELECT ?1,CAST(?2 AS INTEGER) WHERE NOT EXISTS (SELECT 1 FROM cc_session_dirty WHERE session=?1 AND thread=CAST(?2 AS INTEGER))",
        [value(row, "session"), thread],
      ),
    )
  }
  if rows.length() == limit {
    ignore(
      db.run("UPDATE cc_order_dispatch SET after_session=? WHERE thread=CAST(? AS INTEGER)", [
        value(rows[rows.length() - 1], "session"),
        thread,
      ]),
    )
  } else {
    ignore(db.run("DELETE FROM cc_order_dispatch WHERE thread=CAST(? AS INTEGER)", [thread]))
  }
  db.exec("COMMIT")
  rows.length()
}

///|
fn settle_step(db : @sql.Db, session : Json) -> Int raise {
  db.exec("BEGIN IMMEDIATE")
  errdefer (db.exec("ROLLBACK") catch { _ => () })
  check_cc(db)
  if !exists(db, "SELECT 1 FROM cc_sessions WHERE session=?", [session]) {
    fail("copy destination session is not tracked")
  }
  guard first_row(
      db,
      "SELECT CAST(thread AS TEXT) AS thread FROM cc_session_dirty WHERE session=? ORDER BY cc_session_dirty.thread LIMIT 1",
      [session],
    )
    is Some(row) else {
    db.exec("COMMIT")
    return 0
  }
  let thread = value(row, "thread")
  if exists(db, "SELECT 1 FROM cc_order_dispatch WHERE thread=CAST(? AS INTEGER)", [thread]) {
    db.exec("COMMIT")
    return 0
  }
  reconcile(db, session, thread)
  ignore(db.run("DELETE FROM cc_session_dirty WHERE session=? AND thread=CAST(? AS INTEGER)", [session, thread]))
  db.exec("COMMIT")
  1
}

///|
/// Whether the session's destinations may be read (`ccSessionReady`).
pub fn ready(db : @sql.Db, session : Json) -> Bool raise {
  check_cc(db)
  guard first_row(db, "SELECT complete FROM cc_sessions WHERE session=?", [session]) is Some(scope) &&
    is_one(value(scope, "complete")) else {
    return false
  }
  if exists(db, "SELECT 1 FROM cc_session_dirty WHERE session=? LIMIT 1", [session]) {
    return false
  }
  guard first_row(
      db,
      "SELECT COUNT(*) AS n, MAX(EXISTS (SELECT 1 FROM cc_session_rows r WHERE r.session=?1 AND r.thread=d.thread)) AS affects FROM (SELECT thread FROM cc_order_dispatch ORDER BY thread LIMIT 65) d",
      [session],
    )
    is Some(dispatch) else {
    return false
  }
  if is_one(value(dispatch, "affects")) {
    return false
  }
  if value(dispatch, "n") is Number(n, ..) && n <= 64.0 {
    return true
  }
  guard first_row(
      db,
      "SELECT COUNT(*) AS n, MAX(EXISTS (SELECT 1 FROM cc_order_dispatch d WHERE d.thread=r.thread)) AS affects FROM (SELECT thread FROM cc_session_rows WHERE session=?1 ORDER BY thread LIMIT 65) r",
      [session],
    )
    is Some(rows) else {
    return false
  }
  value(rows, "n") is Number(n, ..) && n <= 64.0 && !is_one(value(rows, "affects"))
}

///|
/// The builder's preparations: whose turn each session's lanes have (`CcIndexPreparation`).
pub struct Cc {
  priv turns : Map[String, Int]
}

///|
pub fn Cc::new() -> Cc {
  { turns: Map([]) }
}

///|
pub fn Cc::cancel(self : Cc, session : String) -> Unit {
  self.turns.remove(session)
}

///|
/// One slice of the session's copy destinations: its scan, a shared thread's distribution, or its reconciliation, in
/// turn; whether they are ready then.
pub fn Cc::step(self : Cc, db : @sql.Db, session : String, existing? : Bool = true, limit? : Int = 64) -> Bool raise {
  let s = Json::string(session)
  check_cc(db)
  if existing && !exists(db, "SELECT 1 FROM sessions WHERE key=?", [s]) {
    self.turns.remove(session)
    return true
  }
  let mut scope = first_row(db, "SELECT complete FROM cc_sessions WHERE session=?", [s])
  if scope is None {
    track(db, s, existing)
    scope = first_row(db, "SELECT complete FROM cc_sessions WHERE session=?", [s])
    if scope is None {
      self.turns.remove(session)
      return true
    }
  }
  if ready(db, s) {
    self.turns.remove(session)
    return true
  }
  let scanning = scope is Some(sc) && value(sc, "complete") is Number(0.0, ..)
  let pending : Array[() -> Bool raise] = [
    () => scanning,
    () => exists(db, "SELECT 1 FROM cc_order_dispatch LIMIT 1", []),
    () => exists(db, "SELECT 1 FROM cc_session_dirty WHERE session=? LIMIT 1", [s]),
  ]
  let steps : Array[() -> Unit raise] = [
    () => ignore(scan_step(db, s, limit)),
    () => ignore(dispatch_step(db, limit)),
    () => ignore(settle_step(db, s)),
  ]
  let turn = self.turns.get(session).unwrap_or(0)
  for n = 0; n < 3; n = n + 1 {
    let at = (turn + n) % 3
    if !pending[at]() {
      continue
    }
    self.turns[session] = (at + 1) % 3
    steps[at]()
    let done = ready(db, s)
    if done {
      self.turns.remove(session)
    }
    return done
  }
  if ready(db, s) {
    self.turns.remove(session)
    return true
  }
  fail("copy destination preparation has no runnable work")
}

///|
fn exists_member(session : String, thread : String) -> String {
  "(EXISTS (SELECT 1 FROM thread_sessions m JOIN threads t ON t.id=m.thread WHERE m.session=\{session} AND m.thread=\{thread}))"
}

///|
fn last_at(thread : String) -> String {
  "(SELECT at FROM entries WHERE thread=\{thread} ORDER BY n DESC LIMIT 1)"
}

///|
let name_refresh : String = {
  let (session, thread) = ("?1", "CAST(?2 AS INTEGER)")
  let present = exists_member(session, thread)
  let last = last_at(thread)
  "UPDATE cc_session_rows SET name_present=\{present}, name_has_last=CASE WHEN \{present} THEN (\{last} IS NOT NULL) END, name_last_at=CASE WHEN \{present} THEN COALESCE(\{last},0) END, name_created_at=(SELECT created_at FROM threads WHERE id=\{thread}) WHERE session=\{session} AND thread=\{thread} AND EXISTS (SELECT 1 FROM session_chat_scopes WHERE session=\{session}) AND (name_present IS NOT \{present} OR (\{present} AND (name_has_last IS NOT (\{last} IS NOT NULL) OR name_last_at IS NOT COALESCE(\{last},0) OR name_created_at IS NOT (SELECT created_at FROM threads WHERE id=\{thread}))))"
}

///|
let name_ensure : String = "INSERT OR IGNORE INTO session_chat_rows(session,has_last,last_at,created_at,thread) SELECT session,name_has_last,name_last_at,name_created_at,thread FROM cc_session_rows WHERE session=?1 AND thread=CAST(?2 AS INTEGER) AND name_present=1 AND EXISTS (SELECT 1 FROM session_chat_scopes WHERE session=?1)"

///|
/// One slice of the session's chat names' order: its copy destinations first, then its ordered rows in key order
/// (`SessionChatPreparation`); whether it is ready then.
pub fn Cc::names_step(self : Cc, db : @sql.Db, session : String, existing? : Bool = true, limit? : Int = 64) -> Bool raise {
  let s = Json::string(session)
  check_version(db, "session_chat_meta", "session chat index")
  if existing && !exists(db, "SELECT 1 FROM sessions WHERE key=?", [s]) {
    return true
  }
  if !ready(db, s) {
    ignore(self.step(db, session, existing~, limit~))
    return false
  }
  db.exec("BEGIN IMMEDIATE")
  errdefer (db.exec("ROLLBACK") catch { _ => () })
  check_version(db, "session_chat_meta", "session chat index")
  if existing && !exists(db, "SELECT 1 FROM sessions WHERE key=?", [s]) {
    db.exec("COMMIT")
    return true
  }
  if !ready(db, s) {
    db.exec("COMMIT")
    return false
  }
  ignore(
    db.run(
      "INSERT INTO session_chat_scopes(session,scan_end) SELECT ?1,(SELECT thread FROM cc_session_rows WHERE session=?1 ORDER BY thread DESC LIMIT 1) WHERE NOT EXISTS (SELECT 1 FROM session_chat_scopes WHERE session=?1)",
      [s],
    ),
  )
  guard first_row(
      db,
      "SELECT CAST(scan_after AS TEXT) AS scan_after,CAST(scan_end AS TEXT) AS scan_end,complete FROM session_chat_scopes WHERE session=?",
      [s],
    )
    is Some(scope) else {
    fail("session chat scope is missing")
  }
  if is_one(value(scope, "complete")) {
    db.exec("COMMIT")
    return true
  }
  let after = value(scope, "scan_after")
  let lim = Json::number(limit.to_double())
  let rows = if after is Null {
    db.all(
      "SELECT CAST(thread AS TEXT) AS thread FROM cc_session_rows WHERE session=?1 AND thread<=CAST(?2 AS INTEGER) ORDER BY cc_session_rows.thread LIMIT ?3",
      [s, value(scope, "scan_end"), lim],
    )
  } else {
    db.all(
      "SELECT CAST(thread AS TEXT) AS thread FROM cc_session_rows WHERE session=?1 AND thread>CAST(?2 AS INTEGER) AND thread<=CAST(?3 AS INTEGER) ORDER BY cc_session_rows.thread LIMIT ?4",
      [s, after, value(scope, "scan_end"), lim],
    )
  }
  for row in rows {
    ignore(db.run(name_refresh, [s, value(row, "thread")]))
    ignore(db.run(name_ensure, [s, value(row, "thread")]))
  }
  let done = rows.length() < limit
  let reached = match rows.last() {
    Some(r) => value(r, "thread")
    None => after
  }
  ignore(
    db.run("UPDATE session_chat_scopes SET scan_after=CAST(? AS INTEGER),complete=? WHERE session=?", [
      reached,
      Json::number(if done { 1.0 } else { 0.0 }),
      s,
    ]),
  )
  db.exec("COMMIT")
  done
}

///|
let candidate : String = "SELECT m.session,m.thread,m.rowid AS member_rowid,m.joined_at, (SELECT d.rowid FROM deliveries d INDEXED BY deliveries_session WHERE d.session=m.session AND d.thread=m.thread ORDER BY d.rowid DESC LIMIT 1) AS last_delivery FROM thread_sessions m JOIN threads t ON t.id=m.thread WHERE m.session=?1 AND m.rowid=CAST(?2 AS INTEGER)"

///|
let add_candidate : String = "INSERT INTO latest_thread_rows(session,has_last,last_delivery,joined_at,member_rowid,thread) SELECT c.session,c.last_delivery IS NOT NULL,COALESCE(c.last_delivery,0),c.joined_at,c.member_rowid,c.thread FROM (\{candidate}) c WHERE NOT EXISTS (SELECT 1 FROM latest_thread_rows r WHERE r.session=c.session AND r.has_last=(c.last_delivery IS NOT NULL) AND r.last_delivery=COALESCE(c.last_delivery,0) AND r.joined_at IS c.joined_at AND r.member_rowid=c.member_rowid)"

///|
let add_member : String = "INSERT INTO latest_thread_members(thread,session) SELECT m.thread,m.session FROM thread_sessions m WHERE m.session=?1 AND m.rowid=CAST(?2 AS INTEGER) AND NOT EXISTS (SELECT 1 FROM latest_thread_members r WHERE r.thread=m.thread AND r.session=m.session)"

///|
/// One slice of an old session's walk for its latest conversation (`prepareLatestThreadStep`); whether it is done.
pub fn latest_step(db : @sql.Db, session : String, existing? : Bool = true, limit? : Int = 64) -> Bool raise {
  let s = Json::string(session)
  db.exec("BEGIN IMMEDIATE")
  errdefer (db.exec("ROLLBACK") catch { _ => () })
  check_version(db, "latest_thread_meta", "latest thread index")
  if existing && !exists(db, "SELECT 1 FROM sessions WHERE key=?", [s]) {
    db.exec("COMMIT")
    return true
  }
  ignore(
    db.run(
      "INSERT INTO latest_thread_scopes(session,scan_end) SELECT ?1,(SELECT rowid FROM thread_sessions INDEXED BY thread_sessions_session WHERE session=?1 ORDER BY rowid DESC LIMIT 1) WHERE NOT EXISTS (SELECT 1 FROM latest_thread_scopes WHERE session=?1)",
      [s],
    ),
  )
  guard first_row(
      db,
      "SELECT CAST(scan_after AS TEXT) AS scan_after,CAST(scan_end AS TEXT) AS scan_end,complete FROM latest_thread_scopes WHERE session=?",
      [s],
    )
    is Some(scope) else {
    fail("latest thread scope is missing")
  }
  if is_one(value(scope, "complete")) {
    db.exec("COMMIT")
    return true
  }
  let after = value(scope, "scan_after")
  let lim = Json::number(limit.to_double())
  let rows = if after is Null {
    db.all(
      "SELECT CAST(rowid AS TEXT) AS rowid FROM thread_sessions INDEXED BY thread_sessions_session WHERE session=?1 AND rowid<=CAST(?2 AS INTEGER) ORDER BY thread_sessions.rowid LIMIT ?3",
      [s, value(scope, "scan_end"), lim],
    )
  } else {
    db.all(
      "SELECT CAST(rowid AS TEXT) AS rowid FROM thread_sessions INDEXED BY thread_sessions_session WHERE session=?1 AND rowid>CAST(?2 AS INTEGER) AND rowid<=CAST(?3 AS INTEGER) ORDER BY thread_sessions.rowid LIMIT ?4",
      [s, after, value(scope, "scan_end"), lim],
    )
  }
  for row in rows {
    ignore(db.run(add_member, [s, value(row, "rowid")]))
    ignore(db.run(add_candidate, [s, value(row, "rowid")]))
  }
  let done = rows.length() < limit
  let reached = match rows.last() {
    Some(r) => value(r, "rowid")
    None => after
  }
  ignore(
    db.run("UPDATE latest_thread_scopes SET scan_after=CAST(? AS INTEGER),complete=? WHERE session=?", [
      reached,
      Json::number(if done { 1.0 } else { 0.0 }),
      s,
    ]),
  )
  db.exec("COMMIT")
  done
}
