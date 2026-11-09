// A session's reads of what it keeps beside its chats (station/src/read/sessions.ts `widgetState`, `transcriptFile`):
// what a widget holds, and where the session's current transcript is on this machine.

///|
fn session_row(db : @sql.Db, key : Json) -> Map[String, Json] raise {
  guard one(db, "SELECT * FROM sessions WHERE key = ?", [key]) is Some(r) else {
    raise Refused(404, "unknown session \{match key { String(s) => s; k => k.stringify() }}")
  }
  r
}

///|
/// sessions.ts `widgetState`: what a widget in one of the session's messages holds, null when nothing or not JSON.
pub fn widget_state(db : @sql.Db, args : Json) -> Json raise {
  let key = args.value("key").unwrap_or(Json::null())
  ignore(session_row(db, key))
  let path = match args.value("path") {
    Some(String(p)) => Json::string(p)
    Some(Null) | None => Json::string("")
    Some(p) => p
  }
  let state = match one(db, "SELECT state FROM widget_states WHERE session = ? AND path = ?", [key, path]) {
    Some(r) =>
      match parsed(field(r, "state")) {
        Some(v) => to_json(v)
        None => Json::null()
      }
    None => Json::null()
  }
  { "state": state }
}

///|
/// Whether a key can be found by its bytes as written (runtime-source.ts `safe`): no NUL, no replacement character.
fn safe_key(s : String) -> Bool {
  !s.contains("\u{0}") && !s.contains("\u{fffd}")
}

///|
fn utf8_bytes(s : String) -> Array[Json] {
  let out : Array[Json] = []
  let n = s.length()
  let mut i = 0
  while i < n {
    let mut c = s.unsafe_charcode_at(i)
    i += 1
    if c >= 0xd800 && c <= 0xdbff && i < n && s.unsafe_charcode_at(i) >= 0xdc00 && s.unsafe_charcode_at(i) <= 0xdfff {
      c = 0x10000 + ((c - 0xd800) << 10) + (s.unsafe_charcode_at(i) - 0xdc00)
      i += 1
    }
    let push = (b : Int) => out.push(Json::number(b.to_double()))
    if c < 0x80 {
      push(c)
    } else if c < 0x800 {
      push(0xc0 | (c >> 6))
      push(0x80 | (c & 0x3f))
    } else if c < 0x10000 {
      push(0xe0 | (c >> 12))
      push(0x80 | ((c >> 6) & 0x3f))
      push(0x80 | (c & 0x3f))
    } else {
      push(0xf0 | (c >> 18))
      push(0x80 | ((c >> 12) & 0x3f))
      push(0x80 | ((c >> 6) & 0x3f))
      push(0x80 | (c & 0x3f))
    }
  }
  out
}

///|
fn source_of(id : Json, runtime : Json, profile : Json) -> @locate.Source {
  { id: match id { String(s) => s; _ => "" }, runtime: match runtime { String(s) => s; _ => "" }, profile: match profile { String(p) => Some(p); _ => None } }
}

///|
/// store.ts `runtimeSessionSources(...).find(id)`.
fn original_source(db : @sql.Db, key : Json, id : String) -> @locate.Source? raise {
  for r in db.all(
    "SELECT r.id, COALESCE(r.runtime, s.original_runtime, s.runtime) AS runtime, r.profile FROM sessions s CROSS JOIN runtime_sessions r ON r.session_key = s.key WHERE s.key = ? ORDER BY r.at, r.rowid",
    [key],
  ) {
    if field(r, "id") == Json::string(id) {
      return Some(source_of(field(r, "id"), field(r, "runtime"), field(r, "profile")))
    }
  }
  None
}

///|
/// runtime-source.ts `findRuntimeSource`: a session's runtime session by its id.
fn runtime_source(db : @sql.Db, key : Json, id : String) -> @locate.Source? raise {
  if !safe_key(id) {
    return original_source(db, key, id)
  }
  let bytes = utf8_bytes(id)
  let lower = bytes + [Json::number(0.0)]
  let upper = bytes + [Json::number(1.0)]
  guard one(
      db,
      "SELECT s.runtime_session_id AS current_id, s.runtime AS session_runtime, s.profile AS session_profile,\n      r.id AS source_id, COALESCE(r.runtime, s.original_runtime, s.runtime) AS source_runtime, r.profile AS source_profile,\n      EXISTS (SELECT 1 FROM runtime_sessions x WHERE x.session_key = s.key\n        AND x.id >= CAST(?3 AS TEXT) AND x.id < CAST(?4 AS TEXT)) AS ambiguous\n      FROM sessions s LEFT JOIN runtime_sessions r ON r.session_key = s.key AND r.id = ?2 WHERE s.key = ?1",
      [key, Json::string(id), Json::array(lower), Json::array(upper)],
    )
    is Some(row) else {
    return None
  }
  let current = field(row, "current_id")
  let ambiguous = !(field(row, "ambiguous") is (Number(0.0, ..) | Null))
  if ambiguous || (current is String(c) && !safe_key(c)) {
    return original_source(db, key, id)
  }
  if !(field(row, "source_id") is Null) {
    if field(row, "source_id") != Json::string(id) {
      return original_source(db, key, id)
    }
    return Some(source_of(field(row, "source_id"), field(row, "source_runtime"), field(row, "source_profile")))
  }
  if current == Json::string(id) {
    Some(source_of(Json::string(id), field(row, "session_runtime"), field(row, "session_profile")))
  } else {
    None
  }
}

///|
/// sessions.ts `transcriptFile`: where the session's current transcript is (found anywhere, as a history finds it),
/// null before it is written.
pub fn transcript_file(db : @sql.Db, host : @host.Host, data : String, sep : String, finder : @locate.Finder, args : Json) -> Json raise {
  let key = args.value("key").unwrap_or(Json::null())
  let row = session_row(db, key)
  guard field(row, "runtime_session_id") is String(current) else { return { "path": Json::null() } }
  guard runtime_source(db, key, current) is Some(source) else { return { "path": Json::null() } }
  let cwd = field(row, "cwd")
  let workspace = match field(row, "workspace") { String(w) => w; _ => "" }
  let places = match cwd {
    String(c) if c != workspace => [c, workspace]
    _ => [workspace]
  }
  let (paths, found) = finder.sources(data, profiles(host, data, sep), [source], places, anywhere=true)
  { "path": if found && paths.length() > 0 { Json::string(paths[paths.length() - 1].0) } else { Json::null() } }
}

///|
/// sessions.ts `configOf`'s profiles: each with an id and a home, a relative home under the data directory.
fn profiles(host : @host.Host, data : String, sep : String) -> Array[(String, String)] {
  let raw = match (try { Ok(host.shell_sync("fs.read", { "path": Json::string(@nodepath.join(sep, [data, "config.json"])), "strict": false })) } catch { e => Err(e) }) {
    Ok(String(text)) => @jsjson.parse(text) catch { _ => @jsjson.JValue::Obj([]) }
    _ => Obj([])
  }
  let out = []
  guard raw.get("profiles") is Some(Arr(ps)) else { return out }
  for p in ps {
    guard jfield(p, "id") is Some(Str(id)) && jfield(p, "home") is Some(Str(home)) else { continue }
    let home = @jsjson.text(home)
    let absolute = home.has_prefix("/") || (sep == "\\" && (home.has_prefix("\\") || (home.length() >= 2 && home.unsafe_charcode_at(1) == ':')))
    out.push((@jsjson.text(id), if absolute { home } else { @nodepath.join(sep, [data, home]) }))
  }
  out
}
