// An older store's whole-store lookups, kept up in bounded steps, here for the MoonBit builders: the edit lookup
// (station/src/store/legacy-edits-build.ts: its old messages scanned, then the keys older writers changed folded back)
// and the said lookup (legacy-said-build.ts: its old messages scanned). Both were made when the store was opened; a
// merged view or widget trigger that must be switched first (`repairMergedEditLookup`, the store's schema upkeep) is
// left to the worker: `Fallback`.

///|
let version : Int = 1

///|
let batch : Int = 64

///|
/// The store needs the worker's schema repair before its edits can be prepared.
pub(all) suberror Fallback

///|
fn first(db : @sql.Db, sql : String, params : Array[Json]) -> Map[String, Json]? raise {
  match db.all(sql, params) {
    [r, ..] => Some(r)
    _ => None
  }
}

///|
fn exists(db : @sql.Db, kind : String, name : String) -> Bool raise {
  first(db, "SELECT 1 FROM sqlite_master WHERE type=? AND name=?", [Json::string(kind), Json::string(name)]) is Some(_)
}

///|
fn sql_of(db : @sql.Db, kind : String, name : String) -> String? raise {
  match first(db, "SELECT sql FROM sqlite_master WHERE type=? AND name=?", [Json::string(kind), Json::string(name)]) {
    Some(r) =>
      match r.get("sql") {
        Some(String(s)) => Some(s)
        _ => Some("")
      }
    None => None
  }
}

///|
fn get(row : Map[String, Json], name : String) -> Json {
  row.get(name).unwrap_or(Json::null())
}

///|
fn int(row : Map[String, Json], name : String) -> Int {
  match row.get(name) {
    Some(Number(n, ..)) => n.to_int()
    _ => -1
  }
}

///|
fn write(db : @sql.Db, f : () -> Int raise) -> Int raise {
  db.exec("BEGIN IMMEDIATE")
  errdefer (db.exec("ROLLBACK") catch { _ => () })
  let result = f()
  db.exec("COMMIT")
  result
}

///|
/// A scan's state (`legacy_edit_meta`, `legacy_said_meta`), its keys as text.
fn meta(db : @sql.Db, table : String) -> Map[String, Json] raise {
  guard first(
      db,
      "SELECT version,scanned,CAST(cursor_thread AS TEXT) cursor_thread,CAST(cursor_n AS TEXT) cursor_n,CAST(end_thread AS TEXT) end_thread,CAST(end_n AS TEXT) end_n FROM \{table} WHERE id=1",
      [],
    )
    is Some(m) else {
    raise Failure("\{table} has no row")
  }
  m
}

///|
/// The next at most `limit` entries' keys after the cursor up to the end the scan began with, in (thread, n) order.
fn scan_keys(db : @sql.Db, m : Map[String, Json], limit : Int) -> Array[Map[String, Json]] raise {
  let columns = "CAST(e.thread AS TEXT) thread,CAST(e.n AS TEXT) n"
  let cursor_thread = get(m, "cursor_thread")
  let cursor_n = get(m, "cursor_n")
  let end_thread = get(m, "end_thread")
  let end_n = get(m, "end_n")
  let rows = []
  if end_thread is Null {
    return rows
  }
  let lim = (n : Int) => Json::number(n.to_double())
  if !(cursor_thread is Null) {
    if cursor_thread == end_thread {
      rows.append(
        db.all(
          "SELECT \{columns} FROM entries e WHERE e.thread=CAST(?1 AS INTEGER) AND e.n>CAST(?2 AS INTEGER) AND e.n<=CAST(?3 AS INTEGER) ORDER BY e.n LIMIT ?4",
          [cursor_thread, cursor_n, end_n, lim(limit)],
        ),
      )
    } else {
      rows.append(
        db.all(
          "SELECT \{columns} FROM entries e WHERE e.thread=CAST(?1 AS INTEGER) AND e.n>CAST(?2 AS INTEGER) ORDER BY e.n LIMIT ?3",
          [cursor_thread, cursor_n, lim(limit)],
        ),
      )
    }
  }
  if rows.length() < limit && cursor_thread != end_thread {
    if cursor_thread is Null {
      rows.append(
        db.all(
          "SELECT \{columns} FROM entries e WHERE e.thread<CAST(?1 AS INTEGER) ORDER BY e.thread,e.n LIMIT ?2",
          [end_thread, lim(limit - rows.length())],
        ),
      )
    } else {
      rows.append(
        db.all(
          "SELECT \{columns} FROM entries e WHERE e.thread<CAST(?1 AS INTEGER) AND e.thread>CAST(?2 AS INTEGER) ORDER BY e.thread,e.n LIMIT ?3",
          [end_thread, cursor_thread, lim(limit - rows.length())],
        ),
      )
    }
    if rows.length() < limit {
      rows.append(
        db.all(
          "SELECT \{columns} FROM entries e WHERE e.thread=CAST(?1 AS INTEGER) AND e.n<=CAST(?2 AS INTEGER) ORDER BY e.n LIMIT ?3",
          [end_thread, end_n, lim(limit - rows.length())],
        ),
      )
    }
  }
  rows
}

///|
/// One batch of a scan: each key's row put (`put`, `?1` thread, `?2` n), the cursor moved with them; the scan's
/// size then.
fn scan_step(db : @sql.Db, table : String, put : String, incompatible : (Json) -> String) -> Int raise {
  write(db, () => {
    let m = meta(db, table)
    if int(m, "version") != version {
      raise Failure(incompatible(get(m, "version")))
    }
    if int(m, "scanned") == 1 {
      return 0
    }
    let rows = scan_keys(db, m, batch)
    for row in rows {
      ignore(db.run(put, [get(row, "thread"), get(row, "n")]))
    }
    let (thread, n) = match rows.last() {
      Some(r) => (get(r, "thread"), get(r, "n"))
      None => (get(m, "cursor_thread"), get(m, "cursor_n"))
    }
    ignore(
      db.run(
        "UPDATE \{table} SET scanned=?,cursor_thread=CAST(? AS INTEGER),cursor_n=CAST(? AS INTEGER) WHERE id=1",
        [Json::number(if rows.length() < batch { 1.0 } else { 0.0 }), thread, n],
      ),
    )
    rows.length()
  })
}

// The edit lookup.

///|
fn has_legacy_edits(db : @sql.Db) -> Bool raise {
  if !exists(db, "table", "legacy_edit_meta") {
    return false
  }
  guard first(db, "SELECT version,scanned,old_index FROM legacy_edit_meta WHERE id=1", []) is Some(m) &&
    int(m, "version") == version &&
    (int(m, "scanned") == 0 || int(m, "scanned") == 1) &&
    (int(m, "old_index") == 0 || int(m, "old_index") == 1) else {
    raise Failure("legacy edit lookup has an unsupported version")
  }
  true
}

///|
/// An old store's (thread, target) index, as the edit lookup's fallback reads it (`hasOldEditIndex`).
fn has_old_edit_index(db : @sql.Db) -> Bool raise {
  let columns = db.all(
    "SELECT name,coll FROM pragma_index_xinfo('entries_target') WHERE \"key\"=1 ORDER BY seqno",
    [],
  )
  guard columns is [a, b] &&
    get(a, "name") == Json::string("thread") &&
    get(a, "coll") == Json::string("BINARY") &&
    get(b, "name") == Json::string("target") &&
    get(b, "coll") == Json::string("BINARY") else {
    return false
  }
  ignore(
    db.all(
      "EXPLAIN QUERY PLAN SELECT MAX(n) FROM entries INDEXED BY entries_target WHERE thread=? AND target=?",
      [Json::number(0.0), Json::number(0.0)],
    ),
  ) catch {
    _ => return false
  }
  true
}

///|
/// The edits read through the lookup: the native index absent (`usesLegacyEdits`).
fn uses_legacy_edits(db : @sql.Db) -> Bool raise {
  !exists(db, "index", "entries_edits") && has_legacy_edits(db)
}

///|
/// A single merged message can be read: the scan done and at most one batch of changed keys left
/// (`legacyMergedReadReady`), as the merged view now reads.
fn edits_ready(db : @sql.Db) -> Bool raise {
  let view = sql_of(db, "view", "merged").unwrap_or("")
  let legacy = view.contains("legacy_edit_meta")
  let old_index = legacy && view.contains("INDEXED BY entries_target")
  if old_index && !has_old_edit_index(db) {
    return false
  }
  if !legacy {
    return exists(db, "index", "entries_edits")
  }
  guard first(
      db,
      "SELECT scanned=1 AND NOT EXISTS (SELECT 1 FROM legacy_edit_dirty LIMIT 1 OFFSET 64) AS ready FROM legacy_edit_meta WHERE id=1",
      [],
    )
    is Some(r) else {
    raise Failure("legacy edit lookup metadata is missing")
  }
  int(r, "ready") == 1
}

///|
/// The merged view or the widget sources' trigger must be switched to the indexes there now
/// (`repairMergedEditLookup` would change something).
fn needs_repair(db : @sql.Db) -> Bool raise {
  let view = sql_of(db, "view", "merged").unwrap_or("")
  let view_broken = if view.contains("legacy_edit_meta") {
    view.contains("INDEXED BY entries_target") && !has_old_edit_index(db)
  } else {
    !exists(db, "index", "entries_edits")
  }
  if view_broken {
    return true
  }
  // (`widgetSourceBeforeAddNeedsRepair`)
  guard sql_of(db, "trigger", "widget_source_before_add") is Some(add) else { return false }
  let gated = add.contains("widget_source_before_gate")
  let gate = exists(db, "view", "widget_source_before_gate")
  let run = sql_of(db, "trigger", "widget_source_before_gate_run")
  let legacy = uses_legacy_edits(db)
  let old_index = legacy &&
    int(first(db, "SELECT old_index FROM legacy_edit_meta WHERE id=1", []).unwrap_or(Map([])), "old_index") == 1
  gated != legacy ||
  gate != legacy ||
  (run is Some(_)) != legacy ||
  (!gated && add.contains("FROM entries x INDEXED BY entries_target")) ||
  (legacy && run is Some(r) && r.contains("INDEXED BY entries_target") != old_index)
}

///|
/// The changed keys folded back into the lookup, at most a batch of work (`legacyEditDrain`): a key's targets proposed
/// by other writes removed first, then the key itself.
fn edits_drain(db : @sql.Db) -> Int raise {
  write(db, () => {
    let m = meta(db, "legacy_edit_meta")
    if int(m, "version") != version {
      raise Failure("unsupported legacy edit preparation")
    }
    if int(m, "scanned") != 1 {
      return 0
    }
    let mut visited = 0
    while visited < batch {
      guard first(
          db,
          "SELECT CAST(d.thread AS TEXT) thread,CAST(d.n AS TEXT) n FROM legacy_edit_dirty d ORDER BY d.thread,d.n LIMIT 1",
          [],
        )
        is Some(key) else {
        break
      }
      let k = [get(key, "thread"), get(key, "n")]
      // (the targets stay in SQLite: an old store's can be of any type, or integers beyond 2^53)
      visited += db.run(
        "DELETE FROM legacy_edit_targets WHERE thread=CAST(?1 AS INTEGER) AND n=CAST(?2 AS INTEGER) AND target IN (SELECT target FROM legacy_edit_targets INDEXED BY legacy_edit_targets_by_key WHERE thread=CAST(?1 AS INTEGER) AND n=CAST(?2 AS INTEGER) AND target IS NOT (SELECT target FROM entries WHERE thread=CAST(?1 AS INTEGER) AND n=CAST(?2 AS INTEGER)) ORDER BY target LIMIT ?3)",
        k + [Json::number((batch - visited).to_double())],
      )
      if visited == batch {
        break
      }
      ignore(
        db.run(
          "DELETE FROM legacy_edit_build WHERE thread=CAST(?1 AS INTEGER) AND n=CAST(?2 AS INTEGER) AND target IS (SELECT old_target FROM legacy_edit_dirty WHERE thread=CAST(?1 AS INTEGER) AND n=CAST(?2 AS INTEGER))",
          k,
        ),
      )
      ignore(
        db.run(
          "INSERT INTO legacy_edit_build(thread,target,n) SELECT thread,target,n FROM entries WHERE thread=CAST(? AS INTEGER) AND n=CAST(? AS INTEGER) AND target IS NOT NULL ON CONFLICT(thread,target,n) DO NOTHING",
          k,
        ),
      )
      ignore(
        db.run(
          "DELETE FROM legacy_edit_targets WHERE thread=CAST(?1 AS INTEGER) AND n=CAST(?2 AS INTEGER) AND target IS (SELECT target FROM entries WHERE thread=CAST(?1 AS INTEGER) AND n=CAST(?2 AS INTEGER))",
          k,
        ),
      )
      ignore(db.run("DELETE FROM legacy_edit_dirty WHERE thread=CAST(? AS INTEGER) AND n=CAST(? AS INTEGER)", k))
      visited += 1
    }
    visited
  })
}

///|
/// One step of the edit lookup's upkeep (said-worker.ts `legacyEdits`); whether a merged message can be read then.
/// A store whose merged view must be switched first raises `Fallback`.
pub fn edits_step(db : @sql.Db) -> Bool raise {
  if edits_ready(db) {
    return true
  }
  if needs_repair(db) {
    raise Fallback
  }
  // (`legacyEditsMaintenanceStep`: the scan, then the changed keys)
  if has_legacy_edits(db) {
    if int(meta(db, "legacy_edit_meta"), "scanned") != 1 {
      ignore(
        scan_step(
          db,
          "legacy_edit_meta",
          "INSERT INTO legacy_edit_build(thread,target,n) SELECT e.thread,e.target,e.n FROM entries e WHERE e.thread=CAST(?1 AS INTEGER) AND e.n=CAST(?2 AS INTEGER) AND e.target IS NOT NULL AND NOT EXISTS (SELECT 1 FROM legacy_edit_dirty d WHERE d.thread=e.thread AND d.n=e.n) ON CONFLICT(thread,target,n) DO NOTHING",
          _ => "unsupported legacy edit preparation",
        ),
      )
    } else {
      ignore(edits_drain(db))
    }
  }
  edits_ready(db)
}

// The said lookup.

///|
fn has_legacy_said(db : @sql.Db) -> Bool raise {
  if !exists(db, "view", "legacy_said") {
    return false
  }
  if !exists(db, "table", "legacy_said_meta") {
    raise Failure("legacy said view has no metadata")
  }
  guard first(db, "SELECT version,scanned FROM legacy_said_meta WHERE id=1", []) is Some(m) &&
    int(m, "version") == version &&
    (int(m, "scanned") == 0 || int(m, "scanned") == 1) else {
    raise Failure("legacy said view has an unsupported version")
  }
  true
}

///|
fn said_scanned(db : @sql.Db) -> Bool raise {
  guard first(db, "SELECT version,scanned FROM legacy_said_meta WHERE id=1", []) is Some(m) &&
    int(m, "version") == version &&
    (int(m, "scanned") == 0 || int(m, "scanned") == 1) else {
    raise Failure("legacy said lookup metadata is missing or invalid")
  }
  int(m, "scanned") == 1
}

///|
/// One batch of the said lookup's old scan (said-worker.ts `legacySaid`); whether it is done (or the store has none).
pub fn said_step(db : @sql.Db) -> Bool raise {
  if has_legacy_said(db) && !said_scanned(db) {
    ignore(
      scan_step(
        db,
        "legacy_said_meta",
        "INSERT INTO legacy_said_build(thread,n,author_kind,author) SELECT thread,n,author_kind,author FROM entries WHERE thread=CAST(?1 AS INTEGER) AND n=CAST(?2 AS INTEGER) AND kind='message' AND letter IS NULL ON CONFLICT(thread,n) DO UPDATE SET author_kind=excluded.author_kind,author=excluded.author",
        v => "legacy said version \{v.stringify()} is incompatible with \{version}",
      ),
    )
  }
  !has_legacy_said(db) || said_scanned(db)
}
