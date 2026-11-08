// The live view's transcript locator (sessions/live-locator.ts) in live-locator-worker.ts's place: asked to `locate` a
// session, it reads the session and its runtime sessions in one read transaction, then looks for their transcripts a
// batch of 64 at a time, asking the station for its hints of each batch (`hints`) and telling it what it found
// (`batch`), which the station accepts or has looked for again; then `done`. Several are looked for at once, a batch
// each in turn, so a short history is not kept waiting behind a long one; a `cancel` is answered `cancelled`.

///|
let batch_size : Int = 64

///|
/// live-location-protocol.ts's sources of a history are read in pages past this many (store.ts HISTORY_RUNTIME_BATCH);
/// past it, the duplicates of the current one are counted where they were.
let history_batch : Int = 128

///|
priv enum Waiting {
  Hints
  Accepted
}

///|
priv struct Locating {
  id : Json
  profiles : Array[(String, String)]
  places : Array[String]
  sources : Array[Source?]
  identity : Json
  runtime : String
  mut at : Int
  mut visited : Int
  mut batch : Array[Source]
  mut current : Bool
  mut found : (Array[(String, String)], Bool)
  mut waiting : Waiting
}

///|
pub struct Locator {
  priv host : @host.Host
  priv db : @sql.Db
  priv data : String
  priv finder : Finder
  priv running : Map[String, Locating]
}

///|
pub fn Locator::new(host : @host.Host, db : @sql.Db, data : String, sep : String) -> Locator {
  { host, db, data, finder: Finder::new(host, sep), running: Map([]) }
}

///|
fn text(v : Json?) -> String? {
  match v {
    Some(String(s)) => Some(s)
    _ => None
  }
}

///|
fn Locator::say(self : Locator, message : Json) -> Unit {
  self.host.say(message.stringify())
}

///|
fn id_key(id : Json) -> String {
  id.stringify()
}

///|
/// A line from the station: a `locate`, or a reply to one being looked for.
pub fn Locator::heard(self : Locator, line : String) -> Unit {
  let message = @json.parse(line) catch { _ => return }
  guard message is { "type": String(kind), "id": id, .. } else { return }
  let key = id_key(id)
  if kind == "locate" {
    if self.running.contains(key) {
      return
    }
    self.start(id, message) catch {
      e => self.say({ "type": "error", "id": id, "error": Json::string(describe(e)) })
    }
    return
  }
  guard self.running.get(key) is Some(l) else {
    if kind == "cancel" {
      self.say({ "type": "cancelled", "id": id })
    }
    return
  }
  let step = () => {
    match (kind, l.waiting, message) {
      ("cancel", _, _) => {
        self.running.remove(key)
        self.say({ "type": "cancelled", "id": id })
      }
      ("hints", Hints, { "hints": hints, .. }) => {
        self.finder.use_hints(hints)
        l.found = self.finder.sources(self.data, l.profiles, l.batch, l.places)
        let paths : Array[Json] = l.found.0.map(p => { "path": Json::string(p.0), "runtime": Json::string(p.1) })
        l.waiting = Accepted
        self.say({
          "type": "batch",
          "id": id,
          "paths": Json::array(paths),
          "current": Json::boolean(l.found.1),
          "hints": self.finder.hints(),
        })
      }
      ("accepted", Accepted, { "accepted": accepted, .. }) =>
        if accepted is True {
          l.current = l.found.1
          l.batch = []
          self.advance(l)
        } else {
          self.ask_hints(l)
        }
      ("hints", _, _) => fail("expected transcript location acknowledgement")
      _ => fail("expected transcript location hints")
    }
  }
  try step() catch {
    e => {
      self.running.remove(key)
      self.say({ "type": "error", "id": id, "error": Json::string(describe(e)) })
    }
  }
}

///|
fn describe(e : Error) -> String {
  match e {
    @wire.ShellError(m) => m
    Failure(m) => m
    e => e.to_string()
  }
}

///|
/// The session and its runtime sessions, read in one transaction (live-locator-worker.ts `locate`, store.ts
/// `historyRuntimeSources`); then its first batch.
fn Locator::start(self : Locator, id : Json, message : Json) -> Unit raise {
  guard message is { "key": String(key), .. } else { fail("no key") }
  let profiles = match message {
    { "profiles": Array(ps), .. } =>
      ps.filter_map(p => match p {
        { "id": String(pid), "home": String(home), .. } => Some((pid, home))
        _ => None
      })
    _ => []
  }
  self.db.exec("BEGIN")
  let (row, rows) = try {
    let found = self.db.all("SELECT * FROM sessions WHERE key = ?", [Json::string(key)])
    let row = found.get(0)
    let rows = match row {
      Some(r) if text(r.get("runtime")) is Some(runtime) && runtime_kind(runtime) =>
        self.db.all(
          "SELECT r.id, COALESCE(r.runtime, s.original_runtime, s.runtime) AS runtime, r.profile FROM sessions s CROSS JOIN runtime_sessions r ON r.session_key = s.key WHERE s.key = ? ORDER BY r.at, r.rowid",
          [Json::string(key)],
        )
      _ => []
    }
    self.db.exec("COMMIT")
    (row, rows)
  } catch {
    e => {
      self.db.exec("COMMIT") catch { _ => () }
      raise e
    }
  }
  let identity : Json = match row {
    Some(r) if text(r.get("token")) is Some(token) =>
      {
        "runtime": r.get("runtime").unwrap_or(Json::null()),
        "runtimeSessionId": r.get("runtime_session_id").unwrap_or(Json::null()),
        "cwd": r.get("cwd").unwrap_or(Json::null()),
        "workspace": r.get("workspace").unwrap_or(Json::null()),
        "profile": r.get("profile").unwrap_or(Json::null()),
        "ws": r.get("ws").unwrap_or(Json::null()),
        "tokenHash": Json::string(@activity.sha256_hex(@activity.utf8(token))),
      }
    _ => Json::null()
  }
  guard row is Some(r) && text(r.get("runtime")) is Some(runtime) && runtime_kind(runtime) else {
    let runtime = match row {
      Some(r) if text(r.get("runtime")) is Some(rt) && runtime_kind(rt) => Json::string(rt)
      _ => Json::null()
    }
    self.say({ "type": "done", "id": id, "identity": identity, "runtime": runtime, "current": false })
    return
  }
  let current_id = text(r.get("runtime_session_id"))
  let source = (s : Map[String, Json]) => Source::{
    id: text(s.get("id")).unwrap_or(""),
    runtime: text(s.get("runtime")).unwrap_or(""),
    profile: text(s.get("profile")),
  }
  let profile = text(r.get("profile"))
  let sources : Array[Source?] = []
  match current_id {
    None => for s in rows { sources.push(Some(source(s))) }
    Some(cid) => {
      let mut current : Source? = None
      let marked = rows.length() > history_batch
      for s in rows {
        let s = source(s)
        if s.id == cid {
          if current is None {
            current = Some(s)
          }
          if marked {
            sources.push(None)
          }
        } else {
          sources.push(Some(s))
        }
      }
      sources.push(Some(current.unwrap_or({ id: cid, runtime, profile })))
    }
  }
  let cwd = text(r.get("cwd"))
  let workspace = text(r.get("workspace")).unwrap_or("")
  let places = match cwd {
    Some(c) if c != workspace => [c, workspace]
    _ => [workspace]
  }
  let l = {
    id,
    profiles,
    places,
    sources,
    identity,
    runtime,
    at: 0,
    visited: 0,
    batch: [],
    current: false,
    found: ([], false),
    waiting: Hints,
  }
  self.running[id_key(id)] = l
  self.advance(l)
}

///|
/// The next batch's hints asked for, or the end told.
fn Locator::advance(self : Locator, l : Locating) -> Unit {
  while l.at < l.sources.length() {
    if l.sources[l.at] is Some(s) {
      l.batch.push(s)
    }
    l.at += 1
    l.visited += 1
    if l.visited % batch_size == 0 && l.batch.length() > 0 {
      self.ask_hints(l)
      return
    }
  }
  if l.batch.length() > 0 {
    self.ask_hints(l)
    return
  }
  self.running.remove(id_key(l.id))
  self.say({
    "type": "done",
    "id": l.id,
    "identity": l.identity,
    "runtime": Json::string(l.runtime),
    "current": Json::boolean(l.current),
  })
}

///|
fn Locator::ask_hints(self : Locator, l : Locating) -> Unit {
  l.waiting = Hints
  let sources : Array[Json] = l.batch.map(s => {
    "id": Json::string(s.id),
    "runtime": Json::string(s.runtime),
    "profile": match s.profile { Some(p) => Json::string(p); None => Json::null() },
  })
  self.say({ "type": "hints", "id": l.id, "sources": Json::array(sources) })
}
