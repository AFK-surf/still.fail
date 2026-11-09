// What the station prepares after a handover for its sessions (station/src/sessions/workspace-activity-builder.ts),
// here for the MoonBit builder: a workspace's active sessions (store/workspace-activity.ts), the sessions whose last
// turn a restart may take up (recover-waits.ts) and their waits by expiry (awake-waits.ts), each brought across from
// an older store in bounded transactions as its `…Step` does; the triggers keep what writers change meanwhile.

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
fn complete(row : Map[String, Json]) -> Bool {
  get(row, "complete") is Number(1.0, ..)
}

///|
fn flag(b : Bool) -> Json {
  Json::number(if b { 1.0 } else { 0.0 })
}

///|
fn write(db : @sql.Db, f : () -> Bool raise) -> Bool raise {
  db.exec("BEGIN IMMEDIATE")
  errdefer (db.exec("ROLLBACK") catch { _ => () })
  let result = f()
  db.exec("COMMIT")
  result
}

// The active sessions of a workspace.

///|
fn active(key : String) -> String {
  "EXISTS (SELECT 1 FROM sessions z WHERE z.key = \{key} AND (z.running = 1 OR EXISTS (SELECT 1 FROM deliveries d INDEXED BY deliveries_pending WHERE d.session = z.key AND d.delivered_at IS NULL) OR EXISTS (SELECT 1 FROM letter_deliveries d INDEXED BY letter_deliveries_pending WHERE d.session = z.key AND d.delivered_at IS NULL)))"
}

///|
let add_active : String = "INSERT INTO workspace_activity (ws, session) SELECT s.ws, s.key FROM sessions s WHERE s.key = ?1 AND s.ws IS NOT NULL AND \{active("s.key")} AND NOT EXISTS (SELECT 1 FROM workspace_activity a WHERE a.ws = s.ws AND a.session = s.key)"

///|
/// The next active key after the cursor (`after`; none: the first), of the running sessions and the pending deliveries
/// and letters, each sought in its index, the least of them in SQLite's order (`byBytes`).
fn next_active(after : Bool) -> String {
  let (key, session) = if after { (" AND key > ?1", " AND session > ?1") } else { ("", "") }
  "SELECT MIN(session) AS session FROM (SELECT (SELECT key FROM sessions INDEXED BY sessions_running WHERE running = 1\{key} ORDER BY key LIMIT 1) AS session UNION ALL SELECT (SELECT session FROM deliveries INDEXED BY deliveries_pending WHERE delivered_at IS NULL\{session} ORDER BY session LIMIT 1) UNION ALL SELECT (SELECT session FROM letter_deliveries INDEXED BY letter_deliveries_pending WHERE delivered_at IS NULL\{session} ORDER BY session LIMIT 1))"
}

///|
/// At most `limit` active keys of an older store brought across, with the cursor (`workspaceActivityStep`).
pub fn activity_step(db : @sql.Db, limit? : Int = 64) -> Bool raise {
  write(db, () => {
    guard first(db, "SELECT cursor, complete FROM workspace_activity_meta WHERE id = 1", []) is Some(meta) else {
      raise Failure("workspace activity metadata is missing")
    }
    if complete(meta) {
      return true
    }
    let mut cursor = get(meta, "cursor")
    let mut visited = 0
    let mut done = false
    while visited < limit {
      let key = match first(db, next_active(!(cursor is Null)), if cursor is Null { [] } else { [cursor] }) {
        Some(r) => get(r, "session")
        None => Json::null()
      }
      if key is Null {
        done = true
        break
      }
      ignore(db.run(add_active, [key]))
      cursor = key
      visited += 1
    }
    ignore(db.run("UPDATE workspace_activity_meta SET cursor = ?, complete = ? WHERE id = 1", [cursor, flag(done)]))
    done
  })
}

// The sessions a restart may take up, and their waits.

///|
let half_safe : String = "2251799813685247"

///|
let second_limit : String = "2251799813685"

///|
let uncertain : String = "-9007199254740991"

///|
/// A session's latest waiting turn's expiry (`awakeDeadline`).
fn awake_deadline(key : String) -> String {
  "(SELECT CASE WHEN typeof(t.ended_at) = 'integer' AND t.ended_at BETWEEN -\{half_safe} AND \{half_safe} AND (t.wait_seconds IS NULL OR (typeof(t.wait_seconds) = 'integer' AND t.wait_seconds BETWEEN -\{second_limit} AND \{second_limit})) THEN t.ended_at + COALESCE(t.wait_seconds, 0) * 1000 ELSE \{uncertain} END FROM sessions s CROSS JOIN turns t ON t.rowid = (SELECT rowid FROM turns INDEXED BY turns_by_session WHERE session_key = s.key ORDER BY started_at DESC, rowid DESC LIMIT 1) WHERE s.key = \{key} AND s.archived_at IS NULL AND s.running != 1 AND t.ended_at IS NOT NULL AND t.declared = 'waiting')"
}

///|
let sync_awake : String = "UPDATE session_recover_waits SET awake_deadline = \{awake_deadline("?1")} WHERE session = ?1 AND (1) AND awake_deadline IS NOT \{awake_deadline("?1")}"

///|
let wanted : String = "EXISTS (SELECT 1 FROM sessions s WHERE s.key = ?1 AND s.archived_at IS NULL AND s.running != 1) AND EXISTS (SELECT 1 FROM turns t WHERE t.rowid = (SELECT rowid FROM turns INDEXED BY turns_by_session WHERE session_key = ?1 ORDER BY started_at DESC, rowid DESC LIMIT 1) AND t.ended_at IS NOT NULL AND (t.declared = 'waiting' OR (t.outcome = 'failed' AND substr(t.detail, 1, 11) = 'rate_limit:')))"

///|
let drop_recovery : String = "DELETE FROM session_recover_waits WHERE session = ?1 AND (1) AND NOT (\{wanted})"

///|
let put_recovery : String = "INSERT INTO session_recover_waits (session, awake_deadline) SELECT ?1, \{awake_deadline("?1")} WHERE (1) AND \{wanted} AND NOT EXISTS (SELECT 1 FROM session_recover_waits WHERE session = ?1)"

///|
/// A walk over `table`'s keys (`column`) by the cursor of `meta`, at most `limit` of them each given to `each`.
fn walk(
  db : @sql.Db,
  meta_table : String,
  table : String,
  column : String,
  limit : Int,
  before? : (Map[String, Json]) -> Bool raise = _ => true,
  each : (Json) -> Unit raise,
) -> Bool raise {
  write(db, () => {
    guard first(db, "SELECT cursor, complete FROM \{meta_table} WHERE id = 1", []) is Some(meta) else {
      raise Failure("\{meta_table} has no row")
    }
    if complete(meta) {
      return true
    }
    if !before(meta) {
      return false
    }
    let cursor = get(meta, "cursor")
    let lim = Json::number(limit.to_double())
    let rows = if cursor is Null {
      db.all("SELECT \{column} AS k FROM \{table} ORDER BY \{column} LIMIT ?", [lim])
    } else {
      db.all("SELECT \{column} AS k FROM \{table} WHERE \{column} > ? ORDER BY \{column} LIMIT ?", [cursor, lim])
    }
    for row in rows {
      each(get(row, "k"))
    }
    let done = rows.length() < limit
    let reached = match rows.last() {
      Some(r) => get(r, "k")
      None => cursor
    }
    ignore(db.run("UPDATE \{meta_table} SET cursor = ?, complete = ? WHERE id = 1", [reached, flag(done)]))
    done
  })
}

///|
/// At most `limit` existing sessions' recovery waits filled in (`recoverWaitsStep`).
pub fn recovery_step(db : @sql.Db, limit? : Int = 64) -> Bool raise {
  walk(db, "session_recover_wait_meta", "sessions", "key", limit, key => {
    ignore(db.run(drop_recovery, [key]))
    ignore(db.run(put_recovery, [key]))
  })
}

///|
/// At most `limit` recovery waits' expiry filled in, once the recovery waits are all there (`awakeWaitsStep`).
pub fn awake_step(db : @sql.Db, limit? : Int = 64) -> Bool raise {
  walk(
    db,
    "session_awake_wait_meta",
    "session_recover_waits",
    "session",
    limit,
    before=_ => match first(db, "SELECT complete FROM session_recover_wait_meta WHERE id = 1", []) {
      Some(r) => complete(r)
      None => false
    },
    key => ignore(db.run(sync_awake, [key])),
  )
}
