// Whether the statistics the station keeps are complete for a reader, without filling old history
// (station/src/usage/minute-worker.ts): the minutes, the remote tasks, the details (`usageDetailReady`) and the chats
// and cards (`usageChatStatsReady`), each for a viewer (`{workspace, home}`, or none: every workspace), here for the
// MoonBit checker.

///|
fn installed(db : @sql.Db, name : String) -> Bool raise {
  db.all("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", [Json::string(name)]).length() > 0
}

///|
fn one_is(db : @sql.Db, sql : String, params : Array[Json], column : String, n : Double) -> Bool raise {
  match db.all(sql, params) {
    [r, ..] => r.get(column) is Some(Number(v, ..)) && v == n
    _ => false
  }
}

///|
fn some(db : @sql.Db, sql : String, params : Array[Json]) -> Bool raise {
  db.all(sql, params).length() > 0
}

///|
pub fn minutes_ready(db : @sql.Db) -> Bool raise {
  !installed(db, "usage_minute_all") || one_is(db, "SELECT done FROM usage_minute_all WHERE id = 1", [], "done", 1.0)
}

///|
pub fn remote_ready(db : @sql.Db) -> Bool raise {
  !installed(db, "remote_run_progress") ||
  one_is(db, "SELECT done FROM remote_run_progress WHERE id = 1", [], "done", 1.0)
}

///|
/// A viewer's workspace and whether it is the home one, from `{workspace, home}`; None for none.
fn viewer(v : Json) -> (String, Bool)? {
  match v {
    { "workspace": String(ws), "home": home, .. } => Some((ws, !(home is False)))
    { "workspace": String(ws), .. } => Some((ws, true))
    _ => None
  }
}

///|
fn retired(db : @sql.Db) -> Bool raise {
  installed(db, "usage_retired_detail")
}

///|
/// `usageDetailReady` as the minute worker asks it (behind its retired check, and with no detail kept: complete).
pub fn detail_ready(db : @sql.Db, v : Json) -> Bool raise {
  if retired(db) {
    return false
  }
  if !installed(db, "usage_detail_all") {
    return true
  }
  if installed(db, "usage_compact_since") {
    return false
  }
  let table = if installed(db, "usage_detail_live_since") { "usage_detail_live" } else { "usage_detail" }
  if one_is(db, "SELECT done FROM \{table}_all WHERE id = 1", [], "done", 1.0) {
    return true
  }
  guard viewer(v) is Some((ws, home)) && !home else { return false }
  some(db, "SELECT 1 FROM \{table}_ready WHERE ws = ?", [Json::string(ws)]) &&
  !some(db, "SELECT session FROM \{table}_scope INDEXED BY \{table}_scope_ws WHERE ws = ? AND done = 0 LIMIT 1", [
    Json::string(ws),
  ])
}

///|
/// `usageChatStatsReady` as the minute worker asks it (no chat statistics kept: complete).
pub fn chats_ready(db : @sql.Db, v : Json) -> Bool raise {
  if !installed(db, "usage_chat_progress") {
    return true
  }
  if installed(db, "card_outcomes_incomplete") {
    return false
  }
  if !one_is(db, "SELECT done FROM usage_chat_progress WHERE id = 1", [], "done", 1.0) {
    return false
  }
  guard viewer(v) is Some((ws, home)) else { return !some(db, "SELECT 1 FROM usage_chat_dirty LIMIT 1", []) }
  if some(db, "SELECT 1 FROM usage_chat_dirty_scope WHERE kind = 2 AND ws = ? LIMIT 1", [Json::string(ws)]) {
    return false
  }
  !home || !some(db, "SELECT 1 FROM usage_chat_dirty_scope WHERE kind = 1 AND ws = '' LIMIT 1", [])
}

///|
/// Every statistic complete for every workspace: the checker is not needed until a session moves.
pub fn complete(db : @sql.Db) -> Bool raise {
  minutes_ready(db) && remote_ready(db) && detail_ready(db, Json::null()) && chats_ready(db, Json::null())
}
