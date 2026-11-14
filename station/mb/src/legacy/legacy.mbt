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
/// One batch of the edit lookup's upkeep, as the store keeps it after a handover (`legacyEditsMaintenanceStep`): the
/// scan, then the changed keys; whether nothing is left then.
pub fn edits_maintenance(db : @sql.Db) -> Bool raise {
  if !has_legacy_edits(db) {
    return true
  }
  if int(meta(db, "legacy_edit_meta"), "scanned") != 1 {
    ignore(
      scan_step(
        db,
        "legacy_edit_meta",
        "INSERT INTO legacy_edit_build(thread,target,n) SELECT e.thread,e.target,e.n FROM entries e WHERE e.thread=CAST(?1 AS INTEGER) AND e.n=CAST(?2 AS INTEGER) AND e.target IS NOT NULL AND NOT EXISTS (SELECT 1 FROM legacy_edit_dirty d WHERE d.thread=e.thread AND d.n=e.n) ON CONFLICT(thread,target,n) DO NOTHING",
        _ => "unsupported legacy edit preparation",
      ),
    )
    return false
  }
  edits_drain(db) < batch
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
  ignore(edits_maintenance(db))
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
    ignore(said_scan(db))
  }
  !has_legacy_said(db) || said_scanned(db)
}

///|
fn said_scan(db : @sql.Db) -> Int raise {
  scan_step(
    db,
    "legacy_said_meta",
    "INSERT INTO legacy_said_build(thread,n,author_kind,author) SELECT thread,n,author_kind,author FROM entries WHERE thread=CAST(?1 AS INTEGER) AND n=CAST(?2 AS INTEGER) AND kind='message' AND letter IS NULL ON CONFLICT(thread,n) DO UPDATE SET author_kind=excluded.author_kind,author=excluded.author",
    said_incompatible,
  )
}

///|
let said_incompatible : (Json) -> String = v => "legacy said version \{v.stringify()} is incompatible with \{version}"

///|
/// The keys older writers changed folded back into the said lookup, at most a batch (`legacySaidDrain`).
fn said_drain(db : @sql.Db) -> Int raise {
  write(db, () => {
    let m = meta(db, "legacy_said_meta")
    if int(m, "version") != version {
      raise Failure(said_incompatible(get(m, "version")))
    }
    let keys = db.all(
      "SELECT CAST(d.thread AS TEXT) thread,CAST(d.n AS TEXT) n FROM legacy_said_dirty d ORDER BY d.thread,d.n LIMIT ?",
      [Json::number(batch.to_double())],
    )
    for key in keys {
      let k = [get(key, "thread"), get(key, "n")]
      ignore(db.run("DELETE FROM legacy_said_build WHERE thread=CAST(? AS INTEGER) AND n=CAST(? AS INTEGER)", k))
      ignore(
        db.run(
          "INSERT INTO legacy_said_build(thread,n,author_kind,author) SELECT thread,n,author_kind,author FROM entries WHERE thread=CAST(? AS INTEGER) AND n=CAST(? AS INTEGER) AND kind='message' AND letter IS NULL",
          k,
        ),
      )
      ignore(db.run("DELETE FROM legacy_said_dirty WHERE thread=CAST(? AS INTEGER) AND n=CAST(? AS INTEGER)", k))
    }
    keys.length()
  })
}

///|
/// One batch of the said lookup's upkeep after a handover (`legacySaidMaintenanceStep`): the scan, then the changed
/// keys; whether nothing is left then.
pub fn said_maintenance(db : @sql.Db) -> Bool raise {
  if !has_legacy_said(db) {
    return true
  }
  if !said_scanned(db) {
    ignore(said_scan(db))
    return false
  }
  said_drain(db) < batch
}

// Lookups copied from their source by id up to the last id when they were made: the archive policy
// (archive-policy-index.ts), the decisions by time (legacy-decision-time.ts) and by session
// (legacy-decision-session.ts, and its repair beside an old table whose index was removed).

///|
/// The meta row's state, checked: `complete` (or 2 where `two` allows it), else `unsupported`.
fn checked_state(db : @sql.Db, table : String, unsupported : String, two? : Bool = false) -> Int raise {
  guard first(db, "SELECT version,complete FROM \{table} WHERE id=1", []) is Some(m) &&
    int(m, "version") == version &&
    (int(m, "complete") == 0 || int(m, "complete") == 1 || (two && int(m, "complete") == 2)) else {
    raise Failure(unsupported)
  }
  int(m, "complete")
}

///|
fn has_policy(db : @sql.Db) -> Bool raise {
  if !exists(db, "table", "archive_policy_lookup_meta") {
    return false
  }
  ignore(checked_state(db, "archive_policy_lookup_meta", "archive policy lookup has an unsupported version"))
  true
}

///|
fn has_decision_time(db : @sql.Db) -> Bool raise {
  if !exists(db, "table", "legacy_decision_time_meta") {
    return false
  }
  if !exists(db, "table", "legacy_decision_time") {
    raise Failure("legacy decision-time metadata has no lookup")
  }
  ignore(checked_state(db, "legacy_decision_time_meta", "legacy decision-time lookup has an unsupported version"))
  true
}

///|
/// A decision-session lookup's state (`sessionState`): none, or 0/1 (2: the repair's table being emptied).
fn session_state(db : @sql.Db, table : String) -> Int? raise {
  if !exists(db, "table", "\{table}_meta") {
    return None
  }
  if !exists(db, "table", table) {
    raise Failure("legacy decision-session metadata has no lookup")
  }
  Some(
    checked_state(
      db,
      "\{table}_meta",
      "legacy decision-session lookup has an unsupported version",
      two=table == "legacy_decision_session_repair",
    ),
  )
}

///|
fn has_session_lookup(db : @sql.Db, table : String) -> Bool raise {
  match session_state(db, table) {
    Some(s) if s != 2 => exists(db, "index", "\{table}_by_session")
    _ => false
  }
}

///|
/// At most `limit` source ids copied into a lookup by `put` (`?1` the id), with the cursor; whether all are then.
/// `gate`: the lookup is there to copy into (checked again under the write lock).
fn copy_ids(
  db : @sql.Db,
  meta_table : String,
  source : String,
  put : String,
  incompatible : String,
  limit : Int,
  gate : () -> Bool raise,
) -> Bool raise {
  if !gate() {
    return true
  }
  write(db, () => {
    if !gate() {
      return 1
    }
    guard first(
        db,
        "SELECT version,complete,CAST(cursor AS TEXT) cursor,CAST(end_id AS TEXT) end_id FROM \{meta_table} WHERE id=1",
        [],
      )
      is Some(m) else {
      raise Failure(incompatible)
    }
    if int(m, "version") != version {
      raise Failure(incompatible)
    }
    if int(m, "complete") == 1 {
      return 1
    }
    let cursor = get(m, "cursor")
    let end = get(m, "end_id")
    let lim = Json::number(limit.to_double())
    let rows = if end is Null {
      []
    } else if cursor is Null {
      db.all(
        "SELECT CAST(id AS TEXT) AS id FROM \{source} WHERE id<=CAST(?1 AS INTEGER) ORDER BY \{source}.id LIMIT ?2",
        [end, lim],
      )
    } else {
      db.all(
        "SELECT CAST(id AS TEXT) AS id FROM \{source} WHERE id>CAST(?1 AS INTEGER) AND id<=CAST(?2 AS INTEGER) ORDER BY \{source}.id LIMIT ?3",
        [cursor, end, lim],
      )
    }
    for row in rows {
      ignore(db.run(put, [get(row, "id")]))
    }
    let done = rows.length() < limit
    let reached = match rows.last() {
      Some(r) => get(r, "id")
      None => cursor
    }
    ignore(
      db.run("UPDATE \{meta_table} SET cursor=CAST(? AS INTEGER),complete=? WHERE id=1", [
        reached,
        Json::number(if done { 1.0 } else { 0.0 }),
      ]),
    )
    if done { 1 } else { 0 }
  }) ==
  1
}

///|
/// One batch of the archive policy lookup (`archivePolicyIndexStep`).
pub fn policy_step(db : @sql.Db) -> Bool raise {
  copy_ids(
    db,
    "archive_policy_lookup_meta",
    "archive_policy",
    "INSERT INTO archive_policy_lookup(id,ws) SELECT p.id,p.ws FROM archive_policy p WHERE p.id=CAST(?1 AS INTEGER) AND NOT EXISTS (SELECT 1 FROM archive_policy_lookup k WHERE k.id=p.id)",
    "unsupported archive policy preparation",
    batch,
    () => has_policy(db),
  )
}

///|
/// One batch of the decisions-by-time lookup (`decisionTimeIndexStep`).
pub fn decision_time_step(db : @sql.Db) -> Bool raise {
  copy_ids(
    db,
    "legacy_decision_time_meta",
    "decision_checks",
    "INSERT INTO legacy_decision_time(id,created_at,session) SELECT id,created_at,session FROM decision_checks d WHERE d.id=CAST(?1 AS INTEGER) AND NOT EXISTS (SELECT 1 FROM legacy_decision_time l WHERE l.id=d.id)",
    "unsupported legacy decision-time preparation",
    batch,
    () => has_decision_time(db),
  )
}

///|
fn session_put(table : String) -> String {
  "INSERT INTO \{table}(id,session) SELECT id,session FROM decision_checks d WHERE d.id=CAST(?1 AS INTEGER) AND NOT EXISTS (SELECT 1 FROM \{table} l WHERE l.id=d.id)"
}

///|
/// One batch of the decisions-by-session lookup (`decisionSessionIndexStep`).
pub fn decision_session_step(db : @sql.Db) -> Bool raise {
  let table = "legacy_decision_session"
  copy_ids(
    db,
    "\{table}_meta",
    "decision_checks",
    session_put(table),
    "unsupported legacy decision-session preparation",
    batch,
    () => has_session_lookup(db, table),
  )
}

///|
let repair : String = "legacy_decision_session_repair"

///|
fn repair_reconcile(ids : String) -> String {
  "DELETE FROM \{repair} WHERE id IN (\{ids}); INSERT INTO \{repair}(id,session) SELECT id,session FROM decision_checks WHERE id IN (\{ids});"
}

///|
/// The repair's index and triggers (as `REPAIR_INDEX`, `REPAIR_TRIGGERS`), made once its old rows are gone.
let repair_ddl : String = [
  "CREATE INDEX \{repair}_by_session ON \{repair}(session);",
  "CREATE TRIGGER \{repair}_insert AFTER INSERT ON decision_checks BEGIN INSERT INTO \{repair}(id,session) SELECT id,session FROM decision_checks WHERE id=NEW.id ON CONFLICT(id) DO UPDATE SET session=excluded.session; END;",
  "CREATE TRIGGER \{repair}_update AFTER UPDATE OF id,session ON decision_checks WHEN OLD.id IS NOT NEW.id OR OLD.session IS NOT NEW.session BEGIN \{repair_reconcile("OLD.id,NEW.id")} END;",
  "CREATE TRIGGER \{repair}_delete AFTER DELETE ON decision_checks BEGIN \{repair_reconcile("OLD.id")} END;",
].join("\n")

///|
fn repair_needs_work(db : @sql.Db) -> Bool raise {
  match session_state(db, repair) {
    Some(2) => true
    Some(0) => has_session_lookup(db, repair)
    _ => false
  }
}

///|
/// One batch of the decisions-by-session repair (`decisionSessionRepairStep`): its old table emptied in batches, then
/// its index and triggers made and the lookup copied as the other.
pub fn decision_session_repair_step(db : @sql.Db) -> Bool raise {
  if !repair_needs_work(db) {
    return true
  }
  if session_state(db, repair) == Some(2) {
    ignore(
      write(db, () => {
        if session_state(db, repair) == Some(2) {
          ignore(
            db.run("DELETE FROM \{repair} WHERE id IN (SELECT id FROM \{repair} ORDER BY id LIMIT ?)", [
              Json::number(batch.to_double()),
            ]),
          )
          if first(db, "SELECT 1 FROM \{repair} LIMIT 1", []) is None {
            db.exec(repair_ddl)
            db.exec(
              "UPDATE \{repair}_meta SET complete=0,cursor=NULL,end_id=(SELECT MAX(id) FROM decision_checks) WHERE id=1",
            )
          }
        }
        0
      }),
    )
    return false
  }
  copy_ids(
    db,
    "\{repair}_meta",
    "decision_checks",
    session_put(repair),
    "unsupported legacy decision-session preparation",
    batch,
    () => has_session_lookup(db, repair),
  )
}

// The agent-message time lookup (legacy-agent-build.ts).

///|
pub fn has_legacy_agent(db : @sql.Db) -> Bool raise {
  if !exists(db, "table", "legacy_agent_meta") {
    return false
  }
  guard first(db, "SELECT version,scanned FROM legacy_agent_meta WHERE id=1", []) is Some(m) &&
    int(m, "version") == version &&
    (int(m, "scanned") == 0 || int(m, "scanned") == 1) else {
    raise Failure("legacy agent lookup has an unsupported version")
  }
  true
}

///|
let agent_incompatible : (Json) -> String = v => "legacy agent version \{v.stringify()} is incompatible with \{version}"

///|
/// The keys older writers changed folded back, at most a batch of work (`legacyAgentDrain`): a key's other times
/// removed first, then the key itself.
fn agent_drain(db : @sql.Db) -> Int raise {
  write(db, () => {
    let m = meta(db, "legacy_agent_meta")
    if int(m, "version") != version {
      raise Failure(agent_incompatible(get(m, "version")))
    }
    // (before the scan has passed a key, folding it could make the scanner stage an older time for it)
    if int(m, "scanned") != 1 {
      return 0
    }
    let mut visited = 0
    while visited < batch {
      guard first(
          db,
          "SELECT CAST(d.thread AS TEXT) thread,CAST(d.n AS TEXT) n,CAST(d.old_at AS TEXT) old_at FROM legacy_agent_dirty d ORDER BY d.thread,d.n LIMIT 1",
          [],
        )
        is Some(key) else {
        break
      }
      let k = [get(key, "thread"), get(key, "n")]
      let now = match
        first(
          db,
          "SELECT CAST(at AS TEXT) at FROM entries WHERE thread=CAST(? AS INTEGER) AND n=CAST(? AS INTEGER) AND kind='message' AND author_kind='agent'",
          k,
        ) {
        Some(r) => get(r, "at")
        None => Json::null()
      }
      visited += db.run(
        "DELETE FROM legacy_agent_times WHERE thread=CAST(?1 AS INTEGER) AND n=CAST(?2 AS INTEGER) AND at IN (SELECT at FROM legacy_agent_times INDEXED BY legacy_agent_times_by_key WHERE thread=CAST(?1 AS INTEGER) AND n=CAST(?2 AS INTEGER) AND (?3 IS NULL OR at != CAST(?3 AS INTEGER)) ORDER BY legacy_agent_times.at LIMIT ?4)",
        k + [now, Json::number((batch - visited).to_double())],
      )
      if visited == batch {
        break
      }
      if !(get(key, "old_at") is Null) {
        ignore(
          db.run(
            "DELETE FROM legacy_agent_build WHERE thread=CAST(? AS INTEGER) AND at=CAST(? AS INTEGER) AND n=CAST(? AS INTEGER)",
            [k[0], get(key, "old_at"), k[1]],
          ),
        )
      }
      ignore(
        db.run(
          "INSERT INTO legacy_agent_build(thread,at,n) SELECT thread,at,n FROM entries WHERE thread=CAST(? AS INTEGER) AND n=CAST(? AS INTEGER) AND kind='message' AND author_kind='agent' ON CONFLICT(thread,at,n) DO NOTHING",
          k,
        ),
      )
      if !(now is Null) {
        ignore(
          db.run(
            "DELETE FROM legacy_agent_times WHERE thread=CAST(? AS INTEGER) AND at=CAST(? AS INTEGER) AND n=CAST(? AS INTEGER)",
            [k[0], now, k[1]],
          ),
        )
      }
      ignore(db.run("DELETE FROM legacy_agent_dirty WHERE thread=CAST(? AS INTEGER) AND n=CAST(? AS INTEGER)", k))
      visited += 1
    }
    visited
  })
}

///|
/// One batch of the agent lookup's upkeep (`legacyAgentMaintenanceStep`); whether nothing is left then.
pub fn agent_maintenance(db : @sql.Db) -> Bool raise {
  if !has_legacy_agent(db) {
    return true
  }
  if int(meta(db, "legacy_agent_meta"), "scanned") != 1 {
    ignore(
      scan_step(
        db,
        "legacy_agent_meta",
        "INSERT INTO legacy_agent_build(thread,at,n) SELECT e.thread,CAST(CAST(e.at AS TEXT) AS INTEGER),e.n FROM entries e WHERE e.thread=CAST(?1 AS INTEGER) AND e.n=CAST(?2 AS INTEGER) AND e.kind='message' AND e.author_kind='agent' AND NOT EXISTS (SELECT 1 FROM legacy_agent_dirty WHERE thread=e.thread AND n=e.n) ON CONFLICT(thread,at,n) DO NOTHING",
        agent_incompatible,
      ),
    )
    return false
  }
  agent_drain(db) < batch
}

// The login-card lookup (legacy-login-cards.ts).

///|
fn has_login_cards(db : @sql.Db) -> Bool raise {
  if !exists(db, "table", "login_card_meta") {
    return false
  }
  guard first(db, "SELECT version,scanned FROM login_card_meta WHERE id=1", []) is Some(m) &&
    int(m, "version") == version &&
    (int(m, "scanned") == 0 || int(m, "scanned") == 1) else {
    raise Failure("legacy login-card lookup has an unsupported version")
  }
  true
}

///|
/// A card's text as SQLite's LIKE sees it: ASCII folded, and cut at a NUL (LIKE stops there).
fn like_text(card : String) -> String {
  let out = StringBuilder::new()
  for c in card {
    if c == '\u{0}' {
      break
    }
    out.write_char(if c >= 'A' && c <= 'Z' { (c.to_int() + 32).unsafe_to_char() } else { c })
  }
  out.to_string()
}

///|
fn find_from(text : String, what : String, from : Int) -> Int? {
  if from > text.length() {
    return None
  }
  match text.view(start_offset=from).find(what) {
    Some(i) => Some(from + i)
    None => None
  }
}

///|
fn login_ok(login : String) -> Bool {
  login.length() >= 1 &&
  login.length() <= 40 &&
  login.iter().all(c => (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z'))
}

///|
/// At most 64 entries and 64 login tokens of the old cards scanned into the lookup, the cursor (and the offset in a
/// card left partly scanned) with them (`legacyLoginCardsStep`); whether the scan is done.
fn login_cards_step(db : @sql.Db) -> Bool raise {
  write(db, () => {
    guard first(
        db,
        "SELECT version,scanned,CAST(end_thread AS TEXT) end_thread,CAST(end_n AS TEXT) end_n,CAST(cursor_thread AS TEXT) cursor_thread,CAST(cursor_n AS TEXT) cursor_n,offset FROM login_card_meta WHERE id=1",
        [],
      )
      is Some(m) &&
      int(m, "version") == version &&
      (int(m, "scanned") == 0 || int(m, "scanned") == 1) else {
      raise Failure("unsupported login card preparation")
    }
    if int(m, "scanned") == 1 {
      return 1
    }
    let fields = "CAST(thread AS TEXT) thread,CAST(n AS TEXT) n,CAST(rowid AS TEXT) entry_rowid,ts,kind,author_kind,CASE WHEN card LIKE '%\"login\"%' THEN CAST(card AS TEXT) END AS card"
    let from = if exists(db, "index", "entries_login_cards") {
      "FROM entries INDEXED BY entries_login_cards WHERE card LIKE '%\"login\"%'"
    } else {
      "FROM entries WHERE 1"
    }
    let end_thread = get(m, "end_thread")
    let end_n = get(m, "end_n")
    let mut cursor_thread = get(m, "cursor_thread")
    let mut cursor_n = get(m, "cursor_n")
    let mut offset : Int? = match get(m, "offset") {
      Number(o, ..) => Some(o.to_int())
      _ => None
    }
    let mut visited = 0
    let mut tokens = 0
    let mut ready = end_thread is Null
    while !ready && visited < batch && tokens < batch {
      let row = if offset is Some(_) {
        match
          first(db, "SELECT \{fields} FROM entries WHERE thread=CAST(?1 AS INTEGER) AND n=CAST(?2 AS INTEGER)", [
            cursor_thread, cursor_n,
          ]) {
          Some(r) => r
          None => {
            offset = None
            continue
          }
        }
      } else {
        let mut found = if cursor_thread is Null {
          first(
            db,
            "SELECT \{fields} \{from} AND thread<=CAST(?1 AS INTEGER) ORDER BY entries.thread,entries.n LIMIT 1",
            [end_thread],
          )
        } else {
          first(
            db,
            "SELECT \{fields} \{from} AND thread=CAST(?1 AS INTEGER) AND n>CAST(?2 AS INTEGER) ORDER BY entries.n LIMIT 1",
            [cursor_thread, cursor_n],
          )
        }
        if found is None && !(cursor_thread is Null) {
          found = first(
            db,
            "SELECT \{fields} \{from} AND thread>CAST(?1 AS INTEGER) AND thread<=CAST(?2 AS INTEGER) ORDER BY entries.thread,entries.n LIMIT 1",
            [cursor_thread, end_thread],
          )
        }
        guard found is Some(r) &&
          int(
            first(
              db,
              "SELECT CAST(?1 AS INTEGER)>CAST(?2 AS INTEGER) OR (CAST(?1 AS INTEGER)=CAST(?2 AS INTEGER) AND CAST(?3 AS INTEGER)>CAST(?4 AS INTEGER)) AS beyond",
              [get(r, "thread"), end_thread, get(r, "n"), end_n],
            ).unwrap_or(Map([])),
            "beyond",
          ) ==
          0 else {
          ready = true
          break
        }
        cursor_thread = get(r, "thread")
        cursor_n = get(r, "n")
        offset = Some(0)
        r
      }
      visited += 1
      guard get(row, "kind") == Json::string("message") &&
        get(row, "author_kind") == Json::string("agent") &&
        get(row, "card") is String(card) else {
        offset = None
        continue
      }
      let text = like_text(card)
      let prefix = "\"login\":\""
      let mut at = offset.unwrap_or(0)
      while tokens < batch {
        guard find_from(text, prefix, at) is Some(start) else {
          offset = None
          break
        }
        at = start + prefix.length()
        let login = match find_from(text, "\"", at) {
          Some(end) => text.view(start_offset=at, end_offset=end).to_string()
          None => ""
        }
        if login_ok(login) {
          ignore(
            db.run(
              "INSERT INTO login_card_keys(login,thread,n,entry_rowid,ts) SELECT ?1,CAST(?2 AS INTEGER),CAST(?3 AS INTEGER),CAST(?4 AS INTEGER),?5 WHERE NOT EXISTS (SELECT 1 FROM login_card_keys WHERE login=?1 AND thread=CAST(?2 AS INTEGER) AND n=CAST(?3 AS INTEGER))",
              [Json::string(login), get(row, "thread"), get(row, "n"), get(row, "entry_rowid"), get(row, "ts")],
            ),
          )
        }
        tokens += 1
        offset = Some(at)
      }
    }
    ignore(
      db.run(
        "UPDATE login_card_meta SET scanned=?,cursor_thread=CAST(? AS INTEGER),cursor_n=CAST(? AS INTEGER),offset=? WHERE id=1",
        [
          Json::number(if ready { 1.0 } else { 0.0 }),
          cursor_thread,
          cursor_n,
          match offset {
            Some(o) => Json::number(o.to_double())
            None => Json::null()
          },
        ],
      ),
    )
    if ready { 1 } else { 0 }
  }) ==
  1
}

///|
/// One batch of the login-card lookup's scan (`legacyLoginCardsMaintenanceStep`); whether it is done.
pub fn login_cards_maintenance(db : @sql.Db) -> Bool raise {
  if !has_login_cards(db) {
    return true
  }
  login_cards_step(db)
}

///|
/// legacy-edits-build.ts `legacyMergedReadReady`: a single merged message can be read now.
pub fn merged_read_ready(db : @sql.Db) -> Bool raise {
  edits_ready(db)
}

///|
/// legacy-edits-build.ts `legacyMergedNeedsRepair`: the merged view's index is gone; it must be switched first.
pub fn merged_needs_repair(db : @sql.Db) -> Bool raise {
  let view = sql_of(db, "view", "merged").unwrap_or("")
  if view.contains("legacy_edit_meta") {
    view.contains("INDEXED BY entries_target") && !has_old_edit_index(db)
  } else {
    !exists(db, "index", "entries_edits")
  }
}

///|
/// legacy-edits-read.ts `boundedEditKey`: a message's latest edit (as text), None when there is none; raises
/// `Unprepared` when old edits need preparing first.
pub fn bounded_edit_key(db : @sql.Db, thread : Json, n : Json) -> String? raise {
  let read = (sql : String) => first(db, sql, [thread, n])
  let mut edit = read(
    "WITH tail AS MATERIALIZED (\n    SELECT n,target FROM entries WHERE thread=?1 ORDER BY n DESC LIMIT 65\n  ) SELECT (SELECT CAST(n AS TEXT) FROM tail WHERE target=CAST(?2 AS INTEGER) ORDER BY n DESC LIMIT 1) AS n,\n    (SELECT COUNT(*) FROM tail) AS count",
  )
  let count = (e : Map[String, Json]?) => match e {
    Some(r) => int(r, "count")
    None => 0
  }
  let key = (e : Map[String, Json]?) => match e {
    Some(r) => match get(r, "n") { String(s) => Some(s); _ => None }
    None => None
  }
  if key(edit) is None && count(edit) == 65 {
    let meta = if has_legacy_edits(db) {
      first(db, "SELECT scanned,old_index FROM legacy_edit_meta WHERE id=1", [])
    } else {
      None
    }
    if meta is Some(m) && int(m, "scanned") == 0 && int(m, "old_index") == 1 && has_old_edit_index(db) {
      edit = read(
        "WITH edits AS MATERIALIZED (\n    SELECT x.n FROM entries x INDEXED BY entries_target WHERE x.thread=?1 AND x.target=CAST(?2 AS INTEGER)\n      ORDER BY x.rowid DESC LIMIT 65\n  ) SELECT CAST(MAX(n) AS TEXT) AS n,COUNT(*) AS count FROM edits",
      )
    }
    if count(edit) == 65 {
      raise Unprepared("legacy edits pending")
    }
  }
  key(edit)
}

///|
/// Old edits to be prepared before a message can be read merged (read/store.ts LegacyEditsUnavailable).
pub(all) suberror Unprepared {
  Unprepared(String)
}
