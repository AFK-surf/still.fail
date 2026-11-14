// A peer for the mesh's tests, with no network: a shell stood in (`@shell.Shell::stood_in`) that answers what the
// mesh asks of iroh as a shell does, by the same names with the same JSON. On a runtime of the test's own clock
// (`@effect.Runtime::new`): nothing here waits on real time or on a thread. It is driven one of two ways.
//
// By hand (`Stood::new`): it holds back the calls a test answers itself, when it says: a dial (`iroh.connect`), a
// read (`istream.read`), a connection's end (`conn.closed`). For what turns on the order of the shell's answers.
//
// By a peer that answers by itself (`Stood::with_peer`, which gives the shell and its `Peer`): for a link's life.
// A test scripts the peer and moves the clock, and reads what the peer saw:
//
//   let (stood, far) = Stood::with_peer()
//   let mesh = stood.mesh()
//   far.answers = (line, hello) => …      what a control line is answered, as the door writes it (no newline);
//                                          None: the stream ends instead. `{"ok":true}` to every line unless said.
//   far.serves = (head, body) => …        what a request is answered: the pieces written back, its head line first
//                                          (`replied(200, b"…")`).
//   far.quiet = true                      control lines are taken and not answered: its pings are lost.
//   far.takes = 4_000                     each answer comes that many ms later, on the test's clock.
//   far.holds = true … far.release()      answers are kept back until the test gives them.
//   far.away = true                       a dial is not answered (given up by the mesh when its time runs out).
//   far.end(2, "bye")                     the peer ends connection 2 with that reason (`kind`: "timeout"…).
//   far.lose(2)                           the peer is gone from under connection 2 without a word: what the device
//                                          writes there is taken (and kept in `heard`, `asked`), nothing comes
//                                          back, and the connection does not end. Other connections are answered.
//   stood.rx[2] = 100.0                   what the transport says came on connection 2 so far (`conn.stats`).
//   stood.on_relay = false                the endpoint is on no relay yet (`iroh.relayStatus`): an opening's time
//                                          is not counted until it is.
//   let link = stood.opened(mesh, source.gives())      a link (`scope=`: in that scope), its hello answered by the
//                                          script; `Source` gives "c1", "c2"… and keeps how each was asked
//   stood.rt.advance(tick_ms)             time goes on: what is due meanwhile happens at its own time
//   far.heard, far.asked, far.dials, far.closes        what it saw: each control line (`<ms> <connection> <line>`),
//                                          each request, when each dial came, what the device closed with.
//
// The handles are numbered as they are given out, as by hand: the endpoint 1, the first connection 2, its control
// stream 3, then each request's stream or the next connection as it comes. An op may still be held back for the
// test by its name (`holding`), under either.
//
// Most tests go a step at a time, each run as far as it goes by itself (`go`, `give`). What depends on which of two
// fibers comes first within one turn is set up without running (`start`, `answered`) and then run at once (`run`):
// the runtime takes what is ready in the order it was made ready.

///|
priv struct Stood {
  rt : @effect.Runtime
  shell : Ref[@shell.Shell?]
  /// Every op asked, in order, each with the handle it was asked of (`conn.close 2`; 0: none).
  said : Array[String]
  /// The calls held back for the test to answer: the call's id, its op, its handle.
  held : Array[(Int64, String, Int)]
  /// The handles given out so far: the last one's number.
  mut last : Int
  /// The connections closed here, and why (what `conn.closeReason` answers of one).
  ended : Map[Int, Json]
  /// The connections let go of: closed with `forget`, as the mesh does of one whose end it was told. A page's shell
  /// forgets such a one, and answers nothing of it after.
  forgot : Map[Int, Unit]
  /// An op held back besides (`conn.openBi`, for an opening that stops with its connection made); "": none.
  mut holding : String
  /// Whether a dial given up is given up at the shell (`fetch.cancel`); false: it goes on, and is answered when the
  /// test says, as a dial the shell could no longer stop.
  mut cancels : Bool
  /// The peer that answers by itself (`Stood::with_peer`); none: every dial, read and end is the test's to answer.
  mut peer : Peer?
  /// The bytes that came on each connection so far, as the transport counts them (`conn.stats`): the test's to say
  /// (`stood.rx[2] = 100`); 0 of one it said nothing of.
  rx : Map[Int, Double]
  /// Whether the endpoint is on a relay (`iroh.relayStatus`: no relay at all while true, as a mesh made with none;
  /// one not connected while false).
  mut on_relay : Bool
}

///|
/// The handle `args` names (`{"id": n}`), 0 where it names none.
fn handle_of(args : Json) -> Int {
  match args {
    { "id": Number(n, ..), .. } => n.to_int()
    _ => 0
  }
}

///|
fn Stood::new() -> Stood {
  let rt = @effect.Runtime::new()
  let stood : Stood = {
    rt,
    shell: Ref(None),
    said: [],
    held: [],
    last: 0,
    ended: Map([]),
    forgot: Map([]),
    holding: "",
    cancels: true,
    peer: None,
    rx: Map([]),
    on_relay: true,
  }
  let answer = (id : Int64, json : Json) => stood.shell.val.unwrap().answer(id, json)
  let shell = @shell.Shell::stood_in(
    rt,
    calls=(id, op, args, bytes) => {
      let handle = handle_of(args)
      stood.said.push("\{op} \{handle}")
      if op == stood.holding {
        stood.held.push((id, op, handle))
        return
      }
      if stood.peer is Some(peer) && peer.took(id, op, handle, args, bytes) {
        return
      }
      match op {
        "iroh.bind" | "conn.openBi" =>
          if stood.ended.contains(handle) {
            stood.shell.val.unwrap().refuse(id, "connection closed: closed")
          } else {
            stood.last += 1
            answer(id, { "id": Json::number(stood.last.to_double()) })
          }
        "istream.write" | "istream.finish" | "istream.reset" | "iroh.close" => answer(id, {})
        "conn.close" => {
          if !stood.ended.contains(handle) {
            stood.ended[handle] = { "kind": "local", "reason": "closed" }
          }
          if args is { "forget": True, .. } {
            stood.forgot[handle] = ()
          }
          answer(id, {})
        }
        "iroh.connect" | "istream.read" | "conn.closed" => stood.held.push((id, op, handle))
        _ => stood.shell.val.unwrap().refuse(id, "the stood-in shell has no \{op}")
      }
    },
    asks=(op, args) => {
      let handle = handle_of(args)
      match op {
        "iroh.endpointId" => Json::string("ab".repeat(32))
        "iroh.relayStatus" =>
          if stood.on_relay {
            Json::array([])
          } else {
            [{ "url": "https://relay.test/", "connected": false }]
          }
        "conn.paths" => Json::array([])
        "conn.stats" => { "rxBytes": Json::number(stood.rx.get(handle).unwrap_or(0.0)), "txBytes": 0 }
        "conn.closeReason" => {
          if stood.forgot.contains(handle) {
            raise @shell.ShellError("no handle \{handle}")
          }
          stood.ended.get(handle).unwrap_or(Json::null())
        }
        "fetch.cancel" => {
          if !stood.cancels {
            return Json::boolean(false)
          }
          for i, call in stood.held {
            if call.0.to_int() == handle && call.1 == "iroh.connect" {
              ignore(stood.held.remove(i))
              stood.shell.val.unwrap().refuse(call.0, "cancelled")
              return Json::boolean(true)
            }
          }
          Json::boolean(false)
        }
        _ => raise @shell.ShellError("the stood-in shell has no \{op}")
      }
    },
    draws=n => Bytes::make(n, b'\x07'),
  )
  stood.shell.val = Some(shell)
  stood
}

///|
/// The oldest call of `op` held back, taken: its id and its handle. The test's mistake where none is held.
fn Stood::taken(self : Stood, op : String) -> (Int64, Int) raise {
  for i, call in self.held {
    if call.1 == op {
      ignore(self.held.remove(i))
      return (call.0, call.2)
    }
  }
  fail("the mesh asked no \{op} that is not answered yet: \{self.said.join(", ")}")
}

///|
/// The oldest `op` held back is answered `json` (and `bytes`), and the fibers it woke run.
fn Stood::give(self : Stood, op : String, json : Json, bytes? : Bytes) -> Unit raise {
  self.answered(op, json, bytes?)
  self.run()
}

///|
/// The oldest `op` held back is answered, and nothing runs yet: the fiber it woke is ready, behind what was before.
fn Stood::answered(self : Stood, op : String, json : Json, bytes? : Bytes) -> Unit raise {
  let (id, _) = self.taken(op)
  self.shell.val.unwrap().answer(id, json, bytes?)
}

///|
/// All that is ready runs, and what that makes ready, until nothing is.
fn Stood::run(self : Stood) -> Unit {
  ignore(self.rt.run_ready())
}

///|
/// `f` as a fiber of the test's runtime, ready and not yet run: it takes its first step behind what is ready now.
fn[X] Stood::start(self : Stood, f : async () -> X) -> @effect.Fiber[X] {
  self.rt.fork(f)
}

///|
/// The oldest `op` held back fails, in the shell's words, and the fibers it woke run.
fn Stood::refuse(self : Stood, op : String, why : String) -> Unit raise {
  let (id, _) = self.taken(op)
  self.shell.val.unwrap().refuse(id, why)
  ignore(self.rt.run_ready())
}

///|
/// The dial under way is answered: a connection, the next handle.
fn Stood::dialled(self : Stood) -> Unit raise {
  self.dial_answered()
  self.run()
}

///|
/// The same, and nothing runs yet. (Where a peer answers by itself, the connection is that peer's: a dial it left
/// unanswered, `away`, and the test answers after.)
fn Stood::dial_answered(self : Stood) -> Unit raise {
  self.last += 1
  if self.peer is Some(far) {
    far.conns[self.last] = []
  }
  self.answered("iroh.connect", { "id": Json::number(self.last.to_double()) })
}

///|
/// `f` as a fiber of the test's runtime, run as far as it goes by itself.
fn[X] Stood::go(self : Stood, f : async () -> X) -> @effect.Fiber[X] {
  let fiber = self.rt.fork(f)
  ignore(self.rt.run_ready())
  fiber
}

///|
/// How many times `said` (an op and its handle) was asked.
fn Stood::times(self : Stood, said : String) -> Int {
  self.said.filter(one => one == said).length()
}

///|
/// A mesh on the stood-in shell, its key kept already; `says` and `refusal`: its program's (`Options`).
fn Stood::mesh(self : Stood, says? : Map[String, Json], refusal? : (Json, String) -> Error?) -> Mesh raise {
  let made = self.go(() => Mesh::make(
    self.shell.val.unwrap(),
    { get: _ => Some(Bytes::make(32, b'\x01')), set: (_, _) => () },
    { alpn: "test/1", relays: [], relay_only: true, says, refusal },
  ))
  guard made.poll() is Some(Succeeded(mesh)) else { fail("the mesh was not made: \{self.said.join(", ")}") }
  mesh
}

///|
/// The peer the tests dial.
let peer : String = "cd".repeat(32)

///|
/// A link to `peer`, open and let in: dialled, its credential sent, the peer's answer `{"ok":true}` read. The
/// endpoint is handle 1, the connection 2, its control stream 3.
fn Stood::link(self : Stood, mesh : Mesh) -> Link raise {
  let opening = self.go(() => mesh.link(peer, (_, _) => { credential: "c", also: None }))
  self.dialled()
  self.give("istream.read", {}, bytes=b"{\"ok\":true}\n")
  guard opening.poll() is Some(Succeeded(link)) else { fail("the link did not open: \{self.said.join(", ")}") }
  link
}

///|
/// What a fiber ended with, in a line: `ok`, the mesh's code and words of what it failed with, `interrupted`, or
/// `waiting` while it has not ended.
fn[X] ended_as(fiber : @effect.Fiber[X]) -> String {
  match fiber.poll() {
    None => "waiting"
    Some(Succeeded(_)) => "ok"
    Some(Failed(e)) => said(e)
    Some(Interrupted) => "interrupted"
  }
}

// ── a peer that answers by itself ──

///|
/// A stream of a connection, at the peer.
priv struct Flow {
  conn : Int
  /// The connection's first: its control stream. Every other is a request's.
  control : Bool
  /// What the device wrote on it that the peer has not taken yet: a line not ended, a request until it is finished.
  wrote : @wire.Carry
  /// How many lines the peer took off it.
  mut lines : Int
  /// What the peer sent that the device has not read yet, in order; None: its end.
  sent : Array[Bytes?]
  /// The device's read that waits for more: the call's id.
  mut reader : Int64?
  /// Reset by the device: nothing more is sent on it.
  mut reset : Bool
}

///|
/// The peer: what a test scripts of it, what it saw, and what it keeps of its connections. The file's head says how
/// a test uses it.
priv struct Peer {
  stood : Stood
  mut answers : (String, Bool) -> String?
  mut serves : (String, Bytes) -> Array[Bytes]
  mut quiet : Bool
  mut takes : Int
  mut holds : Bool
  mut away : Bool
  /// The connections it is gone from under (`lose`): nothing more comes on them.
  lost : Map[Int, Unit]
  /// Every control line it took, in order: `<ms on the test's clock> <connection> <the line as written>`.
  heard : Array[String]
  /// Every request it took, as it was finished: `<ms> <connection> <its head line> <its body's length>`.
  asked : Array[String]
  /// When each dial came (ms on the test's clock).
  dials : Array[Int64]
  /// What the device closed each connection with, the first time: `<connection> <reason>`.
  closes : Array[String]
  /// Its connections' streams, in the order opened, and its streams.
  conns : Map[Int, Array[Int]]
  flows : Map[Int, Flow]
  /// The device's wait for a connection's end (`conn.closed`): the call's id, by connection.
  waits : Map[Int, Int64]
  /// The answers kept back (`holds`): the stream each is for, and its pieces.
  kept : Array[(Int, Array[Bytes?])]
}

///|
/// A stood-in shell whose peer answers by itself, and that peer: every hello and ping let in, every request
/// answered 200 with nothing, at once, until the test says otherwise.
fn Stood::with_peer() -> (Stood, Peer) {
  let stood = Stood::new()
  let far : Peer = {
    stood,
    answers: (_, _) => Some("{\"ok\":true}"),
    serves: (_, _) => replied(200, b""),
    quiet: false,
    takes: 0,
    holds: false,
    away: false,
    lost: Map([]),
    heard: [],
    asked: [],
    dials: [],
    closes: [],
    conns: Map([]),
    flows: Map([]),
    waits: Map([]),
    kept: [],
  }
  stood.peer = Some(far)
  (stood, far)
}

///|
/// A reply as the door writes one: its head line, then its body where it has one.
fn replied(status : Int, body : Bytes) -> Array[Bytes] {
  let head = @utf8.encode("{\"status\":\{status},\"headers\":{}}\n")
  if body.length() == 0 { [head] } else { [head, body] }
}

///|
/// Takes what the mesh asked of the shell where it is the peer's to answer: true then, false where it is the shell's
/// own (the endpoint, a handle the peer never gave).
fn Peer::took(self : Peer, id : Int64, op : String, handle : Int, args : Json, bytes : Bytes?) -> Bool {
  let stood = self.stood
  let shell = stood.shell.val.unwrap()
  let gone = "connection closed"
  match op {
    "iroh.connect" => {
      self.dials.push(stood.rt.now())
      if self.away {
        // (held as a dial by hand is: given up by `fetch.cancel`, or answered by the test)
        stood.held.push((id, op, handle))
      } else {
        stood.last += 1
        self.conns[stood.last] = []
        shell.answer(id, { "id": Json::number(stood.last.to_double()) })
      }
    }
    "conn.openBi" => {
      guard self.conns.get(handle) is Some(streams) else { return false }
      guard !stood.ended.contains(handle) else {
        shell.refuse(id, gone)
        return true
      }
      stood.last += 1
      streams.push(stood.last)
      self.flows[stood.last] = {
        conn: handle,
        control: streams.length() == 1,
        wrote: @wire.Carry::new(),
        lines: 0,
        sent: [],
        reader: None,
        reset: false,
      }
      shell.answer(id, { "id": Json::number(stood.last.to_double()) })
    }
    "conn.closed" => {
      guard self.conns.contains(handle) else { return false }
      match stood.ended.get(handle) {
        Some(why) => shell.answer(id, why)
        None => self.waits[handle] = id
      }
    }
    "conn.close" => {
      guard self.conns.contains(handle) else { return false }
      if args is { "forget": True, .. } {
        stood.forgot[handle] = ()
      }
      if !stood.ended.contains(handle) {
        self.closes.push("\{handle} \{if args is { "reason": String(reason), .. } { reason } else { "" }}")
        // (as both shells say a connection closed here: no reason kept)
        self.over(handle, { "kind": "local", "reason": "" })
      }
      shell.answer(id, {})
    }
    "istream.write" => {
      guard self.flows.get(handle) is Some(flow) else { return false }
      guard !stood.ended.contains(flow.conn) else {
        shell.refuse(id, gone)
        return true
      }
      flow.wrote.push(bytes.unwrap_or(b""))
      shell.answer(id, {})
      while flow.control && flow.wrote.line() is Some(line) {
        flow.lines += 1
        self.heard.push("\{stood.rt.now()} \{flow.conn} \{line}")
        if !self.quiet {
          self.send(handle, [(self.answers)(line, flow.lines == 1).map(answer => @utf8.encode(answer + "\n"))])
        }
      }
    }
    "istream.finish" => {
      guard self.flows.get(handle) is Some(flow) else { return false }
      shell.answer(id, {})
      if !flow.control {
        let head = flow.wrote.line().unwrap_or("")
        let body = flow.wrote.take()
        self.asked.push("\{stood.rt.now()} \{flow.conn} \{head} \{body.length()}")
        let pieces : Array[Bytes?] = (self.serves)(head, body).map(piece => Some(piece))
        pieces.push(None)
        self.send(handle, pieces)
      }
    }
    "istream.read" => {
      guard self.flows.get(handle) is Some(flow) else { return false }
      if flow.sent.length() > 0 {
        self.hand(id, flow.sent.remove(0))
      } else if flow.reset {
        self.hand(id, None)
      } else if stood.ended.contains(flow.conn) {
        shell.refuse(id, gone)
      } else {
        flow.reader = Some(id)
      }
    }
    "istream.reset" => {
      guard self.flows.get(handle) is Some(flow) else { return false }
      flow.reset = true
      flow.sent.clear()
      if flow.reader is Some(reader) {
        flow.reader = None
        self.hand(reader, None)
      }
      shell.answer(id, {})
    }
    _ => return false
  }
  true
}

///|
/// A read is answered: a piece, or the stream's end.
fn Peer::hand(self : Peer, id : Int64, piece : Bytes?) -> Unit {
  let shell = self.stood.shell.val.unwrap()
  match piece {
    Some(bytes) => shell.answer(id, {}, bytes~)
    None => shell.answer(id, { "end": true })
  }
}

///|
/// The peer sends `pieces` on `stream`: now, `takes` ms from now, or once the test releases them (`holds`).
fn Peer::send(self : Peer, stream : Int, pieces : Array[Bytes?]) -> Unit {
  if self.holds {
    self.kept.push((stream, pieces))
  } else if self.takes > 0 {
    self.stood.rt.after(self.takes, () => self.put(stream, pieces))
  } else {
    self.put(stream, pieces)
  }
}

///|
/// `pieces` come to the device on `stream`: to its read that waits, else kept for its next. Nothing comes on a
/// stream it reset or a connection that ended.
fn Peer::put(self : Peer, stream : Int, pieces : Array[Bytes?]) -> Unit {
  guard self.flows.get(stream) is Some(flow) && !flow.reset && !self.stood.ended.contains(flow.conn) else { return }
  // (gone from under it: what was on its way is lost too)
  guard !self.lost.contains(flow.conn) else { return }
  for piece in pieces {
    match flow.reader {
      Some(reader) => {
        flow.reader = None
        self.hand(reader, piece)
      }
      None => flow.sent.push(piece)
    }
  }
}

///|
/// The answers kept back come now, in the order they were made, and the fibers they woke run.
fn Peer::release(self : Peer) -> Unit {
  let kept = self.kept.copy()
  self.kept.clear()
  for one in kept {
    self.put(one.0, one.1)
  }
  self.stood.run()
}

///|
/// Connection `conn` is over, for `why` (as `conn.closed` says it): the device's wait for its end is answered, and
/// its reads that wait fail.
fn Peer::over(self : Peer, conn : Int, why : Json) -> Unit {
  let shell = self.stood.shell.val.unwrap()
  self.stood.ended[conn] = why
  if self.waits.get(conn) is Some(waiting) {
    self.waits.remove(conn)
    shell.answer(waiting, why)
  }
  for stream in self.conns.get(conn).unwrap_or([]) {
    if self.flows.get(stream) is Some(flow) && flow.reader is Some(reader) {
      flow.reader = None
      shell.refuse(reader, "connection closed")
    }
  }
}

///|
/// The peer is gone from under connection `conn` without a word, as a process ended with its connections open:
/// nothing more comes on it, what was on its way too, and it does not end.
fn Peer::lose(self : Peer, conn : Int) -> Unit {
  self.lost[conn] = ()
}

///|
/// The peer ends connection `conn` with `reason` (`kind` "application" unless said: "timeout", "other"), and the
/// fibers that woke run.
fn Peer::end(self : Peer, conn : Int, reason : String, kind? : String = "application") -> Unit {
  self.over(conn, { "kind": Json::string(kind), "reason": Json::string(reason) })
  self.stood.run()
}

///|
/// A credential's source for a test: "c1", "c2"… one more each time it is asked ("a1"… for a source said to be
/// `of` "a": one a scope, told apart), and how each was asked kept: "kept" (the one it has will do), "fresh" (a new
/// one: the last was refused).
priv struct Source {
  of : String
  asked : Array[String]
}

///|
fn Source::new(of? : String = "c") -> Source {
  { of, asked: [] }
}

///|
/// What a mesh is given as its credentials; `also`: what is said with each in a link's first line.
fn Source::gives(self : Source, also? : Map[String, Json]) -> async (String, Bool) -> Presented {
  (_, fresh) => {
    self.asked.push(if fresh { "fresh" } else { "kept" })
    { credential: "\{self.of}\{self.asked.length()}", also }
  }
}

///|
/// A link to `peer` (in `scope`, where one is said) on a shell whose peer answers, asked for and run as far as it
/// goes: handed out, its hello answered by the peer's script (unless that is kept back).
fn Stood::opened(
  self : Stood,
  mesh : Mesh,
  credentials : async (String, Bool) -> Presented,
  scope? : String = "",
) -> Link raise {
  let opening = self.go(() => mesh.link(peer, credentials, scope~))
  guard opening.poll() is Some(Succeeded(link)) else {
    fail("the link did not open (\{ended_as(opening)}): \{self.said.join(", ")}")
  }
  link
}
