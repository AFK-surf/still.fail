// A session's page and the threads as a viewer reads them (station/src/read/sessions.ts `session`, `threads`,
// `thread`, `threadView`: GET /sessions/:key, GET /threads, GET /threads/:id): each thread with its sessions, last
// entry and message, where the viewer read to and how much they have not, who wrote, its letters, a Slack channel's
// name, the Slack and Feishu threads a still.fail chat copies to, and who it is shared with; a session with its
// summary, threads, turns and jobs.

///|
/// A session whose up jobs' lookup the pool is to prepare once this read is answered (read/worker.ts `Answer`
/// `prepareUpJobs`), set by `jobsNow`, taken by the reader.
pub let prepare_up_jobs : Ref[String?] = Ref(None)

///|
let cc_sessions_pending : String = "copy destination sessions pending:"

///|
/// A thread as listed for a viewer (store.ts `ThreadSummary`).
priv struct Summary {
  thread : Map[String, Json]
  sessions : Array[Map[String, Json]]
  last : Json
  last_message : Json
  read : Json
  unread : Json
  people : Json
  first_text : Json
  letters : Double
  letters_last : Double
  said_at : Double
}

///|
/// store.ts `listThreads(s, viewer, session, thread, "count", visibleTo)`: of one thread, of one session's, or all.
fn list_threads(db : @sql.Db, viewer : String, session : String?, thread : Json?, visible_to : Json?) -> Array[Summary] raise {
  let base = "SELECT t.*, COALESCE(r.n, 0) AS read_n FROM threads t LEFT JOIN reads r ON r.thread = t.id AND r.viewer = ?1"
  let where_ : Array[String] = []
  let args : Array[Json] = [Json::string(viewer)]
  match (thread, session) {
    (Some(t), _) => {
      where_.push("t.id = ?2")
      args.push(t)
    }
    (None, Some(s)) => {
      where_.push("t.id IN (SELECT thread FROM thread_sessions WHERE session = ?2)")
      args.push(Json::string(s))
    }
    _ => ()
  }
  let selected = if where_.length() == 0 { base } else { "\{base} WHERE \{where_.join(" AND ")}" }
  let and_ = if where_.length() == 0 { " WHERE " } else { " AND " }
  let rows = match visible_to {
    Some(v) => {
      let n = args.length()
      let scope = "EXISTS (SELECT 1 FROM thread_sessions visible_member\n      LEFT JOIN sessions visible_session ON visible_session.key = visible_member.session\n      WHERE visible_member.thread = t.id AND (visible_session.ws = ?\{n + 1}\n        OR (?\{n + 2} AND visible_session.ws IS NULL)))"
      let home = v.value("home") != Some(Json::boolean(false))
      try {
        db.all(selected + and_ + scope, args + [v.value("workspace").unwrap_or(Json::null()), Json::number(if home { 1.0 } else { 0.0 })])
      } catch {
        e => {
          guard sql_message(e).contains("no such column: visible_session.ws") else { raise e }
          if !home {
            return []
          }
          db.all(selected + and_ + "EXISTS (SELECT 1 FROM thread_sessions visible_member WHERE visible_member.thread = t.id)", args)
        }
      }
    }
    None => db.all(selected, args)
  }
  if rows.length() == 0 {
    return []
  }
  let slack = [Json::string(viewer)] + db.all("SELECT slack_user FROM identities WHERE viewer = ? ORDER BY at", [Json::string(viewer)]).map(r => field(r, "slack_user"))
  let own = Json::string(Json::array([Json::string(viewer)]).stringify())
  let slack_selves = Json::string(Json::array(slack).stringify())
  let legacy = has_legacy_said(db)
  let out : Array[Summary] = []
  for r in rows {
    let id = field(r, "id")
    let sessions = db.all("SELECT * FROM thread_sessions WHERE thread = ? ORDER BY joined_at, rowid", [id])
    let last = last_entry(db, id)
    let last_message = last_said(db, id)
    let read = field(r, "read_n")
    let selves = if field(r, "surface") != Json::string("ember") { slack_selves } else { own }
    let unread = match one(db, if legacy { legacy_unread_sql } else { unread_sql }, [id, read, selves]) {
      Some(u) => field(u, "c")
      None => Json::number(0.0)
    }
    let people = thread_people(db, id, field(r, "surface"))
    let first_text = first_text(db, id)
    let letters_last = num(max_n(db, "SELECT MAX(n) AS n FROM letters WHERE thread = ?", id))
    let kept_letters = match one(db, "SELECT letters FROM thread_state WHERE thread = ?", [id]) {
      Some(s) if !(field(s, "letters") is Null) => num(field(s, "letters"))
      _ => 0.0
    }
    let said_at = match last_message.value("createdAt") { Some(Number(n, ..)) => n; _ => 0.0 }
    out.push({ thread: r, sessions, last, last_message, read, unread, people, first_text, letters: letters_last + kept_letters, letters_last, said_at })
  }
  stable_sort(out, (a, b) => {
    for pair in [(a.said_at, b.said_at), (num(field(a.thread, "created_at")), num(field(b.thread, "created_at"))), (num(field(a.thread, "id")), num(field(b.thread, "id")))] {
      if pair.0 != pair.1 {
        return if pair.1 > pair.0 { 1 } else { -1 }
      }
    }
    0
  })
}

///|
/// store.ts `chatShares` of some sessions, whole: each workspace it is still shared with and its name, whether they may
/// write, who shared it and when.
fn shares_of(db : @sql.Db, ids : Array[String], now : Double) -> Map[String, Json] raise {
  let out : Map[String, Json] = Map([])
  let rows = try { db.all(shares_of_sql, [ids_json(ids.map(Json::string))]) } catch { _ => return out }
  for r in rows {
    let to = match parsed(field(r, "shared")) {
      Some(Arr(xs)) => xs
      _ => []
    }
    let live : Array[Json] = []
    for t in to {
      guard jget(Some(t), "workspace") is Some(Str(ws)) else { continue }
      let used = match jget(Some(t), "used") {
        Some(Num(u)) => u
        _ => num(field(r, "at"))
      }
      if now - used < 6.0 * 3600000.0 {
        let name = match jget(Some(t), "name") {
          None | Some(Null) => @jsjson.text(ws)
          Some(Str(n)) => @jsjson.text(n)
          Some(other) => js_string(to_json(other))
        }
        live.push({ "workspace": Json::string(@jsjson.text(ws)), "name": Json::string(name) })
      }
    }
    if live.length() > 0 {
      out[js_text(field(r, "session"))] = {
        "to": Json::array(live),
        "write": Json::boolean(field(r, "write") == Json::number(1.0)),
        "by": field(r, "by"),
        "at": field(r, "at"),
      }
    }
  }
  out
}

///|
/// JavaScript's `String(v)` of a value JSON.parse made.
fn js_string(v : Json) -> String {
  match v {
    Number(n, ..) => js_text(Json::number(n))
    True => "true"
    False => "false"
    Array(xs) => xs.map(x => if x is Null { "" } else { js_string(x) }).join(",")
    Object(_) => "[object Object]"
    String(s) => s
    Null => "null"
  }
}

///|
/// The session a thread's link names: its home, else its first session's.
fn share_key(t : Summary) -> String {
  match field(t.thread, "home") {
    String(h) => h
    _ =>
      match t.sessions.get(0) {
        Some(m) => js_text(field(m, "session"))
        None => ""
      }
  }
}

///|
/// cc-thread-index.ts `indexedCcThreads`: the Slack and Feishu threads a still.fail chat copies to, with the connect
/// posting in each; refused while one of its sessions' destinations is prepared.
fn cc_threads(db : @sql.Db, thread : Json) -> Array[Map[String, Json]] raise {
  db.exec("SAVEPOINT cc_threads_read")
  defer (db.exec("RELEASE cc_threads_read") catch { _ => () })
  let sessions = db.all("SELECT session FROM thread_sessions WHERE thread=? ORDER BY session", [thread]).map(r => field(r, "session"))
  let missing = sessions.filter(s => !@cc.ready(db, s)) catch { e => raise e }
  if missing.length() > 0 {
    raise Refused(503, cc_sessions_pending + Json::array(missing).stringify())
  }
  let candidates : Array[(Json, Json)] = []
  let seen : Set[String] = Set::new()
  for s in sessions {
    for row in db.all(cc_session_keys_sql, [s]) {
      let t = field(row, "thread")
      if !seen.contains(js_text(t)) {
        seen.add(js_text(t))
        candidates.push((t, s))
      }
    }
  }
  if candidates.length() == 0 {
    return []
  }
  db.all(cc_indexed_threads_sql, [Json::string(Json::array(candidates.map(c => Json::array([c.0, c.1]))).stringify())])
}

///|
/// sessions.ts `threadJson`: auto_title, home, hidden_at, hidden_by and shown_at left out when none.
fn listed_thread_json(t : Map[String, Json]) -> Map[String, Json] {
  let v : Map[String, Json] = {
    "id": field(t, "id"),
    "surface": field(t, "surface"),
    "channel": field(t, "channel"),
    "threadTs": field(t, "thread_ts"),
    "title": field(t, "title"),
  }
  if !(field(t, "auto_title") is Null) {
    v["autoTitle"] = field(t, "auto_title")
  }
  v["createdBy"] = field(t, "created_by")
  v["createdAt"] = field(t, "created_at")
  for pair in [("home", "home"), ("hiddenAt", "hidden_at"), ("hiddenBy", "hidden_by"), ("shownAt", "shown_at")] {
    if !(field(t, pair.1) is Null) {
      v[pair.0] = field(t, pair.1)
    }
  }
  v
}

///|
/// sessions.ts `threadView`.
fn thread_view(db : @sql.Db, known : Known, t : Summary, shares : Map[String, Json]) -> Json raise {
  let id = field(t.thread, "id")
  let names = known.author_names(db, id)
  let v = listed_thread_json(t.thread)
  v["sessions"] = Json::array(t.sessions.map(m => ({
    "thread": field(m, "thread"),
    "session": field(m, "session"),
    "connect": field(m, "connect"),
    "joinedAt": field(m, "joined_at"),
  } : Json)))
  v["last"] = t.last
  v["lastMessage"] = if t.last_message is Null { Json::null() } else { message_view(db, t.last_message, names) }
  v["read"] = t.read
  v["unread"] = t.unread
  v["people"] = Json::array(known.people(t.people))
  v["firstText"] = t.first_text
  if t.letters > 0.0 {
    v["letters"] = Json::number(t.letters)
  }
  if t.letters_last > 0.0 {
    v["lettersLast"] = Json::number(t.letters_last)
  }
  let own = field(t.thread, "surface") == Json::string("ember")
  v["channelName"] = if own { Json::null() } else { known.channel(slack_connect_of(t.sessions), field(t.thread, "channel")) }
  v["creator"] = known.creator(field(t.thread, "created_by"))
  if own {
    let to = cc_threads(db, id)
    if to.length() > 0 {
      let cc : Array[Json] = []
      for o in to {
        cc.push({
          "thread": field(o, "id"),
          "surface": field(o, "surface"),
          "channel": field(o, "channel"),
          "threadTs": field(o, "thread_ts"),
          "channelName": known.channel(match field(o, "connect") { String(c) => Some(c); _ => None }, field(o, "channel")),
        })
      }
      v["cc"] = Json::array(cc)
    }
  }
  v["xshare"] = shares.get(share_key(t)).unwrap_or(Json::null())
  Json::object(v)
}

///|
/// sessions.ts `threadViews`: the threads of the viewer's workspace (of one session).
fn thread_views(db : @sql.Db, known : Known, viewer : Json, session : String?) -> Array[Json] raise {
  let email = match viewer.value("email") { Some(String(e)) => e; _ => "" }
  let visible = list_threads(db, email, session, None, Some(viewer))
  // store.ts `requireCcSessions`
  let wanted : Array[Json] = []
  let seen : Set[String] = Set::new()
  for t in visible {
    if field(t.thread, "surface") == Json::string("ember") {
      for m in t.sessions {
        let s = js_text(field(m, "session"))
        if !seen.contains(s) {
          seen.add(s)
          wanted.push(field(m, "session"))
        }
      }
    }
  }
  let missing = wanted.filter(s => !@cc.ready(db, s)) catch { e => raise e }
  if missing.length() > 0 {
    raise Refused(503, cc_sessions_pending + Json::array(missing).stringify())
  }
  let shares = shares_of(db, visible.map(share_key), known.now)
  visible.map(t => thread_view(db, known, t, shares)) catch { e => raise e }
}

///|
/// sessions.ts `threads` (GET /threads?session=).
pub fn thread_list_of(db : @sql.Db, host : @host.Host, data : String, sep : String, ask : Json) -> Json raise {
  let args = ask.value("args").unwrap_or(Json::null())
  let session = match args.value("session") { Some(String(s)) => Some(s); _ => None }
  Json::array(thread_views(db, Known::of(host, data, sep, ask), args.value("viewer").unwrap_or(Json::null()), session))
}

///|
/// sessions.ts `parseI64`: digits with a sign at most, within an i64.
fn parse_i64(text : String) -> Json? {
  let cs = text.to_array()
  let start = if cs.length() > 0 && (cs[0] == '+' || cs[0] == '-') { 1 } else { 0 }
  if cs.length() == start || !cs[start:].iter().all(c => c >= '0' && c <= '9') {
    return None
  }
  let digits = String::from_array(cs[start:].to_array())
  let neg = cs[0] == '-'
  // (compared as digits: beyond an i64 is none)
  let trimmed = {
    let mut i = 0
    while i < digits.length() - 1 && digits.unsafe_get(i) == '0'.to_int().to_uint16() {
      i += 1
    }
    digits.view(start_offset=i).to_owned()
  }
  let limit = if neg { "9223372036854775808" } else { "9223372036854775807" }
  if trimmed.length() > 19 || (trimmed.length() == 19 && trimmed > limit) {
    return None
  }
  match (try { Ok(@json.parse(trimmed)) } catch { e => Err(e) }) {
    Ok(Number(n, ..)) => Some(Json::number(if neg { -n } else { n }))
    _ => None
  }
}

///|
/// store.ts `seesThread`.
fn sees_thread_of(db : @sql.Db, viewer : Json, thread : Json) -> Bool raise {
  let members = db.all("SELECT * FROM thread_sessions WHERE thread = ? ORDER BY joined_at, rowid", [thread])
  if members.length() == 0 {
    return sees(viewer, Json::null())
  }
  for m in members {
    if one(db, "SELECT * FROM sessions WHERE key = ?", [field(m, "session")]) is Some(s) && sees(viewer, field(s, "ws")) {
      return true
    }
  }
  false
}

///|
/// sessions.ts `thread` (GET /threads/:id).
pub fn thread_of(db : @sql.Db, host : @host.Host, data : String, sep : String, ask : Json) -> Json raise {
  let args = ask.value("args").unwrap_or(Json::null())
  let viewer = args.value("viewer").unwrap_or(Json::null())
  let id = js_text(args.value("id").unwrap_or(Json::null()))
  guard parse_i64(id) is Some(n) &&
    one(db, "SELECT * FROM threads WHERE id = ?", [n]) is Some(_) &&
    sees_thread_of(db, viewer, n) else {
    raise Refused(404, "unknown thread \{id}")
  }
  let email = match viewer.value("email") { Some(String(e)) => e; _ => "" }
  guard list_threads(db, email, None, Some(n), None).get(0) is Some(found) else {
    raise Refused(404, "unknown thread \{js_text(n)}")
  }
  let known = Known::of(host, data, sep, ask)
  thread_view(db, known, found, shares_of(db, [share_key(found)], known.now))
}

///|
/// store.ts `jobsNow`: a session's latest jobs and those of it still up.
fn jobs_now(db : @sql.Db, session : String) -> Array[Map[String, Json]] raise {
  let key = Json::string(session)
  let by_start = (rows : Array[Map[String, Json]]) => stable_sort(rows, (a, b) => {
    let d = num(field(b, "started_at")) - num(field(a, "started_at"))
    if d < 0.0 { -1 } else if d > 0.0 { 1 } else { 0 }
  })
  let latest = db.all(latest_jobs_sql, [key, Json::number(51.0)])
  if latest.length() <= 50 {
    return by_start(latest)
  }
  let ready = try {
    let r = session_up_jobs_ready(db, key)
    if !r {
      prepare_up_jobs.val = Some(session)
    }
    r
  } catch {
    e => {
      guard sql_message(e).contains("no such table: session_up_job_meta") else { raise e }
      false
    }
  }
  let by_id : Map[String, Map[String, Json]] = Map([])
  for r in latest[:50].to_array() + db.all(if ready { prepared_up_jobs_of_sql } else { up_jobs_of_sql }, [key]) {
    by_id[js_text(field(r, "id"))] = r
  }
  by_start(by_id.values().collect())
}

///|
/// sessions.ts `session` (GET /sessions/:key): the session, its threads, turns and jobs (newest first).
pub fn session_page(db : @sql.Db, host : @host.Host, data : String, sep : String, ask : Json) -> Json raise {
  let args = ask.value("args").unwrap_or(Json::null())
  let viewer = args.value("viewer").unwrap_or(Json::null())
  let key = js_text(args.value("key").unwrap_or(Json::null()))
  if one(db, "SELECT * FROM sessions WHERE key = ?", [Json::string(key)]) is Some(row) && !sees(viewer, field(row, "ws")) {
    raise Refused(404, "unknown session \{key}")
  }
  // (`?turns=`: how many of its latest, ops-sessions.ts `latest`)
  let last = match args.value("turns") {
    Some(String(t)) if t.length() >= 1 && t.length() <= 6 && t.iter().all(c => c >= '0' && c <= '9') =>
      Some(@json.parse(t) catch { _ => Json::null() })
    _ => None
  }
  let turn_rows = match last {
    None => db.all("SELECT * FROM turns WHERE session_key = ? ORDER BY started_at", [Json::string(key)])
    Some(n) => db.all(latest_turns_sql, [Json::string(key), n]).rev()
  }
  let turns = turn_rows.map(r => {
    r["turn_id"] = field(r, "id")
    latest_turn(r)
  })
  let job_rows = if args.value("jobs") == Some(Json::string("now")) { jobs_now(db, key) } else { db.all(session_jobs_sql, [Json::string(key)]) }
  let jobs = job_rows.map(j => shown(db, host, j)) catch { e => raise e }
  let known = Known::of(host, data, sep, ask)
  let summary = summary_with(db, known, key, lists_of(db, [key]))
  {
    "session": summary,
    "threads": Json::array(thread_views(db, known, viewer, Some(key))),
    "turns": Json::array(turns),
    "jobs": Json::array(jobs),
  }
}
