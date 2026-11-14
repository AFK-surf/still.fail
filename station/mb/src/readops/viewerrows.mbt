// The chat list as one viewer has it, made by the station for a device that does not make it itself (station/src/read/
// views.ts `chats`, `chatRows`, `archivedPage`: GET /chats, and a page of the archive): each shared row with what is the
// viewer's own (client/core-ts/src/chat-row.ts `rowFor`) and in the viewer's words (`worded`: its title by the one rule
// client/core-ts/src/titles.ts names a chat by), the words given by the pool in the language asked.

///|
/// views.ts ARCHIVE_PAGE.
let archive_page : Int = 50

///|
/// titles.ts `withoutMentions`: text without Slack's `<@U123>` mentions.
fn without_mentions(text : String) -> String {
  let out = StringBuilder::new()
  let mut rest = text
  while rest.find("<@") is Some(at) {
    out.write_string(rest.view(end_offset=at).to_owned())
    let after = rest.view(start_offset=at + 2).to_owned()
    match after.find(">") {
      Some(end) if end > 0 && after.view(end_offset=end).iter().all(c => (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')) =>
        rest = after.view(start_offset=end + 1).to_owned()
      _ => {
        out.write_string("<@")
        rest = after
      }
    }
  }
  out.write_string(rest)
  out.to_string()
}

///|
/// titles.ts `chatTitle`: what a chat is called: as given, else a still.fail chat untitled, else a thread's first line a
/// person wrote, else its channel, else a direct message or untitled.
fn chat_title(t : Json, first_text : Json, channel_name : Json, untitled : String, direct : String) -> String {
  let text = (k : String) => match t.value(k) {
    Some(String(s)) => @jscase.trim_white(s)
    _ => ""
  }
  let given = if text("title") != "" { text("title") } else { text("autoTitle") }
  if given != "" {
    return given
  }
  let surface = match t.value("surface") { Some(String(s)) => s; _ => "" }
  if surface == "chat" || surface == "ember" || surface == "stillfail" {
    return untitled
  }
  let first = without_mentions(match first_text { String(s) => s; _ => "" })
  for line in first.split("\n") {
    let words = @jscase.split_by(line.to_owned(), @jscase.is_white_space).filter(w => w != "")
    let joined = words.join(" ")
    if joined != "" {
      return joined
    }
  }
  let name = @jscase.trim_white(match channel_name { String(s) => s; _ => "" })
  if name != "" {
    return if surface.has_prefix("feishu:") { name } else { "#" + name }
  }
  if text("channel").has_prefix("D") {
    return direct
  }
  untitled
}

///|
/// What is the viewer's own of the list (chat-row.ts `Own`).
priv struct Own {
  email : String
  slack : Array[String]
  reads : Map[String, Json]
  dismissed : Set[String]
  kept : Set[String]
  hidden : Set[String]
  muted : Set[String]
  pins : Map[String, Json]
}

///|
/// chat-row.ts `rowFor` of a shared row, in the viewer's words (`worded`).
fn row_for(shared : Json, own : Own, words : Json) -> Json {
  guard shared is Object(o) else { return shared }
  let word = (k : String) => match words.value(k) { Some(String(s)) => s; _ => "" }
  let row = Map::from_array(o.to_array())
  let mine_of = row.get("mineOf")
  let said = row.get("said").unwrap_or(Json::null())
  let answered_by = row.get("answeredBy")
  row.remove("mineOf")
  row.remove("said")
  row.remove("answeredBy")
  row.remove("ws")
  // chat-row.ts `worded`
  if row.get("named") is Some(named) {
    row.remove("named")
    row["title"] = Json::string(chat_title(
      named.value("thread").unwrap_or(Json::null()),
      named.value("firstText").unwrap_or(Json::null()),
      named.value("channelName").unwrap_or(Json::null()),
      word("untitled"),
      word("directMessage"),
    ))
  }
  if row.get("last") is Some(Object(l)) && l.get("quotedOnly") == Some(Json::boolean(true)) {
    let last = Map::from_array(l.to_array())
    last.remove("quotedOnly")
    last["text"] = Json::string(word("quotedOnly"))
    row["last"] = Json::object(last)
  }
  let mine = (p : Json) => is_mine(own.email, own.slack, p)
  let thread = match row.get("thread") { Some(Number(_, ..) as t) => Some(t); _ => None }
  // chat-row.ts `unread`
  row["unread"] = Json::boolean(match thread {
    Some(t) =>
      match said {
        Object(_) => {
          let by_viewer = said.value("authorKind") == Some(Json::string("person")) &&
            mine({ "id": said.value("author").unwrap_or(Json::null()), "email": said.value("author").unwrap_or(Json::null()) })
          let n = if by_viewer { said.value("other") } else { said.value("n") }
          let read = num(own.reads.get(js_text(t)).unwrap_or(Json::number(0.0)))
          n is Some(Number(x, ..)) && x > read
        }
        _ => false
      }
    None => false
  })
  row["mine"] = Json::boolean(match mine_of { Some(Array(ps)) => ps.iter().any(mine); _ => false })
  if thread is Some(t) {
    let k = js_text(t)
    row["archiveReminderDismissed"] = Json::boolean(own.kept.contains(k))
    row["hidden"] = Json::boolean(own.hidden.contains(k))
    row["muted"] = Json::boolean(own.muted.contains(k))
    for which in ["card", "need", "decision"] {
      if row.get(which) is Some(Object(c)) && own.dismissed.contains("\{k}:\{js_text(c.get("seq").unwrap_or(Json::null()))}") {
        let d = Map::from_array(c.to_array())
        d["dismissed"] = true
        row[which] = Json::object(d)
      }
    }
    let answered = match answered_by {
      Some(Array(xs)) =>
        xs.filter_map(a => match a {
          Object(m) if mine(m.get("by").unwrap_or(Json::null())) => {
            let v = Map::from_array(m.to_array())
            v.remove("by")
            Some(Json::object(v))
          }
          _ => None
        })
      _ => []
    }
    if answered.length() > 0 {
      row["answered"] = Json::array(answered)
    }
  }
  row["pinned"] = match row.get("id") { Some(String(id)) => own.pins.get(id).unwrap_or(Json::null()); _ => Json::null() }
  Json::object(row)
}

///|
/// JavaScript's `Number(text)`: white space around it, decimal (with `Infinity`), or hex, octal and binary; NaN else.
fn js_number(text : String) -> Double {
  let t = @jscase.trim(text)
  if t == "" {
    return 0.0
  }
  let lower = @jscase.lower(t)
  for prefix in [("0x", 16), ("0o", 8), ("0b", 2)] {
    if lower.has_prefix(prefix.0) && lower.length() > 2 {
      let mut n = 0.0
      for c in lower.view(start_offset=2) {
        let d = if c >= '0' && c <= '9' { c.to_int() - '0'.to_int() } else if c >= 'a' && c <= 'f' { c.to_int() - 'a'.to_int() + 10 } else { 99 }
        if d >= prefix.1 {
          return 0.0 / 0.0
        }
        n = n * prefix.1.to_double() + d.to_double()
      }
      return n
    }
  }
  match t {
    "Infinity" | "+Infinity" => return 1.0 / 0.0
    "-Infinity" => return -1.0 / 0.0
    _ => ()
  }
  if lower.contains("inf") || lower.contains("nan") {
    return 0.0 / 0.0
  }
  parse_f64(t).unwrap_or(0.0 / 0.0)
}

///|
/// views.ts `chats`: the viewer's list (or the archive's, `archived`), of `scope`'s rows or whole.
fn viewer_chats(db : @sql.Db, known : Known, viewer : Json, words : Json, archived : Bool, scope : Scope?) -> Array[Json] raise {
  let rows = shared_rows(db, known, scope, archived~).filter(r => sees(viewer, r.value("ws").unwrap_or(Json::null())))
  let email = match viewer.value("email") { Some(String(e)) => e; _ => "" }
  let threads = rows.filter_map(r => match r.value("thread") { Some(Number(_, ..) as t) => Some(t); _ => None })
  let keys = rows.filter_map(r => match r.value("id") { Some(String(k)) => Some(k); _ => None })
  let set_of = (sql : String, params : Array[Json]) => {
    let out : Set[String] = Set::new()
    for r in db.all(sql, params) {
      out.add(js_text(field(r, "thread")))
    }
    out
  }
  let reads : Map[String, Json] = Map([])
  if threads.length() > 0 {
    for r in db.all("SELECT thread, n FROM reads WHERE viewer = ?1 AND thread IN (SELECT value FROM json_each(?2))", [Json::string(email), ids_json(threads)]) {
      reads[js_text(field(r, "thread"))] = field(r, "n")
    }
  }
  let dismissed : Set[String] = Set::new()
  let kept : Set[String] = Set::new()
  match scope {
    None => {
      for r in db.all("SELECT thread, n FROM dismissed WHERE viewer = ?", [Json::string(email)]) {
        dismissed.add("\{js_text(field(r, "thread"))}:\{js_text(field(r, "n"))}")
      }
      for r in db.all("SELECT thread FROM kept_chats WHERE viewer = ?1", [Json::string(email)]) {
        kept.add(js_text(field(r, "thread")))
      }
    }
    Some(sc) =>
      for t in unique_ids([sc.threads]) {
        for r in db.all("SELECT thread, n FROM dismissed WHERE viewer = ? AND thread = ?", [Json::string(email), t]) {
          dismissed.add("\{js_text(field(r, "thread"))}:\{js_text(field(r, "n"))}")
        }
        for r in db.all("SELECT thread FROM kept_chats WHERE viewer = ? AND thread = ?", [Json::string(email), t]) {
          kept.add(js_text(field(r, "thread")))
        }
      }
  }
  let hidden = if threads.length() == 0 { Set::new() } else {
    set_of("SELECT thread FROM hidden_chats WHERE viewer = ?1 AND thread IN (SELECT value FROM json_each(?2))", [Json::string(email), ids_json(threads)])
  }
  let muted = if threads.length() == 0 { Set::new() } else {
    set_of("SELECT thread FROM muted_chats WHERE viewer = ?1 AND thread IN (SELECT value FROM json_each(?2))", [Json::string(@jscase.lower(email)), ids_json(threads)])
  }
  let pins : Map[String, Json] = Map([])
  let pin_rows = match scope {
    None => db.all("SELECT session, at FROM pins WHERE viewer = ?", [Json::string(email)])
    Some(_) =>
      if keys.length() == 0 {
        []
      } else {
        db.all("SELECT session, at FROM pins WHERE viewer = ?1 AND session IN (SELECT value FROM json_each(?2))", [Json::string(email), ids_json(keys.map(Json::string))])
      }
  }
  for r in pin_rows {
    pins[js_text(field(r, "session"))] = field(r, "at")
  }
  let slack = db.all("SELECT slack_user FROM identities WHERE viewer = ? ORDER BY at", [Json::string(email)]).map(r => js_text(field(r, "slack_user")))
  let own : Own = { email, slack, reads, dismissed, kept, hidden, muted, pins }
  rows.map(r => row_for(r, own, words))
}

///|
/// ops.ts `chats`: a page of the archive (`archived` with `page`: views.ts `archivedPage`), else the viewer's list or the
/// archive's whole.
pub fn viewer_chat_list(db : @sql.Db, host : @host.Host, data : String, sep : String, ask : Json) -> Json raise {
  let args = ask.value("args").unwrap_or(Json::null())
  let known = Known::of(host, data, sep, ask)
  let viewer = args.value("viewer").unwrap_or(Json::null())
  let words = args.value("words").unwrap_or(Json::null())
  let archived = match args.value("archived") { Some(True) => true; _ => false }
  guard archived && args.value("page") is Some(String(page)) else {
    return Json::array(viewer_chats(db, known, viewer, words, archived, None))
  }
  // ops.ts `cursorOf`: where the page before ended, `<when>:<key or chat id>`, or "" for its first.
  let (when, id) = match page.find(":") {
    Some(at) if at > 0 =>
      match js_number(page.view(end_offset=at).to_owned()) {
        n if n == n.floor() && n.abs() <= 9007199254740991.0 => (Json::number(n), Json::string(page.view(start_offset=at + 1).to_owned()))
        _ => (Json::number(9007199254740991.0), Json::string("\u{ffff}"))
      }
    _ => (Json::number(9007199254740991.0), Json::string("\u{ffff}"))
  }
  let items = db.all(
    "SELECT kind, id, at FROM (\n    SELECT 's' AS kind, key AS id, archived_at AS at FROM sessions INDEXED BY sessions_put_away WHERE archived_at IS NOT NULL AND (archived_at < ?1 OR (archived_at = ?1 AND key < ?2))\n    UNION ALL\n    SELECT 't' AS kind, CAST(id AS TEXT) AS id, hidden_at AS at FROM threads INDEXED BY threads_put_away WHERE hidden_at IS NOT NULL AND (hidden_at < ?1 OR (hidden_at = ?1 AND CAST(id AS TEXT) < ?2))\n  ) ORDER BY at DESC, id DESC LIMIT ?3",
    [when, id, Json::number(archive_page.to_double())],
  )
  let sessions = items.filter(i => field(i, "kind") == Json::string("s")).map(i => js_text(field(i, "id")))
  let threads = items.filter(i => field(i, "kind") == Json::string("t")).map(i => @json.parse(js_text(field(i, "id"))) catch { _ => Json::null() })
  let rows = if items.length() == 0 { [] } else { viewer_chats(db, known, viewer, words, true, Some(scope_of(db, sessions, threads))) }
  let next = match items.last() {
    Some(last) if items.length() >= archive_page => Json::string("\{js_text(field(last, "at"))}:\{js_text(field(last, "id"))}")
    _ => Json::null()
  }
  { "rows": Json::array(rows), "next": next }
}

///|
/// views.ts `chatRows`: the viewer's rows a change of some sessions and threads can touch, and the ids of those.
pub fn viewer_chat_rows(db : @sql.Db, host : @host.Host, data : String, sep : String, ask : Json) -> Json raise {
  let args = ask.value("args").unwrap_or(Json::null())
  let known = Known::of(host, data, sep, ask)
  let sessions = keys_arg(args.value("sessions")).unwrap_or([])
  let threads = match args.value("threads") { Some(Array(t)) => t; _ => [] }
  let scope = scope_of(db, sessions, threads)
  {
    "rows": Json::array(viewer_chats(db, known, args.value("viewer").unwrap_or(Json::null()), args.value("words").unwrap_or(Json::null()), false, Some(scope))),
    "scope": Json::array(scope.rows.map(Json::string)),
  }
}
