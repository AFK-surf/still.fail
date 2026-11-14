// A session as lists and events show it (station/src/read/sessions.ts `summary`, `sessions`: GET /sessions, and each
// session's summary told as it changes): its row without the token, the hub's process state, its counts and latest
// turn, who started it and who wrote with it, its bindings, watches, transcript's length and what its calls used.
// Refused, as the TypeScript is, while an old store's turn counts, bindings or session list are prepared.

///|
let turn_count_pending : String = "turn count pending: "

///|
/// rows.ts `parseProfiles`: the profiles it may run on, its pinned one alone, or none.
fn profiles_of(r : Map[String, Json]) -> Json {
  if field(r, "profiles") is String(raw) && raw != "" {
    match (try { Some(@jsjson.parse(raw)) } catch { _ => None }) {
      Some(Arr(xs)) => {
        let list = xs.filter_map(x => match x {
          Str(s) if @jsjson.text(s) != "" => Some(Json::string(@jsjson.text(s)))
          _ => None
        })
        if list.length() > 0 {
          return Json::array(list)
        }
      }
      _ => ()
    }
  }
  if field(r, "profile_pinned") == Json::number(1.0) {
    Json::array([field(r, "profile")])
  } else {
    Json::null()
  }
}

///|
/// sessions.ts `sessionJson` of rows.ts `toSession`: the token skipped, `cwd`, `profiles`, `context`, `contextBefore`
/// left out when none.
fn summary_session_json(r : Map[String, Json]) -> Map[String, Json] {
  let flag = (k : String) => match field(r, k) {
    Null => Json::null()
    Number(0.0, ..) => Json::boolean(false)
    _ => Json::boolean(true)
  }
  let v : Map[String, Json] = {
    "key": field(r, "key"),
    "connect": field(r, "connect"),
    "scope": if field(r, "scope") == Json::string("all") { "all" } else { "thread" },
    "title": field(r, "title"),
    "createdBy": field(r, "created_by"),
    "runtime": field(r, "runtime"),
    "profile": field(r, "profile"),
    "profilePinned": Json::boolean(field(r, "profile_pinned") == Json::number(1.0)),
    "model": field(r, "model"),
    "effort": field(r, "effort"),
    "fast": flag("fast"),
    "afresh": flag("afresh"),
    "runtimeSessionId": field(r, "runtime_session_id"),
    "workspace": field(r, "workspace"),
  }
  if !(field(r, "cwd") is Null) {
    v["cwd"] = field(r, "cwd")
  }
  if profiles_of(r) is (Array(_) as p) {
    v["profiles"] = p
  }
  if field(r, "context") is (Number(_, ..) as c) {
    v["context"] = c
  }
  if field(r, "context_before") is (Number(_, ..) as c) {
    v["contextBefore"] = c
  }
  v["running"] = Json::boolean(field(r, "running") == Json::number(1.0))
  v["createdAt"] = field(r, "created_at")
  v["lastActiveAt"] = field(r, "last_active_at")
  v["archivedAt"] = field(r, "archived_at")
  v["archivedBy"] = field(r, "archived_by")
  v["shownAt"] = field(r, "shown_at")
  v
}

///|
/// What `summary` and `sessions` read for some sessions at once (sessions.ts `Lists`).
priv struct Lists {
  stats : Map[String, Map[String, Json]]
  bindings : Map[String, Array[Json]]
  participants : Map[String, Array[Json]]
  watches : Map[String, Json]
  lengths : Map[String, Json]
  usages : Map[String, Json]
}

///|
/// store.ts `sessionStats` of some sessions: refused naming those whose turns are not counted yet.
fn session_stats(db : @sql.Db, keys : Array[String]) -> Map[String, Map[String, Json]] raise {
  let out : Map[String, Map[String, Json]] = Map([])
  if keys.length() == 0 {
    return out
  }
  let rows = db.all("\{session_stats_sql} WHERE s.key IN (SELECT value FROM json_each(?))", [ids_json(keys.map(Json::string))])
  let unknown = rows.filter(r => field(r, "turns") is Null).map(r => field(r, "key"))
  if unknown.length() > 0 {
    raise Refused(503, turn_count_pending + Json::array(unknown).stringify())
  }
  for r in rows {
    out[js_text(field(r, "key"))] = r
  }
  out
}

///|
/// store.ts `listBindings` of some sessions: the connects each is bound to.
fn list_bindings(db : @sql.Db, keys : Array[String]) -> Map[String, Array[Json]] raise {
  let out : Map[String, Array[Json]] = Map([])
  if keys.length() == 0 {
    return out
  }
  if !session_bindings_ready(db) {
    fail("session binding index is still being prepared")
  }
  for r in db.all(session_bindings_selected_sql, [ids_json(unique_keys([keys]).map(Json::string))]) {
    let k = js_text(field(r, "session"))
    match out.get(k) {
      Some(a) => a.push(field(r, "connect"))
      None => out[k] = [field(r, "connect")]
    }
  }
  out
}

///|
/// store.ts `participants` of some sessions: each person once a session, at the first time they wrote in any of its
/// threads, in their references' byte order and then (stably) by when.
fn participants_of(db : @sql.Db, keys : Array[String]) -> Map[String, Array[Json]] raise {
  let out : Map[String, Array[Json]] = Map([])
  if keys.length() == 0 {
    return out
  }
  let firsts : Map[String, Map[String, Double]] = Map([])
  let order : Array[String] = []
  for r in db.all("SELECT ts.session, ts.connect, t.id, t.surface FROM thread_sessions ts JOIN threads t ON t.id = ts.thread WHERE ts.session IN (SELECT value FROM json_each(?))", [ids_json(keys.map(Json::string))]) {
    let key = js_text(field(r, "session"))
    let refs = match firsts.get(key) {
      Some(m) => m
      None => {
        let m : Map[String, Double] = Map([])
        firsts[key] = m
        order.push(key)
        m
      }
    }
    for a in db.all(people_at_sql, [field(r, "id")]) {
      let author = js_text(field(a, "author"))
      let reference = if field(r, "surface") == Json::string("ember") { author } else { "slack:\{js_text(field(r, "connect"))}:\{author}" }
      let at = num(field(a, "at"))
      match refs.get(reference) {
        Some(first) if at >= first => ()
        _ => refs[reference] = at
      }
    }
  }
  for key in order {
    let refs = firsts.get(key).unwrap()
    if refs.length() == 0 {
      continue
    }
    let by_ref = refs.to_array()
    by_ref.sort_by((a, b) => by_bytes(a.0, b.0))
    let sorted = stable_sort(by_ref, (a, b) => if a.1 < b.1 { -1 } else if a.1 > b.1 { 1 } else { 0 })
    out[key] = sorted.map(p => Json::string(p.0))
  }
  out
}

///|
/// store.ts `transcriptLengths` and `sessionUsages` of some sessions; none where the store keeps none.
fn lengths_and_usages(db : @sql.Db, keys : Array[String]) -> (Map[String, Json], Map[String, Json]) {
  let lengths : Map[String, Json] = Map([])
  let usages : Map[String, Json] = Map([])
  if keys.length() == 0 {
    return (lengths, usages)
  }
  let list = [ids_json(keys.map(Json::string))]
  let rows = try { db.all("SELECT session, n FROM transcript_lengths WHERE session IN (SELECT value FROM json_each(?))", list) } catch { _ => [] }
  for r in rows {
    lengths[js_text(field(r, "session"))] = field(r, "n")
  }
  let read = () => {
    let incremental = one(db, "SELECT 1 AS x FROM sqlite_master WHERE type = 'table' AND name = 'usage_totals_incremental'", []) is Some(_)
    let source = if incremental { "session_usage u JOIN usage_totals_source_sessions c ON c.session = u.session AND c.done = 1" } else { "session_usage u" }
    let found : Array[(String, Json)] = []
    for r in db.all("SELECT u.session, u.usage FROM \{source} WHERE u.session IN (SELECT value FROM json_each(?))", list) {
      guard field(r, "usage") is String(u) else { fail("usage") }
      found.push((js_text(field(r, "session")), to_json(@jsjson.parse(u))))
    }
    found
  }
  // (one usage that does not read is none of them, as JSON.parse throwing in the map makes it)
  let found = try { read() } catch { _ => [] }
  for f in found {
    usages[f.0] = f.1
  }
  (lengths, usages)
}

///|
fn lists_of(db : @sql.Db, keys : Array[String]) -> Lists raise {
  let bindings = list_bindings(db, keys)
  let stats = session_stats(db, keys)
  let participants = participants_of(db, keys)
  let watches = watching(db, Some(keys))
  let (lengths, usages) = lengths_and_usages(db, keys)
  { stats, bindings, participants, watches, lengths, usages }
}

///|
/// sessions.ts `summaryWith`.
fn summary_with(db : @sql.Db, known : Known, key : String, l : Lists) -> Json raise {
  guard one(db, "SELECT * FROM sessions WHERE key = ?", [Json::string(key)]) is Some(row) else {
    raise Refused(404, "unknown session \{key}")
  }
  let v = summary_session_json(row)
  v["boundTo"] = Json::array(l.bindings.get(key).unwrap_or([]))
  v["process"] = Json::string(known.processes.get(key).unwrap_or("cold"))
  let stat = l.stats.get(key)
  let s = (k : String, none : Json) => match stat { Some(r) => field(r, k); None => none }
  v["turns"] = s("turns", Json::number(0.0))
  v["workMs"] = s("work_ms", Json::null())
  v["pending"] = s("pending", Json::number(0.0))
  v["firstText"] = s("first_text", Json::null())
  v["lastTurn"] = match stat { Some(r) => latest_turn(r); None => Json::null() }
  v["creator"] = known.creator(field(row, "created_by"))
  v["participants"] = Json::array(known.people(Json::array(l.participants.get(key).unwrap_or([]))))
  v["contextActions"] = if field(row, "runtime") == Json::string("claude") || field(row, "runtime") == Json::string("codex") {
    ["compact", "clear"]
  } else {
    ["clear"]
  }
  if l.watches.get(key) is Some(w) {
    v["watch"] = w
  }
  if l.lengths.get(key) is Some(n) {
    v["transcriptLength"] = n
  }
  if l.usages.get(key) is Some(u) {
    v["usage"] = u
  }
  Json::object(v)
}

///|
/// sessions.ts `summary`: one session's.
pub fn session_summary(db : @sql.Db, host : @host.Host, data : String, sep : String, ask : Json) -> Json raise {
  let args = ask.value("args").unwrap_or(Json::null())
  let key = js_text(args.value("key").unwrap_or(Json::null()))
  summary_with(db, Known::of(host, data, sep, ask), key, lists_of(db, [key]))
}

///|
/// session-list-index.ts `sessionListReady`.
fn session_list_ready(db : @sql.Db) -> Bool raise {
  guard one(db, "SELECT version, complete FROM session_list_meta WHERE id = 1", []) is Some(m) else {
    fail("session list index version marker is missing")
  }
  if !(field(m, "version") is Number(1.0, ..)) {
    fail("session list index version \{js_text(field(m, "version"))} is incompatible with 1")
  }
  field(m, "complete") is Number(1.0, ..)
}

///|
/// sessions.ts `sessions` (GET /sessions): the sessions shown in lists, or the archived ones; of one connect; of the
/// viewer's workspace (every one for a read made for no one).
pub fn session_list(db : @sql.Db, host : @host.Host, data : String, sep : String, ask : Json) -> Json raise {
  let args = ask.value("args").unwrap_or(Json::null())
  let known = Known::of(host, data, sep, ask)
  let connect = match args.value("connect") { Some(String(c)) => Some(c); _ => None }
  let archived = match args.value("archived") {
    Some(True) => true
    Some(Number(n, ..)) => n != 0.0 && !n.is_nan()
    Some(String(s)) => s != ""
    Some(Array(_)) | Some(Object(_)) => true
    _ => false
  }
  let viewer = match args.value("viewer") { Some(Object(_) as v) => Some(v); _ => None }
  let rows = match (viewer, connect) {
    (None, None) => {
      let (index, where_) = if archived { ("sessions_put_away", "archived_at IS NOT NULL") } else { ("sessions_live", "archived_at IS NULL") }
      db.all("SELECT * FROM sessions INDEXED BY \{index} WHERE \{where_} ORDER BY last_active_at DESC, rowid ASC", [])
    }
    _ => {
      if !session_list_ready(db) {
        fail("session list index is still being prepared")
      }
      match viewer {
        None => db.all(session_list_connect_sql, [Json::number(if archived { 1.0 } else { 0.0 }), Json::string(connect.unwrap())])
        Some(v) => {
          let params = [
            v.value("workspace").unwrap_or(Json::null()),
            Json::number(if v.value("home") == Some(Json::boolean(false)) { 0.0 } else { 1.0 }),
            Json::number(if archived { 1.0 } else { 0.0 }),
          ]
          match connect {
            None => db.all(session_list_scope_sql, params)
            Some(c) => db.all(session_list_scope_connect_sql, params + [Json::string(c)])
          }
        }
      }
    }
  }
  let keys = rows.map(r => js_text(field(r, "key")))
  let l = lists_of(db, keys)
  Json::array(keys.map(k => summary_with(db, known, k, l))) catch { e => raise e }
}
