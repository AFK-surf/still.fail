// The session list's candidates by workspace and archive state (station/src/store/session-list-index.ts): the old
// sessions copied in bounded batches, as `sessionListStep` does, and visited again for search
// (`auditSessionListStep`: a list from an older station may have missed keys with a NUL or not UTF-8), here for the
// MoonBit builder.

///|
let version : Int = 1

///|
let first : String = "SELECT CAST(rowid AS TEXT) AS position FROM sessions WHERE rowid <= CAST(? AS INTEGER) ORDER BY rowid LIMIT ?"

///|
let next : String = "SELECT CAST(rowid AS TEXT) AS position FROM sessions WHERE rowid > CAST(? AS INTEGER) AND rowid <= CAST(? AS INTEGER) ORDER BY rowid LIMIT ?"

///|
/// A session as the list keeps it: its key, whether it has a workspace, the workspace, archived or not, its connect.
let values : String = "s.key, CASE WHEN s.ws IS NULL THEN 0 ELSE 1 END, COALESCE(s.ws, ''), (s.archived_at IS NOT NULL), s.connect"

///|
let matches : String = "i.kind = CASE WHEN s.ws IS NULL THEN 0 ELSE 1 END AND i.ws = COALESCE(s.ws, '') AND i.archived = (s.archived_at IS NOT NULL) AND i.connect = s.connect AND i.session = s.key"

///|
/// The session at a position, kept as SQLite has its key (a key with a NUL is not read out and in again).
let see_position : String = "INSERT INTO session_list_rows (session, kind, ws, archived, connect) SELECT \{values} FROM sessions s WHERE s.key = (SELECT key FROM sessions WHERE rowid = CAST(? AS INTEGER)) AND NOT EXISTS (SELECT 1 FROM session_list_rows i WHERE \{matches})"

///|
fn value(row : Map[String, Json], name : String) -> Json {
  match row.get(name) {
    Some(j) => j
    None => Json::null()
  }
}

///|
/// A walk over the sessions recorded in `table`'s one row (id 1): one batch of at most `limit`; whether it is done.
fn walk(db : @sql.Db, table : String, meta : Map[String, Json], limit : Int) -> Bool raise {
  if meta.get("complete") is Some(Number(1.0, ..)) {
    return true
  }
  let last = value(meta, "last_rowid")
  let end = value(meta, "end_rowid")
  let lim = Json::number(limit.to_double())
  let rows = if last is Null { db.all(first, [end, lim]) } else { db.all(next, [last, end, lim]) }
  for row in rows {
    ignore(db.run(see_position, [value(row, "position")]))
  }
  let done = rows.length() < limit
  let reached = match rows.last() {
    Some(row) => value(row, "position")
    None => last
  }
  ignore(
    db.run("UPDATE \{table} SET last_rowid = CAST(? AS INTEGER), complete = ? WHERE id = 1", [
      reached,
      Json::number(if done { 1.0 } else { 0.0 }),
    ]),
  )
  done
}

///|
fn meta_of(db : @sql.Db, table : String) -> Map[String, Json]? raise {
  match
    db.all(
      "SELECT version, CAST(last_rowid AS TEXT) AS last_rowid, CAST(end_rowid AS TEXT) AS end_rowid, complete FROM \{table} WHERE id = 1",
      [],
    ) {
    [m, ..] => Some(m)
    _ => None
  }
}

///|
fn list_meta(db : @sql.Db) -> Map[String, Json] raise {
  guard meta_of(db, "session_list_meta") is Some(meta) else {
    fail("session list index version marker is missing")
  }
  match meta.get("version") {
    Some(Number(v, ..)) if v.to_int() == version => ()
    _ => fail("session list index version \{value(meta, "version").stringify()} is incompatible with \{version}")
  }
  meta
}

///|
/// One batch of at most `limit` old sessions; whether all are copied then.
pub fn step(db : @sql.Db, limit? : Int = 256) -> Bool raise {
  db.exec("BEGIN IMMEDIATE")
  errdefer (db.exec("ROLLBACK") catch { _ => () })
  let done = walk(db, "session_list_meta", list_meta(db), limit)
  db.exec("COMMIT")
  done
}

///|
/// One batch of at most `limit` sessions visited again for search, once the list is prepared; whether all are then.
pub fn audit(db : @sql.Db, limit? : Int = 256) -> Bool raise {
  db.exec("BEGIN IMMEDIATE")
  errdefer (db.exec("ROLLBACK") catch { _ => () })
  if !(list_meta(db).get("complete") is Some(Number(1.0, ..))) {
    db.exec("COMMIT")
    return false
  }
  db.exec(
    "CREATE TABLE IF NOT EXISTS search_job_session_audit (id INTEGER PRIMARY KEY CHECK (id = 1), version INTEGER NOT NULL, last_rowid INTEGER, end_rowid INTEGER, complete INTEGER NOT NULL) WITHOUT ROWID; INSERT INTO search_job_session_audit (id, version, last_rowid, end_rowid, complete) SELECT 1, 1, NULL, (SELECT rowid FROM sessions ORDER BY rowid DESC LIMIT 1), NOT EXISTS (SELECT 1 FROM sessions LIMIT 1) WHERE NOT EXISTS (SELECT 1 FROM search_job_session_audit WHERE id = 1)",
  )
  guard meta_of(db, "search_job_session_audit") is Some(meta) else {
    fail("search job session audit is missing")
  }
  match meta.get("version") {
    Some(Number(1.0, ..)) => ()
    _ => fail("search job session audit version \{value(meta, "version").stringify()} is incompatible with 1")
  }
  let done = walk(db, "search_job_session_audit", meta, limit)
  db.exec("COMMIT")
  done
}
