// A link: one connection to a peer, let in by the credential said on its control stream (its first stream), each
// further stream one request. The lines are `@wire`'s; the streams are the shell's (`conn.*`, `istream.*`).

///|
/// A reply head is a line of JSON; anything longer is not a peer talking.
let max_head : Int = 64 * 1024

///|
/// A stream of a connection, at the shell.
priv struct Stream {
  shell : @shell.Shell
  id : Json
}

///|
/// What came next on it; None at its end. Never asked again once given up while waiting (the shell goes on reading
/// for the read let go, and what that takes is gone): a stream whose read is given up is reset.
async fn Stream::read(self : Stream) -> Bytes? {
  self.shell.call("istream.read", { "id": self.id }).bytes
}

///|
async fn Stream::write(self : Stream, bytes : Bytes) -> Unit {
  ignore(self.shell.call("istream.write", { "id": self.id }, bytes~))
}

///|
async fn Stream::finish(self : Stream) -> Unit {
  ignore(self.shell.call("istream.finish", { "id": self.id }))
}

///|
/// Stops it both ways: nothing more is read of it, and the peer stops sending.
fn Stream::reset(self : Stream) -> Unit {
  self.shell.tell("istream.reset", { "id": self.id, "code": 0 })
}

///|
/// Lines off a stream, what followed them kept.
priv struct Lines {
  stream : Stream
  carry : @wire.Carry
}

///|
/// One line; None at the stream's end.
async fn Lines::next(self : Lines) -> String? {
  while true {
    if self.carry.line() is Some(line) {
      return Some(line)
    }
    if self.carry.length() > max_head {
      raise failed("head_too_long")
    }
    let chunk = self.stream.read() catch { e => raise cut(e) }
    match chunk {
      Some(chunk) => self.carry.push(chunk)
      None => {
        if self.carry.length() == 0 {
          return None
        }
        raise failed("reply_cut")
      }
    }
  }
  None
}

///|
/// The control stream: credential lines out, answers back.
priv struct Control {
  stream : Stream
  lines : Lines
  says : Map[String, Json]?
  refusal : ((Json, String) -> Error?)?
  /// The refusal read last was one its user named (`Options.refusal`): the credential was fine.
  mut named : Bool
}

///|
async fn Control::send(self : Control, credential : String, also? : Map[String, Json]) -> Unit {
  self.stream.write(@utf8.encode(@wire.hello_line(credential, says?=self.says, also?))) catch {
    e => raise cut(e)
  }
}

///|
/// The peer's answer to the credential last sent; fails if it refused.
async fn Control::answer(self : Control) -> Json {
  guard self.lines.next() is Some(line) else { raise failed("credential_closed") }
  let answer : Json = @json.parse(line) catch { e => raise under("credential_unreadable", e) }
  guard answer is { "error": error, .. } else { return answer }
  let reason = match error {
    String(reason) => reason
    other => other.stringify()
  }
  if answer is { "code": String(code), .. } && code == "client_upgrade_required" {
    raise MeshError(code~, message=reason, cause="")
  }
  // What the peer refuses for besides the credential is its user's to name.
  if self.refusal is Some(refusal) && refusal(answer, reason) is Some(other) {
    self.named = true
    raise other
  }
  raise MeshError(code="credential_refused", message=say("credential_refused_why", args={ "reason": reason }), cause="")
}

///|
/// What a credential's source gives: the credential, and what else is said with it in a link's first line.
pub(all) struct Presented {
  credential : String
  also : Map[String, Json]?
}

///|
/// Why a connection ended: `kind` "application" (closed by an end of it, `reason` what that end said), "local" (closed
/// here), "timeout", or "other".
pub(all) struct Closed {
  kind : String
  reason : String
}

///|
fn closed_of(said : Json) -> Closed? {
  guard said is { "kind": String(kind), .. } else { return None }
  Some({ kind, reason: if said is { "reason": String(reason), .. } { reason } else { "" } })
}

///|
/// It, said to people.
pub fn Closed::words(self : Closed) -> String {
  match (self.kind, self.reason) {
    ("application", "credential_refused") => say("credential_refused")
    ("application", "credential_revoked") => say("credential_revoked")
    ("application", "credential_expired") => say("credential_expired")
    ("application", "station_removed") => say("station_removed")
    ("application", reason) => say("closed_by_station", args={ "reason": reason })
    ("local", _) => say("closed")
    ("timeout", _) => say("timed_out")
    _ => say("cut")
  }
}

///|
pub struct Link {
  /// The peer's endpoint id.
  peer : String
  priv shell : @shell.Shell
  priv conn : Json
  priv control : Control
  /// The control stream is asked one exchange at a time.
  priv lock : @effect.Semaphore
  priv credentials : async (String, Bool) -> Presented
  /// The credential it last presented: what its pings present again.
  priv mut credential : String
  priv mut renewal_failed : Bool
  /// The peer's refusal of the first credential, once it answered.
  priv mut refused : Error?
  /// The peer's answer to the first credential, whole; none until it answered, and where it refused.
  priv mut answer : Json?
  /// Done once the peer answered the first credential (refused or not).
  priv answered : @effect.Deferred[Unit]
  /// Done as the connection ends, with why.
  priv gone : @effect.Deferred[Closed]
  /// The bytes its replies' bodies have brought so far.
  priv mut came : Int
  /// Its pings (mesh.mbt `Mesh::ping`): how many in a row were not answered, whether one is under way, and what its
  /// replies had brought as it was last pinged.
  priv mut missed : Int
  priv mut pinging : Bool
  priv mut rx : Int
}

///|
/// Once the peer answered the first credential: its answer, whole, as its line was parsed (its user's to read: who it
/// let in, what it says of itself), or failing with its refusal. A link is handed out as its credential is sent, its
/// requests going already: what must know it was let in first waits here.
pub async fn Link::admitted(self : Link) -> Json {
  self.answered.wait()
  if self.refused is Some(refused) {
    raise refused
  }
  self.answer.unwrap_or(Json::null())
}

///|
/// The credential presented again on the control stream (a ping, a renewal): the peer's answer, or its refusal.
pub async fn Link::exchange(self : Link, credential : String) -> Json {
  self.lock.with_permit(() => {
    self.control.send(credential)
    self.control.answer()
  })
}

///|
/// A reply: its head, and its body as it comes.
pub struct Reply {
  status : Int
  headers : Array[(String, String)]
  priv link : Link
  priv stream : Stream
  /// What came with the head line and was not taken yet.
  priv mut carry : Bytes?
  priv mut done : Bool
}

///|
/// The header `name` (as the peer wrote it), where the reply has it.
pub fn Reply::header(self : Reply, name : String) -> String? {
  for header in self.headers {
    if header.0 == name {
      return Some(header.1)
    }
  }
  None
}

///|
/// The next of its body as it comes (what came with the head line first); None once it ended. A reply whose `take` is
/// given up while it waits is to be cancelled, not taken again.
pub async fn Reply::take(self : Reply) -> Bytes? {
  if self.carry is Some(carry) {
    self.carry = None
    return Some(carry)
  }
  if self.done {
    return None
  }
  let chunk = self.stream.read() catch {
    e => {
      self.done = true
      raise cut(e)
    }
  }
  match chunk {
    Some(chunk) => self.link.came += chunk.length()
    None => self.done = true
  }
  chunk
}

///|
/// All of its body, read to its end.
pub async fn Reply::rest(self : Reply) -> Bytes {
  let mut all = b""
  while self.take() is Some(chunk) {
    all = if all.length() == 0 { chunk } else { all + chunk }
  }
  all
}

///|
/// Lets go of it: its stream is stopped both ways (nothing more is read, the peer stops sending).
pub fn Reply::cancel(self : Reply) -> Unit {
  self.done = true
  self.carry = None
  self.stream.reset()
}

///|
/// One request on a stream of its own: its head and body sent, its reply's head read. Given up before that head (its
/// asker gone, or failed), the stream goes at once.
pub async fn Link::request(
  self : Link,
  method_ : String,
  path : String,
  headers? : Array[(String, String)] = [],
  body? : Bytes = b"",
) -> Reply {
  self.ask(@wire.head_line(method_, path, headers), body) catch {
    e =>
      match self.refused {
        Some(refused) => raise refused
        None => raise e
      }
  }
}

///|
async fn Link::ask(self : Link, head : String, body : Bytes) -> Reply {
  let opened = self.shell.call("conn.openBi", { "id": self.conn }) catch { e => raise cut(e) }
  guard opened.json is { "id": id, .. } else { raise failed("cut") }
  let stream : Stream = { shell: self.shell, id }
  let had = Ref(false)
  defer {
    if !had.val {
      stream.reset()
    }
  }
  try {
    stream.write(@utf8.encode(head))
    if body.length() > 0 {
      stream.write(body)
    }
    stream.finish()
  } catch {
    e => raise cut(e)
  }
  let lines : Lines = { stream, carry: @wire.Carry::new() }
  guard lines.next() is Some(line) else { raise failed("no_reply") }
  match @wire.reply_head(line) {
    Unreadable(why) => raise MeshError(code="mesh", message=say("reply_unreadable"), cause=why)
    NoStatus => raise failed("reply_no_status")
    Head(status, headers) => {
      had.val = true
      let with_head = lines.carry.take()
      { status, headers, link: self, stream, carry: if with_head.length() > 0 { Some(with_head) } else { None }, done: false }
    }
  }
}

///|
/// Why it ended, if it has.
pub fn Link::ended(self : Link) -> Closed? {
  let said = self.shell.ask("conn.closeReason", { "id": self.conn }) catch { _ => return Some({ kind: "other", reason: "" }) }
  closed_of(said)
}

///|
/// Waits for its end: why it ended.
pub async fn Link::closed(self : Link) -> Closed {
  self.gone.wait()
}

///|
/// Closes it.
pub fn Link::close(self : Link) -> Unit {
  self.shell.tell("conn.close", { "id": self.conn, "code": 0, "reason": "closed" })
}

///|
/// Whether requests go on it: not ended, and its credential not refused at a renewal.
pub fn Link::usable(self : Link) -> Bool {
  self.ended() is None && !self.renewal_failed
}

///|
/// The ways the connection can go now, as the shell says them (`conn.paths`: each `{id, selected, relay, ip, rttMs, …}`).
pub fn Link::paths(self : Link) -> Array[Json] {
  let said = self.shell.ask("conn.paths", { "id": self.conn }) catch { _ => return [] }
  match said {
    Array(paths) => paths
    _ => []
  }
}

///|
/// How it goes now: "relay" or "direct"; None while no way is chosen.
pub fn Link::path(self : Link) -> String? {
  for path in self.paths() {
    if path is { "selected": True, .. } {
      return Some(if path is { "relay": String(_), .. } { "relay" } else { "direct" })
    }
  }
  None
}

///|
/// The relay it goes through now; None where it goes direct, or no way is chosen.
pub fn Link::via(self : Link) -> String? {
  for path in self.paths() {
    if path is { "selected": True, "relay": String(relay), .. } {
      return Some(relay)
    }
  }
  None
}

///|
/// Whether its replies brought anything since this was last asked: a ping waits behind the replies on its line, and
/// one late while more came is not missed.
fn Link::brought(self : Link) -> Bool {
  let more = self.came > self.rx
  self.rx = self.came
  more
}
