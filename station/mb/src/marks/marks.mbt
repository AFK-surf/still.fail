// The marks that keep a chat out of automatic archive, looked up by the chat (station/src/store/archive-mark-index.ts):
// old pins and kept chats prepared in bounded batches, as `archiveMarksStep` does, here for the MoonBit builder.

///|
let version : Int = 1

///|
priv struct Part {
  source : String
  key : String
  rows : String
}

///|
fn part(kind : String) -> Part {
  if kind == "pins" {
    { source: "pins", key: "session", rows: "archive_pin_rows" }
  } else {
    { source: "kept_chats", key: "thread", rows: "archive_keep_rows" }
  }
}

///|
fn text(v : Json?) -> Json {
  match v {
    Some(j) => j
    None => Json::null()
  }
}

///|
/// Its markers, kept then pins, each of this version.
fn markers(db : @sql.Db) -> Array[Map[String, Json]] raise {
  let rows = db.all(
    "SELECT kind, version, CAST(last_rowid AS TEXT) AS last_rowid, CAST(end_rowid AS TEXT) AS end_rowid, complete FROM archive_mark_meta ORDER BY kind",
    [],
  )
  guard rows.length() == 2 &&
    rows[0].get("kind") == Some(Json::string("kept")) &&
    rows[1].get("kind") == Some(Json::string("pins")) else {
    fail("archive mark index version marker is missing")
  }
  for row in rows {
    match row.get("version") {
      Some(Number(n, ..)) if n.to_int() == version => ()
      v => fail("archive mark index version \{text(v).stringify()} is incompatible with \{version}")
    }
  }
  rows
}

///|
fn complete(m : Map[String, Json]) -> Bool {
  match m.get("complete") {
    Some(Number(n, ..)) => n == 1.0
    _ => false
  }
}

///|
/// One batch of at most `limit` rows of the first kind not prepared yet; whether all of both are then.
pub fn step(db : @sql.Db, limit? : Int = 256) -> Bool raise {
  db.exec("BEGIN IMMEDIATE")
  // (what failed is let go: nothing of a batch is kept but whole)
  errdefer (db.exec("ROLLBACK") catch { _ => () })
  let all = markers(db)
  let meta = all.iter().find_first(m => !complete(m))
  guard meta is Some(meta) else {
    db.exec("COMMIT")
    return true
  }
  let kind = match meta.get("kind") {
    Some(String(k)) => k
    _ => fail("archive mark kind is missing")
  }
  let { source, key, rows } = part(kind)
  let last = text(meta.get("last_rowid"))
  let end = text(meta.get("end_rowid"))
  let lim = Json::number(limit.to_double())
  let positions = if last is Null {
    db.all(
      "SELECT CAST(rowid AS TEXT) AS position FROM \{source} WHERE rowid <= CAST(? AS INTEGER) ORDER BY rowid LIMIT ?",
      [end, lim],
    )
  } else {
    db.all(
      "SELECT CAST(rowid AS TEXT) AS position FROM \{source} WHERE rowid > CAST(? AS INTEGER) AND rowid <= CAST(? AS INTEGER) ORDER BY rowid LIMIT ?",
      [last, end, lim],
    )
  }
  let put = "INSERT INTO \{rows} (\{key}, position) SELECT s.\{key}, s.rowid FROM \{source} s WHERE s.rowid = CAST(? AS INTEGER) AND NOT EXISTS (SELECT 1 FROM \{rows} i WHERE i.\{key} IS s.\{key} AND i.position = s.rowid)"
  for row in positions {
    ignore(db.run(put, [text(row.get("position"))]))
  }
  let finished = positions.length() < limit
  let reached = match positions.last() {
    Some(row) => text(row.get("position"))
    None => last
  }
  ignore(
    db.run("UPDATE archive_mark_meta SET last_rowid = CAST(? AS INTEGER), complete = ? WHERE kind = ?", [
      reached,
      Json::number(if finished { 1.0 } else { 0.0 }),
      Json::string(kind),
    ]),
  )
  db.exec("COMMIT")
  finished &&
  all.iter().all(m => m.get("kind") == Some(Json::string(kind)) || complete(m))
}
