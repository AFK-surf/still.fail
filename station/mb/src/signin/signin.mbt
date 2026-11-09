// The sign-in each save decision names (station/src/vault/signin-save-index.ts): an older session's sign-ins put in
// the lookup in bounded steps, by status and rowid, as `stepSigninSaveIndex` does, here for the MoonBit builder.

///|
fn get(row : Map[String, Json], name : String) -> Json {
  row.get(name).unwrap_or(Json::null())
}

///|
/// At most `limit` of `session`'s old sign-ins put in the lookup, with the cursor; whether all are then.
pub fn step(db : @sql.Db, session : String, limit? : Int = 64) -> Bool raise {
  guard limit >= 1 else { raise Failure("sign-in index batch must be positive") }
  let s = Json::string(session)
  let lim = Json::number(limit.to_double())
  db.exec("BEGIN IMMEDIATE")
  errdefer (db.exec("ROLLBACK") catch { _ => () })
  ignore(
    db.run(
      "INSERT INTO signin_save_progress (session, status, row, done) SELECT ?, NULL, NULL, 0 WHERE NOT EXISTS (SELECT 1 FROM signin_save_progress WHERE session = ?)",
      [s, s],
    ),
  )
  guard db.all("SELECT status, CAST(row AS TEXT) AS row, done FROM signin_save_progress WHERE session = ?", [s])
    is [state, ..] else {
    raise Failure("sign-in index progress is missing")
  }
  if get(state, "done") is Number(1.0, ..) {
    db.exec("COMMIT")
    return true
  }
  let cols = "status, CAST(rowid AS TEXT) AS row"
  let order = "ORDER BY status, signin_asks.rowid"
  let rows = if get(state, "status") is Null {
    db.all("SELECT \{cols} FROM signin_asks INDEXED BY signin_asks_by_session WHERE session = ?1 \{order} LIMIT ?2", [s, lim])
  } else {
    // (the rest of that status's rowids first, then the next statuses: a tuple comparison would walk the earlier ones)
    let found = db.all(
      "SELECT \{cols} FROM signin_asks INDEXED BY signin_asks_by_session WHERE session = ?1 AND status = ?3 AND rowid > CAST(?4 AS INTEGER) \{order} LIMIT ?2",
      [s, lim, get(state, "status"), get(state, "row")],
    )
    if found.length() < limit {
      found.append(
        db.all(
          "SELECT \{cols} FROM signin_asks INDEXED BY signin_asks_by_session WHERE session = ?1 AND status > ?3 \{order} LIMIT ?2",
          [s, Json::number((limit - found.length()).to_double()), get(state, "status")],
        ),
      )
    }
    found
  }
  for row in rows {
    ignore(
      db.run(
        "INSERT INTO signin_save_lookup (ask, session, save) SELECT id, session, json_extract(body, '$.save') FROM signin_asks WHERE rowid = CAST(?1 AS INTEGER) AND json_type(body, '$.save') = 'text' AND NOT EXISTS (SELECT 1 FROM signin_save_lookup l WHERE l.ask = signin_asks.id)",
        [get(row, "row")],
      ),
    )
  }
  let done = rows.length() < limit
  let (status, at) = match rows.last() {
    Some(r) => (get(r, "status"), get(r, "row"))
    None => (get(state, "status"), get(state, "row"))
  }
  ignore(
    db.run("UPDATE signin_save_progress SET status = ?, row = CAST(? AS INTEGER), done = ? WHERE session = ?", [
      status,
      at,
      Json::number(if done { 1.0 } else { 0.0 }),
      s,
    ]),
  )
  db.exec("COMMIT")
  done
}
