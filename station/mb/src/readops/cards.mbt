// The reads of a chat's pending card (station/src/read/store.ts `pendingCardNumber`, `statePendingCard`,
// `deliveryCardState`): by the card posts' index once a chat's posts are all in it, refused while they are being
// put in (the pool then has them prepared and asks again).

///|
let card_posts_pending : String = "card posts pending:"

///|
fn one(db : @sql.Db, sql : String, params : Array[Json]) -> Map[String, Json]? raise {
  db.all(sql, params).get(0)
}

///|
/// store.ts `threadsWithCards` for one chat: whether it has a post with a card or options at all.
fn has_cards(db : @sql.Db, thread : Json) -> Bool raise {
  one(db, "SELECT 1 AS x FROM entries INDEXED BY entries_cards WHERE thread = ? AND card IS NOT NULL LIMIT 1", [thread]) is Some(_) ||
  one(db, "SELECT 1 AS x FROM entries INDEXED BY entries_options WHERE thread = ? AND options IS NOT NULL LIMIT 1", [thread]) is Some(_)
}

///|
fn pending(thread : Json) -> Refused {
  Refused(503, card_posts_pending + Json::array([thread]).stringify())
}

///|
/// A JSON column as JSON.parse reads it, none when it does not parse (rows.ts `parsed`).
fn parsed(v : Json) -> @jsjson.JValue? {
  match v {
    String(s) => Some(@jsjson.parse(s)) catch { _ => None }
    _ => None
  }
}

///|
/// A value JSON.parse read, as the answer carries it.
pub fn to_json(v : @jsjson.JValue) -> Json {
  match v {
    Null => Json::null()
    Bool(b) => Json::boolean(b)
    Num(n) => Json::number(n)
    Str(s) => Json::string(@jsjson.text(s))
    Arr(xs) => Json::array(xs.map(to_json))
    Obj(fields) => {
      let m : Map[String, Json] = Map([])
      for f in fields {
        m[@jsjson.text(f.0)] = to_json(f.1)
      }
      Json::object(m)
    }
  }
}

///|
/// rows.ts `cardOf`: its own card, else its options as an options card.
fn card_of(card : Json, options : Json) -> Json? {
  match parsed(card) {
    Some(c) => Some(to_json(c))
    None =>
      match parsed(options) {
        Some(o) => Some({ "type": "options", "options": to_json(o) })
        None => None
      }
  }
}

///|
/// store.ts `pendingCardNumber`: the chat's card still waiting, by its number.
pub fn pending_card_number(db : @sql.Db, thread : Json) -> Json raise {
  db.exec("SAVEPOINT pending_card_number_read")
  defer (db.exec("RELEASE pending_card_number_read") catch { _ => () })
  if !@cards.ready(db, thread) {
    let indexed = match
      one(db, "SELECT COUNT(*) AS n FROM sqlite_master WHERE type = 'index' AND name IN ('entries_cards', 'entries_options')", []) {
      Some(r) => r.get("n") is Some(Number(2.0, ..))
      None => false
    }
    if indexed && !has_cards(db, thread) {
      return Json::null()
    }
    raise pending(thread)
  }
  guard one(db, "SELECT CAST(n AS TEXT) AS n FROM card_posts WHERE thread=? ORDER BY card_posts.n DESC LIMIT 1", [thread]) is Some(asked) else {
    return Json::null()
  }
  let n = field(asked, "n")
  guard one(db, "SELECT card, options FROM entries WHERE thread = ? AND n = CAST(? AS INTEGER) AND kind = 'message'", [thread, n]) is Some(post) &&
    card_of(field(post, "card"), field(post, "options")) is Some(_) else {
    return Json::null()
  }
  if one(db, "SELECT 1 AS x FROM entries WHERE thread = ? AND kind = 'message' AND author_kind = 'person' AND n > CAST(? AS INTEGER) LIMIT 1", [thread, n]) is Some(_) {
    return Json::null()
  }
  if one(db, "SELECT 1 AS x FROM closed_cards WHERE thread = ? AND n = CAST(? AS INTEGER)", [thread, n]) is Some(_) {
    return Json::null()
  }
  number_of(n)
}

///|
/// A number read as text (an id past 2^53 kept as SQLite has it, as near as a double holds it, as node reads it).
fn number_of(n : Json) -> Json {
  match n {
    String(s) => @json.parse(s) catch { _ => Json::null() }
    v => v
  }
}

///|
/// store.ts `statePendingCard`: the latest card waiting among the chats, `[thread, n, ts]`.
pub fn state_pending_card(db : @sql.Db, args : Json) -> Json raise {
  db.exec("SAVEPOINT state_pending_card_read")
  defer (db.exec("RELEASE state_pending_card_read") catch { _ => () })
  let threads = match args.value("threads") {
    Some(Array(ts)) => ts
    _ => []
  }
  let cards : Array[(Json, Json, Json, Double)] = []
  for thread in threads {
    let n = pending_card_number(db, thread)
    if n is Null {
      continue
    }
    if one(db, "SELECT ts, at FROM entries WHERE thread = ? AND n = ? AND kind = 'message'", [thread, n]) is Some(row) {
      let ts = match field(row, "ts") {
        Null => Json::string("")
        t => t
      }
      let at = match field(row, "at") {
        Number(a, ..) => a
        _ => 0.0 / 0.0
      }
      cards.push((thread, n, ts, at))
    }
  }
  // (sorted as Array.prototype.sort sorts by `a.at - b.at`: stable, a NaN compare equal)
  let sorted = stable_sort(cards, (a, b) => {
    let d = a.3 - b.3
    if d < 0.0 { -1 } else if d > 0.0 { 1 } else { 0 }
  })
  match sorted.last() {
    Some((thread, n, ts, _)) => Json::array([thread, n, ts])
    None => Json::null()
  }
}

///|
fn[T] stable_sort(xs : Array[T], cmp : (T, T) -> Int) -> Array[T] {
  let out = xs.copy()
  for i = 1; i < out.length(); i = i + 1 {
    let x = out[i]
    let mut j = i - 1
    while j >= 0 && cmp(out[j], x) > 0 {
      out[j + 1] = out[j]
      j -= 1
    }
    out[j + 1] = x
  }
  out
}

///|
/// store.ts `deliveryCardState`: the card a person's message answered, and the card waiting now.
pub fn delivery_card_state(db : @sql.Db, args : Json) -> Json raise {
  let thread = args.value("thread").unwrap_or(Json::null())
  let n = args.value("n").unwrap_or(Json::null())
  db.exec("SAVEPOINT delivery_card_state_read")
  defer (db.exec("RELEASE delivery_card_state_read") catch { _ => () })
  if one(db, "SELECT 1 AS x FROM entries WHERE thread = ? AND n = ? AND kind = 'message' AND author_kind = 'person'", [thread, n]) is None {
    return Json::null()
  }
  if !@cards.ready(db, thread) {
    if !has_cards(db, thread) {
      return Json::null()
    }
    raise pending(thread)
  }
  guard one(db, "SELECT CAST(MAX(n) AS TEXT) AS n FROM card_posts WHERE thread=? AND n<?", [thread, n]) is Some(r) &&
    field(r, "n") is String(_) else {
    return Json::null()
  }
  let asked = field(r, "n")
  if one(db, "SELECT 1 AS x FROM entries WHERE thread = ? AND kind = 'message' AND author_kind = 'person' AND n > CAST(? AS INTEGER) AND n < ? LIMIT 1", [thread, asked, n]) is Some(_) {
    return Json::null()
  }
  if one(db, "SELECT 1 AS x FROM closed_cards WHERE thread = ? AND n = CAST(? AS INTEGER)", [thread, asked]) is Some(_) {
    return Json::null()
  }
  guard one(db, "SELECT ts, author, card, options FROM entries WHERE thread = ? AND n = CAST(? AS INTEGER) AND kind = 'message'", [thread, asked]) is Some(post) else {
    return Json::null()
  }
  guard card_of(field(post, "card"), field(post, "options")) is Some(card) else { return Json::null() }
  let current_n = pending_card_number(db, thread)
  let current = if current_n is Null {
    Json::null()
  } else {
    match one(db, "SELECT ts FROM entries WHERE thread = ? AND n = ? AND kind = 'message'", [thread, current_n]) {
      Some(c) => ({ "ts": or_empty(field(c, "ts")) } : Json)
      None => Json::null()
    }
  }
  { "ended": { "author": field(post, "author"), "ts": or_empty(field(post, "ts")) }, "card": card, "current": current }
}

///|
fn or_empty(v : Json) -> Json {
  match v {
    Null => Json::string("")
    t => t
  }
}
