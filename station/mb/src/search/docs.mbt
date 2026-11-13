// What a search looks through of the station's own data (station/src/search/sources.ts `stationDocSteps`): the chats
// and their messages (through the candidate scopes where they are ready: scope-read.ts), the sessions' jobs (through
// the session list for a small workspace: job-scope.ts), the workspaces' memory and skills (read/memory.ts) and the
// profiles, read as they are asked for, each given to `each` as it comes and `pause` called where the worker let other
// searches through.

///|
let batch : Int = 256

///|
fn field(row : Map[String, Json], name : String) -> Json {
  row.get(name).unwrap_or(Json::null())
}

///|
fn text_of(v : Json) -> String? {
  match v {
    String(s) => Some(s)
    _ => None
  }
}

///|
fn num_of(v : Json) -> Double? {
  match v {
    Number(n, ..) => Some(n)
    _ => None
  }
}

///|
fn num(n : Int) -> Json {
  Json::number(n.to_double())
}

///|
fn one(db : @sql.Db, sql : String, params : Array[Json]) -> Map[String, Json]? raise {
  db.all(sql, params).get(0)
}

///|
fn exists(db : @sql.Db, kind : String, name : String) -> Bool raise {
  one(db, "SELECT 1 AS x FROM sqlite_master WHERE type = ? AND name = ?", [Json::string(kind), Json::string(name)]) is Some(_)
}

///|
/// legacy-said-build.ts `hasLegacySaid`.
pub fn has_legacy_said(db : @sql.Db) -> Bool raise {
  if !exists(db, "view", "legacy_said") {
    return false
  }
  if !exists(db, "table", "legacy_said_meta") {
    fail("legacy said view has no metadata")
  }
  guard one(db, "SELECT version, scanned FROM legacy_said_meta WHERE id=1", []) is Some(m) &&
    m.get("version") is Some(Number(1.0, ..)) &&
    m.get("scanned") is Some(Number(0.0, ..) | Number(1.0, ..)) else {
    fail("legacy said view has an unsupported version")
  }
  true
}

///|
fn message_keys(range : String, limit : String, legacy : Bool) -> String {
  let from = if legacy { "legacy_said" } else { "entries INDEXED BY entries_said" }
  let extra = if legacy { "" } else { " AND kind = 'message' AND letter IS NULL" }
  "\n  SELECT n FROM \{from}\n    WHERE thread = ?1 AND \{range}\{extra}\n  UNION ALL\n  SELECT n FROM entries\n    WHERE thread = ?1 AND \{range} AND kind = 'message' AND letter IS NOT NULL\n  ORDER BY n LIMIT \{limit}"
}

///|
fn messages_sql(range : String, limit : String, legacy : Bool) -> String {
  "SELECT * FROM merged WHERE thread = ?1 AND n IN (\{message_keys(range, limit, legacy)}\n) ORDER BY n"
}

///|
fn message_times_sql(range : String, limit : String, legacy : Bool) -> String {
  "SELECT n, at FROM entries WHERE thread = ?1 AND kind = 'message' AND n IN (\{message_keys(range, limit, legacy)}\n) ORDER BY n"
}

///|
/// One search's reading: the store, the data directory, what it was asked, and where its documents go.
pub struct Reading {
  priv db : @sql.Db
  priv host : @host.Host
  priv data : String
  priv sep : String
  priv kinds : Array[String]?
  priv asker : Asker
  priv archived : Bool
  priv words : Array[String]
  priv legacy : Bool
  priv each : (Doc) -> Unit
  priv pause : async () -> Unit
  priv mut scope_pending : Bool
  priv mut session_list_pending : Bool
}

///|
pub fn Reading::new(
  db : @sql.Db,
  host : @host.Host,
  data : String,
  sep : String,
  kinds : Array[String]?,
  asker : Asker,
  archived : Bool,
  words : Array[String],
  each : (Doc) -> Unit,
  pause : async () -> Unit,
) -> Reading raise {
  {
    db,
    host,
    data,
    sep,
    kinds,
    asker,
    archived,
    words,
    legacy: has_legacy_said(db),
    each,
    pause,
    scope_pending: false,
    session_list_pending: false,
  }
}

///|
/// Whether the search found the candidate scopes not ready (the station is asked to prepare them), and the session
/// list.
pub fn Reading::pending(self : Reading) -> (Bool, Bool) {
  (self.scope_pending, self.session_list_pending)
}

///|
fn Reading::wants(self : Reading, kind : String) -> Bool {
  match self.kinds {
    None => true
    Some(ks) => ks.contains(kind)
  }
}

///|
/// A session's row (store.ts getSession), none when it is not there.
fn Reading::session(self : Reading, key : Json) -> Map[String, Json]? raise {
  one(self.db, "SELECT * FROM sessions WHERE key = ?", [key])
}

// ── chats ──

///|
/// What a chat is called (views.ts titleOf, core-ts titles.ts `chatTitle`) in the language the worker read in (zh).
fn title_of(row : Map[String, Json], first_text : String?) -> String {
  let given = (k : String) => match row.get(k) {
    Some(String(s)) => @jscase.trim_white(s)
    _ => ""
  }
  if given("title") != "" {
    return given("title")
  }
  if given("auto_title") != "" {
    return given("auto_title")
  }
  if row.get("surface") is Some(String("chat" | "ember" | "stillfail")) {
    return "新对话"
  }
  let first = without_mentions(first_text.unwrap_or(""))
  for line in first.split("\n") {
    let words = @jscase.split_by(line.to_owned(), @jscase.is_white_space).filter(w => w != "")
    let joined = words.join(" ")
    if joined != "" {
      return joined
    }
  }
  if given("channel").has_prefix("D") {
    return "私信"
  }
  "新对话"
}

///|
/// titles.ts `withoutMentions`: Slack's `<@U123>` taken out.
fn without_mentions(text : String) -> String {
  let out = StringBuilder::new()
  let mut rest = text
  while rest.find("<@") is Some(at) {
    out.write_string(rest.view(end_offset=at).to_owned())
    let after = rest.view(start_offset=at + 2).to_owned()
    let end = after.find(">").unwrap_or(-1)
    let id_ok = end > 0 &&
      after
      .view(end_offset=end)
      .iter()
      .all(c => (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9'))
    if id_ok {
      rest = after.view(start_offset=end + 1).to_owned()
    } else {
      out.write_string("<@")
      rest = after
    }
  }
  out.write_string(rest)
  out.to_string()
}

///|
/// A merged row's JSON column as JSON.parse reads it, none when it does not parse or is empty.
fn parsed(v : Json) -> @jsjson.JValue? {
  match v {
    String(s) if s != "" => Some(@jsjson.parse(s)) catch { _ => None }
    _ => None
  }
}

///|
/// A value read by JSON.parse as the JSON a hit carries.
fn to_json(v : @jsjson.JValue) -> Json {
  match v {
    Null => Json::null()
    Bool(b) => Json::boolean(b)
    Num(n) => Json::number(n)
    Str(s) => Json::string(@jsjson.text(s))
    Arr(xs) => Json::array(xs.map(to_json))
    Obj(fields) => {
      let m : Map[String, Json] = Map([])
      for f in fields {
        m[@jsjson.text(f.0)] = to_json(f.1)
      }
      Json::object(m)
    }
  }
}

///|
/// `{ ...(identity ?? {}), runtime }` as JavaScript spreads it.
fn with_runtime(identity : @jsjson.JValue?, runtime : String) -> Json {
  let m : Map[String, Json] = Map([])
  match identity {
    Some(Obj(_) as o) => if to_json(o) is Object(fields) { for k, v in fields { m[k] = v } }
    Some(Arr(xs)) => for i, x in xs { m[i.to_string()] = to_json(x) }
    Some(Str(units)) => {
      // (a string spreads by its characters, a pair of surrogates one)
      let s = @jsjson.text(units)
      let mut i = 0
      let mut n = 0
      while i < s.length() {
        let c = s.unsafe_charcode_at(i)
        let w = if c >= 0xd800 && c <= 0xdbff && i + 1 < s.length() && s.unsafe_charcode_at(i + 1) >= 0xdc00 && s.unsafe_charcode_at(i + 1) <= 0xdfff { 2 } else { 1 }
        m[n.to_string()] = Json::string(s.view(start_offset=i, end_offset=i + w).to_owned())
        i += w
        n += 1
      }
    }
    _ => ()
  }
  m["runtime"] = Json::string(runtime)
  Json::object(m)
}

///|
/// store.ts `originalRuntime`.
fn Reading::original_runtime(self : Reading, key : Json) -> String? raise {
  let ordered = exists(self.db, "index", "runtime_sessions_ordered")
  let sql = if ordered {
    "SELECT COALESCE(s.original_runtime,\n  (SELECT r.runtime FROM runtime_sessions r INDEXED BY runtime_sessions_ordered WHERE r.session_key = s.key ORDER BY r.at, r.rowid LIMIT 1),\n  s.runtime) AS runtime FROM sessions s WHERE s.key = ?"
  } else {
    "SELECT COALESCE(original_runtime, runtime) AS runtime FROM sessions WHERE key = ?"
  }
  match one(self.db, sql, [key]) {
    Some(r) => text_of(field(r, "runtime"))
    None => None
  }
}

///|
/// sources.ts `threadDocSteps`: a chat's messages, then the chat.
async fn Reading::thread(self : Reading, id : Json) -> Unit {
  guard one(self.db, "SELECT * FROM threads WHERE id = ?", [id]) is Some(row) else { return }
  let members = self.db.all("SELECT session FROM thread_sessions WHERE thread = ? ORDER BY joined_at, rowid", [id])
  let sessions : Array[Map[String, Json]] = []
  for m in members {
    if self.session(field(m, "session")) is Some(s) {
      sessions.push(s)
    }
  }
  let home = match sessions.search_by(s => field(s, "key") == field(row, "home")) {
    Some(i) => Some(sessions[i])
    None => sessions.get(0)
  }
  let ws = match home {
    Some(h) => text_of(field(h, "ws"))
    None => None
  }
  if !sees(ws, None, self.asker) {
    return
  }
  let archived = !(field(row, "hidden_at") is Null) ||
    (sessions.length() > 0 && sessions.iter().all(s => !(field(s, "archived_at") is Null)))
  if self.archived && !archived {
    return
  }
  let surface = if field(row, "surface") == Json::string("ember") { "stillfail" } else { "slack" }
  let first_text = match
    one(
      self.db,
      "SELECT m.text FROM thread_state t JOIN merged m ON m.thread = t.thread AND m.n = t.person_n WHERE t.thread = ?",
      [id],
    ) {
    Some(r) => text_of(field(r, "text"))
    None => None
  }
  let title = title_of(row, first_text)
  let wants_messages = self.wants("message")
  let wants_chat = self.wants("chat")
  let body = if wants_chat {
    let parts : Array[String] = []
    for s in sessions {
      parts.push(text_of(field(s, "title")).unwrap_or(""))
    }
    for s in sessions {
      parts.push(text_of(field(s, "model")).unwrap_or(""))
    }
    parts.filter(w => w != "").join("\n")
  } else {
    ""
  }
  let chat = match sessions.get(0) {
    Some(s) => field(s, "key")
    None => Json::null()
  }
  let refs : Array[(String, Json)] = [
    ("thread", id),
    ("chat", chat),
    ("surface", Json::string(surface)),
    ("archived", Json::boolean(archived)),
  ]
  match field(row, "channel") {
    String(c) if c != "" => refs.push(("channel", Json::string(c)))
    Number(n, ..) if n != 0.0 && !n.is_nan() => refs.push(("channel", Json::number(n)))
    _ => ()
  }
  if !wants_messages && !has(title + "\n" + body, self.words) {
    return
  }
  let end = field(one(self.db, "SELECT MAX(n) AS n FROM entries WHERE thread = ?", [id]).unwrap_or(Map([])), "n")
  let mut after : Json = Json::null()
  let mut last_at : Double? = None
  let origins : Map[String, String?] = Map([])
  let legacy = self.legacy
  while !(end is Null) {
    let first = if wants_messages {
      messages_sql("n <= ?2", "?3", legacy)
    } else {
      message_times_sql("n <= ?2", "?3", legacy)
    }
    let next = if wants_messages {
      messages_sql("n > ?2 AND n <= ?3", "?4", legacy)
    } else {
      message_times_sql("n > ?2 AND n <= ?3", "?4", legacy)
    }
    let rows = if after is Null {
      self.db.all(first, [id, end, num(batch)])
    } else {
      self.db.all(next, [id, after, end, num(batch)])
    }
    if rows.length() == 0 {
      break
    }
    for r in rows {
      let created = if wants_messages { field(r, "created_at") } else { field(r, "at") }
      let at = num_of(created).unwrap_or(0.0)
      last_at = Some(
        match last_at {
          Some(l) => if at > l { at } else { l }
          None => at
        },
      )
      if !wants_messages {
        continue
      }
      let text = text_of(field(r, "text")).unwrap_or("")
      let files : Array[String] = []
      match parsed(field(r, "attachments")) {
        Some(Arr(xs)) =>
          for a in xs {
            if a.get("name") is Some(Str(n)) {
              let name = @jsjson.text(n)
              if name != "" {
                files.push(name)
              }
            }
          }
        _ => ()
      }
      if @jscase.trim(text) == "" && files.length() == 0 {
        continue
      }
      let author_kind = field(r, "author_kind")
      let author = field(r, "author")
      let identity = parsed(field(r, "agent_identity"))
      let mut shown : Json? = match identity {
        Some(v) => Some(to_json(v))
        None => None
      }
      let has_runtime = match identity {
        Some(v) => v.get("runtime") is Some(Str(_))
        None => false
      }
      if author_kind == Json::string("agent") && !has_runtime {
        let a = author.stringify()
        if !origins.contains(a) {
          let found = match self.original_runtime(author) {
            Some(rt) => Some(rt)
            None =>
              match sessions.search_by(s => field(s, "key") == author) {
                Some(i) => text_of(field(sessions[i], "runtime"))
                None => None
              }
          }
          origins[a] = found
        }
        if origins.get(a) is Some(Some(runtime)) && runtime != "" {
          shown = Some(with_runtime(identity, runtime))
        }
      }
      let message_refs : Array[(String, Json)] = [
        ("thread", id),
        ("seq", field(r, "n")),
        ("chat", chat),
        ("chatTitle", Json::string(title)),
        ("surface", Json::string(surface)),
        ("archived", Json::boolean(archived)),
        ("authorKind", author_kind),
        ("author", author),
      ]
      if shown is Some(s) && !(s is Null) && s != Json::boolean(false) && s != Json::number(0.0) && s != Json::string("") {
        message_refs.push(("agentIdentity", s))
      }
      (self.each)({
        key: "m:\{id.stringify()}:\{field(r, "n").stringify()}",
        kind: "message",
        ws,
        scope: None,
        title: "",
        body: if files.length() > 0 { text + "\n" + files.join("\n") } else { text },
        at: num_of(field(r, "created_at")),
        refs: message_refs,
      })
    }
    after = field(rows[rows.length() - 1], "n")
    (self.pause)()
    if rows.length() < batch {
      break
    }
  }
  if wants_chat {
    let at = match last_at {
      Some(a) => Some(a)
      None => num_of(field(row, "created_at"))
    }
    (self.each)({ key: "c:\{id.stringify()}", kind: "chat", ws, scope: None, title, body, at, refs })
  }
}

///|
/// scope-read.ts `readSearchScopePage`: the asker's candidate chats after `after` through `end`, none while the scopes
/// are not ready.
fn Reading::scope_page(self : Reading, after : Json, end : Json) -> Array[Json]? raise {
  self.db.exec("SAVEPOINT search_scope_page")
  defer (self.db.exec("RELEASE search_scope_page") catch { _ => () })
  if !exists(self.db, "table", "search_scope_meta") {
    return None
  }
  guard one(self.db, "SELECT version FROM search_scope_meta WHERE id = 1", []) is Some(v) &&
    v.get("version") is Some(Number(1.0, ..)) else {
    return None
  }
  guard one(
      self.db,
      "SELECT version, threads_done, members_done,\n      EXISTS (SELECT 1 FROM search_scope_sessions_dirty LIMIT 1) OR EXISTS (SELECT 1 FROM search_scope_members_dirty LIMIT 1)\n        OR EXISTS (SELECT 1 FROM search_scope_threads_dirty LIMIT 1) AS dirty FROM search_scope_meta WHERE id = 1",
      [],
    )
    is Some(meta) else {
    return None
  }
  let is1 = (k : String) => meta.get(k) is Some(Number(1.0, ..))
  if !is1("version") || !is1("threads_done") || !is1("members_done") || is1("dirty") {
    return None
  }
  let scopes : Array[(Int, String)] = [(1, self.asker.workspace), (2, "")]
  if self.asker.workspace != "*" {
    scopes.push((1, "*"))
  }
  if self.asker.home {
    scopes.push((0, ""))
  }
  let candidates : Array[Double] = []
  let lim = num(batch)
  for s in scopes {
    let rows = if after is Null {
      self.db.all(
        "SELECT thread FROM search_scope_threads WHERE kind = ?1 AND ws = ?2 AND thread <= ?3\n  ORDER BY thread LIMIT ?4",
        [num(s.0), Json::string(s.1), end, lim],
      )
    } else {
      self.db.all(
        "SELECT thread FROM search_scope_threads WHERE kind = ?1 AND ws = ?2 AND thread > ?3 AND thread <= ?4\n  ORDER BY thread LIMIT ?5",
        [num(s.0), Json::string(s.1), after, end, lim],
      )
    }
    for r in rows {
      if num_of(field(r, "thread")) is Some(t) {
        candidates.push(t)
      }
    }
  }
  if self.asker.home {
    let rows = if after is Null {
      self.db.all("SELECT thread FROM search_scope_orphans WHERE thread <= ?1 ORDER BY thread LIMIT ?2", [end, lim])
    } else {
      self.db.all("SELECT thread FROM search_scope_orphans WHERE thread > ?1 AND thread <= ?2 ORDER BY thread LIMIT ?3", [
        after, end, lim,
      ])
    }
    for r in rows {
      if num_of(field(r, "thread")) is Some(t) {
        candidates.push(t)
      }
    }
  }
  let seen : Set[Double] = Set([])
  let out : Array[Double] = []
  for c in candidates {
    if !seen.contains(c) {
      seen.add(c)
      out.push(c)
    }
  }
  out.sort()
  if out.length() > batch {
    out.truncate(batch)
  }
  Some(out.map(Json::number(_)))
}

///|
/// The chats (and their messages), as `stationDocSteps` walks them.
async fn Reading::threads(self : Reading) -> Unit {
  let end = field(one(self.db, "SELECT MAX(id) AS id FROM threads", []).unwrap_or(Map([])), "id")
  let mut after : Json = Json::null()
  while !(end is Null) {
    let scoped = self.scope_page(after, end)
    if scoped is None {
      self.scope_pending = true
    }
    let ids = match scoped {
      Some(ids) => ids
      None => {
        let rows = if after is Null {
          self.db.all("SELECT id FROM threads WHERE id <= ? ORDER BY id LIMIT ?", [end, num(batch)])
        } else {
          self.db.all("SELECT id FROM threads WHERE id > ? AND id <= ? ORDER BY id LIMIT ?", [after, end, num(batch)])
        }
        rows.map(r => field(r, "id"))
      }
    }
    if ids.length() == 0 {
      break
    }
    for i, id in ids {
      self.thread(id) catch {
        e => {
          let m = describe(e)
          if !(m.contains("no such") || m.contains("archive") || m.contains("ENOENT")) {
            raise e
          }
        }
      }
      if (i + 1) % 128 == 0 && i + 1 < ids.length() {
        (self.pause)()
      }
    }
    after = ids[ids.length() - 1]
    (self.pause)()
    if scoped is None && ids.length() < batch {
      break
    }
  }
}

///|
pub fn describe(e : Error) -> String {
  match e {
    @wire.ShellError(m) => m
    Failure(m) => m
    e => e.to_string()
  }
}

// ── jobs ──

///|
fn job_doc(r : Map[String, Json], key : Json, session : Map[String, Json], thread : Json?) -> Doc {
  let port = field(r, "port")
  // (as `[command, cwd ?? "", port…].filter((w) => w !== "").join("\n")`: a null command kept, joined as nothing)
  let body : Array[String?] = []
  body.push(match field(r, "command") { Null => None; v => Some(js_string(v)) })
  body.push(Some(match field(r, "cwd") { Null => ""; v => js_string(v) }))
  body.push(Some(if port is Null { "" } else { ":" + js_string(port) }))
  let refs : Array[(String, Json)] = [
    ("job", field(r, "id")),
    ("session", key),
    ("chat", key),
    ("state", field(r, "state")),
  ]
  if !(port is Null) {
    refs.push(("port", port))
  }
  if thread is Some(t) {
    refs.push(("thread", t))
  }
  {
    key: "j:" + js_string(field(r, "id")),
    kind: "job",
    ws: text_of(field(session, "ws")),
    scope: None,
    title: js_string(field(r, "name")),
    body: body.filter(w => w != Some("")).map(w => w.unwrap_or("")).join("\n"),
    at: num_of(field(r, "started_at")),
    refs,
  }
}

///|
/// A value as JavaScript makes it a string in a template.
fn js_string(v : Json) -> String {
  match v {
    String(s) => s
    Null => "null"
    True => "true"
    False => "false"
    Number(n, ..) => if n == n.floor() && n.abs() < 1.0e21 { n.to_int64().to_string() } else { n.to_string() }
    v => v.stringify()
  }
}

///|
/// The thread a session's jobs open: its newest still.fail chat (store.ts sessionThreads).
fn Reading::job_thread(self : Reading, key : Json) -> Json? raise {
  for t in
    self.db.all(
      "SELECT t.id FROM thread_sessions ts JOIN threads t ON t.id = ts.thread WHERE ts.session = ? AND t.surface = 'ember' ORDER BY ts.joined_at DESC, ts.rowid DESC LIMIT 1",
      [key],
    ) {
    return Some(field(t, "id"))
  }
  None
}

///|
/// sources.ts `jobDocSteps`.
async fn Reading::session_jobs(self : Reading, key : Json, session : Map[String, Json]) -> Unit {
  let end = field(
    one(self.db, "SELECT MAX(rowid) AS n FROM jobs INDEXED BY jobs_by_session WHERE session_key = ?", [key]).unwrap_or(
      Map([]),
    ),
    "n",
  )
  if end is Null {
    return
  }
  let thread = self.job_thread(key)
  let mut current = session
  let mut after : Json = Json::null()
  while true {
    let rows = if after is Null {
      self.db.all(
        "SELECT rowid AS seq, id, name, command, cwd, port, state, started_at FROM jobs WHERE session_key = ? AND rowid <= ? ORDER BY rowid LIMIT ?",
        [key, end, num(batch)],
      )
    } else {
      self.db.all(
        "SELECT rowid AS seq, id, name, command, cwd, port, state, started_at FROM jobs WHERE session_key = ? AND rowid > ? AND rowid <= ? ORDER BY rowid LIMIT ?",
        [key, after, end, num(batch)],
      )
    }
    if rows.length() == 0 {
      return
    }
    for r in rows {
      (self.each)(job_doc(r, key, current, thread))
    }
    after = field(rows[rows.length() - 1], "seq")
    (self.pause)()
    guard self.session(key) is Some(latest) && sees(text_of(field(latest, "ws")), None, self.asker) else {
      fail("the session changed while searching; search again")
    }
    if rows.length() < batch {
      return
    }
    current = latest
  }
}

///|
fn ascii(s : String) -> Bool {
  s.iter().all(c => c >= ' ' && c <= '~')
}

///|
/// job-scope.ts `smallJobScope`: a small workspace's sessions by the session list, none for the original walk.
fn Reading::small_job_scope(self : Reading, end : String) -> Array[String]? raise {
  if !ascii(self.asker.workspace) || !ascii(end) {
    return None
  }
  self.db.exec("SAVEPOINT search_job_scope")
  defer (self.db.exec("RELEASE search_job_scope") catch { _ => () })
  if !exists(self.db, "table", "session_list_meta") {
    return None
  }
  guard one(self.db, "SELECT version, complete FROM session_list_meta WHERE id = 1", []) is Some(meta) &&
    meta.get("version") is Some(Number(1.0, ..)) else {
    return None
  }
  if !(meta.get("complete") is Some(Number(1.0, ..))) {
    self.session_list_pending = true
    return None
  }
  let scopes : Array[(Int, String)] = [(1, self.asker.workspace)]
  if self.asker.workspace != "*" {
    scopes.push((1, "*"))
  }
  if self.asker.home {
    scopes.push((0, ""))
  }
  let limit = 64
  let keys : Array[String] = []
  let mut read = 0
  let take = (rows : Array[Map[String, Json]]) => {
    read += rows.length()
    if read > limit {
      return false
    }
    for row in rows {
      guard field(row, "session") is String(s) && ascii(s) && field(row, "nul") is Number(0.0, ..) else { return false }
      if !keys.contains(s) {
        keys.push(s)
      }
    }
    true
  }
  for s in scopes {
    let rows = self.db.all(
      "SELECT session, instr(session, char(0)) AS nul FROM session_list_rows WHERE kind = ? AND ws = ?\n  ORDER BY archived, connect, session LIMIT ?",
      [num(s.0), Json::string(s.1), num(limit + 1 - read)],
    )
    if !take(rows) {
      return None
    }
    if s.0 == 1 {
      let rows = self.db.all(
        "SELECT session, instr(session, char(0)) AS nul FROM session_list_rows\n  WHERE kind = 1 AND ws >= (?1 || char(0)) AND ws < (?1 || char(1)) ORDER BY ws, archived, connect, session LIMIT ?2",
        [Json::string(s.1), num(limit + 1 - read)],
      )
      if !take(rows) {
        return None
      }
    }
  }
  if !exists(self.db, "table", "search_job_session_audit") {
    self.session_list_pending = true
    return None
  }
  guard one(self.db, "SELECT version, complete FROM search_job_session_audit WHERE id = 1", []) is Some(audit) &&
    audit.get("version") is Some(Number(1.0, ..)) else {
    return None
  }
  if !(audit.get("complete") is Some(Number(1.0, ..))) {
    self.session_list_pending = true
    return None
  }
  let out = keys.filter(k => compare_units(k, end) <= 0)
  out.sort_by(compare_units)
  Some(out)
}

///|
/// The sessions' jobs, as `stationDocSteps` walks them: by the session list for a small workspace, else seeking each
/// next session in the jobs index (its key as SQLite has it, by its bytes and storage class).
async fn Reading::jobs(self : Reading) -> Unit {
  let position = "session_key, CAST(session_key AS BLOB) AS bytes, typeof(session_key) AS storage"
  guard one(self.db, "SELECT \{position} FROM jobs INDEXED BY jobs_by_session\n      ORDER BY session_key DESC LIMIT 1", []) is Some(end) else {
    return
  }
  let key_of = (row : Map[String, Json]) => field(row, "session_key")
  let scoped = match key_of(end) {
    String(e) => self.small_job_scope(e)
    _ => None
  }
  match scoped {
    Some(keys) =>
      for i, key in keys {
        let k = Json::string(key)
        if one(self.db, "SELECT 1 AS x FROM jobs INDEXED BY jobs_by_session WHERE session_key = ? LIMIT 1", [k]) is Some(_) {
          if self.session(k) is Some(session) && sees(text_of(field(session, "ws")), None, self.asker) {
            self.session_jobs(k, session)
          }
        }
        if (i + 1) % 32 == 0 {
          (self.pause)()
        }
      }
    None => {
      let bound = (row : Map[String, Json], p : String) => if field(row, "storage") == Json::string("text") {
        "CAST(\{p} AS TEXT)"
      } else {
        p
      }
      let value = (row : Map[String, Json]) => if field(row, "storage") == Json::string("text") {
        field(row, "bytes")
      } else {
        field(row, "session_key")
      }
      let mut after : Map[String, Json]? = None
      while true {
        let found = match after {
          None =>
            one(
              self.db,
              "SELECT \{position} FROM jobs INDEXED BY jobs_by_session\n              WHERE session_key <= \{bound(end, "?1")} ORDER BY session_key LIMIT 1",
              [value(end)],
            )
          Some(a) =>
            one(
              self.db,
              "SELECT \{position} FROM jobs INDEXED BY jobs_by_session\n              WHERE session_key > \{bound(a, "?1")} AND session_key <= \{bound(end, "?2")}\n              ORDER BY session_key LIMIT 1",
              [value(a), value(end)],
            )
        }
        guard found is Some(row) else { break }
        after = Some(row)
        let k = key_of(row)
        if self.session(k) is Some(session) && sees(text_of(field(session, "ws")), None, self.asker) {
          self.session_jobs(k, session)
        }
        (self.pause)()
      }
    }
  }
}

// ── memory, skills, profiles ──

///|
/// A file's text (`strict`: as std::fs::read_to_string, none when not UTF-8).
fn Reading::read(self : Reading, path : String, strict : Bool) -> String? {
  match (try { Ok(self.host.shell_sync("fs.read", { "path": Json::string(path), "strict": Json::boolean(strict) })) } catch { e => Err(e) }) {
    Ok(String(s)) => Some(s)
    _ => None
  }
}

///|
fn Reading::entries(self : Reading, dir : String) -> Array[String]? {
  match (try { Ok(self.host.shell_sync("fs.readdir", { "path": Json::string(dir) })) } catch { e => Err(e) }) {
    Ok(Array(names)) => Some(names.filter_map(n => if n is String(s) { Some(s) } else { None }))
    _ => None
  }
}

///|
/// Rust's Path::join (ops/paths.ts joinPath): an absolute path replaces, nothing normalised.
fn Reading::joined(self : Reading, a : String, b : String) -> String {
  let absolute = b.has_prefix("/") ||
    (self.sep == "\\" && (b.has_prefix("\\") || (b.length() >= 2 && b.unsafe_charcode_at(1) == ':')))
  if absolute {
    b
  } else if a == "" || a.has_suffix("/") || (self.sep == "\\" && a.has_suffix("\\")) {
    a + b
  } else {
    a + self.sep + b
  }
}

///|
/// config.json as JSON.parse reads it ({} when it does not).
fn Reading::config(self : Reading) -> @jsjson.JValue {
  match self.read(self.joined(self.data, "config.json"), false) {
    Some(text) => @jsjson.parse(text) catch { _ => Obj([]) }
    None => Obj([])
  }
}

///|
fn jstr(v : @jsjson.JValue?) -> String? {
  match v {
    Some(Str(s)) => Some(@jsjson.text(s))
    _ => None
  }
}

///|
/// The agents' home (memory.ts `agentHome`).
fn Reading::agent_home(self : Reading, raw : @jsjson.JValue) -> String {
  self.joined(self.data, jstr(raw.get("agentHome")).unwrap_or("agent"))
}

///|
fn workspace_id(name : String) -> Bool {
  name.length() >= 1 &&
  name.length() <= 128 &&
  name.iter().all(c => (c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '_' || c == '-')
}

///|
/// memory.ts `front`: a SKILL.md's frontmatter field.
fn front(text : String, key : String) -> String? {
  if !text.has_prefix("---\n") {
    return None
  }
  let body = text.view(start_offset=4).to_owned()
  guard body.find("\n---") is Some(end) else { return None }
  for raw in body.view(end_offset=end).to_owned().split("\n") {
    let line = if raw.has_suffix("\r") { raw.view(end_offset=raw.length() - 1).to_owned() } else { raw.to_owned() }
    if line.has_prefix(key + ":") {
      let v = @jscase.trim(line.view(start_offset=key.length() + 1).to_owned())
      let mut s = 0
      let mut e = v.length()
      while s < e && v.unsafe_charcode_at(s) == '"' {
        s += 1
      }
      while e > s && v.unsafe_charcode_at(e - 1) == '"' {
        e -= 1
      }
      return Some(v.view(start_offset=s, end_offset=e).to_owned())
    }
  }
  None
}

///|
/// Strings by their UTF-8 bytes (Rust's order): the same as by code points.
fn compare_bytes(a : String, b : String) -> Int {
  let x = a.iter().collect()
  let y = b.iter().collect()
  let n = if x.length() < y.length() { x.length() } else { y.length() }
  for i in 0..<n {
    let d = x[i].to_int() - y[i].to_int()
    if d != 0 {
      return d
    }
  }
  x.length() - y.length()
}

///|
let builtin_skills : Array[String] = [
  "stillfail-chats", "stillfail-jobs", "stillfail-show", "stillfail-viz", "stillfail-browser", "stillfail-login", "stillfail-vault",
  "stillfail-cron", "stillfail-github-ci", "stillfail-feedback",
]

///|
/// A workspace's memory and skills as documents (sources.ts `memoryDocs`, memory.ts `memory`): `ws` None the home one.
fn Reading::memory_docs(self : Reading, raw : @jsjson.JValue, ws : String?) -> Array[Doc] {
  let home = match ws {
    None => self.agent_home(raw)
    Some(w) => self.joined(self.joined(self.agent_home(raw), "workspaces"), w)
  }
  let path = self.joined(home, "MEMORY.md")
  let docs : Array[Doc] = []
  let text = self.read(path, true).unwrap_or("")
  let wsj = ws.unwrap_or("")
  if @jscase.trim(text) != "" {
    docs.push({
      key: "k:\{wsj}:",
      kind: "memory",
      ws,
      scope: None,
      title: "MEMORY.md",
      body: text,
      at: None,
      refs: [("path", Json::string(path))],
    })
  }
  let dir = self.joined(home, "skills")
  let skills : Array[(String, String, Bool, Bool, String, Array[(String, String)])] = []
  for name in self.entries(dir).unwrap_or([]) {
    guard self.read(self.joined(self.joined(dir, name), "SKILL.md"), true) is Some(text) else { continue }
    let description = front(text, "description").unwrap_or("")
    let builtin = builtin_skills.contains(name)
    let files : Array[(String, String)] = []
    let names = self
      .entries(self.joined(dir, name))
      .unwrap_or([])
      .filter(n => n.has_suffix(".md") && n != "SKILL.md" && !n.has_prefix("SKILL.conflict-"))
    names.sort_by(compare_bytes)
    for f in names {
      if self.read(self.joined(self.joined(dir, name), f), true) is Some(t) {
        files.push((f, t))
      }
    }
    skills.push((name, description, description.has_prefix("项目记忆："), builtin, text, files))
  }
  skills.sort_by((a, b) => {
    let x = (if a.3 { 1 } else { 0 }) - (if b.3 { 1 } else { 0 })
    if x != 0 {
      return x
    }
    let y = (if !a.2 { 1 } else { 0 }) - (if !b.2 { 1 } else { 0 })
    if y != 0 {
      return y
    }
    compare_bytes(a.0, b.0)
  })
  for k in skills {
    let (name, description, project, builtin, text, files) = k
    let parts = [description, text]
    for f in files {
      parts.push(f.0 + "\n" + f.1)
    }
    docs.push({
      key: "k:\{wsj}:\{name}",
      kind: "skill",
      ws,
      scope: None,
      title: name,
      body: parts.join("\n"),
      at: None,
      refs: [
        ("skill", Json::string(name)),
        ("description", Json::string(description)),
        ("builtin", Json::boolean(builtin)),
        ("project", Json::boolean(project)),
      ],
    })
  }
  docs
}

///|
/// The workspaces with memory of their own (sources.ts `memoryWorkspaces`), in the directory's order.
fn Reading::memory_workspaces(self : Reading, raw : @jsjson.JValue) -> Array[String] {
  self.entries(self.joined(self.agent_home(raw), "workspaces")).unwrap_or([]).filter(workspace_id)
}

///|
/// The profiles as documents (sources.ts `profileDocs` over `profilesOf`).
fn Reading::profile_docs(self : Reading, raw : @jsjson.JValue) -> Array[Doc] {
  let docs : Array[Doc] = []
  guard raw.get("profiles") is Some(Arr(profiles)) else { return docs }
  for p in profiles {
    guard jstr(p.get("id")) is Some(id) && jstr(p.get("home")) is Some(_) else { continue }
    let runtime = jstr(p.get("runtime")).unwrap_or("")
    let model = jstr(p.get("model"))
    let name = jstr(p.get("name"))
    let access = p.get("access")
    let access_field = (k : String) => match access {
      Some(Obj(_) as a) => jstr(a.get(k)).unwrap_or("")
      _ => ""
    }
    let body = [id, runtime, model.unwrap_or(""), access_field("kind"), access_field("provider")].filter(w => w != "").join("\n")
    docs.push({
      key: "p:\{id}",
      kind: "profile",
      ws: Some("*"),
      scope: None,
      title: name.unwrap_or(id),
      body,
      at: None,
      refs: [("profile", Json::string(id)), ("runtime", Json::string(runtime))],
    })
  }
  docs
}

///|
/// All the kinds asked for (sources.ts `stationDocSteps`), in its order.
pub async fn Reading::run(self : Reading) -> Unit {
  if self.wants("chat") || self.wants("message") {
    self.threads()
  }
  if self.wants("job") {
    self.jobs()
  }
  if self.wants("skill") || self.wants("memory") {
    let raw = self.config()
    let places : Array[String?] = [None]
    for w in self.memory_workspaces(raw) {
      places.push(Some(w))
    }
    for ws in places {
      if sees(ws, None, self.asker) {
        for d in self.memory_docs(raw, ws) {
          if self.wants(d.kind) {
            (self.each)(d)
          }
        }
      }
      (self.pause)()
    }
  }
  if self.wants("profile") {
    for d in self.profile_docs(self.config()) {
      (self.each)(d)
    }
  }
}
