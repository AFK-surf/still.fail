// The vault's decided uses, its pending requests' lookup, its vaults' members and its recoverable requests (station/
// src/vault/use-index.ts, pending-index.ts, member-index.ts, rebox-index.ts): each filled from old rows in bounded
// transactions, as their `backfill…` functions do, here for the MoonBit builder. Exceptional request bodies are read
// as JavaScript reads them (@jsjson), their identities kept as UTF-16 code units.

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
fn done_of(db : @sql.Db, sql : String, params : Array[Json]) -> Bool raise {
  match first(db, sql, params) {
    Some(r) => get(r, "done") is Number(1.0, ..)
    None => false
  }
}

///|
fn flag(b : Bool) -> Json {
  Json::number(if b { 1.0 } else { 0.0 })
}

///|
fn tx(db : @sql.Db, f : () -> Bool raise) -> Bool raise {
  db.exec("BEGIN IMMEDIATE")
  errdefer (db.exec("ROLLBACK") catch { _ => () })
  let r = f()
  db.exec("COMMIT")
  r
}

///|
/// A cursor's next `limit` ids of `ws`'s rows in `table`.
fn ids_after(db : @sql.Db, table : String, ws : Json, after : Json, limit : Int) -> Array[Map[String, Json]] raise {
  let lim = Json::number(limit.to_double())
  if after is Null {
    db.all("SELECT id FROM \{table} WHERE ws = ? ORDER BY id LIMIT ?", [ws, lim])
  } else {
    db.all("SELECT id FROM \{table} WHERE ws = ? AND id > ? ORDER BY id LIMIT ?", [ws, after, lim])
  }
}

///|
fn last_id(rows : Array[Map[String, Json]], otherwise : Json) -> Json {
  match rows.last() {
    Some(r) => get(r, "id")
    None => otherwise
  }
}

// The decided uses (use-index.ts).

///|
fn ambiguous_use(body : String) -> String {
  "CASE WHEN json_valid(\{body}) THEN (instr(\{body}, '\\ud') > 0 OR instr(\{body}, '\\uD') > 0 OR (instr(\{body}, '\\u0000') > 0 AND EXISTS (SELECT 1 FROM json_each(\{body}) WHERE instr(key, char(0)) > 0)) OR EXISTS (SELECT 1 FROM json_each(\{body}) WHERE key IN ('vault','owner','save','at') GROUP BY key HAVING count(*) > 1)) ELSE 0 END"
}

///|
fn use_index_complete(db : @sql.Db, ws : Json) -> Bool raise {
  done_of(db, "SELECT done FROM vault_use_backfill WHERE ws = ?", [ws])
}

///|
fn use_audit_complete(db : @sql.Db, ws : Json) -> Bool raise {
  done_of(db, "SELECT done FROM vault_use_ambiguous_audit_v2 WHERE ws = ?", [ws])
}

///|
fn use_state(db : @sql.Db, ws : Json) -> Map[String, Json]? raise {
  first(
    db,
    "SELECT b.done, a.done AS audited, EXISTS (SELECT 1 FROM vault_use_ambiguous_v2 WHERE ws = b.ws AND dirty = 1 LIMIT 1) AS dirty, EXISTS (SELECT 1 FROM vault_use_ambiguous_v2 WHERE ws = b.ws LIMIT 1) AS ambiguous FROM vault_use_backfill b LEFT JOIN vault_use_ambiguous_audit_v2 a ON a.ws = b.ws WHERE b.ws = ?",
    [ws],
  )
}

///|
fn ready_state(s : Map[String, Json]?) -> Bool {
  s is Some(r) &&
  get(r, "done") is Number(1.0, ..) &&
  get(r, "audited") is Number(1.0, ..) &&
  get(r, "dirty") is Number(0.0, ..)
}

///|
fn use_ready(db : @sql.Db, ws : Json) -> Bool raise {
  ready_state(use_state(db, ws))
}

///|
fn audit_use_rows(db : @sql.Db, ws : Json, rows : Array[Map[String, Json]]) -> Unit raise {
  for row in rows {
    ignore(
      db.run(
        "INSERT OR IGNORE INTO vault_use_ambiguous_v2 (ws,id,dirty,is_use) SELECT ws, id, 1, 0 FROM vault_requests WHERE ws = ? AND id = ? AND status IN ('granted','denied') AND (\{ambiguous_use("body")}) = 1",
        [ws, get(row, "id")],
      ),
    )
  }
}

///|
fn backfill_use_audit(db : @sql.Db, ws : Json, limit? : Int = 32) -> Bool raise {
  tx(db, () => {
    ignore(db.run("INSERT OR IGNORE INTO vault_use_ambiguous_audit_v2 (ws,after_id,done) VALUES (?,NULL,0)", [ws]))
    let audit = first(db, "SELECT after_id, done FROM vault_use_ambiguous_audit_v2 WHERE ws = ?", [ws]).unwrap()
    if get(audit, "done") is Number(1.0, ..) {
      return true
    }
    let rows = ids_after(db, "vault_requests", ws, get(audit, "after_id"), limit)
    audit_use_rows(db, ws, rows)
    let done = rows.length() < limit
    ignore(
      db.run("UPDATE vault_use_ambiguous_audit_v2 SET after_id = ?, done = ? WHERE ws = ?", [
        last_id(rows, get(audit, "after_id")),
        flag(done),
        ws,
      ]),
    )
    done
  })
}

///|
/// What `useTime` binds of a body's `at`: null, a flag as 1 or 0, a number, a string, else its JSON.
fn use_time(v : @jsjson.JValue?) -> Json {
  match v {
    None | Some(Null) => Json::null()
    Some(Bool(b)) => flag(b)
    Some(Num(d)) => Json::number(d)
    Some(Str(s)) => Json::string(@jsjson.text(s))
    Some(other) => Json::string(@jsjson.stringify(other))
  }
}

///|
fn blob(s : Array[Int]) -> Json {
  Json::array(@jsjson.utf16le(s).map(b => Json::number(b.to_double())))
}

///|
/// At most `limit` exceptional bodies read as JavaScript reads them (`repairAmbiguousUses`).
fn repair_ambiguous(db : @sql.Db, ws : Json, limit? : Int = 32) -> Bool raise {
  tx(db, () => {
    let rows = db.all(
      "SELECT a.id, r.body, r.status FROM vault_use_ambiguous_v2 a LEFT JOIN vault_requests r ON r.ws = a.ws AND r.id = a.id WHERE a.ws = ? AND a.dirty = 1 ORDER BY a.id LIMIT ?",
      [ws, Json::number(limit.to_double())],
    )
    for row in rows {
      let id = get(row, "id")
      let status = get(row, "status")
      guard get(row, "body") is String(body) && (status == Json::string("granted") || status == Json::string("denied")) else {
        ignore(db.run("DELETE FROM vault_use_ambiguous_v2 WHERE ws = ? AND id = ?", [ws, id]))
        continue
      }
      let request = @jsjson.parse(body) catch { @jsjson.SyntaxError(m) => raise Failure("JSON.parse: \{m}") }
      let field = (name : String) => match request {
        Obj(_) => request.get(name)
        _ => None
      }
      let vault = match field("vault") {
        Some(Str(s)) => Some(s)
        _ => None
      }
      let owner = match field("owner") {
        Some(Str(s)) => Some(s)
        _ => None
      }
      let no_save = match field("save") {
        None | Some(Null) => true
        _ => false
      }
      ignore(
        db.run("UPDATE vault_use_ambiguous_v2 SET dirty = 0, is_use = ?, vault = ?, owner = ?, at = ? WHERE ws = ? AND id = ?", [
          flag(vault is Some(_) && no_save),
          match vault {
            Some(v) => blob(v)
            None => Json::null()
          },
          match owner {
            Some(o) => blob(o)
            None => Json::null()
          },
          use_time(field("at")),
          ws,
          id,
        ]),
      )
    }
    rows.length() < limit
  })
}

///|
fn backfill_use_index(db : @sql.Db, ws : Json, limit? : Int = 32) -> Bool raise {
  tx(db, () => {
    ignore(db.run("INSERT OR IGNORE INTO vault_use_backfill (ws, after_id, done) VALUES (?, NULL, 0)", [ws]))
    ignore(db.run("INSERT OR IGNORE INTO vault_use_ambiguous_audit_v2 (ws, after_id, done) VALUES (?, NULL, 0)", [ws]))
    let state = first(db, "SELECT after_id, done FROM vault_use_backfill WHERE ws = ?", [ws]).unwrap()
    let audit = first(db, "SELECT after_id, done FROM vault_use_ambiguous_audit_v2 WHERE ws = ?", [ws]).unwrap()
    if get(state, "done") is Number(1.0, ..) {
      return true
    }
    let rows = ids_after(db, "vault_requests", ws, get(state, "after_id"), limit)
    for row in rows {
      ignore(
        db.run(
          "INSERT OR IGNORE INTO vault_use_lookup SELECT ws, id, json_extract(body, '$.vault'), json_extract(body, '$.owner'), json_extract(body, '$.at') FROM vault_requests WHERE ws = ? AND id = ? AND status IN ('granted', 'denied') AND json_extract(body, '$.save') IS NULL",
          [ws, get(row, "id")],
        ),
      )
    }
    let done = rows.length() < limit
    if !(get(audit, "done") is Number(1.0, ..)) && get(audit, "after_id") == get(state, "after_id") {
      audit_use_rows(db, ws, rows)
      ignore(
        db.run("UPDATE vault_use_ambiguous_audit_v2 SET after_id = ?, done = ? WHERE ws = ?", [
          last_id(rows, get(audit, "after_id")),
          flag(done),
          ws,
        ]),
      )
    }
    ignore(
      db.run("UPDATE vault_use_backfill SET after_id = ?, done = ? WHERE ws = ?", [
        last_id(rows, get(state, "after_id")),
        flag(done),
        ws,
      ]),
    )
    done
  })
}

///|
/// One bounded step toward a complete use page (`backfillUsePreparation`).
pub fn backfill_use_preparation(db : @sql.Db, ws : Json) -> Bool raise {
  if !use_index_complete(db, ws) {
    return backfill_use_index(db, ws) && use_ready(db, ws)
  }
  if !use_audit_complete(db, ws) {
    return backfill_use_audit(db, ws) && use_ready(db, ws)
  }
  repair_ambiguous(db, ws) && use_ready(db, ws)
}

///|
/// One batch of the background preparation, a workspace at a time (`backfillNextWorkspace`); whether all are done.
pub fn backfill_next_workspace(db : @sql.Db) -> Bool raise {
  let state = first(db, "SELECT after_ws, done FROM vault_use_backfill_all WHERE id = 1", []).unwrap()
  if get(state, "done") is Number(1.0, ..) {
    return true
  }
  let after = get(state, "after_ws")
  let next = if after is Null {
    first(db, "SELECT ws FROM vault_requests ORDER BY ws LIMIT 1", [])
  } else {
    first(db, "SELECT ws FROM vault_requests WHERE ws > ? ORDER BY ws LIMIT 1", [after])
  }
  guard next is Some(n) else {
    ignore(db.run("UPDATE vault_use_backfill_all SET done = 1 WHERE id = 1 AND after_ws IS ?", [after]))
    return done_of(db, "SELECT done FROM vault_use_backfill_all WHERE id = 1", [])
  }
  let ws = get(n, "ws")
  if use_ready(db, ws) || backfill_use_preparation(db, ws) {
    ignore(db.run("UPDATE vault_use_backfill_all SET after_ws = ? WHERE id = 1 AND after_ws IS ? AND done = 0", [ws, after]))
  }
  false
}

///|
/// A read of a vault's (or an owner's) decided uses: its workspace, vault, owner (code units) and how many.
pub(all) struct UseRead {
  ws : Json
  vault : Array[Int]
  owner : Array[Int]?
  limit : Json
}

///|
fn well_formed(s : Array[Int]) -> Bool {
  let n = s.length()
  let mut i = 0
  while i < n {
    let c = s[i]
    if c >= 0xd800 && c <= 0xdbff {
      if i + 1 < n && s[i + 1] >= 0xdc00 && s[i + 1] <= 0xdfff {
        i += 2
        continue
      }
      return false
    }
    if c >= 0xdc00 && c <= 0xdfff {
      return false
    }
    i += 1
  }
  true
}

///|
/// The page, once the workspace's uses are prepared (`tryReadUses`); None before.
pub fn try_read_uses(db : @sql.Db, q : UseRead) -> Array[Json]? raise {
  db.exec("SAVEPOINT vault_use_page")
  defer (db.exec("RELEASE vault_use_page") catch { _ => () })
  let state = use_state(db, q.ws)
  if !ready_state(state) {
    return None
  }
  let ambiguous = !(get(state.unwrap(), "ambiguous") is Number(0.0, ..))
  let normal = well_formed(q.vault) && (match q.owner { Some(o) => well_formed(o); None => true })
  if !ambiguous && !normal {
    return Some([])
  }
  let vault = Json::string(@jsjson.text(q.vault))
  let rows = if !ambiguous {
    match q.owner {
      None =>
        db.all(
          "SELECT r.body FROM vault_use_lookup u INDEXED BY vault_use_lookup_vault JOIN vault_requests r ON r.ws = u.ws AND r.id = u.id WHERE u.ws = ?1 AND u.vault = ?2 ORDER BY u.at DESC, u.id DESC LIMIT ?3",
          [q.ws, vault, q.limit],
        )
      Some(o) =>
        db.all(
          "SELECT r.body FROM vault_use_lookup u INDEXED BY vault_use_lookup_owner JOIN vault_requests r ON r.ws = u.ws AND r.id = u.id WHERE u.ws = ?1 AND u.vault = ?2 AND u.owner = ?3 ORDER BY u.at DESC, u.id DESC LIMIT ?4",
          [q.ws, vault, Json::string(@jsjson.text(o)), q.limit],
        )
    }
  } else {
    match q.owner {
      None =>
        db.all(
          "SELECT r.body AS body, u.at AS at, u.id AS id FROM vault_use_lookup u INDEXED BY vault_use_lookup_vault JOIN vault_requests r ON r.ws = u.ws AND r.id = u.id WHERE ?4 AND u.ws = ?1 AND u.vault = ?2 AND NOT EXISTS (SELECT 1 FROM vault_use_ambiguous_v2 a WHERE a.ws = u.ws AND a.id = u.id) UNION ALL SELECT r.body, a.at, a.id FROM vault_use_ambiguous_v2 a INDEXED BY vault_use_ambiguous_vault_v2 JOIN vault_requests r ON r.ws = a.ws AND r.id = a.id WHERE a.ws = ?1 AND a.vault = ?3 AND a.dirty = 0 AND a.is_use = 1 ORDER BY at DESC, id DESC LIMIT ?5",
          [q.ws, vault, blob(q.vault), flag(normal), q.limit],
        )
      Some(o) =>
        db.all(
          "SELECT r.body AS body, u.at AS at, u.id AS id FROM vault_use_lookup u INDEXED BY vault_use_lookup_owner JOIN vault_requests r ON r.ws = u.ws AND r.id = u.id WHERE ?6 AND u.ws = ?1 AND u.vault = ?2 AND u.owner = ?3 AND NOT EXISTS (SELECT 1 FROM vault_use_ambiguous_v2 a WHERE a.ws = u.ws AND a.id = u.id) UNION ALL SELECT r.body, a.at, a.id FROM vault_use_ambiguous_v2 a INDEXED BY vault_use_ambiguous_owner_v2 JOIN vault_requests r ON r.ws = a.ws AND r.id = a.id WHERE a.ws = ?1 AND a.vault = ?4 AND a.owner = ?5 AND a.dirty = 0 AND a.is_use = 1 ORDER BY at DESC, id DESC LIMIT ?7",
          [q.ws, vault, Json::string(@jsjson.text(o)), blob(q.vault), blob(o), flag(normal), q.limit],
        )
    }
  }
  Some(rows.map(r => get(r, "body")))
}
