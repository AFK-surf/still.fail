// The running jobs with a process group (station/src/store/process-jobs.ts): the lookup made when it is missing, with
// the triggers that keep it for every writer, and an older store's running jobs brought forward in bounded batches,
// as `installProcessJobs` and `processJobsStep` do, here for the MoonBit builder.

///|
let version : Int = 1

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
fn active(row : String) -> String {
  "(\{row}.state = 'running' AND \{row}.pgid IS NOT NULL)"
}

///|
let conflicts : String = "SELECT j.id FROM ( SELECT rowid AS position FROM jobs WHERE id = NEW.id UNION SELECT rowid FROM jobs WHERE token = NEW.token UNION SELECT rowid FROM jobs WHERE rowid = NEW.rowid ) p CROSS JOIN jobs j ON j.rowid = p.position WHERE \{active("j")} AND j.id IS NOT NULL"

///|
fn stage(old : Bool) -> String {
  let also = if old { "UNION SELECT OLD.id WHERE OLD.id IS NOT NULL AND \{active("OLD")}" } else { "" }
  "DELETE FROM process_job_replaced WHERE job IS NOT NULL; INSERT INTO process_job_replaced (job) \{conflicts} \{also};"
}

///|
fn see(rowid : String) -> String {
  "INSERT INTO process_job_rows (job) SELECT j.id FROM jobs j WHERE j.rowid = \{rowid} AND j.id IS NOT NULL AND \{active("j")} AND NOT EXISTS (SELECT 1 FROM process_job_rows p WHERE p.job = j.id);"
}

///|
let reconcile : String = "DELETE FROM process_job_rows WHERE job IN (SELECT job FROM process_job_replaced) AND NOT EXISTS (SELECT 1 FROM jobs j WHERE j.id = process_job_rows.job AND \{active("j")}); INSERT INTO process_job_rows (job) SELECT j.id FROM process_job_replaced p CROSS JOIN jobs j ON j.id = p.job WHERE \{active("j")} AND NOT EXISTS (SELECT 1 FROM process_job_rows r WHERE r.job = j.id); DELETE FROM process_job_replaced WHERE job IS NOT NULL;"

///|
let changed : String = "OLD.rowid IS NOT NEW.rowid OR OLD.id IS NOT NEW.id OR OLD.token IS NOT NEW.token OR \{active("OLD")} IS NOT \{active("NEW")} OR EXISTS (SELECT 1 FROM process_job_replaced)"

///|
let last_running : String = "SELECT CAST(rowid AS TEXT) AS position FROM jobs INDEXED BY jobs_state WHERE state = 'running' ORDER BY rowid DESC LIMIT 1"

///|
pub fn schema() -> String {
  [
    "CREATE TABLE process_job_meta (id INTEGER PRIMARY KEY CHECK (id = 1), version INTEGER NOT NULL, complete INTEGER NOT NULL, cursor INTEGER, end_rowid INTEGER, schema_version INTEGER) WITHOUT ROWID;",
    "INSERT INTO process_job_meta (id, version, complete, cursor, end_rowid) VALUES (1, \{version}, 0, NULL, CAST((\{last_running}) AS INTEGER));",
    "CREATE TABLE process_job_rows (job TEXT PRIMARY KEY) WITHOUT ROWID;",
    "CREATE TABLE process_job_replaced (job TEXT PRIMARY KEY) WITHOUT ROWID;",
    "CREATE TRIGGER process_job_before_add BEFORE INSERT ON jobs WHEN EXISTS (SELECT 1 FROM process_job_replaced) OR EXISTS (\{conflicts}) BEGIN \{stage(false)} END;",
    "CREATE TRIGGER process_job_add AFTER INSERT ON jobs WHEN \{active("NEW")} OR EXISTS (SELECT 1 FROM process_job_replaced) BEGIN \{reconcile} \{see("NEW.rowid")} END;",
    "CREATE TRIGGER process_job_before_change BEFORE UPDATE ON jobs WHEN \{changed} BEGIN \{stage(true)} END;",
    "CREATE TRIGGER process_job_change AFTER UPDATE ON jobs WHEN \{changed} BEGIN \{reconcile} \{see("NEW.rowid")} END;",
    "CREATE TRIGGER process_job_drop AFTER DELETE ON jobs WHEN \{active("OLD")} BEGIN DELETE FROM process_job_rows WHERE job = OLD.id; END;",
  ].join("\n")
}

///|
fn installed(db : @sql.Db) -> Bool raise {
  first(db, "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'process_job_meta'", []) is Some(_)
}

///|
fn check(db : @sql.Db) -> Unit raise {
  let v = match first(db, "SELECT version, complete FROM process_job_meta WHERE id = 1", []) {
    Some(m) => get(m, "version")
    None => Json::null()
  }
  guard v is Number(n, ..) && n.to_int() == version else {
    let said = if v is Null { "missing" } else { v.stringify() }
    raise Failure("process job index version \{said} is incompatible with \{version}")
  }
}

///|
fn schema_version(db : @sql.Db) -> Json raise {
  match first(db, "PRAGMA schema_version", []) {
    Some(r) => get(r, "schema_version")
    None => Json::null()
  }
}

///|
/// The lookup made when it is missing (`installProcessJobs`).
pub fn install(db : @sql.Db) -> Unit raise {
  if installed(db) {
    check(db)
    return
  }
  db.exec("BEGIN IMMEDIATE")
  errdefer (db.exec("ROLLBACK") catch { _ => () })
  if !installed(db) {
    db.exec(schema())
    ignore(db.run("UPDATE process_job_meta SET schema_version = ? WHERE id = 1", [schema_version(db)]))
  } else {
    check(db)
  }
  db.exec("COMMIT")
}

///|
/// At most `limit` running jobs brought forward, with the cursor; a VACUUM between batches (the schema cookie changed)
/// starts the walk over (`processJobsStep`). Whether all are then.
pub fn step(db : @sql.Db, limit? : Int = 64) -> Bool raise {
  guard limit >= 1 else { raise Failure("process job batch must be positive") }
  db.exec("BEGIN IMMEDIATE")
  errdefer (db.exec("ROLLBACK") catch { _ => () })
  check(db)
  guard first(
      db,
      "SELECT complete, CAST(cursor AS TEXT) AS cursor, CAST(end_rowid AS TEXT) AS end_rowid, schema_version FROM process_job_meta WHERE id = 1",
      [],
    )
    is Some(meta)
  if get(meta, "complete") is Number(1.0, ..) {
    db.exec("COMMIT")
    return true
  }
  let schema = schema_version(db)
  let (cursor, end) = if schema != get(meta, "schema_version") {
    (
      Json::null(),
      match first(db, last_running, []) {
        Some(r) => get(r, "position")
        None => Json::null()
      },
    )
  } else {
    (get(meta, "cursor"), get(meta, "end_rowid"))
  }
  let lim = Json::number(limit.to_double())
  let rows = if end is Null {
    []
  } else if cursor is Null {
    db.all(
      "SELECT CAST(rowid AS TEXT) AS position FROM jobs INDEXED BY jobs_state WHERE state = 'running' AND rowid <= CAST(? AS INTEGER) ORDER BY rowid LIMIT ?",
      [end, lim],
    )
  } else {
    db.all(
      "SELECT CAST(rowid AS TEXT) AS position FROM jobs INDEXED BY jobs_state WHERE state = 'running' AND rowid > CAST(? AS INTEGER) AND rowid <= CAST(? AS INTEGER) ORDER BY rowid LIMIT ?",
      [cursor, end, lim],
    )
  }
  let put = see("CAST(? AS INTEGER)")
  for row in rows {
    ignore(db.run(put, [get(row, "position")]))
  }
  let done = rows.length() < limit
  let reached = match rows.last() {
    Some(r) => get(r, "position")
    None => cursor
  }
  ignore(
    db.run(
      "UPDATE process_job_meta SET cursor = CAST(? AS INTEGER), end_rowid = CAST(? AS INTEGER), complete = ?, schema_version = ? WHERE id = 1",
      [reached, end, Json::number(if done { 1.0 } else { 0.0 }), schema],
    ),
  )
  db.exec("COMMIT")
  done
}
