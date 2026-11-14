// Every thread as chat_list has it, with no viewer's unread count (station/src/read/ops-sessions.ts `threadList`,
// store.ts `listThreads(s, "", null, null, "none")`): each with its sessions, last entry, latest message, people, first
// words and letters, the most recently said in first.

///|
/// store.ts `threadPeople`: who wrote in a thread, a platform's people named `slack:<connect>:<user>`.
fn thread_people(db : @sql.Db, thread : Json, surface : Json) -> Json raise {
  let connect = match one(db, "SELECT MIN(connect) AS c FROM thread_sessions WHERE thread = ?", [thread]) {
    Some(r) => field(r, "c")
    None => Json::null()
  }
  let authors = db.all("SELECT author FROM thread_people WHERE thread = ? ORDER BY first_n", [thread]).map(r => field(r, "author"))
  if surface == Json::string("ember") {
    return Json::array(authors)
  }
  match connect {
    String(c) => Json::array(authors.map(a => Json::string("slack:\{c}:\{js_text(a)}")))
    _ => Json::array([])
  }
}

///|
fn count_of(db : @sql.Db, sql : String, thread : Json, name : String) -> Double raise {
  match one(db, sql, [thread]) {
    Some(r) =>
      match field(r, name) {
        Number(n, ..) => n
        _ => 0.0
      }
    None => 0.0
  }
}

///|
/// ops-sessions.ts `threadList`.
pub fn thread_list(db : @sql.Db) -> Json raise {
  let rows = db.all("SELECT t.*, COALESCE(r.n, 0) AS read_n FROM threads t LEFT JOIN reads r ON r.thread = t.id AND r.viewer = ?1", [Json::string("")])
  let summaries : Array[(Double, Double, Double, Json)] = []
  for r in rows {
    let id = field(r, "id")
    let last_letter = count_of(db, "SELECT MAX(n) AS n FROM letters WHERE thread = ?", id, "n")
    let last_message = last_said(db, id)
    let said_at = match last_message.value("createdAt") {
      Some(Number(n, ..)) => n
      _ => 0.0
    }
    let summary : Json = {
      "sessions": Json::array(db.all("SELECT * FROM thread_sessions WHERE thread = ? ORDER BY joined_at, rowid", [id]).map(membership_json)),
      "last": Json::number(count_of(db, "SELECT MAX(n) AS n FROM entries WHERE thread = ?", id, "n")),
      "lastMessage": last_message,
      "read": field(r, "read_n"),
      "unread": 0,
      "people": thread_people(db, id, field(r, "surface")),
      "firstText": first_text(db, id),
      "letters": Json::number(last_letter + count_of(db, "SELECT letters FROM thread_state WHERE thread = ?", id, "letters")),
      "lettersLast": Json::number(last_letter),
      "thread": thread_json(r),
    }
    let created = match field(r, "created_at") { Number(n, ..) => n; _ => 0.0 }
    let n = match id { Number(n, ..) => n; _ => 0.0 }
    summaries.push((said_at, created, n, summary))
  }
  // Array.prototype.sort is stable; equal keys keep the rows' order.
  let sorted = stable_sort(summaries, (a, b) => {
    for pair in [(a.0, b.0), (a.1, b.1), (a.2, b.2)] {
      if pair.0 != pair.1 {
        return if pair.1 > pair.0 { 1 } else { -1 }
      }
    }
    0
  })
  Json::array(sorted.map(s => s.3))
}
