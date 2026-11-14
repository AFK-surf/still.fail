// The chats a Comma connect sends of the workspace (station/src/read/outflow.ts `outflowChats`, v1 `chats`): those
// with something new since a time, the latest active first, each with where it is, its title, how it stands, who
// started it, its agents, what it asks of whom now, its link in the app and whether a Comma Router wrote in it; a page
// of them, or all. Written out field by field as that file does, so another station of another version is answered
// the same.

///|
let outflow_chats_pending : String = "outflow chat order is still being prepared"

///|
/// JavaScript's `encodeURIComponent`.
fn encode_uri_component(s : String) -> String {
  let out = StringBuilder::new()
  let hex = "0123456789ABCDEF"
  let byte = (b : Int) => {
    out.write_char('%')
    out.write_char(hex.unsafe_get(b >> 4).to_int().unsafe_to_char())
    out.write_char(hex.unsafe_get(b & 15).to_int().unsafe_to_char())
  }
  for c in s {
    let u = c.to_int()
    if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || "-_.!~*'()".contains_char(c) {
      out.write_char(c)
    } else if u < 0x80 {
      byte(u)
    } else if u < 0x800 {
      byte(0xc0 | (u >> 6))
      byte(0x80 | (u & 63))
    } else if u < 0x10000 {
      byte(0xe0 | (u >> 12))
      byte(0x80 | ((u >> 6) & 63))
      byte(0x80 | (u & 63))
    } else {
      byte(0xf0 | (u >> 18))
      byte(0x80 | ((u >> 12) & 63))
      byte(0x80 | ((u >> 6) & 63))
      byte(0x80 | (u & 63))
    }
  }
  out.to_string()
}

///|
/// outflow.ts `state`: how a chat stands by its agents' latest turn.
fn outflow_state(turn : Json) -> Json {
  guard turn is Object(_) else { return Json::null() }
  match turn.value("outcome") {
    None | Some(Null) => return Json::string("working")
    _ => ()
  }
  guard turn.value("declared") is Some(String(d)) else { return Json::string("ended") }
  let said = ending_of(d)
  Json::string(if said == "need_help" { "need_human" } else { said })
}

///|
/// outflow.ts `assigneeAt`: the email of who decides the card on a message, as it names one.
fn assignee_at(db : @sql.Db, thread : Json, n : Json) -> String? raise {
  guard one(db, "SELECT card FROM entries WHERE thread = ? AND n = ? AND kind = 'message'", [thread, n]) is Some(r) &&
    field(r, "card") is String(card) else {
    return None
  }
  match (try { Some(@jsjson.parse(card)) } catch { _ => None }) {
    Some(v) =>
      match jget(Some(v), "assignee") {
        Some(Str(a)) if !js_blank(@jsjson.text(a)) => Some(@jscase.lower(@jscase.trim(@jsjson.text(a))))
        _ => None
      }
    None => None
  }
}

///|
/// outflow.ts `unreadBy`: whether a chat's latest message is one its creator has not read, past where they read it to.
fn unread_by(db : @sql.Db, thread : Json, ref : String, email : String) -> Bool raise {
  guard one(db, "SELECT e.n, e.author_kind, e.author FROM thread_state t JOIN entries e ON e.thread = t.thread AND e.n = t.said_n\n    WHERE t.thread = ?", [thread]) is Some(said) else {
    return false
  }
  let author = js_text(field(said, "author"))
  if field(said, "author_kind") == Json::string("person") && (author == ref || @jscase.lower(author) == email) {
    return false
  }
  let read = match one(db, "SELECT MAX(n) AS n FROM reads WHERE viewer IN (?1, lower(?1)) AND thread = ?2", [Json::string(email), thread]) {
    Some(r) if field(r, "n") is Number(n, ..) => n
    _ => 0.0
  }
  num(field(said, "n")) > read
}

///|
/// outflow.ts `attentionOf`: what a chat asks of someone now; none when nothing (and for an archived chat).
fn attention_of(db : @sql.Db, thread : Map[String, Json], latest : Json, creator : String?, email : String?) -> Json? raise {
  if latest is Null || !(field(thread, "hidden_at") is Null) {
    return None
  }
  let said = outflow_state(latest)
  let mine = match email { Some(e) => [Json::string(@jscase.lower(e))]; None => [] }
  let words = (v : Json?) => match v {
    Some(String(s)) if !js_blank(s) => Json::string(@jscase.trim(s))
    _ => Json::null()
  }
  if said == Json::string("need_human") {
    let assignee = match latest.value("about") {
      Some(Object(_) as about) => assignee_at(db, about.value("thread").unwrap_or(Json::null()), about.value("seq").unwrap_or(Json::null()))
      _ => None
    }
    return Some({
      "kind": "need",
      "waitsFor": Json::array(match assignee { Some(a) => [Json::string(a)]; None => mine }),
      "note": words(latest.value("need")),
    })
  }
  if said == Json::string("all_done") {
    guard email is Some(e) && creator is Some(c) && field(thread, "surface") == Json::string("ember") else { return None }
    return if unread_by(db, field(thread, "id"), c, @jscase.lower(e)) {
      Some({ "kind": "done", "waitsFor": Json::array(mine), "note": words(latest.value("need")) })
    } else {
      None
    }
  }
  if latest.value("outcome") == Some(Json::string("failed")) && latest.value("declared") == Some(Json::null()) {
    let note = match words(latest.value("detail")) {
      String(d) => words(Some(Json::string(d.split("\n").next().map(v => v.to_owned()).unwrap_or(""))))
      _ => Json::null()
    }
    return Some({ "kind": "failed", "waitsFor": Json::array(mine), "note": note })
  }
  None
}

///|
/// outflow.ts `outflowChats`.
pub fn outflow_chats(db : @sql.Db, host : @host.Host, data : String, sep : String, ask : Json) -> Json raise {
  let args = ask.value("args").unwrap_or(Json::null())
  let since = Json::number(whole(args.value("since")))
  let of = outflow_of(args.value("ws"))
  let page = match args.value("limit") {
    Some(Number(_, ..)) => {
      let l = whole(args.value("limit"))
      Some((if l < 1.0 { 1 } else if l > 1000.0 { 1000 } else { l.to_int() }, match args.value("before") { Some(String(b)) => Some(b); _ => None }))
    }
    _ => None
  }
  let pages = match args.value("pages") {
    Some({ "origin": String(o), "workspace": String(w), "station": String(st), .. }) => Some((o, w, st))
    _ => None
  }
  let words = args.value("words").unwrap_or(Json::null())
  let word = (k : String) => match words.value(k) { Some(String(s)) => s; _ => "" }
  // outflow-index.ts `outflowChatIndexReady`
  let scopes = if of.1 { [Json::string("H"), Json::string("W" + js_text(of.0))] } else { [Json::string("W" + js_text(of.0))] }
  let ready = exists_in(db, "table", "outflow_chat_progress") &&
    (match one(db, "SELECT done FROM outflow_chat_progress WHERE id = 1", []) { Some(r) => field(r, "done") == Json::number(1.0); None => false }) &&
    scopes.iter().all(sc => (one(db, "SELECT 1 AS x FROM outflow_chat_order INDEXED BY outflow_chat_scope_order WHERE scope = ? AND dirty = 1 LIMIT 1", [sc]) catch { _ => None }) is None)
  if !ready {
    raise Failure(outflow_chats_pending)
  }
  let cursor = match page {
    Some((_, Some(before))) => {
      let parts = before.split(".").map(v => js_number(v.to_owned())).collect()
      let at = parts.get(0).unwrap_or(0.0 / 0.0)
      let thread = parts.get(1).unwrap_or(0.0 / 0.0)
      if !at.is_nan() && !at.is_inf() && !thread.is_nan() && !thread.is_inf() { Some((at, thread)) } else { None }
    }
    _ => None
  }
  let limit = match page { Some((l, _)) => Json::number((l + 1).to_double()); None => Json::number(-1.0) }
  let candidates : Map[String, (Json, Double)] = Map([])
  for scope in scopes {
    let rows = match cursor {
      Some((at, t)) =>
        db.all("SELECT thread, at FROM outflow_chat_order INDEXED BY outflow_chat_scope_order\n  WHERE scope = ?1 AND dirty = 0 AND at >= ?2 AND (at, thread) < (?3, ?4) ORDER BY at DESC, thread DESC LIMIT ?5", [
          scope, since, Json::number(at), Json::number(t), limit,
        ])
      None =>
        db.all("SELECT thread, at FROM outflow_chat_order INDEXED BY outflow_chat_scope_order\n  WHERE scope = ?1 AND dirty = 0 AND at >= ?2 ORDER BY at DESC, thread DESC LIMIT ?3", [scope, since, limit])
    }
    for r in rows {
      candidates[js_text(field(r, "thread"))] = (field(r, "thread"), num(field(r, "at")))
    }
  }
  let ordered = stable_sort(candidates.values().collect(), (a, b) => {
    let d = if b.1 != a.1 { b.1 - a.1 } else { num(b.0) - num(a.0) }
    if d < 0.0 { -1 } else if d > 0.0 { 1 } else { 0 }
  })
  let more = match page { Some((l, _)) => ordered.length() > l; None => false }
  let threads = match page { Some((l, _)) if ordered.length() > l => ordered[:l].to_array(); _ => ordered }
  let sessions : Map[String, Map[String, Json]?] = Map([])
  let session_of = (k : String) => match sessions.get(k) {
    Some(s) => s
    None => {
      let s = one(db, "SELECT * FROM sessions WHERE key = ?", [Json::string(k)])
      sessions[k] = s
      s
    }
  }
  let listed : Array[(Map[String, Json], Array[String], Double)] = []
  for t in threads {
    guard one(db, "SELECT * FROM threads WHERE id = ?", [t.0]) is Some(thread) else { continue }
    let members : Array[String] = []
    for m in db.all("SELECT * FROM thread_sessions WHERE thread = ? ORDER BY joined_at, rowid", [t.0]) {
      let k = js_text(field(m, "session"))
      if session_of(k) is Some(s) && sees_of(of, field(s, "ws")) {
        members.push(k)
      }
    }
    if members.length() > 0 {
      listed.push((thread, members, t.1))
    }
  }
  let turns : Map[String, Json] = Map([])
  for l in listed {
    for k in l.1 {
      if !turns.contains(k) {
        turns[k] = last_turn_of(db, k)
      }
    }
  }
  let teams_cache : Ref[Map[String, Team]?] = Ref(None)
  let teams_of = () => match teams_cache.val {
    Some(t) => t
    None => {
      let t = teams(host, data, sep)
      teams_cache.val = Some(t)
      t
    }
  }
  let chats : Array[Json] = []
  for l in listed {
    let (thread, members, last_active_at) = l
    let id = field(thread, "id")
    let latest_list = stable_sort(members.filter_map(k => match turns.get(k) { Some(Object(_) as t) => Some((k, t)); _ => None }), (a, b) => {
      let d = num(b.1.value("startedAt").unwrap_or(Json::null())) - num(a.1.value("startedAt").unwrap_or(Json::null()))
      if d < 0.0 { -1 } else if d > 0.0 { 1 } else { 0 }
    })
    let latest = match latest_list.get(0) { Some(p) => p.1; None => Json::null() }
    let creator = match field(thread, "created_by") {
      String(c) => Some(c)
      _ =>
        match session_of(members[0]) {
          Some(s) if field(s, "created_by") is String(c) => Some(c)
          _ => None
        }
    }
    let who = match creator {
      Some(c) =>
        match outflow_person(host, data, sep, teams_of, c) {
          Object(p) => {
            let m : Map[String, Json] = { "ref": Json::string(c) }
            for k, v in p {
              m[k] = v
            }
            Json::object(m)
          }
          _ => Json::null()
        }
      None => Json::null()
    }
    let email = match who.value("email") { Some(String(e)) if e != "" => Some(e); _ => None }
    let attention = attention_of(db, thread, latest, creator, email)
    let lead = match latest_list.get(0) {
      Some(p) => members.search_by(k => k == p.0).map(i => members[i]).unwrap_or(members[0])
      None => members[0]
    }
    let url = match pages {
      Some((origin, workspace, station)) => {
        let ws = match session_of(lead) { Some(s) if field(s, "ws") is String(w) => w; _ => workspace }
        Some("\{origin}/o/\{ws}/\{station}/\{encode_uri_component(lead)}")
      }
      None => None
    }
    let needs_first = !given_title(thread) && !(field(thread, "surface") is String("chat" | "ember" | "stillfail"))
    let first = if needs_first { first_text(db, id) } else { Json::null() }
    let chat : Map[String, Json] = {
      "thread": id,
      "surface": if field(thread, "surface") == Json::string("ember") { "stillfail" } else { field(thread, "surface") },
      "title": Json::string(chat_title(thread_json(thread), first, Json::null(), word("untitled"), word("directMessage"))),
      "state": outflow_state(latest),
      "creator": who,
      "createdAt": field(thread, "created_at"),
      "lastActiveAt": Json::number(last_active_at),
      "archived": Json::boolean(!(field(thread, "hidden_at") is Null)),
      "agents": Json::array(members.map(k => match session_of(k) {
        Some(s) => ({ "runtime": field(s, "runtime"), "model": field(s, "model") } : Json)
        None => Json::null()
      })),
    }
    if attention is Some(a) {
      chat["attention"] = a
    }
    if url is Some(u) {
      chat["url"] = Json::string(u)
    }
    if field(thread, "surface") == Json::string("ember") &&
      one(db, "SELECT 1 AS x FROM thread_people WHERE thread = ? AND author >= 'slack:' AND author < 'slack;' LIMIT 1", [id]) is Some(_) {
      chat["router"] = true
    }
    chats.push(Json::object(chat))
  }
  guard page is Some(_) else { return { "since": since, "chats": Json::array(chats) } }
  let next = match chats.last() {
    Some(last) if more => Json::string("\{js_text(last.value("lastActiveAt").unwrap())}.\{js_text(last.value("thread").unwrap())}")
    _ => Json::null()
  }
  { "since": since, "chats": Json::array(chats), "more": Json::boolean(more), "next": next }
}
