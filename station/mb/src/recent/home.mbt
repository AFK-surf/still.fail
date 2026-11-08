// Home: its default part (chat-list-home-index.ts, chat-list-home-source.ts) and its intersection with the named
// workspace (chat-list-home-overlap.ts).

///|
/// Whether a chat belongs to the default part of home, in bounded member batches (`recentHomeChatStep`): Some(in or
/// not) when decided, None with the cursor moved (`after`, `seen`) when more members are left.
fn home_chat(
  db : @sql.Db,
  thread : Json,
  after : Ref[Json],
  seen : Ref[Bool],
  limit : Int,
  visited : Ref[Int],
) -> Bool? raise {
  guard first(db, "SELECT home FROM threads WHERE id = CAST(? AS INTEGER)", [
      thread,
    ])
    is Some(chat) else {
    visited.val = 0
    return Some(false)
  }
  let session_ws = (key : Json) => {
    first(db, "SELECT ws FROM sessions WHERE key = ?", [key])
  }
  let home = get(chat, "home")
  if !(home is Null) {
    visited.val = 1
    return Some(
      match session_ws(home) {
        None => true
        Some(s) => get(s, "ws") is Null
      },
    )
  }
  let members = if after.val is Null {
    db.all(
      "SELECT session FROM thread_sessions WHERE thread = CAST(?1 AS INTEGER) ORDER BY session LIMIT ?2",
      [thread, num(limit)],
    )
  } else {
    db.all(
      "SELECT session FROM thread_sessions WHERE thread = CAST(?1 AS INTEGER) AND session > ?2 ORDER BY session LIMIT ?3",
      [thread, after.val, num(limit)],
    )
  }
  visited.val = members.length()
  for m in members {
    match session_ws(get(m, "session")) {
      None => return Some(true)
      Some(s) => if get(s, "ws") is Null { return Some(true) }
    }
  }
  if members.length() < limit {
    return Some(!seen.val && members.length() == 0)
  }
  after.val = get(members[members.length() - 1], "session")
  seen.val = true
  None
}

///|
fn mark_home_dirty(db : @sql.Db, thread : Json) -> Unit raise {
  ignore(
    db.run(
      "UPDATE recent_home_dirty SET revision = revision + 1 WHERE thread = CAST(? AS INTEGER)",
      [thread],
    ),
  )
  ignore(
    db.run(
      "INSERT INTO recent_home_dirty(thread, revision) SELECT CAST(?1 AS INTEGER), 1 WHERE NOT EXISTS (SELECT 1 FROM recent_home_dirty WHERE thread = CAST(?1 AS INTEGER))",
      [thread],
    ),
  )
}

///|
/// A session's chats journaled for the default part when it became known, went, or moved in or out of the default
/// workspace (`settleRecentHomeSessionStep`), in bounded batches.
fn settle_home_session(db : @sql.Db, limit : Int) -> Int raise {
  write(db, () => {
    guard first(
        db,
        "SELECT session, CAST(revision AS TEXT) AS revision FROM recent_scope_session_dirty WHERE kind = 0 AND ws = '' ORDER BY session LIMIT 1",
        [],
      )
      is Some(pending) else {
      return 0
    }
    let session = get(pending, "session")
    let revision = get(pending, "revision")
    let work = first(
      db,
      "SELECT CAST(revision AS TEXT) AS revision, phase, CAST(after AS TEXT) AS after FROM recent_home_session_work WHERE session = ?",
      [session],
    )
    let (phase, after) = match work {
      Some(k) if get(k, "revision") == revision =>
        (get(k, "phase"), get(k, "after"))
      _ => {
        ignore(
          db.run(
            "INSERT INTO recent_home_session_work(session, revision, phase, after) VALUES (?, CAST(? AS INTEGER), 'home', NULL) ON CONFLICT(session) DO UPDATE SET revision = excluded.revision, phase = 'home', after = NULL",
            [session, revision],
          ),
        )
        (text("home"), Json::null())
      }
    }
    guard session is String(key) && phase is String(p) else {
      fail("recent home session work is malformed")
    }
    let batch = session_threads(db, key, p, after, limit)
    for t in batch.threads {
      mark_home_dirty(db, t)
    }
    if batch.phase == "done" {
      ignore(
        db.run("DELETE FROM recent_home_session_work WHERE session = ?", [
          session,
        ]),
      )
      acknowledge(db, 0, text(""), session, revision)
    } else {
      ignore(
        db.run(
          "UPDATE recent_home_session_work SET phase = ?, after = CAST(? AS INTEGER) WHERE session = ?",
          [text(batch.phase), batch.after, session],
        ),
      )
    }
    batch.visited
  })
}

///|
/// At most `limit` old chats of `table` (`column`) up to the meta's boundary added to `dirty`
/// (`scanRecentHomeChatsStep`, `scanRecentHomeOverlapStep`).
fn scan_into(
  db : @sql.Db,
  meta : String,
  table : String,
  column : String,
  dirty : String,
  limit : Int,
) -> Int raise {
  write(db, () => {
    let m = one(
      db,
      "SELECT CAST(cursor AS TEXT) AS cursor, CAST(through AS TEXT) AS through, scan_done FROM \{meta} WHERE id = 1",
      [],
    )
    let cursor = get(m, "cursor")
    let through = get(m, "through")
    if int(m, "scan_done") == 1 || through is Null {
      return 0
    }
    let found = if cursor is Null {
      db.all(
        "SELECT CAST(\{column} AS TEXT) AS tid FROM \{table} WHERE \{column} <= CAST(?1 AS INTEGER) ORDER BY \{column} LIMIT ?2",
        [through, num(limit)],
      )
    } else {
      db.all(
        "SELECT CAST(\{column} AS TEXT) AS tid FROM \{table} WHERE \{column} > CAST(?1 AS INTEGER) AND \{column} <= CAST(?2 AS INTEGER) ORDER BY \{column} LIMIT ?3",
        [cursor, through, num(limit)],
      )
    }
    for r in found {
      ignore(
        db.run(
          "INSERT INTO \{dirty}(thread, revision) SELECT CAST(?1 AS INTEGER), 1 WHERE NOT EXISTS (SELECT 1 FROM \{dirty} WHERE thread = CAST(?1 AS INTEGER))",
          [get(r, "tid")],
        ),
      )
    }
    let reached = match found.last() {
      Some(r) => get(r, "tid")
      None => cursor
    }
    ignore(
      db.run(
        "UPDATE \{meta} SET cursor = CAST(? AS INTEGER), scan_done = ? WHERE id = 1",
        [reached, num(if found.length() < limit { 1 } else { 0 })],
      ),
    )
    found.length()
  })
}

///|
/// Changed chats accounted for the default part, in bounded member batches (`settleRecentHomeChatStep`): a simple chat
/// costs one unit; the revision keeps a change made during a long scan; row, count, cursor and marker go together.
fn settle_home_chats(db : @sql.Db, limit : Int) -> Int raise {
  write(db, () => {
    let mut visited = 0
    while visited < limit {
      guard first(
          db,
          "SELECT CAST(thread AS TEXT) AS tid, CAST(revision AS TEXT) AS revision FROM recent_home_dirty ORDER BY thread LIMIT 1",
          [],
        )
        is Some(pending) else {
        break
      }
      let thread = get(pending, "tid")
      let revision = get(pending, "revision")
      let after : Ref[Json] = Ref(Json::null())
      let seen = Ref(false)
      match
        first(
          db,
          "SELECT CAST(revision AS TEXT) AS revision, after_session, seen FROM recent_home_work WHERE thread = CAST(? AS INTEGER)",
          [thread],
        ) {
        Some(k) if get(k, "revision") == revision => {
          after.val = get(k, "after_session")
          seen.val = int(k, "seen") == 1
        }
        _ =>
          ignore(
            db.run(
              "INSERT INTO recent_home_work(thread, revision, after_session, seen) VALUES (CAST(? AS INTEGER), CAST(? AS INTEGER), NULL, 0) ON CONFLICT(thread) DO UPDATE SET revision = excluded.revision, after_session = NULL, seen = 0",
              [thread, revision],
            ),
          )
      }
      let used = Ref(0)
      let decided = home_chat(db, thread, after, seen, limit - visited, used)
      visited += if used.val > 1 { used.val } else { 1 }
      guard decided is Some(included) else {
        ignore(
          db.run(
            "UPDATE recent_home_work SET after_session = ?, seen = ? WHERE thread = CAST(? AS INTEGER)",
            [after.val, num(if seen.val { 1 } else { 0 }), thread],
          ),
        )
        break
      }
      let had = exists(
        db,
        "SELECT 1 FROM recent_home_rows WHERE thread = CAST(? AS INTEGER)",
        [thread],
      )
      if included {
        let put = db.run(
          "INSERT INTO recent_home_rows(thread, at, said_at, created_at) SELECT thread, at, said_at, created_at FROM (\{current("?1")}) WHERE true ON CONFLICT(thread) DO UPDATE SET at = excluded.at, said_at = excluded.said_at, created_at = excluded.created_at",
          [thread],
        )
        if put == 0 {
          fail("recent home chat disappeared inside a write transaction")
        }
        if !had {
          ignore(
            db.run(
              "UPDATE recent_home_meta SET total = total + 1 WHERE id = 1",
              [],
            ),
          )
        }
      } else if had {
        ignore(
          db.run(
            "DELETE FROM recent_home_rows WHERE thread = CAST(? AS INTEGER)",
            [thread],
          ),
        )
        ignore(
          db.run("UPDATE recent_home_meta SET total = total - 1 WHERE id = 1", []),
        )
      }
      ignore(
        db.run(
          "DELETE FROM recent_home_work WHERE thread = CAST(? AS INTEGER)",
          [thread],
        ),
      )
      ignore(
        db.run(
          "DELETE FROM recent_home_dirty WHERE thread = CAST(? AS INTEGER) AND revision = CAST(? AS INTEGER)",
          [thread, revision],
        ),
      )
      ignore(
        db.run(
          "DELETE FROM recent_home_order_dirty WHERE thread = CAST(? AS INTEGER)",
          [thread],
        ),
      )
    }
    visited
  })
}

///|
/// The order of at most `limit` default-home chats brought up to date (`settleRecentHomeOrderStep`).
fn settle_home_order(db : @sql.Db, limit : Int) -> Int raise {
  write(db, () => {
    let changed = db.all(
      "SELECT CAST(thread AS TEXT) AS tid FROM recent_home_order_dirty ORDER BY thread LIMIT ?",
      [num(limit)],
    )
    for r in changed {
      let thread = get(r, "tid")
      ignore(
        db.run(
          "UPDATE recent_home_rows SET at = c.at, said_at = c.said_at, created_at = c.created_at FROM (\{current("?1")}) c WHERE recent_home_rows.thread = c.thread AND (recent_home_rows.at IS NOT c.at OR recent_home_rows.said_at IS NOT c.said_at OR recent_home_rows.created_at IS NOT c.created_at)",
          [thread],
        ),
      )
      ignore(
        db.run(
          "DELETE FROM recent_home_order_dirty WHERE thread = CAST(? AS INTEGER)",
          [thread],
        ),
      )
    }
    changed.length()
  })
}

///|
/// Default chats' workspace intersections brought up to date in bounded batches (`settleRecentHomeOverlapStep`);
/// a chat with no workspaces costs one unit.
fn settle_overlap(db : @sql.Db, limit : Int) -> Int raise {
  write(db, () => {
    let mut visited = 0
    while visited < limit {
      guard first(
          db,
          "SELECT CAST(thread AS TEXT) AS tid, CAST(revision AS TEXT) AS revision FROM recent_home_overlap_dirty ORDER BY thread LIMIT 1",
          [],
        )
        is Some(pending) else {
        break
      }
      let thread = get(pending, "tid")
      let revision = get(pending, "revision")
      let after = match
        first(
          db,
          "SELECT CAST(revision AS TEXT) AS revision, after_ws FROM recent_home_overlap_work WHERE thread = CAST(? AS INTEGER)",
          [thread],
        ) {
        Some(k) if get(k, "revision") == revision => get(k, "after_ws")
        _ => {
          ignore(
            db.run(
              "INSERT INTO recent_home_overlap_work(thread, revision, after_ws) VALUES (CAST(? AS INTEGER), CAST(? AS INTEGER), NULL) ON CONFLICT(thread) DO UPDATE SET revision = excluded.revision, after_ws = NULL",
              [thread, revision],
            ),
          )
          Json::null()
        }
      }
      let included = exists(
        db,
        "SELECT 1 FROM recent_home_rows WHERE thread = CAST(? AS INTEGER)",
        [thread],
      )
      let table = if included {
        "recent_scope_rows INDEXED BY recent_scope_rows_thread"
      } else {
        "recent_home_overlap_rows INDEXED BY recent_home_overlap_by_thread"
      }
      let remaining = limit - visited
      let found = if after is Null {
        db.all(
          "SELECT ws FROM \{table} WHERE thread = CAST(?1 AS INTEGER) ORDER BY ws LIMIT ?2",
          [thread, num(remaining)],
        )
      } else {
        db.all(
          "SELECT ws FROM \{table} WHERE thread = CAST(?1 AS INTEGER) AND ws > ?2 ORDER BY ws LIMIT ?3",
          [thread, after, num(remaining)],
        )
      }
      for r in found {
        if included {
          ignore(
            db.run(
              "INSERT INTO recent_home_overlap_rows(ws, thread) SELECT ?1, CAST(?2 AS INTEGER) WHERE NOT EXISTS (SELECT 1 FROM recent_home_overlap_rows WHERE ws = ?1 AND thread = CAST(?2 AS INTEGER))",
              [get(r, "ws"), thread],
            ),
          )
        } else {
          ignore(
            db.run(
              "DELETE FROM recent_home_overlap_rows WHERE ws = ? AND thread = CAST(? AS INTEGER)",
              [get(r, "ws"), thread],
            ),
          )
        }
      }
      visited += if found.length() > 1 { found.length() } else { 1 }
      if found.length() == remaining {
        ignore(
          db.run(
            "UPDATE recent_home_overlap_work SET after_ws = ? WHERE thread = CAST(? AS INTEGER)",
            [get(found[found.length() - 1], "ws"), thread],
          ),
        )
        break
      }
      ignore(
        db.run(
          "DELETE FROM recent_home_overlap_work WHERE thread = CAST(? AS INTEGER)",
          [thread],
        ),
      )
      ignore(
        db.run(
          "DELETE FROM recent_home_overlap_dirty WHERE thread = CAST(? AS INTEGER) AND revision = CAST(? AS INTEGER)",
          [thread, revision],
        ),
      )
    }
    visited
  })
}

///|
/// The default part's count can be read (`preparedDefaultHomeTotal` gives one).
fn default_home_ready(db : @sql.Db) -> Bool raise {
  installed(db, "home") &&
  installed(db, "scope") &&
  int(
    one(db, "SELECT scan_done FROM recent_home_meta WHERE id = 1", []),
    "scan_done",
  ) ==
  1 &&
  !exists(db, "SELECT 1 FROM recent_home_dirty LIMIT 1", []) &&
  !exists(db, "SELECT 1 FROM recent_home_order_dirty LIMIT 1", []) &&
  !exists(
    db,
    "SELECT 1 FROM recent_scope_session_dirty WHERE kind = 0 AND ws = '' LIMIT 1",
    [],
  )
}

///|
/// Home's page can be read (`readPreparedRecentHome` gives one): its default part, the workspace and their overlap.
fn home_ready(db : @sql.Db, home : String) -> Bool raise {
  snapshot(db, "recent_home_union", () => {
    installed(db, "overlap") &&
    int(
      one(db, "SELECT scan_done FROM recent_home_overlap_meta WHERE id = 1", []),
      "scan_done",
    ) ==
    1 &&
    !exists(db, "SELECT 1 FROM recent_home_overlap_dirty LIMIT 1", []) &&
    default_home_ready(db) &&
    workspace_total_ready(db, home)
  })
}
