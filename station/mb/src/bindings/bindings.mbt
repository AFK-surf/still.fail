// A session's connection bindings looked up by the session (station/src/store/session-bindings-index.ts): the old
// bindings copied in bounded batches, as `sessionBindingsStep` does, here for the MoonBit builder.

///|
let version : Int = 1

///|
let first : String = "SELECT CAST(rowid AS TEXT) AS position FROM bindings WHERE rowid <= CAST(? AS INTEGER) ORDER BY rowid LIMIT ?"

///|
let next : String = "SELECT CAST(rowid AS TEXT) AS position FROM bindings WHERE rowid > CAST(? AS INTEGER) AND rowid <= CAST(? AS INTEGER) ORDER BY rowid LIMIT ?"

///|
let put : String = "INSERT INTO session_binding_rows (session, binding_rowid, connect) SELECT b.session_key, b.rowid, b.connect FROM bindings b WHERE b.rowid = CAST(? AS INTEGER) AND NOT EXISTS (SELECT 1 FROM session_binding_rows i WHERE i.session = b.session_key AND i.binding_rowid = b.rowid)"

///|
fn value(row : Map[String, Json], name : String) -> Json {
  match row.get(name) {
    Some(j) => j
    None => Json::null()
  }
}

///|
/// One batch of at most `limit` old bindings; whether all are copied then.
pub fn step(db : @sql.Db, limit? : Int = 256) -> Bool raise {
  db.exec("BEGIN IMMEDIATE")
  // (what failed is let go: nothing of a batch is kept but whole)
  errdefer (db.exec("ROLLBACK") catch { _ => () })
  let meta = db.all(
    "SELECT version, CAST(last_rowid AS TEXT) AS last_rowid, CAST(end_rowid AS TEXT) AS end_rowid, complete FROM session_binding_meta WHERE id = 1",
    [],
  )
  guard meta is [meta, ..] else { fail("session binding index version marker is missing") }
  match meta.get("version") {
    Some(Number(n, ..)) if n.to_int() == version => ()
    v => fail("session binding index version \{(match v { Some(j) => j; None => Json::null() }).stringify()} is incompatible with \{version}")
  }
  if meta.get("complete") is Some(Number(1.0, ..)) {
    db.exec("COMMIT")
    return true
  }
  let last = value(meta, "last_rowid")
  let end = value(meta, "end_rowid")
  let lim = Json::number(limit.to_double())
  let rows = if last is Null { db.all(first, [end, lim]) } else { db.all(next, [last, end, lim]) }
  for row in rows {
    ignore(db.run(put, [value(row, "position")]))
  }
  let done = rows.length() < limit
  let reached = match rows.last() {
    Some(row) => value(row, "position")
    None => last
  }
  ignore(
    db.run("UPDATE session_binding_meta SET last_rowid = CAST(? AS INTEGER), complete = ? WHERE id = 1", [
      reached,
      Json::number(if done { 1.0 } else { 0.0 }),
    ]),
  )
  db.exec("COMMIT")
  done
}
