// A session's exact count of turns (station/src/store/turn-state.ts): counted in short indexed slices from the
// newest back, a guard in the database that the session's writes invalidate, the count published only by a last
// write that finds its guard still there, as `turnCountStep` does, here for the MoonBit builder. Only the writes take
// the backfill permit (`may_write`): the slices read without it.

///|
pub let batch : Int = 64

///|
let first : String = "SELECT started_at, rowid AS rid FROM turns INDEXED BY turns_by_session WHERE session_key = ?1 AND started_at = ?2 AND rowid <= ?3 ORDER BY rowid DESC LIMIT ?4"

///|
let after : String = "SELECT started_at, rowid AS rid FROM turns INDEXED BY turns_by_session WHERE session_key = ?1 AND started_at = ?2 AND rowid < ?3 ORDER BY rowid DESC LIMIT ?4"

///|
let earlier : String = "SELECT started_at, rowid AS rid FROM turns INDEXED BY turns_by_session WHERE session_key = ?1 AND started_at < ?2 ORDER BY started_at DESC, rowid DESC LIMIT ?3"

///|
let tail_same : String = "SELECT started_at, rowid AS rid FROM turns INDEXED BY turns_by_session WHERE session_key = ?1 AND started_at = ?2 AND rowid > ?3 ORDER BY rowid LIMIT ?4"

///|
let tail_newer : String = "SELECT started_at, rowid AS rid FROM turns INDEXED BY turns_by_session WHERE session_key = ?1 AND started_at > ?2 ORDER BY started_at, rowid LIMIT ?3"

///|
/// A turn's place: when it started and its rowid.
priv struct Position {
  at : Json
  rid : Json
}

///|
fn position(row : Map[String, Json]) -> Position {
  {
    at: row.get("started_at").unwrap_or(Json::null()),
    rid: row.get("rid").unwrap_or(Json::null()),
  }
}

///|
/// A count under way: its guard's token, how many so far, where it began (the newest turn then) and how far back.
pub struct Scan {
  priv session : String
  priv token : String
  priv mut n : Int
  priv mut boundary : Position
  priv mut after : Position?
  priv mut finished : Bool
}

///|
pub fn Scan::token(self : Scan) -> String {
  self.token
}

///|
/// One step of `session`'s count from `scan` (None: none begun); whether it is counted, and the scan to go on with.
/// `token` names a new guard; `may_write` takes the permit before each write (false: not now).
pub async fn step(
  db : @sql.Db,
  session : String,
  scan : Scan?,
  token~ : () -> String,
  may_write~ : async () -> Bool,
  limit? : Int = batch,
) -> (Bool, Scan?) {
  guard limit >= 1 && limit <= batch else { fail("turn count batch must be between 1 and 64") }
  let s = Json::string(session)
  let counted = () => db.all("SELECT 1 FROM session_turns WHERE session = ?", [s]).length() > 0
  let has_turns = () => db.all(
      "SELECT 1 FROM turns INDEXED BY turns_by_session WHERE session_key = ? LIMIT 1",
      [s],
    ).length() >
    0
  guard scan is Some(scan) else {
    if counted() || !has_turns() {
      return (true, None)
    }
    if !may_write() {
      return (false, None)
    }
    db.exec("BEGIN IMMEDIATE")
    errdefer (db.exec("ROLLBACK") catch { _ => () })
    if counted() || !has_turns() {
      db.exec("COMMIT")
      return (true, None)
    }
    let token = token()
    guard db.all(
        "SELECT started_at, rowid AS rid FROM turns INDEXED BY turns_by_session WHERE session_key = ? ORDER BY started_at DESC, rowid DESC LIMIT 1",
        [s],
      )
      is [latest, ..] else {
      fail("turn count found no turn")
    }
    let boundary = position(latest)
    ignore(
      db.run(
        "INSERT INTO session_turns_guard(session, token, boundary_at, boundary_rowid) VALUES (?, ?, ?, ?) ON CONFLICT(session) DO UPDATE SET token = excluded.token, boundary_at = excluded.boundary_at, boundary_rowid = excluded.boundary_rowid",
        [s, Json::string(token), boundary.at, boundary.rid],
      ),
    )
    db.exec("COMMIT")
    return (false, Some({ session, token, n: 0, boundary, after: None, finished: false }))
  }
  guard scan.session == session else { fail("turn count belongs to another session") }
  let guarded = () => db.all("SELECT token FROM session_turns_guard WHERE session = ?", [s]) is [g, ..] &&
    g.get("token") == Some(Json::string(scan.token))
  if !guarded() {
    return (false, None)
  }
  let lim = (n : Int) => Json::number(n.to_double())
  let mut visited = 0
  if !scan.finished {
    let before = scan.after.unwrap_or(scan.boundary)
    let rows = db.all(if scan.after is None { first } else { after }, [s, before.at, before.rid, lim(limit)])
    if rows.length() < limit {
      for row in db.all(earlier, [s, before.at, lim(limit - rows.length())]) {
        rows.push(row)
      }
    }
    visited = rows.length()
    scan.n += visited
    if rows.last() is Some(last) {
      scan.after = Some(position(last))
    }
    scan.finished = rows.length() < limit
  }
  if !scan.finished || visited > 0 || !may_write() {
    return (false, Some(scan))
  }
  db.exec("BEGIN IMMEDIATE")
  errdefer (db.exec("ROLLBACK") catch { _ => () })
  if !guarded() {
    db.exec("COMMIT")
    return (false, None)
  }
  let tail = db.all(tail_same, [s, scan.boundary.at, scan.boundary.rid, lim(limit)])
  if tail.length() < limit {
    for row in db.all(tail_newer, [s, scan.boundary.at, lim(limit - tail.length())]) {
      tail.push(row)
    }
  }
  let count = scan.n + tail.length()
  if tail.length() == limit {
    let boundary = position(tail[tail.length() - 1])
    ignore(
      db.run("UPDATE session_turns_guard SET boundary_at=?, boundary_rowid=? WHERE session=? AND token=?", [
        boundary.at,
        boundary.rid,
        s,
        Json::string(scan.token),
      ]),
    )
    db.exec("COMMIT")
    scan.n = count
    scan.boundary = boundary
    return (false, Some(scan))
  }
  if count > 0 {
    ignore(db.run("INSERT INTO session_turns (session, n) VALUES (?, ?)", [s, Json::number(count.to_double())]))
  }
  ignore(db.run("DELETE FROM session_turns_guard WHERE session = ? AND token = ?", [s, Json::string(scan.token)]))
  db.exec("COMMIT")
  (true, None)
}
