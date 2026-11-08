// A large old store's per-chat lookups, prepared only for the chats a read asks for, here for the MoonBit builder: the
// closed cards by time (station/src/store/legacy-closed-cards.ts, `closedCardsStep`) and people's messages by time
// (legacy-people-since.ts, `peopleSinceStep`). A small store gets the native index instead; a large one the lookup's
// tables and triggers, then each asked chat's old rows copied in batches of at most 64.

///|
let version : Int = 1

///|
let batch : Int = 64

///|
/// One lookup: what it is called in errors, its tables, the source it copies, and how a store gets it.
priv struct Lookup {
  name : String
  /// The native index a small store gets, and how it is made.
  native : String
  native_ddl : String
  meta : String
  scopes : String
  /// The source table (more than 64 rows: the lookup instead of the native index).
  source : String
  schema : String
  /// One old row copied: `?1` the chat, `?2` its number as text.
  put : String
  /// A store made before the lookup removed a deleted chat's scope: that trigger, added when it is missing.
  cleanup : (String, String)?
}

///|
fn closed_candidates(p : String) -> String {
  "SELECT rowid AS id FROM closed_cards WHERE thread=\{p}.thread AND n=\{p}.n UNION SELECT rowid FROM closed_cards WHERE rowid=\{p}.rowid"
}

///|
fn closed_remove(p : String) -> String {
  "DELETE FROM legacy_closed_cards WHERE thread=\{p}.thread AND n=\{p}.n; DELETE FROM legacy_closed_cards WHERE source_rowid=\{p}.rowid;"
}

///|
fn closed_add(ids : String) -> String {
  "INSERT INTO legacy_closed_cards(thread,at,source_rowid,n) SELECT c.thread,c.at,c.rowid,c.n FROM (\{ids}) p CROSS JOIN closed_cards c ON c.rowid=p.id WHERE EXISTS (SELECT 1 FROM legacy_closed_scopes s WHERE s.thread=c.thread) AND NOT EXISTS (SELECT 1 FROM legacy_closed_cards k WHERE k.thread=c.thread AND k.n=c.n);"
}

///|
let closed : Lookup = {
  let changed = "OLD.thread IS NOT NEW.thread OR OLD.n IS NOT NEW.n OR OLD.at IS NOT NEW.at OR OLD.rowid IS NOT NEW.rowid"
  {
    name: "closed-card",
    native: "closed_cards_thread_at",
    native_ddl: "CREATE INDEX IF NOT EXISTS closed_cards_thread_at ON closed_cards (thread, at)",
    meta: "legacy_closed_meta",
    scopes: "legacy_closed_scopes",
    source: "closed_cards",
    schema: [
      "CREATE TABLE legacy_closed_meta (id INTEGER PRIMARY KEY CHECK(id=1),version INTEGER NOT NULL) WITHOUT ROWID;",
      "INSERT INTO legacy_closed_meta VALUES(1,\{version});",
      "CREATE TABLE legacy_closed_scopes (thread INTEGER PRIMARY KEY,last_n INTEGER,end_n INTEGER,complete INTEGER NOT NULL) WITHOUT ROWID;",
      "CREATE TABLE legacy_closed_cards (source_rowid INTEGER PRIMARY KEY,thread INTEGER NOT NULL,n INTEGER NOT NULL,at INTEGER NOT NULL);",
      "CREATE UNIQUE INDEX legacy_closed_by_entry ON legacy_closed_cards(thread,n);",
      "CREATE INDEX legacy_closed_by_time ON legacy_closed_cards(thread,at);",
      "CREATE TRIGGER legacy_closed_insert AFTER INSERT ON closed_cards BEGIN \{closed_remove("NEW")} \{closed_add(closed_candidates("NEW"))} END;",
      "CREATE TRIGGER legacy_closed_update AFTER UPDATE ON closed_cards WHEN \{changed} BEGIN \{closed_remove("OLD")} \{closed_remove("NEW")} \{closed_add(closed_candidates("OLD") + " UNION " + closed_candidates("NEW"))} END;",
      "CREATE TRIGGER legacy_closed_delete AFTER DELETE ON closed_cards BEGIN \{closed_remove("OLD")} \{closed_add(closed_candidates("OLD"))} END;",
    ].join("\n"),
    put: "INSERT INTO legacy_closed_cards(thread,at,source_rowid,n) SELECT c.thread,c.at,c.rowid,c.n FROM closed_cards c WHERE c.thread=?1 AND c.n=CAST(?2 AS INTEGER) AND NOT EXISTS (SELECT 1 FROM legacy_closed_cards k WHERE k.thread=c.thread AND k.n=c.n)",
    cleanup: Some(
      (
        "legacy_closed_drop_thread",
        "CREATE TRIGGER legacy_closed_drop_thread AFTER DELETE ON threads WHEN NOT EXISTS (SELECT 1 FROM closed_cards WHERE thread=OLD.id LIMIT 1) BEGIN DELETE FROM legacy_closed_scopes WHERE thread=OLD.id; END;",
      ),
    ),
  }
}

///|
fn people_candidates(p : String) -> String {
  "SELECT rowid AS id FROM entries WHERE thread=\{p}.thread AND n=\{p}.n UNION SELECT rowid FROM entries INDEXED BY entries_ts WHERE \{p}.ts IS NOT NULL AND thread=\{p}.thread AND ts=\{p}.ts UNION SELECT rowid FROM entries WHERE rowid=\{p}.rowid"
}

///|
fn people_remove(p : String) -> String {
  "DELETE FROM legacy_people_time_rows WHERE thread=\{p}.thread AND n=\{p}.n; DELETE FROM legacy_people_time_rows WHERE source_rowid=\{p}.rowid; DELETE FROM legacy_people_time_rows WHERE \{p}.ts IS NOT NULL AND thread=\{p}.thread AND ts=\{p}.ts;"
}

///|
fn people_add(ids : String) -> String {
  "INSERT INTO legacy_people_time_rows(source_rowid,thread,n,at,ts) SELECT e.rowid,e.thread,e.n,e.at,e.ts FROM (\{ids}) p CROSS JOIN entries e ON e.rowid=p.id WHERE e.kind='message' AND e.author_kind='person' AND EXISTS (SELECT 1 FROM legacy_people_time_scopes s WHERE s.thread=e.thread) AND NOT EXISTS (SELECT 1 FROM legacy_people_time_rows k WHERE k.source_rowid=e.rowid) AND NOT EXISTS (SELECT 1 FROM legacy_people_time_rows k WHERE k.thread=e.thread AND k.n=e.n);"
}

///|
let people : Lookup = {
  let changed = "OLD.thread IS NOT NEW.thread OR OLD.n IS NOT NEW.n OR OLD.rowid IS NOT NEW.rowid OR OLD.ts IS NOT NEW.ts OR OLD.at IS NOT NEW.at OR OLD.kind IS NOT NEW.kind OR OLD.author_kind IS NOT NEW.author_kind"
  {
    name: "people-time",
    native: "entries_people_since",
    native_ddl: "CREATE INDEX IF NOT EXISTS entries_people_since ON entries (thread, at) WHERE author_kind = 'person' AND kind = 'message'",
    meta: "legacy_people_time_meta",
    scopes: "legacy_people_time_scopes",
    source: "entries",
    schema: [
      "CREATE TABLE legacy_people_time_meta(id INTEGER PRIMARY KEY CHECK(id=1),version INTEGER NOT NULL) WITHOUT ROWID;",
      "INSERT INTO legacy_people_time_meta VALUES(1,\{version});",
      "CREATE TABLE legacy_people_time_scopes(thread INTEGER PRIMARY KEY,last_n INTEGER,end_n INTEGER,complete INTEGER NOT NULL) WITHOUT ROWID;",
      "CREATE TABLE legacy_people_time_rows(source_rowid INTEGER PRIMARY KEY,thread INTEGER NOT NULL,n INTEGER NOT NULL,at INTEGER NOT NULL,ts TEXT);",
      "CREATE UNIQUE INDEX legacy_people_time_by_entry ON legacy_people_time_rows(thread,n);",
      "CREATE INDEX legacy_people_time_by_at ON legacy_people_time_rows(thread,at);",
      "CREATE INDEX legacy_people_time_by_ts ON legacy_people_time_rows(thread,ts) WHERE ts IS NOT NULL;",
      "CREATE TRIGGER legacy_people_time_insert AFTER INSERT ON entries WHEN EXISTS (SELECT 1 FROM legacy_people_time_scopes WHERE thread=NEW.thread) OR EXISTS (SELECT 1 FROM legacy_people_time_rows WHERE source_rowid=NEW.rowid) BEGIN \{people_remove("NEW")} \{people_add(people_candidates("NEW"))} END;",
      "CREATE TRIGGER legacy_people_time_update AFTER UPDATE ON entries WHEN (\{changed}) AND (EXISTS (SELECT 1 FROM legacy_people_time_scopes WHERE thread IN (OLD.thread,NEW.thread)) OR EXISTS (SELECT 1 FROM legacy_people_time_rows WHERE source_rowid=NEW.rowid)) BEGIN \{people_remove("OLD")} \{people_remove("NEW")} \{people_add(people_candidates("OLD") + " UNION " + people_candidates("NEW"))} END;",
      "CREATE TRIGGER legacy_people_time_delete AFTER DELETE ON entries WHEN EXISTS (SELECT 1 FROM legacy_people_time_scopes WHERE thread=OLD.thread) OR EXISTS (SELECT 1 FROM legacy_people_time_rows WHERE source_rowid=OLD.rowid) BEGIN \{people_remove("OLD")} \{people_add(people_candidates("OLD"))} END;",
      "CREATE TRIGGER legacy_people_time_drop_thread AFTER DELETE ON threads WHEN NOT EXISTS (SELECT 1 FROM entries WHERE thread=OLD.id LIMIT 1) BEGIN DELETE FROM legacy_people_time_scopes WHERE thread=OLD.id; END;",
    ].join("\n"),
    put: "INSERT INTO legacy_people_time_rows(source_rowid,thread,n,at,ts) SELECT e.rowid,e.thread,e.n,e.at,e.ts FROM entries e WHERE e.thread=?1 AND e.n=CAST(?2 AS INTEGER) AND e.kind='message' AND e.author_kind='person' AND NOT EXISTS (SELECT 1 FROM legacy_people_time_rows k WHERE k.source_rowid=e.rowid) AND NOT EXISTS (SELECT 1 FROM legacy_people_time_rows k WHERE k.thread=e.thread AND k.n=e.n)",
    cleanup: None,
  }
}

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
fn meta_version(db : @sql.Db, l : Lookup) -> Int? raise {
  match first(db, "SELECT version FROM \{l.meta} WHERE id=1", []) {
    Some(r) =>
      match r.get("version") {
        Some(Number(v, ..)) => Some(v.to_int())
        _ => Some(-1)
      }
    None => None
  }
}

///|
fn native(db : @sql.Db, l : Lookup) -> Bool raise {
  exists(db, "index", l.native)
}

///|
/// The lookup's tables there, of this version; of another, an error.
fn legacy(db : @sql.Db, l : Lookup) -> Bool raise {
  if !exists(db, "table", l.meta) {
    return false
  }
  guard meta_version(db, l) == Some(version) else {
    raise Failure("legacy \{l.name} lookup has an unsupported version")
  }
  true
}

///|
/// A lookup made before its cleanup trigger, of this version (one of another is left alone).
fn needs_cleanup(db : @sql.Db, l : Lookup) -> Bool raise {
  guard l.cleanup is Some((trigger, _)) else { return false }
  if !exists(db, "table", l.meta) ||
    exists(db, "trigger", trigger) ||
    !exists(db, "table", "threads") ||
    !exists(db, "table", l.scopes) {
    return false
  }
  meta_version(db, l) == Some(version)
}

///|
/// The native index on a small store, else the lookup (both choices checked again under the write lock).
fn install(db : @sql.Db, l : Lookup) -> Unit raise {
  if (native(db, l) || legacy(db, l)) && !needs_cleanup(db, l) {
    return
  }
  db.exec("BEGIN IMMEDIATE")
  errdefer (db.exec("ROLLBACK") catch { _ => () })
  if !native(db, l) && !legacy(db, l) {
    if first(db, "SELECT 1 FROM \{l.source} LIMIT 1 OFFSET 63", []) is None {
      db.exec(l.native_ddl)
    } else {
      db.exec(l.schema)
    }
  }
  if needs_cleanup(db, l) && l.cleanup is Some((_, ddl)) {
    db.exec(ddl)
  }
  db.exec("COMMIT")
}

///|
fn scope_of(db : @sql.Db, l : Lookup, thread : Json) -> Map[String, Json]? raise {
  first(
    db,
    "SELECT CAST(last_n AS TEXT) AS last_n,CAST(end_n AS TEXT) AS end_n,complete FROM \{l.scopes} WHERE thread=?",
    [thread],
  )
}

///|
fn get(row : Map[String, Json], name : String) -> Json {
  row.get(name).unwrap_or(Json::null())
}

///|
/// At most `limit` (64 at most) of `thread`'s old rows copied into the lookup; whether all of its are then.
fn step(db : @sql.Db, l : Lookup, thread : Int64, limit : Int) -> Bool raise {
  guard limit >= 1 && limit <= batch else { raise Failure("\{l.name} batch must be 1–64") }
  install(db, l)
  if native(db, l) {
    return true
  }
  let t = Json::number(thread.to_double())
  db.exec("BEGIN IMMEDIATE")
  errdefer (db.exec("ROLLBACK") catch { _ => () })
  // (an older connection may have changed the schema between the install and this write lock)
  if native(db, l) {
    db.exec("COMMIT")
    return true
  }
  if !legacy(db, l) {
    db.exec("COMMIT")
    return false
  }
  if scope_of(db, l, t) is None {
    // (a request queued before its chat was deleted does not make the chat's scope again)
    let chats = l.cleanup is None || exists(db, "table", "threads")
    if chats &&
      first(db, "SELECT 1 FROM threads WHERE id=?", [t]) is None &&
      first(db, "SELECT 1 FROM \{l.source} WHERE thread=? LIMIT 1", [t]) is None {
      db.exec("COMMIT")
      return true
    }
    ignore(
      db.run(
        "INSERT INTO \{l.scopes}(thread,last_n,end_n,complete) VALUES(?1,NULL,(SELECT n FROM \{l.source} WHERE thread=?1 ORDER BY n DESC LIMIT 1),0)",
        [t],
      ),
    )
  }
  guard scope_of(db, l, t) is Some(s) else { raise Failure("\{l.name} scope is missing") }
  if get(s, "complete") is Number(1.0, ..) {
    db.exec("COMMIT")
    return true
  }
  let last = get(s, "last_n")
  let end = get(s, "end_n")
  let lim = Json::number(limit.to_double())
  let rows = if end is Null {
    []
  } else if last is Null {
    db.all(
      "SELECT CAST(n AS TEXT) AS n FROM (SELECT n FROM \{l.source} WHERE thread=?1 AND n<=CAST(?2 AS INTEGER) ORDER BY n LIMIT ?3)",
      [t, end, lim],
    )
  } else {
    db.all(
      "SELECT CAST(n AS TEXT) AS n FROM (SELECT n FROM \{l.source} WHERE thread=?1 AND n>CAST(?2 AS INTEGER) AND n<=CAST(?3 AS INTEGER) ORDER BY n LIMIT ?4)",
      [t, last, end, lim],
    )
  }
  for row in rows {
    ignore(db.run(l.put, [t, get(row, "n")]))
  }
  let done = rows.length() < limit
  let reached = match rows.last() {
    Some(r) => get(r, "n")
    None => last
  }
  ignore(
    db.run("UPDATE \{l.scopes} SET last_n=CAST(? AS INTEGER),complete=? WHERE thread=?", [
      reached,
      Json::number(if done { 1.0 } else { 0.0 }),
      t,
    ]),
  )
  db.exec("COMMIT")
  done
}

///|
/// One batch of the closed cards of `thread` (`closedCardsStep`).
pub fn closed_step(db : @sql.Db, thread : Int64, limit? : Int = 64) -> Bool raise {
  step(db, closed, thread, limit)
}

///|
/// One batch of the people's messages of `thread` (`peopleSinceStep`).
pub fn people_step(db : @sql.Db, thread : Int64, limit? : Int = 64) -> Bool raise {
  step(db, people, thread, limit)
}
