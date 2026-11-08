// A named workspace's rows (chat-list-scope-source.ts, -rows.ts, -build.ts, -order.ts, -visibility.ts): its sessions'
// chats found in bounded scans, then the journaled session, membership, order and visibility changes settled.

// Sources (chat-list-scope-source.ts).

///|
/// A session's chats: its home chats (`phase` "home"), then the chats it is a member of without a home ("members").
struct Threads {
  threads : Array[Json]
  members : Array[Json]
  visited : Int
  phase : String
  after : Json
}

///|
/// One batch of `session`'s chats from `phase`/`after` (`recentScopeSessionThreadsStep`). The home check comes after
/// limiting the memberships, so a long run of chats with a home cannot make one batch unbounded.
fn session_threads(
  db : @sql.Db,
  session : String,
  phase : String,
  after : Json,
  limit : Int,
) -> Threads raise {
  let s = text(session)
  let lim = num(limit)
  match phase {
    "done" => { threads: [], members: [], visited: 0, phase, after, }
    "home" => {
      let found = if after is Null {
        db.all(
          "SELECT CAST(id AS TEXT) AS tid FROM threads INDEXED BY threads_home WHERE home = ?1 ORDER BY id LIMIT ?2",
          [s, lim],
        )
      } else {
        db.all(
          "SELECT CAST(id AS TEXT) AS tid FROM threads INDEXED BY threads_home WHERE home = ?1 AND id > CAST(?2 AS INTEGER) ORDER BY id LIMIT ?3",
          [s, after, lim],
        )
      }
      let threads = found.map(r => get(r, "tid"))
      if found.length() == limit {
        {
          threads,
          members: [],
          visited: found.length(),
          phase: "home",
          after: threads[threads.length() - 1],
        }
      } else {
        {
          threads,
          members: [],
          visited: found.length(),
          phase: "members",
          after: Json::null(),
        }
      }
    }
    _ => {
      let found = if after is Null {
        db.all(
          "SELECT CAST(rowid AS TEXT) AS r, CAST(thread AS TEXT) AS tid FROM thread_sessions INDEXED BY thread_sessions_session WHERE session = ?1 ORDER BY rowid LIMIT ?2",
          [s, lim],
        )
      } else {
        db.all(
          "SELECT CAST(rowid AS TEXT) AS r, CAST(thread AS TEXT) AS tid FROM thread_sessions INDEXED BY thread_sessions_session WHERE session = ?1 AND rowid > CAST(?2 AS INTEGER) ORDER BY rowid LIMIT ?3",
          [s, after, lim],
        )
      }
      let members = found.map(r => get(r, "tid"))
      let threads = []
      for m in members {
        if exists(
            db,
            "SELECT 1 FROM threads WHERE id = CAST(? AS INTEGER) AND home IS NULL",
            [m],
          ) {
          threads.push(m)
        }
      }
      if found.length() == limit {
        {
          threads,
          members,
          visited: found.length(),
          phase: "members",
          after: get(found[found.length() - 1], "r"),
        }
      } else {
        {
          threads,
          members,
          visited: found.length(),
          phase: "done",
          after: Json::null(),
        }
      }
    }
  }
}

///|
/// One connection's sessions in workspace `ws` (at most `limit`, rowids up to `through`) after `connect`/`after`, and
/// the cursor then (`recentScopeSessionsStep`): a connection with none advanced in a step of its own.
fn workspace_sessions(
  db : @sql.Db,
  ws : String,
  connect : Json,
  after : Json,
  limit : Int,
  through : Json,
) -> (Array[Map[String, Json]], Json, Json, Bool) raise {
  let connect = if connect is Null {
    match
      first(
        db,
        "SELECT connect FROM sessions INDEXED BY sessions_by_connect ORDER BY connect LIMIT 1",
        [],
      ) {
      Some(r) => get(r, "connect")
      None => Json::null()
    }
  } else {
    connect
  }
  if connect is Null {
    return ([], Json::null(), Json::null(), true)
  }
  let sessions = if after is Null {
    db.all(
      "SELECT CAST(rowid AS TEXT) AS r, key FROM sessions INDEXED BY sessions_by_connect WHERE connect = ?1 AND ws = ?2 AND rowid <= CAST(?3 AS INTEGER) ORDER BY rowid LIMIT ?4",
      [connect, text(ws), through, num(limit)],
    )
  } else {
    db.all(
      "SELECT CAST(rowid AS TEXT) AS r, key FROM sessions INDEXED BY sessions_by_connect WHERE connect = ?1 AND ws = ?2 AND rowid > CAST(?3 AS INTEGER) AND rowid <= CAST(?4 AS INTEGER) ORDER BY rowid LIMIT ?5",
      [connect, text(ws), after, through, num(limit)],
    )
  }
  if sessions.length() == limit {
    return (sessions, connect, get(sessions[sessions.length() - 1], "r"), false)
  }
  let next = match
    first(
      db,
      "SELECT connect FROM sessions INDEXED BY sessions_by_connect WHERE connect > ? ORDER BY connect LIMIT 1",
      [connect],
    ) {
    Some(r) => get(r, "connect")
    None => Json::null()
  }
  (sessions, next, Json::null(), next is Null)
}

// Contributions (chat-list-scope-rows.ts).

///|
fn[T] contribution(db : @sql.Db, f : () -> T raise) -> T raise {
  db.exec("SAVEPOINT recent_scope_contribution")
  errdefer (db.exec(
    "ROLLBACK TO recent_scope_contribution; RELEASE recent_scope_contribution",
  ) catch {
    _ => ()
  })
  let result = f()
  db.exec("RELEASE recent_scope_contribution")
  result
}

///|
fn tracked(db : @sql.Db, ws : Json) -> Bool raise {
  exists(db, "SELECT 1 FROM recent_scope_tracked WHERE kind = 1 AND ws = ?", [
    ws,
  ])
}

///|
/// One session's contribution added or refreshed (`putRecentScopeSource`); a chat counts once in a workspace.
fn put_source(
  db : @sql.Db,
  ws : Json,
  thread : Json,
  session : Json,
) -> Unit raise {
  contribution(db, () => {
    if !tracked(db, ws) {
      fail("recent scope is not tracked")
    }
    if !chat_exists(db, thread) {
      return
    }
    let had = exists(
      db,
      "SELECT 1 FROM recent_scope_rows WHERE ws = ? AND thread = CAST(? AS INTEGER)",
      [ws, thread],
    )
    ignore(
      db.run(
        "INSERT INTO recent_scope_sources(ws, thread, session) SELECT ?1, CAST(?2 AS INTEGER), ?3 WHERE NOT EXISTS (SELECT 1 FROM recent_scope_sources WHERE ws = ?1 AND thread = CAST(?2 AS INTEGER) AND session = ?3)",
        [ws, thread, session],
      ),
    )
    ignore(
      db.run(
        "INSERT INTO recent_scope_rows(ws, thread, at, said_at, created_at) SELECT ?1, thread, at, said_at, created_at FROM (\{current("?2")}) WHERE true ON CONFLICT(ws, thread) DO UPDATE SET at = excluded.at, said_at = excluded.said_at, created_at = excluded.created_at WHERE at IS NOT excluded.at OR said_at IS NOT excluded.said_at OR created_at IS NOT excluded.created_at",
        [ws, thread],
      ),
    )
    if !had {
      ignore(
        db.run(
          "UPDATE recent_scope_tracked SET total = total + 1 WHERE kind = 1 AND ws = ?",
          [ws],
        ),
      )
    }
  })
}

///|
/// One source removed; the chat stays until its last source in the workspace is gone (`removeRecentScopeSource`).
fn remove_source(
  db : @sql.Db,
  ws : Json,
  thread : Json,
  session : Json,
) -> Unit raise {
  contribution(db, () => {
    let removed = db.run(
      "DELETE FROM recent_scope_sources WHERE ws = ? AND thread = CAST(? AS INTEGER) AND session = ?",
      [ws, thread, session],
    )
    if removed == 0 ||
      exists(
        db,
        "SELECT 1 FROM recent_scope_sources WHERE ws = ? AND thread = CAST(? AS INTEGER) LIMIT 1",
        [ws, thread],
      ) {
      return
    }
    if db.run(
        "DELETE FROM recent_scope_rows WHERE ws = ? AND thread = CAST(? AS INTEGER)",
        [ws, thread],
      ) !=
      0 {
      ignore(
        db.run(
          "UPDATE recent_scope_tracked SET total = total - 1 WHERE kind = 1 AND ws = ?",
          [ws],
        ),
      )
    }
  })
}

///|
fn put_candidate(
  db : @sql.Db,
  ws : Json,
  thread : Json,
  session : Json,
) -> Unit raise {
  ignore(
    db.run(
      "INSERT INTO recent_scope_candidates(ws, thread, session) SELECT ?1, CAST(?2 AS INTEGER), ?3 WHERE NOT EXISTS (SELECT 1 FROM recent_scope_candidates WHERE ws = ?1 AND thread = CAST(?2 AS INTEGER) AND session = ?3)",
      [ws, thread, session],
    ),
  )
}

///|
fn remove_candidate_row(
  db : @sql.Db,
  ws : Json,
  thread : Json,
  session : Json,
) -> Unit raise {
  ignore(
    db.run(
      "DELETE FROM recent_scope_candidates WHERE ws = ? AND thread = CAST(? AS INTEGER) AND session = ?",
      [ws, thread, session],
    ),
  )
}

///|
let visibility_pending : String = "SELECT COUNT(*) AS n, MAX(d.ambiguous) AS ambiguous, MAX(COALESCE(d.home_ws = ?1, 0) OR EXISTS (SELECT 1 FROM recent_scope_rows r WHERE r.ws = ?1 AND r.thread = d.thread)) AS affects FROM (SELECT thread, home_ws, ambiguous FROM recent_scope_visibility_dirty ORDER BY thread LIMIT 65) d"

///|
let visibility_ambiguous : String = "SELECT MAX(EXISTS (SELECT 1 FROM recent_scope_candidates c WHERE c.ws = ?1 AND c.thread = d.thread)) AS affects FROM (SELECT thread, ambiguous FROM recent_scope_visibility_dirty ORDER BY thread LIMIT 65) d WHERE d.ambiguous"

///|
let visibility_rows_small : String = "SELECT COUNT(*) AS n, MAX(EXISTS (SELECT 1 FROM recent_scope_visibility_dirty d WHERE d.thread = r.thread)) AS affects FROM (SELECT thread FROM recent_scope_rows WHERE ws = ?1 ORDER BY thread LIMIT 65) r"

///|
let visibility_members_small : String = "SELECT COUNT(*) AS n, MAX(EXISTS (SELECT 1 FROM recent_scope_visibility_dirty d WHERE d.thread = c.thread AND d.ambiguous = 1)) AS affects FROM (SELECT thread FROM recent_scope_candidates WHERE ws = ?1 ORDER BY thread, session LIMIT 65) c"

///|
let order_pending : String = "SELECT COUNT(*) AS n, MAX(EXISTS (SELECT 1 FROM recent_scope_rows r WHERE r.ws = ?1 AND r.thread = d.thread)) AS affects FROM (SELECT thread FROM recent_scope_order_dispatch ORDER BY thread LIMIT 65) d"

///|
let order_small : String = "SELECT COUNT(*) AS n, MAX(EXISTS (SELECT 1 FROM recent_scope_order_dispatch d WHERE d.thread = r.thread)) AS affects FROM (SELECT thread FROM recent_scope_rows WHERE ws = ?1 ORDER BY thread LIMIT 65) r"

///|
/// The workspace's count can be read (`preparedRecentWorkspaceTotal` gives one): it is complete and no pending
/// change can touch it.
fn workspace_total_ready(db : @sql.Db, ws : String) -> Bool raise {
  if !installed(db, "scope") {
    return false
  }
  let w = [text(ws)]
  guard first(
      db, "SELECT complete, scan_done, scan_session FROM recent_scope_tracked WHERE kind = 1 AND ws = ?",
      w,
    )
    is Some(meta) else {
    return false
  }
  if int(meta, "complete") != 1 ||
    exists(
      db, "SELECT 1 FROM recent_scope_session_dirty WHERE kind = 1 AND ws = ? LIMIT 1",
      w,
    ) ||
    exists(
      db, "SELECT 1 FROM recent_scope_member_dirty WHERE ws = ? LIMIT 1", w,
    ) ||
    exists(db, "SELECT 1 FROM recent_scope_order_dirty WHERE ws = ? LIMIT 1", w) {
    return false
  }
  let scanned = int(meta, "scan_done") == 1 && get(meta, "scan_session") is Null
  let visibility = one(db, visibility_pending, w)
  if int(visibility, "affects") == 1 {
    return false
  }
  if int(visibility, "n") > 64 {
    if !scanned ||
      exists(
        db, "SELECT 1 FROM recent_scope_visibility_dirty WHERE home_ws = ? LIMIT 1",
        w,
      ) {
      return false
    }
    for sql in [visibility_rows_small, visibility_members_small] {
      let small = one(db, sql, w)
      if int(small, "n") > 64 || int(small, "affects") == 1 {
        return false
      }
    }
  } else if int(visibility, "ambiguous") == 1 {
    if !scanned || int(one(db, visibility_ambiguous, w), "affects") == 1 {
      return false
    }
  }
  let pending = one(db, order_pending, w)
  if int(pending, "affects") == 1 {
    return false
  }
  if int(pending, "n") > 64 {
    let small = one(db, order_small, w)
    if int(small, "n") > 64 || int(small, "affects") == 1 {
      return false
    }
  }
  true
}

///|
fn workspace_ready(db : @sql.Db, ws : String) -> Bool raise {
  snapshot(db, "recent_scope_page", () => workspace_total_ready(db, ws))
}

// The initial scan and the journals settled (chat-list-scope-build.ts).

///|
/// At most `limit` source units of the workspace's initial scan, its cursor with them (`scanRecentWorkspaceStep`): a
/// session's chats, then the next session, by connection, or by rowid once connections keep arriving.
fn scan_workspace(db : @sql.Db, ws : String, limit : Int) -> Int raise {
  let w = text(ws)
  write(db, () => {
    guard first(
        db,
        "SELECT scan_connect, CAST(scan_after AS TEXT) AS scan_after, scan_done, scan_session, scan_phase, CAST(scan_thread_after AS TEXT) AS scan_thread_after, CAST(scan_high AS TEXT) AS scan_high, scan_connections, scan_rowids FROM recent_scope_tracked WHERE kind = 1 AND ws = ?",
        [w],
      )
      is Some(row) else {
      fail("recent scope is not tracked")
    }
    let mut connect = get(row, "scan_connect")
    let mut after = get(row, "scan_after")
    let mut done = int(row, "scan_done")
    let mut session = get(row, "scan_session")
    let mut phase = get(row, "scan_phase")
    let mut thread_after = get(row, "scan_thread_after")
    let high = get(row, "scan_high")
    let mut connections = int(row, "scan_connections")
    let mut by_rowid = int(row, "scan_rowids")
    let mut visited = 0
    while visited < limit {
      if session is String(key) {
        let from = match phase {
          String(p) => p
          _ => "home"
        }
        let batch = session_threads(
          db,
          key,
          from,
          thread_after,
          limit - visited,
        )
        for m in batch.members {
          put_candidate(db, w, m, session)
        }
        for t in batch.threads {
          put_source(db, w, t, session)
        }
        visited += if batch.visited > 1 { batch.visited } else { 1 }
        if batch.phase == "done" {
          session = Json::null()
          phase = Json::null()
          thread_after = Json::null()
        } else {
          phase = text(batch.phase)
          thread_after = batch.after
        }
      } else if done == 1 {
        break
      } else {
        if high is Null {
          fail("recent workspace scan has no starting boundary")
        }
        if by_rowid == 1 {
          let found = if after is Null {
            first(
              db,
              "SELECT CAST(rowid AS TEXT) AS r, key, ws FROM sessions WHERE rowid <= CAST(?1 AS INTEGER) ORDER BY rowid LIMIT 1",
              [high],
            )
          } else {
            first(
              db,
              "SELECT CAST(rowid AS TEXT) AS r, key, ws FROM sessions WHERE rowid > CAST(?1 AS INTEGER) AND rowid <= CAST(?2 AS INTEGER) ORDER BY rowid LIMIT 1",
              [after, high],
            )
          }
          match found {
            None => {
              done = 1
              session = Json::null()
            }
            Some(s) => {
              done = 0
              after = get(s, "r")
              session = if get(s, "ws") == w {
                get(s, "key")
              } else {
                Json::null()
              }
            }
          }
        } else {
          let previous = connect
          let (sessions, next_connect, next_after, finished) = workspace_sessions(
            db, ws, connect, after, 1, high,
          )
          connect = next_connect
          after = next_after
          done = if finished { 1 } else { 0 }
          session = match sessions {
            [s, ..] => get(s, "key")
            _ => Json::null()
          }
          if connect != previous {
            connections += 1
          }
          if done == 0 && connections >= 64 {
            by_rowid = 1
            after = Json::null()
          }
        }
        phase = if session is Null { Json::null() } else { text("home") }
        thread_after = Json::null()
        visited += 1
      }
    }
    if visited != 0 {
      ignore(
        db.run(
          "UPDATE recent_scope_tracked SET scan_connect = ?, scan_after = CAST(? AS INTEGER), scan_done = ?, scan_session = ?, scan_phase = ?, scan_thread_after = CAST(? AS INTEGER), scan_connections = ?, scan_rowids = ? WHERE kind = 1 AND ws = ?",
          [
            connect,
            after,
            num(done),
            session,
            phase,
            thread_after,
            num(connections),
            num(by_rowid),
            w,
          ],
        ),
      )
    }
    visited
  })
}

///|
fn scan_finished(db : @sql.Db, ws : Json) -> Unit raise {
  guard first(
      db,
      "SELECT scan_done, scan_session FROM recent_scope_tracked WHERE kind = 1 AND ws = ?",
      [ws],
    )
    is Some(p) else {
    fail("recent scope is not tracked")
  }
  if int(p, "scan_done") != 1 || !(get(p, "scan_session") is Null) {
    fail("recent scope source scan is unfinished")
  }
}

///|
/// One batch of a changed session's sources for the workspace, removed then found again
/// (`settleRecentWorkspaceSessionStep`); its revision acknowledged when it is through.
fn settle_workspace_session(
  db : @sql.Db,
  ws : String,
  limit : Int,
) -> Int raise {
  let w = text(ws)
  let lim = num(limit)
  write(db, () => {
    scan_finished(db, w)
    guard first(
        db,
        "SELECT session, CAST(revision AS TEXT) AS revision FROM recent_scope_session_dirty WHERE kind = 1 AND ws = ? ORDER BY session LIMIT 1",
        [w],
      )
      is Some(pending) else {
      return 0
    }
    let session = get(pending, "session")
    let revision = get(pending, "revision")
    let work = first(
      db,
      "SELECT CAST(revision AS TEXT) AS revision, phase, CAST(after AS TEXT) AS after FROM recent_scope_session_work WHERE ws = ? AND session = ?",
      [w, session],
    )
    let (phase0, after0) = match work {
      Some(k) if get(k, "revision") == revision =>
        (get(k, "phase"), get(k, "after"))
      _ => {
        ignore(
          db.run(
            "INSERT INTO recent_scope_session_work(ws, session, revision, phase, after) VALUES (?, ?, CAST(? AS INTEGER), 'remove', NULL) ON CONFLICT(ws, session) DO UPDATE SET revision = excluded.revision, phase = 'remove', after = NULL",
            [w, session, revision],
          ),
        )
        (text("remove"), Json::null())
      }
    }
    let mut phase = phase0
    let mut after = after0
    for
      cleanup in [
        (
          "remove", "candidates", "SELECT CAST(thread AS TEXT) AS tid FROM recent_scope_sources INDEXED BY recent_scope_sources_session WHERE ws = ?1 AND session = ?2 ORDER BY thread LIMIT ?3",
          "SELECT CAST(thread AS TEXT) AS tid FROM recent_scope_sources INDEXED BY recent_scope_sources_session WHERE ws = ?1 AND session = ?2 AND thread > CAST(?3 AS INTEGER) ORDER BY thread LIMIT ?4",
        ),
        (
          "candidates", "home", "SELECT CAST(thread AS TEXT) AS tid FROM recent_scope_candidates INDEXED BY recent_scope_candidates_session WHERE ws = ?1 AND session = ?2 ORDER BY thread LIMIT ?3",
          "SELECT CAST(thread AS TEXT) AS tid FROM recent_scope_candidates INDEXED BY recent_scope_candidates_session WHERE ws = ?1 AND session = ?2 AND thread > CAST(?3 AS INTEGER) ORDER BY thread LIMIT ?4",
        ),
      ] {
      let (name, next, from_start, from_after) = cleanup
      if phase != text(name) {
        continue
      }
      let found = if after is Null {
        db.all(from_start, [w, session, lim])
      } else {
        db.all(from_after, [w, session, after, lim])
      }
      for r in found {
        if name == "remove" {
          remove_source(db, w, get(r, "tid"), session)
        } else {
          remove_candidate_row(db, w, get(r, "tid"), session)
        }
      }
      if found.length() == limit {
        ignore(
          db.run(
            "UPDATE recent_scope_session_work SET after = CAST(? AS INTEGER) WHERE ws = ? AND session = ?",
            [get(found[found.length() - 1], "tid"), w, session],
          ),
        )
      } else {
        ignore(
          db.run(
            "UPDATE recent_scope_session_work SET phase = ?, after = NULL WHERE ws = ? AND session = ?",
            [text(next), w, session],
          ),
        )
      }
      if found.length() != 0 {
        return found.length()
      }
      phase = text(next)
      after = Json::null()
    }
    let now = first(db, "SELECT ws FROM sessions WHERE key = ?", [session])
    if !(now is Some(s) && get(s, "ws") == w) {
      ignore(
        db.run(
          "DELETE FROM recent_scope_session_work WHERE ws = ? AND session = ?",
          [w, session],
        ),
      )
      acknowledge(db, 1, w, session, revision)
      return 0
    }
    guard phase is String(p) &&
      (p == "home" || p == "members") &&
      session is String(key) else {
      fail("recent workspace session cleanup is unfinished")
    }
    let batch = session_threads(db, key, p, after, limit)
    for m in batch.members {
      put_candidate(db, w, m, session)
    }
    for t in batch.threads {
      put_source(db, w, t, session)
    }
    if batch.phase == "done" {
      ignore(
        db.run(
          "DELETE FROM recent_scope_session_work WHERE ws = ? AND session = ?",
          [w, session],
        ),
      )
      acknowledge(db, 1, w, session, revision)
    } else {
      ignore(
        db.run(
          "UPDATE recent_scope_session_work SET phase = ?, after = CAST(? AS INTEGER) WHERE ws = ? AND session = ?",
          [text(batch.phase), batch.after, w, session],
        ),
      )
    }
    batch.visited
  })
}

///|
/// Only the revision accounted is cleared: a session changed again between batches stays pending.
fn acknowledge(
  db : @sql.Db,
  kind : Int,
  ws : Json,
  session : Json,
  revision : Json,
) -> Unit raise {
  ignore(
    db.run(
      "DELETE FROM recent_scope_session_dirty WHERE kind = ? AND ws = ? AND session = ? AND revision = CAST(? AS INTEGER)",
      [num(kind), ws, session, revision],
    ),
  )
}

///|
/// Changed memberships reconciled, at most `limit` (`settleRecentWorkspaceMemberStep`).
fn settle_workspace_members(
  db : @sql.Db,
  ws : String,
  limit : Int,
) -> Int raise {
  let w = text(ws)
  write(db, () => {
    scan_finished(db, w)
    let changed = db.all(
      "SELECT CAST(thread AS TEXT) AS tid, session, CAST(revision AS TEXT) AS revision FROM recent_scope_member_dirty WHERE ws = ? ORDER BY thread, session LIMIT ?",
      [w, num(limit)],
    )
    for row in changed {
      let thread = get(row, "tid")
      let session = get(row, "session")
      if exists(
          db,
          "SELECT 1 FROM sessions s JOIN thread_sessions m ON m.session = s.key WHERE m.thread = CAST(?1 AS INTEGER) AND s.key = ?2 AND s.ws = ?3",
          [thread, session, w],
        ) {
        put_candidate(db, w, thread, session)
      } else {
        remove_candidate_row(db, w, thread, session)
      }
      if exists(
          db,
          "SELECT 1 FROM threads t JOIN sessions s ON s.key = ?2 WHERE t.id = CAST(?1 AS INTEGER) AND s.ws = ?3 AND (t.home = s.key OR (t.home IS NULL AND EXISTS (SELECT 1 FROM thread_sessions m WHERE m.thread = t.id AND m.session = s.key)))",
          [thread, session, w],
        ) {
        put_source(db, w, thread, session)
      } else {
        remove_source(db, w, thread, session)
      }
      ignore(
        db.run(
          "DELETE FROM recent_scope_member_dirty WHERE ws = ? AND thread = CAST(? AS INTEGER) AND session = ? AND revision = CAST(? AS INTEGER)",
          [w, thread, session, get(row, "revision")],
        ),
      )
    }
    changed.length()
  })
}

// Order changes (chat-list-scope-order.ts) and visibility (chat-list-scope-visibility.ts).

///|
/// The next chat of a finite round over `table`'s pending chats (its turn in `turn`), the turn moved to it; None when
/// nothing is pending. `columns`: what else of the pending row is read.
fn next_in_turn(
  db : @sql.Db,
  table : String,
  turn : String,
  columns : String,
) -> Map[String, Json]? raise {
  let progress = one(
    db,
    "SELECT CAST(after_thread AS TEXT) AS after_thread, CAST(through_thread AS TEXT) AS through_thread FROM \{turn} WHERE id = 1",
    [],
  )
  let pick = "SELECT CAST(thread AS TEXT) AS tid, \{columns} FROM \{table}"
  let mut through = get(progress, "through_thread")
  let after = get(progress, "after_thread")
  let mut pending = if through is Null {
    None
  } else if after is Null {
    first(
      db,
      "\{pick} WHERE thread <= CAST(? AS INTEGER) ORDER BY thread LIMIT 1",
      [through],
    )
  } else {
    first(
      db,
      "\{pick} WHERE thread > CAST(? AS INTEGER) AND thread <= CAST(? AS INTEGER) ORDER BY thread LIMIT 1",
      [after, through],
    )
  }
  if pending is None {
    through = get(
      one(db, "SELECT CAST(MAX(thread) AS TEXT) AS tid FROM \{table}", []),
      "tid",
    )
    if through is Null {
      return None
    }
    pending = first(
      db,
      "\{pick} WHERE thread <= CAST(? AS INTEGER) ORDER BY thread LIMIT 1",
      [through],
    )
  }
  guard pending is Some(p) else {
    fail("recent scope turn lost its pending chat")
  }
  ignore(
    db.run(
      "UPDATE \{turn} SET after_thread = CAST(? AS INTEGER), through_thread = CAST(? AS INTEGER) WHERE id = 1",
      [get(p, "tid"), through],
    ),
  )
  Some(p)
}

///|
/// One highly shared chat's order change moved to at most `limit` of its workspaces (`dispatchRecentScopeOrderStep`).
fn dispatch_order(db : @sql.Db, limit : Int) -> Int raise {
  write(db, () => {
    guard next_in_turn(
        db, "recent_scope_order_dispatch", "recent_scope_order_turn", "after_ws",
      )
      is Some(pending) else {
      return 0
    }
    let thread = get(pending, "tid")
    let after = get(pending, "after_ws")
    let found = if after is Null {
      db.all(
        "SELECT ws FROM recent_scope_rows INDEXED BY recent_scope_rows_thread WHERE thread = CAST(?1 AS INTEGER) ORDER BY ws LIMIT ?2",
        [thread, num(limit)],
      )
    } else {
      db.all(
        "SELECT ws FROM recent_scope_rows INDEXED BY recent_scope_rows_thread WHERE thread = CAST(?1 AS INTEGER) AND ws > ?2 ORDER BY ws LIMIT ?3",
        [thread, after, num(limit)],
      )
    }
    for r in found {
      ignore(
        db.run(
          "INSERT INTO recent_scope_order_dirty(ws, thread) SELECT ?1, CAST(?2 AS INTEGER) WHERE NOT EXISTS (SELECT 1 FROM recent_scope_order_dirty WHERE ws = ?1 AND thread = CAST(?2 AS INTEGER))",
          [get(r, "ws"), thread],
        ),
      )
    }
    if found.length() == limit {
      ignore(
        db.run(
          "UPDATE recent_scope_order_dispatch SET after_ws = ? WHERE thread = CAST(? AS INTEGER)",
          [get(found[found.length() - 1], "ws"), thread],
        ),
      )
    } else {
      ignore(
        db.run(
          "DELETE FROM recent_scope_order_dispatch WHERE thread = CAST(? AS INTEGER)",
          [thread],
        ),
      )
    }
    found.length()
  })
}

///|
/// One dirty chat's order in the workspace recalculated, or a gone chat's sources removed in batches
/// (`settleRecentWorkspaceOrderStep`); a chat still being dispatched waits.
fn settle_workspace_order(
  db : @sql.Db,
  ws : String,
  limit : Int,
) -> Int raise {
  let w = text(ws)
  write(db, () => {
    if !tracked(db, w) {
      fail("recent scope is not tracked")
    }
    guard first(
        db,
        "SELECT CAST(thread AS TEXT) AS tid FROM recent_scope_order_dirty WHERE ws = ? ORDER BY thread LIMIT 1",
        [w],
      )
      is Some(pending) else {
      return 0
    }
    let thread = get(pending, "tid")
    if exists(
        db,
        "SELECT 1 FROM recent_scope_order_dispatch WHERE thread = CAST(? AS INTEGER)",
        [thread],
      ) {
      return 0
    }
    let mut visited = 1
    if chat_exists(db, thread) {
      ignore(
        db.run(
          "UPDATE recent_scope_rows SET at = c.at, said_at = c.said_at, created_at = c.created_at FROM (\{current("?2")}) c WHERE recent_scope_rows.ws = ?1 AND recent_scope_rows.thread = c.thread AND (recent_scope_rows.at IS NOT c.at OR recent_scope_rows.said_at IS NOT c.said_at OR recent_scope_rows.created_at IS NOT c.created_at)",
          [w, thread],
        ),
      )
    } else {
      let sources = db.all(
        "SELECT session FROM recent_scope_sources WHERE ws = ? AND thread = CAST(? AS INTEGER) ORDER BY session LIMIT ?",
        [w, thread, num(limit)],
      )
      for s in sources {
        remove_source(db, w, thread, get(s, "session"))
      }
      visited = if sources.length() > 1 { sources.length() } else { 1 }
      if sources.length() == limit {
        return visited
      }
      // (a row without sources: the chat went while its initial scan ran)
      if db.run(
          "DELETE FROM recent_scope_rows WHERE ws = ? AND thread = CAST(? AS INTEGER)",
          [w, thread],
        ) !=
        0 {
        ignore(
          db.run(
            "UPDATE recent_scope_tracked SET total = total - 1 WHERE kind = 1 AND ws = ?",
            [w],
          ),
        )
      }
    }
    ignore(
      db.run(
        "DELETE FROM recent_scope_order_dirty WHERE ws = ? AND thread = CAST(? AS INTEGER)",
        [w, thread],
      ),
    )
    visited
  })
}

///|
/// One batch of a chat's workspace contributions rebuilt after its home changed (`settleRecentScopeVisibilityStep`):
/// its old sources removed, then the new ones added; a home changed again between batches starts the chat over.
fn settle_visibility(db : @sql.Db, limit : Int) -> Int raise {
  let lim = num(limit)
  write(db, () => {
    guard next_in_turn(
        db, "recent_scope_visibility_dirty", "recent_scope_visibility_turn", "CAST(revision AS TEXT) AS revision",
      )
      is Some(pending) else {
      return 0
    }
    let thread = get(pending, "tid")
    let revision = get(pending, "revision")
    // (the hint refreshed before old contributions go, so a reader of a new home cannot take this for a finished page)
    ignore(
      db.run(
        "UPDATE recent_scope_visibility_dirty SET home_ws = (SELECT s.ws FROM threads t JOIN sessions s ON s.key = t.home WHERE t.id = CAST(?1 AS INTEGER)), ambiguous = EXISTS (SELECT 1 FROM threads t WHERE t.id = CAST(?1 AS INTEGER) AND t.home IS NULL AND EXISTS (SELECT 1 FROM thread_sessions m WHERE m.thread = t.id LIMIT 1)) WHERE thread = CAST(?1 AS INTEGER)",
        [thread],
      ),
    )
    let work = first(
      db,
      "SELECT CAST(revision AS TEXT) AS revision, phase, after_ws, after_session FROM recent_scope_visibility_work WHERE thread = CAST(? AS INTEGER)",
      [thread],
    )
    let (phase, after_ws, after_session) = match work {
      Some(k) if get(k, "revision") == revision =>
        (get(k, "phase"), get(k, "after_ws"), get(k, "after_session"))
      _ => {
        ignore(
          db.run(
            "INSERT INTO recent_scope_visibility_work(thread, revision, phase, after_ws, after_session) VALUES (CAST(? AS INTEGER), CAST(? AS INTEGER), 'remove', NULL, NULL) ON CONFLICT(thread) DO UPDATE SET revision = excluded.revision, phase = 'remove', after_ws = NULL, after_session = NULL",
            [thread, revision],
          ),
        )
        (text("remove"), Json::null(), Json::null())
      }
    }
    if phase == text("remove") {
      let sources = if after_ws is Null {
        db.all(
          "SELECT ws, session FROM recent_scope_sources INDEXED BY recent_scope_sources_thread WHERE thread = CAST(?1 AS INTEGER) ORDER BY ws, session LIMIT ?2",
          [thread, lim],
        )
      } else {
        db.all(
          "SELECT ws, session FROM recent_scope_sources INDEXED BY recent_scope_sources_thread WHERE thread = CAST(?1 AS INTEGER) AND (ws, session) > (?2, ?3) ORDER BY ws, session LIMIT ?4",
          [thread, after_ws, after_session, lim],
        )
      }
      for s in sources {
        remove_source(db, get(s, "ws"), thread, get(s, "session"))
      }
      if sources.length() == limit {
        let last = sources[sources.length() - 1]
        ignore(
          db.run(
            "UPDATE recent_scope_visibility_work SET after_ws = ?, after_session = ? WHERE thread = CAST(? AS INTEGER)",
            [get(last, "ws"), get(last, "session"), thread],
          ),
        )
      } else {
        ignore(
          db.run(
            "UPDATE recent_scope_visibility_work SET phase = 'add', after_ws = NULL, after_session = NULL WHERE thread = CAST(? AS INTEGER)",
            [thread],
          ),
        )
      }
      return sources.length()
    }
    let chat = first(
      db,
      "SELECT home FROM threads WHERE id = CAST(? AS INTEGER)",
      [thread],
    )
    let mut visited = 0
    match chat {
      Some(c) if !(get(c, "home") is Null) => {
        let home = get(c, "home")
        if first(db, "SELECT ws FROM sessions WHERE key = ?", [home]) is Some(s) &&
          get(s, "ws") is String(_) &&
          tracked(db, get(s, "ws")) {
          put_source(db, get(s, "ws"), thread, home)
        }
        visited = 1
      }
      Some(_) => {
        let members = if after_session is Null {
          db.all(
            "SELECT session FROM thread_sessions WHERE thread = CAST(?1 AS INTEGER) ORDER BY session LIMIT ?2",
            [thread, lim],
          )
        } else {
          db.all(
            "SELECT session FROM thread_sessions WHERE thread = CAST(?1 AS INTEGER) AND session > ?2 ORDER BY session LIMIT ?3",
            [thread, after_session, lim],
          )
        }
        for m in members {
          let session = get(m, "session")
          if first(db, "SELECT ws FROM sessions WHERE key = ?", [session])
            is Some(s) &&
            get(s, "ws") is String(_) &&
            tracked(db, get(s, "ws")) {
            put_source(db, get(s, "ws"), thread, session)
          }
        }
        visited = members.length()
        if members.length() == limit {
          ignore(
            db.run(
              "UPDATE recent_scope_visibility_work SET after_session = ? WHERE thread = CAST(? AS INTEGER)",
              [get(members[members.length() - 1], "session"), thread],
            ),
          )
          return visited
        }
      }
      None => ()
    }
    ignore(
      db.run(
        "DELETE FROM recent_scope_visibility_work WHERE thread = CAST(? AS INTEGER)",
        [thread],
      ),
    )
    ignore(
      db.run(
        "DELETE FROM recent_scope_visibility_dirty WHERE thread = CAST(? AS INTEGER) AND revision = CAST(? AS INTEGER)",
        [thread, revision],
      ),
    )
    visited
  })
}
