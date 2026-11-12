// A chat's messages as the Router reads a Task through a Comma connect (station/src/read/outflow.ts `outflowMessages`,
// `task.read`): its entries, or its messages alone, after a message, with who wrote each as far as the station's names
// books know them (read/slack-known.ts). The statements are the TypeScript's, as it makes them.

///|
/// read/store.ts PAGE_ORDINARY_KEYS_AFTER.
let page_ordinary_keys_after_sql : String =
  #|SELECT CAST(p.n AS TEXT) AS n FROM (
  #|  SELECT n FROM entries INDEXED BY entries_said WHERE thread=?1 AND n>?2 AND kind='message' AND letter IS NULL
  #|  ORDER BY n LIMIT ?3) p ORDER BY p.n

///|
/// read/store.ts LEGACY_PAGE_ORDINARY_KEYS_AFTER.
let legacy_page_ordinary_keys_after_sql : String =
  #|SELECT CAST(p.n AS TEXT) AS n FROM (
  #|  SELECT n FROM legacy_said WHERE thread=?1 AND n>?2 ORDER BY n LIMIT ?3) p ORDER BY p.n

///|
/// read/store.ts PAGE_LETTER_CANDIDATES_AFTER.
let page_letter_candidates_after_sql : String =
  #|SELECT CAST(e.n AS TEXT) AS n,e.kind FROM entries e INDEXED BY entries_letters
  #|  WHERE e.thread=?1 AND e.n>?2 AND e.letter IS NOT NULL ORDER BY e.n LIMIT ?3

///|
/// read/store.ts LEGACY_SAID_PAGE_HEAD.
let legacy_said_page_head_sql : String =
  #|SELECT CAST(e.n AS TEXT) AS n,e.kind FROM entries e
  #|  WHERE e.thread=?1 AND e.n>?2 ORDER BY e.n LIMIT ?3

///|
/// store/page-letter-index.ts PAGE_LETTER_KEYS_AFTER.
let page_letter_keys_after_sql : String =
  #|SELECT CAST(p.n AS TEXT) AS n FROM (
  #|    SELECT b.n FROM page_letter_rows b WHERE b.thread=?1 AND b.token=?2 AND b.n>CAST(?3 AS INTEGER)
  #|      AND NOT EXISTS (SELECT 1 FROM page_letter_dirty d WHERE d.thread=b.thread AND d.token=b.token AND d.n=b.n)
  #|    UNION ALL
  #|    SELECT e.n FROM page_letter_dirty d CROSS JOIN entries e ON e.thread=d.thread AND e.n=d.n
  #|      WHERE d.thread=?1 AND d.token=?2 AND d.n>CAST(?3 AS INTEGER) AND e.kind='message' AND e.letter IS NOT NULL
  #|    ORDER BY n LIMIT ?4
  #|  ) p ORDER BY p.n

///|
/// store/rows.ts MESSAGE_PAGE_ENTRIES.
let message_page_entries_sql : String =
  #|SELECT e.* FROM json_each(?2) j
  #|  CROSS JOIN entries e ON e.thread=?1 AND e.n=CAST(j.value AS INTEGER) ORDER BY e.n

///|
/// Text keys of integers in their order (store.ts `ascendingKeys`).
fn ascending(keys : Array[String]) -> Array[String] {
  stable_sort(keys, compare_int_text)
}

///|
/// store.ts `messagePageKeysAfter`: the keys of a thread's messages after `after`, at most `limit`, by the said index and
/// the letters'; by a short source head while an old store's lookups are prepared; refused while neither proves it.
fn page_keys_after(db : @sql.Db, thread : Json, after : Json, limit : Int) -> Array[String] raise {
  let legacy = has_legacy_said(db)
  let head = (pending : () -> Error) => {
    let cap = limit + 64
    let rows = db.all(legacy_said_page_head_sql, [thread, after, int_json(cap)])
    let keys = take(text_keys(rows.filter(r => field(r, "kind") == Json::string("message"))), limit)
    if keys.length() < limit && rows.length() == cap {
      raise pending()
    }
    keys
  }
  if legacy {
    let (preparing, needs_drain) = said_page_state(db, thread)
    if preparing || needs_drain {
      return head(() => if preparing {
        Refused(503, legacy_said_pending)
      } else {
        Refused(503, said_pending + Json::array([thread]).stringify())
      })
    }
  }
  let token = @letters.ready_token(db, thread)
  if token is None && !exists_in(db, "index", "entries_letters") {
    return head(() => Refused(503, page_letter_pending + Json::array([thread]).stringify()))
  }
  let ordinary = text_keys(
    db.all(if legacy { legacy_page_ordinary_keys_after_sql } else { page_ordinary_keys_after_sql }, [thread, after, int_json(limit)]),
  )
  if token is Some(t) {
    let letters = text_keys(db.all(page_letter_keys_after_sql, [thread, Json::string(t), after, int_json(limit)]))
    return take(ascending(ordinary + letters), limit)
  }
  let cap = limit + 64
  let candidates = db.all(page_letter_candidates_after_sql, [thread, after, int_json(cap)])
  let ceiling = if candidates.length() == cap {
    match field(candidates[candidates.length() - 1], "n") {
      String(c) => Some(c)
      _ => None
    }
  } else {
    None
  }
  let letters = text_keys(candidates.filter(r => field(r, "kind") == Json::string("message")))
  let known = match ceiling {
    Some(c) => ordinary.filter(k => compare_int_text(k, c) <= 0)
    None => ordinary
  }
  let keys = ascending(known + letters)
  if keys.length() < limit && ceiling is Some(_) {
    raise Refused(503, page_letter_pending + Json::array([thread]).stringify())
  }
  take(keys, limit)
}

///|
/// The workspace whose chats are read (outflow.ts `Of`): as another station asked, else the home one.
fn outflow_of(ws : Json?) -> (Json, Bool) {
  match ws {
    Some({ "workspace": String(w), .. } as o) => (Json::string(w), o.value("home") is Some(True))
    _ => (Json::string("\u{0}home"), true)
  }
}

///|
fn sees_of(of : (Json, Bool), ws : Json) -> Bool {
  ws == of.0 || (ws is Null && of.1)
}

///|
/// store.ts `seesThread`: a chat of the workspace (one with no members, the home one's).
fn sees_thread(db : @sql.Db, of : (Json, Bool), thread : Json) -> Bool raise {
  let members = db.all("SELECT session FROM thread_sessions WHERE thread = ? ORDER BY joined_at, rowid", [thread])
  if members.length() == 0 {
    return sees_of(of, Json::null())
  }
  for m in members {
    if one(db, "SELECT ws FROM sessions WHERE key = ?", [field(m, "session")]) is Some(row) && sees_of(of, field(row, "ws")) {
      return true
    }
  }
  false
}

///|
/// A connect's place on its platform and the names book it is in (slack-known.ts `Team`).
priv struct Team {
  id : String
  book : String
}

///|
/// slack-known.ts `teams`: each connect's Slack workspace, Feishu company or Comma group, this station's over those of
/// other stations whose chats run here.
fn teams(host : @host.Host, data : String, sep : String) -> Map[String, Team] raise {
  let out : Map[String, Team] = Map([])
  let remote = read_json(host, join_path(sep, data, "remote-connects.json"))
  for e in entries_of(Some(remote)) {
    let d = jget(Some(e.1), "described")
    match str_of(jget(d, "kind")) {
      Some("feishu") => out[e.0] = { id: e.0, book: "feishu" }
      Some("slack") =>
        match str_of(jget(d, "team")) {
          Some(t) if t != "" => out[e.0] = { id: t, book: "slack" }
          _ => ()
        }
      _ => ()
    }
  }
  let own = read_json(host, join_path(sep, data, "config.json"))
  guard jget(Some(own), "connects") is Some(Arr(connects)) else { return out }
  for c in connects {
    guard str_of(jget(Some(c), "id")) is Some(id) else { continue }
    match str_of(jget(Some(c), "kind")) {
      Some("feishu") => out[id] = { id, book: "feishu" }
      Some("comma") => out[id] = { id, book: "comma" }
      _ =>
        match str_of(jget(jget(jget(Some(c), "slack"), "team"), "id")) {
          Some(t) if t != "" => out[id] = { id: t, book: "slack" }
          _ => ()
        }
    }
  }
  out
}

///|
/// outflow.ts `person`: who a person reference is as far as known, with where they were heard.
fn outflow_person(host : @host.Host, data : String, sep : String, teams_of : () -> Map[String, Team] raise, ref : String) -> Json raise {
  if ref.has_prefix("slack:") {
    let rest = ref.view(start_offset=6).to_owned()
    match rest.find(":") {
      Some(colon) if colon > 0 && colon < rest.length() - 1 => {
        let connect = rest.view(end_offset=colon).to_owned()
        let user = rest.view(start_offset=colon + 1).to_owned()
        let team = teams_of().get(connect)
        let book_file = match team {
          Some(t) if t.book == "feishu" => "feishu-names.json"
          Some(t) if t.book == "comma" => "comma-names.json"
          _ => "slack-names.json"
        }
        let names = match read_json(host, join_path(sep, data, book_file)) {
          Obj(_) as b => Some(b)
          _ => None
        }
        let place = match team { Some(t) => t.id; None => "?" }
        let known = jget(jget(names, "u:\{place}:\{user}"), "person")
        let (name, email) = match jget(known, "name") {
          Some(Str(n)) => {
            let n = @jsjson.raw_text(n)
            let e = match jget(known, "email") { Some(Str(e)) => @jsjson.raw_text(e); _ => "" }
            (if n != "" { n } else { user }, if e != "" { Json::string(e) } else { Json::null() })
          }
          _ => (user, Json::null())
        }
        let via = match team { Some(t) => t.book; None => "slack" }
        return {
          "name": if ref.has_suffix(":" + name) { Json::null() } else { Json::string(name) },
          "email": email,
          "via": Json::string(via),
        }
      }
      _ => ()
    }
  }
  if ref == "local" {
    return { "name": Json::null(), "email": Json::null(), "via": "local" }
  }
  { "name": Json::null(), "email": Json::string(ref), "via": "cloud" }
}

///|
/// A whole number from the args (another station's may say anything), else 0 (ops-usage.ts `num`).
fn whole(v : Json?) -> Double {
  match v {
    Some(Number(n, ..)) if n == n.floor() && n.abs() <= 9007199254740991.0 => n
    _ => 0.0
  }
}

///|
/// outflow.ts `outflowMessages`: a chat's messages after its message `after`, at most `limit`, oldest first; null for a
/// chat that is not the workspace's.
pub fn outflow_messages(db : @sql.Db, host : @host.Host, data : String, sep : String, args : Json) -> Json raise {
  let thread = Json::number(whole(args.value("thread")))
  let after = whole(args.value("after"))
  let limit = {
    let l = whole(args.value("limit"))
    if l < 1.0 { 1 } else if l > 500.0 { 500 } else { l.to_int() }
  }
  let of = outflow_of(args.value("ws"))
  let messages_only = args.value("messagesOnly") is Some(True)
  if one(db, "SELECT 1 AS x FROM threads WHERE id = ?", [thread]) is None || !sees_thread(db, of, thread) {
    return Json::null()
  }
  let rows = if messages_only {
    db.exec("SAVEPOINT message_entries_after_read")
    defer (db.exec("RELEASE message_entries_after_read") catch { _ => () })
    let keys = page_keys_after(db, thread, Json::number(after), limit + 1)
    if keys.length() == 0 {
      []
    } else {
      db.all(message_page_entries_sql, [thread, Json::array(keys.map(Json::string)).stringify() |> Json::string])
    }
  } else {
    db.all("SELECT * FROM entries WHERE thread = ? AND n >= ? AND n <= ? ORDER BY n LIMIT ?", [
      thread,
      Json::number(after + 1.0),
      as_integer(Json::string(i64_max)),
      int_json(limit + 1),
    ])
  }
  let page = take_rows(rows, limit)
  let mut known : Map[String, Team]? = None
  let teams_of = () => match known {
    Some(t) => t
    None => {
      let t = teams(host, data, sep)
      known = Some(t)
      t
    }
  }
  let people : Map[String, Json] = Map([])
  let messages = []
  for e in page {
    let kind = field(e, "author_kind")
    let author_kind = match kind {
      String("agent") => "agent"
      String("ember") | String("stillfail") => "ember"
      _ => "person"
    }
    let m : Map[String, Json] = {
      "n": field(e, "n"),
      "kind": if field(e, "kind") == Json::string("edit") { "edit" } else { "message" },
      "target": field(e, "target"),
      "authorKind": Json::string(author_kind),
      "author": field(e, "author"),
      "text": field(e, "text"),
      "at": field(e, "at"),
    }
    if author_kind == "person" && field(e, "author") is String(a) {
      let p = match people.get(a) {
        Some(p) => p
        None => {
          let p = outflow_person(host, data, sep, teams_of, a)
          people[a] = p
          p
        }
      }
      m["person"] = p
    }
    messages.push(Json::object(m))
  }
  let last = match one(db, "SELECT MAX(n) AS n FROM entries WHERE thread = ?", [thread]) {
    Some(r) if !(field(r, "n") is Null) => field(r, "n")
    _ => Json::number(0.0)
  }
  let out : Map[String, Json] = {
    "thread": thread,
    "messages": Json::array(messages),
    "last": last,
    "more": Json::boolean(rows.length() > page.length()),
  }
  if messages_only {
    out["messagesOnly"] = true
  }
  Json::object(out)
}

///|
fn take_rows(rows : Array[Map[String, Json]], limit : Int) -> Array[Map[String, Json]] {
  if rows.length() > limit {
    rows.view(end=limit).iter().collect()
  } else {
    rows
  }
}
