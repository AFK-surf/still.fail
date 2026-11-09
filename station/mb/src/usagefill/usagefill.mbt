// What the station does once the previous station has left its usage statistics (station/src/usage/retire-worker.ts):
// the retired per-call indexes freed in bounded deletes (store/usage-retire.ts `dropUsageIndexStep`), then the calls
// from before the compact statistics began taken in, newest first, whole quarters at a time (store/usage-fill.ts
// `fillUsageStep`), here for the MoonBit builder.

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
fn quote(name : String) -> String {
  "\"" + name.replace_all(old="\"", new="\"\"") + "\""
}

///|
/// One bounded delete of a retired index table, by its primary key; the table dropped once empty (`dropUsageIndexStep`).
/// Whether none is left.
pub fn drop_step(db : @sql.Db, batch? : Int = 256) -> Bool raise {
  guard first(
      db,
      "SELECT name FROM sqlite_master WHERE type = 'table' AND (name = 'usage_detail' OR name GLOB 'usage_detail_*' OR name = 'usage_main_calls') ORDER BY name LIMIT 1",
      [],
    )
    is Some(row) &&
    get(row, "name") is String(table) else {
    return true
  }
  let columns = db.all("PRAGMA table_info(\{quote(table)})", [])
  let keyed = columns.filter(c => get(c, "pk") is Number(p, ..) && p > 0)
  keyed.sort_by((a, b) => {
    let pa = match get(a, "pk") {
      Number(p, ..) => p
      _ => 0.0
    }
    let pb = match get(b, "pk") {
      Number(p, ..) => p
      _ => 0.0
    }
    pa.compare(pb)
  })
  let keys = keyed.map(c => match get(c, "name") {
    String(n) => quote(n)
    _ => "rowid"
  })
  if keys.length() == 0 {
    keys.push("rowid")
  }
  let tuple = if keys.length() == 1 { keys[0] } else { "(" + keys.join(", ") + ")" }
  let removed = db.run(
    "DELETE FROM \{quote(table)} WHERE \{tuple} IN (SELECT \{keys.join(", ")} FROM \{quote(table)} LIMIT ?)",
    [Json::number(batch.to_double())],
  )
  if removed == 0 {
    db.exec("DROP TABLE IF EXISTS \{quote(table)}")
  }
  false
}

// The fill (usage-fill.ts) and what it uses of the compact statistics (usage-compact.ts) and the year (usage-history.ts).

///|
let quarter_ms : Int = 900000

///|
let context_columns : Array[String] = [
  "id", "at", "session", "turn", "profile", "runtime", "model", "subagent", "fast", "context", "context_window", "cache_write",
  "cache_write_long",
]

///|
fn invalidate_context(session : String) -> String {
  "UPDATE usage_totals SET compact_context = NULL WHERE session = \{session} AND (1) AND (runtime, model, fast) = (SELECT context_runtime, context_model, context_fast FROM usage_minute_scope WHERE session = \{session}) AND compact_context IS NOT NULL; UPDATE usage_minute_scope SET context_runtime = NULL, context_model = NULL, context_fast = NULL, context_uncertain = 1, context_after = (SELECT at FROM usage INDEXED BY usage_session WHERE session = \{session} ORDER BY at DESC LIMIT 1) WHERE session = \{session} AND (1);"
}

///|
/// The context trigger as the compact statistics have it now (`contextChange`): an old call taken in changes nothing.
pub fn context_change() -> String {
  let changed = context_columns.map(c => "OLD.\{c} IS NOT NEW.\{c}").join(" OR ")
  "CREATE TRIGGER usage_compact_context_change AFTER UPDATE OF \{context_columns.join(", ")} ON usage WHEN (OLD.subagent = 0 OR NEW.subagent = 0) AND (\{changed}) BEGIN \{invalidate_context("OLD.session")} \{invalidate_context("NEW.session")} END;"
}

///|
fn has_table(db : @sql.Db, name : String) -> Bool raise {
  first(db, "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", [Json::string(name)]) is Some(_)
}

///|
fn number(row : Map[String, Json]?, name : String) -> Json {
  match row {
    Some(r) => get(r, name)
    None => Json::null()
  }
}

///|
/// One batch of at least `batch` calls, or those left, and whole quarters (`fillUsageStep`): true when no call is left
/// before the two `since`.
pub fn fill_step(db : @sql.Db, batch? : Int = 256) -> Bool raise {
  if !has_table(db, "usage_compact_since") || !has_table(db, "usage_history_since") {
    return true
  }
  db.exec("BEGIN IMMEDIATE")
  errdefer (db.exec("ROLLBACK") catch { _ => () })
  // (`keepContextOnFill`: a context trigger from before the fill is replaced)
  if first(db, "SELECT sql FROM sqlite_master WHERE type = 'trigger' AND name = 'usage_compact_context_change'", [])
    is Some(t) &&
    get(t, "sql") is String(sql) &&
    sql.contains("compact_counted") {
    db.exec("DROP TRIGGER usage_compact_context_change; \{context_change()}")
  }
  // (the quarter the fill reaches up to, and its time: millisecond times, exact in a Double as in JavaScript)
  let since = first(db, "SELECT h.since AS history, c.since AS coverage FROM usage_history_since h, usage_compact_since c WHERE h.id = 1 AND c.id = 1", [])
  let history = number(since, "history")
  let coverage = number(since, "coverage")
  let q = quarter_ms.to_double()
  let c = match coverage {
    Number(v, ..) => v
    _ => raise Failure("usage compact coverage is missing")
  }
  let h = match history {
    Number(v, ..) => v
    _ => c
  }
  let end_q = ((if c > h { c } else { h }) / q).ceil()
  let end = Json::number(end_q)
  let before = Json::number(end_q * q)
  let next = match
    first(db, "SELECT at FROM usage INDEXED BY usage_at WHERE at < ? ORDER BY at DESC LIMIT 1 OFFSET ?", [
      before,
      Json::number((batch - 1).to_double()),
    ]) {
    Some(r) => Some(r)
    None => first(db, "SELECT at FROM usage INDEXED BY usage_at WHERE at < ? ORDER BY at LIMIT 1", [before])
  }
  guard next is Some(n) else {
    if !(history is Null) {
      ignore(db.run("UPDATE usage_history_since SET since = ? WHERE id = 1", [Json::null()]))
    }
    db.exec("COMMIT")
    return true
  }
  let at = match get(n, "at") {
    Number(v, ..) => v
    _ => raise Failure("a call has no time")
  }
  let start_q = (at / q).floor()
  let start = Json::number(start_q)
  let from = Json::number(start_q * q)
  ignore(
    db.run(
      "UPDATE usage INDEXED BY usage_at SET compact_counted = 1 WHERE at >= ? AND at < ? AND compact_counted = 0",
      [from, before],
    ),
  )
  if start_q * q < c {
    ignore(db.run("UPDATE usage_compact_since SET since = ? WHERE id = 1", [from]))
  }
  if !(history is Null) {
    // (`setUsageHistoryQuarters`, then `setUsageHistorySince`)
    ignore(
      db.run(
        "DELETE FROM usage_history WHERE scope IN (SELECT scope FROM usage_history_total) AND quarter >= ? AND quarter < ?",
        [start, end],
      ),
    )
    ignore(
      db.run(
        "INSERT INTO usage_history (scope, quarter, calls, tokens) SELECT COALESCE((SELECT ws FROM sessions WHERE key = u.session), ''), (CASE WHEN u.at >= 0 THEN u.at / \{quarter_ms} ELSE -1 - ((-1 - u.at) / \{quarter_ms}) END), SUM(u.calls), SUM((u.input + u.cache_read + u.cache_write + u.cache_write_long + u.output)) FROM usage u INDEXED BY usage_at WHERE u.at >= ? * \{quarter_ms} AND u.at < ? * \{quarter_ms} GROUP BY 1, 2",
        [start, end],
      ),
    )
    ignore(db.run("UPDATE usage_history_since SET since = ? WHERE id = 1", [from]))
  }
  db.exec("COMMIT")
  false
}
