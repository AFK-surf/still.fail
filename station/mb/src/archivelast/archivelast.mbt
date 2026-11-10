// An old chat's latest message, found in small slices when its tail of edits is long (station/src/store/
// archive-last.ts): a per-chat guard that old writers invalidate, kept under an epoch, as `archiveLastStep` does, here
// for the MoonBit builder. The guard's tables and triggers made when they are missing or changed
// (`installArchiveLast`), each trigger marked `archive_last_v1`.

///|
let version : Int = 1

///|
let mark : String = "archive_last_v1"

///|
let names : Array[String] = [
  "archive_last_insert", "archive_last_update", "archive_last_delete", "archive_last_thread_delete",
]

///|
let same_victim : String = "(EXISTS (SELECT 1 FROM entries e WHERE e.thread=NEW.thread AND e.n=NEW.n AND e.kind='message') OR (NEW.ts IS NOT NULL AND EXISTS (SELECT 1 FROM entries e WHERE e.thread=NEW.thread AND e.ts=NEW.ts AND e.kind='message')))"

///|
let rowid_victim : String = "SELECT e.thread FROM entries e WHERE e.rowid=NEW.rowid AND e.kind='message'"

///|
/// The triggers, each with the mark (on a line of its own: a comment).
let triggers : String = [
  "CREATE TRIGGER archive_last_insert BEFORE INSERT ON entries WHEN EXISTS (SELECT 1 FROM archive_last_guard LIMIT 1) BEGIN\n-- \{mark}\nDELETE FROM archive_last_guard WHERE thread=NEW.thread AND (NEW.kind='message' OR \{same_victim}); DELETE FROM archive_last_guard WHERE thread=(\{rowid_victim}); END;",
  "CREATE TRIGGER archive_last_update BEFORE UPDATE OF thread,n,rowid,_rowid_,oid,kind,at,ts ON entries WHEN EXISTS (SELECT 1 FROM archive_last_guard LIMIT 1) AND (OLD.thread IS NOT NEW.thread OR OLD.n IS NOT NEW.n OR OLD.rowid IS NOT NEW.rowid OR OLD.kind IS NOT NEW.kind OR OLD.at IS NOT NEW.at OR OLD.ts IS NOT NEW.ts) BEGIN\n-- \{mark}\nDELETE FROM archive_last_guard WHERE thread=OLD.thread AND OLD.kind='message'; DELETE FROM archive_last_guard WHERE thread=NEW.thread AND (NEW.kind='message' OR \{same_victim}); DELETE FROM archive_last_guard WHERE thread=(\{rowid_victim} AND OLD.rowid IS NOT NEW.rowid); END;",
  "CREATE TRIGGER archive_last_delete BEFORE DELETE ON entries WHEN OLD.kind='message' BEGIN\n-- \{mark}\nDELETE FROM archive_last_guard WHERE thread=OLD.thread; END;",
  "CREATE TRIGGER archive_last_thread_delete AFTER DELETE ON threads BEGIN\n-- \{mark}\nDELETE FROM archive_last_guard WHERE thread=OLD.id; END;",
].join("\n")

///|
fn value(row : Map[String, Json], name : String) -> Json {
  row.get(name).unwrap_or(Json::null())
}

///|
fn first_row(db : @sql.Db, sql : String, params : Array[Json]) -> Map[String, Json]? raise {
  match db.all(sql, params) {
    [r, ..] => Some(r)
    _ => None
  }
}

///|
fn schema_version(db : @sql.Db) -> Json raise {
  match first_row(db, "PRAGMA schema_version", []) {
    Some(r) => value(r, "schema_version")
    None => Json::null()
  }
}

///|
fn sql_of(db : @sql.Db, kind : String, name : String) -> String? raise {
  match first_row(db, "SELECT sql FROM sqlite_master WHERE type=? AND name=?", [Json::string(kind), Json::string(name)]) {
    Some(r) =>
      match value(r, "sql") {
        String(s) => Some(s)
        _ => Some("")
      }
    None => None
  }
}

///|
/// The tables and marked triggers there, of this version.
fn current(db : @sql.Db) -> Bool raise {
  if sql_of(db, "table", "archive_last_meta") is None || sql_of(db, "table", "archive_last_guard") is None {
    return false
  }
  guard first_row(db, "SELECT version FROM archive_last_meta WHERE id=1", []) is Some(v) else { return false }
  guard value(v, "version") is Number(n, ..) && n.to_int() == version else {
    fail("archive last metadata has an unsupported version")
  }
  for name in names {
    guard sql_of(db, "trigger", name) is Some(sql) && sql.contains(mark) else { return false }
  }
  true
}

///|
/// The builder's state: the schema version its install was checked at.
pub struct Archive {
  priv db : @sql.Db
  priv mut checked : Json?
}

///|
pub fn Archive::new(db : @sql.Db) -> Archive {
  { db, checked: None }
}

///|
/// The tables and triggers made when they are not there (a new epoch: answers while a trigger was gone are not
/// trusted); false when they cannot be now.
fn Archive::install(self : Archive) -> Bool raise {
  let db = self.db
  let initial = schema_version(db)
  if self.checked == Some(initial) {
    return true
  }
  if current(db) {
    self.checked = Some(initial)
    return true
  }
  db.exec("BEGIN IMMEDIATE")
  errdefer (db.exec("ROLLBACK") catch { _ => () })
  if !current(db) {
    db.exec(
      "CREATE TABLE IF NOT EXISTS archive_last_meta(id INTEGER PRIMARY KEY CHECK(id=1),version INTEGER NOT NULL, epoch TEXT NOT NULL) WITHOUT ROWID; CREATE TABLE IF NOT EXISTS archive_last_guard(thread INTEGER PRIMARY KEY,epoch TEXT NOT NULL, before_n INTEGER,at INTEGER,ready INTEGER NOT NULL) WITHOUT ROWID;",
    )
    if first_row(db, "SELECT version FROM archive_last_meta WHERE id=1", []) is Some(v) &&
      !(value(v, "version") is Number(n, ..) && n.to_int() == version) {
      fail("archive last version \{value(v, "version").stringify()} is incompatible")
    }
    ignore(
      db.run(
        "INSERT INTO archive_last_meta VALUES(1,?,lower(hex(randomblob(16)))) ON CONFLICT(id) DO UPDATE SET epoch=excluded.epoch",
        [Json::number(version.to_double())],
      ),
    )
    for name in names {
      db.exec("DROP TRIGGER IF EXISTS \{name}")
    }
    db.exec(triggers)
  }
  db.exec("COMMIT")
  self.checked = Some(schema_version(db))
  true
}

///|
let slice_first : String = "SELECT CAST(e.n AS TEXT) AS n,CASE WHEN e.kind='message' THEN e.at END AS at FROM entries e WHERE e.thread=? ORDER BY e.n DESC LIMIT ?"

///|
let slice_before : String = "SELECT CAST(e.n AS TEXT) AS n,CASE WHEN e.kind='message' THEN e.at END AS at FROM entries e WHERE e.thread=?1 AND e.n<CAST(?2 AS INTEGER) ORDER BY e.n DESC LIMIT ?3"

///|
/// One slice of at most `limit` (64 at most) of `thread`'s entries from its newest back; whether its latest message
/// is known then. Progress is the chat's guard, shared with every opener.
pub fn Archive::step(self : Archive, thread : Int64, limit? : Int = 64) -> Bool raise {
  guard limit >= 1 && limit <= 64 else { fail("archive last batch must be 1–64") }
  let db = self.db
  if !self.install() {
    return false
  }
  let checked = self.checked
  let t = Json::number(thread.to_double())
  db.exec("BEGIN IMMEDIATE")
  errdefer (db.exec("ROLLBACK") catch { _ => () })
  if checked != Some(schema_version(db)) {
    db.exec("COMMIT")
    return false
  }
  guard first_row(db, "SELECT version,epoch FROM archive_last_meta WHERE id=1", []) is Some(meta) else {
    db.exec("COMMIT")
    self.checked = None
    return false
  }
  guard value(meta, "version") is Number(n, ..) && n.to_int() == version else {
    fail("archive last metadata has an unsupported version")
  }
  let epoch = value(meta, "epoch")
  ignore(
    db.run(
      "INSERT INTO archive_last_guard(thread,epoch,before_n,at,ready) VALUES(?,?,NULL,NULL,0) ON CONFLICT(thread) DO UPDATE SET epoch=excluded.epoch,before_n=NULL,at=NULL,ready=0 WHERE archive_last_guard.epoch!=excluded.epoch",
      [t, epoch],
    ),
  )
  guard first_row(
      db,
      "SELECT CAST(before_n AS TEXT) AS before_n,at,ready FROM archive_last_guard WHERE thread=? AND epoch=?",
      [t, epoch],
    )
    is Some(state) else {
    fail("archive last guard is missing")
  }
  // (a ready guard of the earlier time-only worker has no key: its time serves archive reads, a message asked for
  // scans again)
  let ready = value(state, "ready") is Number(r, ..) && r != 0.0
  if ready && (!(value(state, "before_n") is Null) || value(state, "at") is Null) {
    db.exec("COMMIT")
    return true
  }
  let lim = Json::number(limit.to_double())
  let rows = if value(state, "before_n") is Null {
    db.all(slice_first, [t, lim])
  } else {
    db.all(slice_before, [t, value(state, "before_n"), lim])
  }
  let last = rows.iter().find_first(r => !(value(r, "at") is Null))
  let done = last is Some(_) || rows.length() < limit
  let before = match last {
    Some(l) => value(l, "n")
    None => if done { Json::null() } else { value(rows[rows.length() - 1], "n") }
  }
  let at = match last {
    Some(l) => value(l, "at")
    None => Json::null()
  }
  ignore(
    db.run("UPDATE archive_last_guard SET before_n=CAST(? AS INTEGER),at=?,ready=? WHERE thread=? AND epoch=?", [
      before,
      at,
      Json::number(if done { 1.0 } else { 0.0 }),
      t,
      epoch,
    ]),
  )
  db.exec("COMMIT")
  done
}
