// A chat's entries and its own log of letters as a device pages them (station/src/read/views.ts `entries`, `letters`:
// GET /threads/:id/entries, /threads/:id/letters): what came since an entry, a page back, a gap, else the latest page,
// each entry as the archive writes it (store/archive.ts `entryJson`) with its author's name and an agent's model and
// runtime. A query's numbers are read as Rust read them (`str::parse::<f64>`, then `as i64`); what it refuses says the
// station's words the pool gives (`words`: `notInteger` by name, `fromAndTo`).

///|
/// views.ts `parseF64`: Rust's `str::parse::<f64>` (no spaces, no hex, nothing empty), none where it does not read.
fn parse_f64(text : String) -> Double? {
  let s = text.to_array()
  let mut i = 0
  let mut sign = 1.0
  if i < s.length() && (s[i] == '+' || s[i] == '-') {
    if s[i] == '-' {
      sign = -1.0
    }
    i += 1
  }
  let body = String::from_array(s[i:].to_array())
  let lower = @jscase.lower(body)
  if lower == "inf" || lower == "infinity" {
    return Some(sign * (1.0 / 0.0))
  }
  if lower == "nan" {
    return Some(0.0 / 0.0)
  }
  // (\d+\.?\d*|\.\d+)([eE][+-]?\d+)?
  let digit = (c : Char) => c >= '0' && c <= '9'
  let b = body.to_array()
  let mut j = 0
  let int_start = j
  while j < b.length() && digit(b[j]) {
    j += 1
  }
  let int_part = String::from_array(b[int_start:j].to_array())
  let mut frac = ""
  if j < b.length() && b[j] == '.' {
    j += 1
    let f = j
    while j < b.length() && digit(b[j]) {
      j += 1
    }
    frac = String::from_array(b[f:j].to_array())
  }
  if int_part == "" && frac == "" {
    return None
  }
  let mut exp = ""
  if j < b.length() && (b[j] == 'e' || b[j] == 'E') {
    j += 1
    let e = j
    if j < b.length() && (b[j] == '+' || b[j] == '-') {
      j += 1
    }
    let d = j
    while j < b.length() && digit(b[j]) {
      j += 1
    }
    if j == d {
      return None
    }
    exp = "e" + String::from_array(b[e:j].to_array())
  }
  if j != b.length() {
    return None
  }
  let normal = (if int_part == "" { "0" } else { int_part }) + (if frac == "" { "" } else { "." + frac }) + exp
  match (try { Ok(@json.parse(normal)) } catch { e => Err(e) }) {
    Ok(Number(n, ..)) => Some(sign * n)
    // (a number beyond a double's range is infinite to Rust)
    _ => Some(sign * (1.0 / 0.0))
  }
}

///|
/// views.ts `asI64`: Rust's `f64 as i64` (truncated, saturating, NaN 0).
fn as_i64(n : Double) -> Int64 {
  if n.is_nan() {
    return 0L
  }
  if n >= 9223372036854775807.0 {
    return 9223372036854775807L
  }
  if n <= -9223372036854775808.0 {
    return -9223372036854775807L - 1L
  }
  n.to_int64()
}

///|
/// A query's pairs, the first of a name counting (`[[k, v], …]`), or a plain map of them.
fn param_of(params : Json, name : String) -> String? {
  match params {
    Array(pairs) => {
      for p in pairs {
        if p is Array([String(k), String(v), ..]) && k == name {
          return Some(v)
        }
      }
      None
    }
    Object(m) =>
      match m.get(name) {
        Some(String(v)) => Some(v)
        _ => None
      }
    _ => None
  }
}

///|
fn int_text(n : Int64) -> Json {
  Json::string(n.to_string())
}

///|
/// What `entries` and `letters` read of a query: the numbers and the limit, refused as the TypeScript refuses them.
priv struct Paging {
  after : Int64?
  before : Int64?
  from : Int64?
  to : Int64?
  limit_given : Bool
  limit : Int
}

///|
fn paging(args : Json) -> Paging raise {
  let params = args.value("params").unwrap_or(Json::null())
  let words = args.value("words").unwrap_or(Json::null())
  let number = (name : String) => {
    guard param_of(params, name) is Some(v) else { return None }
    match parse_f64(v) {
      Some(n) if !n.is_nan() && !n.is_inf() && n.floor() == n && n >= 0.0 => Some(as_i64(n))
      _ => {
        let said = match words.value("notInteger") {
          Some(w) =>
            match w.value(name) {
              Some(String(s)) => s
              _ => name
            }
          None => name
        }
        raise Refused(400, said)
      }
    }
  }
  let after = number("after")
  let before = number("before")
  let from = number("from")
  let to = number("to")
  let asked = param_of(params, "limit")
  let parsed_limit = match asked { Some(a) => parse_f64(a); None => None }
  let wanted = match parsed_limit {
    None => 50.0
    Some(n) if n == 0.0 => 50.0
    Some(n) => n
  }
  let limit = if wanted.is_nan() {
    0
  } else {
    let c = if wanted < 1.0 { 1.0 } else if wanted > 500.0 { 500.0 } else { wanted }
    c.to_int()
  }
  if (from is Some(_)) != (to is Some(_)) {
    raise Refused(400, match words.value("fromAndTo") { Some(String(s)) => s; _ => "from and to" })
  }
  { after, before, from, to, limit_given: asked is Some(_), limit }
}

///|
/// rows.ts `withChange`'s reading of a notice's change: an object whose `was` and `now` are objects.
fn change_of(v : Json) -> Json? {
  match parsed(v) {
    Some(Obj(_) as c) =>
      match (jget(Some(c), "was"), jget(Some(c), "now")) {
        (Some(Obj(_) | Arr(_)), Some(Obj(_) | Arr(_))) => Some(to_json(c))
        _ => None
      }
    _ => None
  }
}

///|
/// rows.ts `letterOf`: a letter's way, title and link, none where it is not one.
fn letter_of(v : Json) -> Json? {
  let out : Map[String, Json] = Map([])
  with_letter(out, v)
  out.get("letter")
}

///|
/// archive.ts `entryJson` of a row of entries (rows.ts `toEntry`), or of the letters' own log (`letterEntry`).
fn entry_json(r : Map[String, Json], letter_log : Bool) -> Json {
  let v : Map[String, Json] = Map([])
  if !letter_log && parsed(field(r, "agent_identity")) is Some(identity) {
    v["agentIdentity"] = to_json(identity)
  }
  v["thread"] = field(r, "thread")
  v["n"] = field(r, "n")
  v["kind"] = if !letter_log && field(r, "kind") == Json::string("edit") { "edit" } else { "message" }
  v["target"] = if letter_log { Json::null() } else { field(r, "target") }
  v["ts"] = field(r, "ts")
  v["authorKind"] = author_kind(field(r, "author_kind"))
  v["author"] = field(r, "author")
  v["text"] = field(r, "text")
  v["attachments"] = json_list(field(r, "attachments"), attachment)
  v["quotes"] = if letter_log { Json::array([]) } else { json_list(field(r, "quotes"), quote) }
  v["declared"] = if letter_log { Json::null() } else { field(r, "declared") }
  if !letter_log {
    for k in ["client", "profile", "runtime"] {
      if !(field(r, k) is Null) {
        v[k] = field(r, k)
      }
    }
    if parsed(field(r, "options")) is Some(o) {
      v["options"] = to_json(o)
    }
    if parsed(field(r, "card")) is Some(c) {
      v["card"] = to_json(c)
    }
  }
  v["at"] = field(r, "at")
  if letter_of(field(r, "letter")) is Some(l) {
    v["letter"] = l
  }
  if !letter_log && change_of(field(r, "change")) is Some(c) {
    v["change"] = c
  }
  Json::object(v)
}

///|
/// views.ts `entryViews`: entries with their authors' names, an agent's with its session's model and runtime.
fn entry_views(db : @sql.Db, known : Known, thread : Json, rows : Array[Map[String, Json]], letter_log : Bool) -> Array[Json] raise {
  let names = known.author_names(db, thread)
  let sessions : Map[String, Map[String, Json]?] = Map([])
  let origins : Map[String, Json] = Map([])
  let out : Array[Json] = []
  for r in rows {
    guard entry_json(r, letter_log) is Object(o) else { continue }
    let v = Map::from_array(o.to_array())
    let kind = js_text(v.get("authorKind").unwrap_or(Json::null()))
    let author = js_text(field(r, "author"))
    v["authorName"] = names.name(kind, author)
    if names.picture(kind, author) is Some(p) {
      v["authorPicture"] = Json::string(p)
    }
    if kind == "agent" {
      let session = match sessions.get(author) {
        Some(s) => s
        None => {
          let s = one(db, "SELECT * FROM sessions WHERE key = ?", [Json::string(author)])
          sessions[author] = s
          s
        }
      }
      if session is Some(s) {
        let identity = v.get("agentIdentity")
        match identity {
          Some(Object(_) as i) if i.value("runtime") is Some(String(_)) => v["authorRuntime"] = i.value("runtime").unwrap()
          _ => {
            let origin = match origins.get(author) {
              Some(o) => o
              None => {
                let o = original_runtime(db, Json::string(author))
                origins[author] = o
                o
              }
            }
            v["authorRuntime"] = if origin is Null { field(s, "runtime") } else { origin }
          }
        }
        let model = match identity {
          Some(Null) | None =>
            if v.get("authorRuntime") == Some(field(s, "runtime")) { field(s, "model") } else { Json::null() }
          Some(Object(_) as i) => i.value("model").unwrap_or(Json::null())
          Some(_) => Json::null()
        }
        if model is String(_) {
          v["authorModel"] = model
        }
      }
    }
    if v.get("declared") is Some(String(d)) {
      v["declared"] = Json::string(said_before(d))
      v["ending"] = Json::string(ending_of(d))
    }
    match v.get("card") {
      Some(_) => ()
      None =>
        if v.get("options") is Some(o) {
          v["card"] = { "type": "options", "options": o }
        }
    }
    out.push(Json::object(v))
  }
  out
}

///|
fn known_thread(db : @sql.Db, thread : Json) -> Unit raise {
  if one(db, "SELECT * FROM threads WHERE id = ?", [thread]) is None {
    raise Refused(404, "unknown thread \{js_text(thread)}")
  }
}

///|
fn max_n(db : @sql.Db, sql : String, thread : Json) -> Json raise {
  match one(db, sql, [thread]) {
    Some(r) if !(field(r, "n") is Null) => field(r, "n")
    _ => Json::number(0.0)
  }
}

///|
/// views.ts `entries`.
pub fn thread_entries(db : @sql.Db, host : @host.Host, data : String, sep : String, ask : Json) -> Json raise {
  let args = ask.value("args").unwrap_or(Json::null())
  let known = Known::of(host, data, sep, ask)
  let thread = args.value("thread").unwrap_or(Json::null())
  known_thread(db, thread)
  let p = paging(args)
  let last = max_n(db, "SELECT MAX(n) AS n FROM entries WHERE thread = ?", thread)
  let between = "SELECT * FROM entries WHERE thread = ? AND n >= CAST(? AS INTEGER) AND n <= CAST(? AS INTEGER) ORDER BY n"
  let max = 9223372036854775807L
  let rows = match (p.after, p.from, p.to) {
    // (`n + 1` wraps at i64::MAX, as a release build's does)
    (Some(a), _, _) =>
      if p.limit_given {
        db.all("\{between} LIMIT ?", [thread, int_text(a + 1L), int_text(max), Json::number(p.limit.to_double())])
      } else {
        db.all(between, [thread, int_text(a + 1L), int_text(max)])
      }
    (None, Some(f), Some(t)) => db.all(between, [thread, int_text(f), int_text(t)])
    _ =>
      db
      .all("SELECT * FROM entries WHERE thread = ? AND n < CAST(? AS INTEGER) ORDER BY n DESC LIMIT ?", [
        thread,
        int_text(p.before.unwrap_or(max)),
        Json::number(p.limit.to_double()),
      ])
      .rev()
  }
  { "last": last, "entries": Json::array(entry_views(db, known, thread, rows, false)) }
}

///|
/// views.ts `letters`.
pub fn thread_letters(db : @sql.Db, host : @host.Host, data : String, sep : String, ask : Json) -> Json raise {
  let args = ask.value("args").unwrap_or(Json::null())
  let known = Known::of(host, data, sep, ask)
  let thread = args.value("thread").unwrap_or(Json::null())
  known_thread(db, thread)
  let p = paging(args)
  let last = max_n(db, "SELECT MAX(n) AS n FROM letters WHERE thread = ?", thread)
  let between = "SELECT * FROM letters WHERE thread = ? AND n >= CAST(? AS INTEGER) AND n <= CAST(? AS INTEGER) ORDER BY n"
  let max = 9223372036854775807L
  let rows = match (p.after, p.from, p.to) {
    (Some(a), _, _) =>
      if p.limit_given {
        db.all("\{between} LIMIT ?", [thread, int_text(a + 1L), int_text(max), Json::number(p.limit.to_double())])
      } else {
        db.all(between, [thread, int_text(a + 1L), int_text(max)])
      }
    (None, Some(f), Some(t)) => db.all(between, [thread, int_text(f), int_text(t)])
    _ =>
      db
      .all("SELECT * FROM letters WHERE thread = ? AND n < CAST(? AS INTEGER) ORDER BY n DESC LIMIT ?", [
        thread,
        int_text(p.before.unwrap_or(max)),
        Json::number(p.limit.to_double()),
      ])
      .rev()
  }
  { "last": last, "letters": Json::array(entry_views(db, known, thread, rows, true)) }
}
