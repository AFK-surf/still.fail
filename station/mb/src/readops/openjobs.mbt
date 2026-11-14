// The jobs up of the viewer's workspace (station/src/read/jobs.ts `openJobs`: GET /jobs), each as the pages show it,
// and, for a device from before that does not name them from the list it holds (`chats` not false), the chat each is in:
// the session's own over one it only takes part in, a listed one over an archived one, made of the items its session
// and its chats make (views.ts `scopeOfJobNames`, `chats(…, titlesOnly)`).

///|
/// The pool is to prepare the workspace up jobs' lookup once this read is answered (read/worker.ts `Answer`
/// `prepareWorkspaceUpJobs`), set by `upJobs`, taken by the reader.
pub let prepare_workspace_up_jobs : Ref[Bool] = Ref(false)

///|
/// store.ts `upJobs`: the jobs up a viewer may see, newest first (a superset, `seenBy` decides).
fn up_jobs(db : @sql.Db, viewer : Json) -> Array[Map[String, Json]] raise {
  let ws = match viewer.value("workspace") { Some(String(w)) => w; _ => "" }
  if !ws.iter().all(c => c.to_int() >= 0x20 && c.to_int() <= 0x7e) {
    return db.all(jobs_up_sql, [])
  }
  let home = Json::number(if viewer.value("home") == Some(Json::boolean(false)) { 0.0 } else { 1.0 })
  let ready = try {
    match one(db, "SELECT version,ready FROM workspace_up_meta WHERE id=1", []) {
      Some(m) if field(m, "version") == Json::number(1.0) => Some(field(m, "ready") == Json::number(1.0))
      m => raise Failure("workspace up jobs index version \{match m { Some(m) => js_text(field(m, "version")); None => "missing" }} is incompatible with 1")
    }
  } catch {
    e => {
      guard sql_message(e).contains("no such table: workspace_up_meta") else { raise e }
      None
    }
  }
  if ready is Some(true) {
    return db.all(workspace_up_jobs_sql, [Json::string(ws), home])
  }
  if ready is Some(false) {
    prepare_workspace_up_jobs.val = true
  }
  db.all(jobs_up_in_workspace_sql, [Json::string(ws), home]) catch {
    e => {
      guard sql_message(e).contains("no such column: s.ws") else { raise e }
      if home == Json::number(1.0) { db.all(jobs_up_sql, []) } else { [] }
    }
  }
}

///|
/// store.ts `seenBy` of some sessions: which a viewer sees (a missing one counts as the home workspace's).
fn seen_by(db : @sql.Db, viewer : Json, keys : Array[String]) -> ((String) -> Bool) raise {
  let wanted : Set[String] = Set::new()
  for k in keys {
    wanted.add(k)
  }
  let ws : Map[String, Json] = Map([])
  if keys.length() > 0 {
    let list = [ids_json(keys.map(Json::string))]
    let first = try { Some(db.all("SELECT key, ws FROM sessions INDEXED BY sessions_ws WHERE key IN (SELECT value FROM json_each(?))", list)) } catch {
      _ => None
    }
    let rows = match first {
      Some(r) => r
      // (a database from before has no `ws`: every chat its home workspace's)
      None => db.all("SELECT * FROM sessions WHERE key IN (SELECT value FROM json_each(?))", list)
    }
    for r in rows {
      ws[js_text(field(r, "key"))] = field(r, "ws")
    }
  }
  k => wanted.contains(k) && sees(viewer, ws.get(k).unwrap_or(Json::null()))
}

///|
/// store.ts `missingOriginIndex`.
fn missing_origin_index(e : Error) -> Bool {
  let m = sql_message(e)
  for name in ["cc_index_meta", "cc_sessions", "cc_session_rows", "cc_session_dirty", "cc_order_dispatch", "cc_session_order", "thread_sessions_session"] {
    for kind in ["table", "index"] {
      if m == "no such \{kind}: \{name}" || m == "no such \{kind}: main.\{name}" {
        return true
      }
    }
  }
  false
}

///|
/// store.ts `preparedOriginIndexAvailable`.
fn prepared_origin_index(db : @sql.Db) -> Bool raise {
  match one(db, "SELECT \"notnull\" AS required FROM pragma_table_info('threads') WHERE name = 'surface'", []) {
    Some(r) if field(r, "required") == Json::number(1.0) => ()
    _ => return false
  }
  match one(db, "SELECT version FROM cc_index_meta WHERE id = 1", []) {
    Some(r) => field(r, "version") == Json::number(cc_index_version)
    None => false
  }
}

///|
/// store.ts `namingOriginProbe`: whether a member has an external thread visible to the shared reader.
fn naming_origin(db : @sql.Db, session : String, prepared_ok : Bool) -> Bool raise {
  let original = () => one(db, has_naming_origin_sql, [Json::string(session), Json::string("ember")]) is Some(_)
  if !prepared_ok {
    return original()
  }
  let possible = () => one(db, has_naming_origin_possible_sql, [Json::string(session)]) is Some(_)
  let first = try { Some(possible()) } catch { e => if missing_origin_index(e) { None } else { raise e } }
  guard first is Some(true) else { return original() }
  db.exec("SAVEPOINT naming_origin_probe")
  defer (db.exec("RELEASE naming_origin_probe") catch { _ => () })
  let answer = try {
    if !possible() || !@cc.ready(db, Json::string(session)) {
      None
    } else {
      Some(one(db, has_naming_origin_prepared_sql, [Json::string(session)]) is Some(_))
    }
  } catch {
    e => if missing_origin_index(e) || sql_message(e).has_prefix("copy destination index version ") { None } else { raise e }
  }
  match answer {
    Some(a) => a
    None => original()
  }
}

///|
/// store.ts `latestNamingOrigins`: each session's latest external origin, as threadsForChatNames orders them.
fn latest_naming_origins(db : @sql.Db, sessions : Array[String]) -> Array[Json] raise {
  if sessions.length() == 0 {
    return []
  }
  let original = (keys : Array[String]) => db.all(latest_naming_origin_sql, [ids_json(keys.map(Json::string)), Json::string("ember")]).map(r => field(r, "id"))
  db.exec("SAVEPOINT latest_naming_origins")
  defer (db.exec("RELEASE latest_naming_origins") catch { _ => () })
  let found = try {
    if !prepared_origin_index(db) {
      original(sessions)
    } else {
      let possible : Set[Int] = Set::new()
      for r in db.all(latest_naming_origin_possible_sql, [ids_json(sessions.map(Json::string))]) {
        possible.add(num(field(r, "ordinal")).to_int())
      }
      let ids : Array[Json] = Array::make(sessions.length(), Json::null())
      let pending : Array[String] = []
      let positions : Array[Int] = []
      for i, session in sessions {
        if possible.contains(i) && @cc.ready(db, Json::string(session)) {
          match one(db, latest_naming_origin_prepared_sql, [Json::string(session)]) {
            Some(c) if num(field(c, "count")) < 9.0 => {
              ids[i] = field(c, "id")
              continue
            }
            _ => ()
          }
        }
        pending.push(session)
        positions.push(i)
      }
      if pending.length() > 0 {
        for i, id in original(pending) {
          ids[positions[i]] = id
        }
      }
      ids
    }
  } catch {
    e =>
      if missing_origin_index(e) || sql_message(e).has_prefix("copy destination index version ") {
        original(sessions)
      } else {
        raise e
      }
  }
  found.filter(id => !(id is Null))
}

///|
/// store.ts `jobNameFirstMembers`: a large named own chat of the only job session, its first member alone where that
/// is the session; none to read its members as ever; refused while its lookup is prepared.
fn job_name_first_members(db : @sql.Db, owner : String, thread : Json) -> Array[Map[String, Json]]? raise {
  if one(db, job_name_first_large_sql, [thread]) is None {
    return None
  }
  let pending = () => Refused(503, job_name_first_pending + Json::array([Json::string(owner), thread]).stringify())
  let answer = () => {
    match one(db, "SELECT version FROM job_name_first_meta WHERE id=1", []) {
      Some(r) if field(r, "version") == Json::number(1.0) => ()
      r => raise Failure("job name first index version \{match r { Some(r) => js_text(field(r, "version")); None => "missing" }} is incompatible with 1")
    }
    match one(db, "SELECT thread,ready,restart FROM job_name_first WHERE owner=?", [Json::string(owner)]) {
      Some(scope) => {
        if field(scope, "thread") != thread {
          return None
        }
        if field(scope, "ready") != Json::number(1.0) || field(scope, "restart") != Json::number(0.0) {
          raise pending()
        }
        match one(db, job_name_first_row_sql, [Json::string(owner), thread]) {
          Some(first) if field(first, "session") == Json::string(owner) => Some([first])
          _ => None
        }
      }
      None => {
        if one(db, "SELECT 1 AS x FROM job_name_first WHERE thread=?", [thread]) is Some(_) ||
          one(db, "SELECT 1 AS x FROM session_up_job_rows WHERE session=? LIMIT 1", [Json::string(owner)]) is None {
          return None
        }
        raise pending()
      }
    }
  }
  answer() catch {
    Refused(_, _) as r => raise r
    e => {
      let m = sql_message(e)
      for t in ["job_name_first_meta", "job_name_first", "session_up_job_rows"] {
        if m == "no such table: \{t}" || m == "no such table: main.\{t}" {
          return None
        }
      }
      raise e
    }
  }
}

///|
/// What names a job's chat (views.ts `Scope` of `scopeOfJobNames`): the rows, the agents, the threads and their members.
priv struct JobScope {
  rows : Array[String]
  agents : Array[String]
  threads : Array[Json]
  members : Map[String, Array[Map[String, Json]]]
}

///|
/// views.ts `scopeOfJobNames`.
fn scope_of_job_names(db : @sql.Db, keys : Array[String]) -> JobScope raise {
  let rows = unique_keys([keys])
  let rows_seen : Set[String] = Set::new()
  for k in rows {
    rows_seen.add(k)
  }
  let agents = rows.copy()
  let agents_seen : Set[String] = Set::new()
  for k in agents {
    agents_seen.add(k)
  }
  let origins : Array[String] = []
  let origins_seen : Set[String] = Set::new()
  let has_chat : Set[String] = Set::new()
  let members_of : Map[String, Array[Map[String, Json]]] = Map([])
  let target : Map[String, Map[String, Json]?] = Map([])
  for k in keys {
    target[k] = one(db, "SELECT * FROM sessions WHERE key = ?", [Json::string(k)])
  }
  let owner = if keys.length() == 1 { Some(keys[0]) } else { None }
  let chats = if keys.length() == 0 {
    []
  } else {
    db
    .all("SELECT DISTINCT t.id FROM thread_sessions m CROSS JOIN threads t ON t.id = m.thread\n    WHERE m.session IN (SELECT value FROM json_each(?1)) AND t.surface = ?2", [ids_json(keys.map(Json::string)), Json::string("ember")])
    .map(r => field(r, "id"))
  }
  let checked : Map[String, Bool] = Map([])
  let prepared_ok : Ref[Bool?] = Ref(None)
  for id in chats {
    guard one(db, "SELECT * FROM threads WHERE id = ?", [id]) is Some(thread) else { continue }
    let given = given_title(thread)
    let own = match owner {
      Some(o) =>
        field(thread, "home") == Json::string(o) && field(thread, "hidden_at") is Null && given &&
        (match target.get(o) { Some(Some(s)) => field(s, "archived_at") is Null; _ => false })
      None => false
    }
    let members = match (if own { job_name_first_members(db, owner.unwrap(), id) } else { None }) {
      Some(m) => m
      None => db.all("SELECT * FROM thread_sessions WHERE thread = ? ORDER BY joined_at, rowid", [id])
    }
    members_of[js_text(id)] = members
    for m in members {
      let s = js_text(field(m, "session"))
      push_new(rows, rows_seen, s)
      push_new(agents, agents_seen, s)
      if target.get(s) is Some(Some(session)) && !(field(thread, "hidden_at") is Null) == !(field(session, "archived_at") is Null) {
        has_chat.add(s)
      }
    }
    if !given {
      for m in members {
        let s = js_text(field(m, "session"))
        let found = match checked.get(s) {
          Some(f) => f
          None => {
            let ok = match prepared_ok.val {
              Some(ok) => ok
              None => {
                let ok = try { prepared_origin_index(db) } catch { e => if missing_origin_index(e) { false } else { raise e } }
                prepared_ok.val = Some(ok)
                ok
              }
            }
            let f = naming_origin(db, s, ok)
            checked[s] = f
            f
          }
        }
        if found {
          push_new(origins, origins_seen, s)
          break
        }
      }
    }
  }
  for k in keys {
    if target.get(k) is Some(Some(session)) {
      let title = match field(session, "title") { String(t) => @jscase.trim_white(t); _ => "" }
      if title == "" && !has_chat.contains(k) {
        push_new(origins, origins_seen, k)
      }
    }
  }
  let external = unique_ids([latest_naming_origins(db, origins)])
  for id in external {
    let members = db.all("SELECT * FROM thread_sessions WHERE thread = ? ORDER BY joined_at, rowid", [id])
    members_of[js_text(id)] = members
    for m in members {
      push_new(agents, agents_seen, js_text(field(m, "session")))
    }
  }
  { rows, agents, threads: chats + external, members: members_of }
}

///|
/// views.ts `chats(station, viewer, archived, scope, titlesOnly)` as `openJobs` reads it: each item's id, session,
/// title and agents' keys, of the viewer's workspace.
fn job_name_items(db : @sql.Db, viewer : Json, words : Json, archived : Bool, scope : JobScope) -> Array[(Json, String, String, Array[String])] raise {
  let word = (k : String) => match words.value(k) { Some(String(s)) => s; _ => "" }
  let sessions : Array[Map[String, Json]] = []
  for k in scope.agents {
    if one(db, "SELECT * FROM sessions WHERE key = ?", [Json::string(k)]) is Some(s) {
      sessions.push(s)
    }
  }
  let sorted = stable_sort(sessions, (a, b) => {
    let d = num(field(b, "last_active_at")) - num(field(a, "last_active_at"))
    if d < 0.0 { -1 } else if d > 0.0 { 1 } else { 0 }
  })
  let in_rows : Set[String] = Set::new()
  for k in scope.rows {
    in_rows.add(k)
  }
  let shown : Map[String, Map[String, Json]] = Map([])
  let all : Map[String, Map[String, Json]] = Map([])
  let order : Array[String] = []
  for x in sorted {
    let key = js_text(field(x, "key"))
    all[key] = x
    if !(field(x, "archived_at") is Null) == archived {
      shown[key] = x
      if in_rows.contains(key) {
        order.push(key)
      }
    }
  }
  let listed = (t : Map[String, Json]) => !(field(t, "hidden_at") is Null) == archived
  // store.ts `threadsForChatNames`, of the scope's threads with the members it found
  let selected : Array[(Map[String, Json], Array[Map[String, Json]], Double)] = []
  if scope.threads.length() > 0 {
    let marks = scope.threads.map(_ => "?")
    for t in db.all("SELECT * FROM threads WHERE id IN (\{marks.join(", ")})", scope.threads) {
      let id = field(t, "id")
      let members = match scope.members.get(js_text(id)) {
        Some(m) => m
        None => db.all("SELECT * FROM thread_sessions WHERE thread = ? ORDER BY joined_at, rowid", [id])
      }
      let at = match one(db, "SELECT e.at FROM thread_state t JOIN entries e ON e.thread = t.thread AND e.n = t.said_n AND e.kind = 'message' WHERE t.thread = ?", [id]) {
        Some(r) if field(r, "at") is Number(n, ..) => n
        _ => 0.0
      }
      selected.push((t, members, at))
    }
  }
  let ordered = stable_sort(selected, (a, b) => {
    for pair in [(a.2, b.2), (num(field(a.0, "created_at")), num(field(b.0, "created_at"))), (num(field(a.0, "id")), num(field(b.0, "id")))] {
      if pair.0 != pair.1 {
        return if pair.1 > pair.0 { 1 } else { -1 }
      }
    }
    0
  })
  let threads = ordered.filter(t => t.1.iter().any(m => all.contains(js_text(field(m, "session")))))
  let first_texts : Map[String, Json] = Map([])
  let name_text = (t : Map[String, Json]) => {
    let surface = field(t, "surface")
    if given_title(t) || surface is String("chat" | "ember" | "stillfail") {
      return Json::null()
    }
    let k = js_text(field(t, "id"))
    match first_texts.get(k) {
      Some(f) => f
      None => {
        let f = first_text(db, field(t, "id"))
        first_texts[k] = f
        f
      }
    }
  }
  let origins : Map[String, (Map[String, Json], Array[Map[String, Json]])] = Map([])
  let chatted : Set[String] = Set::new()
  for t in threads {
    let own = field(t.0, "surface") == Json::string("ember")
    for m in t.1 {
      let s = js_text(field(m, "session"))
      if own {
        if listed(t.0) {
          chatted.add(s)
        }
      } else if !origins.contains(s) {
        origins[s] = (t.0, t.1)
      }
    }
  }
  let in_chat = (t : Map[String, Json], members : Array[Map[String, Json]]) => {
    let alone = archived && field(t, "home") is Null
    members.filter(m => (if alone { all } else { shown }).contains(js_text(field(m, "session")))).map(m => js_text(field(m, "session")))
  }
  let known_channel = (thread : Map[String, Json], members : Array[Map[String, Json]]) => (thread, members)
  ignore(known_channel)
  let out : Array[(Json, String, String, Array[String])] = []
  let push = (key : String, title : String, agents : Array[String]) => {
    if in_rows.contains(key) && sees(viewer, match all.get(key) { Some(x) => field(x, "ws"); None => Json::null() }) {
      out.push((Json::string(key), key, title, agents))
    }
  }
  for t in threads {
    if field(t.0, "surface") != Json::string("ember") || !listed(t.0) {
      continue
    }
    let agents = in_chat(t.0, t.1)
    if agents.length() == 0 {
      continue
    }
    let from = t.1.iter().filter_map(m => origins.get(js_text(field(m, "session")))).head()
    let title = match from {
      Some(f) if !given_title(t.0) =>
        chat_title(thread_json(f.0), name_text(f.0), channel_of(db, f.0, f.1), word("untitled"), word("directMessage"))
      _ => chat_title(thread_json(t.0), name_text(t.0), Json::null(), word("untitled"), word("directMessage"))
    }
    push(agents[0], title, agents)
  }
  for key in order {
    if chatted.contains(key) {
      continue
    }
    let x = shown.get(key).unwrap()
    let own = match field(x, "title") { String(s) => @jscase.trim_white(s); _ => "" }
    let title = if own != "" {
      own
    } else {
      match origins.get(key) {
        Some(f) => chat_title(thread_json(f.0), name_text(f.0), channel_of(db, f.0, f.1), word("untitled"), word("directMessage"))
        None => word("untitled")
      }
    }
    push(key, title, [key])
  }
  out
}

///|
/// The channel's name of a Slack thread, as `origin` gives it, for its title.
fn channel_of(db : @sql.Db, thread : Map[String, Json], members : Array[Map[String, Json]]) -> Json {
  ignore(db)
  match current_known.val {
    Some(k) => k.channel(slack_connect_of(members), field(thread, "channel")) catch { _ => Json::null() }
    None => Json::null()
  }
}

///|
/// The read's own (Known) for what names a chat, while `openJobs` runs.
let current_known : Ref[Known?] = Ref(None)

///|
/// jobs.ts `openJobs`.
pub fn open_jobs(db : @sql.Db, host : @host.Host, data : String, sep : String, ask : Json) -> Json raise {
  let args = ask.value("args").unwrap_or(Json::null())
  let viewer = args.value("viewer").unwrap_or(Json::null())
  let up = up_jobs(db, viewer)
  let seen = seen_by(db, viewer, up.map(j => js_text(field(j, "session_key"))))
  let open = up.filter(j => seen(js_text(field(j, "session_key"))))
  if open.length() == 0 {
    return Json::array([])
  }
  if args.value("chats") == Some(Json::boolean(false)) {
    return Json::array(open.map(j => shown(db, host, j))) catch { e => raise e }
  }
  // (set anew by every read that names chats)
  current_known.val = Some(Known::of(host, data, sep, ask))
  let words = args.value("words").unwrap_or(Json::null())
  let keys = unique_keys([open.map(j => js_text(field(j, "session_key")))])
  let wanted : Set[String] = Set::new()
  for k in keys {
    wanted.add(k)
  }
  let scope = scope_of_job_names(db, keys)
  let scan = (archived : Bool) => {
    let own : Map[String, Json] = Map([])
    let any : Map[String, Json] = Map([])
    for item in job_name_items(db, viewer, words, archived, scope) {
      let (id, session, title, agents) = item
      let shown_chat : Json = { "id": id, "title": Json::string(title), "archived": Json::boolean(archived) }
      for key in agents {
        if !wanted.contains(key) {
          continue
        }
        any[key] = shown_chat
        if session == key {
          own[key] = shown_chat
        }
      }
    }
    (own, any)
  }
  let listed = scan(false)
  let archived = if keys.iter().any(k => !listed.0.contains(k)) { Some(scan(true)) } else { None }
  let out : Array[Json] = []
  for j in open {
    guard shown(db, host, j) is Object(o) else { continue }
    let v = Map::from_array(o.to_array())
    let k = js_text(field(j, "session_key"))
    let chat = match listed.0.get(k) {
      Some(c) => Some(c)
      None =>
        match archived.bind(a => a.0.get(k)) {
          Some(c) => Some(c)
          None =>
            match listed.1.get(k) {
              Some(c) => Some(c)
              None => archived.bind(a => a.1.get(k))
            }
        }
    }
    if chat is Some(c) {
      v["chat"] = c
    }
    out.push(Json::object(v))
  }
  Json::array(out)
}
