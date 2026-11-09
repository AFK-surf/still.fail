// Reading and writing as the index's steps do. Chat ids, rowids and revisions go in and out as text (`CAST`), so an
// id beyond 2^53 stays exact; results are never ordered by such a text alias.

///|
fn first(
  db : @sql.Db,
  sql : String,
  params : Array[Json],
) -> Map[String, Json]? raise {
  match db.all(sql, params) {
    [r, ..] => Some(r)
    _ => None
  }
}

///|
/// A statement's one row (an aggregate's, a meta table's).
fn one(
  db : @sql.Db,
  sql : String,
  params : Array[Json],
) -> Map[String, Json] raise {
  guard first(db, sql, params) is Some(r) else {
    fail("recent chat index row missing: \{sql}")
  }
  r
}

///|
fn exists(db : @sql.Db, sql : String, params : Array[Json]) -> Bool raise {
  first(db, sql, params) is Some(_)
}

///|
fn get(row : Map[String, Json], name : String) -> Json {
  row.get(name).unwrap_or(Json::null())
}

///|
/// A small integer column (a flag, a count); -1 for NULL.
fn int(row : Map[String, Json], name : String) -> Int {
  match row.get(name) {
    Some(Number(n, ..)) => n.to_int()
    _ => -1
  }
}

///|
fn text(s : String) -> Json {
  Json::string(s)
}

///|
fn num(n : Int) -> Json {
  Json::number(n.to_double())
}

///|
/// `f` in a write transaction, rolled back when it fails.
fn[T] write(db : @sql.Db, f : () -> T raise) -> T raise {
  db.exec("BEGIN IMMEDIATE")
  errdefer (db.exec("ROLLBACK") catch { _ => () })
  let result = f()
  db.exec("COMMIT")
  result
}

///|
/// `f` on one read snapshot (or inside the caller's transaction).
fn[T] snapshot(db : @sql.Db, name : String, f : () -> T raise) -> T raise {
  db.exec("SAVEPOINT \{name}")
  errdefer (db.exec("RELEASE \{name}") catch { _ => () })
  let result = f()
  db.exec("RELEASE \{name}")
  result
}

///|
/// A chat's place in the order: its selected message's time, else its creation (`?N` is the chat, as text).
fn current(param : String) -> String {
  "SELECT t.id AS thread, COALESCE(e.at, t.created_at) AS at, COALESCE(e.at, 0) AS said_at, t.created_at AS created_at FROM threads t LEFT JOIN thread_state s ON s.thread = t.id LEFT JOIN entries e ON e.thread = t.id AND e.n = s.said_n AND e.kind = 'message' WHERE t.id = CAST(\{param} AS INTEGER)"
}

///|
fn chat_exists(db : @sql.Db, thread : Json) -> Bool raise {
  exists(db, "SELECT 1 FROM threads WHERE id = CAST(? AS INTEGER)", [thread])
}
