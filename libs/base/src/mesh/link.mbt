// A link: one connection to a peer, let in by the credential said on its control stream (its first stream), each
// further stream one request: its head and body out and its reply back (`Link::request`), or its head out and
// then the stream open both ways (`Link::duplex`); and the streams the peer opens on it (`Link::accept`). The lines
// are `@wire`'s; the streams are the shell's (`conn.*`, `istream.*`).
//
// A wait on the shell given up is not the shell's call given up, so each wait here says what becomes of its stream
// when its fiber is cut: a request given up before its reply's head is reset; a read given up leaves a reply to be
// cancelled, never read again (`Reply::take`); a write given up lets go of its stream (`Out::write`); the wait for
// a request's stream to be opened is the mesh's own fiber, which resets the stream that comes for an asker gone
// (`Link::stream`); and the wait for a stream the peer opens is the mesh's own too, whose stream is the next
// asker's (`Link::accept`).
//
// A shell lets go of a stream once it was reset, or was both read to its end and finished; and with its
// connection. So a request's goes as its reply is read to its end; one open both ways is finished or cancelled by
// its program, or stays until the connection ends.

///|
/// A reply head is a line of JSON; anything longer is not a peer talking.
let max_head : Int = 64 * 1024

///|
/// How much of a reply's body `Reply::rest` keeps unless told otherwise: enough for what a device asks whole (a list,
/// a page of a log), and no more of a peer's bytes than a device can hold beside its work. What is longer is read as
/// it comes (`Reply::take`), or asked for with the bound it needs.
pub let max_body : Int = 16 * 1024 * 1024

///|
/// How much of a request's body goes at a time where its sender is told as it goes (`Link::request`'s `wrote`).
pub let body_step : Int = 64 * 1024

///|
/// The fields of a request's head line that are the link's own to write: what `more` may not name.
let head_fields : Array[String] = ["method", "path", "headers"]

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
  /// The scope its program asked for it in (`Mesh::link`); "" where it said none.
  scope : String
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
  /// Its pings' round trips (`Link::note`): how many were counted, their mean and mean deviation smoothed, how long
  /// the last one answered took (none answered: none), and whether one was answered yet (the first is not counted).
  priv mut samples : Int
  priv mut srtt : Double
  priv mut dev : Double
  priv mut answered_ms : Int?
  priv mut warm : Bool
  /// The mesh's fibers: where the wait for a stream the peer opens runs (`Link::accept`).
  priv fibers : @effect.Scope
  /// One asks for the next stream the peer opens at a time; and the shell's answer to the wait under way, kept
  /// until someone takes it (none: no wait is under way).
  priv accepts : @effect.Semaphore
  priv mut coming : @effect.Deferred[Json?]?
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
  /// Let go of (`cancel`, a read that failed): nothing more goes out on its stream either (`Out`).
  priv mut gone : Bool
  /// Done as it is let go of, however it is: whether for something that failed (a read, a write, a body too long)
  /// and not by its program's own `cancel`. What a wait on its stream is told then (`Out::stopped`).
  priv went : @effect.Deferred[Bool]
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
/// given up while it waits is to be cancelled, not taken again; one whose `take` failed is let go of here (its stream
/// reset: the shell keeps a stream until it is, or is read to its end), and has ended.
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
      self.let_go(true)
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
/// All of its body, read to its end: `most` bytes at most (`max_body` unless said). One longer fails as the piece
/// that passes the bound comes (`too_long`: nothing past it is kept or read, and the reply is let go of, so the peer
/// stops sending). Its pieces are kept as they come and joined once at the end.
pub async fn Reply::rest(self : Reply, most? : Int = max_body) -> Bytes {
  let pieces : Array[Bytes] = []
  let mut length = 0
  while self.take() is Some(piece) {
    // (asked of the room left, never of a sum: a peer's lengths added up could pass what an Int holds)
    if piece.length() > most - length {
      self.let_go(true)
      raise MeshError(
        code="too_long",
        message=say("reply_unreadable"),
        cause="a reply's body is longer than the \{most} bytes kept of one",
      )
    }
    length += piece.length()
    pieces.push(piece)
  }
  joined(pieces, length)
}

///|
/// `pieces`, `length` bytes together, as one: each copied once.
fn joined(pieces : Array[Bytes], length : Int) -> Bytes {
  if pieces.length() == 1 {
    return pieces[0]
  }
  let all : FixedArray[Byte] = FixedArray::make(length, b'\x00')
  let mut at = 0
  for piece in pieces {
    all.blit_from_bytes(at, piece, 0, piece.length())
    at += piece.length()
  }
  as_bytes(all)
}

///|
/// `all` as the bytes they are, not copied: nothing writes it after.
fn as_bytes(all : FixedArray[Byte]) -> Bytes = "%identity"

///|
/// Lets go of it: its stream is stopped both ways (nothing more is read, the peer stops sending).
pub fn Reply::cancel(self : Reply) -> Unit {
  self.let_go(false)
}

///|
/// Let go of, by its program (`cancel`) or, `broke`, for something that failed: every way it is goes through
/// here, so whoever waits on its stream is told (`went`: the first way stands).
fn Reply::let_go(self : Reply, broke : Bool) -> Unit {
  self.done = true
  self.gone = true
  self.carry = None
  ignore(self.went.succeed(broke))
  self.stream.reset()
}

///|
/// One request on a stream of its own: its head and body sent, its reply's head read. Given up before that head (its
/// asker gone, or failed), the stream goes at once.
///
/// `more`: further fields of its head line, after its headers (what its peer's door reads there: the program's;
/// never `method`, `path` or `headers`). `wrote`: told how much of the body has gone, as it goes: the body is then
/// written `body_step` bytes at a time, each step said once the stream took it (as far as the link lets it; no more
/// than a step waits here). Its reply's body is read whole up to a bound (`Reply::rest`), or as it comes
/// (`Reply::take`: a piece a call, nothing read of the peer before it is asked for, so a reader that stops asking
/// holds the peer back by the transport's own window and keeps one piece at most).
pub async fn Link::request(
  self : Link,
  method_ : String,
  path : String,
  headers? : Array[(String, String)] = [],
  body? : Bytes = b"",
  more? : Map[String, Json],
  wrote? : (Int) -> Unit,
) -> Reply {
  self.begin(head_of(method_, path, headers, more), body, true, wrote)
}

///|
/// A request whose stream stays open both ways after its head: the head line sent (with `more`, as
/// `Link::request`'s), the reply's head read, and from there what the peer sends is the reply's body as it comes
/// (`Reply::take`) and what goes to it is `Out`'s to write. Nothing is finished: the program says when it has no
/// more to send (`Out::finish`), and lets go of the stream by cancelling the reply (`Reply::cancel`), which stops it
/// both ways. Reading the reply to its end lets go of nothing by itself: the stream is the shell's until it was
/// finished too, or cancelled, or its connection ended. Given up before the reply's head, the stream goes at once.
pub async fn Link::duplex(
  self : Link,
  method_ : String,
  path : String,
  headers? : Array[(String, String)] = [],
  more? : Map[String, Json],
) -> (Reply, Out) {
  let reply = self.begin(head_of(method_, path, headers, more), b"", false, None)
  (
    reply,
    {
      stream: reply.stream,
      let_go: () => reply.let_go(true),
      is_gone: () => reply.gone,
      went: reply.went,
      is_read: () => reply.done,
      finished: false,
    },
  )
}

///|
/// A request's head line, its `more` held to what a program may say there.
fn head_of(method_ : String, path : String, headers : Array[(String, String)], more : Map[String, Json]?) -> String raise {
  if more is Some(fields) {
    for field in head_fields {
      if fields.contains(field) {
        // (its program's mistake: the head would not say what the call does)
        raise MeshError(code="invalid_params", message="a request's `more` names \{field}: its head's own, which the link writes", cause="")
      }
    }
  }
  @wire.head_line(method_, path, headers, more?)
}

///|
/// A request's stream opened, its head and body sent (finished, where `finish`), its reply's head read. A failure
/// is the peer's refusal of the link where it refused it (the credential, or what its program named).
async fn Link::begin(self : Link, head : String, body : Bytes, finish : Bool, wrote : ((Int) -> Unit)?) -> Reply {
  self.sent(head, body, finish, wrote) catch {
    e =>
      match self.refused {
        Some(refused) => raise refused
        None => raise e
      }
  }
}

///|
async fn Link::sent(self : Link, head : String, body : Bytes, finish : Bool, wrote : ((Int) -> Unit)?) -> Reply {
  // (ended, and the mesh told so: the shell is asked nothing of its connection after, `Mesh::open`)
  if self.ended_as_told() is Some(why) {
    raise MeshError(code="mesh", message=say("cut"), cause="connection closed: \{why.reason}")
  }
  let stream = self.stream()
  let had = Ref(false)
  defer {
    if !had.val {
      stream.reset()
    }
  }
  try {
    stream.write(@utf8.encode(head))
    match wrote {
      // A body that is told of goes a step at a time, each said as the stream takes it.
      Some(wrote) =>
        for at = 0; at < body.length(); at = at + body_step {
          let end = if at + body_step < body.length() { at + body_step } else { body.length() }
          stream.write(body[at:end].to_owned())
          wrote(end)
        }
      None =>
        if body.length() > 0 {
          stream.write(body)
        }
    }
    if finish {
      stream.finish()
    }
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
      {
        status,
        headers,
        link: self,
        stream,
        carry: if with_head.length() > 0 { Some(with_head) } else { None },
        done: false,
        gone: false,
        went: @effect.Deferred::new(),
      }
    }
  }
}

///|
/// A stream opened on the link. The shell's wait for it (`conn.openBi`) is a fiber of the mesh's, not the asker's:
/// the shell opens it whoever waits, so for an asker gone meanwhile the stream that comes is reset there, and none
/// is left open for nobody. Whoever waits for it waits for the link's end beside it (which the close says of every
/// link: that fiber, cut before its first step, says nothing).
async fn Link::stream(self : Link) -> Stream {
  let coming : @effect.Deferred[Json] = @effect.Deferred::new()
  let wanted = Ref(true)
  let shell = self.shell
  ignore(
    self.fibers.fork(name="mesh stream", () => {
      let opened = attempt(() => shell.call("conn.openBi", { "id": self.conn }))
      match opened {
        Did({ json: { "id": id, .. }, .. }) =>
          if wanted.val {
            ignore(coming.succeed(id))
          } else {
            shell.tell("istream.reset", { "id": id, "code": 0 })
          }
        Did(_) => ignore(coming.fail(failed("cut")))
        Fell(e) => ignore(coming.fail(cut(e)))
      }
    }),
  )
  let taken = Ref(false)
  defer {
    if !taken.val {
      wanted.val = false
      // (come already, and its asker cut before it took it)
      let came : Json? = coming.poll() catch { _ => None }
      if came is Some(id) {
        shell.tell("istream.reset", { "id": id, "code": 0 })
      }
    }
  }
  let id = @effect.race_first(() => coming.wait(), () => {
    let why = self.gone.wait()
    raise MeshError(code="mesh", message=say("cut"), cause="connection closed: \{why.reason}")
  })
  taken.val = true
  { shell, id }
}

///|
/// What goes out on a stream that is open both ways: a duplex request's (`Link::duplex`), or one the peer opened
/// (`Link::accept`).
pub struct Out {
  priv stream : Stream
  /// Lets go of the stream, its reading half told too; and whether it was let go of, by either half: nothing more
  /// is written then.
  priv let_go : () -> Unit
  priv is_gone : () -> Bool
  /// Done as the stream is let go of here: whether for something that failed (its reply's or inbound's `went`).
  priv went : @effect.Deferred[Bool]
  /// Whether its reading half was read to its end; and whether it was finished here: both, the shell has let go
  /// of the stream.
  priv is_read : () -> Bool
  priv mut finished : Bool
}

///|
/// Writes `bytes`, waiting until the stream took them (as far as the link lets them go). One that fails, or is given
/// up while it waits, lets go of the stream, both ways: the shell's write goes on whoever waits, so what of the
/// bytes went is not known, and what is written after would follow a hole. Nothing is written after that.
pub async fn Out::write(self : Out, bytes : Bytes) -> Unit {
  guard !(self.is_gone)() else { raise failed("cut") }
  let went = Ref(false)
  defer {
    if !went.val {
      (self.let_go)()
    }
  }
  self.stream.write(bytes) catch { e => raise cut(e) }
  went.val = true
}

///|
/// Nothing more goes out on it; what the peer sends still comes. Given up while it waits, it is finished all the
/// same (the shell's call goes on), which is all it was asked for. Asked again once it was finished, nothing is;
/// one that failed is not finished, and asked again asks the shell again.
pub async fn Out::finish(self : Out) -> Unit {
  guard !(self.is_gone)() else { raise failed("cut") }
  guard !self.finished else { return }
  self.finished = true
  self.stream.finish() catch {
    e => {
      self.finished = false
      raise cut(e)
    }
  }
}

///|
/// Waits until the stream's sending is over, and says whether its peer stopped it: the code it stopped it with, or
/// None. Given up while it waits, nothing is lost: the shell's wait holds nothing a later call needs.
///
/// None is said only where no stop came: once the stream was finished and the peer took all of it (so "the peer
/// took all that was written" is `finish`, then this giving None); and of a stream its program let go of itself
/// (`cancel`), which asked for no more of it. A stream let go of here for a read or a write that failed, or was
/// given up, fails as cut: what its peer did is not known, and a stop it sent may be what failed it. On a lost
/// connection it fails as cut too, where the shell can tell (a page's iroh says nothing of a failure: its shell
/// looks at the connection, and fails where that has ended).
///
/// A stream let go of here is answered by the mesh, asked before or waiting as it happens: the shells answer a
/// wait on a stream reset here only as its connection ends, so the shell's own wait, where one was begun, is left
/// behind then (it holds nothing a later call needs).
///
/// It is asked before the stream is both read to its end and finished: the shell lets go of the stream then, and
/// has nothing to ask of it after. So where the reply may already be read to its end, this wait is begun before
/// `finish` (in a fiber of its program's), not after it; asked after both, it fails as the program's mistake,
/// with nothing asked. The mesh does not begin it for its program at `finish`: the shells take calls side by
/// side, and one asked in the same breath as the finish that lets go of the stream is not sure to find it.
pub async fn Out::stopped(self : Out) -> Int? {
  let let_go = () => {
    if self.went.wait() {
      raise failed("cut")
    }
    None
  }
  if (self.is_gone)() {
    return let_go()
  }
  guard !(self.finished && (self.is_read)()) else {
    raise MeshError(
      code="invalid_params",
      message="a stream read to its end and finished is let go of: whether its peer stopped it is asked before the last of the two",
      cause="",
    )
  }
  @effect.race_first(
    () => {
      let said = self.stream.shell.call("istream.stopped", { "id": self.stream.id }) catch { e => raise cut(e) }
      match said.json {
        { "code": Number(code, ..), .. } => Some(code.to_int())
        _ => None
      }
    },
    let_go,
  )
}

///|
/// A stream the peer opened on the link (`Link::accept`): what it sends as it comes, and what goes back (`out`).
/// What it is for is its program's to read off it: the base reads no head of it, so whatever its program takes
/// for one it bounds itself (a line's length, how long it waits for it), as the base bounds a reply's.
///
/// Its program lets go of it: read to its end and finished (`out`), or cancelled. Read to its end alone it stays
/// the shell's until its connection ends.
pub struct Inbound {
  out : Out
  priv stream : Stream
  priv mut done : Bool
  priv mut gone : Bool
  /// As a reply's: done as it is let go of, whether for something that failed.
  priv went : @effect.Deferred[Bool]
}

///|
/// The next of what the peer sent on it; None once it ended. As a reply's (`Reply::take`): one whose `take` is given
/// up while it waits is to be cancelled, not taken again; one whose `take` failed is let go of here, and has ended.
pub async fn Inbound::take(self : Inbound) -> Bytes? {
  if self.done {
    return None
  }
  let chunk = self.stream.read() catch {
    e => {
      self.let_go(true)
      raise cut(e)
    }
  }
  if chunk is None {
    self.done = true
  }
  chunk
}

///|
/// Lets go of it: its stream is stopped both ways.
pub fn Inbound::cancel(self : Inbound) -> Unit {
  self.let_go(false)
}

///|
/// As a reply's (`Reply::let_go`).
fn Inbound::let_go(self : Inbound, broke : Bool) -> Unit {
  self.done = true
  self.gone = true
  ignore(self.went.succeed(broke))
  self.stream.reset()
}

///|
/// The next stream the peer opens on the link; None once the connection ended, or the mesh closed. One asker at a
/// time: another waits its turn.
///
/// The shell's wait for it (`conn.acceptBi`) is a fiber of the mesh's, not the asker's, and one is under way at
/// most: an asker that gives up loses nothing, and the stream that wait brings is the next asker's. With nobody
/// asking again it is kept at the shell until the connection ends, as every stream of it is.
pub async fn Link::accept(self : Link) -> Inbound? {
  self.accepts.with_permit(() => {
    // (ended, and the mesh told so: the shell is asked nothing of its connection after)
    guard self.ended_as_told() is None else { return None }
    let coming = match self.coming {
      Some(coming) => coming
      None => {
        let coming : @effect.Deferred[Json?] = @effect.Deferred::new()
        self.coming = Some(coming)
        // (cut as the mesh closes, before its first step even, it says nothing: whoever waits below is told by
        // the link's end, which the close says of every link)
        ignore(
          self.fibers.fork(name="mesh accept", () => {
            let said = attempt(() => self.shell.call("conn.acceptBi", { "id": self.conn }))
            ignore(
              coming.succeed(
                match said {
                  Did({ json: { "id": id, .. }, .. }) => Some(id)
                  _ => None
                },
              ),
            )
          }),
        )
        coming
      }
    }
    let next = @effect.race_first(() => coming.wait(), () => {
      ignore(self.gone.wait())
      None
    })
    guard next is Some(id) else { return None }
    // (taken: the next asker's wait is another)
    self.coming = None
    let stream : Stream = { shell: self.shell, id }
    let inbound : Ref[Inbound?] = Ref(None)
    let went : @effect.Deferred[Bool] = @effect.Deferred::new()
    let out : Out = {
      stream,
      let_go: () => if inbound.val is Some(inbound) { inbound.let_go(true) },
      is_gone: () => inbound.val is Some(inbound) && inbound.gone,
      went,
      is_read: () => inbound.val is Some(inbound) && inbound.done,
      finished: false,
    }
    let taken : Inbound = { out, stream, done: false, gone: false, went }
    inbound.val = Some(taken)
    Some(taken)
  })
}

///|
/// Why it ended, once the mesh was told (by the shell, or by its own closing); none until then.
fn Link::ended_as_told(self : Link) -> Closed? {
  self.gone.poll() catch {
    _ => None
  }
}

///|
/// Why it ended, if it has: what the mesh was told of its end once it was, the shell's word until then (it knows
/// before the mesh's fiber that waits for it has run).
pub fn Link::ended(self : Link) -> Closed? {
  if self.ended_as_told() is Some(why) {
    return Some(why)
  }
  let said = self.shell.ask("conn.closeReason", { "id": self.conn }) catch { _ => return Some({ kind: "other", reason: "" }) }
  closed_of(said)
}

///|
/// Waits for its end: why it ended.
pub async fn Link::closed(self : Link) -> Closed {
  self.gone.wait()
}

///|
/// Closes it; `reason`: what the peer is told it was closed for ("closed" unless said).
pub fn Link::close(self : Link, reason? : String = "closed") -> Unit {
  self.shell.tell("conn.close", { "id": self.conn, "code": 0, "reason": Json::string(reason) })
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

///|
/// How a link's pings went: what a program shows of its way, or chooses a way by.
pub(all) struct Pings {
  /// The round trips counted so far (none: `srtt` and `dev` say nothing yet).
  samples : Int
  /// Their mean, in ms, smoothed an eighth each time, and their mean deviation, a quarter.
  srtt : Double
  dev : Double
  /// Pings in a row not answered.
  missed : Int
  /// How long the last one answered took, in ms; none where none was.
  answered_ms : Int?
}

///|
pub fn Link::pings(self : Link) -> Pings {
  { samples: self.samples, srtt: self.srtt, dev: self.dev, missed: self.missed, answered_ms: self.answered_ms }
}

///|
/// A ping's round trip of `ms` is counted: smoothed as TCP smooths its own (RFC 6298: the mean an eighth each time,
/// the mean deviation a quarter), but its deviation from nothing at first, not half the first round trip.
fn Link::note(self : Link, ms : Int) -> Unit {
  let ms = ms.to_double()
  if self.samples == 0 {
    self.srtt = ms
    self.dev = 0.0
  } else {
    self.dev = 0.75 * self.dev + 0.25 * (ms - self.srtt).abs()
    self.srtt = 0.875 * self.srtt + 0.125 * ms
  }
  self.samples += 1
}

///|
/// The bytes that came on its connection so far, the transport's own packets too (`conn.stats`); 0 where the shell
/// does not say.
fn Link::heard(self : Link) -> Double {
  let said = self.shell.ask("conn.stats", { "id": self.conn }) catch { _ => return 0.0 }
  match said {
    { "rxBytes": Number(bytes, ..), .. } => bytes
    _ => 0.0
  }
}
