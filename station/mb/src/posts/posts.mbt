// The markers of which agent said something in which block of a chat's messages (station/src/store/post-blocks.ts):
// an older store's requested suffix of a chat marked newest first in bounded steps, as `postBlocksStep` does, here for
// the MoonBit builder. The history is read before the write is taken; under it only the selected posts are rechecked.

///|
let size : Int = 64

///|
fn get(row : Map[String, Json], name : String) -> Json {
  row.get(name).unwrap_or(Json::null())
}

///|
fn first(db : @sql.Db, sql : String, params : Array[Json]) -> Map[String, Json]? raise {
  match db.all(sql, params) {
    [r, ..] => Some(r)
    _ => None
  }
}

///|
fn block(n : String) -> String {
  "(\{n} / \{size} - CASE WHEN \{n} < 0 AND \{n} % \{size} != 0 THEN 1 ELSE 0 END)"
}

///|
fn fresh(db : @sql.Db) -> Bool raise {
  match first(db, "SELECT fresh FROM post_blocks_meta WHERE id = 1", []) {
    Some(r) => get(r, "fresh") is Number(1.0, ..)
    None => raise Failure("post block metadata is missing")
  }
}

///|
/// A chat's coverage, and whether it covers from `after` on (`covers`): its cursor and completeness as text.
fn coverage(db : @sql.Db, thread : Json, after : Json) -> (Map[String, Json]?, Bool) raise {
  match
    first(
      db,
      "SELECT CAST(cursor AS TEXT) AS cursor, complete, (complete = 1 OR (cursor IS NOT NULL AND cursor <= ?2 + 1)) AS covers FROM post_blocks_coverage WHERE thread = ?1",
      [thread, after],
    ) {
    Some(r) => (Some(r), get(r, "covers") is Number(1.0, ..))
    None => (None, false)
  }
}

///|
/// One step of marking `thread`'s messages from `after` on, at most `limit` (64 at most) entries, newest first; whether
/// that suffix is covered then.
pub fn step(db : @sql.Db, thread : Int64, after : Int64, limit? : Int = 64) -> Bool raise {
  guard limit >= 1 && limit <= size else { raise Failure("post block batch must be between 1 and 64") }
  if fresh(db) {
    return true
  }
  let t = Json::number(thread.to_double())
  let a = Json::number(after.to_double())
  let lim = Json::number(limit.to_double())
  let (before, covered) = coverage(db, t, a)
  if covered {
    return true
  }
  let before_cursor = match before {
    Some(r) => get(r, "cursor")
    None => Json::null()
  }
  let before_complete = match before {
    Some(r) => get(r, "complete")
    None => Json::number(0.0)
  }
  let rows = if before_cursor is Null {
    db.all(
      "SELECT CAST(n AS TEXT) AS n, kind, author_kind, author FROM entries WHERE thread = ? AND n >= ? ORDER BY entries.n DESC LIMIT ?",
      [t, a, lim],
    )
  } else {
    db.all(
      "SELECT CAST(n AS TEXT) AS n, kind, author_kind, author FROM entries WHERE thread = ? AND n < CAST(? AS INTEGER) AND n >= ? ORDER BY entries.n DESC LIMIT ?",
      [t, before_cursor, a, lim],
    )
  }
  let older = rows.length() < limit &&
    first(db, "SELECT 1 FROM entries WHERE thread = ? AND n < ? LIMIT 1", [t, a]) is Some(_)
  db.exec("BEGIN IMMEDIATE")
  errdefer (db.exec("ROLLBACK") catch { _ => () })
  let (current, now_covered) = coverage(db, t, a)
  let current_cursor = match current {
    Some(r) => get(r, "cursor")
    None => Json::null()
  }
  let current_complete = match current {
    Some(r) => get(r, "complete")
    None => Json::number(0.0)
  }
  if current_cursor != before_cursor || current_complete != before_complete {
    db.exec("COMMIT")
    return now_covered
  }
  for row in rows {
    if get(row, "kind") == Json::string("message") && get(row, "author_kind") == Json::string("agent") {
      ignore(
        db.run(
          "INSERT INTO post_blocks (thread, author, bucket) SELECT e.thread, e.author, \{block("e.n")} FROM entries e WHERE e.thread = ? AND e.n = CAST(? AS INTEGER) AND e.author = ? AND e.kind = 'message' AND e.author_kind = 'agent' AND NOT EXISTS (SELECT 1 FROM post_blocks b WHERE b.thread = e.thread AND b.author = e.author AND b.bucket = \{block("e.n")})",
          [t, get(row, "n"), get(row, "author")],
        ),
      )
    }
  }
  let cursor = if rows.length() < limit {
    a
  } else {
    get(rows[rows.length() - 1], "n")
  }
  let complete = rows.length() < limit && !older
  ignore(
    db.run(
      "INSERT INTO post_blocks_coverage(thread, cursor, complete) VALUES (?, CAST(? AS INTEGER), ?) ON CONFLICT(thread) DO UPDATE SET cursor = excluded.cursor, complete = excluded.complete",
      [t, cursor, Json::number(if complete { 1.0 } else { 0.0 })],
    ),
  )
  let done = complete ||
    (
      match first(db, "SELECT CAST(? AS INTEGER) <= ? + 1 AS ok", [cursor, a]) {
        Some(r) => get(r, "ok") is Number(1.0, ..)
        None => false
      }
    )
  db.exec("COMMIT")
  done
}
