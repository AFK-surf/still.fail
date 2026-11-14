// The chat list as the station makes it once for everyone who sees it (station/src/read/views.ts `sharedChats`, of the
// list shown, not the archive's): `sharedOf`, told to every event stream that makes its sidebar of it, and `sharedChats`
// (GET /chats?shared=1), what a viewer's workspace sees of it. Whole, or the rows a change of some sessions and threads
// can touch (`scopeOf`) and the ids of those. Each row as the TypeScript makes it, field for field.

///|
/// views.ts LAST_CHARS and ANSWERED_WITHIN.
let last_chars : Int = 200

///|
let answered_within : Double = 129600000.0

///|
/// views.ts `Scope`: the ids of the rows a change can touch, the sessions and threads they are made of.
priv struct Scope {
  rows : Array[String]
  sessions : Array[String]
  threads : Array[Json]
}

///|
fn push_new(out : Array[String], seen : Set[String], s : String) -> Unit {
  if !seen.contains(s) {
    seen.add(s)
    out.push(s)
  }
}

///|
/// store.ts `threadsOfSessions`: the threads sessions take part in, each once.
fn threads_of_sessions(db : @sql.Db, keys : Array[String]) -> Array[Json] raise {
  if keys.length() == 0 {
    return []
  }
  let marks = keys.map(_ => "?")
  db
  .all("SELECT DISTINCT thread FROM thread_sessions WHERE session IN (\{marks.join(", ")})", keys.map(Json::string))
  .map(r => field(r, "thread"))
}

///|
fn members_of(db : @sql.Db, ids : Array[Json]) -> Array[String] raise {
  let out : Array[String] = []
  let seen : Set[String] = Set::new()
  for id in ids {
    for m in db.all("SELECT * FROM thread_sessions WHERE thread = ? ORDER BY joined_at, rowid", [id]) {
      push_new(out, seen, js_text(field(m, "session")))
    }
  }
  out
}

///|
fn unique_ids(lists : Array[Array[Json]]) -> Array[Json] {
  let out : Array[Json] = []
  let seen : Set[String] = Set::new()
  for l in lists {
    for id in l {
      if !seen.contains(id.stringify()) {
        seen.add(id.stringify())
        out.push(id)
      }
    }
  }
  out
}

///|
fn unique_keys(lists : Array[Array[String]]) -> Array[String] {
  let out : Array[String] = []
  let seen : Set[String] = Set::new()
  for l in lists {
    for k in l {
      push_new(out, seen, k)
    }
  }
  out
}

///|
/// views.ts `scopeOf`.
fn scope_of(db : @sql.Db, sessions : Array[String], threads : Array[Json]) -> Scope raise {
  let touched = unique_ids([threads, threads_of_sessions(db, sessions)])
  let rows = unique_keys([sessions, members_of(db, touched)])
  let theirs = threads_of_sessions(db, rows)
  let agents = unique_keys([rows, members_of(db, theirs)])
  { rows, sessions: agents, threads: unique_ids([touched, theirs, threads_of_sessions(db, agents)]) }
}

///|
/// A thread for the list (store.ts `listThreads` with no viewer, what `sharedChats` reads of it): the thread, its
/// sessions, its latest message, who wrote in it and the first thing said.
priv struct Listed {
  thread : Map[String, Json]
  sessions : Array[Map[String, Json]]
  last_message : Json
  people : Json
  first_text : Json
  last_at : Double
}

///|
fn listed_threads(db : @sql.Db, ids : Array[Json]) -> Array[Listed] raise {
  if ids.length() == 0 {
    return []
  }
  let marks = ids.mapi((i, _) => "?\{i + 2}")
  let rows = db.all(
    "SELECT t.*, COALESCE(r.n, 0) AS read_n FROM threads t LEFT JOIN reads r ON r.thread = t.id AND r.viewer = ?1 WHERE t.id IN (\{marks.join(", ")})",
    [Json::string("")] + ids,
  )
  let out : Array[Listed] = []
  for r in rows {
    let id = field(r, "id")
    let sessions = db.all("SELECT * FROM thread_sessions WHERE thread = ? ORDER BY joined_at, rowid", [id])
    let last_message = last_said(db, id)
    let people = thread_people(db, id, field(r, "surface"))
    let first_text = first_text(db, id)
    let last_at = match last_message.value("createdAt") {
      Some(Number(n, ..)) => n
      _ => 0.0
    }
    out.push({ thread: r, sessions, last_message, people, first_text, last_at })
  }
  stable_sort(out, (a, b) => {
    for pair in [(a.last_at, b.last_at), (num(field(a.thread, "created_at")), num(field(b.thread, "created_at"))), (num(field(a.thread, "id")), num(field(b.thread, "id")))] {
      if pair.0 != pair.1 {
        return if pair.1 > pair.0 { 1 } else { -1 }
      }
    }
    0
  })
}

///|
/// The name a chat was given (titles.ts `givenTitle`), whether it has one.
fn given_title(thread : Map[String, Json]) -> Bool {
  let text = (k : String) => match field(thread, k) {
    String(s) => @jscase.trim_white(s)
    _ => ""
  }
  text("title") != "" || text("autoTitle") != "" || text("auto_title") != ""
}

///|
/// rows.ts `takeChars`: the first `n` characters (code points).
fn take_chars(s : String, n : Int) -> String {
  let buf = StringBuilder::new()
  let mut count = 0
  for c in s {
    if count >= n {
      break
    }
    count += 1
    buf.write_char(c)
  }
  buf.to_string()
}

///|
/// views.ts `answeredView`, with who answered.
fn answered_view(known : Known, a : Answer) -> Json raise {
  let q = (k : String) => a.question.value(k).unwrap_or(Json::null())
  let v : Map[String, Json] = { "seq": q("n"), "text": q("text"), "askedAt": q("createdAt"), "answeredAt": a.at, "card": a.card }
  if a.answer is Null {
    v["closed"] = true
  } else {
    v["reply"] = a.answer.value("text").unwrap_or(Json::null())
    let quoted = match a.answer.value("quotes") {
      Some(Array(qs)) => qs.iter().any(x => x.value("ts") == Some(q("ts")))
      _ => false
    }
    v["quoted"] = Json::boolean(quoted)
  }
  v["by"] = known.creator(a.by)
  Json::object(v)
}

///|
/// views.ts `cardView` of a chat's card as `pendingCard` finds it, as the shared row has it (no one's let go).
fn card_view(db : @sql.Db, thread : Json, names : Names) -> Json raise {
  guard review_pending_card(db, { "thread": thread }) is Array([m, card]) else { return Json::null() }
  let message = match message_view(db, m, names) {
    Object(o) => Map::from_array(o.to_array())
    _ => Map([])
  }
  if card.value("type") == Some(Json::string("options")) {
    message["options"] = card.value("options").unwrap_or(Json::null())
  }
  message["card"] = card
  let seq = m.value("n").unwrap_or(Json::null())
  let before : Array[Json] = []
  if messages_before(db, thread, seq, Some(Json::number(2.0))) is Array(xs) {
    for b in xs {
      before.push(message_view(db, b, names))
    }
  }
  { "seq": seq, "card": card, "message": Json::object(message), "before": Json::array(before) }
}

///|
/// views.ts `needView`: what one of a chat's agents needs a person for without a card.
fn need_view(db : @sql.Db, thread : Json, agents : Array[Json], names : Names) -> Json raise {
  let turn = agents.iter().map(a => a.value("lastTurn").unwrap_or(Json::null())).find_first(t => match t.value("ending") {
    Some(String(e)) => e == "need_help" || e == "need_decision"
    _ => t.value("declared") == Some(Json::string("block"))
  })
  guard turn is Some(turn) else { return Json::null() }
  let about = turn.value("about").unwrap_or(Json::null())
  let seq = match about {
    Object(_) if about.value("thread") == Some(thread) && is_integer(about.value("seq").unwrap_or(Json::null())) =>
      about.value("seq").unwrap()
    _ => Json::null()
  }
  let started = turn.value("startedAt").unwrap_or(Json::null())
  let ended = turn.value("endedAt").unwrap_or(Json::null())
  let from = if is_integer(started) { started } else { Json::number(0.0) }
  let to = if is_integer(ended) { ended } else { as_integer(Json::string(i64_max)) }
  guard asking_message(db, thread, seq, from, to) is Some((m, earlier)) else { return Json::null() }
  let before = earlier.map(b => message_view(db, b, names)) catch { e => raise e }
  { "seq": m.value("n").unwrap_or(Json::null()), "message": message_view(db, m, names), "before": Json::array(before) }
}

///|
/// views.ts `sharedChats(station, false, scope)`: the rows shown (of `scope`, its rows alone).
fn shared_rows(db : @sql.Db, known : Known, scope : Scope?) -> Array[Json] raise {
  let (_, reviews) = known.config()
  // The sessions the rows are made of: those shown, else those of the scope, the latest active first.
  let sessions = match scope {
    None => db.all(shown_sessions_sql, [])
    Some(sc) => {
      let found : Array[Map[String, Json]] = []
      for k in sc.sessions {
        if one(db, "SELECT * FROM sessions WHERE key = ?", [Json::string(k)]) is Some(s) {
          found.push(s)
        }
      }
      stable_sort(found, (a, b) => {
        let d = num(field(b, "last_active_at")) - num(field(a, "last_active_at"))
        if d < 0.0 { -1 } else if d > 0.0 { 1 } else { 0 }
      })
    }
  }
  let shown : Map[String, Map[String, Json]] = Map([])
  let all : Map[String, Map[String, Json]] = Map([])
  let order : Array[String] = []
  let in_rows : Set[String] = Set::new()
  if scope is Some(sc) {
    for k in sc.rows {
      in_rows.add(k)
    }
  }
  for x in sessions {
    let key = js_text(field(x, "key"))
    all[key] = x
    if field(x, "archived_at") is Null {
      shown[key] = x
      if scope is None || in_rows.contains(key) {
        order.push(key)
      }
    }
  }
  let in_chat = (t : Listed) => t.sessions.filter(m => shown.contains(js_text(field(m, "session")))).map(m => js_text(field(m, "session")))
  let watches = watching(db, scope.map(sc => sc.sessions))
  let of = match scope {
    Some(sc) => sc.threads
    None =>
      db
      .all("SELECT DISTINCT thread FROM thread_sessions WHERE session IN (SELECT session FROM thread_sessions WHERE thread IN (\n       SELECT ts.thread FROM thread_sessions ts JOIN sessions x ON x.key = ts.session WHERE x.archived_at IS NULL))", [])
      .map(r => field(r, "thread"))
  }
  let threads = listed_threads(db, of).filter(t => t.sessions.iter().any(m => all.contains(js_text(field(m, "session")))))
  let stat_keys = unique_keys([
    match scope { Some(sc) => sc.sessions; None => shown.keys().collect() },
    threads.map(t => t.sessions.map(m => js_text(field(m, "session")))).fold(init=[], (a, b) => a + b),
  ])
  let stats = session_activity(db, stat_keys)
  let agent = (key : String) => {
    let x = all.get(key).unwrap()
    let v : Map[String, Json] = {
      "key": Json::string(key),
      "runtime": field(x, "runtime"),
      "model": field(x, "model"),
      "effort": field(x, "effort"),
      "process": Json::string(known.processes.get(key).unwrap_or("cold")),
      "pending": match stats.get(key) { Some((p, _)) => p; None => Json::number(0.0) },
      "lastTurn": match stats.get(key) { Some((_, t)) => t; None => Json::null() },
    }
    if watches.get(key) is Some(w) {
      v["watch"] = w
    }
    Json::object(v)
  }
  // Per agent: the Slack thread it came from (the latest one it is in), whether it has a chat of its own, and who wrote
  // in its Slack threads.
  let origins : Map[String, Listed] = Map([])
  let chatted : Set[String] = Set::new()
  let spoke : Map[String, Array[Json]] = Map([])
  for t in threads {
    let own = field(t.thread, "surface") == Json::string("ember")
    let writers = if own { [] } else { known.people(t.people) }
    for m in t.sessions {
      let s = js_text(field(m, "session"))
      if own {
        if field(t.thread, "hidden_at") is Null {
          chatted.add(s)
        }
      } else {
        if !origins.contains(s) {
          origins[s] = t
        }
        if writers.length() > 0 {
          spoke[s] = spoke.get(s).unwrap_or([]) + writers
        }
      }
    }
  }
  let item_threads = threads.filter(t => field(t.thread, "surface") == Json::string("ember") && field(t.thread, "hidden_at") is Null && in_chat(t).length() > 0)
  let carded = threads_with_cards(db, item_threads.map(t => field(t.thread, "id")))
  let carded_set : Set[String] = Set::new()
  for c in carded {
    carded_set.add(c.stringify())
  }
  require_card_posts(db, carded)
  let legacy = has_legacy_said(db)
  let said_by : Map[String, Json] = Map([])
  let need_said : Array[Json] = []
  for t in item_threads {
    let id = field(t.thread, "id")
    let said = try { Some(said_of(db, legacy, id)) } catch {
      Refused(503, m) if m.has_prefix(said_pending) => {
        let more : Json = @json.parse(m.view(start_offset=said_pending.length()).to_owned()) catch { _ => Json::array([]) }
        if more is Array(xs) {
          need_said.append(xs)
        }
        None
      }
      e => raise e
    }
    if said is Some(s) {
      said_by[id.stringify()] = s
    }
  }
  if need_said.length() > 0 {
    raise Refused(503, said_pending + Json::array(unique_ids([need_said])).stringify())
  }
  let answered : Map[String, Array[Json]] = Map([])
  for a in answers_since(db, Json::number(known.now - answered_within), carded) {
    let k = a.question.value("thread").unwrap_or(Json::null()).stringify()
    let v = answered_view(known, a)
    match answered.get(k) {
      Some(l) => l.push(v)
      None => answered[k] = [v]
    }
  }
  let rows : Array[Json] = []
  let ids : Array[String] = []
  for t in item_threads {
    let id = field(t.thread, "id")
    let from = t.sessions.iter().filter_map(m => origins.get(js_text(field(m, "session")))).head()
    let agents = in_chat(t).map(agent)
    let origin = match from { Some(f) => known.origin(f.thread, f.sessions); None => Json::null() }
    let creator = known.creator(field(t.thread, "created_by"))
    let people = known.people(t.people)
    let names = known.author_names(db, id)
    let last_view = if t.last_message is Null { Json::null() } else { message_view(db, t.last_message, names) }
    let starters = agents.map(a => known.creator(match all.get(js_text(a.value("key").unwrap())) { Some(x) => field(x, "created_by"); None => Json::null() })) catch {
      e => raise e
    }
    let key = js_text(agents[0].value("key").unwrap())
    let named : Json = match from {
      Some(f) if !(origin is Null) && !given_title(t.thread) =>
        { "thread": thread_json(f.thread), "firstText": f.first_text, "channelName": origin.value("channelName").unwrap_or(Json::null()) }
      _ => { "thread": thread_json(t.thread), "firstText": t.first_text, "channelName": Json::null() }
    }
    let last = match last_view {
      Object(_) => {
        let g = (k : String) => last_view.value(k).unwrap_or(Json::null())
        let text0 = match g("text") { String(s) => @jscase.trim_white(s); _ => "" }
        let quoted_only = text0 == "" && (g("quotes") is Array(qs) && qs.length() > 0)
        let l : Map[String, Json] = {
          "seq": g("seq"),
          "authorKind": g("authorKind"),
          "author": g("author"),
          "authorName": g("authorName"),
          "text": if g("text") is String(_) { Json::string(take_chars(text0, last_chars)) } else { Json::null() },
          "createdAt": g("createdAt"),
        }
        if quoted_only {
          l["quotedOnly"] = true
        }
        if last_view.value("authorPicture") is Some(p) {
          l["authorPicture"] = p
        }
        if !(g("agentIdentity") is Null) {
          l["agentIdentity"] = g("agentIdentity")
        }
        if last_view.value("authorModel") is Some(p) {
          l["authorModel"] = p
        }
        if last_view.value("authorRuntime") is Some(p) {
          l["authorRuntime"] = p
        }
        Json::object(l)
      }
      _ => Json::null()
    }
    let created_at = num(field(t.thread, "created_at"))
    let row : Map[String, Json] = {
      "id": Json::string(key),
      "session": Json::string(key),
      "thread": id,
      "title": "",
      "agents": Json::array(agents),
      "last": last,
      "unread": false,
      "mine": false,
      "lastActiveAt": Json::number(if created_at > t.last_at { created_at } else { t.last_at }),
      "connect": match from { Some(f) => match slack_connect_of(f.sessions) { Some(c) => Json::string(c); None => Json::null() }; None => Json::null() },
      "origin": origin,
      "creator": creator,
      "people": Json::array(people),
    }
    row["ws"] = match all.get(key) { Some(x) => field(x, "ws"); None => Json::null() }
    row["named"] = named
    let mine_of : Array[Json] = [creator] + people + starters
    for a in agents {
      mine_of.append(spoke.get(js_text(a.value("key").unwrap())).unwrap_or([]))
    }
    row["mineOf"] = Json::array(mine_of.filter(p => !(p is Null)))
    row["said"] = said_by.get(id.stringify()).unwrap_or(Json::null())
    row["archiveReminderDismissed"] = false
    row["archiveRecommended"] = Json::boolean(archive_suggested(db, id))
    if reviews {
      row["archiveReviewed"] = true
      let verdict = archive_verdict(db, id)
      if !(verdict is Null) {
        row["archiveCheck"] = verdict
      }
    }
    if known.client_keys.get(key) is Some(k) {
      row["clientKey"] = Json::string(k)
    }
    let card = if carded_set.contains(id.stringify()) { card_view(db, id, names) } else { Json::null() }
    if card is Object(_) {
      let c = card.value("card").unwrap_or(Json::null())
      if c.value("type") == Some(Json::string("options")) {
        // (serde_json's swap_remove of `card`: `before` takes its place)
        row["decision"] = {
          "seq": card.value("seq").unwrap(),
          "before": card.value("before").unwrap(),
          "message": card.value("message").unwrap(),
          "options": c.value("options").unwrap_or(Json::null()),
        }
      }
      row["card"] = card
    } else {
      let need = need_view(db, id, agents, names)
      if !(need is Null) {
        row["need"] = need
      }
    }
    if answered.get(id.stringify()) is Some(list) {
      answered.remove(id.stringify())
      row["answeredBy"] = Json::array(list)
    }
    rows.push(Json::object(row))
    ids.push(key)
  }
  for key in order {
    if chatted.contains(key) {
      continue
    }
    let x = shown.get(key).unwrap()
    let from = origins.get(key)
    let origin = match from { Some(f) => known.origin(f.thread, f.sessions); None => Json::null() }
    let own = match field(x, "title") { String(s) => @jscase.trim_white(s); _ => "" }
    let named : Json = if own != "" {
      { "thread": { "surface": "ember", "title": Json::string(own) } }
    } else {
      match from {
        Some(f) if !(origin is Null) =>
          { "thread": thread_json(f.thread), "firstText": f.first_text, "channelName": origin.value("channelName").unwrap_or(Json::null()) }
        _ => { "thread": { "surface": "ember" } }
      }
    }
    let starter = known.creator(field(x, "created_by"))
    let row : Map[String, Json] = {
      "id": Json::string(key),
      "session": Json::string(key),
      "thread": Json::null(),
      "title": "",
      "agents": Json::array([agent(key)]),
      "last": Json::null(),
      "unread": false,
      "mine": false,
      "lastActiveAt": field(x, "last_active_at"),
      "connect": if field(x, "connect") == Json::string("ember") { Json::null() } else { field(x, "connect") },
      "origin": origin,
      "people": Json::array(if starter is Null { [] } else { [starter] }),
      "creator": starter,
    }
    row["ws"] = field(x, "ws")
    row["named"] = named
    row["mineOf"] = Json::array(([starter] + spoke.get(key).unwrap_or([])).filter(p => !(p is Null)))
    rows.push(Json::object(row))
    ids.push(key)
  }
  let wanted = match scope {
    None => None
    Some(_) => Some(ids.filter(k => in_rows.contains(k)))
  }
  let (openers, opened) = openers_opened(db, wanted)
  let shares = chat_shares(db, wanted, known.now)
  let out : Array[Json] = []
  for i, r in rows {
    let key = ids[i]
    if scope is Some(_) && !in_rows.contains(key) {
      continue
    }
    guard r is Object(o) else { continue }
    let row = Map::from_array(o.to_array())
    row["pinned"] = Json::null()
    if openers.get(key) is Some(op) {
      row["opener"] = op
    }
    if opened.get(key) is Some(children) {
      row["opened"] = Json::array(children)
    }
    if shares.get(key) is Some(s) {
      row["xshare"] = s
    }
    out.push(Json::object(row))
  }
  out
}

///|
fn keys_arg(v : Json?) -> Array[String]? {
  match v {
    Some(Array(xs)) => Some(xs.map(js_text))
    _ => None
  }
}

///|
/// views.ts `sharedOf`: the list whole (`scope` null), or the rows a change of some sessions and threads can touch and
/// the ids of those, for everyone.
pub fn shared_of(db : @sql.Db, host : @host.Host, data : String, sep : String, ask : Json) -> Json raise {
  let args = ask.value("args").unwrap_or(Json::null())
  let known = Known::of(host, data, sep, ask)
  match (keys_arg(args.value("sessions")), args.value("threads")) {
    (Some(sessions), Some(Array(threads))) => {
      let scope = scope_of(db, sessions, threads)
      { "rows": Json::array(shared_rows(db, known, Some(scope))), "scope": Json::array(scope.rows.map(Json::string)) }
    }
    _ => { "rows": Json::array(shared_rows(db, known, None)), "scope": Json::null() }
  }
}

///|
/// rows.ts `sees`: whether a viewer sees what is of the workspace `ws`.
fn sees(viewer : Json, ws : Json) -> Bool {
  ws == viewer.value("workspace").unwrap_or(Json::null()) || (ws is Null && viewer.value("home") != Some(Json::boolean(false)))
}

///|
/// views.ts `sharedChatRows` (GET /chats?shared=1): what the viewer's workspace sees of the list; of some sessions and
/// threads with the ids those can touch.
pub fn shared_chats(db : @sql.Db, host : @host.Host, data : String, sep : String, ask : Json) -> Json raise {
  let args = ask.value("args").unwrap_or(Json::null())
  let viewer = args.value("viewer").unwrap_or(Json::null())
  let seen = (rows : Array[Json]) => Json::array(rows.filter(r => sees(viewer, r.value("ws").unwrap_or(Json::null()))))
  let known = Known::of(host, data, sep, ask)
  match (keys_arg(args.value("sessions")), args.value("threads")) {
    (Some(sessions), Some(Array(threads))) => {
      let scope = scope_of(db, sessions, threads)
      { "rows": seen(shared_rows(db, known, Some(scope))), "scope": Json::array(scope.rows.map(Json::string)) }
    }
    _ => seen(shared_rows(db, known, None))
  }
}
