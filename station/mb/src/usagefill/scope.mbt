// The usage statistics' workspace upkeep (station/src/usage/scope-worker.ts), here for the MoonBit builder: a
// session's buckets moved to its new workspace (store/usage-compact.ts `moveCompactStep`), new buckets accounted into
// the totals and their time tree (`compactTotalsStep`), and the grouped summary blocks converted and kept
// (store/usage-summary-blocks.ts `usageSummaryBlocksStep`), one bounded batch at a time. Values stay in SQLite: each
// bucket's change is applied there, and only the keys a batch touched are cleaned of empty rows after it.

///|
let minute_bias : String = "281474976710656"

///|
let tree_levels : Int = 7

///|
let totals_batch : Int = 64

///|
let summary_batch : Int = 32

///|
let key_cols : Array[String] = ["session", "minute", "thread", "person", "profile", "runtime", "model", "fast"]

///|
let scoped_key : Array[String] = ["minute", "session", "thread", "person", "profile", "runtime", "model", "fast"]

///|
let dimension_cols : Array[String] = ["session", "thread", "person", "profile", "runtime", "model", "fast"]

///|
let value_cols : Array[String] = ["calls", "input", "cache_read", "cache_write", "cache_write_long", "output"]

///|
/// A key column read out (integers as text) and bound back.
fn is_int(name : String) -> Bool {
  name == "minute" || name == "thread" || name == "fast"
}

///|
fn out(name : String, alias : String) -> String {
  if is_int(name) { "CAST(\{name} AS TEXT) AS \{alias}" } else { "\{name} AS \{alias}" }
}

///|
fn param(name : String, at : Int) -> String {
  if is_int(name) { "CAST(?\{at} AS INTEGER)" } else { "?\{at}" }
}

///|
/// `name = ?n AND …` for the key, from `start`.
fn key_where(names : Array[String], start : Int, prefix? : String = "") -> String {
  names.mapi((i, n) => "\{prefix}\{n} = \{param(n, start + i)}").join(" AND ")
}

///|
fn key_of(row : Map[String, Json], names : Array[String], prefix? : String = "") -> Array[Json] {
  names.map(n => get(row, prefix + n))
}

///|
fn tokens(r : String) -> String {
  "(\{r}.input + \{r}.cache_read + \{r}.cache_write + \{r}.cache_write_long + \{r}.output)"
}

///|
let touched_ddl : String = "CREATE TEMP TABLE IF NOT EXISTS mb_usage_touched_total (scope TEXT PRIMARY KEY) WITHOUT ROWID; CREATE TEMP TABLE IF NOT EXISTS mb_usage_touched_tree (scope TEXT NOT NULL, level INTEGER NOT NULL, bucket INTEGER NOT NULL, PRIMARY KEY (scope, level, bucket)) WITHOUT ROWID; CREATE TEMP TABLE IF NOT EXISTS mb_usage_touched_block (scope TEXT NOT NULL, level INTEGER NOT NULL, bucket INTEGER NOT NULL, session TEXT NOT NULL, thread INTEGER NOT NULL, person TEXT NOT NULL, profile TEXT NOT NULL, runtime TEXT NOT NULL, model TEXT NOT NULL, fast INTEGER NOT NULL, PRIMARY KEY (scope, level, bucket, session, thread, person, profile, runtime, model, fast)) WITHOUT ROWID;"

///|
/// At most `batch` pending buckets (of `session`, else of `scope`, else any) accounted into the totals and their tree
/// (`accountCompactBuckets`), in the caller's write: (count, sessions, earliest minute's time).
fn account(db : @sql.Db, batch : Int, session? : Json, scope? : Json) -> (Int, Array[Json], Double?) raise {
  db.exec(touched_ddl)
  let lim = Json::number(batch.to_double())
  let cols = "\{out("session", "session")}, \{out("minute", "minute")}, \{out("thread", "thread")}, person, profile, runtime, model, \{out("fast", "fast")}, records, minute * 60000.0 AS ms"
  let rows = match (session, scope) {
    (Some(s), _) =>
      db.all("SELECT \{cols} FROM usage_compact INDEXED BY usage_compact_pending_session WHERE pending = 1 AND session = ? LIMIT ?", [s, lim])
    (None, Some(sc)) =>
      db.all("SELECT \{cols} FROM usage_compact INDEXED BY usage_compact_pending_scope WHERE pending = 1 AND scope = ? LIMIT ?", [sc, lim])
    _ => db.all("SELECT \{cols} FROM usage_compact INDEXED BY usage_compact_pending_scope WHERE pending = 1 LIMIT ?", [lim])
  }
  let at = key_where(key_cols, 1)
  // (each bucket's previously accounted contribution taken out of its scope's and the station's totals and tree, its
  // current one put in)
  for row in rows {
    let k = key_of(row, key_cols)
    let contributions = [
      ("accounted_scope", "accounted_calls", "accounted_tokens", "-1 *"),
      ("'G'", "accounted_calls", "accounted_tokens", "-1 *"),
      ("scope", "calls", tokens("usage_compact"), "1 *"),
      ("'G'", "calls", tokens("usage_compact"), "1 *"),
    ]
    for c in contributions {
      let (target, calls, toks, sign) = c
      // (the old contribution only where one was accounted)
      let accounted = if calls == "accounted_calls" { "accounted_scope IS NOT NULL AND " } else { "" }
      let nonzero = "(\{calls} != 0 OR \{toks} != 0)"
      ignore(
        db.run(
          "INSERT INTO usage_compact_total (scope, calls, tokens) SELECT \{target}, \{sign} \{calls}, \{sign} \{toks} FROM usage_compact WHERE \{at} AND \{accounted}\{nonzero} ON CONFLICT (scope) DO UPDATE SET calls = calls + excluded.calls, tokens = tokens + excluded.tokens",
          k,
        ),
      )
      ignore(
        db.run(
          "INSERT INTO temp.mb_usage_touched_total (scope) SELECT \{target} FROM usage_compact WHERE \{at} AND \{accounted}\{nonzero} ON CONFLICT DO NOTHING",
          k,
        ),
      )
      for level in 0..<tree_levels {
        let bucket = "((minute + \{minute_bias}) / \{1L << (8 * level)})"
        ignore(
          db.run(
            "INSERT INTO usage_compact_total_tree (scope, level, bucket, calls, tokens) SELECT \{target}, \{level}, \{bucket}, \{sign} \{calls}, \{sign} \{toks} FROM usage_compact WHERE \{at} AND \{accounted}\{nonzero} ON CONFLICT (scope, level, bucket) DO UPDATE SET calls = calls + excluded.calls, tokens = tokens + excluded.tokens",
            k,
          ),
        )
        ignore(
          db.run(
            "INSERT INTO temp.mb_usage_touched_tree (scope, level, bucket) SELECT \{target}, \{level}, \{bucket} FROM usage_compact WHERE \{at} AND \{accounted}\{nonzero} ON CONFLICT DO NOTHING",
            k,
          ),
        )
      }
    }
    ignore(
      db.run(
        "UPDATE usage_compact SET accounted_scope = scope, accounted_calls = calls, accounted_tokens = \{tokens("usage_compact")}, pending = 0 WHERE \{at}",
        k,
      ),
    )
    if get(row, "records") is Number(0.0, ..) {
      ignore(db.run("DELETE FROM usage_compact WHERE \{at} AND records = 0", k))
    }
  }
  ignore(
    db.run(
      "DELETE FROM usage_compact_total WHERE scope IN (SELECT scope FROM temp.mb_usage_touched_total) AND calls = 0 AND tokens = 0",
      [],
    ),
  )
  ignore(
    db.run(
      "DELETE FROM usage_compact_total_tree WHERE (scope, level, bucket) IN (SELECT scope, level, bucket FROM temp.mb_usage_touched_tree) AND calls = 0 AND tokens = 0",
      [],
    ),
  )
  db.exec("DELETE FROM temp.mb_usage_touched_total; DELETE FROM temp.mb_usage_touched_tree")
  let sessions : Array[Json] = []
  let mut from : Double? = None
  for row in rows {
    let s = get(row, "session")
    if !sessions.contains(s) {
      sessions.push(s)
    }
    let ms = match get(row, "ms") {
      Number(v, ..) => v
      _ => 0.0
    }
    from = match from {
      Some(f) if f <= ms => Some(f)
      _ => Some(ms)
    }
  }
  // (the earliest time only where JavaScript holds it exactly)
  let from = match from {
    Some(f) if f.abs() <= 9007199254740991.0 && f == f.floor() => Some(f)
    _ => None
  }
  (rows.length(), sessions, from)
}

///|
fn write_tx(db : @sql.Db, f : () -> Json raise) -> Json raise {
  db.exec("BEGIN IMMEDIATE")
  errdefer (db.exec("ROLLBACK") catch { _ => () })
  let r = f()
  db.exec("COMMIT")
  r
}

///|
fn answer(done : Bool, more : Array[(String, Json)]) -> Json {
  let m : Map[String, Json] = { "done": Json::boolean(done) }
  for kv in more {
    m[kv.0] = kv.1
  }
  Json::object(m)
}

///|
/// One batch of new buckets accounted (`compactTotalsStep`).
fn totals_step(db : @sql.Db, batch : Int, scope : Json?) -> Json raise {
  let batch = if batch < totals_batch { batch } else { totals_batch }
  write_tx(db, () => {
    let (count, sessions, from) = match scope {
      Some(s) => account(db, batch, scope=s)
      None => account(db, batch)
    }
    let more = [("sessions", Json::array(sessions))]
    if from is Some(f) {
      more.push(("from", Json::number(f)))
    }
    answer(count < batch, more)
  })
}

///|
let moving_cols : String = "session, target, phase, CAST(after_minute AS TEXT) AS after_minute, CAST(after_thread AS TEXT) AS after_thread, after_person, after_profile, after_runtime, after_model, CAST(after_fast AS TEXT) AS after_fast"

///|
/// One batch of re-scoping a moved session's buckets (`moveCompactStep`).
fn move_step(db : @sql.Db, batch : Int, scope : Json?) -> Json raise {
  let batch = if batch < 256 { batch } else { 256 }
  write_tx(db, () => {
    let found = match scope {
      None => first(db, "SELECT \{moving_cols} FROM usage_compact_moving ORDER BY session LIMIT 1", [])
      Some(s) =>
        first(
          db,
          "SELECT m.session AS session, m.target AS target, m.phase AS phase, CAST(m.after_minute AS TEXT) AS after_minute, CAST(m.after_thread AS TEXT) AS after_thread, m.after_person AS after_person, m.after_profile AS after_profile, m.after_runtime AS after_runtime, m.after_model AS after_model, CAST(m.after_fast AS TEXT) AS after_fast FROM usage_compact_moving_scope sc CROSS JOIN usage_compact_moving m ON m.session = sc.session WHERE sc.scope = ? ORDER BY sc.session LIMIT 1",
          [s],
        )
    }
    guard found is Some(move) else { return answer(true, []) }
    let session = get(move, "session")
    let target = get(move, "target")
    if get(move, "phase") is Number(1.0, ..) {
      // (every old scope kept unavailable until the session's pending contributions have left its totals)
      let (count, _, _) = account(db, if batch < totals_batch { batch } else { totals_batch }, session~)
      if count > 0 {
        return answer(false, [])
      }
      let removed = db.run(
        "DELETE FROM usage_compact_moving_scope WHERE (scope, session) IN (SELECT scope, session FROM usage_compact_moving_scope INDEXED BY usage_compact_moving_by_session WHERE session = ? AND scope <> ? LIMIT ?)",
        [session, target, Json::number(batch.to_double())],
      )
      if removed == 0 {
        ignore(db.run("DELETE FROM usage_compact_moving_scope WHERE scope = ? AND session = ?", [target, session]))
        ignore(db.run("DELETE FROM usage_compact_moving WHERE session = ?", [session]))
        return answer(false, [("session", session)])
      }
      return answer(false, [])
    }
    let bucket_cols = "\{out("minute", "minute")}, \{out("thread", "thread")}, person, profile, runtime, model, \{out("fast", "fast")}, scope"
    // (ordered by the columns themselves: the integer ones are read out as text under their own names)
    let order = "usage_compact.minute, usage_compact.thread, person, profile, runtime, model, usage_compact.fast"
    let rows = if get(move, "after_minute") is Null {
      db.all("SELECT \{bucket_cols} FROM usage_compact WHERE session = ? ORDER BY \{order} LIMIT ?", [
        session,
        Json::number(batch.to_double()),
      ])
    } else {
      db.all(
        "SELECT \{bucket_cols} FROM usage_compact WHERE session = ?1 AND (minute, thread, person, profile, runtime, model, fast) > (CAST(?2 AS INTEGER), CAST(?3 AS INTEGER), ?4, ?5, ?6, ?7, CAST(?8 AS INTEGER)) ORDER BY usage_compact.minute, usage_compact.thread, person, profile, runtime, model, usage_compact.fast LIMIT ?9",
        [session] +
        ["after_minute", "after_thread", "after_person", "after_profile", "after_runtime", "after_model", "after_fast"].map(n => get(move, n)) +
        [Json::number(batch.to_double())],
      )
    }
    let names = ["minute", "thread", "person", "profile", "runtime", "model", "fast"]
    for row in rows {
      if get(row, "scope") != target {
        ignore(
          db.run(
            "UPDATE usage_compact SET scope = ?1 WHERE session = ?2 AND \{key_where(names, 3)}",
            [target, session] + key_of(row, names),
          ),
        )
      }
    }
    if rows.length() < batch {
      ignore(db.run("UPDATE usage_compact_moving SET phase = 1 WHERE session = ?", [session]))
      return answer(false, [])
    }
    let last = rows[rows.length() - 1]
    ignore(
      db.run(
        "UPDATE usage_compact_moving SET after_minute = CAST(?1 AS INTEGER), after_thread = CAST(?2 AS INTEGER), after_person = ?3, after_profile = ?4, after_runtime = ?5, after_model = ?6, after_fast = CAST(?7 AS INTEGER) WHERE session = ?8",
        key_of(last, names) + [session],
      ),
    )
    answer(false, [])
  })
}

// The summary blocks (usage-summary-blocks.ts).

///|
fn floor_div(n : String, d : Int) -> String {
  "(CASE WHEN \{n} >= 0 THEN \{n} / \{d} ELSE -1 - ((-1 - \{n}) / \{d}) END)"
}

///|
/// The workspace's (or the station's) blocks converted from the compact rows (`usageSummaryBlocksReady`).
fn blocks_ready(db : @sql.Db, scope : Json?) -> Bool raise {
  if first(db, "SELECT done FROM usage_summary_blocks_progress WHERE id = 1", []) is Some(p) &&
    get(p, "done") is Number(1.0, ..) {
    return true
  }
  match scope {
    None | Some(String("G")) => false
    Some(s) =>
      match first(db, "SELECT done FROM usage_summary_blocks_scope_progress WHERE scope = ?", [s]) {
        Some(r) => get(r, "done") is Number(1.0, ..)
        None => false
      }
  }
}

///|
/// A requested span of minutes (`UsageSummaryRange`): from, to (as text), where its conversion got to, and whether done.
priv struct Range {
  from : Json
  to : Json
  after : Map[String, Json]?
  converted : Bool
}

///|
/// Changed or unconverted rows left for the scope (and span) (`usageSummaryBlocksPending`).
fn blocks_pending(db : @sql.Db, scope : Json?, range : Range?) -> Bool raise {
  let converted = match range {
    Some(r) => r.converted
    None => false
  }
  if !blocks_ready(db, scope) && !converted {
    return true
  }
  let (bounds, times) = match range {
    Some(r) => (" AND minute >= CAST(? AS INTEGER) AND minute < CAST(? AS INTEGER)", [r.from, r.to])
    None => ("", [])
  }
  match scope {
    None | Some(String("G")) =>
      if range is None {
        first(db, "SELECT 1 FROM usage_summary_blocks_dirty LIMIT 1", []) is Some(_)
      } else {
        first(
          db,
          "SELECT 1 FROM usage_summary_blocks_dirty INDEXED BY usage_summary_blocks_dirty_time WHERE minute >= CAST(? AS INTEGER) AND minute < CAST(? AS INTEGER) LIMIT 1",
          times,
        )
        is Some(_)
      }
    Some(s) =>
      first(db, "SELECT 1 FROM usage_summary_blocks_dirty INDEXED BY usage_summary_blocks_dirty_old WHERE old_scope = ?\{bounds} LIMIT 1", [s] + times)
      is Some(_) ||
      first(db, "SELECT 1 FROM usage_summary_blocks_dirty INDEXED BY usage_summary_blocks_dirty_new WHERE new_scope = ?\{bounds} LIMIT 1", [s] + times)
      is Some(_)
  }
}

///|
let key_out : String = key_cols.map(n => out(n, n)).join(", ")

///|
fn progress_out(table : String, where_ : String) -> String {
  "SELECT done, after_session, CAST(after_minute AS TEXT) AS after_minute, CAST(after_thread AS TEXT) AS after_thread, after_person, after_profile, after_runtime, after_model, CAST(after_fast AS TEXT) AS after_fast FROM \{table} WHERE \{where_}"
}

///|
/// A bucket's contribution (`source`: the shadow, or the current compact row) added to or taken from its blocks.
fn apply_blocks(db : @sql.Db, source : String, extra : String, sign : Int, k : Array[Json]) -> Unit raise {
  let at = key_where(key_cols, 1)
  let dims = dimension_cols.join(", ")
  for size in [15, 60] {
    let bucket = floor_div("minute", size)
    ignore(
      db.run(
        "INSERT INTO usage_summary_blocks (scope, level, bucket, \{dims}, parts, \{value_cols.join(", ")}) SELECT scope, \{size}, \{bucket}, \{dims}, \{sign}, \{value_cols.map(v => "\{sign} * \{v}").join(", ")} FROM \{source} WHERE \{at}\{extra} ON CONFLICT (scope, level, bucket, \{dims}) DO UPDATE SET \{(["parts"] + value_cols).map(v => "\{v} = \{v} + excluded.\{v}").join(", ")}",
        k,
      ),
    )
    ignore(
      db.run(
        "INSERT INTO temp.mb_usage_touched_block (scope, level, bucket, \{dims}) SELECT scope, \{size}, \{bucket}, \{dims} FROM \{source} WHERE \{at}\{extra} ON CONFLICT DO NOTHING",
        k,
      ),
    )
  }
}

///|
/// One bounded batch of converting existing compact rows or reconciling changed ones into the blocks
/// (`usageSummaryBlocksStep`).
fn summary_step(db : @sql.Db, batch : Int, scope : Json?, range : Range?) -> Json raise {
  let batch = if batch < summary_batch { batch } else { summary_batch }
  let lim = Json::number(batch.to_double())
  write_tx(db, () => {
    db.exec(touched_ddl)
    guard first(db, progress_out("usage_summary_blocks_progress", "id = 1"), []) is Some(progress) else {
      raise Failure("usage summary progress is missing")
    }
    let named = match scope {
      None | Some(String("G")) => None
      Some(s) => Some(s)
    }
    let scoped = range is None && !(get(progress, "done") is Number(1.0, ..)) && named is Some(_)
    let cursor = if scoped {
      ignore(db.run("INSERT OR IGNORE INTO usage_summary_blocks_scope_progress (scope, done) VALUES (?, 0)", [named.unwrap()]))
      first(db, progress_out("usage_summary_blocks_scope_progress", "scope = ?"), [named.unwrap()]).unwrap()
    } else {
      progress
    }
    let converting = match range {
      None => !(get(cursor, "done") is Number(1.0, ..))
      Some(r) => !r.converted && !blocks_ready(db, scope)
    }
    let order = if scoped { scoped_key } else { key_cols }
    let after = if get(cursor, "after_session") is Null { [] } else { order.map(n => get(cursor, "after_" + n)) }
    let rows = if converting && range is Some(r) {
      let index = if named is Some(_) { "usage_compact_scope_time" } else { "usage_compact_time" }
      let scope_cond = if named is Some(_) { "scope = ? AND " } else { "" }
      let n0 = if named is Some(_) { 2 } else { 1 }
      let after_cond = match r.after {
        Some(_) => " AND (\{scoped_key.join(", ")}) > (\{scoped_key.mapi((i, n) => param(n, n0 + 2 + i)).join(", ")})"
        None => ""
      }
      let params = (if named is Some(s) { [s] } else { [] }) +
        [r.from, r.to] +
        (match r.after {
          Some(a) => scoped_key.map(n => a.get(n).unwrap_or(Json::null()))
          None => []
        }) +
        [lim]
      let limit_at = params.length()
      db.all(
        "SELECT \{key_out} FROM usage_compact INDEXED BY \{index} WHERE \{scope_cond}minute >= CAST(?\{n0} AS INTEGER) AND minute < CAST(?\{n0 + 1} AS INTEGER)\{after_cond} ORDER BY \{scoped_key.map(n => "usage_compact." + n).join(", ")} LIMIT ?\{limit_at}",
        params,
      )
    } else if converting {
      let n0 = if scoped { 2 } else { 1 }
      let where_ = (if scoped { ["scope = ?1"] } else { [] }) +
        (if after.length() > 0 { ["(\{order.join(", ")}) > (\{order.mapi((i, n) => param(n, n0 + i)).join(", ")})"] } else { [] })
      let where_sql = if where_.length() == 0 { "" } else { "WHERE " + where_.join(" AND ") }
      let index = if scoped { "INDEXED BY usage_compact_scope_time" } else { "" }
      let params = (if scoped { [named.unwrap()] } else { [] }) + after + [lim]
      db.all(
        "SELECT \{key_out} FROM usage_compact \{index} \{where_sql} ORDER BY \{order.map(n => "usage_compact." + n).join(", ")} LIMIT ?\{params.length()}",
        params,
      )
    } else if named is None {
      match range {
        None =>
          db.all("SELECT \{key_out} FROM usage_summary_blocks_dirty ORDER BY \{key_cols.map(n => "usage_summary_blocks_dirty." + n).join(", ")} LIMIT ?", [lim])
        Some(r) =>
          db.all(
            "SELECT \{key_out} FROM usage_summary_blocks_dirty INDEXED BY usage_summary_blocks_dirty_time WHERE minute >= CAST(? AS INTEGER) AND minute < CAST(? AS INTEGER) LIMIT ?",
            [r.from, r.to, lim],
          )
      }
    } else {
      let s = named.unwrap()
      let (bounds, times) = match range {
        Some(r) => (" AND minute >= CAST(? AS INTEGER) AND minute < CAST(? AS INTEGER)", [r.from, r.to])
        None => ("", [])
      }
      let found = db.all(
        "SELECT \{key_out} FROM usage_summary_blocks_dirty INDEXED BY usage_summary_blocks_dirty_old WHERE old_scope = ?\{bounds} LIMIT ?",
        [s] + times + [lim],
      )
      if found.length() < batch {
        let seen = found.map(r => Json::array(key_of(r, key_cols)).stringify())
        let next = db.all(
          "SELECT \{key_out} FROM usage_summary_blocks_dirty INDEXED BY usage_summary_blocks_dirty_new WHERE new_scope = ?\{bounds} LIMIT ?",
          [s] + times + [Json::number((batch + found.length()).to_double())],
        )
        for r in next {
          let id = Json::array(key_of(r, key_cols)).stringify()
          if !seen.contains(id) {
            found.push(r)
            seen.push(id)
          }
          if found.length() == batch {
            break
          }
        }
      }
      found
    }
    let at = key_where(key_cols, 1)
    for row in rows {
      let k = key_of(row, key_cols)
      let previous = first(db, "SELECT 1 FROM usage_summary_blocks_shadow WHERE \{at}", k) is Some(_)
      let now = first(db, "SELECT 1 FROM usage_compact WHERE \{at} AND records > 0", k) is Some(_)
      if previous {
        apply_blocks(db, "usage_summary_blocks_shadow", "", -1, k)
      }
      if now {
        apply_blocks(db, "usage_compact", " AND records > 0", 1, k)
        ignore(
          db.run(
            "INSERT INTO usage_summary_blocks_shadow (\{key_cols.join(", ")}, scope, \{value_cols.join(", ")}) SELECT \{key_cols.join(", ")}, scope, \{value_cols.join(", ")} FROM usage_compact WHERE \{at} AND records > 0 ON CONFLICT (\{key_cols.join(", ")}) DO UPDATE SET scope = excluded.scope, \{value_cols.map(v => "\{v} = excluded.\{v}").join(", ")}",
            k,
          ),
        )
      } else if previous {
        ignore(db.run("DELETE FROM usage_summary_blocks_shadow WHERE \{at}", k))
      }
      ignore(db.run("DELETE FROM usage_summary_blocks_dirty WHERE \{at}", k))
    }
    let dims = dimension_cols.join(", ")
    ignore(
      db.run(
        "DELETE FROM usage_summary_blocks WHERE (scope, level, bucket, \{dims}) IN (SELECT scope, level, bucket, \{dims} FROM temp.mb_usage_touched_block) AND parts = 0",
        [],
      ),
    )
    db.exec("DELETE FROM temp.mb_usage_touched_block")
    match range {
      Some(r) => {
        if converting && rows.length() == batch {
          let last = rows[rows.length() - 1]
          let a : Map[String, Json] = Map([])
          for n in key_cols {
            a[n] = get(last, n)
          }
          return answer(false, [("after", Json::object(a))])
        }
        let complete = !blocks_pending(db, scope, Some({ ..r, converted: true }))
        return if complete { answer(true, []) } else { answer(false, [("converted", Json::boolean(true))]) }
      }
      None => ()
    }
    if converting {
      let (table, condition, scope_args) = if scoped {
        ("usage_summary_blocks_scope_progress", "scope = ?", [named.unwrap()])
      } else {
        ("usage_summary_blocks_progress", "id = 1", [])
      }
      if rows.length() < batch {
        ignore(db.run("UPDATE \{table} SET done = 1 WHERE \{condition}", scope_args))
      } else {
        let last = rows[rows.length() - 1]
        let sets = key_cols.mapi((i, n) => "after_\{n} = \{param(n, i + 1)}").join(", ")
        let cond = if scoped { "scope = ?\{key_cols.length() + 1}" } else { "id = 1" }
        ignore(db.run("UPDATE \{table} SET \{sets} WHERE \{cond}", key_of(last, key_cols) + scope_args))
      }
    }
    answer(!blocks_pending(db, scope, None), [])
  })
}

///|
fn range_of(j : Json) -> Range? {
  guard j is Object(m) else { return None }
  let text = (v : Json) => match v {
    Number(n, ..) => Json::string(n.to_int64().to_string())
    v => v
  }
  Some({
    from: text(m.get("from").unwrap_or(Json::null())),
    to: text(m.get("to").unwrap_or(Json::null())),
    after: match m.get("after") {
      Some(Object(a)) => Some(a)
      _ => None
    },
    converted: m.get("converted") is Some(True),
  })
}

///|
/// One batch of what scope-worker.ts does for `{scope?, range?}`: a move, a span's blocks, the totals, or the blocks,
/// whichever is pending first; its answer as the worker's.
pub fn scope_batch(db : @sql.Db, ask : Json) -> Json raise {
  let (scope, range) = match ask {
    Object(m) =>
      (
        match m.get("scope") {
          Some(String(s)) => Some(Json::string(s))
          _ => None
        },
        match m.get("range") {
          Some(r) => range_of(r)
          None => None
        },
      )
    _ => (None, None)
  }
  let compact = first(db, "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'usage_compact_since'", []) is Some(_)
  let blocks_installed = first(db, "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'usage_summary_blocks_progress'", [])
    is Some(_)
  if range is Some(_) && (!compact || !blocks_installed) {
    raise Failure("usage summary statistics are not installed")
  }
  if !compact {
    return answer(true, [])
  }
  let all = match scope {
    None | Some(String("G")) => true
    _ => false
  }
  let named = if all { None } else { scope }
  let moving = if all {
    first(db, "SELECT 1 FROM usage_compact_moving LIMIT 1", []) is Some(_)
  } else {
    first(db, "SELECT 1 FROM usage_compact_moving_scope WHERE scope = ? LIMIT 1", [scope.unwrap()]) is Some(_)
  }
  let pending = match scope {
    None => false
    Some(_) if all =>
      first(db, "SELECT 1 FROM usage_compact INDEXED BY usage_compact_pending_session WHERE pending = 1 LIMIT 1", []) is Some(_)
    Some(s) =>
      first(db, "SELECT 1 FROM usage_compact INDEXED BY usage_compact_pending_scope WHERE pending = 1 AND scope = ? LIMIT 1", [s])
      is Some(_)
  }
  let pending_blocks = blocks_installed && blocks_pending(db, named, range)
  if !moving && !pending && !pending_blocks {
    return answer(true, [])
  }
  let result = if moving {
    let r = move_step(db, 256, named)
    if range is Some(_) && r is Object(m) && m.get("done") is Some(True) {
      m["done"] = Json::boolean(false)
      Json::object(m)
    } else {
      r
    }
  } else if range is Some(_) && pending_blocks {
    summary_step(db, 32, named, range)
  } else if range is Some(_) {
    answer(true, [])
  } else if pending {
    totals_step(db, 256, named)
  } else {
    let r = summary_step(db, 32, named, None)
    answer(r is Object(m) && m.get("done") is Some(True), [])
  }
  if range is None && blocks_installed && result is Object(m) && m.get("done") is Some(True) && blocks_pending(db, named, None) {
    m["done"] = Json::boolean(false)
    return Json::object(m)
  }
  result
}
