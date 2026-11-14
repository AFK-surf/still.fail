// What the agents spent from one time until another, added up by day in the asker's time zone and by chat, person,
// account and model, as the usage page and a Comma connect read it: from the minute statistics (store/usage-compact.ts
// `compactQuery`, read/store.ts `usageGroups`), from the summary blocks in bounded steps where the page asks it
// (read/usage-batched.ts `usageGroupsBatched`, read/usage-summary-blocks.ts `usageGroupsFromBlocks`), or, on a store
// from before those, from the detail statistics (store/usage-detail.ts `detailQuery`). The statements are the
// TypeScript's, as it makes them; what that reader keeps between reads only to read less is not kept here.

///|
let i64_top : Int64 = 9223372036854775807L

///|
/// An i64 as a statement's integer, exactly (the shell reads it as JSON).
fn i64_json(n : Int64) -> Json {
  Json::number(n.to_double(), repr=n.to_string())
}

///|
fn floor_div(n : Int64, d : Int64) -> Int64 {
  if n >= 0L {
    n / d
  } else {
    -1L - (-1L - n) / d
  }
}

///|
fn table_installed(db : @sql.Db, name : String) -> Bool raise {
  one(db, "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", [Json::string(name)]) is Some(_)
}

///|
/// Whose usage a read is of (rows.ts InWorkspace): a workspace, and whether it is the home one (`home !== false`).
priv struct Viewer {
  workspace : String
  home : Bool
}

///|
fn viewer_of(v : Json?) -> Viewer? {
  match v {
    None | Some(Null) => None
    Some(v) =>
      Some({
        workspace: match v.value("workspace") {
          Some(String(w)) => w
          Some(w) => js_text(w)
          None => "undefined"
        },
        home: v.value("home") != Some(Json::boolean(false)),
      })
  }
}

///|
fn viewer_sees(viewer : Viewer, ws : Json) -> Bool {
  ws == Json::string(viewer.workspace) || (ws is Null && viewer.home)
}

///|
fn has_compact(db : @sql.Db) -> Bool raise {
  table_installed(db, "usage_compact_since")
}

///|
/// usage-compact.ts `compactScopeReady`: no session of the viewer's workspaces still moving between them.
fn compact_scope_ready(db : @sql.Db, viewer : Viewer?) -> Bool raise {
  match viewer {
    None => one(db, "SELECT 1 FROM usage_compact_moving LIMIT 1", []) is None
    Some(v) => {
      let sql = if v.home {
        "SELECT 1 FROM usage_compact_moving_scope WHERE scope IN (?, 'H') LIMIT 1"
      } else {
        "SELECT 1 FROM usage_compact_moving_scope WHERE scope = ? LIMIT 1"
      }
      one(db, sql, [Json::string("W" + v.workspace)]) is None
    }
  }
}

///|
let moving_refusal : String = "usage statistics are moving between workspaces"

///|
/// usage-summary-blocks.ts USAGE_SUMMARY_PENDING.
let summary_pending : String = "usage summary statistics are being prepared"

///|
/// usage-detail.ts USAGE_DETAIL_PENDING.
let detail_pending : String = "usage detail statistics are still being filled"

///|
/// store/usage.ts `usageGroupOf`, of a row as a statement gives it.
fn group_of(r : Map[String, Json]) -> Group {
  let num = (k : String) => match field(r, k) { Number(n, ..) => n; _ => 0.0 }
  {
    day: match field(r, "day") { String(d) => d; _ => "" },
    session: field(r, "session"),
    thread: field(r, "thread"),
    person: field(r, "person"),
    profile: field(r, "profile"),
    runtime: field(r, "runtime"),
    model: field(r, "model"),
    fast: !(field(r, "fast") is (Null | Number(0.0, ..))),
    calls: num("calls"),
    input: num("input"),
    cache_read: num("cache_read"),
    cache_write: num("cache_write"),
    cache_write_long: num("cache_write_long"),
    output: num("output"),
  }
}

///|
/// usage-compact.ts `compactQuery`: the minute statistics of [from, to), read by the sessions the time index names; a
/// partial minute at either edge from its original calls.
fn compact_query(from : Int64, to : Int64, offset : Int64, viewer : Viewer?) -> (String, Array[Json]) {
  if from < to && (from % 60_000L != 0L || (to != i64_top && to % 60_000L != 0L)) {
    return compact_query_with_edges(from, to, offset, viewer)
  }
  let start = if from >= to { 0L } else { floor_div(from, 60_000L) }
  let end = if from >= to { 0L } else if to == i64_top { i64_top } else { floor_div(to, 60_000L) }
  let args = [i64_json(offset), i64_json(start), i64_json(end)]
  if viewer is Some(v) {
    args.push(Json::string("W" + v.workspace))
    args.push(Json::string(v.workspace))
  }
  let (scope, bucket_scope, eligible) = match viewer {
    None => ("", "", "SELECT session FROM selected")
    Some(v) =>
      (
        if v.home { "scope IN (?4, 'H') AND " } else { "scope = ?4 AND " },
        if v.home { "c.scope IN (?4, 'H') AND " } else { "c.scope = ?4 AND " },
        "SELECT p.session FROM selected p\n    CROSS JOIN usage_minute_scope sc ON sc.session = p.session\n    WHERE " +
        (if v.home { "(sc.ws = ?5 OR sc.ws IS NULL)" } else { "sc.ws = ?5" }),
      )
  }
  let index = if viewer is None { "usage_compact_time" } else { "usage_compact_scope_time" }
  let sql = "WITH selected AS MATERIALIZED (\n    SELECT DISTINCT session FROM usage_compact INDEXED BY \{index}\n    WHERE \{scope}minute >= ?2 AND minute < ?3\n  ), eligible AS MATERIALIZED (\{eligible})\n" +
    "    SELECT strftime('%Y-%m-%d', (c.minute + ?1) * 60, 'unixepoch') AS day,\n" +
    "    c.session, NULLIF(c.thread, 0) AS thread, NULLIF(c.person, '') AS person, NULLIF(c.profile, '') AS profile,\n" +
    "    c.runtime, NULLIF(c.model, '') AS model, c.fast, SUM(c.calls) AS calls, SUM(c.input) AS input,\n" +
    "    SUM(c.cache_read) AS cache_read, SUM(c.cache_write) AS cache_write, SUM(c.cache_write_long) AS cache_write_long, SUM(c.output) AS output\n" +
    "    FROM eligible p CROSS JOIN usage_compact c ON c.session = p.session AND c.minute >= ?2 AND c.minute < ?3\n" +
    "    WHERE \{bucket_scope}c.records > 0\n" +
    "    GROUP BY day, c.session, c.thread, c.person, c.profile, c.runtime, c.model, c.fast"
  (sql, args)
}

///|
/// usage-compact.ts `compactQueryWithEdges`.
fn compact_query_with_edges(from : Int64, to : Int64, offset : Int64, viewer : Viewer?) -> (String, Array[Json]) {
  let size = 60_000L
  let first = floor_div(from, size)
  let last = floor_div(to, size)
  let args = [i64_json(offset)]
  let bind = (value : Json) => {
    args.push(value)
    "?\{args.length()}"
  }
  let mut selected_scope = ""
  let mut bucket_scope = ""
  let mut eligible = "SELECT session FROM selected"
  if viewer is Some(v) {
    let scope = bind(Json::string("W" + v.workspace))
    let ws = bind(Json::string(v.workspace))
    selected_scope = if v.home { "scope IN (\{scope}, 'H') AND " } else { "scope = \{scope} AND " }
    bucket_scope = if v.home { "c.scope IN (\{scope}, 'H') AND " } else { "c.scope = \{scope} AND " }
    eligible = "SELECT p.session FROM selected p CROSS JOIN usage_minute_scope sc ON sc.session = p.session\n      WHERE " +
      (if v.home { "(sc.ws = \{ws} OR sc.ws IS NULL)" } else { "sc.ws = \{ws}" })
  }
  let index = if viewer is None { "usage_compact_time" } else { "usage_compact_scope_time" }
  let selected_start = bind(i64_json(first))
  let selected_end = bind(
    i64_json(
      if to == i64_top {
        i64_top
      } else {
        last + (if to == last * size { 0L } else { 1L })
      },
    ),
  )
  let start = bind(i64_json(first + (if from == first * size { 0L } else { 1L })))
  let end = bind(i64_json(if to == i64_top { i64_top } else { last }))
  let parts = [
    "SELECT c.minute, c.session, c.thread, c.person, c.profile, c.runtime, c.model, c.fast,\n    c.calls, c.input, c.cache_read, c.cache_write, c.cache_write_long, c.output\n    FROM eligible p CROSS JOIN usage_compact c ON c.session = p.session AND c.minute >= \{start} AND c.minute < \{end}\n    WHERE \{bucket_scope}c.records > 0",
  ]
  let edge = (minute : Int64, begin : Int64, until : Int64) => {
    if begin >= until {
      return
    }
    let bucket = bind(i64_json(minute))
    let low = bind(i64_json(begin))
    let high = bind(i64_json(until))
    parts.push(
      "SELECT e.minute, u.session, COALESCE(u.thread, 0), COALESCE(u.person, ''), COALESCE(u.profile, ''),\n      u.runtime, COALESCE(u.model, ''), u.fast, u.calls, u.input, u.cache_read, u.cache_write, u.cache_write_long, u.output\n      FROM (SELECT DISTINCT c.session, c.minute FROM usage_compact c INDEXED BY \{index}\n        CROSS JOIN eligible p ON p.session = c.session\n        WHERE \{bucket_scope}c.minute = \{bucket} AND c.records > 0) e\n      CROSS JOIN usage u INDEXED BY usage_session ON u.session = e.session AND u.at >= \{low} AND u.at < \{high}\n      WHERE u.compact_counted = 1",
    )
  }
  if from != first * size {
    edge(first, from, if (first + 1L) * size < to { (first + 1L) * size } else { to })
  }
  if to != i64_top && to != last * size && (last != first || from == first * size) {
    edge(last, last * size, to)
  }
  let sql = "WITH selected AS MATERIALIZED (\n      SELECT DISTINCT session FROM usage_compact INDEXED BY \{index}\n      WHERE \{selected_scope}minute >= \{selected_start} AND minute < \{selected_end}\n    ), eligible AS MATERIALIZED (\{eligible}), parts AS (\{parts.join(" UNION ALL ")})\n" +
    "    SELECT strftime('%Y-%m-%d', (minute + ?1) * 60, 'unixepoch') AS day,\n" +
    "      session, NULLIF(thread, 0) AS thread, NULLIF(person, '') AS person, NULLIF(profile, '') AS profile,\n" +
    "      runtime, NULLIF(model, '') AS model, fast, SUM(calls) AS calls, SUM(input) AS input,\n" +
    "      SUM(cache_read) AS cache_read, SUM(cache_write) AS cache_write, SUM(cache_write_long) AS cache_write_long, SUM(output) AS output\n" +
    "    FROM parts GROUP BY day, session, thread, person, profile, runtime, model, fast"
  (sql, args)
}

///|
/// usage-detail.ts SIZES: the detail statistics' buckets, ms.
let detail_sizes : Array[Int64] = [900_000L, 60_000L, 1_000L, 1L]

///|
/// usage-detail.ts `detailRanges`: [from, to) covered with the largest whole buckets available.
fn detail_ranges(from : Int64, to : Int64, offset : Int64) -> Array[(Int, Int64, Int64)] {
  if from >= to {
    return []
  }
  let levels = if offset % 15L == 0L { [0, 1, 2, 3] } else { [1, 2, 3] }
  let ranges = []
  fn visit(a : Int64, b : Int64, index : Int) -> Unit {
    if a >= b {
      return
    }
    let level = levels[index]
    let size = detail_sizes[level]
    let first = -floor_div(-a, size)
    let last = floor_div(b, size)
    if first >= last {
      if index + 1 < levels.length() {
        visit(a, b, index + 1)
      }
      return
    }
    if index + 1 < levels.length() {
      visit(a, first * size, index + 1)
    }
    ranges.push((level, first, last))
    if index + 1 < levels.length() {
      visit(last * size, b, index + 1)
    }
  }
  visit(from, to, 0)
  ranges
}

///|
/// usage-detail.ts `detailQuery`: the detail statistics' buckets intersecting [from, to) (`table`: the generation's).
fn detail_query(from : Int64, to : Int64, offset : Int64, viewer : Viewer?, table : String, by_session : Bool) -> (String, Array[Json])? {
  let ranges = detail_ranges(from, to, offset)
  if ranges.length() == 0 {
    return None
  }
  let args = [i64_json(offset)]
  let mut where_scope = ""
  if viewer is Some(v) {
    args.push(Json::string(if by_session { v.workspace } else { "W" + v.workspace }))
    where_scope = if v.home { "l.scope IN (?2, 'H') AND " } else { "l.scope = ?2 AND " }
  }
  let source = match viewer {
    Some(v) if by_session =>
      "FROM (" +
      (if v.home {
        "SELECT session FROM \{table}_scope INDEXED BY \{table}_scope_ws WHERE ws = ?2 UNION ALL SELECT session FROM \{table}_scope INDEXED BY \{table}_scope_ws WHERE ws IS NULL"
      } else {
        "SELECT session FROM \{table}_scope INDEXED BY \{table}_scope_ws WHERE ws = ?2"
      }) +
      ") sc\n      CROSS JOIN \{table}_lookup l ON l.session = sc.session"
    _ => "FROM \{table}_lookup l INDEXED BY " + (if viewer is None { "\{table}_lookup_time" } else { "\{table}_lookup_scope" })
  }
  if by_session && viewer is Some(_) {
    where_scope = ""
  }
  let targets = ranges.map(range => {
    args.push(i64_json(range.1))
    let start = args.length()
    args.push(i64_json(range.2))
    let end = args.length()
    "SELECT l.session, l.level, l.bucket \{source}\n      WHERE \{where_scope}l.level = \{range.0} AND l.bucket >= ?\{start} AND l.bucket < ?\{end}"
  })
  let sizes = detail_sizes.mapi((level, size) => "WHEN \{level} THEN \{size}").join(" ")
  let sql = "WITH targets AS MATERIALIZED (\{targets.join(" UNION ALL ")} ORDER BY 1, 2, 3),\n" +
    "    parts AS (SELECT d.bucket * (CASE d.level \{sizes} END) AS at, d.* FROM targets target\n" +
    "      CROSS JOIN \{table} d ON d.session = target.session AND d.level = target.level AND d.bucket = target.bucket)\n" +
    "    SELECT strftime('%Y-%m-%d', (at + ?1 * 60000) / 1000.0, 'unixepoch') AS day,\n" +
    "      session, NULLIF(thread, 0) AS thread, NULLIF(person, '') AS person, NULLIF(profile, '') AS profile,\n" +
    "      runtime, NULLIF(model, '') AS model, fast, SUM(calls) AS calls, SUM(input) AS input,\n" +
    "      SUM(cache_read) AS cache_read, SUM(cache_write) AS cache_write, SUM(cache_write_long) AS cache_write_long, SUM(output) AS output\n" +
    "    FROM parts GROUP BY day, session, thread, person, profile, runtime, model, fast"
  Some((sql, args))
}

///|
/// usage-detail.ts `prefix` of the store's generation (`usageDetailGeneration`).
fn detail_table(db : @sql.Db) -> String raise {
  if table_installed(db, "usage_detail_live_since") {
    "usage_detail_live"
  } else {
    "usage_detail"
  }
}

///|
/// usage-retire.ts `retiredUsage`.
fn usage_retired(db : @sql.Db) -> Bool raise {
  table_installed(db, "usage_retired_detail")
}

///|
/// A row a statement says must be there, as reading its field of `undefined` throws in the TypeScript.
fn done_of(db : @sql.Db, sql : String) -> Json raise {
  match one(db, sql, []) {
    Some(r) => field(r, "done")
    None => raise Failure("Cannot read properties of undefined (reading 'done')")
  }
}

///|
/// usage-detail.ts `usageDetailReady`, behind its compact and retired checks.
fn detail_ready(db : @sql.Db, viewer : Viewer?, table : String) -> Bool raise {
  if done_of(db, "SELECT done FROM \{table}_all WHERE id = 1") == Json::number(1.0) {
    return true
  }
  guard viewer is Some(v) && !v.home else { return false }
  one(db, "SELECT 1 FROM \{table}_ready WHERE ws = ?", [Json::string(v.workspace)]) is Some(_) &&
  one(db, "SELECT session FROM \{table}_scope INDEXED BY \{table}_scope_ws\n  WHERE ws = ? AND done = 0 LIMIT 1", [
    Json::string(v.workspace),
  ])
  is None
}

///|
/// usage-detail.ts `usageDetailScopeBySession`, behind its retired check.
fn detail_by_session(db : @sql.Db, viewer : Viewer?, table : String) -> Bool raise {
  guard viewer is Some(v) else { return false }
  if one(db, "SELECT 1 FROM \{table}_dirty_scope INDEXED BY \{table}_dirty_by_scope WHERE scope = ? LIMIT 1", [
      Json::string("W" + v.workspace),
    ])
    is Some(_) {
    return true
  }
  v.home &&
  one(db, "SELECT 1 FROM \{table}_dirty_scope INDEXED BY \{table}_dirty_by_scope WHERE scope = 'H' LIMIT 1", [])
  is Some(_)
}

///|
/// read/store.ts `usageGroups`: the minute statistics, or on a store from before them the detail statistics once they
/// are complete for the viewer.
fn usage_groups(db : @sql.Db, from : Int64, to : Int64, offset : Int64, viewer : Viewer?) -> Array[Group] raise {
  if has_compact(db) {
    if !compact_scope_ready(db, viewer) {
      raise Refused(503, moving_refusal)
    }
    let (sql, args) = compact_query(from, to, offset, viewer)
    return db.all(sql, args).map(group_of)
  }
  if usage_retired(db) {
    raise Refused(503, "usage detail statistics are unavailable")
  }
  let table = detail_table(db)
  if !detail_ready(db, viewer, table) {
    raise Failure(detail_pending)
  }
  match detail_query(from, to, offset, viewer, table, detail_by_session(db, viewer, table)) {
    None => []
    Some((sql, args)) => db.all(sql, args).map(group_of)
  }
}

// ── the summary blocks (read/usage-summary-blocks.ts, read/usage-batched.ts) ──

///|
/// A group of a block or bucket as the statements give it: its dimensions as stored (no thread is 0, no person '') and
/// its amounts.
priv struct Part {
  day : String?
  session : String
  thread : Int64
  person : String
  profile : String
  runtime : String
  model : String
  fast : Int64
  mut parts : Int64
  amounts : FixedArray[Int64]
}

///|
let amount_names : Array[String] = ["calls", "input", "cache_read", "cache_write", "cache_write_long", "output"]

///|
fn int_of(v : Json) -> Int64 {
  match v {
    Number(n, ..) => n.to_int64()
    _ => 0L
  }
}

///|
fn text_of(v : Json) -> String {
  match v {
    String(s) => s
    _ => ""
  }
}

///|
fn part_of(r : Map[String, Json], day : String?, parts : Int64) -> Part {
  let amounts = FixedArray::make(6, 0L)
  for i, name in amount_names {
    amounts[i] = int_of(field(r, name))
  }
  {
    day,
    session: text_of(field(r, "session")),
    thread: int_of(field(r, "thread")),
    person: text_of(field(r, "person")),
    profile: text_of(field(r, "profile")),
    runtime: text_of(field(r, "runtime")),
    model: text_of(field(r, "model")),
    fast: int_of(field(r, "fast")),
    parts,
    amounts,
  }
}

///|
/// usage-batched.ts `groupKey` with its session (`totalKey`): what one group is.
fn part_key(p : Part) -> String {
  ([
    match p.day {
      Some(d) => Json::string(d)
      None => Json::null()
    },
    Json::string(p.session),
    Json::string(p.thread.to_string()),
    Json::string(p.person),
    Json::string(p.profile),
    Json::string(p.runtime),
    Json::string(p.model),
    Json::string(p.fast.to_string()),
  ]
  : Json).stringify()
}

///|
/// usage-batched.ts `add`: a part added to the group of its key.
fn add_part(groups : Map[String, Part], row : Part, sign? : Int64 = 1L) -> Unit {
  let key = part_key(row)
  match groups.get(key) {
    None => {
      let amounts = FixedArray::make(6, 0L)
      for i in 0..<6 {
        amounts[i] = row.amounts[i] * sign
      }
      groups[key] = { ..row, parts: row.parts * sign, amounts }
    }
    Some(held) => {
      held.parts += row.parts * sign
      for i in 0..<6 {
        held.amounts[i] += row.amounts[i] * sign
      }
    }
  }
}

///|
fn utf8_order(a : String, b : String) -> Int {
  by_bytes(a, b)
}

///|
/// usage-batched.ts `answer`: the groups in SQLite's GROUP BY order, as the usage page's rows.
fn parts_answer(groups : Array[Part]) -> Array[Group] raise {
  let safe = (n : Int64) => {
    if n > 9007199254740991L || n < -9007199254740991L {
      raise Failure("integer is too large to be represented as a JavaScript number")
    }
    n.to_double()
  }
  let sorted = groups.copy()
  sorted.sort_by((a, b) => {
    let day = match (a.day, b.day) {
      (None, None) => 0
      (None, _) => -1
      (_, None) => 1
      (Some(x), Some(y)) => utf8_order(x, y)
    }
    if day != 0 {
      return day
    }
    let order = [
      utf8_order(a.session, b.session),
      a.thread.compare(b.thread),
      utf8_order(a.person, b.person),
      utf8_order(a.profile, b.profile),
      utf8_order(a.runtime, b.runtime),
      utf8_order(a.model, b.model),
      a.fast.compare(b.fast),
    ]
    for o in order {
      if o != 0 {
        return o
      }
    }
    0
  })
  sorted.map(p => {
    day: p.day.unwrap_or(""),
    session: Json::string(p.session),
    thread: if p.thread == 0L { Json::null() } else { Json::number(safe(p.thread)) },
    person: if p.person == "" { Json::null() } else { Json::string(p.person) },
    profile: if p.profile == "" { Json::null() } else { Json::string(p.profile) },
    runtime: Json::string(p.runtime),
    model: if p.model == "" { Json::null() } else { Json::string(p.model) },
    fast: safe(p.fast) != 0.0,
    calls: safe(p.amounts[0]),
    input: safe(p.amounts[1]),
    cache_read: safe(p.amounts[2]),
    cache_write: safe(p.amounts[3]),
    cache_write_long: safe(p.amounts[4]),
    output: safe(p.amounts[5]),
  })
}

///|
let block_dimensions : String = "session, thread, person, profile, runtime, model, fast"

///|
let block_amounts : String = "calls, input, cache_read, cache_write, cache_write_long, output"

///|
let block_key : Array[String] = ["session", "minute", "thread", "person", "profile", "runtime", "model", "fast"]

///|
/// usage-summary-blocks.ts `usageSummaryBlockQueries`.
fn block_selected_sql(scoped : Bool, size : Int64) -> String {
  let source = if size == 1L { "usage_summary_blocks_shadow" } else { "usage_summary_blocks" }
  let index = if !scoped {
    Some("\{source}_time")
  } else if size == 1L {
    Some("\{source}_scope_time")
  } else {
    None
  }
  let period = if size == 1L { "minute" } else { "bucket" }
  let scope = if scoped { "scope = ?3 AND " } else { "" }
  let level = if size == 1L { "" } else { "level = \{size} AND " }
  let indexed = match index {
    Some(i) => " INDEXED BY \{i}"
    None => ""
  }
  "SELECT \{block_dimensions}, \{if size == 1L { "1" } else { "parts" }} AS parts, \{block_amounts}\n      FROM \{source}\{indexed} WHERE \{scope}\{level}\{period} >= ?1 AND \{period} < ?2"
}

///|
fn block_next_sql(scoped : Bool) -> String {
  if scoped {
    "SELECT bucket FROM usage_summary_blocks WHERE scope = ?3 AND level = 60 AND bucket >= ?1 AND bucket < ?2 ORDER BY bucket LIMIT 1"
  } else {
    "SELECT bucket FROM usage_summary_blocks INDEXED BY usage_summary_blocks_time WHERE level = 60 AND bucket >= ?1 AND bucket < ?2 ORDER BY bucket LIMIT 1"
  }
}

///|
fn block_last_sql(scoped : Bool) -> String {
  if scoped {
    "SELECT bucket FROM usage_summary_blocks WHERE scope = ? AND level = 60 ORDER BY bucket DESC LIMIT 1"
  } else {
    "SELECT bucket FROM usage_summary_blocks INDEXED BY usage_summary_blocks_time WHERE level = 60 ORDER BY bucket DESC LIMIT 1"
  }
}

///|
/// usage-summary-blocks.ts `usageSummaryBlockPendingQuery`.
fn block_pending_sql(side : String) -> String {
  let predicate = if side == "time" {
    "minute >= ?1 AND minute < ?2"
  } else {
    "\{side}_scope = ?3 AND minute >= ?1 AND minute < ?2"
  }
  "SELECT \{block_key.join(", ")} FROM usage_summary_blocks_dirty INDEXED BY usage_summary_blocks_dirty_\{side} WHERE \{predicate} LIMIT 65"
}

///|
/// usage-summary-blocks.ts `usageSummaryBlockOverlayQuery`.
fn block_overlay_sql(current : Bool) -> String {
  let where_ = block_key.map(name => "\{name} = ?").join(" AND ")
  let source = if current { "usage_compact" } else { "usage_summary_blocks_shadow" }
  "SELECT \{block_key.join(", ")}, scope, \{block_amounts}, 1 AS parts FROM \{source} WHERE \{where_}" +
  (if current { " AND records > 0" } else { "" })
}

///|
/// usage-summary-blocks.ts `usageSummaryBlocksReady`.
fn blocks_ready(db : @sql.Db, scope : String?) -> Bool raise {
  if done_of(db, "SELECT done FROM usage_summary_blocks_progress WHERE id = 1") == Json::number(1.0) {
    return true
  }
  match scope {
    None | Some("G") => false
    Some(s) =>
      match one(db, "SELECT done FROM usage_summary_blocks_scope_progress WHERE scope = ?", [Json::string(s)]) {
        Some(r) => field(r, "done") == Json::number(1.0)
        None => false
      }
  }
}

///|
/// The ISO day of a time, ms (`new Date(ms).toISOString().slice(0, 10)`).
fn iso_day(ms : Int64) -> String raise {
  let iso = @history.date_iso(ms.to_double())
  sub(iso, 0, if iso.length() < 10 { iso.length() } else { 10 })
}

///|
/// usage-summary-blocks.ts `usageGroupsFromBlocks`: the edge minutes and the quarter and hour blocks of each day asked,
/// a few changed buckets laid over them; none where only the exact path can answer.
fn groups_from_blocks(db : @sql.Db, from : Int64, to : Int64, offset : Int64, viewer : Viewer?, prepared : Bool?) -> Array[Part]? raise {
  if offset < -1440L || offset > 1440L || from % 60_000L != 0L || (to != i64_top && to % 60_000L != 0L) {
    return None
  }
  if from >= to {
    return Some([])
  }
  if !table_installed(db, "usage_summary_blocks_progress") {
    if prepared is Some(_) {
      raise Refused(503, summary_pending)
    }
    return None
  }
  let scopes : Array[String?] = match viewer {
    None => [None]
    Some(v) => if v.home { [Some("W" + v.workspace), Some("H")] } else { [Some("W" + v.workspace)] }
  }
  if !(prepared is Some(true)) {
    for scope in scopes {
      if !blocks_ready(db, scope) {
        raise Refused(503, summary_pending)
      }
    }
  }
  let start = from / 60_000L
  let mut end = if to == i64_top { i64_top } else { to / 60_000L }
  let changed : Map[String, Map[String, Json]] = Map([])
  for scope in scopes {
    let sides = if scope is None { ["time"] } else { ["old", "new"] }
    for side in sides {
      let params = match scope {
        None => [i64_json(start), i64_json(end)]
        Some(s) => [i64_json(start), i64_json(end), Json::string(s)]
      }
      let pending = db.all(block_pending_sql(side), params)
      for row in pending {
        changed[(Json::array(block_key.map(k => field(row, k))) : Json).stringify()] = row
      }
      if pending.length() > 64 || changed.length() > 64 {
        raise Refused(503, summary_pending)
      }
    }
  }
  if start >= end {
    return Some([])
  }
  if end == i64_top {
    let mut last : Int64? = None
    for scope in scopes {
      let row = match scope {
        None => one(db, block_last_sql(false), [])
        Some(s) => one(db, block_last_sql(true), [Json::string(s)])
      }
      if row is Some(r) {
        let bucket = int_of(field(r, "bucket"))
        if last is None || bucket > last.unwrap() {
          last = Some(bucket)
        }
      }
    }
    for row in changed.values() {
      let bucket = floor_div(int_of(field(row, "minute")), 60L)
      if last is None || bucket > last.unwrap() {
        last = Some(bucket)
      }
    }
    guard last is Some(l) else { return Some([]) }
    end = (l + 1L) * 60L
    if start >= end {
      return Some([])
    }
  }
  if start + offset < -1036120320L || end + offset > 4223371680L {
    return None
  }
  let selected : Map[String, Part] = Map([])
  let visible : Map[String, Bool] = Map([])
  let sees = (session : String) => match viewer {
    None => true
    Some(v) =>
      match visible.get(session) {
        Some(b) => b
        None => {
          let found = match one(db, "SELECT ws FROM usage_minute_scope WHERE session = ?", [Json::string(session)]) {
            Some(r) => viewer_sees(v, field(r, "ws"))
            None => false
          }
          visible[session] = found
          found
        }
      }
  }
  let next_day_with_usage = (from_minute : Int64) => {
    let mut next : Int64? = None
    for scope in scopes {
      let first = floor_div(from_minute, 60L)
      let after = floor_div(end - 1L, 60L) + 1L
      let row = match scope {
        None => one(db, block_next_sql(false), [i64_json(first), i64_json(after)])
        Some(s) => one(db, block_next_sql(true), [i64_json(first), i64_json(after), Json::string(s)])
      }
      if row is Some(r) {
        let bucket = int_of(field(r, "bucket"))
        let candidate = if bucket * 60L < from_minute { from_minute } else { bucket * 60L }
        if next is None || candidate < next.unwrap() {
          next = Some(candidate)
        }
      }
    }
    for row in changed.values() {
      let minute = int_of(field(row, "minute"))
      if minute >= from_minute && minute < end && (next is None || minute < next.unwrap()) {
        next = Some(minute)
      }
    }
    next
  }
  let read = (day : String, first : Int64, last : Int64, size : Int64) => {
    for scope in scopes {
      let rows = match scope {
        None => db.all(block_selected_sql(false, size), [i64_json(first / size), i64_json(last / size)])
        Some(s) => db.all(block_selected_sql(true, size), [i64_json(first / size), i64_json(last / size), Json::string(s)])
      }
      for r in rows {
        let block = part_of(r, Some(day), int_of(field(r, "parts")))
        if sees(block.session) {
          add_part(selected, block)
        }
      }
    }
  }
  let mut at = start
  while at < end {
    guard next_day_with_usage(at) is Some(next) else { break }
    at = next
    let local_day = floor_div(at + offset, 1440L) * 1440L
    let day_end = if local_day + 1440L - offset < end { local_day + 1440L - offset } else { end }
    let day = iso_day(local_day * 60_000L)
    while at < day_end {
      let mut size = 1L
      let mut stop = day_end
      if at % 60L == 0L && day_end - at >= 60L {
        size = 60L
        stop = at + (day_end - at) / 60L * 60L
      } else if at % 15L == 0L && day_end - at >= 15L {
        size = 15L
        let next = (floor_div(at, 60L) + 1L) * 60L
        stop = if next < day_end { next } else { at + (day_end - at) / 15L * 15L }
      } else {
        let next = (floor_div(at, 15L) + 1L) * 15L
        if next < stop {
          stop = next
        }
      }
      read(day, at, stop, size)
      at = stop
    }
  }
  let allowed = (scope : Json) => match viewer {
    None => true
    Some(_) => scopes.iter().any(c => c.map(Json::string).unwrap_or(Json::null()) == scope)
  }
  for change in changed.values() {
    let minute = int_of(field(change, "minute"))
    let session = text_of(field(change, "session"))
    if minute < start || minute >= end || !sees(session) {
      continue
    }
    let args = block_key.map(k => field(change, k))
    let before = one(db, block_overlay_sql(false), args)
    let after = one(db, block_overlay_sql(true), args)
    let day = iso_day(floor_div(minute + offset, 1440L) * 86_400_000L)
    if before is Some(b) && allowed(field(b, "scope")) {
      add_part(selected, part_of(b, Some(day), int_of(field(b, "parts"))), sign=-1L)
    }
    if after is Some(a) && allowed(field(a, "scope")) {
      add_part(selected, part_of(a, Some(day), int_of(field(a, "parts"))))
    }
  }
  Some(selected.values().filter(g => g.parts > 0L).collect())
}

///|
/// usage-batched.ts `usageSummaryEdgeQuery`: the original calls of a partial minute at an edge, of one scope.
fn summary_edge_sql(scope : String) -> String {
  let index = if scope == "all" { "usage_compact_time" } else { "usage_compact_scope_time" }
  let restriction = if scope == "all" { "" } else { "scope = ?3 AND " }
  let owner = if scope == "all" { "" } else { "CROSS JOIN usage_minute_scope sc ON sc.session = p.session" }
  let visible = if scope == "all" { "" } else if scope == "home" { " AND sc.ws IS NULL" } else { " AND sc.ws = ?6" }
  "WITH selected AS MATERIALIZED (\n      SELECT DISTINCT session FROM usage_compact INDEXED BY \{index} WHERE \{restriction}minute = ?1 AND records > 0\n" +
  "    ) SELECT strftime('%Y-%m-%d', (?1 + ?2) * 60, 'unixepoch') AS day, u.session,\n" +
  "      COALESCE(u.thread, 0) AS thread, COALESCE(u.person, '') AS person, COALESCE(u.profile, '') AS profile,\n" +
  "      u.runtime, COALESCE(u.model, '') AS model, u.fast, u.calls, u.input, u.cache_read, u.cache_write,\n" +
  "      u.cache_write_long, u.output\n" +
  "    FROM selected p \{owner} CROSS JOIN usage u INDEXED BY usage_session\n" +
  "      ON u.session = p.session AND u.at >= ?4 AND u.at < ?5\n" +
  "    WHERE u.compact_counted = 1\{visible}"
}

///|
/// usage-batched.ts `batchedUsageQueries`: the sessions a time range names, and one session's minute statistics.
fn batched_selected_sql(viewer : Viewer?) -> String {
  match viewer {
    None => "SELECT session FROM usage_compact INDEXED BY usage_compact_time WHERE minute >= ?1 AND minute < ?2"
    Some(v) =>
      "SELECT session FROM usage_compact INDEXED BY usage_compact_scope_time WHERE " +
      (if v.home { "scope IN (?3, 'H') AND " } else { "scope = ?3 AND " }) +
      "minute >= ?1 AND minute < ?2"
  }
}

///|
fn batched_buckets_sql(viewer : Viewer?) -> String {
  "SELECT strftime('%Y-%m-%d', (minute + ?1) * 60, 'unixepoch') AS day, minute, " +
  "session, thread, person, profile, runtime, model, fast, calls, input, cache_read, cache_write, cache_write_long, output " +
  "FROM usage_compact WHERE session = ?2 AND minute >= ?3 AND minute < ?4" +
  (match viewer {
    None => ""
    Some(v) => if v.home { " AND scope IN (?5, 'H')" } else { " AND scope = ?5" }
  }) +
  " AND records > 0"
}

///|
/// The ranges a reader has seen prepared since its schema last changed (usage-batched.ts UsageSummaryCache `prepared`),
/// the latest last: a range prepared stays so while its later writes are tracked, so asking it again without saying so
/// takes it as prepared.
let summary_proofs : Ref[(Json, Array[String])] = { val: (Json::null(), []) }

///|
fn proofs_of(db : @sql.Db) -> Array[String] raise {
  let version = match one(db, "PRAGMA schema_version", []) {
    Some(r) => field(r, "schema_version")
    None => Json::null()
  }
  if summary_proofs.val.0 != version {
    summary_proofs.val = (version, [])
  }
  summary_proofs.val.1
}

///|
/// usage-batched.ts `usageGroupsBatched`: the groups from the summary blocks with the edges' calls, or where the
/// blocks cannot answer, each session's minute statistics; none where the page reads them the plain way
/// (`usageGroups`). `prepared`: whether the page waited for the range to be prepared (none: it does not wait).
fn usage_groups_batched(db : @sql.Db, from : Int64, to : Int64, offset : Int64, viewer : Viewer?, prepared : Bool?) -> Array[Group]? raise {
  if !has_compact(db) {
    if prepared is Some(_) && from < to {
      raise Refused(503, summary_pending)
    }
    return None
  }
  let partial = from < to && (from % 60_000L != 0L || (to != i64_top && to % 60_000L != 0L))
  if partial && prepared is None && !table_installed(db, "usage_summary_blocks_progress") {
    return None
  }
  if !compact_scope_ready(db, viewer) {
    raise Refused(503, moving_refusal)
  }
  let start = if from >= to { 0L } else { floor_div(from, 60_000L) }
  let end = if from >= to { 0L } else if to == i64_top { i64_top } else { floor_div(to, 60_000L) }
  let prepared_key = ([
    Json::string(from.to_string()),
    Json::string(to.to_string()),
    match viewer {
      Some(v) => Json::string(v.workspace)
      None => Json::null()
    },
    match viewer {
      Some(v) => Json::boolean(v.home)
      None => Json::null()
    },
  ]
  : Json).stringify()
  let can_reuse = if prepared is Some(false) {
    let proofs = proofs_of(db)
    match proofs.search(prepared_key) {
      Some(i) => {
        proofs.remove(i) |> ignore
        proofs.push(prepared_key)
        true
      }
      None => false
    }
  } else {
    false
  }
  let mut inner_from = from
  let mut inner_to = to
  let edges : Array[(Int64, Int64, Int64)] = []
  if partial {
    let size = 60_000L
    if from % size != 0L {
      let minute = floor_div(from, size)
      let next = (minute + 1L) * size
      let until = if next < to { next } else { to }
      edges.push((minute, from, until))
      inner_from = until
    }
    if to != i64_top && to % size != 0L {
      let minute = floor_div(to, size)
      let first = minute * size
      if first >= inner_from {
        edges.push((minute, first, to))
        inner_to = first
      } else {
        inner_to = inner_from
      }
    }
    if inner_from >= inner_to {
      inner_from = 0L
      inner_to = 0L
    }
  }
  let grouped = groups_from_blocks(db, inner_from, inner_to, offset, viewer, if can_reuse { Some(true) } else { prepared })
  if grouped is Some(blocks) {
    let combined : Map[String, Part] = Map([])
    for row in blocks {
      add_part(combined, row)
    }
    if prepared is Some(true) {
      let proofs = proofs_of(db)
      match proofs.search(prepared_key) {
        Some(i) => proofs.remove(i) |> ignore
        None => ()
      }
      while proofs.length() >= 16 {
        proofs.remove(0) |> ignore
      }
      proofs.push(prepared_key)
    }
    let scopes = match viewer {
      None => ["all"]
      Some(v) => if v.home { ["workspace", "home"] } else { ["workspace"] }
    }
    for edge in edges {
      for scope in scopes {
        let args = [
          i64_json(edge.0),
          i64_json(offset),
          match (scope, viewer) {
            ("all", _) => Json::null()
            ("home", _) => Json::string("H")
            (_, Some(v)) => Json::string("W" + v.workspace)
            _ => Json::null()
          },
          i64_json(edge.1),
          i64_json(edge.2),
        ]
        if scope == "workspace" && viewer is Some(v) {
          args.push(Json::string(v.workspace))
        }
        for r in db.all(summary_edge_sql(scope), args) {
          let day = match field(r, "day") { String(d) => Some(d); _ => None }
          add_part(combined, part_of(r, day, 1L))
        }
      }
    }
    return Some(parts_answer(combined.values().collect()))
  }
  // Each selected session's minute statistics, as a read with nothing kept makes it.
  let params = [i64_json(start), i64_json(end)]
  if viewer is Some(v) {
    params.push(Json::string("W" + v.workspace))
  }
  let sessions : Array[String] = []
  let seen : Set[String] = Set::new()
  for r in db.all(batched_selected_sql(viewer), params) {
    let s = text_of(field(r, "session"))
    if !seen.contains(s) {
      seen.add(s)
      sessions.push(s)
    }
  }
  let groups : Array[Part] = []
  for session in sessions {
    let visible = match viewer {
      None => true
      Some(v) =>
        match one(db, "SELECT ws FROM usage_minute_scope WHERE session = ?", [Json::string(session)]) {
          Some(r) => viewer_sees(v, field(r, "ws"))
          None => false
        }
    }
    if !visible || start >= end {
      continue
    }
    let args = [i64_json(offset), Json::string(session), i64_json(start), i64_json(end)]
    if viewer is Some(v) {
      args.push(Json::string("W" + v.workspace))
    }
    let of_session : Map[String, Part] = Map([])
    for r in db.all(batched_buckets_sql(viewer), args) {
      let day = match field(r, "day") { String(d) => Some(d); _ => None }
      add_part(of_session, part_of(r, day, 1L))
    }
    groups.append(of_session.values().collect())
  }
  Some(parts_answer(groups))
}
