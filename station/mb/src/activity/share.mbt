// The deadlines of chats shared with other workspaces (station/src/store/chat-share-index.ts): made when first needed,
// then each chat's saved shares parsed into its targets in bounded batches, as `installChatShareIndex` and
// `chatShareIndexStep` do. A share whose values JavaScript would not read exactly (too long, not plain, numbers past
// 2^53) is kept on the uncertain list, which keeps reads on the original rules.

///|
let share_version : Int = 1

///|
/// Six hours: a share unused that long lapses (rows.ts `XSHARE_IDLE_MS`).
let idle_ms : Double = 21600000.0

///|
let safe : Double = 9007199254740991.0

///|
fn share_dirty(key : String) -> String {
  "INSERT INTO chat_share_dirty (session) SELECT \{key} WHERE \{key} IS NOT NULL AND NOT EXISTS (SELECT 1 FROM chat_share_dirty d WHERE d.session = \{key});"
}

///|
let share_conflicts : String = "INSERT INTO chat_share_dirty (session) SELECT s.session FROM chat_shares s WHERE s.rowid = NEW.rowid AND s.session IS NOT NEW.session AND s.session IS NOT NULL AND NOT EXISTS (SELECT 1 FROM chat_share_dirty d WHERE d.session = s.session);"

///|
pub fn share_schema() -> String {
  [
    "CREATE TABLE chat_share_index_meta (id INTEGER PRIMARY KEY CHECK (id = 1), version INTEGER NOT NULL, phase INTEGER NOT NULL, cursor TEXT, end_session TEXT) WITHOUT ROWID;",
    "INSERT INTO chat_share_index_meta VALUES (1, \{share_version}, 0, NULL, (SELECT session FROM chat_shares WHERE session IS NOT NULL ORDER BY session DESC LIMIT 1));",
    "CREATE TABLE chat_share_targets (session TEXT NOT NULL, ordinal INTEGER NOT NULL, workspace TEXT NOT NULL, used INTEGER NOT NULL, PRIMARY KEY(session, ordinal)) WITHOUT ROWID;",
    "CREATE INDEX chat_share_target_time ON chat_share_targets (used, session);",
    "CREATE INDEX chat_share_target_workspace ON chat_share_targets (workspace, used, session);",
    "CREATE TABLE chat_share_uncertain (session TEXT PRIMARY KEY) WITHOUT ROWID;",
    "CREATE TABLE chat_share_dirty (session TEXT PRIMARY KEY) WITHOUT ROWID;",
    "CREATE TRIGGER chat_share_index_before_add BEFORE INSERT ON chat_shares BEGIN \{share_dirty("NEW.session")} \{share_conflicts} END;",
    "CREATE TRIGGER chat_share_index_before_change BEFORE UPDATE ON chat_shares WHEN OLD.rowid IS NOT NEW.rowid OR OLD.session IS NOT NEW.session OR OLD.shared IS NOT NEW.shared OR OLD.at IS NOT NEW.at BEGIN \{share_dirty("OLD.session")} \{share_dirty("NEW.session")} \{share_conflicts} END;",
    "CREATE TRIGGER chat_share_index_before_drop BEFORE DELETE ON chat_shares BEGIN \{share_dirty("OLD.session")} END;",
  ].join("\n")
}

///|
fn share_check(db : @sql.Db) -> Unit raise {
  let v = match first(db, "SELECT version FROM chat_share_index_meta WHERE id = 1", []) {
    Some(m) => get(m, "version")
    None => Json::null()
  }
  guard v is Number(n, ..) && n.to_int() == share_version else {
    let said = if v is Null { "missing" } else { v.stringify() }
    raise Failure("chat share index version \{said} is incompatible with \{share_version}")
  }
}

///|
fn share_installed(db : @sql.Db) -> Bool raise {
  first(db, "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'chat_share_index_meta'", []) is Some(_)
}

///|
/// The index made when it is missing (`installChatShareIndex`).
pub fn share_install(db : @sql.Db) -> Unit raise {
  if share_installed(db) {
    share_check(db)
    return
  }
  db.exec("BEGIN IMMEDIATE")
  errdefer (db.exec("ROLLBACK") catch { _ => () })
  if !share_installed(db) {
    db.exec(share_schema())
  } else {
    share_check(db)
  }
  db.exec("COMMIT")
}

///|
fn safe_int(x : Double) -> Bool {
  x == x.floor() && x.abs() <= safe
}

///|
/// A saved share's targets as JavaScript reads them (`toChatShare`, `shareValues`): each workspace named, with when it
/// was last used (else when it was shared); None where that reading is not exact.
fn share_values(row : Map[String, Json]) -> Array[(String, Double)]? {
  guard get(row, "shared_type") == Json::string("text") && get(row, "shared") is String(shared) else { return None }
  if shared.length() > 16384 {
    return None
  }
  let at = get(row, "at")
  let parsed : Json = @json.parse(shared) catch { _ => Json::array([]) }
  let to = match parsed {
    Array(items) => items
    _ => []
  }
  let values = []
  for t in to {
    guard t is Object(fields) && fields.get("workspace") is Some(String(workspace)) else { continue }
    let used = match fields.get("used") {
      Some(Number(u, ..)) => Json::number(u)
      _ => at
    }
    guard used is Number(u, ..) && safe_int(u) && safe_int(u + idle_ms) else { return None }
    values.push((workspace, u))
  }
  if values.length() > 16 {
    return None
  }
  Some(values)
}

///|
/// At most `limit` chats' shares parsed into their targets (`chatShareIndexStep`): the old chats by key up to the last
/// when the index was made, then those writers changed. Whether nothing is left then.
pub fn share_step(db : @sql.Db, limit? : Int = 64) -> Bool raise {
  guard limit >= 1 else { raise Failure("chat share batch must be positive") }
  db.exec("BEGIN IMMEDIATE")
  errdefer (db.exec("ROLLBACK") catch { _ => () })
  share_check(db)
  guard first(db, "SELECT phase, cursor, end_session FROM chat_share_index_meta WHERE id = 1", []) is Some(meta) else {
    raise Failure("chat share index version missing is incompatible with \{share_version}")
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
    let keys = if phase == 0 {
      if end is Null {
        []
      } else if cursor is Null {
        db.all("SELECT session FROM chat_shares WHERE session <= ? ORDER BY session LIMIT ?", [end, lim])
      } else {
        db.all("SELECT session FROM chat_shares WHERE session > ? AND session <= ? ORDER BY session LIMIT ?", [cursor, end, lim])
      }
    } else {
      db.all("SELECT session FROM chat_share_dirty ORDER BY session LIMIT ?", [lim])
    }
    if keys.length() == 0 {
      if phase == 0 {
        phase = 1
        cursor = Json::null()
        continue
      }
      break
    }
    for key in keys {
      let session = get(key, "session")
      ignore(db.run("DELETE FROM chat_share_targets WHERE session = ?", [session]))
      ignore(db.run("DELETE FROM chat_share_uncertain WHERE session = ?", [session]))
      // (`at` only as JavaScript reads it exactly: an integer past 2^53 makes the share uncertain)
      if first(
          db,
          "SELECT typeof(shared) AS shared_type, shared, CASE WHEN typeof(at) IN ('integer', 'real') AND at BETWEEN -9007199254740991 AND 9007199254740991 THEN at END AS at FROM chat_shares WHERE session = ?",
          [session],
        )
        is Some(row) {
        match share_values(row) {
          None => ignore(db.run("INSERT INTO chat_share_uncertain (session) VALUES (?)", [session]))
          Some(values) =>
            for i, target in values {
              ignore(
                db.run("INSERT INTO chat_share_targets (session, ordinal, workspace, used) VALUES (?, ?, ?, ?)", [
                  session,
                  Json::number(i.to_double()),
                  Json::string(target.0),
                  Json::number(target.1),
                ]),
              )
            }
        }
      }
      ignore(db.run("DELETE FROM chat_share_dirty WHERE session = ?", [session]))
      if phase == 0 {
        cursor = session
      }
      visited += 1
    }
  }
  ignore(db.run("UPDATE chat_share_index_meta SET phase = ?, cursor = ? WHERE id = 1", [Json::number(phase.to_double()), cursor]))
  let done = phase == 1 && first(db, "SELECT 1 FROM chat_share_dirty LIMIT 1", []) is None
  db.exec("COMMIT")
  done
}
