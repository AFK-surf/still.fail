// Pages of a chat's messages (station/src/read/store.ts `messagesBefore`, `openedChatSaid`, `chatHistoryMessages`): a
// page's keys found by the said index and the letters' (`boundedMessagePageKeys`), by a short source tail while an old
// store's lookups are prepared (`unpreparedMessagePageKeys`), refused while neither can prove the page; then each read
// merged.

///|
let i64_max : String = "9223372036854775807"

///|
let page_letter_pending : String = "page letter lookup pending: "

///|
let said_pending : String = "sidebar said state pending: "

///|
let legacy_said_pending : String = "legacy said lookup pending"

///|
fn exists_in(db : @sql.Db, kind : String, name : String) -> Bool raise {
  one(db, "SELECT 1 AS x FROM sqlite_master WHERE type = ? AND name = ?", [Json::string(kind), Json::string(name)]) is Some(_)
}

///|
/// legacy-said-build.ts `hasLegacySaid`.
fn has_legacy_said(db : @sql.Db) -> Bool raise {
  if !exists_in(db, "view", "legacy_said") {
    return false
  }
  if !exists_in(db, "table", "legacy_said_meta") {
    fail("legacy said view has no metadata")
  }
  guard one(db, "SELECT version, scanned FROM legacy_said_meta WHERE id=1", []) is Some(m) &&
    m.get("version") is Some(Number(1.0, ..)) &&
    m.get("scanned") is Some(Number(0.0, ..) | Number(1.0, ..)) else {
    fail("legacy said view has an unsupported version")
  }
  true
}

///|
/// legacy-said-build.ts `legacySaidPageState`: (preparing, needs a drain).
fn said_page_state(db : @sql.Db, thread : Json) -> (Bool, Bool) raise {
  guard one(
      db,
      "SELECT m.version,m.scanned,CASE WHEN m.scanned=1 THEN EXISTS (\n    SELECT 1 FROM legacy_said_dirty WHERE thread=?1 LIMIT 1 OFFSET 64) ELSE 0 END AS needs_drain\n  FROM legacy_said_meta m WHERE m.id=1",
      [thread],
    )
    is Some(row) &&
    row.get("version") is Some(Number(1.0, ..)) &&
    row.get("scanned") is Some(Number(0.0, ..) | Number(1.0, ..)) else {
    fail("legacy said lookup metadata is missing or invalid")
  }
  (row.get("scanned") is Some(Number(0.0, ..)), !(row.get("needs_drain") is Some(Number(0.0, ..))))
}

///|
fn text_keys(rows : Array[Map[String, Json]]) -> Array[String] {
  rows.filter_map(r => if field(r, "n") is String(s) { Some(s) } else { None })
}

///|
/// Integers written as text compared as integers (the BigInt order).
fn compare_int_text(a : String, b : String) -> Int {
  let neg_a = a.has_prefix("-")
  let neg_b = b.has_prefix("-")
  if neg_a != neg_b {
    return if neg_a { -1 } else { 1 }
  }
  let c = if a.length() != b.length() {
    a.length() - b.length()
  } else if a < b {
    -1
  } else if a > b {
    1
  } else {
    0
  }
  if neg_a {
    -c
  } else {
    c
  }
}

///|
fn descending(keys : Array[String]) -> Array[String] {
  stable_sort(keys, (a, b) => compare_int_text(b, a))
}

///|
fn take(keys : Array[String], limit : Int) -> Array[String] {
  if keys.length() > limit {
    keys.view(end=limit).iter().collect()
  } else {
    keys
  }
}

///|
fn int_json(n : Int) -> Json {
  Json::number(n.to_double())
}

///|
/// store.ts `boundedMessagePageKeys`.
fn bounded_page_keys(db : @sql.Db, thread : Json, before : Json, limit : Int, legacy : Bool) -> Array[String] raise {
  let token = @letters.ready_token(db, thread)
  if token is None && !exists_in(db, "index", "entries_letters") {
    let cap = limit + 64
    let tail = db.all("SELECT CAST(e.n AS TEXT) AS n,e.kind FROM entries e\n  WHERE e.thread=?1 AND e.n<?2 ORDER BY e.n DESC LIMIT ?3", [thread, before, int_json(cap)])
    let keys = take(text_keys(tail.filter(r => field(r, "kind") == Json::string("message"))), limit)
    if keys.length() < limit && tail.length() == cap {
      raise Refused(503, page_letter_pending + Json::array([thread]).stringify())
    }
    return keys
  }
  let ordinary = text_keys(
    db.all(
      if legacy {
        "SELECT CAST(p.n AS TEXT) AS n FROM (\n  SELECT n FROM legacy_said WHERE thread=?1 AND n<?2 ORDER BY n DESC LIMIT ?3) p ORDER BY p.n DESC"
      } else {
        "SELECT CAST(p.n AS TEXT) AS n FROM (\n  SELECT n FROM entries INDEXED BY entries_said WHERE thread=?1 AND n<?2 AND kind='message' AND letter IS NULL\n  ORDER BY n DESC LIMIT ?3) p ORDER BY p.n DESC"
      },
      [thread, before, int_json(limit)],
    ),
  )
  if token is Some(t) {
    let letters = text_keys(
      db.all(
        "SELECT CAST(p.n AS TEXT) AS n FROM (\n    SELECT b.n FROM page_letter_rows b WHERE b.thread=?1 AND b.token=?2 AND b.n<CAST(?3 AS INTEGER)\n      AND NOT EXISTS (SELECT 1 FROM page_letter_dirty d WHERE d.thread=b.thread AND d.token=b.token AND d.n=b.n)\n    UNION ALL\n    SELECT e.n FROM page_letter_dirty d CROSS JOIN entries e ON e.thread=d.thread AND e.n=d.n\n      WHERE d.thread=?1 AND d.token=?2 AND d.n<CAST(?3 AS INTEGER) AND e.kind='message' AND e.letter IS NOT NULL\n    ORDER BY n DESC LIMIT ?4\n  ) p ORDER BY p.n DESC",
        [thread, Json::string(t), before, int_json(limit)],
      ),
    )
    return take(descending(ordinary + letters), limit)
  }
  let cap = limit + 64
  let candidates = db.all(
    "SELECT CAST(e.n AS TEXT) AS n,e.kind FROM entries e INDEXED BY entries_letters\n  WHERE e.thread=?1 AND e.n<?2 AND e.letter IS NOT NULL ORDER BY e.n DESC LIMIT ?3",
    [thread, before, int_json(cap)],
  )
  let floor = if candidates.length() == cap {
    match field(candidates[candidates.length() - 1], "n") { String(s) => Some(s); _ => None }
  } else {
    None
  }
  let letters = text_keys(candidates.filter(r => field(r, "kind") == Json::string("message")))
  let known = match floor {
    Some(f) => ordinary.filter(k => compare_int_text(k, f) >= 0)
    None => ordinary
  }
  let keys = descending(known + letters)
  if keys.length() < limit && floor is Some(_) {
    raise Refused(503, page_letter_pending + Json::array([thread]).stringify())
  }
  take(keys, limit)
}

///|
/// store.ts `unpreparedMessagePageKeys`.
fn unprepared_page_keys(db : @sql.Db, thread : Json, before : Json, limit : Int, preparing : Bool, huge : Bool) -> Array[String] raise {
  let refuse = () => if preparing {
    Refused(503, legacy_said_pending)
  } else {
    Refused(503, said_pending + Json::array([thread]).stringify())
  }
  if huge {
    raise refuse()
  }
  if limit == 0 {
    return []
  }
  let cap = limit + 64
  let tail = db.all("SELECT CAST(e.n AS TEXT) AS n,e.kind FROM entries e\n  WHERE e.thread=?1 AND e.n<?2 ORDER BY e.n DESC LIMIT ?3", [thread, before, int_json(cap)])
  let keys = take(text_keys(tail.filter(r => field(r, "kind") == Json::string("message"))), limit)
  if keys.length() < limit && tail.length() == cap {
    raise refuse()
  }
  keys
}

///|
/// The messages of keys, merged, newest first as the keys are.
fn merged_keys(db : @sql.Db, thread : Json, keys : Array[String]) -> Array[Json] raise {
  if @legacy.merged_read_ready(db) {
    return db
      .all("SELECT * FROM merged WHERE thread=?1 AND n IN\n  (SELECT CAST(value AS INTEGER) FROM json_each(?2)) ORDER BY n DESC", [
        thread,
        Json::string(Json::array(keys.map(Json::string(_))).stringify()),
      ])
      .map(to_message)
  }
  keys.filter_map(k => merged_bounded(db, thread, Json::string(k)))
}

///|
/// A JavaScript number as the limit a page is asked for: (it, whether it is a safe non-negative integer of a page).
fn page_limit(v : Json?) -> (Int, Bool) {
  match v {
    Some(Number(n, ..)) if n == n.floor() && n >= 0.0 && n <= 9007199254740927.0 => (if n > 2147483647.0 { 2147483647 } else { n.to_int() }, true)
    Some(Number(n, ..)) => (if n.is_nan() { 0 } else if n < 0.0 { -1 } else { 2147483647 }, false)
    _ => (0, false)
  }
}

///|
/// store.ts `messagesBefore`: the latest `limit` messages before `before` (the latest of all without it), oldest first.
fn messages_before(db : @sql.Db, thread : Json, before : Json, limit_v : Json?) -> Json raise {
  let (limit, safe) = page_limit(limit_v)
  db.exec("SAVEPOINT messages_before_read")
  defer (db.exec("RELEASE messages_before_read") catch { _ => () })
  let legacy = has_legacy_said(db)
  if legacy {
    let (preparing, drain) = said_page_state(db, thread)
    if preparing || drain {
      let keys = unprepared_page_keys(db, thread, before, limit, preparing, !safe)
      return Json::array(merged_keys(db, thread, keys).rev())
    }
  }
  if !safe {
    // (every message: SQLite's negative limit, as the TypeScript asks it)
    let lim = match limit_v { Some(Number(n, ..)) => Json::number(n); _ => Json::null() }
    let keys_sql = if legacy {
      "\n  SELECT n FROM legacy_said WHERE thread = ?1 AND n < ?2\n  UNION ALL\n  SELECT n FROM entries WHERE thread = ?1 AND n < ?2 AND kind = 'message' AND letter IS NOT NULL\n  ORDER BY n DESC LIMIT ?3"
    } else {
      "\n  SELECT n FROM entries INDEXED BY entries_said\n    WHERE thread = ?1 AND n < ?2 AND kind = 'message' AND letter IS NULL\n  UNION ALL\n  SELECT n FROM entries\n    WHERE thread = ?1 AND n < ?2 AND kind = 'message' AND letter IS NOT NULL\n  ORDER BY n DESC LIMIT ?3"
    }
    if @legacy.merged_read_ready(db) {
      return Json::array(db.all("SELECT * FROM merged WHERE thread = ?1 AND n IN (\{keys_sql}) ORDER BY n DESC", [thread, before, lim]).map(to_message).rev())
    }
    let page = text_keys(db.all("SELECT CAST(p.n AS TEXT) AS n FROM (\{keys_sql}) p ORDER BY p.n DESC", [thread, before, lim]))
    return Json::array(page.filter_map(k => merged_bounded(db, thread, Json::string(k))).rev())
  }
  if limit == 0 {
    return Json::array([])
  }
  let page = bounded_page_keys(db, thread, before, limit, legacy)
  if page.length() == 0 {
    return Json::array([])
  }
  Json::array(merged_keys(db, thread, page).rev())
}

///|
/// `latestMessages`: the latest messages of a chat.
pub fn latest_messages(db : @sql.Db, args : Json) -> Json raise {
  messages_before(db, args.value("thread").unwrap_or(Json::null()), Json::string(i64_max) |> as_integer, args.value("limit"))
}

///|
/// A bound given as integer text, bound to SQLite as an integer (through CAST in the statements that compare with it,
/// else as the number nearest it, which compares the same with every key below it).
fn as_integer(v : Json) -> Json {
  match v {
    String(s) => @json.parse(s) catch { _ => v }
    v => v
  }
}

///|
/// store.ts `chatHistoryMessages`: a page before a message (`before` its ts), none when that message is not there.
pub fn chat_history_messages(db : @sql.Db, args : Json) -> Json raise {
  let thread = args.value("thread").unwrap_or(Json::null())
  db.exec("SAVEPOINT chat_history_messages_read")
  defer (db.exec("RELEASE chat_history_messages_read") catch { _ => () })
  let before = match args.value("before") {
    None | Some(Null) => Json::string(i64_max)
    Some(ts) =>
      match one(db, "SELECT CAST(n AS TEXT) AS n FROM entries WHERE thread = ? AND ts = ? AND kind = 'message'", [thread, ts]) {
        Some(b) => field(b, "n")
        None => return Json::null()
      }
  }
  messages_before(db, thread, as_integer(before), args.value("limit"))
}

///|
/// store.ts `openedChatSaid`: whether `author` said anything among the latest 200 messages (an agent's only, asked so).
pub fn opened_chat_said(db : @sql.Db, args : Json) -> Json raise {
  let thread = args.value("thread").unwrap_or(Json::null())
  db.exec("SAVEPOINT opened_chat_said_read")
  defer (db.exec("RELEASE opened_chat_said_read") catch { _ => () })
  let before = as_integer(Json::string(i64_max))
  let legacy = has_legacy_said(db)
  let old = if legacy { Some(said_page_state(db, thread)) } else { None }
  let keys = if old is Some((preparing, drain)) && (preparing || drain) {
    unprepared_page_keys(db, thread, before, 200, preparing, false)
  } else {
    bounded_page_keys(db, thread, before, 200, legacy)
  }
  if keys.length() == 0 {
    return false
  }
  let agent_only = args.value("agentOnly") is Some(True)
  Json::boolean(
    one(
      db,
      "SELECT 1 AS x FROM json_each(?2) j CROSS JOIN entries e\n      ON e.thread=?1 AND e.n=CAST(j.value AS INTEGER)\n      WHERE e.author=?3 AND (?4=0 OR e.author_kind='agent') LIMIT 1",
      [thread, Json::string(Json::array(keys.map(Json::string(_))).stringify()), args.value("author").unwrap_or(Json::null()), Json::number(if agent_only { 1.0 } else { 0.0 })],
    )
    is Some(_),
  )
}
