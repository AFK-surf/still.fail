// The pending requests' lookup (pending-index.ts), the vaults' members (member-index.ts) and the recoverable requests
// (rebox-index.ts), each prepared in bounded transactions as their `backfill…` functions do.

///|
fn owner_decision(body : String) -> String {
  "json_extract(\{body}, '$.vault') = 'plain' OR CASE json_type(\{body}, '$.save') WHEN 'object' THEN 1 WHEN 'array' THEN 1 WHEN 'true' THEN 1 WHEN 'text' THEN json_extract(\{body}, '$.save') != '' WHEN 'integer' THEN json_extract(\{body}, '$.save') != 0 WHEN 'real' THEN json_extract(\{body}, '$.save') != 0 ELSE 0 END"
}

///|
fn pending_values(row : String) -> String {
  let body = "\{row}.body"
  "\{row}.ws, \{row}.id, CASE WHEN \{owner_decision(body)} THEN 1 ELSE 0 END, CASE WHEN \{owner_decision(body)} THEN json_extract(\{body}, '$.owner') ELSE json_extract(\{body}, '$.vault') END, json_extract(\{body}, '$.at')"
}

///|
fn duplicate_fields(body : String) -> String {
  "CASE WHEN json_valid(\{body}) THEN EXISTS (SELECT 1 FROM json_each(\{body}) WHERE key IN ('vault', 'owner', 'save', 'at') GROUP BY key HAVING count(*) > 1) ELSE 0 END"
}

///|
fn nul_fields(body : String) -> String {
  "CASE WHEN instr(\{body}, '\\u0000') > 0 AND json_valid(\{body}) THEN EXISTS (SELECT 1 FROM json_each(\{body}) WHERE instr(key, char(0)) > 0) ELSE 0 END"
}

///|
fn pending_index_complete(db : @sql.Db, ws : Json) -> Bool raise {
  done_of(db, "SELECT done FROM vault_pending_backfill WHERE ws = ?", [ws])
}

///|
fn duplicate_audit_complete(db : @sql.Db, ws : Json) -> Bool raise {
  done_of(db, "SELECT done FROM vault_pending_audit_v2 WHERE ws = ?", [ws])
}

///|
fn nul_audit_complete(db : @sql.Db, ws : Json) -> Bool raise {
  done_of(db, "SELECT done FROM vault_pending_nul_audit_v3 WHERE ws = ?", [ws])
}

///|
fn has_vault_members(db : @sql.Db) -> Bool raise {
  first(db, "SELECT 1 FROM sqlite_schema WHERE type = 'table' AND name = 'vault_member_backfill'", []) is Some(_)
}

///|
fn vault_members_complete(db : @sql.Db, ws : Json) -> Bool raise {
  match
    first(
      db,
      "SELECT b.done, a.done AS audited, t.done AS type_audited, n.done AS nul_audited FROM vault_member_backfill b LEFT JOIN vault_member_audit_v2 a ON a.ws = b.ws LEFT JOIN vault_member_type_audit_v3 t ON t.ws = b.ws LEFT JOIN vault_member_nul_audit_v4 n ON n.ws = b.ws WHERE b.ws = ?",
      [ws],
    ) {
    Some(r) =>
      ["done", "audited", "type_audited", "nul_audited"].iter().all(k => get(r, k) is Number(1.0, ..))
    None => false
  }
}

///|
/// The workspace's pending lookup prepared (with its audits and members where asked) (`pendingPreparationComplete`).
pub fn pending_preparation_complete(db : @sql.Db, ws : Json, members : Bool, audit : Bool) -> Bool raise {
  pending_index_complete(db, ws) &&
  (!audit || (duplicate_audit_complete(db, ws) && nul_audit_complete(db, ws))) &&
  (!members || !has_vault_members(db) || vault_members_complete(db, ws))
}

///|
fn audit_pending(db : @sql.Db, table : String, check : (String) -> String, ws : Json, rows : Array[Map[String, Json]]) -> Unit raise {
  for row in rows {
    ignore(db.run("DELETE FROM \{table} WHERE ws = ? AND id = ?", [ws, get(row, "id")]))
    ignore(
      db.run(
        "INSERT OR IGNORE INTO \{table} SELECT r.ws, r.id FROM vault_requests r WHERE r.ws = ? AND r.id = ? AND r.status = 'pending' AND (\{check("r.body")}) = 1",
        [ws, get(row, "id")],
      ),
    )
  }
}

///|
/// One batch of an audit of the old pending lookup (`backfillPendingAudit`, `backfillPendingNulAudit`).
fn backfill_pending_audit(db : @sql.Db, ws : Json, progress : String, table : String, check : (String) -> String, limit? : Int = 32) -> Bool raise {
  tx(db, () => {
    ignore(db.run("INSERT OR IGNORE INTO \{progress} (ws, after_id, done) VALUES (?, NULL, 0)", [ws]))
    let audit = first(db, "SELECT after_id, done FROM \{progress} WHERE ws = ?", [ws]).unwrap()
    if get(audit, "done") is Number(1.0, ..) {
      return true
    }
    let rows = ids_after(db, "vault_pending_lookup", ws, get(audit, "after_id"), limit)
    audit_pending(db, table, check, ws, rows)
    let done = rows.length() < limit
    ignore(
      db.run("UPDATE \{progress} SET after_id = ?, done = ? WHERE ws = ?", [
        last_id(rows, get(audit, "after_id")),
        flag(done),
        ws,
      ]),
    )
    done
  })
}

///|
/// One batch of the old pending requests (`backfillPendingIndex`), new workspaces' audits along with it.
fn backfill_pending_index(db : @sql.Db, ws : Json, limit? : Int = 32) -> Bool raise {
  tx(db, () => {
    for t in ["vault_pending_backfill", "vault_pending_audit_v2", "vault_pending_nul_audit_v3"] {
      ignore(db.run("INSERT OR IGNORE INTO \{t} (ws, after_id, done) VALUES (?, NULL, 0)", [ws]))
    }
    let state = first(db, "SELECT after_id, done FROM vault_pending_backfill WHERE ws = ?", [ws]).unwrap()
    let audit = first(db, "SELECT after_id, done FROM vault_pending_audit_v2 WHERE ws = ?", [ws]).unwrap()
    let nul = first(db, "SELECT after_id, done FROM vault_pending_nul_audit_v3 WHERE ws = ?", [ws]).unwrap()
    if get(state, "done") is Number(1.0, ..) {
      return true
    }
    let rows = ids_after(db, "vault_requests", ws, get(state, "after_id"), limit)
    for row in rows {
      ignore(
        db.run(
          "INSERT OR IGNORE INTO vault_pending_lookup SELECT \{pending_values("r")} FROM vault_requests r WHERE r.ws = ? AND r.id = ? AND r.status = 'pending'",
          [ws, get(row, "id")],
        ),
      )
    }
    let done = rows.length() < limit
    for a in [
      (audit, "vault_pending_audit_v2", "vault_pending_duplicates_v2", duplicate_fields),
      (nul, "vault_pending_nul_audit_v3", "vault_pending_nul_v3", nul_fields),
    ] {
      let (p, progress, table, check) = a
      if !(get(p, "done") is Number(1.0, ..)) && get(p, "after_id") == get(state, "after_id") {
        audit_pending(db, table, check, ws, rows)
        ignore(
          db.run("UPDATE \{progress} SET after_id = ?, done = ? WHERE ws = ?", [
            last_id(rows, get(p, "after_id")),
            flag(done),
            ws,
          ]),
        )
      }
    }
    ignore(
      db.run("UPDATE vault_pending_backfill SET after_id = ?, done = ? WHERE ws = ?", [
        last_id(rows, get(state, "after_id")),
        flag(done),
        ws,
      ]),
    )
    done
  })
}

///|
/// One batch toward a workspace's pending lookup (`backfillPendingPreparation`).
pub fn backfill_pending_preparation(db : @sql.Db, ws : Json, members : Bool, audit : Bool) -> Bool raise {
  if !pending_index_complete(db, ws) {
    if !backfill_pending_index(db, ws) {
      return false
    }
    return pending_preparation_complete(db, ws, members, audit)
  }
  if audit && !duplicate_audit_complete(db, ws) {
    return backfill_pending_audit(db, ws, "vault_pending_audit_v2", "vault_pending_duplicates_v2", duplicate_fields) &&
      pending_preparation_complete(db, ws, members, audit)
  }
  if audit && !nul_audit_complete(db, ws) {
    return backfill_pending_audit(db, ws, "vault_pending_nul_audit_v3", "vault_pending_nul_v3", nul_fields) &&
      pending_preparation_complete(db, ws, members, audit)
  }
  !members || !has_vault_members(db) || vault_members_complete(db, ws) || backfill_vault_members(db, ws)
}

// The vaults' members (member-index.ts).

///|
fn valid_members(body : String) -> String {
  "CASE WHEN json_valid(\{body}) THEN CASE WHEN json_type(\{body}, '$.members') = 'array' THEN 1 ELSE 0 END ELSE 0 END"
}

///|
fn members_body(body : String) -> String {
  "CASE WHEN (\{valid_members(body)}) = 1 THEN \{body} ELSE '{\"members\":[]}' END"
}

///|
fn duplicate_members(body : String) -> String {
  "CASE WHEN json_valid(\{body}) THEN EXISTS (SELECT 1 FROM json_each(\{body}) WHERE key = 'members' LIMIT 1 OFFSET 1) ELSE 0 END"
}

///|
fn nul_members(body : String) -> String {
  "CASE WHEN instr(\{body}, '\\u0000') > 0 AND json_valid(\{body}) THEN EXISTS (SELECT 1 FROM json_each(\{body}) WHERE instr(key, char(0)) > 0 AND substr(key, 1, instr(key, char(0)) - 1) = 'members') ELSE 0 END"
}

///|
/// At most `limit` vaults' members, invalid bodies and audits (`backfillVaultMembers`).
fn backfill_vault_members(db : @sql.Db, ws : Json, limit? : Int = 32) -> Bool raise {
  tx(db, () => {
    let tables = ["vault_member_backfill", "vault_member_audit_v2", "vault_member_type_audit_v3", "vault_member_nul_audit_v4"]
    for t in tables {
      ignore(db.run("INSERT OR IGNORE INTO \{t} (ws, after_id, done) VALUES (?, NULL, 0)", [ws]))
    }
    let read = (t : String) => first(db, "SELECT after_id, done FROM \{t} WHERE ws = ?", [ws]).unwrap()
    let state = read(tables[0])
    let audit = read(tables[1])
    let types = read(tables[2])
    let nul = read(tables[3])
    let is_done = (r : Map[String, Json]) => !(get(r, "done") is Number(0.0, ..))
    if is_done(state) && is_done(audit) && is_done(types) && is_done(nul) {
      return true
    }
    let audit_batch = !is_done(audit) && (is_done(state) || get(state, "after_id") == get(audit, "after_id"))
    let after = if !is_done(state) {
      get(state, "after_id")
    } else if !is_done(audit) {
      get(audit, "after_id")
    } else if !is_done(types) {
      get(types, "after_id")
    } else {
      get(nul, "after_id")
    }
    let type_batch = !is_done(types) && get(types, "after_id") == after
    let nul_batch = !is_done(nul) && get(nul, "after_id") == after
    let rows = ids_after(db, "vaults", ws, after, limit)
    let done = rows.length() < limit
    let invalid = "INSERT OR IGNORE INTO vault_member_invalid SELECT v.ws, v.id FROM vaults v WHERE v.ws = ? AND v.id = ? AND (\{valid_members("v.body")}) = 0"
    let add = "INSERT OR IGNORE INTO vault_member_lookup SELECT v.ws, m.value, v.id FROM vaults v JOIN json_each(\{members_body("v.body")}, '$.members') m WHERE v.ws = ? AND v.id = ? AND m.type = 'text'"
    if !is_done(state) {
      for row in rows {
        ignore(db.run(invalid, [ws, get(row, "id")]))
        ignore(db.run(add, [ws, get(row, "id")]))
      }
      ignore(db.run("UPDATE vault_member_backfill SET after_id = ?, done = ? WHERE ws = ?", [last_id(rows, get(state, "after_id")), flag(done), ws]))
    }
    if audit_batch {
      for row in rows {
        ignore(db.run("DELETE FROM vault_member_duplicates_v2 WHERE ws = ? AND vault = ?", [ws, get(row, "id")]))
        ignore(
          db.run(
            "INSERT OR IGNORE INTO vault_member_duplicates_v2 SELECT v.ws, v.id FROM vaults v WHERE v.ws = ? AND v.id = ? AND (\{duplicate_members("v.body")}) = 1",
            [ws, get(row, "id")],
          ),
        )
      }
      ignore(db.run("UPDATE vault_member_audit_v2 SET after_id = ?, done = ? WHERE ws = ?", [last_id(rows, get(audit, "after_id")), flag(done), ws]))
    }
    if type_batch {
      let clear = "DELETE FROM vault_member_invalid WHERE ws = ? AND vault = ? AND EXISTS (SELECT 1 FROM vaults v WHERE v.ws = ? AND v.id = ? AND (\{valid_members("v.body")}) = 1)"
      for row in rows {
        let id = get(row, "id")
        if !is_done(state) {
          ignore(db.run(clear, [ws, id, ws, id]))
        } else {
          ignore(db.run(add, [ws, id]))
          ignore(db.run(clear, [ws, id, ws, id]))
          ignore(db.run(invalid, [ws, id]))
        }
      }
      ignore(db.run("UPDATE vault_member_type_audit_v3 SET after_id = ?, done = ? WHERE ws = ?", [last_id(rows, get(types, "after_id")), flag(done), ws]))
    }
    if nul_batch {
      for row in rows {
        ignore(db.run("DELETE FROM vault_member_nul_v4 WHERE ws = ? AND vault = ?", [ws, get(row, "id")]))
        ignore(
          db.run(
            "INSERT OR IGNORE INTO vault_member_nul_v4 SELECT v.ws, v.id FROM vaults v WHERE v.ws = ? AND v.id = ? AND (\{nul_members("v.body")}) = 1",
            [ws, get(row, "id")],
          ),
        )
      }
      ignore(db.run("UPDATE vault_member_nul_audit_v4 SET after_id = ?, done = ? WHERE ws = ?", [last_id(rows, get(nul, "after_id")), flag(done), ws]))
    }
    (is_done(state) || done) &&
    (is_done(audit) || (audit_batch && done)) &&
    (is_done(types) || (type_batch && done)) &&
    (is_done(nul) || (nul_batch && done))
  })
}

// The recoverable requests (rebox-index.ts).

///|
/// At most `limit` old request ids put in the recovery lookup (`backfillReboxIndex`); whether all are.
pub fn backfill_rebox(db : @sql.Db, limit? : Int = 32) -> Bool raise {
  tx(db, () => {
    let state = first(db, "SELECT after_ws, after_id, done FROM vault_rebox_backfill WHERE id = 1", []).unwrap()
    if get(state, "done") is Number(1.0, ..) {
      return true
    }
    let lim = Json::number(limit.to_double())
    let rows = if get(state, "after_ws") is Null {
      db.all("SELECT ws, id FROM vault_requests ORDER BY ws, id LIMIT ?", [lim])
    } else {
      db.all("SELECT ws, id FROM vault_requests WHERE (ws, id) > (?, ?) ORDER BY ws, id LIMIT ?", [
        get(state, "after_ws"),
        get(state, "after_id"),
        lim,
      ])
    }
    for row in rows {
      ignore(
        db.run(
          "INSERT INTO vault_rebox_lookup SELECT ws, id FROM vault_requests WHERE ws = ? AND id = ? AND status = 'pending' ON CONFLICT(ws, id) DO NOTHING",
          [get(row, "ws"), get(row, "id")],
        ),
      )
    }
    let done = rows.length() < limit
    let (ws, id) = match rows.last() {
      Some(r) => (get(r, "ws"), get(r, "id"))
      None => (get(state, "after_ws"), get(state, "after_id"))
    }
    ignore(db.run("UPDATE vault_rebox_backfill SET after_ws = ?, after_id = ?, done = ? WHERE id = 1", [ws, id, flag(done)]))
    done
  })
}
