// A session's running jobs and services waiting to restart (station/src/store/session-up-jobs.ts): the old jobs of a
// session prepared in bounded batches, as `sessionUpJobsStep` does, here for the MoonBit builder.

///|
let version : Int = 1

///|
let up : String = "(j.state = 'running' OR (j.state = 'exited' AND j.port IS NOT NULL))"

///|
let first : String = "SELECT CAST(rowid AS TEXT) AS position FROM jobs INDEXED BY jobs_by_session WHERE session_key = ? AND rowid <= CAST(? AS INTEGER) ORDER BY rowid LIMIT ?"

///|
let next : String = "SELECT CAST(rowid AS TEXT) AS position FROM jobs INDEXED BY jobs_by_session WHERE session_key = ? AND rowid > CAST(? AS INTEGER) AND rowid <= CAST(? AS INTEGER) ORDER BY rowid LIMIT ?"

///|
fn value(row : Map[String, Json], name : String) -> Json {
  match row.get(name) {
    Some(j) => j
    None => Json::null()
  }
}

///|
/// Whether the session's are prepared (all are, on a station that had none running when its index was made).
fn ready(db : @sql.Db, session : String) -> Bool raise {
  let meta = db.all("SELECT version, fresh FROM session_up_job_meta WHERE id = 1", [])
  guard meta is [meta, ..] && meta.get("version") is Some(Number(v, ..)) && v.to_int() == version else {
    let had = match meta {
      [m, ..] => value(m, "version").stringify()
      _ => "missing"
    }
    fail("session up jobs index version \{had} is incompatible with \{version}")
  }
  if meta.get("fresh") is Some(Number(1.0, ..)) {
    return true
  }
  let scope = db.all("SELECT complete FROM session_up_job_scopes WHERE session = ?", [Json::string(session)])
  scope is [s, ..] && s.get("complete") is Some(Number(1.0, ..))
}

///|
/// One batch of at most `limit` of `session`'s old jobs; whether all of its are prepared then.
pub fn step(db : @sql.Db, session : String, limit? : Int = 256) -> Bool raise {
  db.exec("BEGIN IMMEDIATE")
  // (what failed is let go: nothing of a batch is kept but whole)
  errdefer (db.exec("ROLLBACK") catch { _ => () })
  if ready(db, session) {
    db.exec("COMMIT")
    return true
  }
  let s = Json::string(session)
  ignore(
    db.run(
      "INSERT INTO session_up_job_scopes (session, last_rowid, end_rowid, complete) SELECT ?, NULL, (SELECT rowid FROM jobs INDEXED BY jobs_by_session WHERE session_key = ? ORDER BY rowid DESC LIMIT 1), 0 WHERE NOT EXISTS (SELECT 1 FROM session_up_job_scopes WHERE session = ?)",
      [s, s, s],
    ),
  )
  let scope = db.all(
    "SELECT CAST(last_rowid AS TEXT) AS last_rowid, CAST(end_rowid AS TEXT) AS end_rowid FROM session_up_job_scopes WHERE session = ?",
    [s],
  )
  guard scope is [scope, ..] else { fail("session up jobs scope is missing") }
  let last = value(scope, "last_rowid")
  let end = value(scope, "end_rowid")
  let lim = Json::number(limit.to_double())
  let rows = if last is Null { db.all(first, [s, end, lim]) } else { db.all(next, [s, last, end, lim]) }
  let put = "INSERT INTO session_up_job_rows (session, job_rowid) SELECT j.session_key, j.rowid FROM jobs j WHERE j.rowid = CAST(? AS INTEGER) AND \{up} AND NOT EXISTS (SELECT 1 FROM session_up_job_rows i WHERE i.session = j.session_key AND i.job_rowid = j.rowid)"
  for row in rows {
    ignore(db.run(put, [value(row, "position")]))
  }
  let done = rows.length() < limit
  let reached = match rows.last() {
    Some(row) => value(row, "position")
    None => last
  }
  ignore(
    db.run("UPDATE session_up_job_scopes SET last_rowid = CAST(? AS INTEGER), complete = ? WHERE session = ?", [
      reached,
      Json::number(if done { 1.0 } else { 0.0 }),
      s,
    ]),
  )
  db.exec("COMMIT")
  done
}
