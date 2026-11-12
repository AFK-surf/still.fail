// The first page of chat_list and its count, read together in one snapshot (station/src/read/ops-sessions.ts
// `recentChatList`): each chat with its sessions, latest message and, unnamed, its first words; the sessions named.

///|
let recent_chat_pending : String = "recent chat order is still being prepared"

///|
/// rows.ts `toMembership`.
fn membership_json(r : Map[String, Json]) -> Json {
  {
    "thread": field(r, "thread"),
    "session": field(r, "session"),
    "connect": field(r, "connect"),
    "joinedAt": field(r, "joined_at"),
    "leftAt": or_null(col(r, "left_at")),
  }
}

///|
/// The text key of a thread's said or first person's message (thread_state `said_n`, `person_n`).
fn state_key(db : @sql.Db, thread : Json, column : String) -> String? raise {
  match one(db, "SELECT CAST(\{column} AS TEXT) AS n FROM thread_state WHERE thread=?", [thread]) {
    Some(r) =>
      match field(r, "n") {
        String(n) => Some(n)
        _ => None
      }
    None => None
  }
}

///|
/// store.ts `lastSaid`: the thread's latest message as merged, in one snapshot.
fn last_said(db : @sql.Db, thread : Json) -> Json raise {
  db.exec("SAVEPOINT last_said_read")
  defer (db.exec("RELEASE last_said_read") catch { _ => () })
  if @legacy.merged_read_ready(db) {
    return match one(db, "SELECT m.* FROM thread_state t JOIN merged m ON m.thread = t.thread AND m.n = t.said_n WHERE t.thread = ?", [thread]) {
      Some(r) => to_message(r)
      None => Json::null()
    }
  }
  match state_key(db, thread, "said_n") {
    Some(n) => merged_bounded(db, thread, Json::string(n)).unwrap_or(Json::null())
    None => Json::null()
  }
}

///|
/// store.ts `firstText`: the first 300 characters of what the thread's first person said, as edited.
fn first_text(db : @sql.Db, thread : Json) -> Json raise {
  db.exec("SAVEPOINT first_text_read")
  defer (db.exec("RELEASE first_text_read") catch { _ => () })
  if @legacy.merged_read_ready(db) {
    return match one(db, "SELECT substr(m.text, 1, 300) AS t FROM thread_state t JOIN merged m ON m.thread = t.thread AND m.n = t.person_n WHERE t.thread = ?", [thread]) {
      Some(r) => field(r, "t")
      None => Json::null()
    }
  }
  guard state_key(db, thread, "person_n") is Some(n) else { return Json::null() }
  let edit = @legacy.bounded_edit_key(db, thread, Json::string(n)) catch {
    @legacy.Unprepared(_) => raise edits_pending()
    e => raise e
  }
  match one(
    db,
    "SELECT substr(CASE WHEN e.n IS NULL THEN m.text ELSE e.text END,1,300) AS t\n      FROM entries m LEFT JOIN entries e ON e.thread=m.thread AND e.n=CAST(?3 AS INTEGER)\n      WHERE m.thread=?1 AND m.n=CAST(?2 AS INTEGER) AND m.kind='message'",
    [thread, Json::string(n), match edit { Some(k) => Json::string(k); None => Json::null() }],
  ) {
    Some(r) => field(r, "t")
    None => Json::null()
  }
}

///|
/// ops-sessions.ts `recentChatList`: the first page of chat_list (at most `limit`) of a workspace (`ws`; none: the
/// station's), the home one's as `home` says, and how many there are.
pub fn recent_chat_list(db : @sql.Db, args : Json) -> Json raise {
  let text = (v : Json?) => match v {
    Some(String(s)) => Some(s)
    _ => None
  }
  let ws = text(args.value("ws"))
  let home = text(args.value("home"))
  let limit = match args.value("limit") {
    Some(Number(n, ..)) if n == n.floor() && n >= 0.0 && n <= 9007199254740991.0 => n.to_int()
    _ => raise Refused(500, "recent chat page size must be nonnegative")
  }
  guard @recent.page(db, ws, home, limit) is Some((ids, total)) else { raise Refused(500, recent_chat_pending) }
  let threads = []
  let keys : Array[Json] = []
  for id in ids {
    guard one(db, "SELECT * FROM threads WHERE id = ?", [id]) is Some(t) else { continue }
    let members = db.all("SELECT * FROM thread_sessions WHERE thread = ? ORDER BY joined_at, rowid", [id])
    for m in members {
      if !keys.contains(field(m, "session")) {
        keys.push(field(m, "session"))
      }
    }
    let unnamed = field(t, "title") is Null && field(t, "auto_title") is Null
    threads.push(({
      "thread": thread_json(t),
      "sessions": Json::array(members.map(membership_json)),
      "lastMessage": last_said(db, id),
      "firstText": if unnamed { first_text(db, id) } else { Json::null() },
    } : Json))
  }
  let sessions = []
  for key in keys {
    if one(db, "SELECT * FROM sessions WHERE key = ?", [key]) is Some(r) {
      sessions.push(({ "key": field(r, "key"), "title": field(r, "title"), "archivedAt": field(r, "archived_at"), "ws": or_null(col(r, "ws")) } : Json))
    }
  }
  { "threads": Json::array(threads), "sessions": Json::array(sessions), "total": Json::number(total) }
}
