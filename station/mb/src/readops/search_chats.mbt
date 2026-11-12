// chat_list searched (station/src/read/ops-sessions.ts `searchChatList`, store/chat-list.ts `searchChats`): every
// chat in scope tested by its titles, latest words and sessions, the matches counted and the first `limit` read in
// full. The statements are the TypeScript's, as it makes them.

///|
/// store/chat-list.ts SEARCH_CHAT_LIST.
let search_chat_list_sql : String =
  #|SELECT t.*, e.at AS said_at,
  #|    CASE WHEN e.n IS NULL THEN NULL ELSE COALESCE((SELECT m.text FROM merged m WHERE m.thread = t.id AND m.n = s.said_n), '') END AS said_text,
  #|    (SELECT substr(m.text, 1, 300) FROM merged m WHERE m.thread = t.id AND m.n = s.person_n) AS first_text,
  #|    (SELECT json_group_array(json_object('session', x.session, 'connect', x.connect, 'joinedAt', x.joined_at,
  #|       'title', x.title, 'archivedAt', x.archived_at, 'ws', x.ws, 'present', x.present))
  #|     FROM (SELECT m.session, m.connect, m.joined_at, a.title, a.archived_at, a.ws, a.key IS NOT NULL AS present
  #|       FROM thread_sessions m LEFT JOIN sessions a ON a.key = m.session WHERE m.thread = t.id
  #|       ORDER BY m.joined_at, m.rowid) x) AS members
  #|  FROM threads t
  #|  LEFT JOIN sessions h ON h.key = t.home
  #|  LEFT JOIN thread_state s ON s.thread = t.id
  #|  LEFT JOIN entries e ON e.thread = t.id AND e.n = s.said_n AND e.kind = 'message'
  #|  WHERE ?1 IS NULL OR CASE
  #|    WHEN t.home IS NOT NULL THEN COALESCE(h.ws, ?2) = ?1
  #|    WHEN NOT EXISTS (SELECT 1 FROM thread_sessions m WHERE m.thread = t.id) THEN ?2 = ?1
  #|    ELSE EXISTS (SELECT 1 FROM thread_sessions m LEFT JOIN sessions a ON a.key = m.session
  #|                 WHERE m.thread = t.id AND COALESCE(a.ws, ?2) = ?1)
  #|  END ORDER BY COALESCE(e.at, t.created_at) DESC, COALESCE(e.at, 0) DESC, t.created_at DESC, t.id DESC

///|
/// store/chat-list.ts SEARCH_CHAT_LIST_KEYS.
let search_chat_list_keys_sql : String =
  #|SELECT t.*, e.at AS said_at, (SELECT json_group_array(json_object('session', x.session, 'connect', x.connect, 'joinedAt', x.joined_at,
  #|       'title', x.title, 'archivedAt', x.archived_at, 'ws', x.ws, 'present', x.present))
  #|     FROM (SELECT m.session, m.connect, m.joined_at, a.title, a.archived_at, a.ws, a.key IS NOT NULL AS present
  #|       FROM thread_sessions m LEFT JOIN sessions a ON a.key = m.session WHERE m.thread = t.id
  #|       ORDER BY m.joined_at, m.rowid) x) AS members
  #|  FROM threads t
  #|  LEFT JOIN sessions h ON h.key = t.home
  #|  LEFT JOIN thread_state s ON s.thread = t.id
  #|  LEFT JOIN entries e ON e.thread = t.id AND e.n = s.said_n AND e.kind = 'message'
  #|  WHERE ?1 IS NULL OR CASE
  #|    WHEN t.home IS NOT NULL THEN COALESCE(h.ws, ?2) = ?1
  #|    WHEN NOT EXISTS (SELECT 1 FROM thread_sessions m WHERE m.thread = t.id) THEN ?2 = ?1
  #|    ELSE EXISTS (SELECT 1 FROM thread_sessions m LEFT JOIN sessions a ON a.key = m.session
  #|                 WHERE m.thread = t.id AND COALESCE(a.ws, ?2) = ?1)
  #|  END ORDER BY COALESCE(e.at, t.created_at) DESC, COALESCE(e.at, 0) DESC, t.created_at DESC, t.id DESC

///|
/// store.ts `lastSaidText`: the thread's latest said words, as edited.
fn last_said_text(db : @sql.Db, thread : Json) -> Json raise {
  db.exec("SAVEPOINT last_said_text_read")
  defer (db.exec("RELEASE last_said_text_read") catch { _ => () })
  if @legacy.merged_read_ready(db) {
    return match one(db, "SELECT m.text AS t FROM thread_state t JOIN merged m ON m.thread = t.thread AND m.n = t.said_n WHERE t.thread = ?", [thread]) {
      Some(r) => field(r, "t")
      None => Json::null()
    }
  }
  guard state_key(db, thread, "said_n") is Some(n) else { return Json::null() }
  let edit = @legacy.bounded_edit_key(db, thread, Json::string(n)) catch {
    @legacy.Unprepared(_) => raise edits_pending()
    e => raise e
  }
  match one(
    db,
    "SELECT CASE WHEN e.n IS NULL THEN m.text ELSE e.text END AS t\n      FROM entries m LEFT JOIN entries e ON e.thread=m.thread AND e.n=CAST(?3 AS INTEGER)\n      WHERE m.thread=?1 AND m.n=CAST(?2 AS INTEGER) AND m.kind='message'",
    [thread, Json::string(n), match edit { Some(k) => Json::string(k); None => Json::null() }],
  ) {
    Some(r) => field(r, "t")
    None => Json::null()
  }
}

///|
/// A value joined into a string as JavaScript's join and template do.
fn js_text(v : Json) -> String {
  match v {
    String(s) => s
    Null => ""
    Number(n, ..) if n == n.floor() && n.abs() < 1.0e21 => n.to_int64().to_string()
    v => v.stringify()
  }
}

///|
/// ops-sessions.ts `searchChatList`: the chats of a workspace (`ws`; none: the station's) whose titles, latest words or
/// sessions hold `query`, the first `limit` of them in full, the sessions they name, and how many match.
pub fn search_chat_list(db : @sql.Db, args : Json) -> Json raise {
  let limit = match args.value("limit") {
    Some(Number(n, ..)) => n
    _ => nan()
  }
  if limit == 0.0 {
    return { "threads": [], "sessions": [], "total": 0 }
  }
  let query = js_text(args.value("query").unwrap_or(Json::string("undefined")))
  let scope = [args.value("ws").unwrap_or(Json::null()), args.value("home").unwrap_or(Json::null())]
  db.exec("SAVEPOINT search_chat_list_read")
  defer (db.exec("RELEASE search_chat_list_read") catch { _ => () })
  let summarized = !@legacy.merged_read_ready(db)
  let threads = []
  let sessions : Map[String, Json] = Map([])
  let mut total = 0
  for row in db.all(if summarized { search_chat_list_keys_sql } else { search_chat_list_sql }, scope) {
    let id = field(row, "id")
    let members = match field(row, "members") {
      String(s) =>
        match (@json.parse(s) catch { _ => Json::array([]) }) {
          Array(ms) => ms
          _ => []
        }
      _ => []
    }
    let (first_words, said) = if summarized {
      (first_text(db, id), last_said_text(db, id))
    } else {
      (field(row, "first_text"), field(row, "said_text"))
    }
    let member = (m : Json, k : String) => m.value(k).unwrap_or(Json::null())
    let titles = [field(row, "title"), field(row, "auto_title"), first_words, ..members.map(m => member(m, "title"))].filter(t => !(t is Null))
    let haystack = @jscase.lower(
      titles.map(js_text).join(" ") + " " + js_text(said) + " " + members.map(m => js_text(member(m, "session"))).join(" "),
    )
    if !haystack.contains(query) {
      continue
    }
    total += 1
    if threads.length().to_double() < limit {
      for m in members {
        if !(member(m, "present") is (Number(0.0, ..) | Null | False)) {
          let key = js_text(member(m, "session"))
          sessions[key] = { "key": member(m, "session"), "title": member(m, "title"), "archivedAt": member(m, "archivedAt"), "ws": member(m, "ws") }
        }
      }
      threads.push(({
        "thread": thread_json(row),
        "sessions": Json::array(
          members.map(m => ({ "thread": id, "session": member(m, "session"), "connect": member(m, "connect"), "joinedAt": member(m, "joinedAt") } : Json)),
        ),
        "lastMessage": last_said(db, id),
        "firstText": first_words,
      } : Json))
    }
  }
  { "threads": Json::array(threads), "sessions": Json::array(sessions.values().collect()), "total": Json::number(total.to_double()) }
}
