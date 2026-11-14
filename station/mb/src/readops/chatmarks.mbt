// What a device that makes the viewer's sidebar itself cannot make of what it holds (station/src/read/views.ts
// `chatMarks`, GET /chats?marks=1): the cards and needs waiting, the cards the viewer answered lately, the archive
// review's marks, what the viewer pinned, kept, hid, muted and read, the chats opened and their openers, the shares,
// client keys, the Slack teams' names and the Slack users the viewer is. Of the sessions shown, or of those a change
// named (`scope`).

///|
/// A chat's id written as a key, as a number.
fn key_number(s : String) -> Double {
  let mut n = 0.0
  for c in s {
    n = n * 10.0 + (c.to_int() - '0'.to_int()).to_double()
  }
  n
}

///|
/// Thread-keyed objects as JavaScript writes them: an integer key in ascending order.
fn by_thread(m : Map[String, Json]) -> Json {
  let keys = m.keys().collect()
  keys.sort_by((a, b) => {
    let (x, y) = (key_number(a), key_number(b))
    if x < y { -1 } else if x > y { 1 } else { 0 }
  })
  let out : Map[String, Json] = Map([])
  for k in keys {
    out[k] = m.get(k).unwrap()
  }
  Json::object(out)
}

///|
/// store.ts `lastTurn`: a session's latest turn with its id.
fn last_turn_of(db : @sql.Db, key : String) -> Json raise {
  match one(db, "SELECT * FROM turns WHERE session_key = ? ORDER BY started_at DESC LIMIT 1", [Json::string(key)]) {
    Some(r) => {
      r["turn_id"] = field(r, "id")
      latest_turn(r)
    }
    None => Json::null()
  }
}

///|
/// store.ts `pendingCards`: the cards these chats wait on as kept (by thread, the post's entry), and those with a card
/// posted before they were kept; none where the store keeps none.
fn pending_cards(db : @sql.Db, threads : Array[Json]) -> (Map[String, Json], Set[String])? raise {
  let from = try {
    match one(db, "SELECT entry FROM pending_cards_from WHERE id = 1", []) {
      Some(r) if !(field(r, "entry") is Null) => num(field(r, "entry"))
      _ => 0.0
    }
  } catch {
    _ => return None
  }
  let at : Map[String, Json] = Map([])
  for r in db.all("SELECT thread, n FROM pending_cards WHERE thread IN (SELECT value FROM json_each(?))", [ids_json(threads)]) {
    at[js_text(field(r, "thread"))] = field(r, "n")
  }
  let before : Set[String] = Set::new()
  let first = (sql : String, t : Json) => match one(db, sql, [t]) {
    Some(r) if field(r, "rowid") is Number(n, ..) => n <= from
    _ => false
  }
  for t in threads {
    if at.contains(js_text(t)) {
      continue
    }
    if first("SELECT rowid FROM entries INDEXED BY entries_cards WHERE thread = ? AND card IS NOT NULL ORDER BY n LIMIT 1", t) ||
      first("SELECT rowid FROM entries INDEXED BY entries_options WHERE thread = ? AND options IS NOT NULL ORDER BY n LIMIT 1", t) {
      before.add(js_text(t))
    }
  }
  Some((at, before))
}

///|
/// views.ts `isMine`: whether a person is the viewer, by id, by email, or as a Slack user the viewer said is them.
fn is_mine(viewer_email : String, slack : Array[String], p : Json) -> Bool {
  guard p is Object(_) else { return false }
  let pid = match p.value("id") { Some(String(s)) => s; _ => "" }
  if pid == viewer_email {
    return true
  }
  if p.value("email") is Some(String(e)) && @jscase.lower(e) == @jscase.lower(viewer_email) {
    return true
  }
  if p.value("via") == Some(Json::string("slack")) {
    let tail = match pid.rev_find(":") {
      Some(i) => pid.view(start_offset=i + 1).to_owned()
      None => pid
    }
    return slack.contains(tail)
  }
  false
}

///|
/// views.ts `chatMarks`.
pub fn chat_marks(db : @sql.Db, host : @host.Host, data : String, sep : String, ask : Json) -> Json raise {
  let args = ask.value("args").unwrap_or(Json::null())
  let known = Known::of(host, data, sep, ask)
  let viewer = args.value("viewer").unwrap_or(Json::null())
  let email = match viewer.value("email") { Some(String(e)) => e; _ => "" }
  let scope = match args.value("scope") {
    Some(Object(_) as sc) =>
      Some((
        keys_arg(sc.value("sessions")).unwrap_or([]),
        match sc.value("threads") { Some(Array(t)) => t; _ => [] },
      ))
    _ => None
  }
  let (connects, reviews) = known.config()
  let session_of = (k : String) => one(db, "SELECT * FROM sessions WHERE key = ?", [Json::string(k)])
  let found : Array[Map[String, Json]] = match scope {
    None => db.all(shown_sessions_sql, [])
    Some((sessions, _)) => {
      let out : Array[Map[String, Json]] = []
      for k in sessions {
        if session_of(k) is Some(x) && field(x, "archived_at") is Null {
          out.push(x)
        }
      }
      out
    }
  }
  let shown = found.filter(x => sees(viewer, field(x, "ws")))
  let keys = shown.map(x => js_text(field(x, "key")))
  let thread_ids = unique_ids([match scope { Some((_, t)) => t; None => [] }, threads_of_sessions(db, keys)])
  // The chats themselves and who is in them, by their keys alone.
  let own : Array[(Map[String, Json], Array[Map[String, Json]])] = []
  for id in thread_ids {
    guard one(db, "SELECT * FROM threads WHERE id = ?", [id]) is Some(t) else { continue }
    if field(t, "surface") == Json::string("ember") && field(t, "hidden_at") is Null {
      own.push((t, db.all("SELECT * FROM thread_sessions WHERE thread = ? ORDER BY joined_at, rowid", [id])))
    }
  }
  let listed : Set[String] = Set::new()
  for k in keys {
    listed.add(k)
  }
  let listed_one = (key : String) => match scope {
    None => listed.contains(key)
    Some(_) =>
      match session_of(key) {
        Some(x) => field(x, "archived_at") is Null && sees(viewer, field(x, "ws"))
        None => false
      }
  }
  let last_turns : Map[String, Json] = Map([])
  let last_turn = (key : String) => match last_turns.get(key) {
    Some(t) => t
    None => {
      let t = last_turn_of(db, key)
      last_turns[key] = t
      t
    }
  }
  let ids = own.map(t => field(t.0, "id"))
  // store.ts `dismissed` of these chats: the viewer's, "thread:n".
  let dismissed : Set[String] = Set::new()
  let dismissed_list : Array[Json] = []
  let seen_ids : Set[String] = Set::new()
  for id in ids {
    if seen_ids.contains(js_text(id)) {
      continue
    }
    seen_ids.add(js_text(id))
    for r in db.all("SELECT thread, n FROM dismissed WHERE viewer = ? AND thread = ?", [Json::string(email), id]) {
      let k = "\{js_text(field(r, "thread"))}:\{js_text(field(r, "n"))}"
      if !dismissed.contains(k) {
        dismissed.add(k)
        dismissed_list.push(Json::string(k))
      }
    }
  }
  let selves = db.all("SELECT slack_user FROM identities WHERE viewer = ? ORDER BY at", [Json::string(email)]).map(r => js_text(field(r, "slack_user")))
  let card : Map[String, Json] = Map([])
  let need : Map[String, Json] = Map([])
  let suggested : Array[Json] = []
  let verdicts : Map[String, Json] = Map([])
  let reviewed : Set[String] = Set::new()
  if ids.length() > 0 {
    for r in db.all("SELECT thread FROM archive_suggestions WHERE thread IN (SELECT value FROM json_each(?1))\n    UNION SELECT thread FROM archive_verdicts WHERE thread IN (SELECT value FROM json_each(?1))", [ids_json(ids)]) {
      reviewed.add(js_text(field(r, "thread")))
    }
  }
  let cards = pending_cards(db, ids)
  require_card_posts(db, match cards {
    None => threads_with_cards(db, ids)
    Some((_, before)) => ids.filter(t => before.contains(js_text(t)))
  })
  for t in own {
    let (thread, sessions) = t
    let id = field(thread, "id")
    let names = known.author_names(db, id)
    let kept = match cards {
      None => None
      Some((_, before)) if before.contains(js_text(id)) => None
      Some((at, _)) => Some(at.get(js_text(id)).unwrap_or(Json::null()))
    }
    let c = card_view(db, id, names, dismissed~, kept?)
    if !(c is Null) {
      card[js_text(id)] = c
    } else {
      let agents = sessions
        .filter(m => listed_one(js_text(field(m, "session"))))
        .map(m => ({ "lastTurn": last_turn(js_text(field(m, "session"))) } : Json))
      let n = need_view(db, id, agents, names, dismissed~)
      if !(n is Null) {
        need[js_text(id)] = n
      }
    }
    if !reviewed.contains(js_text(id)) {
      continue
    }
    if archive_suggested(db, id) {
      suggested.push(id)
    }
    if reviews {
      let v = archive_verdict(db, id)
      if !(v is Null) {
        verdicts[js_text(id)] = v
      }
    }
  }
  let answered : Map[String, Array[Json]] = Map([])
  for a in answers_since(db, Json::number(known.now - answered_within), threads_with_cards(db, ids)) {
    if !is_mine(email, selves, known.creator(a.by)) {
      continue
    }
    let k = js_text(a.question.value("thread").unwrap_or(Json::null()))
    let v = answered_view(known, a, by=false)
    match answered.get(k) {
      Some(l) => l.push(v)
      None => answered[k] = [v]
    }
  }
  let answered_out : Map[String, Json] = Map([])
  for k, l in answered {
    answered_out[k] = Json::array(l)
  }
  // store.ts `keptChats` of these chats, the viewer's.
  let kept_list : Array[Json] = []
  let kept_seen : Set[String] = Set::new()
  for id in ids {
    for r in db.all("SELECT thread FROM kept_chats WHERE viewer = ? AND thread = ?", [Json::string(email), id]) {
      let k = js_text(field(r, "thread"))
      if !kept_seen.contains(k) {
        kept_seen.add(k)
        kept_list.push(field(r, "thread"))
      }
    }
  }
  let pins : Map[String, Json] = Map([])
  let pin_rows = match scope {
    None => db.all("SELECT session, at FROM pins WHERE viewer = ?", [Json::string(email)])
    Some(_) =>
      if keys.length() == 0 {
        []
      } else {
        db.all("SELECT session, at FROM pins WHERE viewer = ?1 AND session IN (SELECT value FROM json_each(?2))", [Json::string(email), ids_json(keys.map(Json::string))])
      }
  }
  for r in pin_rows {
    pins[js_text(field(r, "session"))] = field(r, "at")
  }
  let (openers, opened_by) = openers_opened(db, Some(keys))
  let opened : Map[String, Json] = Map([])
  for k, l in opened_by {
    opened[k] = Json::array(l)
  }
  let shares = chat_shares(db, Some(keys), known.now)
  let client_keys : Map[String, Json] = Map([])
  for k in keys {
    if known.client_keys.get(k) is Some(c) {
      client_keys[k] = Json::string(c)
    }
  }
  let teams : Map[String, Json] = Map([])
  for c in connects {
    let name = known.team_name(c.0)
    if !(name is Null) {
      teams[c.0] = name
    }
  }
  let reads : Map[String, Json] = Map([])
  let hidden : Array[Json] = []
  let muted : Array[Json] = []
  if ids.length() > 0 {
    for r in db.all("SELECT thread, n FROM reads WHERE viewer = ?1 AND thread IN (SELECT value FROM json_each(?2))", [Json::string(email), ids_json(ids)]) {
      reads[js_text(field(r, "thread"))] = field(r, "n")
    }
    let unique = (rows : Array[Map[String, Json]], out : Array[Json]) => {
      let seen : Set[String] = Set::new()
      for r in rows {
        let k = js_text(field(r, "thread"))
        if !seen.contains(k) {
          seen.add(k)
          out.push(field(r, "thread"))
        }
      }
    }
    unique(db.all("SELECT thread FROM hidden_chats WHERE viewer = ?1 AND thread IN (SELECT value FROM json_each(?2))", [Json::string(email), ids_json(ids)]), hidden)
    unique(db.all("SELECT thread FROM muted_chats WHERE viewer = ?1 AND thread IN (SELECT value FROM json_each(?2))", [Json::string(@jscase.lower(email)), ids_json(ids)]), muted)
  }
  {
    "card": by_thread(card),
    "need": by_thread(need),
    "answered": by_thread(answered_out),
    "suggested": Json::array(suggested),
    "verdicts": by_thread(verdicts),
    "reviews": Json::boolean(reviews),
    "kept": Json::array(kept_list),
    "hidden": Json::array(hidden),
    "muted": Json::array(muted),
    "pins": Json::object(pins),
    "openers": Json::object(openers),
    "opened": Json::object(opened),
    "shares": Json::object(shares),
    "clientKeys": Json::object(client_keys),
    "teams": Json::object(teams),
    "selves": Json::array(selves.map(Json::string)),
    "dismissed": Json::array(dismissed_list),
    "reads": by_thread(reads),
  }
}
