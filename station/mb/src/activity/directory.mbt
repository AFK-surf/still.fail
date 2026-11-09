// The reverse lookup of the directories sessions use (station/src/store/session-directory.ts): made when a shared
// runtime first needs it, then an older store's sessions and the sessions writers changed since put in, in bounded
// batches, as `installSessionDirectories` and `sessionDirectoriesStep` do.

///|
let directory_version : Int = 1

///|
fn dirty(key : String) -> String {
  "INSERT INTO session_dir_dirty (session) SELECT \{key} WHERE \{key} IS NOT NULL AND NOT EXISTS (SELECT 1 FROM session_dir_dirty d WHERE d.session = \{key});"
}

///|
let dir_conflicts : String = "INSERT INTO session_dir_dirty (session) SELECT s.key FROM sessions s WHERE (s.token = NEW.token OR s.rowid = NEW.rowid) AND s.key IS NOT NEW.key AND NOT EXISTS (SELECT 1 FROM session_dir_dirty d WHERE d.session = s.key);"

///|
pub fn directory_schema() -> String {
  [
    "CREATE TABLE session_dir_meta (id INTEGER PRIMARY KEY CHECK (id = 1), version INTEGER NOT NULL, phase INTEGER NOT NULL, cursor TEXT, end_session TEXT) WITHOUT ROWID;",
    "INSERT INTO session_dir_meta VALUES (1, \{directory_version}, 0, NULL, (SELECT key FROM sessions WHERE key IS NOT NULL ORDER BY key DESC LIMIT 1));",
    "CREATE TABLE session_dir_rows (session TEXT NOT NULL, root TEXT NOT NULL, PRIMARY KEY(session, root)) WITHOUT ROWID;",
    "CREATE INDEX session_dir_root ON session_dir_rows (root, session);",
    "CREATE TABLE session_dir_dirty (session TEXT PRIMARY KEY) WITHOUT ROWID;",
    "CREATE TRIGGER session_dir_before_add BEFORE INSERT ON sessions BEGIN \{dirty("NEW.key")} \{dir_conflicts} END;",
    "CREATE TRIGGER session_dir_before_change BEFORE UPDATE ON sessions WHEN OLD.rowid IS NOT NEW.rowid OR OLD.key IS NOT NEW.key OR OLD.token IS NOT NEW.token OR OLD.workspace IS NOT NEW.workspace OR OLD.cwd IS NOT NEW.cwd BEGIN \{dirty("OLD.key")} \{dirty("NEW.key")} \{dir_conflicts} END;",
    "CREATE TRIGGER session_dir_before_drop BEFORE DELETE ON sessions BEGIN \{dirty("OLD.key")} END;",
  ].join("\n")
}

///|
fn directory_check(db : @sql.Db) -> Unit raise {
  let v = match first(db, "SELECT version FROM session_dir_meta WHERE id = 1", []) {
    Some(m) => get(m, "version")
    None => Json::null()
  }
  guard v is Number(n, ..) && n.to_int() == directory_version else {
    let said = if v is Null { "missing" } else { v.stringify() }
    raise Failure("session directory index version \{said} is incompatible with \{directory_version}")
  }
}

///|
fn directory_installed(db : @sql.Db) -> Bool raise {
  first(db, "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'session_dir_meta'", []) is Some(_)
}

///|
/// The lookup made when it is missing (`installSessionDirectories`).
pub fn directory_install(db : @sql.Db) -> Unit raise {
  if directory_installed(db) {
    directory_check(db)
    return
  }
  db.exec("BEGIN IMMEDIATE")
  errdefer (db.exec("ROLLBACK") catch { _ => () })
  if !directory_installed(db) {
    db.exec(directory_schema())
  }
  db.exec("COMMIT")
}

///|
/// At most `limit` old or changed sessions' directories put in (`sessionDirectoriesStep`): the old sessions by key up
/// to the last when the lookup was made, then those writers changed. Whether nothing is left then.
pub fn directory_step(db : @sql.Db, limit? : Int = 64) -> Bool raise {
  guard limit >= 1 else { raise Failure("session directory batch must be positive") }
  db.exec("BEGIN IMMEDIATE")
  errdefer (db.exec("ROLLBACK") catch { _ => () })
  directory_check(db)
  guard first(db, "SELECT phase, cursor, end_session FROM session_dir_meta WHERE id = 1", []) is Some(meta) else {
    raise Failure("session directory index version missing is incompatible with \{directory_version}")
  }
  let end = get(meta, "end_session")
  let mut phase = match get(meta, "phase") {
    Number(p, ..) => p.to_int()
    _ => 0
  }
  let mut cursor = get(meta, "cursor")
  let mut visited = 0
  while visited < limit {
    let lim = Json::number((limit - visited).to_double())
    let rows = if phase == 0 {
      let found = if end is Null {
        []
      } else if cursor is Null {
        db.all("SELECT key AS session FROM sessions WHERE key <= ? ORDER BY key LIMIT ?", [end, lim])
      } else {
        db.all("SELECT key AS session FROM sessions WHERE key > ? AND key <= ? ORDER BY key LIMIT ?", [cursor, end, lim])
      }
      if found.length() == 0 {
        phase = 1
        cursor = Json::null()
        continue
      }
      found
    } else {
      let found = db.all("SELECT session FROM session_dir_dirty ORDER BY session LIMIT ?", [lim])
      if found.length() == 0 {
        break
      }
      found
    }
    for row in rows {
      let session = get(row, "session")
      ignore(db.run("DELETE FROM session_dir_rows WHERE session = ?", [session]))
      ignore(
        db.run(
          "INSERT INTO session_dir_rows (session, root) SELECT key, workspace FROM sessions WHERE key = ?1 AND workspace <> '' UNION SELECT key, cwd FROM sessions WHERE key = ?1 AND cwd IS NOT NULL AND cwd <> ''",
          [session],
        ),
      )
      ignore(db.run("DELETE FROM session_dir_dirty WHERE session = ?", [session]))
      if phase == 0 {
        cursor = session
      }
      visited += 1
    }
  }
  ignore(db.run("UPDATE session_dir_meta SET phase = ?, cursor = ? WHERE id = 1", [Json::number(phase.to_double()), cursor]))
  let done = phase == 1 && first(db, "SELECT 1 FROM session_dir_dirty LIMIT 1", []) is None
  db.exec("COMMIT")
  done
}
