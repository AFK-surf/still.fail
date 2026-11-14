// A device's reads answered here, not by the station's Node (`--serve <socket>`): the front hands this program each
// request stream of a route Node gave it (client/shell `conn.hand`'s `routes`, station/src/mesh/served.ts), on a socket
// of its own at `socket`: its head (the connection's id and the stream's, a 2 and its index), then the stream's frames
// (client/shell `pipe`: a length and that many bytes, 0xFFFFFFFE its end), and this program's frames back are its
// answer. The request is answered as station/src/mesh/serve.ts `answerRequest` and the admin API answer it (an old
// core told to update, the build a device runs told Node, the read as the route reads it, the answer's headers, zstd
// where it is asked), its read in this process's own snapshot of the database.
//
// Node says on stdin, a line of JSON each: `set` (the words of each language, the floors, the station's build, the
// runtimes there are), `viewer` (a connection's who as its credential and the lock let them in, `null` once it is
// gone; `moved`: its workspace's chain moved), `names` (people's names as their credentials say them), `answered`
// (Node's answer to a request this program gave it). It says on stdout `listening`, `build` (the build a connection's
// device said, once and as it changes) and `fallback` (a request it gives Node to answer: a read refused for what
// Node prepares, a core that does not take every runtime): Node's answer comes back as `answered`.

///|
/// One connection's member, as Node said.
priv struct Member {
  viewer : Json
  moved : Bool
}

///|
priv struct Serving {
  host : @host.Host
  reader : Reader
  mut set : Json
  members : Map[String, Member]
  /// Requests waiting for their connection's who (Node said nothing of it yet): told true once it is said, false
  /// once it is gone.
  waiting : Map[String, Array[@effect.Deferred[Bool]]]
  names : Map[String, String]
  /// The builds said, by connection (told Node only as they change).
  builds : Map[String, Json]
  /// Requests given Node, by their number.
  fallbacks : Map[Int, @effect.Deferred[Json]]
  mut next : Int
  /// The wall's time when Node last said it, and this clock's then.
  mut wall : Int64
  mut at : Int64
}

///|
const PIPE_END : Int = 0xFFFFFFFE

///|
const PIPE_FAILED : Int = 0xFFFFFFFD

///|
/// A frame's bytes at most (client/shell PIPE_MOST).
const PIPE_MOST : Int = 1048576

///|
/// A request's body at most here: what is routed here asks with none.
const BODY_MOST : Int = 65536

///|
pub async fn serve_reads(host : @host.Host, reader : Reader, socket : String) -> Unit {
  let (said, _) = host.shell("unix.listen", { "path": Json::string(socket) }) catch {
    @wire.ShellError(m) => {
      @host.note("serve: not listening at \{socket}: \{m}")
      @host.exit(1)
      return
    }
    e => raise e
  }
  guard said is { "id": listening, .. } else { fail("the shell gave no listening socket") }
  let s : Serving = {
    host,
    reader,
    set: Json::null(),
    members: Map([]),
    waiting: Map([]),
    names: Map([]),
    builds: Map([]),
    fallbacks: Map([]),
    next: 0,
    wall: 0L,
    at: 0L,
  }
  host.say(({ "listening": Json::string(socket) } : Json).stringify())
  ignore(
    host.rt.fork(name="serve told", () => {
      while host.line() is Some(line) {
        s.told(line)
      }
      @host.exit(0)
    }),
  )
  while true {
    let accepted = try { Ok(host.shell("tcp.accept", { "id": listening })) } catch { e => Err(e) }
    guard accepted is Ok(({ "id": id, .. }, _)) else {
      if accepted is Err(e) {
        @host.note("serve: accept failed: \{e}")
        @effect.sleep(100)
      }
      continue
    }
    ignore(host.rt.fork(name="serve stream", () => s.stream(id)))
  }
}

///|
/// A line of Node's.
fn Serving::told(self : Serving, line : String) -> Unit {
  let said = @json.parse(line) catch { _ => return }
  if said is { "wall": Number(n, ..), .. } {
    self.wall = n.to_int64()
    self.at = @host.now()
  }
  match said {
    { "set": set, .. } => self.set = set
    { "viewer": { "conn": conn, "viewer": viewer, .. } as m, .. } => {
      let key = conn.stringify()
      let waiting = self.waiting.get(key).unwrap_or([])
      self.waiting.remove(key)
      if viewer is Null {
        self.members.remove(key)
        self.builds.remove(key)
        for w in waiting {
          ignore(w.succeed(false))
        }
      } else {
        self.members[key] = { viewer, moved: m.value("moved") is Some(True) }
        for w in waiting {
          ignore(w.succeed(true))
        }
      }
    }
    { "names": Array(pairs), .. } =>
      for p in pairs {
        if p is Array([String(email), String(name)]) {
          self.names[email] = name
        }
      }
    { "answered": Number(n, ..), .. } =>
      match self.fallbacks.get(n.to_int()) {
        Some(d) => {
          self.fallbacks.remove(n.to_int())
          ignore(d.succeed(said))
        }
        None => ()
      }
    _ => ()
  }
}

///|
/// The wall's time now, as Node last said it gone on by this clock.
fn Serving::now(self : Serving) -> Int64 {
  self.wall + (@host.now() - self.at)
}

///|
/// What came on a socket, read as it comes.
priv struct Taken {
  host : @host.Host
  id : Json
  mut have : Bytes
  mut ended : Bool
}

///|
/// At least `n` bytes had (false: it ended first).
async fn Taken::need(self : Taken, n : Int) -> Bool {
  while self.have.length() < n {
    if self.ended {
      return false
    }
    let read = try { Ok(self.host.shell("tcp.read", { "id": self.id })) } catch { e => Err(e) }
    match read {
      Ok((said, Some(bytes))) if !(said is { "end": true, .. }) => self.have = self.have + bytes
      _ => self.ended = true
    }
  }
  true
}

///|
fn Taken::take(self : Taken, n : Int) -> Bytes {
  let out = self.have[0:n].to_bytes()
  self.have = self.have[n:].to_bytes()
  out
}

///|
fn be(b : Bytes, at : Int, n : Int) -> Int64 {
  let mut v = 0L
  for i = 0; i < n; i = i + 1 {
    v = (v << 8) | b[at + i].to_int64()
  }
  v
}

///|
fn be32(n : Int) -> Bytes {
  Bytes::from_array(
    FixedArray::from_array([
      ((n >> 24) & 0xFF).to_byte(),
      ((n >> 16) & 0xFF).to_byte(),
      ((n >> 8) & 0xFF).to_byte(),
      (n & 0xFF).to_byte(),
    ]),
  )
}

///|
/// One stream: its request read, answered, written back.
async fn Serving::stream(self : Serving, id : Json) -> Unit {
  self.answer_stream(id)
  ignore(self.host.shell("tcp.close", { "id": id })) catch {
    _ => ()
  }
}

///|
async fn Serving::answer_stream(self : Serving, id : Json) -> Unit {
  let taken : Taken = { host: self.host, id, have: b"", ended: false }
  guard taken.need(25) else { return }
  let head = taken.take(25)
  let conn = Json::number(be(head, 0, 8).to_double())
  // Its frames, up to its end (a request routed here sends its head and no body).
  let body = @buffer.new()
  while true {
    guard taken.need(4) else { return }
    let n = be(taken.take(4), 0, 4).to_int()
    if n == PIPE_END {
      break
    }
    if n == PIPE_FAILED || n > PIPE_MOST || body.length() + n > BODY_MOST {
      return
    }
    guard taken.need(n) else { return }
    body.write_bytes(taken.take(n))
  }
  let sent = body.to_bytes()
  let mut end = -1
  for i = 0; i < sent.length(); i = i + 1 {
    if sent[i] == b'\n' {
      end = i
      break
    }
  }
  guard end >= 0 else { return }
  let asked = @json.parse(@utf8.decode_lossy(sent[0:end])) catch { _ => return }
  let rest = sent[end + 1:].to_bytes()
  // Its who, once Node said who: gone first, nothing is answered (Node closes such a connection).
  let key = conn.stringify()
  if !self.members.contains(key) {
    let d = @effect.Deferred::new()
    match self.waiting.get(key) {
      Some(ws) => ws.push(d)
      None => self.waiting[key] = [d]
    }
    guard d.wait() else { return }
  }
  guard self.members.get(key) is Some(who) else { return }
  let answer = self.answer(conn, who, asked, rest) catch {
    e => {
      @host.note("serve: a request failed: \{e}")
      ({ "status": 500, "headers": { "content-type": "application/json" } }, @utf8.encode("{\"error\":\"read failed\"}"))
    }
  }
  let (said, bytes) = answer
  let out = @buffer.new()
  let line = @utf8.encode(said.stringify() + "\n")
  out.write_bytes(be32(line.length()))
  out.write_bytes(line)
  let mut at = 0
  while at < bytes.length() {
    let n = if bytes.length() - at > PIPE_MOST { PIPE_MOST } else { bytes.length() - at }
    out.write_bytes(be32(n))
    out.write_bytes(bytes[at:at + n].to_bytes())
    at += n
  }
  out.write_bytes(be32(PIPE_END))
  ignore(self.host.shell("tcp.write", { "id": id }, bytes=out.to_bytes())) catch {
    _ => ()
  }
}

///|
/// A header of `headers` by its name, as any case.
fn header(headers : Json, name : String) -> String? {
  guard headers is Object(m) else { return None }
  for k, v in m {
    if k.to_lower() == name && v is String(s) {
      return Some(s)
    }
  }
  None
}

///|
/// api/oldest.ts `buildOf`: the build `0.<m>.<n>` (or `<n>`) says.
fn build_of(said : String?) -> Int? {
  guard said is Some(s) else { return None }
  let s = @jscase.trim_white(s)
  let parts : Array[String] = s.split(".").map(p => p.to_string()).collect()
  let last = match parts.length() {
    1 => parts[0]
    3 if parts[0] == "0" && digits(parts[1]) => parts[2]
    _ => return None
  }
  guard digits(last) && last.length() <= 15 else { return None }
  Some(parse_double(last).to_int())
}

///|
fn digits(s : String) -> Bool {
  s.length() > 0 && s.iter().all(c => c >= '0' && c <= '9')
}

///|
fn int_of(v : Json?) -> Int {
  match v {
    Some(Number(n, ..)) => n.to_int()
    _ => 0
  }
}

///|
/// The answer to one request of `who`'s: its head line (`{status, headers}`) and body.
async fn Serving::answer(self : Serving, conn : Json, who : Member, asked : Json, body : Bytes) -> (Json, Bytes) raise {
  let headers = asked.value("headers").unwrap_or(Json::object(Map([])))
  let lang = match header(headers, "stillfail-lang") {
    Some(l) if l.has_prefix("en") => "en"
    _ => "zh"
  }
  let words = self.set.value("words").unwrap_or(Json::null()).value(lang).unwrap_or(Json::object(Map([])))
  let json = (status : Int, text : String) => (
    ({ "status": Json::number(status.to_double()), "headers": { "content-type": "application/json" } } : Json),
    @utf8.encode(text),
  )
  // A core older than this station answers, and one too old for a workspace whose chain moved (serve.ts).
  let build = build_of(header(headers, "stillfail-build"))
  let counted = int_of(self.set.value("countedFrom"))
  let too_old = match build {
    Some(b) =>
      (b >= counted && b < int_of(self.set.value("oldestCore"))) ||
      (who.moved && b >= counted && b < int_of(self.set.value("movedFromBuild")))
    None => false
  }
  if too_old {
    let text : Json = { "error": words.value("updateApp").unwrap_or(Json::string("")), "update": true }
    return json(426, text.stringify())
  }
  // The build it runs, told Node as it changes (serve.ts `sawBuild`: kept by the device's id in the lock).
  let key = conn.stringify()
  let b : Json = match build {
    Some(n) => Json::number(n.to_double())
    None => Json::null()
  }
  if self.builds.get(key) != Some(b) {
    self.builds[key] = b
    self.host.say(({ "build": { "conn": conn, "build": b } } : Json).stringify())
  }
  // Only a core that takes every runtime (api/runtime-compat.ts): another's answer is Node's to make.
  let runtimes = match header(headers, "stillfail-runtimes") {
    Some(s) => s.split(",").map(r => @jscase.trim_white(r.to_string())).collect()
    None => []
  }
  let every = match self.set.value("runtimes") {
    Some(Array(all)) => all.iter().all(r => r is String(k) && runtimes.contains(k))
    _ => false
  }
  guard every else { return self.fallback(conn, asked, body) }
  let path = match asked.value("path") {
    Some(String(p)) => p
    _ => ""
  }
  let (route, query) = match path.find("?") {
    Some(at) => (path[0:at].to_string(), path[at + 1:].to_string())
    None => (path, "")
  }
  let pairs = query_pairs(query)
  // A session or a chat of another workspace than the member's is none for them (api/seen.ts `elsewhere`).
  if self.elsewhere(route, who.viewer) is Some(m) {
    return self.whole(headers, @utf8.encode(({ "error": Json::string(m) } : Json).stringify()), status=404)
  }
  let read = match route_read(route, pairs, who.viewer, lang) {
    Read(op, args) => (op, args)
    Missing(m) => return self.whole(headers, @utf8.encode(({ "error": Json::string(m) } : Json).stringify()), status=404)
    Not => return self.fallback(conn, asked, body)
  }
  let (op, args) = read
  guard args is Object(a) else { return self.fallback(conn, asked, body) }
  // (the words and the time the pool gives a read: read/pool.ts `wordsIn`; a session's history only its own word)
  if op == "timeline" {
    a["words"] = { "inScriptOutput": words.value("inScriptOutput").unwrap_or(Json::string("")) }
  } else {
    a["words"] = words
    a["now"] = Json::number(self.now().to_double())
  }
  let names = []
  for email, name in self.names {
    names.push(Json::array([Json::string(email), Json::string(name)]))
  }
  let ask : Json = {
    "op": Json::string(op),
    "args": Json::object(a),
    "lang": Json::string(lang),
    "names": Json::array(names),
    "processes": [],
    "clientKeys": [],
  }
  let text = try {
    Ok(self.reader.read(op, ask).stringify())
  } catch {
    @readops.Refused(status, m) => Err((status, m))
    e => raise e
  }
  // Refused: for what the pool prepares first (its `pending`), Node's to answer; else as the admin API says it.
  if text is Err((status, m)) {
    let pending = match self.set.value("pending") {
      Some(Array(all)) => all.iter().any(p => p is String(p) && m.has_prefix(p))
      _ => true
    }
    if pending {
      return self.fallback(conn, asked, body)
    }
    return self.whole(headers, @utf8.encode(({ "error": Json::string(m) } : Json).stringify()), status~)
  }
  guard text is Ok(text) else { return self.fallback(conn, asked, body) }
  self.whole(headers, @utf8.encode(text))
}

///|
/// An answer's head and its body as it goes: the admin API's headers, compressed where the core asks so
/// (mesh/compress.ts: zstd, from 512 bytes, at its level and window).
async fn Serving::whole(self : Serving, asked : Json, bytes : Bytes, status? : Int = 200) -> (Json, Bytes) raise {
  let headers : Map[String, Json] = {
    "content-type": "application/json",
    "cache-control": "no-store",
    "stillfail-idempotent": "1",
    "stillfail-build": self.set.value("build").unwrap_or(Json::string("")),
  }
  let zstd = match header(asked, "accept-encoding") {
    Some(s) => s.split(",").any(e => @jscase.trim_white(e.to_string()) == "zstd")
    None => false
  }
  let status = Json::number(status.to_double())
  if zstd && bytes.length() >= 512 {
    let (_, out) = self.host.shell("zstd.compress", { "level": 3, "window": 20 }, bytes~)
    headers["content-encoding"] = "zstd"
    return ({ "status": status, "headers": Json::object(headers) }, out.unwrap_or(b""))
  }
  headers["content-length"] = Json::string(bytes.length().to_string())
  ({ "status": status, "headers": Json::object(headers) }, bytes)
}

///|
/// A request Node answers, as it would have had the stream (`fallback`, its answer `answered`), compressed here.
async fn Serving::fallback(self : Serving, conn : Json, asked : Json, body : Bytes) -> (Json, Bytes) raise {
  self.next += 1
  let n = self.next
  let d : @effect.Deferred[Json] = @effect.Deferred::new()
  self.fallbacks[n] = d
  self.host.say(
    ({
      "fallback": Json::number(n.to_double()),
      "conn": conn,
      "head": asked,
      "body": Json::string(@utf8.decode_lossy(body)),
    } : Json).stringify(),
  )
  let said = d.wait()
  let status = said.value("status").unwrap_or(Json::number(500.0))
  let headers = match said.value("headers") {
    Some(Object(h)) => h
    _ => Map([])
  }
  let text = match said.value("text") {
    Some(String(t)) => @utf8.encode(t)
    _ => b""
  }
  let zstd = match header(asked.value("headers").unwrap_or(Json::null()), "accept-encoding") {
    Some(s) => s.split(",").any(e => @jscase.trim_white(e.to_string()) == "zstd")
    None => false
  }
  let typed = match headers.get("content-type") {
    Some(String(t)) => t.has_prefix("application/json") || t.has_prefix("text/")
    _ => false
  }
  if zstd && typed && text.length() >= 512 && !headers.contains("content-encoding") {
    let (_, out) = self.host.shell("zstd.compress", { "level": 3, "window": 20 }, bytes=text)
    headers.remove("content-length")
    headers["content-encoding"] = "zstd"
    return ({ "status": status, "headers": Json::object(headers) }, out.unwrap_or(b""))
  }
  if !headers.contains("content-length") && !headers.contains("content-encoding") {
    headers["content-length"] = Json::string(text.length().to_string())
  }
  ({ "status": status, "headers": Json::object(headers) }, text)
}

///|
/// What a route reads: its read and args, a 404 of its own, or not one answered here (given Node).
priv enum Route {
  Read(String, Json)
  Missing(String)
  Not
}

///|
/// admin/mod.rs `segment_decode`, as the routes read a key: a `+` is a `+`.
fn segment(s : String) -> String {
  percent_decode(s.replace_all(old="+", new="%2B"))
}

///|
/// JS's Number() of a thread's id as api/routes/chats.ts takes it (`[+-]?digits`, checked before).
fn signed_number(s : String) -> Double {
  if s.has_prefix("-") {
    -parse_double(s[1:].to_string())
  } else if s.has_prefix("+") {
    parse_double(s[1:].to_string())
  } else {
    parse_double(s)
  }
}

///|
fn signed_digits(s : String) -> Bool {
  if s.has_prefix("-") || s.has_prefix("+") {
    digits(s[1:].to_string())
  } else {
    digits(s)
  }
}

///|
/// api/seen.ts `elsewhere`: the 404 a request is answered with when the session or chat its path names is there but of
/// another workspace than the member's (rows.ts `sees`); None otherwise.
fn Serving::elsewhere(self : Serving, route : String, viewer : Json) -> String? raise {
  let parts : Array[String] = route.split("/").map(p => p.to_string()).collect()
  guard parts.length() >= 5 && parts[1] == "admin" && parts[2] == "api" else { return None }
  let id = segment(parts[4])
  let sees = (ws : Json) => match ws {
    String(_) => ws == viewer.value("workspace").unwrap_or(Json::null())
    _ => !(viewer.value("home") is Some(False))
  }
  let db = self.reader.db_now()
  match parts[3] {
    "sessions" =>
      match db.all("SELECT ws FROM sessions WHERE key = ?", [Json::string(id)]) {
        [row, ..] if !sees(row.get("ws").unwrap_or(Json::null())) => Some("unknown session \{id}")
        _ => None
      }
    "threads" => {
      guard signed_digits(id) else { return None }
      let n = signed_number(id)
      guard n.abs() <= 9007199254740991.0 else { return None }
      guard db.all("SELECT 1 AS x FROM threads WHERE id = ?", [Json::number(n)]) is [_, ..] else { return None }
      let members = db.all("SELECT s.ws AS ws FROM thread_sessions t LEFT JOIN sessions s ON s.key = t.session WHERE t.thread = ?", [
        Json::number(n),
      ])
      let seen = if members.is_empty() {
        sees(Json::null())
      } else {
        members.iter().any(m => sees(m.get("ws").unwrap_or(Json::null())))
      }
      if seen {
        None
      } else {
        Some("unknown thread \{id}")
      }
    }
    _ => None
  }
}

///|
/// The routes answered here and what each reads, as api/routes/chats.ts and sessions.ts read them.
fn route_read(route : String, pairs : Array[(String, String)], viewer : Json, lang : String) -> Route {
  let parts : Array[String] = route.split("/").map(p => p.to_string()).collect()
  guard parts.length() >= 4 && parts[0] == "" && parts[1] == "admin" && parts[2] == "api" else { return Not }
  let param = (name : String) => {
    for p in pairs {
      if p.0 == name {
        return Some(p.1)
      }
    }
    None
  }
  // (what a route says only where it is asked: undefined in the TypeScript's args)
  let given = (args : Map[String, Json], names : Array[String]) => {
    for n in names {
      if param(n) is Some(v) {
        args[n] = Json::string(v)
      }
    }
  }
  let l = Json::string(lang)
  match parts[3:] {
    ["chats"] =>
      match chats_read(pairs, viewer) {
        Some((op, args)) => Read(op, args)
        None => Not
      }
    ["sessions"] =>
      Read("sessions", {
        "connect": match param("connect") {
          Some(c) => Json::string(c)
          None => Json::null()
        },
        "archived": Json::boolean(param("archived") == Some("1")),
        "lang": l,
        "viewer": viewer,
      })
    ["sessions", key] => {
      let args : Map[String, Json] = { "key": Json::string(segment(key)), "viewer": viewer, "lang": l }
      given(args, ["turns", "jobs"])
      Read("session", Json::object(args))
    }
    ["sessions", key, "timeline"] => {
      let args : Map[String, Json] = { "key": Json::string(segment(key)), "lang": l }
      given(args, ["before", "limit", "from", "to", "brief", "after"])
      Read("timeline", Json::object(args))
    }
    ["threads"] =>
      Read("threads", {
        "viewer": viewer,
        "session": match param("session") {
          Some(c) => Json::string(c)
          None => Json::null()
        },
        "lang": l,
      })
    ["threads", id] => Read("thread", { "id": Json::string(segment(id)), "viewer": viewer, "lang": l })
    ["threads", id, ("entries" | "letters") as which] => {
      // (a thread id is an i64 in the Rust route; one that is no number is no thread)
      guard signed_digits(id) else { return Missing("unknown thread \{id}") }
      let params = pairs.map(p => Json::array([Json::string(p.0), Json::string(p.1)]))
      Read(which.to_string(), { "viewer": viewer, "thread": Json::number(signed_number(id)), "params": Json::array(params) })
    }
    _ => Not
  }
}

///|
/// api/routes/chats.ts's GET /chats: the read and its args for that query.
fn chats_read(pairs : Array[(String, String)], viewer : Json) -> (String, Json)? {
  let param = (name : String) => {
    for p in pairs {
      if p.0 == name {
        return Some(p.1)
      }
    }
    None
  }
  let all = (name : String) => pairs.filter(p => p.0 == name).map(p => Json::string(p.1))
  let some = pairs.iter().any(p => p.0 == "session" || p.0 == "thread")
  let threads = pairs
    .filter(p => p.0 == "thread" && digits(p.1))
    .map(p => Json::number(parse_double(p.1)))
  let sessions = all("session")
  let scoped : Json = { "viewer": viewer, "sessions": Json::array(sessions), "threads": Json::array(threads) }
  if param("marks") == Some("1") {
    let scope : Json = if some {
      { "sessions": Json::array(sessions), "threads": Json::array(threads) }
    } else {
      Json::null()
    }
    return Some(("chatMarks", { "viewer": viewer, "scope": scope }))
  }
  if param("shared") == Some("1") {
    return Some(("sharedChats", if some { scoped } else { { "viewer": viewer, "sessions": Json::null(), "threads": Json::null() } }))
  }
  if some {
    return Some(("chatRows", scoped))
  }
  let args : Map[String, Json] = { "viewer": viewer, "archived": Json::boolean(param("archived") == Some("1")) }
  if param("page") is Some(p) {
    args["page"] = Json::string(p)
  }
  Some(("chats", Json::object(args)))
}


///|
/// api/request.ts `queryPairs`: `&`-separated, each `name=value` percent-decoded.
fn query_pairs(query : String) -> Array[(String, String)] {
  let out = []
  for part in query.split("&") {
    let p = part.to_string()
    if p == "" {
      continue
    }
    match p.find("=") {
      Some(at) => out.push((percent_decode(p[0:at].to_string()), percent_decode(p[at + 1:].to_string())))
      None => out.push((percent_decode(p), ""))
    }
  }
  out
}

///|
/// api/request.ts `percentDecode`: `%xx` a byte, `+` a space, the rest as it is; then UTF-8, lossily.
fn percent_decode(s : String) -> String {
  let bytes = @utf8.encode(s)
  let out = @buffer.new()
  let hex = (b : Byte) => {
    let c = b.to_int()
    if c >= 48 && c <= 57 {
      c - 48
    } else if c >= 97 && c <= 102 {
      c - 87
    } else if c >= 65 && c <= 70 {
      c - 55
    } else {
      -1
    }
  }
  let mut i = 0
  while i < bytes.length() {
    let b = bytes[i]
    if b == b'%' && i + 2 < bytes.length() + 0 && i + 2 <= bytes.length() - 1 && hex(bytes[i + 1]) >= 0 && hex(bytes[i + 2]) >= 0 {
      out.write_byte((hex(bytes[i + 1]) * 16 + hex(bytes[i + 2])).to_byte())
      i += 3
    } else {
      out.write_byte(if b == b'+' { b' ' } else { b })
      i += 1
    }
  }
  @utf8.decode_lossy(out.to_bytes())
}

///|
/// The number its digits say (they are digits only: `digits`), as JS's Number() reads them.
fn parse_double(s : String) -> Double {
  let mut v = 0.0
  for c in s {
    v = v * 10.0 + (c.to_int() - 48).to_double()
  }
  v
}

///|
/// The connection reads are made on (made at the first, as `read` makes it).
fn Reader::db_now(self : Reader) -> @sql.Db raise {
  match self.reading {
    Some(db) => db
    None => {
      let db = @sql.Db::attach(self.host, self.db, wait=5000)
      self.reading = Some(db)
      db
    }
  }
}
