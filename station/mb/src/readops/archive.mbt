// One look of the auto-archive (station/src/store/store.ts `archiveLookOf`, sessions/lifecycle.ts): the sessions shown
// that are idle long enough by their times, each with what archiving needs to know of it (`archiveFactsOf`); the chats
// of their own idle long enough and not kept, their latest message as store/archive-last.ts finds it; when the next
// one comes due. Rows are written out as rows.ts writes them (`toSession`, `toThread`, `toTurnSummary`). The
// statements are the TypeScript's, as it makes them.

///|
/// store/store.ts WORK_OF_SESSION.
let work_of_session_sql : String =
  #|SELECT
  #|  CASE WHEN EXISTS (SELECT 1 FROM deliveries d INDEXED BY deliveries_pending WHERE d.session = s.key AND d.delivered_at IS NULL)
  #|    THEN 1 ELSE EXISTS (SELECT 1 FROM letter_deliveries d INDEXED BY letter_deliveries_pending WHERE d.session = s.key AND d.delivered_at IS NULL) END AS pending,
  #|  l.kind, l.outcome, l.declared, l.wait_seconds, l.wait_for, l.wait_watch, l.need,
  #|  l.about_thread, l.about_n, l.about_ts, l.detail, l.started_at, l.ended_at FROM sessions s
  #|  LEFT JOIN turns l ON l.id = (SELECT id FROM turns t2 WHERE t2.session_key = s.key ORDER BY t2.started_at DESC, t2.rowid DESC LIMIT 1)
  #|  WHERE s.key = ?

///|
/// store/archive-last.ts ARCHIVE_LAST_FIRST.
let archive_last_first_sql : String =
  #|SELECT CASE WHEN e.kind='message' THEN CAST(e.n AS TEXT) END AS n,
  #|    CASE WHEN e.kind='message' THEN e.at END AS at
  #|  FROM entries e WHERE e.thread=? ORDER BY e.n DESC LIMIT 1

///|
/// store/archive-last.ts ARCHIVE_LAST_TAIL.
let archive_last_tail_sql : String =
  #|WITH tail AS MATERIALIZED (
  #|    SELECT e.n,e.kind,e.at FROM entries e WHERE e.thread=? ORDER BY e.n DESC LIMIT 65
  #|  ), last AS MATERIALIZED (SELECT n,at FROM tail WHERE kind='message' ORDER BY n DESC LIMIT 1)
  #|  SELECT (SELECT CAST(n AS TEXT) FROM last) AS n,(SELECT at FROM last) AS at,(SELECT COUNT(*) FROM tail) AS count

///|
/// store/archive-last.ts ARCHIVE_LAST_GUARD.
let archive_last_guard_sql : String =
  #|SELECT CAST(g.before_n AS TEXT) AS n,g.at FROM archive_last_meta m CROSS JOIN archive_last_guard g
  #|  WHERE m.id=1 AND g.thread=? AND g.epoch=m.epoch AND g.ready=1

///|
fn col(r : Map[String, Json], name : String) -> Json? {
  r.get(name)
}

///|
/// A row's column put in an object as JSON.stringify keeps it: left out when the row has none (an older store's).
fn put_col(out : Map[String, Json], name : String, v : Json?) -> Unit {
  if v is Some(v) {
    out[name] = v
  }
}

///|
fn is_one(v : Json?) -> Bool {
  v is Some(Number(1.0, ..))
}

///|
/// A flag kept as 0 or 1, null where it is not set (rows.ts `toSession`'s fast and afresh).
fn flag_or_null(v : Json?) -> Json {
  match v {
    None | Some(Null) => Json::null()
    Some(Number(0.0, ..)) => Json::boolean(false)
    Some(_) => Json::boolean(true)
  }
}

///|
fn number_or_null(v : Json?) -> Json {
  match v {
    Some(Number(_, ..) as n) => n
    _ => Json::null()
  }
}

///|
fn or_null(v : Json?) -> Json {
  match v {
    Some(v) => v
    None => Json::null()
  }
}

///|
/// rows.ts `toSession`.
fn session_json(r : Map[String, Json]) -> Json {
  let out : Map[String, Json] = Map([])
  put_col(out, "key", col(r, "key"))
  put_col(out, "connect", col(r, "connect"))
  out["scope"] = if col(r, "scope") == Some(Json::string("all")) { "all" } else { "thread" }
  put_col(out, "title", col(r, "title"))
  put_col(out, "createdBy", col(r, "created_by"))
  put_col(out, "runtime", col(r, "runtime"))
  put_col(out, "profile", col(r, "profile"))
  out["profilePinned"] = Json::boolean(is_one(col(r, "profile_pinned")))
  put_col(out, "model", col(r, "model"))
  put_col(out, "effort", col(r, "effort"))
  out["fast"] = flag_or_null(col(r, "fast"))
  out["afresh"] = flag_or_null(col(r, "afresh"))
  out["context"] = number_or_null(col(r, "context"))
  out["contextBefore"] = number_or_null(col(r, "context_before"))
  put_col(out, "runtimeSessionId", col(r, "runtime_session_id"))
  put_col(out, "workspace", col(r, "workspace"))
  out["cwd"] = or_null(col(r, "cwd"))
  out["ws"] = or_null(col(r, "ws"))
  put_col(out, "token", col(r, "token"))
  out["running"] = Json::boolean(is_one(col(r, "running")))
  put_col(out, "createdAt", col(r, "created_at"))
  put_col(out, "lastActiveAt", col(r, "last_active_at"))
  put_col(out, "archivedAt", col(r, "archived_at"))
  put_col(out, "archivedBy", col(r, "archived_by"))
  put_col(out, "shownAt", col(r, "shown_at"))
  Json::object(out)
}

///|
/// rows.ts `toThread`.
fn thread_json(r : Map[String, Json]) -> Json {
  let out : Map[String, Json] = Map([])
  for pair in [
    ("id", "id"), ("surface", "surface"), ("channel", "channel"), ("threadTs", "thread_ts"), ("title", "title"), ("autoTitle", "auto_title"),
    ("createdBy", "created_by"), ("createdAt", "created_at"), ("home", "home"), ("hiddenAt", "hidden_at"), ("hiddenBy", "hidden_by"),
    ("shownAt", "shown_at"),
  ] {
    put_col(out, pair.0, col(r, pair.1))
  }
  Json::object(out)
}

///|
/// rows.ts `saidBefore` and `ending`: a declared ending in the words of before, and in today's.
fn said_before(d : String) -> String {
  match d {
    "all_done" => "final"
    "need_decision" | "need_help" => "block"
    d => d
  }
}

///|
fn ending_of(d : String) -> String {
  match d {
    "final" => "all_done"
    "block" | "need_decision" => "need_help"
    d => d
  }
}

///|
/// rows.ts `toTurnSummary`.
fn turn_summary_json(r : Map[String, Json]) -> Json {
  let declared = or_null(col(r, "declared"))
  let out : Map[String, Json] = Map([])
  put_col(out, "kind", col(r, "kind"))
  put_col(out, "outcome", col(r, "outcome"))
  out["declared"] = match declared { String(d) => Json::string(said_before(d)); Null => Json::null(); d => d }
  out["ending"] = match declared { String(d) => Json::string(ending_of(d)); Null => Json::null(); d => d }
  put_col(out, "need", col(r, "need"))
  let about = (or_null(col(r, "about_thread")), or_null(col(r, "about_n")), or_null(col(r, "about_ts")))
  out["about"] = if about.0 is Null || about.1 is Null || about.2 is Null {
    Json::null()
  } else {
    { "thread": about.0, "seq": about.1, "ts": about.2 }
  }
  put_col(out, "waitSeconds", col(r, "wait_seconds"))
  put_col(out, "waitFor", col(r, "wait_for"))
  out["waitWatch"] = match col(r, "wait_watch") {
    None | Some(Null) => Json::null()
    w => Json::boolean(is_one(w))
  }
  put_col(out, "detail", col(r, "detail"))
  put_col(out, "startedAt", col(r, "started_at"))
  put_col(out, "endedAt", col(r, "ended_at"))
  Json::object(out)
}

///|
/// archive-mark-index.ts `archiveMarksReady`: both mark lookups (kept chats, pinned sessions) built.
fn archive_marks_ready(db : @sql.Db) -> Bool raise {
  let rows = db.all("SELECT kind, version, CAST(last_rowid AS TEXT) AS last_rowid,\n    CAST(end_rowid AS TEXT) AS end_rowid, complete FROM archive_mark_meta ORDER BY kind", [])
  guard rows.length() == 2 && field(rows[0], "kind") == Json::string("kept") && field(rows[1], "kind") == Json::string("pins") else {
    fail("archive mark index version marker is missing")
  }
  for r in rows {
    if !(field(r, "version") is Number(1.0, ..)) {
      fail("archive mark index version \{field(r, "version").stringify()} is incompatible with 1")
    }
  }
  rows.iter().all(r => field(r, "complete") is Number(1.0, ..))
}

///|
/// session-bindings-index.ts `sessionBindingsReady`.
fn session_bindings_ready(db : @sql.Db) -> Bool raise {
  guard one(db, "SELECT version, complete FROM session_binding_meta WHERE id = 1", []) is Some(m) else {
    fail("session binding index version marker is missing")
  }
  if !(field(m, "version") is Number(1.0, ..)) {
    fail("session binding index version \{field(m, "version").stringify()} is incompatible with 1")
  }
  field(m, "complete") is Number(1.0, ..)
}

///|
/// session-up-jobs.ts `sessionUpJobsReady`.
fn session_up_jobs_ready(db : @sql.Db, session : Json) -> Bool raise {
  let meta = one(db, "SELECT version, fresh FROM session_up_job_meta WHERE id = 1", [])
  guard meta is Some(m) && field(m, "version") is Number(1.0, ..) else {
    let had = match meta { Some(m) => field(m, "version").stringify(); None => "missing" }
    fail("session up jobs index version \{had} is incompatible with 1")
  }
  if field(m, "fresh") is Number(1.0, ..) {
    return true
  }
  match one(db, "SELECT complete FROM session_up_job_scopes WHERE session = ?", [session]) {
    Some(s) => field(s, "complete") is Number(1.0, ..)
    None => false
  }
}

///|
/// archive-last.ts `installArchiveLast(db, false)`: whether its tables, version and triggers are in place.
fn archive_last_installed(db : @sql.Db) -> Bool raise {
  if !exists_in(db, "table", "archive_last_meta") || !exists_in(db, "table", "archive_last_guard") {
    return false
  }
  guard one(db, "SELECT version FROM archive_last_meta WHERE id=1", []) is Some(v) else { return false }
  if !(field(v, "version") is Number(1.0, ..)) {
    fail("archive last metadata has an unsupported version")
  }
  for name in ["archive_last_insert", "archive_last_update", "archive_last_delete", "archive_last_thread_delete"] {
    match one(db, "SELECT sql FROM sqlite_master WHERE type=? AND name=?", [Json::string("trigger"), Json::string(name)]) {
      Some(r) if field(r, "sql") is String(sql) && sql.contains("archive_last_v1") => ()
      _ => return false
    }
  }
  true
}

///|
/// archive-last.ts `archiveLastRead`: a chat's latest message's time, if known (null for none), in one snapshot.
fn archive_last_read(db : @sql.Db, thread : Json) -> (Bool, Json) raise {
  if !archive_last_installed(db) {
    return (false, Json::null())
  }
  db.exec("SAVEPOINT archive_last_read")
  defer (db.exec("RELEASE archive_last_read") catch { _ => () })
  let answer = () => {
    guard one(db, "SELECT version FROM archive_last_meta WHERE id=1", []) is Some(meta) else { return (false, Json::null()) }
    if !(field(meta, "version") is Number(1.0, ..)) {
      fail("archive last version \{field(meta, "version").stringify()} is incompatible")
    }
    guard one(db, archive_last_first_sql, [thread]) is Some(first) else { return (true, Json::null()) }
    if !(field(first, "at") is Null) {
      return (true, field(first, "at"))
    }
    if one(db, archive_last_guard_sql, [thread]) is Some(cached) {
      return (true, field(cached, "at"))
    }
    guard one(db, archive_last_tail_sql, [thread]) is Some(tail) else { return (false, Json::null()) }
    let count = match field(tail, "count") { Number(c, ..) => c; _ => 0.0 }
    if !(field(tail, "at") is Null) || count < 65.0 {
      return (true, field(tail, "at"))
    }
    (false, Json::null())
  }
  answer() catch {
    e => {
      let m = sql_message(e)
      if m.contains("no such table: archive_last_meta") || m.contains("no such table: archive_last_guard") {
        (false, Json::null())
      } else {
        raise e
      }
    }
  }
}

///|
/// store.ts `recentThreadRows` (its RECENT_THREADS is `limit` here): a session's own chat, then half of those it heard
/// from last (the latest thread's order, once prepared) and half of those it joined last, then the rest of each, at most
/// `limit`; all of them, in sessionThreads' order, where it has no more.
fn recent_threads(db : @sql.Db, key : Json, limit : Int) -> Array[Map[String, Json]] raise {
  let n = Json::number(limit.to_double())
  let joined = db.all(
    "SELECT t.*, ts.connect FROM thread_sessions ts INDEXED BY thread_sessions_session CROSS JOIN threads t ON t.id = ts.thread WHERE ts.session = ?1 ORDER BY ts.rowid DESC LIMIT ?2",
    [key, Json::number((limit + 1).to_double())],
  )
  if joined.length() <= limit {
    return db.all(
      "SELECT t.*, ts.connect FROM thread_sessions ts JOIN threads t ON t.id = ts.thread WHERE ts.session = ?1 ORDER BY ts.joined_at DESC, ts.rowid DESC LIMIT ?2",
      [key, n],
    )
  }
  let ready = match one(db, "SELECT (SELECT version FROM latest_thread_meta WHERE id=1) AS version, COALESCE((SELECT complete FROM latest_thread_scopes WHERE session=?1),0) AS ready", [key]) {
    Some(r) => field(r, "version") is Number(1.0, ..) && field(r, "ready") is Number(1.0, ..)
    None => false
  }
  let heard = if ready {
    db.all(
      "SELECT t.*,m.connect FROM latest_thread_rows r CROSS JOIN thread_sessions m ON m.session=r.session AND m.thread=r.thread CROSS JOIN threads t ON t.id=r.thread WHERE r.session=?1 ORDER BY r.has_last DESC,r.last_delivery DESC,r.joined_at DESC,r.member_rowid DESC LIMIT ?2",
      [key, n],
    )
  } else {
    []
  }
  let home = db.all(
    "SELECT t.*, ts.connect FROM threads t INDEXED BY threads_home CROSS JOIN thread_sessions ts WHERE t.home = ?1 AND ts.thread = t.id AND ts.session = ?1 ORDER BY ts.joined_at DESC, ts.rowid DESC LIMIT 1",
    [key],
  )
  let half = (limit + 1) / 2
  let order : Array[Map[String, Json]] = []
  order.push_iter(home.iter())
  order.push_iter(heard.iter().take(half))
  order.push_iter(joined.iter().take(half))
  order.push_iter(heard.iter().drop(half))
  order.push_iter(joined.iter().drop(half))
  let seen : Array[Json] = []
  let rows : Array[Map[String, Json]] = []
  for r in order {
    if rows.length() == limit {
      break
    }
    let id = field(r, "id")
    if seen.contains(id) {
      continue
    }
    seen.push(id)
    rows.push(r)
  }
  rows
}

///|
/// store.ts `archiveFactsOf` for one session: none when it is not there.
fn archive_facts(db : @sql.Db, key : Json, bindings : Bool, marks : Bool) -> Json? raise {
  guard one(db, work_of_session_sql, [key]) is Some(w) else { return None }
  let work : Json = {
    "pending": Json::boolean(field(w, "pending") != Json::number(0.0)),
    "lastTurn": if field(w, "started_at") is Null { Json::null() } else { turn_summary_json(w) },
  }
  let chats = recent_threads(db, key, 20)
  let threads = chats.map(r => ({ "thread": thread_json(r), "connect": or_null(col(r, "connect")) } : Json))
  let kept = if marks {
    let ids = []
    for r in chats {
      if one(db, "SELECT 1 FROM archive_keep_rows WHERE thread = ? LIMIT 1", [field(r, "id")]) is Some(_) {
        ids.push(field(r, "id"))
      }
    }
    Json::array(ids)
  } else {
    Json::null()
  }
  Some({
    "bound": if bindings { Json::boolean(one(db, "SELECT 1 FROM session_binding_rows WHERE session = ? LIMIT 1", [key]) is Some(_)) } else { Json::null() },
    "pinned": if marks { Json::boolean(one(db, "SELECT 1 FROM archive_pin_rows WHERE session = ? LIMIT 1", [key]) is Some(_)) } else { Json::null() },
    "threads": Json::array(threads),
    "kept": kept,
    "work": work,
    "upJob": if session_up_jobs_ready(db, key) { Json::boolean(one(db, "SELECT 1 FROM session_up_job_rows WHERE session = ? LIMIT 1", [key]) is Some(_)) } else { Json::null() },
  })
}

///|
/// Number(v) of an argument.
fn num_arg(v : Json?) -> Double {
  match arg_number(v) {
    Number(n, ..) => n
    _ => nan()
  }
}

///|
/// store.ts `archiveLookOf`: one look of the auto-archive at `now`, sessions idle `after` (Slack ones `slackAfter`).
pub fn archive_look(db : @sql.Db, args : Json) -> Json raise {
  let now = num_arg(args.value("now"))
  let after = num_arg(args.value("after"))
  let slack_after = num_arg(args.value("slackAfter"))
  let mut next : Double? = None
  let idle = (at : Array[Json], wait : Double) => {
    if !(wait > 0.0) {
      return false
    }
    let mut most = 0.0
    for a in at {
      if a is Number(n, ..) && (n > most || n.is_nan()) {
        most = n
      }
    }
    let due = most + wait
    if due > now && (next is None || due < next.unwrap()) {
      next = Some(due)
    }
    due <= now
  }
  let marks = archive_marks_ready(db)
  let idle_sessions : Array[(Map[String, Json], Bool, Bool)] = []
  for r in db.all("SELECT * FROM sessions WHERE archived_at IS NULL ORDER BY last_active_at DESC", []) {
    let times = [field(r, "last_active_at"), field(r, "shown_at")]
    let quiet = idle(times, after)
    let quiet_long = idle(times, slack_after)
    if quiet || quiet_long {
      idle_sessions.push((r, quiet, quiet_long))
    }
  }
  let bindings = session_bindings_ready(db)
  let facts_marks = archive_marks_ready(db)
  let sessions = []
  for s in idle_sessions {
    if archive_facts(db, field(s.0, "key"), bindings, facts_marks) is Some(f) {
      sessions.push(({ "row": session_json(s.0), "quiet": Json::boolean(s.1), "quietLong": Json::boolean(s.2), "facts": f } : Json))
    }
  }
  let own = []
  let own_unknown = []
  for t in db.all("SELECT * FROM threads WHERE surface = ? AND home IS NULL AND hidden_at IS NULL", [Json::string("ember")]) {
    let id = field(t, "id")
    if marks && one(db, "SELECT 1 FROM archive_keep_rows WHERE thread = ? LIMIT 1", [id]) is Some(_) {
      continue
    }
    let (known, at) = archive_last_read(db, id)
    if !known {
      own_unknown.push(id)
      continue
    }
    if idle([field(t, "created_at"), at, field(t, "shown_at")], after) {
      own.push(thread_json(t))
    }
  }
  {
    "next": match next { Some(n) => Json::number(n); None => Json::null() },
    "sessions": Json::array(sessions),
    "own": Json::array(own),
    "ownUnknown": Json::array(own_unknown),
    "marksReady": Json::boolean(marks),
  }
}
