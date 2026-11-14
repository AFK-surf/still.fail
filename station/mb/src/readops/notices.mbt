// What the people of the station's own chats hear about while no client of theirs runs (station/src/read/notices.ts
// `turnNotices`, `saidNotices`; src/cloud/notify.ts asks them): an agent's turn ending (done with something said, or
// blocked on something new it asks), a person saying something, the station saying something went wrong. The words a
// notice says of the station's own (a file sent, a chat with no name) the pool gives in the station's language
// (`words`), and the time it is made at (`now`).

///|
let last_message_pending : String = "last message pending: "

///|
/// notices.ts TEXT: how much of a notice's text is kept, in characters.
let notice_text : Int = 400

///|
/// archive-last.ts `archiveLastKey`: a chat's latest message's key, if known (none for none), in one snapshot.
fn archive_last_key(db : @sql.Db, thread : Json) -> (Bool, Json) raise {
  if !archive_last_installed(db) {
    return (false, Json::null())
  }
  db.exec("SAVEPOINT archive_last_read")
  defer (db.exec("RELEASE archive_last_read") catch { _ => () })
  let answer = () => {
    guard one(db, "SELECT version FROM archive_last_meta WHERE id=1", []) is Some(meta) else { return (false, Json::null()) }
    if !(field(meta, "version") is Number(1.0, ..)) {
      raise Failure("archive last version \{js_text(field(meta, "version"))} is incompatible")
    }
    guard one(db, archive_last_first_sql, [thread]) is Some(first) else { return (true, Json::null()) }
    if !(field(first, "at") is Null) {
      return (true, field(first, "n"))
    }
    match one(db, archive_last_guard_sql, [thread]) {
      Some(cached) if field(cached, "at") is Null || !(field(cached, "n") is Null) => return (true, field(cached, "n"))
      _ => ()
    }
    // archive-last.ts `nativeLastKey`
    if exists_in(db, "index", "entries_said") && exists_in(db, "index", "entries_letters") {
      let said = one(db, "SELECT CAST(e.n AS TEXT) AS n,e.at FROM entries e INDEXED BY entries_said\n  WHERE e.thread=? AND e.kind='message' AND e.letter IS NULL ORDER BY e.n DESC LIMIT 1", [thread])
      let letter = match said {
        Some(s) => one(db, "SELECT 1 FROM entries e INDEXED BY entries_letters\n  WHERE e.thread=?1 AND e.n>CAST(?2 AS INTEGER) AND e.letter IS NOT NULL ORDER BY e.n DESC LIMIT 1", [thread, field(s, "n")])
        None => one(db, "SELECT 1 FROM entries e INDEXED BY entries_letters\n  WHERE e.thread=? AND e.letter IS NOT NULL ORDER BY e.n DESC LIMIT 1", [thread])
      }
      if letter is None {
        return (true, match said { Some(s) => field(s, "n"); None => Json::null() })
      }
    }
    guard one(db, archive_last_tail_sql, [thread]) is Some(tail) else { return (false, Json::null()) }
    if !(field(tail, "at") is Null) || num(field(tail, "count")) < 65.0 {
      return (true, field(tail, "n"))
    }
    (false, Json::null())
  }
  answer() catch {
    e => {
      let m = sql_message(e)
      if m.contains("no such table: archive_last_meta") || m.contains("no such table: archive_last_guard") {
        (false, Json::null())
      } else {
        raise e
      }
    }
  }
}

///|
/// store.ts `lastMessage`: a chat's latest message as merged; refused while its key is not known.
fn last_message(db : @sql.Db, thread : Json) -> Json raise {
  db.exec("SAVEPOINT last_message_read")
  defer (db.exec("RELEASE last_message_read") catch { _ => () })
  let (known, n) = archive_last_key(db, thread)
  if !known {
    raise Refused(503, last_message_pending + Json::array([thread]).stringify())
  }
  if n is Null {
    return Json::null()
  }
  merged(db, thread, number_of(n)).unwrap_or(Json::null())
}

///|
/// store.ts `blockedAsk`'s freshness: whether a blocked turn asks something new in a chat (its card waiting, else the
/// message its need asks with, not posted before an earlier blocked end of the same session).
fn blocked_fresh(db : @sql.Db, thread : Json, key : String, turn : Json) -> Bool raise {
  let about = turn.value("about").unwrap_or(Json::null())
  let seq = match about {
    Object(_) if about.value("thread") == Some(thread) && is_integer(about.value("seq").unwrap_or(Json::null())) => about.value("seq").unwrap()
    _ => Json::null()
  }
  let started = match turn.value("startedAt") { Some(s) if is_integer(s) => s; _ => Json::number(0.0) }
  let ended = match turn.value("endedAt") { Some(e) if is_integer(e) => e; _ => as_integer(Json::string(i64_max)) }
  let asked = match review_pending_card(db, { "thread": thread }) {
    Array([m, _]) => Some(m)
    _ =>
      match asking_message(db, thread, seq, started, ended) {
        Some((m, _)) => Some(m)
        None => None
      }
  }
  guard asked is Some(m) else { return false }
  one(
    db,
    "SELECT 1 AS x FROM turns WHERE session_key = ? AND ended_at >= ? AND ended_at < ? AND declared IN ('block', 'need_help', 'need_human', 'need_decision') LIMIT 1",
    [Json::string(key), m.value("createdAt").unwrap_or(Json::null()), started],
  ) is None
}

///|
/// String.prototype.trim() === "".
fn js_blank(s : String) -> Bool {
  @jscase.trim(s) == ""
}

///|
/// notices.ts `turnNotice`: what a turn's end is worth telling its chat, (kind, text).
fn turn_notice(turn : Json, last : Json, key : String, file : String, fresh : Bool) -> (String, String)? {
  let theirs = match last {
    Object(_) if last.value("authorKind") == Some(Json::string("agent")) && last.value("author") == Some(Json::string(key)) &&
      num(last.value("createdAt").unwrap_or(Json::null())) >= num(turn.value("startedAt").unwrap_or(Json::null())) => Some(last)
    _ => None
  }
  let text = match theirs {
    Some(m) =>
      match m.value("text") {
        Some(String(t)) if !js_blank(t) => Some(t)
        _ => None
      }
    None => None
  }
  let declared = turn.value("declared").unwrap_or(Json::null())
  if declared == Json::string("block") && fresh {
    let need = match turn.value("need") {
      Some(String(n)) if !js_blank(n) => Some(n)
      _ => None
    }
    return Some(("block", match need { Some(n) => n; None => text.unwrap_or("") }))
  }
  if turn.value("outcome") == Some(Json::string("failed")) {
    return None
  }
  if declared == Json::string("final") || declared == Json::string("block") {
    return match theirs { Some(_) => Some(("done", text.unwrap_or(file))); None => None }
  }
  None
}

///|
/// notices.ts `wentWrong`: the station's word that something went wrong (⚠️ first), its first paragraph.
fn went_wrong(text : String) -> String? {
  guard text.has_prefix("⚠️") else { return None }
  let rest = text.view(start_offset="⚠️".length()).to_owned()
  let first = match rest.find("\n\n") {
    Some(i) => rest.view(end_offset=i).to_owned()
    None => rest
  }
  Some(@jscase.trim(first))
}

///|
/// notices.ts `notice`: a notice of one of the station's chats, to its people but `except` and those who muted it.
fn notice(
  db : @sql.Db,
  known : Known,
  untitled : String,
  thread : Json,
  seq : Json,
  session : Json,
  kind : String,
  by : String,
  text : String,
  except : String?,
) -> Json? raise {
  guard one(db, "SELECT * FROM threads WHERE id = ?", [thread]) is Some(t) else { return None }
  let sessions = db.all("SELECT * FROM thread_sessions WHERE thread = ? ORDER BY joined_at, rowid", [thread]).map(m => field(m, "session"))
  // notices.ts `emailsOf`
  let refs : Array[Json] = []
  if !(field(t, "created_by") is Null) {
    refs.push(field(t, "created_by"))
  }
  match thread_people(db, thread, field(t, "surface")) {
    Array(said) => refs.append(said)
    _ => ()
  }
  for s in sessions {
    if one(db, "SELECT * FROM sessions WHERE key = ?", [s]) is Some(r) && !(field(r, "created_by") is Null) {
      refs.push(field(r, "created_by"))
    }
  }
  let not_ = except.map(@jscase.lower)
  let seen : Set[String] = Set::new()
  let recipients : Array[String] = []
  for p in known.people(Json::array(refs)) {
    guard p.value("email") is Some(String(e)) else { continue }
    let e = @jscase.lower(e)
    if Some(e) == not_ || seen.contains(e) {
      continue
    }
    seen.add(e)
    recipients.push(e)
  }
  let muted : Set[String] = Set::new()
  if recipients.length() > 0 {
    for r in db.all("SELECT viewer FROM muted_chats WHERE viewer IN (SELECT value FROM json_each(?1)) AND thread = ?2", [ids_json(recipients.map(Json::string)), thread]) {
      muted.add(js_text(field(r, "viewer")))
    }
  }
  let to = recipients.filter(e => !muted.contains(e))
  if to.length() == 0 {
    return None
  }
  // (only the station's own chats are told: named as given, else untitled, never by what is said in them)
  let given = @jscase.trim_white(match field(t, "title") { String(s) => s; _ => "" })
  let auto = @jscase.trim_white(match field(t, "auto_title") { String(s) => s; _ => "" })
  let title = if given != "" { given } else if auto != "" { auto } else { untitled }
  Some({
    "to": Json::array(to.map(Json::string)),
    "kind": Json::string(kind),
    "session": session,
    "thread": thread,
    "seq": seq,
    "title": Json::string(title),
    "by": Json::string(by),
    "text": Json::string(take_chars(text, notice_text)),
    "at": Json::number(known.now),
  })
}

///|
fn word_of(args : Json, k : String) -> String {
  match args.value("words") {
    Some(w) =>
      match w.value(k) {
        Some(String(s)) => s
        _ => ""
      }
    None => ""
  }
}

///|
/// notices.ts `turnNotices`: a session's last turn, if it ended since `since` and is not `ended`, told to its chats.
pub fn turn_notices(db : @sql.Db, host : @host.Host, data : String, sep : String, ask : Json) -> Json raise {
  let args = ask.value("args").unwrap_or(Json::null())
  let known = Known::of(host, data, sep, ask)
  let key = js_text(args.value("key").unwrap_or(Json::null()))
  let since = num(args.value("since").unwrap_or(Json::null()))
  let ended = args.value("ended").unwrap_or(Json::null())
  let turn = last_turn_of(db, key)
  let at = turn.value("endedAt").unwrap_or(Json::null())
  if turn is Null || !(at is Number(_, ..)) || num(at) < since || at == ended {
    return { "ended": ended, "notices": Json::array([]) }
  }
  let missing : Array[Json] = []
  let found : Array[(Map[String, Json], Json)] = []
  for t in db.all("SELECT t.* FROM thread_sessions ts JOIN threads t ON t.id = ts.thread WHERE ts.session = ? AND t.surface = ? ORDER BY ts.joined_at DESC, ts.rowid DESC LIMIT ?", [Json::string(key), Json::string("ember"), Json::number(-1.0)]) {
    if !(field(t, "hidden_at") is Null) {
      continue
    }
    let last = try { Some(last_message(db, field(t, "id"))) } catch {
      Refused(503, m) if m.has_prefix(last_message_pending) => {
        let more : Json = @json.parse(m.view(start_offset=last_message_pending.length()).to_owned()) catch { _ => Json::array([]) }
        if more is Array(xs) {
          missing.append(xs)
        }
        None
      }
      e => raise e
    }
    if last is Some(l) {
      found.push((t, l))
    }
  }
  if missing.length() > 0 {
    raise Refused(503, last_message_pending + Json::array(unique_ids([missing])).stringify())
  }
  let out : Array[Json] = []
  for f in found {
    let (t, last) = f
    let id = field(t, "id")
    let fresh = turn.value("declared") == Some(Json::string("block")) && blocked_fresh(db, id, key, turn)
    guard turn_notice(turn, last, key, word_of(args, "file"), fresh) is Some((kind, text)) else { continue }
    let by = match known.author_names(db, id).name("agent", key) { String(s) => s; _ => "" }
    if notice(db, known, word_of(args, "untitled"), id, last.value("n").unwrap_or(Json::null()), Json::string(key), kind, by, text, None) is Some(n) {
      out.push(n)
    }
  }
  { "ended": at, "notices": Json::array(out) }
}

///|
/// notices.ts `saidNotices`: entries written in one of the station's chats, a person's message and the station's ⚠️.
pub fn said_notices(db : @sql.Db, host : @host.Host, data : String, sep : String, ask : Json) -> Json raise {
  let args = ask.value("args").unwrap_or(Json::null())
  let known = Known::of(host, data, sep, ask)
  let id = args.value("thread").unwrap_or(Json::null())
  let since = num(args.value("since").unwrap_or(Json::null()))
  let entries = match args.value("entries") { Some(Array(es)) => es; _ => [] }
  let fresh = entries.filter(e => e.value("kind") == Some(Json::string("message")) && num(e.value("at").unwrap_or(Json::null())) >= since)
  let person = fresh.filter(e => e.value("authorKind") == Some(Json::string("person"))).last()
  let wrong = fresh
    .filter(e => e.value("authorKind") == Some(Json::string("ember")))
    .filter_map(e => match e.value("text") {
      Some(String(t)) => went_wrong(t).map(w => (e.value("n").unwrap_or(Json::null()), w))
      _ => None
    })
    .last()
  if person is None && wrong is None {
    return Json::array([])
  }
  guard one(db, "SELECT * FROM threads WHERE id = ?", [id]) is Some(t) && field(t, "surface") == Json::string("ember") && field(t, "hidden_at") is Null else {
    return Json::array([])
  }
  guard one(db, "SELECT * FROM thread_sessions WHERE thread = ? ORDER BY joined_at, rowid", [id]) is Some(first) else {
    return Json::array([])
  }
  let session = field(first, "session")
  let untitled = word_of(args, "untitled")
  let out : Array[Json] = []
  if person is Some(p) {
    let author = js_text(p.value("author").unwrap_or(Json::null()))
    let by = match known.author_names(db, id).name("person", author) { String(s) => s; _ => author }
    let text = match p.value("text") {
      Some(String(t)) if !js_blank(t) => t
      _ => word_of(args, "file")
    }
    if notice(db, known, untitled, id, p.value("n").unwrap_or(Json::null()), session, "message", by, text, Some(author)) is Some(n) {
      out.push(n)
    }
  }
  if wrong is Some((n, what)) {
    if notice(db, known, untitled, id, n, session, "failed", "", what, None) is Some(x) {
      out.push(x)
    }
  }
  Json::array(out)
}
