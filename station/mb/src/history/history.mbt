// What the words find in the execution histories an asker may see (station/src/search/sources.ts `historyHits`): the
// most recently active sessions first and each one's latest steps first, until a page and one more are found or the
// time is up; a session's transcripts read (their entries numbered as its history page numbers them) only when they
// have every word (`mentions`), each a part at a time through the shell (`text.*`).

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
/// A search of the histories: the store, the shell, the data directory, its words and asker, how long it may take.
pub struct Histories {
  priv db : @sql.Db
  priv host : @host.Host
  priv data : String
  priv sep : String
  priv finder : @locate.Finder
  priv words : Array[String]
  priv asker : @search.Asker
  priv limit : Int
  priv offset : Int
  priv until : Int64
  priv cancelled : () -> Bool
  priv pause : async () -> Unit
  priv mut stopped : Bool
  priv mut expired : Bool
}

///|
pub fn Histories::new(
  db : @sql.Db,
  host : @host.Host,
  data : String,
  sep : String,
  finder : @locate.Finder,
  words : Array[String],
  asker : @search.Asker,
  limit : Int,
  offset : Int,
  ms : Int,
  cancelled : () -> Bool,
  pause : async () -> Unit,
) -> Histories {
  {
    db,
    host,
    data,
    sep,
    finder,
    words,
    asker,
    limit,
    offset,
    until: @host.now() + ms.to_int64(),
    cancelled,
    pause,
    stopped: false,
    expired: false,
  }
}

///|
/// sources.ts `historyHits`' `keep`.
fn Histories::keep(self : Histories) -> Bool {
  if self.stopped || self.expired {
    return false
  }
  if (self.cancelled)() {
    self.stopped = true
  } else if @host.now() > self.until {
    self.expired = true
  }
  !self.stopped && !self.expired
}

///|
fn Histories::visible(self : Histories, ws : Json) -> Bool {
  @search.sees(text_of(ws), None, self.asker)
}

///|
fn Histories::check_visible(self : Histories, key : Json) -> Unit raise {
  guard self.db.all("SELECT ws FROM sessions WHERE key = ?", [key]).get(0) is Some(row) && self.visible(field(row, "ws")) else {
    fail("the session changed while searching; search again")
  }
}

///|
/// The profiles config.json names, their homes under the data directory when relative (sources.ts `profilesOf`).
fn Histories::profiles(self : Histories) -> Array[(String, String)] {
  let raw = match
    (try { Ok(self.host.shell_sync("fs.read", { "path": Json::string(self.data + self.sep + "config.json"), "strict": false })) } catch { e => Err(e) }) {
    Ok(String(text)) => @jsjson.parse(text) catch { _ => @jsjson.JValue::Obj([]) }
    _ => Obj([])
  }
  let out = []
  guard raw.get("profiles") is Some(Arr(ps)) else { return out }
  for p in ps {
    guard p.get("id") is Some(Str(id)) && p.get("home") is Some(Str(home)) else { continue }
    let home = @jsjson.text(home)
    let absolute = home.has_prefix("/") ||
      (self.sep == "\\" && (home.has_prefix("\\") || (home.length() >= 2 && home.unsafe_charcode_at(1) == ':')))
    out.push((@jsjson.text(id), if absolute { home } else { @nodepath.join(self.sep, [self.data, home]) }))
  }
  out
}

///|
/// sources.ts `transcriptFiles`: a session's transcripts and their runtimes, none when it has no runtime session.
async fn Histories::files(
  self : Histories,
  key : Json,
  places : Array[String],
  profiles : Array[(String, String)],
) -> Array[(String, String)]? {
  let sources = @locate.history_sources(self.db, key)
  let paths = []
  let mut visited = 0
  let mut any = false
  for source in sources {
    if !self.keep() {
      return None
    }
    if source is Some(s) {
      any = true
      let (found, _) = self.finder.sources(self.data, profiles, [s], places, anywhere=true)
      for p in found {
        paths.push(p)
      }
    }
    visited += 1
    if visited % 64 == 0 {
      (self.pause)()
      if !self.keep() {
        return None
      }
      self.check_visible(key)
    }
  }
  if any {
    Some(paths)
  } else {
    None
  }
}

///|
/// A file read a part at a time through the shell (`lines`: whole lines, as counter.ts `readFrom`), each part given to
/// `each` until it says to stop; whether it was there.
async fn Histories::parts(self : Histories, path : String, lines : Bool, each : async (String) -> Bool) -> Bool {
  let opened = self.host.shell_sync("text.open", { "path": Json::string(path), "lines": Json::boolean(lines) }) catch {
    _ => return false
  }
  guard opened is { "id": id, .. } else { return false }
  defer (self.host.shell_sync("text.close", { "id": id }) catch { _ => Json::null() }) |> ignore
  while true {
    let part = self.host.shell_sync("text.next", { "id": id }) catch { _ => break }
    guard part is String(text) else { break }
    if !each(text) {
      break
    }
  }
  true
}

///|
/// sources.ts `finder`: whether a part has a word, as written or as JSON writes it; ASCII's case aside, a word cased
/// beyond ASCII always (its entries decide).
fn finds(word : String) -> (String) -> Bool {
  let escaped = @jsjson.stringify(Str(@jsjson.units(word)))
  let json = escaped.view(start_offset=1, end_offset=escaped.length() - 1).to_owned()
  let forms = if json == word { [word] } else { [word, json] }
  if word.iter().all(c => c.to_int() < 0x80) {
    let lowered = forms.map(ascii_lower)
    return text => {
      let t = ascii_lower(text)
      lowered.iter().any(f => t.contains(f))
    }
  }
  if @jscase.has_cases(word) {
    return _ => true
  }
  text => forms.iter().any(f => text.contains(f))
}

///|
fn ascii_lower(s : String) -> String {
  let out = StringBuilder::new()
  for c in s {
    out.write_char(if c >= 'A' && c <= 'Z' { (c.to_int() + 32).unsafe_to_char() } else { c })
  }
  out.to_string()
}

///|
/// How much of the part before a part is kept to find a word across the two (sources.ts OVERLAP).
let overlap : Int = 1024

///|
/// sources.ts `mentions`: whether a transcript has every word anywhere in it.
async fn Histories::mentions(self : Histories, path : String) -> Bool {
  let left = self.words.map(finds)
  if !self.keep() {
    return false
  }
  let mut tail = ""
  let mut found = false
  ignore(
    self.parts(path, false, text => {
      if !self.keep() {
        return false
      }
      let view = tail + text
      let mut i = 0
      while i < left.length() {
        if (left[i])(view) {
          left.remove(i) |> ignore
        } else {
          i += 1
        }
      }
      if left.length() == 0 {
        found = true
        return false
      }
      tail = if view.length() > overlap { view.view(start_offset=view.length() - overlap).to_owned() } else { view }
      (self.pause)()
      self.keep()
    }),
  )
  found && self.keep()
}

///|
/// sources.ts `entriesOf`: a transcript's entries, each given to `each` as it is read.
async fn Histories::entries(self : Histories, runtime : String, path : String, each : (Entry) -> Unit) -> Unit {
  let state = ReadState::new()
  let out : Array[Entry] = []
  let mut failed : Error? = None
  ignore(
    self.parts(path, true, text => {
      for raw in text.split("\n") {
        if !self.keep() {
          return false
        }
        let line = if raw.has_suffix("\r") { raw.view(end_offset=raw.length() - 1).to_owned() } else { raw.to_owned() }
        if line == "" {
          continue
        }
        let record = @jsjson.parse(line) catch { _ => continue }
        timeline_of(runtime, record, state, out) catch {
          e => {
            failed = Some(e)
            return false
          }
        }
        for e in out {
          if !self.keep() {
            return false
          }
          each(e)
        }
        out.clear()
      }
      true
    }),
  )
  if failed is Some(e) {
    // (an entry JavaScript cannot make, a date past its range, fails the search as it does there)
    fail(@search.describe(e))
  }
}

///|
/// sources.ts `historyText`: what of an entry is looked through.
fn history_text(e : Entry) -> String? {
  match e.kind {
    "assistant" | "thinking" => Some(e.text)
    "tool_call" => {
      let tool = e.tool.unwrap_or("")
      let tool = if tool.has_prefix("mcp__stillfail__") {
        tool.view(start_offset=16).to_owned()
      } else if tool.has_prefix("mcp__ember__") {
        tool.view(start_offset=12).to_owned()
      } else {
        tool
      }
      if tool == "chat_post" || tool == "chat_state" {
        None
      } else {
        Some(tool + "\n" + e.text)
      }
    }
    "tool_result" => if @jscase.trim(e.text) == "" { None } else { Some(e.text) }
    _ => None
  }
}

///|
priv struct Step {
  i : Int
  entry : String
  tool : String?
  at : Double?
  text : String
}

///|
/// The history group (sources.ts `historyGroup`), none when nothing was found and nothing left.
pub async fn Histories::group(self : Histories) -> Json? {
  let (hits, more, left) = self.hits()
  if hits.length() == 0 && left == 0 {
    return None
  }
  let g : Map[String, Json] = { "kind": Json::string("history"), "hits": Json::array(hits), "more": Json::boolean(more) }
  if left > 0 {
    g["left"] = Json::number(left.to_double())
  }
  Some(Json::object(g))
}

///|
async fn Histories::hits(self : Histories) -> (Array[Json], Bool, Int) {
  let want = self.offset + self.limit + 1
  let found : Array[Json] = []
  if (self.cancelled)() {
    fail("the search took too long")
  }
  let table = "history_session_snapshot_mb"
  self.db.exec("DROP TABLE IF EXISTS temp.\{table}")
  ignore(
    self.db.run(
      "CREATE TEMP TABLE \{table} AS WITH RECURSIVE connects(connect) AS (\n  VALUES ((SELECT connect FROM sessions INDEXED BY sessions_by_connect ORDER BY connect LIMIT 1))\n  UNION ALL SELECT (SELECT connect FROM sessions INDEXED BY sessions_by_connect WHERE connect > c.connect ORDER BY connect LIMIT 1)\n    FROM connects c WHERE c.connect IS NOT NULL\n), workspaces(ws) AS (SELECT ?1 UNION SELECT '*' UNION SELECT NULL WHERE ?2)\nSELECT s.key, s.workspace, s.cwd, s.title FROM connects c CROSS JOIN workspaces w CROSS JOIN sessions s INDEXED BY sessions_by_connect\nWHERE c.connect IS NOT NULL AND s.connect = c.connect AND s.ws IS w.ws\nORDER BY s.last_active_at DESC, s.rowid ASC",
      [Json::string(self.asker.workspace), Json::number(if self.asker.home { 1.0 } else { 0.0 })],
    ),
  )
  defer (self.db.exec("DROP TABLE IF EXISTS temp.\{table}") catch { _ => () })
  let sessions = self.db.all("SELECT key, workspace, cwd, title FROM temp.\{table} ORDER BY rowid", [])
  let profiles = self.profiles()
  let hit_sessions : Array[Json] = []
  let finish = (hits : Array[Json], more : Bool, left : Int) => {
    if hit_sessions.length() > 0 {
      let rows = self.db.all("SELECT s.key, s.ws FROM json_each(?) j LEFT JOIN sessions s ON s.key = j.value", [
        Json::string(Json::array(hit_sessions).stringify()),
      ])
      if rows.iter().any(row => field(row, "key") is Null || !self.visible(field(row, "ws"))) {
        fail("the session changed while searching; search again")
      }
    }
    (hits, more, left)
  }
  let page = () => {
    let end = if self.offset + self.limit < found.length() { self.offset + self.limit } else { found.length() }
    if self.offset < end { found.view(start=self.offset, end~).iter().collect() } else { [] }
  }
  let mut looked = 0
  let partial = (current : Json) => {
    if self.stopped {
      fail("the search took too long")
    }
    self.check_visible(current)
    finish(page(), true, sessions.length() - looked)
  }
  for session in sessions {
    let key = field(session, "key")
    if found.length() >= want {
      break
    }
    if !self.keep() {
      return partial(key)
    }
    (self.pause)()
    if !self.keep() {
      return partial(key)
    }
    self.check_visible(key)
    let cwd = text_of(field(session, "cwd"))
    let workspace = text_of(field(session, "workspace")).unwrap_or("")
    let places = match cwd {
      Some(c) if c != workspace => [c, workspace]
      _ => [workspace]
    }
    let files = self.files(key, places, profiles)
    if !self.keep() {
      return partial(key)
    }
    guard files is Some(paths) else {
      looked += 1
      continue
    }
    let mut any = false
    for p in paths {
      if self.mentions(p.0) {
        any = true
      }
      if !self.keep() {
        return partial(key)
      }
      self.check_visible(key)
      if any {
        break
      }
    }
    if !any {
      looked += 1
      continue
    }
    let room = want - found.length()
    let latest : Array[Step] = []
    let mut oldest = 0
    let mut i = 0
    for p in paths {
      self.entries(p.1, p.0, e => {
        if history_text(e) is Some(text) && @search.has(text, self.words) {
          let item = {
            i,
            entry: e.kind,
            tool: e.tool,
            at: match e.at {
              Some(a) => date_parse(a)
              None => None
            },
            text: @search.excerpt(text, self.words),
          }
          if latest.length() < room {
            latest.push(item)
          } else {
            latest[oldest] = item
            oldest = (oldest + 1) % room
          }
        }
        i += 1
      })
      if !self.keep() {
        return partial(key)
      }
      self.check_visible(key)
    }
    // Its newest still.fail chat alone (sources.ts: sessionThreads of the surface, the first).
    let thread_row = self.db.all(
      "SELECT t.id, t.surface, t.title, t.auto_title FROM thread_sessions ts JOIN threads t ON t.id = ts.thread WHERE ts.session = ? AND t.surface = 'ember' ORDER BY ts.joined_at DESC, ts.rowid DESC LIMIT 1",
      [key],
    ).get(0)
    let given = match thread_row {
      Some(t) => {
        let pick = (k : String) => match field(t, k) {
          String(s) => @jscase.trim_white(s)
          _ => ""
        }
        if pick("title") != "" {
          Some(pick("title"))
        } else if pick("auto_title") != "" {
          Some(pick("auto_title"))
        } else {
          None
        }
      }
      None => None
    }
    let chat_title = match given {
      Some(g) => g
      None => @jscase.trim(text_of(field(session, "title")).unwrap_or(""))
    }
    let ordered = if latest.length() < room {
      latest
    } else {
      latest.view(start=oldest).iter().collect() + latest.view(end=oldest).iter().collect()
    }
    if ordered.length() > 0 {
      hit_sessions.push(key)
    }
    ordered.rev_inplace()
    for step in ordered {
      let hit : Map[String, Json] = { "session": key, "index": Json::number(step.i.to_double()), "entry": Json::string(step.entry) }
      if step.tool is Some(t) && t != "" {
        hit["tool"] = Json::string(t)
      }
      hit["chat"] = key
      hit["chatTitle"] = Json::string(chat_title)
      if thread_row is Some(t) {
        hit["thread"] = field(t, "id")
      }
      hit["key"] = Json::string("h:\{text_of(key).unwrap_or(key.stringify())}:\{step.i}")
      hit["kind"] = Json::string("history")
      hit["title"] = Json::string("")
      hit["text"] = Json::string(step.text)
      hit["at"] = match step.at {
        Some(a) => Json::number(a)
        None => Json::null()
      }
      found.push(Json::object(hit))
    }
    looked += 1
    if found.length() >= want {
      break
    }
  }
  finish(page(), found.length() > self.offset + self.limit, 0)
}

///|
/// One search asked of the program (search/worker.ts `answer`): what the station's data has, then, when asked for, the
/// execution histories' group.
pub async fn answer(
  db : @sql.Db,
  host : @host.Host,
  data : String,
  sep : String,
  finder : @locate.Finder,
  told : Json,
  cancelled : () -> Bool,
) -> Array[Json] {
  let groups = @search.answer(db, host, data, sep, told, cancelled)
  let query = match told {
    { "query": String(q), .. } => q
    _ => ""
  }
  let words = @search.terms(query)
  let wants = match told {
    { "kinds": Array(ks), .. } => ks.contains(Json::string("history"))
    _ => false
  }
  if words.length() == 0 || !wants {
    return groups
  }
  let histories = Histories::new(
    db,
    host,
    data,
    sep,
    finder,
    words,
    @search.Asker::from_json(told.value("asker").unwrap_or(Json::null())),
    @search.clamp_limit(told.value("limit")),
    @search.clamp_offset(told.value("offset")),
    15_000,
    cancelled,
    async fn() { @effect.pause() },
  )
  if histories.group() is Some(g) {
    groups.push(g)
  }
  groups
}
