// The station-wide ordering's steps (chat-list-index.ts `stepRecentChatIndex`, `readGlobalRecentChatIndex`).

///|
/// At most `limit` old or changed chats accounted, with the cursor; old and changed work alternate while both exist,
/// so new messages cannot postpone old chats. Whether all is accounted then.
fn global_step(db : @sql.Db, limit : Int) -> Bool raise {
  write(db, () => {
    let meta = one(
      db,
      "SELECT CAST(cursor AS TEXT) AS cursor, CAST(through AS TEXT) AS through, complete, prefer_dirty FROM recent_chat_meta WHERE id = 1",
      [],
    )
    let lim = num(limit)
    let pending = db.all(
      "SELECT CAST(thread AS TEXT) AS tid FROM recent_chat_dirty ORDER BY thread LIMIT ?",
      [lim],
    )
    let complete = int(meta, "complete") == 1
    let use_dirty = pending.length() > 0 &&
      (complete || int(meta, "prefer_dirty") == 1)
    let cursor = get(meta, "cursor")
    let through = get(meta, "through")
    let old = if !use_dirty && !complete && !(through is Null) {
      if cursor is Null {
        db.all(
          "SELECT CAST(id AS TEXT) AS tid FROM threads WHERE id <= CAST(? AS INTEGER) ORDER BY id LIMIT ?",
          [through, lim],
        )
      } else {
        db.all(
          "SELECT CAST(id AS TEXT) AS tid FROM threads WHERE id > CAST(? AS INTEGER) AND id <= CAST(? AS INTEGER) ORDER BY id LIMIT ?",
          [cursor, through, lim],
        )
      }
    } else {
      []
    }
    let chats = if use_dirty { pending } else { old }
    let mut delta = 0
    for row in chats {
      let thread = get(row, "tid")
      let had = exists(
        db,
        "SELECT 1 FROM recent_chat_rows WHERE thread = CAST(? AS INTEGER)",
        [thread],
      )
      if !chat_exists(db, thread) {
        if had {
          ignore(
            db.run(
              "DELETE FROM recent_chat_rows WHERE thread = CAST(? AS INTEGER)",
              [thread],
            ),
          )
          delta -= 1
        }
      } else {
        ignore(
          db.run(
            "INSERT INTO recent_chat_rows (thread, at, said_at, created_at) SELECT thread, at, said_at, created_at FROM (\{current("?1")}) WHERE true ON CONFLICT (thread) DO UPDATE SET at = excluded.at, said_at = excluded.said_at, created_at = excluded.created_at WHERE at IS NOT excluded.at OR said_at IS NOT excluded.said_at OR created_at IS NOT excluded.created_at",
            [thread],
          ),
        )
        if !had {
          delta += 1
        }
      }
      ignore(
        db.run(
          "DELETE FROM recent_chat_dirty WHERE thread = CAST(? AS INTEGER)",
          [thread],
        ),
      )
    }
    if use_dirty {
      ignore(
        db.run(
          "UPDATE recent_chat_meta SET total = total + ?, prefer_dirty = 0 WHERE id = 1",
          [num(delta)],
        ),
      )
    } else {
      let reached = match chats.last() {
        Some(r) => get(r, "tid")
        None => cursor
      }
      ignore(
        db.run(
          "UPDATE recent_chat_meta SET cursor = CAST(? AS INTEGER), total = total + ?, complete = ?, prefer_dirty = 1 WHERE id = 1",
          [
            reached,
            num(delta),
            num(if complete || chats.length() < limit { 1 } else { 0 }),
          ],
        ),
      )
    }
    int(
      one(db, "SELECT complete FROM recent_chat_meta WHERE id = 1", []),
      "complete",
    ) ==
    1 &&
    !exists(db, "SELECT 1 FROM recent_chat_dirty LIMIT 1", [])
  })
}

///|
/// The station-wide page can be read (`readGlobalRecentChatIndex` gives one).
fn global_ready(db : @sql.Db) -> Bool raise {
  snapshot(db, "recent_chat_page", () => {
    installed(db, "global") &&
    int(
      one(db, "SELECT complete FROM recent_chat_meta WHERE id = 1", []),
      "complete",
    ) ==
    1 &&
    !exists(db, "SELECT 1 FROM recent_chat_dirty LIMIT 1", [])
  })
}
