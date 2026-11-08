// The station overview's session counts (station/src/store/session-counts.ts): the old sessions brought across in
// bounded transactions up to the boundary the index was made with, as `sessionCountsStep` does, here for the MoonBit
// builder; the triggers count what writers change meanwhile.

///|
let version : Int = 1

///|
fn get(row : Map[String, Json], name : String) -> Json {
  row.get(name).unwrap_or(Json::null())
}

///|
/// A session as the index sees it, by its position (a key with a NUL is not read out and in again).
let see_position : String = "INSERT INTO session_count_seen (session, connect, ws) SELECT s.key, s.connect, s.ws FROM sessions s WHERE s.key = (SELECT key FROM sessions WHERE rowid = CAST(? AS INTEGER)) AND NOT EXISTS (SELECT 1 FROM session_count_seen c WHERE c.session = s.key)"

///|
/// At most `limit` old sessions counted, with the cursor; whether all are then.
pub fn step(db : @sql.Db, limit? : Int = 256) -> Bool raise {
  guard limit >= 1 else { raise Failure("session count batch must be positive") }
  db.exec("BEGIN IMMEDIATE")
  errdefer (db.exec("ROLLBACK") catch { _ => () })
  guard db.all(
      "SELECT version, CAST(last_rowid AS TEXT) AS last_rowid, CAST(end_rowid AS TEXT) AS end_rowid, complete FROM session_count_meta WHERE id = 1",
      [],
    )
    is [meta, ..] else {
    raise Failure("session count index version marker is missing")
  }
  guard get(meta, "version") is Number(v, ..) && v.to_int() == version else {
    raise Failure("session count index version \{get(meta, "version").stringify()} is incompatible with \{version}")
  }
  if get(meta, "complete") is Number(1.0, ..) {
    db.exec("COMMIT")
    return true
  }
  let last = get(meta, "last_rowid")
  let end = get(meta, "end_rowid")
  let lim = Json::number(limit.to_double())
  let rows = if last is Null {
    db.all(
      "SELECT CAST(rowid AS TEXT) AS position FROM sessions WHERE rowid <= CAST(? AS INTEGER) ORDER BY rowid LIMIT ?",
      [end, lim],
    )
  } else {
    db.all(
      "SELECT CAST(rowid AS TEXT) AS position FROM sessions WHERE rowid > CAST(? AS INTEGER) AND rowid <= CAST(? AS INTEGER) ORDER BY rowid LIMIT ?",
      [last, end, lim],
    )
  }
  for row in rows {
    ignore(db.run(see_position, [get(row, "position")]))
  }
  let done = rows.length() < limit
  let reached = match rows.last() {
    Some(r) => get(r, "position")
    None => last
  }
  ignore(
    db.run("UPDATE session_count_meta SET last_rowid = CAST(? AS INTEGER), complete = ? WHERE id = 1", [
      reached,
      Json::number(if done { 1.0 } else { 0.0 }),
    ]),
  )
  db.exec("COMMIT")
  done
}
