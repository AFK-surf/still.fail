// A session's usage as the usage counter and the usage page read it (station/src/store/usage.ts `usageTurns`,
// read/store.ts `usageCallsPage`): the turns a part of a transcript's calls were made in, and a page of its calls.
// The statements are the TypeScript's, as it makes them.

///|
/// store/usage.ts TURNS_FROM.
let turns_from_sql : String =
  #|SELECT IFNULL((SELECT MAX(started_at) FROM turns WHERE session_key = ?1 AND started_at <= ?2),
  #|  (SELECT MIN(started_at) FROM turns WHERE session_key = ?1)) AS at

///|
/// store/usage.ts TURNS_BETWEEN.
let turns_between_sql : String =
  #|SELECT id, kind, started_at, profile, person, thread FROM turns WHERE session_key = ?1 AND started_at >= ?2 AND started_at <= ?3 ORDER BY started_at

///|
/// store/usage.ts TAKEN_SINCE.
let taken_since_sql : String =
  #|SELECT d.delivered_at AS at, CASE WHEN t.surface = ?2 THEN e.author ELSE 'slack:' || ts.connect || ':' || e.author END AS who, e.thread AS thread
  #|  FROM deliveries d JOIN entries e ON e.thread = d.thread AND e.n = d.n JOIN threads t ON t.id = d.thread
  #|  JOIN thread_sessions ts ON ts.thread = d.thread AND ts.session = d.session
  #|  WHERE d.session = ?1 AND d.delivered_at IS NOT NULL AND d.delivered_at >= ?3 AND e.author_kind = 'person' ORDER BY d.delivered_at

///|
/// read/store.ts USAGE_CALLS_SAME.
let usage_calls_same_sql : String =
  #|SELECT CAST(rowid AS TEXT) AS seq, id, CAST(at AS TEXT) AS at, session, turn, thread, person, profile, runtime, model, subagent, fast,
  #|  input, cache_read, cache_write, cache_write_long, output, calls, context, context_window FROM usage INDEXED BY usage_session WHERE session = ?1 AND at = ?2 AND rowid < ?3 ORDER BY rowid DESC LIMIT ?4

///|
/// read/store.ts USAGE_CALLS_EARLIER.
let usage_calls_earlier_sql : String =
  #|SELECT CAST(rowid AS TEXT) AS seq, id, CAST(at AS TEXT) AS at, session, turn, thread, person, profile, runtime, model, subagent, fast,
  #|  input, cache_read, cache_write, cache_write_long, output, calls, context, context_window FROM usage INDEXED BY usage_session WHERE session = ?1 AND at >= ?2 AND at < ?3 ORDER BY usage.at DESC, rowid DESC LIMIT ?4

///|
/// Number.MIN_SAFE_INTEGER and MAX_SAFE_INTEGER.
const MIN_SAFE : Double = -9007199254740991.0

///|
const MAX_SAFE : Double = 9007199254740991.0

///|
/// `a ?? b` of two values a row has.
fn or_else(a : Json, b : Json) -> Json {
  if a is Null {
    b
  } else {
    a
  }
}

///|
/// Number(v) of an argument as JSON gives it (a string of digits, a number), NaN otherwise.
fn arg_number(v : Json?) -> Json {
  match v {
    Some(Number(_, ..) as n) => n
    Some(String(s)) =>
      parsed_number(s)
    Some(Null) => Json::number(0.0)
    Some(True) => Json::number(1.0)
    Some(False) => Json::number(0.0)
    _ => Json::number(nan())
  }
}

///|
fn nan() -> Double {
  0.0 / 0.0
}

///|
/// Number(text) of a string JSON reads as a number, NaN otherwise.
fn parsed_number(s : String) -> Json {
  let v : Json = @json.parse(s) catch { _ => return Json::number(nan()) }
  match v {
    Number(_, ..) => v
    _ => Json::number(nan())
  }
}

///|
fn text_arg(v : Json?) -> String {
  match v {
    Some(String(s)) => s
    Some(Number(n, ..)) if n == n.floor() && n.abs() < 1.0e21 => n.to_int64().to_string()
    Some(Null) => "null"
    Some(True) => "true"
    Some(False) => "false"
    None => "undefined"
    Some(v) => v.stringify()
  }
}

///|
/// store/usage.ts `usageTurns`: the turns of a session calls made from `from` until `until` were made in, oldest first,
/// each with whom it worked for.
pub fn usage_turns(db : @sql.Db, args : Json) -> Json raise {
  let session = Json::string(text_arg(args.value("session")))
  let from = arg_number(args.value("from"))
  let until = arg_number(args.value("until"))
  let (creator, profile) = match one(db, "SELECT created_by, profile FROM sessions WHERE key = ?", [session]) {
    Some(r) => (field(r, "created_by"), field(r, "profile"))
    None => (Json::null(), Json::string(""))
  }
  let home = match one(
      db, "SELECT id FROM threads WHERE home = ?1 UNION ALL SELECT thread FROM (SELECT thread FROM thread_sessions WHERE session = ?1 ORDER BY joined_at LIMIT 1) LIMIT 1",
      [session],
    ) {
    Some(r) => field(r, "id")
    None => Json::null()
  }
  let begins = match one(db, turns_from_sql, [session, from]) {
    Some(r) => field(r, "at")
    None => Json::null()
  }
  let turns = match begins {
    Number(b, ..) => {
      let upto = match until {
        Number(u, ..) if u > b => until
        Number(u, ..) if u.is_nan() => until
        _ => begins
      }
      db.all(turns_between_sql, [session, begins, upto])
    }
    _ => []
  }
  let delivered : Array[(Double, Json, Json)] = if turns.iter().any(t => field(t, "person") is Null) {
    db.all(taken_since_sql, [session, Json::string("ember"), begins]).map(r => (match field(r, "at") { Number(a, ..) => a; _ => 0.0 }, field(r, "who"), field(r, "thread")))
  } else {
    []
  }
  let out : Array[(Json, Json, Json, Json, Json, Json)] = []
  let mut next = 0
  for n, t in turns {
    let started = match field(t, "started_at") { Number(s, ..) => s; _ => 0.0 }
    let end = if n + 1 < turns.length() {
      match field(turns[n + 1], "started_at") { Number(s, ..) => s; _ => 0.0 }
    } else {
      MAX_SAFE
    }
    while next < delivered.length() && delivered[next].0 < started {
      next += 1
    }
    let first = if field(t, "kind") == Json::string("input") && next < delivered.length() && delivered[next].0 < end {
      Some(delivered[next])
    } else {
      None
    }
    let previous = if out.length() > 0 { Some(out[out.length() - 1]) } else { None }
    let person = or_else(
      field(t, "person"),
      match first {
        Some(f) => or_else(f.1, match previous { Some(p) => or_else(p.3, creator); None => creator })
        None => match previous { Some(p) => or_else(p.3, creator); None => creator }
      },
    )
    let thread = or_else(
      field(t, "thread"),
      match first {
        Some(f) => or_else(f.2, match previous { Some(p) => or_else(p.4, home); None => home })
        None => match previous { Some(p) => or_else(p.4, home); None => home }
      },
    )
    out.push((field(t, "id"), field(t, "started_at"), field(t, "id"), person, thread, or_else(field(t, "profile"), profile)))
  }
  if out.length() == 0 {
    out.push((Json::string(""), Json::number(MIN_SAFE), Json::null(), creator, home, profile))
  }
  Json::array(
    out.map(o => ({ "id": o.0, "startedAt": o.1, "of": { "turn": o.2, "person": o.3, "thread": o.4, "profile": o.5 } } : Json)),
  )
}

///|
/// BigInt(text): an integer as written, refused otherwise.
fn big_of(v : Json?) -> Int64 raise {
  let s = @jscase.trim(text_arg(v))
  if s == "" {
    return 0L
  }
  let (neg, digits) = if s.has_prefix("-") {
    (true, s.view(start_offset=1).to_owned())
  } else if s.has_prefix("+") {
    (false, s.view(start_offset=1).to_owned())
  } else {
    (false, s)
  }
  guard digits != "" && digits.iter().all(c => c >= '0' && c <= '9') else { raise Failure("Cannot convert \{s} to a BigInt") }
  // Counted below zero, where an i64 reaches one further; beyond one the statements would not take it either.
  let mut n = 0L
  for c in digits {
    let d = (c.to_int() - '0'.to_int()).to_int64()
    guard n >= (-9223372036854775807L - 1L + d) / 10L else { raise Failure("\{s} is beyond what the statements take") }
    n = n * 10L - d
  }
  if neg {
    n
  } else {
    guard n != -9223372036854775807L - 1L else { raise Failure("\{s} is beyond what the statements take") }
    -n
  }
}

///|
/// An i64 as a statement's integer (the shell takes it as JSON: the extremes as the number nearest them, which compare
/// the same with every key between them).
fn big_param(n : Int64) -> Json {
  Json::number(n.to_double())
}

///|
fn sees_ws(viewer : Json, ws : Json) -> Bool {
  let workspace = viewer.value("workspace").unwrap_or(Json::null())
  ws == workspace || (ws is Null && !(viewer.value("home") is Some(False)))
}

///|
/// read/store.ts `usageCallsPage`: a session's calls from `from` until `to`, latest first, before `before` (its time and
/// sequence), at most `limit`; none for a viewer of another workspace.
pub fn usage_calls(db : @sql.Db, args : Json) -> Json raise {
  let session = Json::string(text_arg(args.value("session")))
  let from = big_of(args.value("from"))
  let to = big_of(args.value("to"))
  let before_at = big_of(args.value("beforeAt"))
  let before_seq = big_of(args.value("beforeSeq"))
  let limit = match args.value("limit") {
    Some(Number(n, ..)) if n == n.floor() && n.abs() <= MAX_SAFE => n
    _ => 0.0
  }
  let viewer = match args.value("viewer") {
    None | Some(Null) => None
    Some(v) => Some(v)
  }
  if viewer is Some(v) {
    match one(db, "SELECT ws FROM sessions WHERE key = ?", [session]) {
      Some(r) if sees_ws(v, field(r, "ws")) => ()
      _ => return { "rows": [], "next": Json::null() }
    }
  }
  let size = if limit < 1.0 { 1 } else if limit > 200.0 { 200 } else { limit.to_int() }
  let page : Array[Map[String, Json]] = []
  if before_at >= from && before_at < to {
    page.append(db.all(usage_calls_same_sql, [session, big_param(before_at), big_param(before_seq), Json::number(size.to_double())]))
  }
  let end = if before_at < to { before_at } else { to }
  if page.length() < size && end > from {
    page.append(db.all(usage_calls_earlier_sql, [session, big_param(from), big_param(end), Json::number((size - page.length()).to_double())]))
  }
  let num = (v : Json) => match v {
    Number(_, ..) => v
    String(s) =>
      parsed_number(s)
    Null => Json::number(0.0)
    _ => Json::number(nan())
  }
  let rows = page.map(r => ({
    "id": field(r, "id"),
    "at": num(field(r, "at")),
    "session": field(r, "session"),
    "turn": field(r, "turn"),
    "thread": field(r, "thread"),
    "person": field(r, "person"),
    "profile": field(r, "profile"),
    "runtime": field(r, "runtime"),
    "model": field(r, "model"),
    "subagent": Json::boolean(field(r, "subagent") != Json::number(0.0)),
    "fast": Json::boolean(field(r, "fast") != Json::number(0.0)),
    "input": num(field(r, "input")),
    "cacheRead": num(field(r, "cache_read")),
    "cacheWrite": num(field(r, "cache_write")),
    "cacheWriteLong": num(field(r, "cache_write_long")),
    "output": num(field(r, "output")),
    "calls": num(field(r, "calls")),
    "context": field(r, "context"),
    "contextWindow": field(r, "context_window"),
  } : Json))
  let next = if page.length() == 0 || page.length() < size {
    Json::null()
  } else {
    let last = page[page.length() - 1]
    { "at": field(last, "at"), "seq": field(last, "seq") }
  }
  { "rows": Json::array(rows), "next": next }
}
