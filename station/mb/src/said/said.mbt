// What the sidebar shows of a chat: the latest message not by the latest person (station/src/store/said-state.ts). An
// old chat's is found by reading back from its newest message in small slices, a guard the chat's writes invalidate,
// and published by a last write that finds its guard, as `saidScanStep` does on a store without the legacy lookup,
// here for the MoonBit builder. Only the writes take the backfill permit (`may_write`).

///|
pub let batch : Int = 64

///|
let latest_sql : String = "SELECT n, author_kind, author FROM entries INDEXED BY entries_said WHERE thread = ?1 AND kind = 'message' AND letter IS NULL ORDER BY n DESC LIMIT 1"

///|
let state_sql : String = "SELECT s.said_n, s.said_other_n, s.said_other_known, g.author AS guard_author, g.other_n AS guard_other_n, g.ready AS guard_ready FROM thread_state s LEFT JOIN said_state_guard g ON g.thread = s.thread WHERE s.thread = ?1 UNION ALL SELECT NULL, NULL, NULL, g.author, g.other_n, g.ready FROM said_state_guard g WHERE g.thread = ?1 AND NOT EXISTS (SELECT 1 FROM thread_state s WHERE s.thread = ?1) LIMIT 1"

///|
let scan_sql : String = "SELECT n, author_kind, author FROM entries INDEXED BY entries_said WHERE thread = ?1 AND kind = 'message' AND letter IS NULL AND n < ?2 ORDER BY n DESC LIMIT ?3"

///|
fn value(row : Map[String, Json], name : String) -> Json {
  row.get(name).unwrap_or(Json::null())
}

///|
/// Whether the store reads its messages through the legacy lookup (`hasLegacySaid`): this builder does not; the
/// worker does.
pub fn legacy(db : @sql.Db) -> Bool raise {
  db.all("SELECT 1 FROM sqlite_master WHERE type='view' AND name='legacy_said'", []).length() > 0
}

///|
/// Whether the boundary is known for `latest` from the chat's state or a finished guard (`saidBoundary`).
fn known(state : Map[String, Json]?, latest : Map[String, Json]) -> Bool {
  if value(latest, "author_kind") != Json::string("person") {
    return true
  }
  guard state is Some(s) else { return false }
  (value(s, "said_n") == value(latest, "n") && value(s, "said_other_known") == Json::number(1.0)) ||
  (value(s, "guard_ready") == Json::number(1.0) && value(s, "guard_author") == value(latest, "author"))
}

///|
/// A search under way: the chat, the latest person's name, its guard's token, how far back it has read, and what it
/// found (the newest message by another, or none: `Some(Null)`).
pub struct Scan {
  priv thread : Int64
  priv author : Json
  priv token : String
  priv mut before : Json
  priv mut found : Json?
}

///|
pub fn Scan::token(self : Scan) -> String {
  self.token
}

///|
fn first_row(db : @sql.Db, sql : String, params : Array[Json]) -> Map[String, Json]? raise {
  match db.all(sql, params) {
    [r, ..] => Some(r)
    _ => None
  }
}

///|
/// One step of `thread`'s search from `scan` (None: none begun); whether it is known, and the scan to go on with.
pub async fn step(
  db : @sql.Db,
  thread : Int64,
  scan : Scan?,
  token~ : () -> String,
  may_write~ : async () -> Bool,
  limit? : Int = batch,
) -> (Bool, Scan?) {
  guard limit >= 1 && limit <= batch else { fail("said scan batch must be between 1 and 64") }
  let t = Json::number(thread.to_double())
  let latest = () => first_row(db, latest_sql, [t])
  let state = () => first_row(db, state_sql, [t])
  guard scan is Some(scan) else {
    // (the check and the read in one snapshot: an old writer's changes between them are seen together)
    db.exec("SAVEPOINT said_scan")
    let (head, boundary_known) = {
      defer (db.exec("RELEASE said_scan") catch { _ => () })
      let head = latest()
      (head, head is Some(h) && known(state(), h))
    }
    if head is None || boundary_known {
      return (true, None)
    }
    if !may_write() {
      return (false, None)
    }
    db.exec("BEGIN IMMEDIATE")
    errdefer (db.exec("ROLLBACK") catch { _ => () })
    let current = latest()
    guard current is Some(current) && !known(state(), current) else {
      db.exec("COMMIT")
      return (true, None)
    }
    let token = token()
    ignore(
      db.run(
        "INSERT INTO said_state_guard(thread,token,author,other_n,ready) VALUES (?,?,?,NULL,0) ON CONFLICT(thread) DO UPDATE SET token=excluded.token,author=excluded.author,other_n=NULL,ready=0",
        [t, Json::string(token), value(current, "author")],
      ),
    )
    db.exec("COMMIT")
    return (
      false,
      Some({ thread, token, author: value(current, "author"), before: value(current, "n"), found: None }),
    )
  }
  guard scan.thread == thread else { fail("said scan belongs to another chat") }
  let guarded = () => first_row(db, "SELECT token FROM said_state_guard WHERE thread=?", [t]) is Some(g) &&
    value(g, "token") == Json::string(scan.token)
  db.exec("SAVEPOINT said_scan")
  let rows = {
    defer (db.exec("RELEASE said_scan") catch { _ => () })
    if !guarded() {
      None
    } else if scan.found is None {
      Some(db.all(scan_sql, [t, scan.before, Json::number(limit.to_double())]))
    } else {
      Some([])
    }
  }
  guard rows is Some(rows) else { return (false, None) }
  if scan.found is None {
    let other = rows.iter().find_first(r => value(r, "author_kind") != Json::string("person") ||
      value(r, "author") != scan.author)
    match other {
      Some(o) => scan.found = Some(value(o, "n"))
      None =>
        if rows.length() < limit {
          scan.found = Some(Json::null())
        } else {
          scan.before = value(rows[rows.length() - 1], "n")
        }
    }
  }
  guard scan.found is Some(found) else { return (false, Some(scan)) }
  if !may_write() {
    return (false, Some(scan))
  }
  db.exec("BEGIN IMMEDIATE")
  errdefer (db.exec("ROLLBACK") catch { _ => () })
  if !guarded() {
    db.exec("COMMIT")
    return (false, None)
  }
  let current = latest()
  if current is Some(c) &&
    (value(c, "author_kind") != Json::string("person") || value(c, "author") != scan.author) {
    db.exec("COMMIT")
    return (false, None)
  }
  let tok = Json::string(scan.token)
  match current {
    None => ignore(db.run("DELETE FROM said_state_guard WHERE thread=? AND token=?", [t, tok]))
    Some(c) => {
      let wrote = db.run("UPDATE thread_state SET said_other_n=?, said_other_known=1 WHERE thread=? AND said_n=?", [
        found,
        t,
        value(c, "n"),
      ])
      if wrote > 0 {
        ignore(db.run("DELETE FROM said_state_guard WHERE thread=? AND token=?", [t, tok]))
      } else {
        ignore(
          db.run("UPDATE said_state_guard SET author=?, other_n=?, ready=1 WHERE thread=? AND token=?", [
            scan.author,
            found,
            t,
            tok,
          ]),
        )
      }
    }
  }
  db.exec("COMMIT")
  (true, None)
}
