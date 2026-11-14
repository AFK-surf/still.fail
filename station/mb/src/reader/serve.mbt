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
  /// What Node says of an answer it makes as it comes (`chunk`, then `done`: None), by the request's number.
  streams : Map[Int, @effect.Queue[String?]]
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
/// A request's body at most here (a batch's is under a megabyte: admin.ts `batch`).
const BODY_MOST : Int = 1048576

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
    streams: Map([]),
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
    { "chunk": Number(n, ..), "text": String(t), .. } =>
      match self.streams.get(n.to_int()) {
        Some(q) => ignore(q.try_offer(Some(t)))
        None => ()
      }
    // (one piece told several of its streams at once, given once: served.ts `#piece`)
    { "pieces": String(t), "to": Array(to), .. } =>
      for k in to {
        if k is Number(k, ..) && self.streams.get(k.to_int()) is Some(q) {
          ignore(q.try_offer(Some(t)))
        }
      }
    { "done": Number(n, ..), .. } =>
      match self.streams.get(n.to_int()) {
        Some(q) => ignore(q.try_offer(None))
        None => ()
      }
    { "claimed": Number(n, ..), .. } | { "answered": Number(n, ..), .. } =>
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
  let answer = self.answer(id, conn, who, asked, rest) catch {
    e => {
      @host.note("serve: a request failed: \{e}")
      ({ "status": 500, "headers": { "content-type": "application/json" } }, @utf8.encode("{\"error\":\"read failed\"}"))
    }
  }
  let (said, bytes) = answer
  // (an answer that went as it came: written there)
  if said is { "relayed": true, .. } {
    return
  }
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
async fn Serving::answer(self : Serving, id : Json, conn : Json, who : Member, asked : Json, body : Bytes) -> (Json, Bytes) raise {
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
  // The event stream (GET /events): Node's to make, written here as it comes, compressed here (relay).
  if asked.value("path") is Some(String(p)) && (p == "/admin/api/events" || p.has_prefix("/admin/api/events?")) {
    self.relay(id, conn, asked, body)
    return ({ "relayed": true }, b"")
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
  let error = (m : String) => ({ "error": Json::string(m) } : Json).stringify()
  // Several reads in one (admin.ts `batch`): each as its own GET would be, all here or all Node's.
  let route = match path.find("?") {
    Some(at) => path[0:at].to_string()
    None => path
  }
  if asked.value("method") == Some(Json::string("POST")) && route == "/admin/api/batch" {
    if body.length() > 1000000 {
      return self.whole(headers, @utf8.encode(error("request too large")), status=413)
    }
    let parsed = try { Some(@json.parse(@utf8.decode_lossy(body))) } catch { _ => None }
    let paths : Array[String] = []
    let fine = match parsed {
      Some(Object(m)) =>
        match m.get("gets") {
          Some(Array(a)) if a.length() <= 64 => {
            let mut all = true
            for g in a {
              match g {
                String(s) => paths.push(s)
                _ => all = false
              }
            }
            all
          }
          _ => false
        }
      _ => false
    }
    guard fine else { return self.whole(headers, @utf8.encode(error("gets: at most 64 paths to read")), status=400) }
    let answers = StringBuilder::new()
    for i, got in paths {
      let route = match got.find("?") {
        Some(at) => got[0:at].to_string()
        None => got
      }
      let one = if batched(route) {
        self.read_path(who, lang, words, "/admin/api" + got)
      } else {
        Text(400, error("not read in a batch: \{route}"))
      }
      guard one is Text(status, text) else { return self.fallback(conn, asked, body) }
      if i > 0 {
        answers.write_string(",")
      }
      answers.write_string("{\"status\":\{status},\"body\":\{if text == "" { "\"\"" } else { text }}}")
    }
    return self.whole(headers, @utf8.encode("{\"answers\":[\{answers}]}"), level=9)
  }
  // A mark the member puts on a chat or a session (api/routes/marks.ts): written here, Node told what changed.
  let marked = match (asked.value("method"), route_of_path(path)) {
    (Some(String("PUT" | "DELETE" as method)), _) => Some(method)
    (Some(String("POST")), ["sessions", _, "title"]) => Some("POST")
    _ => None
  }
  if marked is Some(method) {
    return match self.mark(who, method, path, body, words, lang) {
      Text(status, text) => self.whole(headers, @utf8.encode(text), status~)
      Give => self.fallback(conn, asked, body)
    }
  }
  // A person's message (routes/hub.ts POST /threads/:id/messages): in words alone, written here; any other, Node's.
  if asked.value("method") == Some(Json::string("POST")) && route_of_path(path) is ["threads", id, "messages"] {
    return match self.say(conn, who, id, path, headers, body, words, lang) {
      Some(answer) => answer
      None => self.fallback(conn, asked, body)
    }
  }
  let posted = if asked.value("method") == Some(Json::string("POST")) { Some((body, runtimes)) } else { None }
  match self.read_path(who, lang, words, path, posted?) {
    Text(status, text) => self.whole(headers, @utf8.encode(text), status~)
    Give => self.fallback(conn, asked, body)
  }
}

///|
/// What a path read here comes to: its status and its JSON's text, or Node's to answer (`Give`).
priv enum Done {
  Text(Int, String)
  Give
}

///|
/// admin.ts `BATCHED`: what a batch reads (after /admin/api).
fn batched(route : String) -> Bool {
  let parts : Array[String] = route.split("/").map(p => p.to_string()).collect()
  match parts {
    ["", "threads", id, "entries" | "letters"] | ["", "threads", id] => digits(id)
    ["", "sessions", key] | ["", "sessions", key, "timeline"] => key != ""
    _ => false
  }
}

///|
/// One GET of `who`'s read here (`path` with its /admin/api and its query), as the admin API answers it.
fn Serving::read_path(
  self : Serving,
  who : Member,
  lang : String,
  words : Json,
  path : String,
  posted? : (Bytes, Array[String]),
) -> Done raise {
  let error = (m : String) => ({ "error": Json::string(m) } : Json).stringify()
  let (route, query) = match path.find("?") {
    Some(at) => (path[0:at].to_string(), path[at + 1:].to_string())
    None => (path, "")
  }
  let pairs = query_pairs(query)
  // A session or a chat of another workspace than the member's is none for them (api/seen.ts `elsewhere`).
  if self.elsewhere(route, who.viewer) is Some(m) {
    return Text(404, error(m))
  }
  let routed = match posted {
    Some((body, runtimes)) => changed_read(route, pairs, who.viewer, lang, body, runtimes)
    None => route_read(route, pairs, who.viewer, lang)
  }
  let read = match routed {
    Read(op, args) => (op, args)
    Missing(m) => return Text(404, error(m))
    Refuse(status, m) => return Text(status, error(m))
    Not => return Give
  }
  let (op, args) = read
  guard args is Object(a) else { return Give }
  // (the words and the time the pool gives a read: read/pool.ts `wordsIn`, a list's in `changed` its own args'
  // (`changedOf`); a session's history only its own word)
  if op == "changed" {
    guard a.get("args") is Some(Object(inner)) else { return Give }
    inner["words"] = words
    inner["now"] = Json::number(self.now().to_double())
  } else if op == "timeline" {
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
  match text {
    Ok(text) => Text(200, text)
    // Refused: for what the pool prepares first (its `pending`), Node's to answer; else as the admin API says it.
    Err((status, m)) => {
      let pending = match self.set.value("pending") {
        Some(Array(all)) => all.iter().any(p => p is String(p) && m.has_prefix(p))
        _ => true
      }
      if pending {
        Give
      } else {
        Text(status, error(m))
      }
    }
  }
}

///|
/// An answer's head and its body as it goes: the admin API's headers, compressed where the core asks so
/// (mesh/compress.ts: zstd, from 512 bytes, at its level and window).
async fn Serving::whole(self : Serving, asked : Json, bytes : Bytes, status? : Int = 200, level? : Int = 3) -> (Json, Bytes) raise {
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
    let (_, out) = self.host.shell("zstd.compress", { "level": Json::number(level.to_double()), "window": 20 }, bytes~)
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
  Refuse(Int, String)
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
    "jobs" => {
      // (one not there is the route's to say)
      guard db.all("SELECT session_key FROM jobs WHERE id = ?", [Json::string(id)]) is [job, ..] else { return None }
      let ws = match db.all("SELECT ws FROM sessions WHERE key = ?", [job.get("session_key").unwrap_or(Json::null())]) {
        [row, ..] => row.get("ws").unwrap_or(Json::null())
        _ => Json::null()
      }
      if sees(ws) {
        None
      } else {
        Some("no job \{id}")
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
    ["jobs"] => Read("openJobs", { "viewer": viewer, "lang": l, "chats": Json::boolean(param("chats") != Some("0")) })
    ["jobs", id] => Read("job", { "id": Json::string(segment(id)) })
    ["jobs", id, "log"] => {
      let args : Map[String, Json] = { "id": Json::string(segment(id)) }
      given(args, ["lines"])
      Read("jobLog", Json::object(args))
    }
    _ => Not
  }
}

///|
/// api/routes/changed.ts: a list read again as what changed of it, the list's own args as its GET's (`id` what names
/// a row), the client's `held` and the runtimes it takes.
fn changed_read(route : String, pairs : Array[(String, String)], viewer : Json, lang : String, body : Bytes, runtimes : Array[String]) -> Route {
  let list = match route {
    "/admin/api/changed/chats" => "chats"
    "/admin/api/changed/sessions" => "sessions"
    "/admin/api/changed/threads" => "threads"
    _ => return Not
  }
  if body.length() > 1000000 {
    return Refuse(413, "request too large")
  }
  let held = match (try { Some(@json.parse(@utf8.decode_lossy(body))) } catch { _ => None }) {
    Some(Object(m)) =>
      match m.get("held") {
        Some(Object(_) as h) => Some(h)
        _ => None
      }
    _ => None
  }
  guard held is Some(held) else { return Refuse(400, "held: each held row's digest by its id") }
  let get = match route_read("/admin/api/" + list, pairs, viewer, lang) {
    Read(_, args) => args
    _ => return Not
  }
  let id = if list == "chats" { "id" } else if list == "sessions" { "key" } else { "id" }
  // (the chats' own args: a GET /chats with neither marks, shared nor rows, api/routes/chats.ts `chatsOf`)
  let args = if list == "chats" {
    let a : Map[String, Json] = { "viewer": viewer, "archived": Json::boolean(pairs.iter().any(p => p.0 == "archived" && p.1 == "1")) }
    for p in pairs {
      if p.0 == "page" {
        a["page"] = Json::string(p.1)
        break
      }
    }
    Json::object(a)
  } else {
    get
  }
  Read("changed", {
    "op": Json::string(list),
    "args": args,
    "id": Json::string(id),
    "held": held,
    "runtimes": Json::array(runtimes.map(r => Json::string(r))),
  })
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

///|
/// An answer Node makes as it comes (GET /events: serve.ts gives it the request, its head first, then each piece as it
/// is made, then that it ended), written on stream socket `id` as it comes: compressed where the core asks so (mesh/
/// compress.ts `compressedStream`: zstd, each piece flushed, a megabyte's window). Node is told to stop once the stream
/// is gone (a write to it fails).
async fn Serving::relay(self : Serving, id : Json, conn : Json, asked : Json, body : Bytes) -> Unit raise {
  self.next += 1
  let n = self.next
  let d : @effect.Deferred[Json] = @effect.Deferred::new()
  let pieces : @effect.Queue[String?] = @effect.Queue::unbounded()
  self.fallbacks[n] = d
  self.streams[n] = pieces
  defer self.streams.remove(n)
  self.host.say(
    ({
      "fallback": Json::number(n.to_double()),
      "conn": conn,
      "head": asked,
      "body": Json::string(@utf8.decode_lossy(body)),
      "stream": true,
    } : Json).stringify(),
  )
  let said = d.wait()
  let status = said.value("status").unwrap_or(Json::number(500.0))
  let headers = match said.value("headers") {
    Some(Object(h)) => h
    _ => Map([])
  }
  let zstd = match header(asked.value("headers").unwrap_or(Json::null()), "accept-encoding") {
    Some(s) => s.split(",").any(e => @jscase.trim_white(e.to_string()) == "zstd")
    None => false
  }
  let typed = match headers.get("content-type") {
    Some(String(t)) => t.has_prefix("application/json") || t.has_prefix("text/")
    _ => false
  }
  let mut z : Json? = None
  if zstd && typed && !headers.contains("content-encoding") {
    let (made, _) = self.host.shell("zstd.stream", { "level": 3, "window": 20 })
    if made is { "id": zid, .. } {
      z = Some(zid)
      headers.remove("content-length")
      headers["content-encoding"] = "zstd"
    }
  }
  let head : Json = { "status": status, "headers": Json::object(headers) }
  let mut open = self.frames(id, @utf8.encode(head.stringify() + "\n"))
  while open {
    guard pieces.take() is Some(text) else { break }
    let raw = @utf8.encode(text)
    let bytes = match z {
      Some(zid) => self.host.shell("zstd.push", { "id": zid }, bytes=raw).1.unwrap_or(b"")
      None => raw
    }
    if bytes.length() > 0 {
      open = self.frames(id, bytes)
    }
  }
  if z is Some(zid) {
    ignore(self.host.shell("zstd.close", { "id": zid })) catch {
      _ => ()
    }
  }
  if open {
    ignore(self.host.shell("tcp.write", { "id": id }, bytes=be32(PIPE_END))) catch {
      _ => ()
    }
  } else {
    // (gone: what makes it is let go of)
    self.host.say(({ "stop": Json::number(n.to_double()) } : Json).stringify())
  }
}

///|
/// `bytes` written to stream socket `id` as `pipe`'s frames; false once it cannot be (the stream is gone).
async fn Serving::frames(self : Serving, id : Json, bytes : Bytes) -> Bool {
  let out = @buffer.new()
  let mut at = 0
  while at < bytes.length() {
    let k = if bytes.length() - at > PIPE_MOST { PIPE_MOST } else { bytes.length() - at }
    out.write_bytes(be32(k))
    out.write_bytes(bytes[at:at + k].to_bytes())
    at += k
  }
  try {
    ignore(self.host.shell("tcp.write", { "id": id }, bytes=out.to_bytes()))
    true
  } catch {
    _ => false
  }
}

///|
/// api/routes/marks.ts's marks of a member's own: a chat's read position, hidden, muted, kept; a session pinned. As
/// the admin API answers them (a read-only member writes only the first three: admin.ts `OWN_MARKS`; one of another
/// workspace is not there: api/seen.ts), written in a transaction that writes, and what changed told Node
/// (`changes`, store.ts `#with`'s), which tells its followers as the store's own writes are told. Any other: Node's.
fn Serving::mark(
  self : Serving,
  who : Member,
  method : String,
  path : String,
  body : Bytes,
  words : Json,
  lang : String,
) -> Done raise {
  let error = (m : String) => ({ "error": Json::string(m) } : Json).stringify()
  let route = match path.find("?") {
    Some(at) => path[0:at].to_string()
    None => path
  }
  let parts : Array[String] = route.split("/").map(p => p.to_string()).collect()
  guard parts.length() >= 4 && parts[1] == "admin" && parts[2] == "api" else { return Give }
  let what = match (method, parts[3:]) {
    ("PUT", ["threads", _, "read" | "hidden" | "muted" | "keep" | "title" | "dismissed" as w]) => w.to_string()
    ("DELETE", ["threads", _, "keep"]) => "unkeep"
    ("PUT" | "DELETE", ["sessions", _, "pin"]) => "pin"
    ("POST", ["sessions", _, "title"]) => "named"
    _ => return Give
  }
  let viewer = who.viewer
  // (a read-only member's own marks only: admin.ts `OWN_MARKS`)
  let own = what == "read" || what == "hidden" || what == "muted" || what == "dismissed"
  if viewer.value("role") == Some(Json::string("viewer")) && not(own) {
    return Text(403, error("read-only members cannot change this station"))
  }
  if self.elsewhere(route, viewer) is Some(m) {
    return Text(404, error(m))
  }
  let email = match viewer.value("email") {
    Some(String(e)) => e
    _ => return Give
  }
  let input = if body.length() == 0 {
    Map([])
  } else {
    match (try { Some(@json.parse(@utf8.decode_lossy(body))) } catch { _ => None }) {
      Some(Object(m)) => m
      Some(_) => Map([])
      None => return Text(400, error("invalid JSON"))
    }
  }
  let db = self.reader.db_now()
  let now = Json::number(self.now().to_double())
  let id = segment(parts[4])
  let word = (w : String) => match words.value(w) {
    Some(String(said)) => said
    _ => ""
  }
  // A session named by hand, and its own chat with it (marks.ts POST /sessions/:key/title).
  if what == "named" {
    guard db.all("SELECT 1 AS x FROM sessions WHERE key = ?", [Json::string(id)]) is [_, ..] else {
      return Text(404, error("unknown session \{id}"))
    }
    let name = title_of(input)
    let home = self.writing(db, () => {
      ignore(db.run("UPDATE sessions SET title = ?1 WHERE key = ?2", [name, Json::string(id)]))
      match db.all("SELECT id FROM threads WHERE home = ? ORDER BY id LIMIT 1", [Json::string(id)]) {
        [r, ..] => {
          let home = r.get("id").unwrap_or(Json::null())
          ignore(db.run("UPDATE threads SET title = ?1 WHERE id = ?2", [name, home]))
          home
        }
        _ => Json::null()
      }
    })
    let changes : Array[Json] = [{ "type": "session", "key": Json::string(id) }]
    if home is Null {
      self.changed(changes)
    } else {
      changes.push({ "type": "thread", "id": home, "entries": [] })
      self.changed(changes, titled=[home])
    }
    return Text(200, ({ "ok": true } : Json).stringify())
  }
  if what == "pin" {
    guard db.all("SELECT 1 AS x FROM sessions WHERE key = ?", [Json::string(id)]) is [_, ..] else {
      return Text(404, error("unknown session \{id}"))
    }
    let pinned = method == "PUT"
    let key = Json::string(id)
    let at = self.writing(db, () => {
      if pinned {
        ignore(db.run("INSERT OR IGNORE INTO pins (viewer, session, at) VALUES (?, ?, ?)", [Json::string(email), key, now]))
        match db.all("SELECT at FROM pins WHERE viewer = ? AND session = ?", [Json::string(email), key]) {
          [r, ..] => r.get("at").unwrap_or(Json::null())
          _ => Json::null()
        }
      } else {
        ignore(db.run("DELETE FROM pins WHERE viewer = ? AND session = ?", [Json::string(email), key]))
        Json::null()
      }
    })
    self.changed([{ "type": "pins", "viewer": Json::string(email), "session": key, "at": at }])
    return Text(200, ({ "session": key, "pinned": Json::boolean(pinned) } : Json).stringify())
  }
  // (marks.ts `thread`: a number SQLite keeps, and a chat there)
  guard signed_digits(id) && signed_number(id).abs() <= 9007199254740991.0 else { return Text(404, error("unknown thread \{id}")) }
  let thread = Json::number(signed_number(id))
  guard db.all("SELECT surface FROM threads WHERE id = ?", [thread]) is [found, ..] else {
    return Text(404, error("unknown thread \{id}"))
  }
  let v = Json::string(email)
  match what {
    // A chat named by hand; none names it by its first message again. Answered as the chat is read.
    "title" => {
      if found.get("surface") != Some(Json::string("ember")) {
        return Text(400, error(word("renameOnlyStillfail")))
      }
      let name = title_of(input)
      ignore(self.writing(db, () => {
        ignore(db.run("UPDATE threads SET title = ?1 WHERE id = ?2", [name, thread]))
        Json::null()
      }))
      self.changed([{ "type": "thread", "id": thread, "entries": [] }], titled=[thread])
      self.read_path(who, lang, words, "/admin/api/threads/" + thread.stringify())
    }
    // A card (or a need) the member will not take up, by its post's entry `n`.
    "dismissed" => {
      let n = match input.get("n") {
        Some(Number(n, ..)) if n >= 1.0 && n == n.floor() => Json::number(n)
        _ => return Text(400, error(word("badN")))
      }
      // (marks.ts: a card, its own or options from before cards, or an agent's post: rows.ts `cardOfEntry`)
      let asked = db.all("SELECT card, options, author_kind FROM entries WHERE thread = ? AND n >= ? AND n <= ? ORDER BY n", [
        thread, n, n,
      ])
      let waiting = match asked {
        [e, ..] =>
          e.get("author_kind") == Some(Json::string("agent")) ||
          (match parsed_column(e.get("card")) {
            Some(Null) | None => false
            Some(_) => true
          }) ||
          parsed_column(e.get("options")) is Some(_)
        _ => false
      }
      guard waiting else { return Text(404, error(word("nothingWaiting"))) }
      ignore(self.writing(db, () => {
        ignore(db.run("INSERT OR IGNORE INTO dismissed (viewer, thread, n, at) VALUES (?, ?, ?, ?)", [v, thread, n, now]))
        Json::null()
      }))
      self.changed([{ "type": "dismissed", "viewer": v, "card": { "thread": thread, "n": n } }])
      Text(200, ({ "dismissed": { "thread": thread, "n": n } } : Json).stringify())
    }
    "read" => {
      let n = match input.get("n") {
        Some(Number(n, ..)) if n >= 0.0 && n == n.floor() => Json::number(n)
        _ => {
          let said = match words.value("badN") {
            Some(String(w)) => w
            _ => ""
          }
          return Text(400, error(said))
        }
      }
      let at = self.writing(db, () => {
        ignore(
          db.run(
            "INSERT INTO reads (viewer, thread, n, at) VALUES (?, ?, ?, ?) ON CONFLICT (viewer, thread) DO UPDATE SET n = MAX(n, excluded.n), at = excluded.at",
            [v, thread, n, now],
          ),
        )
        match db.all("SELECT n FROM reads WHERE viewer = ? AND thread = ?", [v, thread]) {
          [r, ..] => r.get("n").unwrap_or(Json::number(0.0))
          _ => Json::number(0.0)
        }
      })
      self.changed([{ "type": "read", "viewer": v, "thread": thread, "n": at }])
      Text(200, ({ "viewer": v, "thread": thread, "n": at } : Json).stringify())
    }
    "hidden" | "muted" => {
      guard input.get(what) is Some(True | False as flag) else { return Text(400, error("\{what} must be a boolean")) }
      let on = flag is True
      let table = if what == "hidden" { "hidden_chats" } else { "muted_chats" }
      // (muted by the email as it is in lower case: store.ts `setChatMuted`)
      let as_kept = if what == "muted" { Json::string(email.to_lower()) } else { v }
      ignore(self.writing(db, () => {
        if on {
          ignore(db.run("INSERT OR IGNORE INTO \{table} (viewer, thread) VALUES (?, ?)", [as_kept, thread]))
        } else {
          ignore(db.run("DELETE FROM \{table} WHERE viewer = ? AND thread = ?", [as_kept, thread]))
        }
        Json::null()
      }))
      let change : Map[String, Json] = { "type": Json::string(what), "viewer": v, "thread": thread }
      change[what] = Json::boolean(on)
      self.changed([Json::object(change)])
      let answer : Map[String, Json] = {}
      answer[what] = Json::boolean(on)
      Text(200, Json::object(answer).stringify())
    }
    _ => {
      let kept = what == "keep"
      ignore(self.writing(db, () => {
        if kept {
          ignore(db.run("INSERT OR IGNORE INTO kept_chats (viewer, thread) VALUES (?, ?)", [v, thread]))
        } else {
          ignore(db.run("DELETE FROM kept_chats WHERE viewer = ? AND thread = ?", [v, thread]))
        }
        Json::null()
      }))
      self.changed([{ "type": "dismissed", "viewer": v, "kept": { "thread": thread, "kept": Json::boolean(kept) } }])
      Text(200, ({ "kept": Json::boolean(kept) } : Json).stringify())
    }
  }
}

///|
/// `write` in a transaction that writes (BEGIN IMMEDIATE: waits its turn as the store's do), committed as it returns.
fn Serving::writing(self : Serving, db : @sql.Db, write : () -> Json raise) -> Json raise {
  ignore(self)
  db.exec("BEGIN IMMEDIATE")
  let out = write() catch {
    e => {
      db.exec("ROLLBACK") catch {
        _ => ()
      }
      raise e
    }
  }
  db.exec("COMMIT")
  out
}

///|
/// What changed told Node, which tells its followers (store.ts `told`).
/// `titled`: the chats named by hand in it (the store's `titleRevision` raised, which a title being made waits on).
fn Serving::changed(self : Serving, changes : Array[Json], titled? : Array[Json] = []) -> Unit {
  let said : Map[String, Json] = { "changes": Json::array(changes) }
  if titled.length() > 0 {
    said["titled"] = Json::array(titled)
  }
  self.host.say(Json::object(said).stringify())
}

///|
/// A name given by hand (marks.ts `title`): trimmed, at most 80 characters; none or empty is null.
fn title_of(input : Map[String, Json]) -> Json {
  let t = match input.get("title") {
    Some(String(t)) => @jscase.trim(t)
    _ => ""
  }
  if t == "" {
    return Json::null()
  }
  let out = StringBuilder::new()
  let mut count = 0
  for c in t {
    if count == 80 {
      break
    }
    out.write_char(c)
    count += 1
  }
  Json::string(out.to_string())
}

///|
/// A column of JSON as rows.ts `parsed` reads it: None for none or what does not parse.
fn parsed_column(v : Json?) -> Json? {
  match v {
    Some(String(text)) => try { Some(@json.parse(text)) } catch { _ => None }
    _ => None
  }
}

///|
/// The segments of `path` after /admin/api, without its query.
fn route_of_path(path : String) -> Array[String] {
  let route = match path.find("?") {
    Some(at) => path[0:at].to_string()
    None => path
  }
  let parts : Array[String] = route.split("/").map(p => p.to_string()).collect()
  if parts.length() >= 3 && parts[1] == "admin" && parts[2] == "api" {
    parts[3:].to_array()
  } else {
    []
  }
}

///|
/// routes/hub.ts's POST /threads/:id/messages and sessions/lifecycle.ts `say`, for a message in words alone: refused
/// as there; claimed of Node first (admin.ts `claimSay`: a keyed one's first answer given again, the hub's timestamp),
/// written as store.ts `insertMessage` writes one, told Node (`said`), which tells the store's followers and delivers
/// it to the chat's sessions. One with files, quotes, copies elsewhere, to a chat archived (or one the station
/// archived, which a message brings back): None, Node's.
async fn Serving::say(
  self : Serving,
  conn : Json,
  who : Member,
  raw : String,
  path : String,
  headers : Json,
  body : Bytes,
  words : Json,
  lang : String,
) -> (Json, Bytes)? raise {
  let error = (status : Int, m : String) => Some(
    (({ "status": Json::number(status.to_double()), "headers": { "content-type": "application/json" } } : Json), @utf8.encode(({ "error": Json::string(m) } : Json).stringify())),
  )
  let word = (k : String) => match words.value(k) {
    Some(String(w)) => w
    _ => ""
  }
  let viewer = who.viewer
  if viewer.value("role") == Some(Json::string("viewer")) {
    return error(403, "read-only members cannot change this station")
  }
  let route = "/admin/api/threads/\{raw}/messages"
  if self.elsewhere(route, viewer) is Some(m) {
    return error(404, m)
  }
  let db = self.reader.db_now()
  let id = segment(raw)
  guard signed_digits(id) && signed_number(id).abs() <= 9007199254740991.0 else { return error(404, "unknown thread \{id}") }
  let thread = Json::number(signed_number(id))
  let found = db.all("SELECT surface, hidden_at, home FROM threads WHERE id = ?", [thread])
  guard found is [t, ..] else { return error(404, "unknown thread \{id}") }
  if t.get("surface") != Some(Json::string("ember")) {
    return error(400, word("postOnlyStillfail"))
  }
  if body.length() > 1000000 {
    return error(413, "request too large")
  }
  let input : Map[String, Json] = if body.length() == 0 {
    Map([])
  } else {
    match (try { Some(@json.parse(@utf8.decode_lossy(body))) } catch { _ => None }) {
      Some(Object(m)) => m
      Some(_) => Map([])
      None => return error(400, "invalid JSON")
    }
  }
  // (words and quotes: files and copies to Slack or Feishu are Node's)
  let listed = (k : String) => match input.get(k) {
    None | Some(Null) => false
    Some(Array(a)) => a.length() > 0
    Some(_) => true
  }
  if listed("attachments") || listed("cc") {
    return None
  }
  // (read again as JSON.parse reads it: what is kept of it is as JSON.stringify writes it)
  let js : @jsjson.JValue = if body.length() == 0 {
    Obj([])
  } else {
    match (try { Some(@jsjson.parse(@utf8.decode_lossy(body))) } catch { _ => None }) {
      Some(Obj(_) as o) => o
      _ => Obj([])
    }
  }
  let said = match js.get("text") {
    None | Some(Null) => ""
    Some(Str(u)) => @jscase.trim(@jsjson.raw_text(u))
    Some(v) => @jscase.trim(@jsjson.stringify(v))
  }
  let given_quotes = js.get("quotes")
  let quotes = quotes_of(given_quotes)
  if said == "" && quotes.length() == 0 {
    return error(400, word("emptyMessage"))
  }
  // A quote naming the card waiting in the chat answers it (hub.ts: only one naming a message, as given)
  let original = match given_quotes {
    Some(Arr(all)) => all
    _ => []
  }
  let named = original.iter().any(q => q is Obj(_) && q.get("ts") is Some(Str(_)))
  let mut answered : Json? = None
  if named {
    match self.pending_card(db, thread) {
      Ready(Some((asked, at_ts, card))) => {
        let options = match card.get("options") {
          Some(Arr(o)) => o
          _ => []
        }
        let selected = options.iter().any(o => o is Obj(_) &&
          is_str(o.get("label"), said) &&
          is_str(o.get("action"), "close"))
        let quoted = original.iter().any(q => q is Obj(_) && is_str(q.get("ts"), at_ts))
        if selected && quoted {
          return error(409, word("updateClientForOption"))
        }
        if quoted {
          answered = Some(asked)
        }
      }
      Ready(None) => ()
      // (an old chat whose cards are not indexed yet: Node prepares it)
      NotReady => return None
    }
  }
  // A chat out of lists (archived by hand, or by the station: a message brings that back): Node's (store.ts `#bringBack`).
  let out = t.get("hidden_at") is Some(Number(_)) ||
    db.all(
      "SELECT 1 AS x FROM thread_sessions ts JOIN sessions s ON s.key = ts.session WHERE ts.thread = ? AND s.archived_at IS NOT NULL LIMIT 1",
      [thread],
    ) is [_, ..]
  if out {
    return None
  }
  // Which app sent it, for its agent (control characters out, 80 at most).
  let client = match js.get("client") {
    Some(Str(u)) => {
      let kept = StringBuilder::new()
      let mut count = 0
      for ch in @jscase.trim(@jsjson.text(u)) {
        let code = ch.to_int()
        if code < 0x20 || (code >= 0x7F && code < 0xA0) {
          continue
        }
        if count >= 80 {
          break
        }
        kept.write_char(ch)
        count += 1
      }
      let k = kept.to_string()
      if k == "" { Json::null() } else { Json::string(k) }
    }
    _ => Json::null()
  }
  // Claimed of Node: a keyed one's first answer, or the timestamp it is written at.
  self.next += 1
  let n = self.next
  let d : @effect.Deferred[Json] = @effect.Deferred::new()
  self.fallbacks[n] = d
  self.host.say(
    ({
      "claim": Json::number(n.to_double()),
      "conn": conn,
      "path": Json::string("/threads/\{raw}/messages"),
      "key": match header(headers, "idempotency-key") {
        Some(k) => Json::string(k)
        None => Json::null()
      },
      "lang": Json::string(lang),
    } : Json).stringify(),
  )
  let claimed = d.wait()
  let given = (k : String) => match claimed.value(k) {
    Some(Object(a)) => {
      let h = match a.get("headers") {
        Some(Object(h)) => Json::object(h)
        _ => Json::object(Map([]))
      }
      let text = match a.get("text") {
        Some(String(t)) => t
        _ => ""
      }
      Some((({ "status": a.get("status").unwrap_or(Json::number(500.0)), "headers": h } : Json), @utf8.encode(text)))
    }
    _ => None
  }
  if given("kept") is Some(answer) {
    return Some(answer)
  }
  if given("refused") is Some(answer) {
    return Some(answer)
  }
  guard claimed.value("ts") is Some(String(_) as ts) else { return error(500, "no timestamp") }
  let email = viewer.value("email").unwrap_or(Json::null())
  let at = Json::number(self.now().to_double())
  // (rows.ts `jsonList`: none for none)
  let kept_quotes = if quotes.length() == 0 { Json::null() } else { Json::string(@jsjson.stringify(Arr(quotes))) }
  let written = try {
    Ok(
      self.writing(db, () => {
        let existing = db.all("SELECT n FROM entries WHERE thread = ? AND ts = ? AND kind = 'message'", [thread, ts])
        if existing is [_, ..] {
          raise Failure("message timestamp already used; retry the write")
        }
        let last = match db.all("SELECT MAX(n) AS n FROM entries WHERE thread = ?", [thread]) {
          [{ "n": Number(k, ..), .. }, ..] => k
          _ =>
            match self.set.value("lastKnown") {
              Some(String(sql)) =>
                match db.all(sql, [thread]) {
                  [{ "n": Number(k, ..), .. }, ..] => k
                  _ => 0.0
                }
              _ => 0.0
            }
        }
        let k = Json::number(last + 1.0)
        ignore(
          db.run(
            "INSERT INTO entries (thread, n, kind, target, ts, author_kind, author, text, attachments, quotes, declared, client, profile, runtime, options, card, at, agent_identity, letter, change) VALUES (?, ?, 'message', NULL, ?, 'person', ?, ?, NULL, ?, NULL, ?, NULL, NULL, NULL, NULL, ?, NULL, NULL, NULL)",
            [thread, k, ts, email, Json::string(@jsjson.text(@jsjson.units(said))), kept_quotes, client, at],
          ),
        )
        match db.all("SELECT thread, n, kind, target, ts, author_kind, author, text, attachments, quotes, declared, client, profile, runtime, options, card, at, agent_identity, letter, change FROM entries WHERE thread = ? AND n = ?", [thread, k]) {
          [row, ..] => Json::object(row)
          _ => raise Failure("the message was not written")
        }
      }),
    )
  } catch {
    e => Err(e.to_string())
  }
  match written {
    Ok(row) => {
      let k = row.value("n").unwrap_or(Json::null())
      let answer = ({ "n": k } : Json).stringify()
      self.host.say(
        ({
          "said": { "thread": thread, "n": k, "text": Json::string(said), "row": row },
          "of": Json::number(n.to_double()),
          "answer": { "status": 200, "headers": { "content-type": "application/json" }, "text": Json::string(answer) },
        } : Json).stringify(),
      )
      // Answered from the decisions page: read up to that card, not past it (later ones may be unseen).
      if answered is Some(card_n) && email is String(e) {
        let v = Json::string(e)
        let now = Json::number(self.now().to_double())
        let read_n = self.writing(db, () => {
          ignore(
            db.run(
              "INSERT INTO reads (viewer, thread, n, at) VALUES (?, ?, ?, ?) ON CONFLICT (viewer, thread) DO UPDATE SET n = MAX(n, excluded.n), at = excluded.at",
              [v, thread, card_n, now],
            ),
          )
          match db.all("SELECT n FROM reads WHERE viewer = ? AND thread = ?", [v, thread]) {
            [r, ..] => r.get("n").unwrap_or(Json::number(0.0))
            _ => Json::number(0.0)
          }
        })
        self.changed([{ "type": "read", "viewer": v, "thread": thread, "n": read_n }])
      }
      Some(self.whole(headers, @utf8.encode(answer)))
    }
    Err(m) => {
      self.host.say(({ "said": Json::null(), "of": Json::number(n.to_double()) } : Json).stringify())
      error(500, m)
    }
  }
}

///|
/// The card waiting in a chat, as store.ts `pendingCardHeaderIfReady` finds it.
priv enum Pending {
  /// its post's n and ts and its card (cardOf: its own, else its options as an options card), or none waiting
  Ready(((Json, String, @jsjson.JValue))?)
  /// the chat's cards not indexed yet (card-post-index.ts `cardPostsReady`)
  NotReady
}

///|
fn Serving::pending_card(self : Serving, db : @sql.Db, thread : Json) -> Pending raise {
  ignore(self)
  guard db.all("SELECT phase FROM card_post_scopes WHERE thread = ?", [thread]) is [{ "phase": Number(2.0, ..), .. }, ..] else {
    return NotReady
  }
  guard db.all("SELECT n FROM card_posts WHERE thread=? ORDER BY n DESC LIMIT 1", [thread]) is [{ "n": Number(_) as n, .. }, ..] else {
    return Ready(None)
  }
  let answered = db.all(
    "SELECT 1 AS x FROM entries WHERE thread = ? AND kind = 'message' AND author_kind = 'person' AND n > ? LIMIT 1",
    [thread, n],
  ) is [_, ..]
  let closed = db.all("SELECT 1 AS x FROM closed_cards WHERE thread = ? AND n = ?", [thread, n]) is [_, ..]
  if answered || closed {
    return Ready(None)
  }
  guard db.all("SELECT ts, card, options FROM entries WHERE thread = ? AND n = ? AND kind = 'message'", [thread, n]) is [row, ..] else {
    return Ready(None)
  }
  let parsed = (v : Json?) => match v {
    Some(String(t)) => try { Some(@jsjson.parse(t)) } catch { _ => None }
    _ => None
  }
  let card = match parsed(row.get("card")) {
    Some(c) => Some(c)
    None =>
      match parsed(row.get("options")) {
        Some(o) => Some(@jsjson.JValue::Obj([(@jsjson.units("type"), Str(@jsjson.units("options"))), (@jsjson.units("options"), o)]))
        None => None
      }
  }
  guard card is Some(c) else { return Ready(None) }
  let ts = match row.get("ts") {
    Some(String(t)) => t
    _ => ""
  }
  Ready(Some((n, ts, c)))
}

///|
/// The first `max` characters of code units (`[...s].slice(0, max)`: a pair one, a lone surrogate one).
fn js_chars(u : Array[Int], max : Int) -> Array[Int] {
  let out = []
  let mut count = 0
  let mut i = 0
  while i < u.length() && count < max {
    let c = u[i]
    if c >= 0xd800 && c <= 0xdbff && i + 1 < u.length() && u[i + 1] >= 0xdc00 && u[i + 1] <= 0xdfff {
      out.push(c)
      out.push(u[i + 1])
      i += 2
    } else {
      out.push(c)
      i += 1
    }
    count += 1
  }
  out
}

///|
/// What is kept of the quotes a message brings (routes/hub.ts `quotesOf`): 20 at most, each cut, an empty one dropped.
fn quotes_of(given : @jsjson.JValue?) -> Array[@jsjson.JValue] {
  guard given is Some(Arr(list)) else { return [] }
  let out = []
  for k, q in list {
    if k >= 20 {
      break
    }
    let o : @jsjson.JValue = if q is Obj(_) { q } else { Obj([]) }
    let field = (name : String, fallback : String, max : Int) => {
      let v = match o.get(name) {
        None | Some(Null) => @jsjson.units(fallback)
        Some(Str(s)) => s
        Some(v) => @jsjson.units(@jsjson.stringify(v))
      }
      js_chars(v, max)
    }
    let text = field("text", "", 4000)
    let quote : Array[(Array[Int], @jsjson.JValue)] = [
      (@jsjson.units("author"), Str(field("author", "消息", 100))),
      (@jsjson.units("text"), Str(text)),
      (@jsjson.units("comment"), Str(field("comment", "", 4000))),
    ]
    if o.get("ts") is Some(Str(ts)) && ts_like(ts) {
      quote.push((@jsjson.units("ts"), Str(ts)))
    }
    if o.get("role") is Some(Str(role)) && ["agent", "person", "page", "image"].iter().any(r => @jsjson.units(r) == role) {
      quote.push((@jsjson.units("role"), Str(role)))
    }
    if o.get("file") is Some(Str(file)) && file.length() > 0 {
      quote.push((@jsjson.units("file"), Str(js_chars(file, 200))))
    }
    if @jscase.trim(@jsjson.raw_text(text)) != "" {
      out.push(@jsjson.JValue::Obj(quote))
    }
  }
  out
}

///|
/// `^[0-9]+\.[0-9]+$`
fn ts_like(u : Array[Int]) -> Bool {
  let mut dot = -1
  for i, c in u {
    if c == '.'.to_int() {
      if dot >= 0 {
        return false
      }
      dot = i
    } else if c < '0'.to_int() || c > '9'.to_int() {
      return false
    }
  }
  dot > 0 && dot < u.length() - 1
}

///|
/// Whether `v` is the string `s` (code unit for code unit, as `===`).
fn is_str(v : @jsjson.JValue?, s : String) -> Bool {
  match v {
    Some(Str(u)) => u == @jsjson.units(s)
    _ => false
  }
}
