// The chats of the resources page (station/src/read/usage.ts `resourceChats`: GET /resources): each session's latest
// thread and its title (by the one rule, in the words the pool gives); none for a session of another workspace.

///|
/// usage.ts `resourceChats`.
pub fn resource_chats(db : @sql.Db, host : @host.Host, data : String, sep : String, ask : Json) -> Json raise {
  let args = ask.value("args").unwrap_or(Json::null())
  let known = Known::of(host, data, sep, ask)
  let viewer = match args.value("viewer") { Some(Object(_) as v) => Some(v); _ => None }
  let words = args.value("words").unwrap_or(Json::null())
  let word = (k : String) => match words.value(k) { Some(String(s)) => s; _ => "" }
  let out : Map[String, Json] = Map([])
  let sessions = match args.value("sessions") { Some(Array(xs)) => xs; _ => [] }
  for s in sessions {
    let key = js_text(s)
    if viewer is Some(v) {
      let ws = match one(db, "SELECT ws FROM sessions WHERE key = ?", [s]) { Some(r) => field(r, "ws"); None => Json::null() }
      if !sees(v, ws) {
        out[key] = Json::null()
        continue
      }
    }
    let thread = one(db, "SELECT t.* FROM thread_sessions ts JOIN threads t ON t.id = ts.thread WHERE ts.session = ? ORDER BY ts.joined_at DESC, ts.rowid DESC LIMIT ?", [s, Json::number(1.0)])
    match thread {
      None => out[key] = { "thread": Json::null(), "title": Json::null() }
      Some(t) => {
        let id = field(t, "id")
        let own = field(t, "surface") == Json::string("ember")
        // store.ts `usageThreads`: a thread's first words where it has no name and is not one of the station's own
        let first = if !own && field(t, "title") is Null && field(t, "auto_title") is Null {
          try { first_text(db, id) } catch { _ => Json::null() }
        } else {
          Json::null()
        }
        // usage.ts `threadConnect`: the first of its sessions' connects that is not the station's own
        let connect = match one(db, "SELECT connect FROM thread_sessions WHERE thread = ? AND connect != 'ember' ORDER BY joined_at, rowid LIMIT 1", [id]) {
          Some(r) => match field(r, "connect") { String(c) => Some(c); _ => None }
          None => None
        }
        let channel = if own { Json::null() } else { known.channel(connect, field(t, "channel")) }
        out[key] = { "thread": id, "title": Json::string(chat_title(thread_json(t), first, channel, word("untitled"), word("directMessage"))) }
      }
    }
  }
  Json::object(out)
}
