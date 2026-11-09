// The files a chat's messages carry, for the widgets that show them (station/src/store/widget-sources.ts): an old
// thread's messages prepared in bounded batches, as `widgetSourcesStep` does, here for the MoonBit builder.

///|
let version : Int = 1

///|
let valid_attachments : String = "CASE WHEN json_valid(m.attachments) THEN m.attachments ELSE '[]' END"

///|
let path_of : String = "CASE WHEN json_valid(a.value) THEN json_extract(a.value, '$.path') END"

///|
let name_of : String = "CASE WHEN json_valid(a.value) THEN json_extract(a.value, '$.name') END"

///|
/// One message, as the batch names it.
let message : String = "SELECT ? AS thread, CAST(? AS INTEGER) AS n"

///|
let insert_rows : String = "INSERT INTO widget_source_rows (thread,n,slot,path,at,name) SELECT m.thread, m.n, a.id, \{path_of}, m.created_at, \{name_of} FROM (\{message}) k CROSS JOIN merged m ON m.thread = k.thread AND m.n = k.n CROSS JOIN json_each(\{valid_attachments}) a WHERE typeof(\{path_of}) = 'text' AND NOT EXISTS (SELECT 1 FROM widget_source_rows i WHERE i.thread = m.thread AND i.n = m.n AND i.slot = a.id)"

///|
/// Malformed or noncanonical attachments, remembered without making the write itself fail.
let invalid : String = "(m.attachments IS NOT NULL AND (NOT json_valid(m.attachments) OR EXISTS (SELECT 1 FROM json_each(\{valid_attachments}) a WHERE a.value IS NOT NULL AND NOT json_valid(a.value))))"

///|
let insert_invalid : String = "INSERT INTO widget_source_invalid (thread,n) SELECT m.thread, m.n FROM (\{message}) k CROSS JOIN merged m ON m.thread = k.thread AND m.n = k.n WHERE \{invalid} AND NOT EXISTS (SELECT 1 FROM widget_source_invalid i WHERE i.thread = m.thread AND i.n = m.n)"

///|
/// Where a batch's positions are read: through the letter and said indexes (`indexed`), or the primary key on a store
/// that lacks one of them. Ordered inside, numbers cast to text only after.
fn positions_query(after : Bool, indexed : Bool) -> String {
  let range = if after {
    "thread=?1 AND n>CAST(?2 AS INTEGER) AND n<=CAST(?3 AS INTEGER)"
  } else {
    "thread=?1 AND n<=CAST(?2 AS INTEGER)"
  }
  let limit = if after { "?4" } else { "?3" }
  if !indexed {
    return "SELECT CAST(entries.n AS TEXT) AS n FROM entries WHERE \{range} ORDER BY entries.n LIMIT \{limit}"
  }
  "SELECT CAST(n AS TEXT) AS n FROM ( SELECT n FROM entries INDEXED BY entries_said WHERE \{range} AND kind='message' AND letter IS NULL UNION ALL SELECT n FROM entries INDEXED BY entries_letters WHERE \{range} AND letter IS NOT NULL ORDER BY n LIMIT \{limit} )"
}

///|
fn value(row : Map[String, Json], name : String) -> Json {
  match row.get(name) {
    Some(j) => j
    None => Json::null()
  }
}

///|
fn check(db : @sql.Db) -> Unit raise {
  let meta = db.all("SELECT version FROM widget_source_meta WHERE id=1", [])
  match meta {
    [m, ..] if m.get("version") is Some(Number(v, ..)) && v.to_int() == version => ()
    [m, ..] => fail("widget source index version \{value(m, "version").stringify()} is incompatible with \{version}")
    _ => fail("widget source index version missing is incompatible with \{version}")
  }
}

///|
fn scope_of(db : @sql.Db, thread : Json) -> Map[String, Json]? raise {
  match
    db.all(
      "SELECT CAST(last_n AS TEXT) AS last_n, CAST(end_n AS TEXT) AS end_n, complete FROM widget_source_scopes WHERE thread=?",
      [thread],
    ) {
    [s, ..] => Some(s)
    _ => None
  }
}

///|
fn complete(scope : Map[String, Json]?) -> Bool {
  scope is Some(s) && s.get("complete") is Some(Number(1.0, ..))
}

///|
/// One batch of at most `limit` (128 at most) of `thread`'s old messages; whether all of its are prepared then. Its
/// positions are read before the write is taken; a scope that moved meanwhile is left as it is.
pub fn step(db : @sql.Db, thread : Int64, limit? : Int = 128) -> Bool raise {
  guard limit >= 1 && limit <= 128 else { fail("widget source batch must be between 1 and 128") }
  let t = Json::number(thread.to_double())
  check(db)
  if complete(scope_of(db, t)) {
    return true
  }
  if scope_of(db, t) is None {
    db.exec("BEGIN IMMEDIATE")
    {
      errdefer (db.exec("ROLLBACK") catch { _ => () })
      ignore(
        db.run(
          "INSERT INTO widget_source_scopes (thread,last_n,end_n,complete) SELECT ?,NULL,(SELECT n FROM entries WHERE thread=? ORDER BY n DESC LIMIT 1),0 WHERE NOT EXISTS (SELECT 1 FROM widget_source_scopes WHERE thread=?)",
          [t, t, t],
        ),
      )
      db.exec("COMMIT")
    }
  }
  guard scope_of(db, t) is Some(before) else { fail("widget source scope is missing") }
  if complete(Some(before)) {
    return true
  }
  let indexes = db.all(
    "SELECT count(*) AS n FROM sqlite_master WHERE type='index' AND name IN ('entries_said','entries_letters')",
    [],
  )
  let indexed = indexes is [i, ..] && i.get("n") is Some(Number(2.0, ..))
  let last = value(before, "last_n")
  let end = value(before, "end_n")
  let lim = Json::number(limit.to_double())
  let positions = if last is Null {
    db.all(positions_query(false, indexed), [t, end, lim])
  } else {
    db.all(positions_query(true, indexed), [t, last, end, lim])
  }
  db.exec("BEGIN IMMEDIATE")
  errdefer (db.exec("ROLLBACK") catch { _ => () })
  let now = scope_of(db, t)
  guard now is Some(n) &&
    value(n, "last_n") == last &&
    value(n, "end_n") == end &&
    value(n, "complete") == value(before, "complete") else {
    db.exec("COMMIT")
    return complete(now)
  }
  for position in positions {
    let at = value(position, "n")
    ignore(db.run(insert_rows, [t, at]))
    ignore(db.run(insert_invalid, [t, at]))
  }
  let done = positions.length() < limit
  let reached = match positions.last() {
    Some(p) => value(p, "n")
    None => last
  }
  ignore(
    db.run("UPDATE widget_source_scopes SET last_n=CAST(? AS INTEGER), complete=? WHERE thread=?", [
      reached,
      Json::number(if done { 1.0 } else { 0.0 }),
      t,
    ]),
  )
  db.exec("COMMIT")
  done
}
