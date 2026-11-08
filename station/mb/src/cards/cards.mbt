// The messages of a chat that carry a card or options (station/src/store/card-post-index.ts): an old thread's
// prepared in bounded batches, as `cardPostsStep` does, here for the MoonBit builder. Phases: 0 the cards, 1 the
// options, 3 every entry (a store that lost one of their indexes), 2 done.

///|
let version : Int = 1

///|
fn value(row : Map[String, Json], name : String) -> Json {
  match row.get(name) {
    Some(j) => j
    None => Json::null()
  }
}

///|
fn check(db : @sql.Db) -> Unit raise {
  match db.all("SELECT version FROM card_post_meta WHERE id=1", []) {
    [m, ..] if m.get("version") is Some(Number(v, ..)) && v.to_int() == version => ()
    [m, ..] => fail("card post index version \{value(m, "version").stringify()} is incompatible with \{version}")
    _ => fail("card post index version missing is incompatible with \{version}")
  }
}

///|
fn scope_of(db : @sql.Db, thread : Json) -> Map[String, Json]? raise {
  match
    db.all("SELECT CAST(last_n AS TEXT) AS last_n,CAST(end_n AS TEXT) AS end_n,phase FROM card_post_scopes WHERE thread=?", [
      thread,
    ]) {
    [s, ..] => Some(s)
    _ => None
  }
}

///|
fn phase(scope : Map[String, Json]?) -> Int {
  match scope {
    Some(s) =>
      match s.get("phase") {
        Some(Number(p, ..)) => p.to_int()
        _ => -1
      }
    None => -1
  }
}

///|
fn same(a : Map[String, Json]?, b : Map[String, Json]) -> Bool {
  a is Some(a) &&
  value(a, "last_n") == value(b, "last_n") &&
  value(a, "end_n") == value(b, "end_n") &&
  value(a, "phase") == value(b, "phase")
}

///|
/// Where a batch's positions are read: by the cards' or the options' index, or every entry (`column` None). Ordered
/// inside, numbers cast to text only after; the limit applies before the kind is looked at.
fn positions_query(column : String?, after : Bool) -> String {
  let (index, predicate) = match column {
    Some(c) => (" INDEXED BY entries_\{if c == "card" { "cards" } else { "options" }}", " AND \{c} IS NOT NULL")
    None => ("", "")
  }
  let range = if after {
    "n>CAST(?2 AS INTEGER) AND n<=CAST(?3 AS INTEGER)"
  } else {
    "n<=CAST(?2 AS INTEGER)"
  }
  "SELECT CAST(n AS TEXT) AS n FROM (SELECT n FROM entries\{index} WHERE thread=?1 AND \{range}\{predicate} ORDER BY n LIMIT \{if after { "?4" } else { "?3" }})"
}

///|
/// One batch of at most `limit` (128 at most) of `thread`'s old entries; whether all of its are prepared then.
pub fn step(db : @sql.Db, thread : Int64, limit? : Int = 128) -> Bool raise {
  guard limit >= 1 && limit <= 128 else { fail("card post batch must be between 1 and 128") }
  let t = Json::number(thread.to_double())
  check(db)
  if phase(scope_of(db, t)) == 2 {
    return true
  }
  if scope_of(db, t) is None {
    db.exec("BEGIN IMMEDIATE")
    {
      errdefer (db.exec("ROLLBACK") catch { _ => () })
      ignore(
        db.run(
          "INSERT INTO card_post_scopes(thread,last_n,end_n,phase) SELECT ?1,NULL,(SELECT n FROM entries WHERE thread=?1 ORDER BY n DESC LIMIT 1),0 WHERE NOT EXISTS (SELECT 1 FROM card_post_scopes WHERE thread=?1)",
          [t],
        ),
      )
      db.exec("COMMIT")
    }
  }
  guard scope_of(db, t) is Some(before) else { fail("card post scope is missing") }
  let at = phase(Some(before))
  if at == 2 {
    return true
  }
  let indexes = db.all(
    "SELECT COUNT(*) AS n FROM sqlite_master WHERE type='index' AND name IN ('entries_cards','entries_options')",
    [],
  )
  let indexed = indexes is [i, ..] && i.get("n") is Some(Number(2.0, ..))
  // (an old index gone between batches: the walk starts again by the primary key, as the earlier card-only batches
  // cannot say they saw every options-only post)
  if !indexed && at != 3 {
    db.exec("BEGIN IMMEDIATE")
    errdefer (db.exec("ROLLBACK") catch { _ => () })
    let now = scope_of(db, t)
    if same(now, before) {
      ignore(db.run("UPDATE card_post_scopes SET last_n=NULL,phase=3 WHERE thread=?", [t]))
    }
    db.exec("COMMIT")
    return phase(now) == 2
  }
  let column = if at == 3 {
    None
  } else if at == 0 {
    Some("card")
  } else {
    Some("options")
  }
  let last = value(before, "last_n")
  let end = value(before, "end_n")
  let lim = Json::number(limit.to_double())
  let rows = if last is Null {
    db.all(positions_query(column, false), [t, end, lim])
  } else {
    db.all(positions_query(column, true), [t, last, end, lim])
  }
  db.exec("BEGIN IMMEDIATE")
  errdefer (db.exec("ROLLBACK") catch { _ => () })
  let now = scope_of(db, t)
  if !same(now, before) {
    db.exec("COMMIT")
    return phase(now) == 2
  }
  let add = "INSERT INTO card_posts(thread,n) SELECT e.thread,e.n FROM entries e WHERE e.thread=?1 AND e.n=CAST(?2 AS INTEGER) AND e.kind='message' AND (e.card IS NOT NULL OR e.options IS NOT NULL) AND NOT EXISTS (SELECT 1 FROM card_posts p WHERE p.thread=e.thread AND p.n=e.n)"
  for row in rows {
    ignore(db.run(add, [t, value(row, "n")]))
  }
  let end_of_phase = rows.length() < limit
  let next = if !end_of_phase {
    at
  } else if column is None {
    2
  } else {
    at + 1
  }
  let reached = if end_of_phase {
    Json::null()
  } else {
    match rows.last() {
      Some(r) => value(r, "n")
      None => Json::null()
    }
  }
  ignore(
    db.run("UPDATE card_post_scopes SET last_n=CAST(? AS INTEGER),phase=? WHERE thread=?", [
      reached,
      Json::number(next.to_double()),
      t,
    ]),
  )
  db.exec("COMMIT")
  next == 2
}
