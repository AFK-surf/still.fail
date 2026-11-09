// The active jobs' two lookups an older store lacks (station/src/store/active-jobs-upgrade.ts): built beside the
// running queue in bounded batches and published by renaming them once complete, then (a store whose other-jobs table
// predates its remote index) the remote keys copied into a table of their own, as `installActiveJobUpgrade` and
// `activeJobUpgradeStep` do, here for the MoonBit builder.

///|
fn exists(db : @sql.Db, kind : String, name : String) -> Bool raise {
  first(db, "SELECT 1 FROM sqlite_master WHERE type = ? AND name = ?", [Json::string(kind), Json::string(name)]) is Some(_)
}

///|
fn conflict(other : Bool) -> String {
  let not_old = if other { "AND j.rowid IS NOT OLD.rowid" } else { "" }
  "SELECT j.session_key AS session, j.id AS job FROM ( SELECT rowid AS position FROM jobs WHERE id = NEW.id UNION SELECT rowid FROM jobs WHERE token = NEW.token UNION SELECT rowid FROM jobs WHERE rowid = NEW.rowid ) p CROSS JOIN jobs j ON j.rowid = p.position WHERE j.state = 'running' AND j.id IS NOT NULL \{not_old}"
}

///|
let active_changed : String = "OLD.rowid IS NOT NEW.rowid OR OLD.id IS NOT NEW.id OR OLD.token IS NOT NEW.token OR OLD.session_key IS NOT NEW.session_key OR OLD.state IS NOT NEW.state OR OLD.watch IS NOT NEW.watch OR EXISTS (SELECT 1 FROM active_job_upgrade_replaced)"

///|
fn active_stage(other : Bool) -> String {
  "DELETE FROM active_job_upgrade_replaced WHERE session IS NOT NULL; INSERT INTO active_job_upgrade_replaced (session, job) \{conflict(other)};"
}

///|
/// The statements that put a job (its rowid `rowid`) in the lookups being built, each on its own.
fn active_see(watches : Bool, others : Bool, rowid : String) -> Array[String] {
  let out = []
  if watches {
    out.push(
      "INSERT INTO active_job_watch_build (job, session, token) SELECT j.id, j.session_key, j.token FROM jobs j WHERE j.rowid = \{rowid} AND j.state = 'running' AND j.watch <> 0 AND (j.id IS NOT NULL OR (SELECT complete FROM active_job_upgrade WHERE id = 1) = 1) AND NOT EXISTS (SELECT 1 FROM active_job_watch_build w WHERE w.job = j.id)",
    )
  }
  if others {
    out.push(
      "INSERT INTO active_job_other_build (session, job) SELECT j.session_key, j.id FROM jobs j WHERE j.rowid = \{rowid} AND j.state = 'running' AND j.watch = 0 AND (j.id IS NOT NULL OR (SELECT complete FROM active_job_upgrade WHERE id = 1) = 1) AND NOT EXISTS (SELECT 1 FROM active_job_other_build a WHERE a.session = j.session_key AND a.job = j.id)",
    )
  }
  out
}

///|
fn active_reconcile(watches : Bool, others : Bool) -> String {
  let w = if watches {
    "DELETE FROM active_job_watch_build WHERE job IN (SELECT job FROM active_job_upgrade_replaced) AND NOT EXISTS (SELECT 1 FROM jobs j WHERE j.id = active_job_watch_build.job AND j.state = 'running' AND j.watch <> 0 AND j.session_key = active_job_watch_build.session AND j.token = active_job_watch_build.token); INSERT INTO active_job_watch_build (job, session, token) SELECT j.id, j.session_key, j.token FROM active_job_upgrade_replaced r CROSS JOIN jobs j ON j.id = r.job WHERE j.state = 'running' AND j.watch <> 0 AND NOT EXISTS (SELECT 1 FROM active_job_watch_build w WHERE w.job = j.id);"
  } else {
    ""
  }
  let o = if others {
    "DELETE FROM active_job_other_build WHERE (session, job) IN (SELECT session, job FROM active_job_upgrade_replaced) AND NOT EXISTS (SELECT 1 FROM jobs j WHERE j.id = active_job_other_build.job AND j.state = 'running' AND j.watch = 0 AND j.session_key = active_job_other_build.session); INSERT INTO active_job_other_build (session, job) SELECT j.session_key, j.id FROM active_job_upgrade_replaced r CROSS JOIN jobs j ON j.id = r.job WHERE j.state = 'running' AND j.watch = 0 AND NOT EXISTS (SELECT 1 FROM active_job_other_build a WHERE a.session = j.session_key AND a.job = j.id);"
  } else {
    ""
  }
  "\{w} \{o} DELETE FROM active_job_upgrade_replaced WHERE session IS NOT NULL;"
}

///|
fn active_drop(watches : Bool, others : Bool) -> String {
  let w = if watches { "DELETE FROM active_job_watch_build WHERE job = OLD.id;" } else { "" }
  let o = if others { "DELETE FROM active_job_other_build WHERE session = OLD.session_key AND job = OLD.id;" } else { "" }
  "\{w} \{o}"
}

///|
/// The upgrade's tables and triggers for the lookups missing (`watches`, `others`).
pub fn active_schema(watches : Bool, others : Bool) -> String {
  let see = (rowid : String) => active_see(watches, others, rowid).map(s => s + ";").join(" ")
  let flag = (b : Bool) => if b { "1" } else { "0" }
  [
    "CREATE TABLE active_job_upgrade (id INTEGER PRIMARY KEY CHECK (id = 1), version INTEGER NOT NULL, complete INTEGER NOT NULL, watches INTEGER NOT NULL, others INTEGER NOT NULL, cursor INTEGER, end_rowid INTEGER, schema_version INTEGER) WITHOUT ROWID;",
    "INSERT INTO active_job_upgrade VALUES (1, \{version}, 0, \{flag(watches)}, \{flag(others)}, NULL, CAST((\{last_running}) AS INTEGER), NULL);",
    "CREATE TABLE active_job_upgrade_replaced (session TEXT NOT NULL, job TEXT NOT NULL, PRIMARY KEY (session, job)) WITHOUT ROWID;",
    if watches {
      "CREATE TABLE active_job_watch_build (job TEXT PRIMARY KEY, session TEXT NOT NULL, token TEXT NOT NULL UNIQUE) WITHOUT ROWID; CREATE INDEX active_watch_jobs_session ON active_job_watch_build (session);"
    } else {
      ""
    },
    if others {
      "CREATE TABLE active_job_other_build (session TEXT NOT NULL, job TEXT NOT NULL, PRIMARY KEY (session, job)) WITHOUT ROWID; CREATE INDEX active_other_remote_jobs ON active_job_other_build (job) WHERE job >= 'remote_' AND job < 'remote`';"
    } else {
      ""
    },
    "CREATE TRIGGER active_job_upgrade_before_add BEFORE INSERT ON jobs WHEN EXISTS (SELECT 1 FROM active_job_upgrade_replaced) OR EXISTS (\{conflict(false)}) BEGIN \{active_stage(false)} END;",
    "CREATE TRIGGER active_job_upgrade_add AFTER INSERT ON jobs WHEN NEW.state = 'running' OR EXISTS (SELECT 1 FROM active_job_upgrade_replaced) BEGIN \{active_reconcile(watches, others)} \{see("NEW.rowid")} END;",
    "CREATE TRIGGER active_job_upgrade_before_change BEFORE UPDATE ON jobs WHEN EXISTS (SELECT 1 FROM active_job_upgrade_replaced) OR ((OLD.rowid IS NOT NEW.rowid OR OLD.id IS NOT NEW.id OR OLD.token IS NOT NEW.token) AND EXISTS (\{conflict(true)})) BEGIN \{active_stage(true)} END;",
    "CREATE TRIGGER active_job_upgrade_change AFTER UPDATE ON jobs WHEN \{active_changed} BEGIN \{active_drop(watches, others)} \{active_reconcile(watches, others)} \{see("NEW.rowid")} END;",
    "CREATE TRIGGER active_job_upgrade_drop AFTER DELETE ON jobs WHEN OLD.state = 'running' BEGIN \{active_drop(watches, others)} END;",
  ].join("\n")
}

///|
fn upgrade_meta(db : @sql.Db) -> Map[String, Json]? raise {
  if !exists(db, "table", "active_job_upgrade") {
    return None
  }
  let row = first(
    db,
    "SELECT version, complete, watches, others, CAST(cursor AS TEXT) AS cursor, CAST(end_rowid AS TEXT) AS end_rowid, schema_version FROM active_job_upgrade WHERE id = 1",
    [],
  )
  let v = match row {
    Some(r) => get(r, "version")
    None => Json::null()
  }
  guard v is Number(n, ..) && n.to_int() == version && row is Some(r) else {
    let said = if v is Null { "missing" } else { v.stringify() }
    raise Failure("active job upgrade version \{said} is incompatible with \{version}")
  }
  Some(r)
}

///|
fn remote_ready(db : @sql.Db) -> Bool raise {
  exists(db, "table", "active_remote_job_meta") &&
  (
    match first(db, "SELECT version, complete FROM active_remote_job_meta WHERE id = 1", []) {
      Some(r) => get(r, "version") is Number(1.0, ..) && get(r, "complete") is Number(1.0, ..)
      None => false
    }
  )
}

///|
/// Both lookups published, and the remote keys there (`activeJobUpgradeReady`).
fn upgrade_ready(db : @sql.Db) -> Bool raise {
  exists(db, "table", "active_watch_jobs") &&
  exists(db, "table", "active_other_jobs") &&
  (exists(db, "index", "active_other_remote_jobs") || remote_ready(db))
}

///|
/// The upgrade made when a lookup is missing (`installActiveJobUpgrade`).
fn install_upgrade(db : @sql.Db) -> Unit raise {
  if upgrade_meta(db) is Some(_) || (exists(db, "table", "active_watch_jobs") && exists(db, "table", "active_other_jobs")) {
    return
  }
  db.exec("BEGIN IMMEDIATE")
  errdefer (db.exec("ROLLBACK") catch { _ => () })
  if upgrade_meta(db) is None {
    let watches = !exists(db, "table", "active_watch_jobs")
    let others = !exists(db, "table", "active_other_jobs")
    if watches || others {
      db.exec(active_schema(watches, others))
      ignore(db.run("UPDATE active_job_upgrade SET schema_version = ? WHERE id = 1", [schema_version(db)]))
    }
  }
  db.exec("COMMIT")
}

///|
let remote_schema : String = [
  "CREATE TABLE active_remote_job_meta (id INTEGER PRIMARY KEY CHECK (id = 1), version INTEGER NOT NULL, complete INTEGER NOT NULL, cursor_session TEXT, cursor_job TEXT, end_session TEXT, end_job TEXT) WITHOUT ROWID;",
  "INSERT INTO active_remote_job_meta SELECT 1, \{version}, 0, NULL, NULL, (SELECT session FROM active_other_jobs ORDER BY session DESC, job DESC LIMIT 1), (SELECT job FROM active_other_jobs ORDER BY session DESC, job DESC LIMIT 1);",
  "CREATE TABLE active_remote_job_rows (job TEXT NOT NULL, session TEXT NOT NULL, PRIMARY KEY (job, session)) WITHOUT ROWID;",
  "CREATE TRIGGER active_remote_job_add AFTER INSERT ON active_other_jobs WHEN NEW.job >= 'remote_' AND NEW.job < 'remote`' BEGIN INSERT OR IGNORE INTO active_remote_job_rows VALUES (NEW.job, NEW.session); END;",
  "CREATE TRIGGER active_remote_job_drop AFTER DELETE ON active_other_jobs WHEN OLD.job >= 'remote_' AND OLD.job < 'remote`' BEGIN DELETE FROM active_remote_job_rows WHERE job = OLD.job AND session = OLD.session; END;",
  "CREATE TRIGGER active_remote_job_change AFTER UPDATE ON active_other_jobs BEGIN DELETE FROM active_remote_job_rows WHERE job = OLD.job AND session = OLD.session; INSERT OR IGNORE INTO active_remote_job_rows SELECT NEW.job, NEW.session WHERE NEW.job >= 'remote_' AND NEW.job < 'remote`'; END;",
].join("\n")

///|
/// The remote keys' table, for a store whose other-jobs table predates its remote index (`installActiveRemoteJobs`).
fn install_remote(db : @sql.Db) -> Unit raise {
  let needless = () => exists(db, "index", "active_other_remote_jobs") ||
    exists(db, "table", "active_remote_job_meta") ||
    !exists(db, "table", "active_other_jobs")
  if needless() {
    return
  }
  db.exec("BEGIN IMMEDIATE")
  errdefer (db.exec("ROLLBACK") catch { _ => () })
  if !exists(db, "index", "active_other_remote_jobs") && !exists(db, "table", "active_remote_job_meta") {
    db.exec(remote_schema)
  }
  db.exec("COMMIT")
}

///|
/// One batch of the remote keys (`activeRemoteJobsStep`).
fn remote_step(db : @sql.Db, limit : Int) -> Bool raise {
  if exists(db, "index", "active_other_remote_jobs") {
    return upgrade_ready(db)
  }
  install_remote(db)
  if !exists(db, "table", "active_remote_job_meta") {
    return false
  }
  db.exec("BEGIN IMMEDIATE")
  errdefer (db.exec("ROLLBACK") catch { _ => () })
  guard first(db, "SELECT * FROM active_remote_job_meta WHERE id = 1", []) is Some(row) else {
    raise Failure("active remote job metadata is missing")
  }
  guard get(row, "version") is Number(1.0, ..) else {
    raise Failure("active remote job version \{get(row, "version").stringify()} is incompatible with \{version}")
  }
  if get(row, "complete") is Number(1.0, ..) {
    db.exec("COMMIT")
    return upgrade_ready(db)
  }
  let lim = Json::number(limit.to_double())
  let rows = if get(row, "end_session") is Null {
    []
  } else if get(row, "cursor_session") is Null {
    db.all(
      "SELECT session, job FROM active_other_jobs WHERE (session, job) <= (?, ?) ORDER BY session, job LIMIT ?",
      [get(row, "end_session"), get(row, "end_job"), lim],
    )
  } else {
    db.all(
      "SELECT session, job FROM active_other_jobs WHERE (session, job) > (?, ?) AND (session, job) <= (?, ?) ORDER BY session, job LIMIT ?",
      [get(row, "cursor_session"), get(row, "cursor_job"), get(row, "end_session"), get(row, "end_job"), lim],
    )
  }
  for r in rows {
    ignore(
      db.run(
        "INSERT OR IGNORE INTO active_remote_job_rows SELECT job, session FROM active_other_jobs WHERE session = ? AND job = ? AND job >= 'remote_' AND job < 'remote`'",
        [get(r, "session"), get(r, "job")],
      ),
    )
  }
  let done = rows.length() < limit
  let (session, job) = match rows.last() {
    Some(r) => (get(r, "session"), get(r, "job"))
    None => (get(row, "cursor_session"), get(row, "cursor_job"))
  }
  ignore(
    db.run("UPDATE active_remote_job_meta SET cursor_session = ?, cursor_job = ?, complete = ? WHERE id = 1", [
      session,
      job,
      Json::number(if done { 1.0 } else { 0.0 }),
    ]),
  )
  db.exec("COMMIT")
  done && upgrade_ready(db)
}

///|
/// One batch of the active-jobs upgrade (`activeJobUpgradeStep`): at most `limit` running jobs put in the lookups
/// being built, the walk started over when the schema changed, the lookups published by renaming once complete (not
/// while a running job has no id); then the remote keys. Whether all is ready then.
pub fn active_step(db : @sql.Db, limit? : Int = 64) -> Bool raise {
  guard limit >= 1 else { raise Failure("active job batch must be positive") }
  install_upgrade(db)
  match upgrade_meta(db) {
    None => return remote_step(db, limit)
    Some(m) if get(m, "complete") is Number(1.0, ..) => return remote_step(db, limit)
    _ => ()
  }
  db.exec("BEGIN IMMEDIATE")
  errdefer (db.exec("ROLLBACK") catch { _ => () })
  guard upgrade_meta(db) is Some(current) else { raise Failure("active job upgrade is missing") }
  if get(current, "complete") is Number(1.0, ..) {
    db.exec("COMMIT")
    return upgrade_ready(db)
  }
  let schema = schema_version(db)
  let (cursor, end) = if schema != get(current, "schema_version") {
    (
      Json::null(),
      match first(db, last_running, []) {
        Some(r) => get(r, "position")
        None => Json::null()
      },
    )
  } else {
    (get(current, "cursor"), get(current, "end_rowid"))
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
  let watches = get(current, "watches") is Number(1.0, ..)
  let others = get(current, "others") is Number(1.0, ..)
  let puts = active_see(watches, others, "CAST(? AS INTEGER)")
  for row in rows {
    for put in puts {
      ignore(db.run(put, [get(row, "position")]))
    }
  }
  let finished = rows.length() < limit
  if finished {
    // (a running job without an id, from a writer before the index, cannot be in either lookup: wait until it is gone)
    if first(db, "SELECT 1 FROM jobs INDEXED BY sqlite_autoindex_jobs_1 WHERE id IS NULL AND state = 'running' LIMIT 1", [])
      is Some(_) {
      raise Failure("a running job without an id cannot yet be indexed")
    }
    if watches {
      db.exec("ALTER TABLE active_job_watch_build RENAME TO active_watch_jobs")
    }
    if others {
      db.exec("ALTER TABLE active_job_other_build RENAME TO active_other_jobs")
    }
  }
  let reached = match rows.last() {
    Some(r) => get(r, "position")
    None => cursor
  }
  ignore(
    db.run(
      "UPDATE active_job_upgrade SET cursor = CAST(? AS INTEGER), end_rowid = CAST(? AS INTEGER), complete = ?, schema_version = ? WHERE id = 1",
      [reached, end, Json::number(if finished { 1.0 } else { 0.0 }), schema],
    ),
  )
  db.exec("COMMIT")
  finished && upgrade_ready(db)
}
