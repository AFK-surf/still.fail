// Messages as read/store.ts reads them merged with their latest edit (the merged view once its lookup is ready, else the
// message and its latest edit found in a bounded tail: `mergedWithBoundedEdit`), made as rows.ts `toMessage` and
// `letterMessage` make a MessageRow (its JSON columns read as JSON.parse reads them, the attachments and quotes kept as
// serde would keep them, a list with a wrong one none), and the reads made of them: a chat's card still waiting
// (`reviewPendingCard`), the question a need names (`stateQuestion`), a session's undelivered messages and letters
// (`pendingDeliveries`).

///|
let legacy_edits_pending : String = "legacy edit lookup pending"

///|
fn jfield(v : @jsjson.JValue, k : String) -> @jsjson.JValue? {
  match v {
    Obj(_) => v.get(k)
    _ => None
  }
}

///|
fn jstr(v : @jsjson.JValue?) -> String? {
  match v {
    Some(Str(s)) => Some(@jsjson.text(s))
    _ => None
  }
}

///|
fn is_u64(v : @jsjson.JValue?) -> Bool {
  v is Some(Num(n)) && n == n.floor() && n >= 0.0 && !n.is_inf()
}

///|
fn absent(v : @jsjson.JValue?) -> Bool {
  v is (None | Some(Null))
}

///|
/// rows.ts `attachment`: its fields in their order, unknown ones dropped; a wrong one raises.
fn attachment(a : @jsjson.JValue) -> Json raise {
  guard a is Obj(_) && jstr(jfield(a, "name")) is Some(name) && jstr(jfield(a, "path")) is Some(path) && is_u64(jfield(a, "size")) else {
    fail("attachment")
  }
  let u32 = (v : @jsjson.JValue?) => absent(v) || (is_u64(v) && (v is Some(Num(n)) && n <= 4294967295.0))
  let str = (v : @jsjson.JValue?) => absent(v) || v is Some(Str(_))
  if !u32(jfield(a, "width")) || !u32(jfield(a, "height")) || !str(jfield(a, "thumbhash")) || !(absent(jfield(a, "duration")) || is_u64(jfield(a, "duration"))) || !u32(jfield(a, "frames")) {
    fail("attachment")
  }
  let out : Map[String, Json] = { "name": Json::string(name), "path": Json::string(path), "size": to_json(jfield(a, "size").unwrap()) }
  for k in ["width", "height", "thumbhash", "duration", "frames"] {
    if !absent(jfield(a, k)) {
      out[k] = to_json(jfield(a, k).unwrap())
    }
  }
  Json::object(out)
}

///|
/// rows.ts `quote`.
fn quote(q : @jsjson.JValue) -> Json raise {
  guard q is Obj(_) && jstr(jfield(q, "author")) is Some(author) && jstr(jfield(q, "text")) is Some(text) && jstr(jfield(q, "comment")) is Some(comment) else {
    fail("quote")
  }
  let str = (v : @jsjson.JValue?) => absent(v) || v is Some(Str(_))
  if !str(jfield(q, "ts")) || !str(jfield(q, "role")) || !str(jfield(q, "file")) {
    fail("quote")
  }
  let out : Map[String, Json] = { "author": Json::string(author), "text": Json::string(text), "comment": Json::string(comment) }
  for k in ["ts", "role", "file"] {
    if !absent(jfield(q, k)) {
      out[k] = to_json(jfield(q, k).unwrap())
    }
  }
  Json::object(out)
}

///|
/// rows.ts `fromJsonList`: a stored list read with `read`, none when it does not read or one of it is wrong.
fn json_list(v : Json, read : (@jsjson.JValue) -> Json raise) -> Json {
  guard parsed(v) is Some(Arr(items)) else { return Json::array([]) }
  let out : Array[Json] = []
  for item in items {
    let one = read(item) catch { _ => return Json::array([]) }
    out.push(one)
  }
  Json::array(out)
}

///|
/// rows.ts `letterOf`, spread as `withLetter` spreads it.
fn with_letter(out : Map[String, Json], v : Json) -> Unit {
  guard parsed(v) is Some(l) && l is (Obj(_) | Arr(_)) else { return }
  let way = jstr(jfield(l, "way"))
  guard way is Some("in" | "out") && jstr(jfield(l, "title")) is Some(title) else { return }
  out["letter"] = {
    "way": Json::string(way.unwrap()),
    "title": Json::string(title),
    "link": match jstr(jfield(l, "link")) { Some(s) => Json::string(s); None => Json::null() },
  }
}

///|
/// rows.ts `authorKind`.
fn author_kind(v : Json) -> Json {
  match v {
    String("agent") => Json::string("agent")
    String("ember" | "stillfail") => Json::string("ember")
    _ => Json::string("person")
  }
}

///|
fn absent_null(v : Json) -> Json {
  v
}

///|
/// rows.ts `toMessage`: a merged row as a MessageRow.
pub fn to_message(r : Map[String, Json]) -> Json {
  let out : Map[String, Json] = {
    "agentIdentity": match parsed(field(r, "agent_identity")) { Some(v) => to_json(v); None => Json::null() },
    "thread": field(r, "thread"),
    "n": field(r, "n"),
    "ts": match field(r, "ts") { Null => Json::string(""); t => t },
    "authorKind": author_kind(field(r, "author_kind")),
    "author": field(r, "author"),
    "text": match field(r, "text") { Null => Json::string(""); t => t },
    "attachments": json_list(field(r, "attachments"), attachment),
    "quotes": json_list(field(r, "quotes"), quote),
    "declared": absent_null(field(r, "declared")),
    "client": field(r, "client"),
    "createdAt": field(r, "created_at"),
    "editedAt": field(r, "edited_at"),
  }
  with_letter(out, field(r, "letter"))
  Json::object(out)
}

///|
/// rows.ts `letterMessage`: a letter of a chat's own log as a message handed to a session (`apart`).
fn letter_message(r : Map[String, Json]) -> Json {
  let out : Map[String, Json] = {
    "agentIdentity": Json::null(),
    "thread": field(r, "thread"),
    "n": field(r, "n"),
    "ts": field(r, "ts"),
    "authorKind": author_kind(field(r, "author_kind")),
    "author": field(r, "author"),
    "text": field(r, "text"),
    "attachments": json_list(field(r, "attachments"), attachment),
    "quotes": Json::array([]),
    "declared": Json::null(),
    "client": Json::null(),
    "createdAt": field(r, "at"),
    "editedAt": Json::null(),
  }
  with_letter(out, field(r, "letter"))
  out["apart"] = true
  Json::object(out)
}

///|
fn edits_pending() -> Refused {
  Refused(503, legacy_edits_pending)
}

///|
/// read/store.ts `mergedWithBoundedEdit`: a message with its latest edit, found in a bounded tail.
fn merged_bounded(db : @sql.Db, thread : Json, n : Json) -> Json? raise {
  let edit = @legacy.bounded_edit_key(db, thread, n) catch {
    @legacy.Unprepared(_) => raise edits_pending()
    e => raise e
  }
  let row = one(
    db,
    "SELECT m.thread,m.n,m.ts,m.author_kind,m.author,\n    CASE WHEN e.n IS NULL THEN m.text ELSE e.text END AS text,\n    CASE WHEN e.n IS NULL THEN m.attachments ELSE e.attachments END AS attachments,\n    CASE WHEN e.n IS NULL THEN m.quotes ELSE e.quotes END AS quotes,\n    m.declared,m.client,m.agent_identity,m.at AS created_at,e.at AS edited_at,m.letter\n  FROM entries m LEFT JOIN entries e ON e.thread=m.thread AND e.n=CAST(?3 AS INTEGER)\n  WHERE m.thread=?1 AND m.n=CAST(?2 AS INTEGER) AND m.kind='message'",
    [thread, n, match edit { Some(k) => Json::string(k); None => Json::null() }],
  )
  match row {
    Some(r) => Some(to_message(r))
    None => None
  }
}

///|
/// A message merged: by the view once its lookup is ready, else bounded.
fn merged(db : @sql.Db, thread : Json, n : Json) -> Json? raise {
  if !@legacy.merged_read_ready(db) {
    return merged_bounded(db, thread, n)
  }
  match one(db, "SELECT * FROM merged WHERE thread = ? AND n = ?", [thread, n]) {
    Some(m) => Some(to_message(m))
    None => None
  }
}

///|
/// read/store.ts `pendingCard` (`reviewPendingCard`): the chat's card still waiting, `[message, card]`.
pub fn review_pending_card(db : @sql.Db, args : Json) -> Json raise {
  let thread = args.value("thread").unwrap_or(Json::null())
  db.exec("SAVEPOINT pending_card_read")
  defer (db.exec("RELEASE pending_card_read") catch { _ => () })
  if !@cards.ready(db, thread) {
    if !has_cards(db, thread) {
      return Json::null()
    }
    raise pending(thread)
  }
  guard one(db, "SELECT CAST(n AS TEXT) AS n FROM card_posts WHERE thread=? ORDER BY card_posts.n DESC LIMIT 1", [thread]) is Some(asked) else {
    return Json::null()
  }
  card_at(db, thread, number_of(field(asked, "n")))
}

///|
/// read/store.ts `cardAt`.
fn card_at(db : @sql.Db, thread : Json, n : Json) -> Json raise {
  db.exec("SAVEPOINT card_at_read")
  defer (db.exec("RELEASE card_at_read") catch { _ => () })
  guard one(db, "SELECT card, options FROM entries WHERE thread = ? AND n = ?", [thread, n]) is Some(asked) else {
    return Json::null()
  }
  let answered = one(db, "SELECT 1 AS x FROM entries WHERE thread = ? AND kind = 'message' AND author_kind = 'person' AND n > ? LIMIT 1", [thread, n]) is Some(_)
  let closed = one(db, "SELECT 1 AS x FROM closed_cards WHERE thread = ? AND n = ?", [thread, n]) is Some(_)
  if answered || closed {
    return Json::null()
  }
  guard card_of(field(asked, "card"), field(asked, "options")) is Some(card) else { return Json::null() }
  match merged(db, thread, n) {
    Some(m) => Json::array([m, card])
    None => Json::null()
  }
}

///|
/// JavaScript's `String.prototype.trim() === ""`.
fn blank(v : Json) -> Bool {
  match v {
    String(s) => s.iter().all(c => is_js_space(c.to_int()))
    _ => true
  }
}

///|
fn is_js_space(c : Int) -> Bool {
  match c {
    0x09 | 0x0a | 0x0b | 0x0c | 0x0d | 0x20 | 0xa0 | 0x1680 | 0x2028 | 0x2029 | 0x202f | 0x205f | 0x3000 | 0xfeff => true
    _ => c >= 0x2000 && c <= 0x200a
  }
}

///|
/// read/store.ts `stateQuestion`: the question a need names (`ts` in one of `threads`), and whether it is still asked.
pub fn state_question(db : @sql.Db, args : Json) -> Json raise {
  let key = args.value("key").unwrap_or(Json::null())
  let ts = args.value("ts").unwrap_or(Json::null())
  let threads = match args.value("threads") {
    Some(Array(ts)) => ts
    _ => []
  }
  db.exec("SAVEPOINT state_question_read")
  defer (db.exec("RELEASE state_question_read") catch { _ => () })
  for thread in threads {
    guard one(db, "SELECT CAST(n AS TEXT) AS n, card, options FROM entries WHERE thread = ? AND ts = ? AND kind = 'message'", [thread, ts]) is Some(entry) else {
      continue
    }
    if @legacy.merged_needs_repair(db) {
      raise edits_pending()
    }
    let n = number_of(field(entry, "n"))
    guard merged(db, thread, n) is Some(m) else { continue }
    guard m is Object(mm) else { continue }
    if field(mm, "authorKind") != Json::string("agent") || field(mm, "author") != key || blank(field(mm, "text")) {
      return { "kind": "invalid" }
    }
    let carded = !(field(entry, "card") is Null) || !(field(entry, "options") is Null)
    let answered = if carded {
      pending_card_number(db, thread) != field(mm, "n")
    } else {
      one(db, "SELECT 1 AS x FROM entries WHERE thread = ? AND kind = 'message' AND author_kind = 'person' AND n > ? LIMIT 1", [thread, field(mm, "n")]) is Some(_)
    }
    return if answered {
      { "kind": "answered" }
    } else {
      { "kind": "found", "about": Json::array([field(mm, "thread"), field(mm, "n"), field(mm, "ts")]) }
    }
  }
  { "kind": "missing" }
}

///|
/// read/store.ts `pendingDeliveries`: a session's undelivered messages and letters in the order given to its runtime.
pub fn pending_deliveries(db : @sql.Db, args : Json) -> Json raise {
  let session = args.value("key").unwrap_or(Json::null())
  db.exec("SAVEPOINT pending_delivery_read")
  defer (db.exec("RELEASE pending_delivery_read") catch { _ => () })
  let place = (r : Map[String, Json], message : Json) => ({
    "message": message,
    "surface": field(r, "surface"),
    "channel": field(r, "channel"),
    "threadTs": field(r, "thread_ts"),
    "connect": field(r, "connect"),
  } : Json)
  let said : Array[(Json, Double)] = []
  if @legacy.merged_read_ready(db) {
    for r in db.all(
      "SELECT m.*, t.surface, t.channel, t.thread_ts, ts.connect FROM deliveries d\n        JOIN merged m ON m.thread = d.thread AND m.n = d.n JOIN threads t ON t.id = d.thread\n        JOIN thread_sessions ts ON ts.thread = t.id AND ts.session = d.session\n        WHERE d.session = ? AND d.delivered_at IS NULL ORDER BY d.rowid",
      [session],
    ) {
      said.push((place(r, to_message(r)), created(field(r, "created_at"))))
    }
  } else {
    for r in db.all(
      "SELECT d.thread, CAST(d.n AS TEXT) AS n, t.surface, t.channel, t.thread_ts, ts.connect FROM deliveries d\n        JOIN entries e ON e.thread = d.thread AND e.n = d.n AND e.kind = 'message' JOIN threads t ON t.id = d.thread\n        JOIN thread_sessions ts ON ts.thread = t.id AND ts.session = d.session\n        WHERE d.session = ? AND d.delivered_at IS NULL ORDER BY d.rowid",
      [session],
    ) {
      if merged_bounded(db, field(r, "thread"), field(r, "n")) is Some(m) {
        let at = match m {
          Object(mm) => created(field(mm, "createdAt"))
          _ => 0.0
        }
        said.push((place(r, m), at))
      }
    }
  }
  let letters : Array[(Json, Double)] = []
  for r in db.all(
    "SELECT l.*, t.surface, t.channel, t.thread_ts, ts.connect FROM letter_deliveries d\n      JOIN letters l ON l.thread = d.thread AND l.n = d.n JOIN threads t ON t.id = d.thread\n      JOIN thread_sessions ts ON ts.thread = t.id AND ts.session = d.session\n      WHERE d.session = ? AND d.delivered_at IS NULL ORDER BY d.rowid",
    [session],
  ) {
    letters.push((place(r, letter_message(r)), created(field(r, "at"))))
  }
  let out : Array[Json] = []
  let mut i = 0
  let mut j = 0
  while i < said.length() || j < letters.length() {
    if j >= letters.length() || (i < said.length() && said[i].1 <= letters[j].1) {
      out.push(said[i].0)
      i += 1
    } else {
      out.push(letters[j].0)
      j += 1
    }
  }
  Json::array(out)
}

///|
fn created(v : Json) -> Double {
  match v {
    Number(n, ..) => n
    _ => 0.0 / 0.0
  }
}
