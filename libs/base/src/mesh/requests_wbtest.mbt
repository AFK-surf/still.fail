// What a link carries beside the one whole request (link.mbt): a head line with further fields, a body sent a step
// at a time and told of, a reply read as it comes, a stream open both ways, and the streams the peer opens; and how
// each fails. On the peer that answers by itself (stood_wbtest.mbt): the endpoint is handle 1, the link's
// connection 2, its control stream 3, and the first stream after that 4. The head lines' bytes are the TypeScript
// mesh's (`@wire.head_line`, held line for line in src/wire/wire_test.mbt).

///|
/// A link let in, with its shell, peer and mesh.
fn linked() -> (Stood, Peer, Mesh, Link) raise {
  let (stood, far) = Stood::with_peer()
  let mesh = stood.mesh()
  let link = stood.opened(mesh, Source::new().gives())
  (stood, far, mesh, link)
}

///|
/// What an ended fiber gave; the test's mistake where it has not ended so.
fn[X] gave(fiber : @effect.Fiber[X]) -> X raise {
  guard fiber.poll() is Some(Succeeded(x)) else { fail("it did not end well: \{ended_as(fiber)}") }
  x
}

///|
let cut_said : String = "mesh: " + say("cut")

// ── a request's head and body ──

///|
test "a request with further fields in its head: they follow its headers on the line, as written; with no body it is the line alone, finished" {
  let (stood, far, _, link) = linked()
  let more : Map[String, Json] = { "adb": { "offer": true, "connect": 5555 }, "n": 1 }
  let asked = stood.go(() => link.request("POST", "/adb", headers=[("x-a", "1")], more~).status)
  assert_eq(gave(asked), 200)
  assert_eq(
    far.asked.join("\n"),
    (
      #|0 2 {"method":"POST","path":"/adb","headers":{"x-a":"1"},"adb":{"offer":true,"connect":5555},"n":1} 0
    ),
  )
  // (one write, the line; then finished)
  assert_eq((far.wrote.length(), stood.times("istream.finish 4")), (1, 1))
  // A field of the head's own is not `more`'s to say: its program is told, and nothing is opened.
  for field in ["method", "path", "headers"] {
    let more : Map[String, Json] = Map([(field, Json::string("y"))])
    let refused = stood.go(() => link.request("GET", "/x", more~))
    assert_eq(ended_as(refused).has_prefix("invalid_params: "), true)
    let both = stood.go(() => link.duplex("GET", "/x", more~))
    assert_eq(ended_as(both).has_prefix("invalid_params: "), true)
  }
  assert_eq((stood.times("conn.openBi 2"), far.asked.length()), (2, 1))
}

///|
test "a body its sender is told of goes 64 KiB at a time, each step said once the stream took it; one not told of goes whole" {
  let (stood, far, _, link) = linked()
  let body = Bytes::makei(150_000, i => (i % 251).to_byte())
  let came : Ref[Bytes] = Ref(b"")
  far.serves = (_, body) => {
    came.val = body
    replied(201, b"")
  }
  let said : Array[Int] = []
  let asked = stood.go(() => link.request("PUT", "/file", body~, wrote=sent => said.push(sent)).status)
  assert_eq(gave(asked), 201)
  assert_eq(said, [65536, 131072, 150000])
  assert_eq(far.wrote[1:].to_owned(), ["4 65536", "4 65536", "4 18928"])
  assert_true(came.val == body)
  assert_eq(far.asked[0], "0 2 {\"method\":\"PUT\",\"path\":\"/file\",\"headers\":{}} 150000")
  // Not told of: the head, then the body in one write (stream 5).
  far.wrote.clear()
  assert_eq(gave(stood.go(() => link.request("PUT", "/file", body~).status)), 201)
  assert_eq(far.wrote[1:].to_owned(), ["5 150000"])
  assert_true(came.val == body)
  // A body of one step exactly is one step; none at all is no write and nothing said (streams 6 and 7).
  far.wrote.clear()
  said.clear()
  let step = Bytes::make(body_step, b'x')
  assert_eq(gave(stood.go(() => link.request("PUT", "/file", body=step, wrote=sent => said.push(sent)).status)), 201)
  assert_eq((said, far.wrote[1:].to_owned()), ([65536], ["6 65536"]))
  said.clear()
  assert_eq(gave(stood.go(() => link.request("PUT", "/file", wrote=sent => said.push(sent)).status)), 201)
  assert_eq((said, far.wrote.filter(one => one.has_prefix("7 ")).length()), ([], 1))
}

///|
test "a step is said only once the stream took it, and a request given up in the middle of its body is let go of: its stream reset, nothing more written or said" {
  let (stood, _, _, link) = linked()
  let body = Bytes::make(150_000, b'y')
  let said : Array[Int] = []
  // The shell's writes are the test's to answer from here.
  stood.holding = "istream.write"
  let asking = stood.go(() => link.request("PUT", "/file", body~, wrote=sent => said.push(sent)))
  assert_eq((stood.held.length(), said), (1, []))
  // The head line taken: the first step is written, and not said until it is taken too.
  stood.give("istream.write", {})
  assert_eq((stood.held.length(), said), (1, []))
  stood.give("istream.write", {})
  assert_eq((stood.held.length(), said), (1, [65536]))
  // Given up while the second step waits: the stream is reset, and the write the shell goes on with, answered
  // after, brings nothing: no third step, nothing said, nothing finished.
  asking.interrupt()
  stood.run()
  assert_eq((ended_as(asking), stood.times("istream.reset 4")), ("interrupted", 1))
  stood.give("istream.write", {})
  assert_eq((said, stood.held.length(), stood.times("istream.write 4"), stood.times("istream.finish 4")), ([65536], 0, 3, 0))
}

///|
test "a write the peer stops in the middle of a body: the request fails as cut, its stream is let go of, and only the steps taken were said" {
  let (stood, _, _, link) = linked()
  let said : Array[Int] = []
  stood.holding = "istream.write"
  let asking = stood.go(() => link.request("PUT", "/file", body=Bytes::make(150_000, b'y'), wrote=sent => said.push(sent)))
  stood.give("istream.write", {})
  stood.give("istream.write", {})
  stood.refuse("istream.write", "stopped by peer: code 3")
  assert_eq((ended_as(asking), said, stood.times("istream.reset 4"), stood.times("istream.finish 4")), (cut_said, [65536], 1, 0))
}

// ── a reply read as it comes ──

///|
test "a reply's body read as it comes is asked of the shell a piece a call: nothing is read of the peer before it is asked for" {
  let (stood, far, _, link) = linked()
  far.serves = (_, _) => [b"{\"status\":200,\"headers\":{}}\n", b"ab", b"cd", b"ef"]
  let reply = gave(stood.go(() => link.request("GET", "/long")))
  // (one read so far: the one that brought the head line)
  assert_eq(stood.times("istream.read 4"), 1)
  stood.rt.advance(tick_ms)
  assert_eq(stood.times("istream.read 4"), 1)
  let pieces : Array[Bytes?] = []
  for reads in 2..<6 {
    pieces.push(gave(stood.go(() => reply.take())))
    assert_eq(stood.times("istream.read 4"), reads)
  }
  assert_true(pieces == [Some(b"ab"), Some(b"cd"), Some(b"ef"), None])
  // (ended: asked again, it says so with nothing asked of the shell)
  assert_true(gave(stood.go(() => reply.take())) is None)
  assert_eq(stood.times("istream.read 4"), 5)
}

///|
test "a reply's stream the peer resets in the middle of its body: the read fails as cut, the stream is let go of, and the reply has ended" {
  let (stood, far, _, link) = linked()
  // (answered at its head, a piece of its body with it; the rest never comes)
  far.opens = _ => Some([b"{\"status\":200,\"headers\":{}}\nab"])
  let reply = gave(stood.go(() => link.request("GET", "/long")))
  assert_true(gave(stood.go(() => reply.take())) == Some(b"ab"))
  let reading = stood.go(() => reply.take())
  assert_eq(ended_as(reading), "waiting")
  far.reset(4, 9)
  assert_eq((ended_as(reading), stood.times("istream.reset 4")), (cut_said, 1))
  assert_true(gave(stood.go(() => reply.take())) is None)
  // And read whole, it fails the same.
  far.opens = _ => Some([b"{\"status\":200,\"headers\":{}}\nab"])
  let whole = stood.go(() => link.request("GET", "/long").rest())
  assert_eq(ended_as(whole), "waiting")
  far.reset(5, 9)
  assert_eq((ended_as(whole), stood.times("istream.reset 5")), (cut_said, 1))
}

///|
test "a reply's head longer than 64 KiB is not a peer talking: refused, and its stream let go of, a request's and a duplex's alike" {
  let (stood, far, _, link) = linked()
  let long = Bytes::make(64 * 1024 + 1, b'x')
  far.serves = (_, _) => [long]
  let asked = stood.go(() => link.request("GET", "/x"))
  assert_eq((ended_as(asked), stood.times("istream.reset 4")), ("mesh: " + say("head_too_long"), 1))
  far.opens = _ => Some([long])
  let both = stood.go(() => link.duplex("GET", "/x"))
  assert_eq((ended_as(both), stood.times("istream.reset 5")), ("mesh: " + say("head_too_long"), 1))
  // (64 KiB of a head and its newline in the next piece is one)
  far.opens = _ => None
  far.serves = (_, _) => [b"{\"status\":200,\"headers\":{\"a\":\"" + Bytes::make(64 * 1024 - 40, b'x') + b"\"}}", b"\n"]
  assert_eq(gave(stood.go(() => link.request("GET", "/x").status)), 200)
}

// ── a stream open both ways ──

///|
test "a duplex is its head line and nothing finished: the reply's head read, then what the peer sends is the reply's body as it comes and what goes out is written as it is, until each end says it has no more" {
  let (stood, far, _, link) = linked()
  // (the peer answers at the head line, the first of its frames in the same piece)
  far.opens = _ => Some([b"{\"status\":200,\"headers\":{\"kind\":\"view\"}}\nf0"])
  let more : Map[String, Json] = { "screen": { "id": 3, "audio": false } }
  let (reply, out) = gave(stood.go(() => link.duplex("GET", "/screen", headers=[("x-a", "1")], more~)))
  assert_eq((reply.status, reply.header("kind")), (200, Some("view")))
  assert_eq(
    far.asked.join("\n"),
    (
      #|0 2 {"method":"GET","path":"/screen","headers":{"x-a":"1"},"screen":{"id":3,"audio":false}} open
    ),
  )
  assert_eq((far.wrote.length(), stood.times("istream.finish 4")), (1, 0))
  // What came with the head line first, then each piece as the peer sends it.
  assert_true(gave(stood.go(() => reply.take())) == Some(b"f0"))
  let reading = stood.go(() => reply.take())
  assert_eq(ended_as(reading), "waiting")
  far.sends(4, b"f1")
  assert_true(gave(reading) == Some(b"f1"))
  // What goes out, as written, while the peer's side stays open.
  assert_eq(ended_as(stood.go(() => out.write(b"key down"))), "ok")
  assert_eq(ended_as(stood.go(() => out.write(b" key up"))), "ok")
  assert_true(far.got(4) == b"key down key up")
  // The wait for what was written to be taken ends as it is finished and taken; the peer still sends after.
  let taken = stood.go(() => out.stopped())
  assert_eq(ended_as(taken), "waiting")
  assert_eq(ended_as(stood.go(() => out.finish())), "ok")
  assert_true(gave(taken) is None)
  assert_eq(stood.times("istream.finish 4"), 1)
  far.sends(4, b"f2")
  assert_true(gave(stood.go(() => reply.take())) == Some(b"f2"))
  far.finish(4)
  assert_true(gave(stood.go(() => reply.take())) is None)
  // (read to its end and finished: not reset)
  assert_eq(stood.times("istream.reset 4"), 0)
}

///|
test "a stream open both ways read to its end is not let go of by that: it is the shell's until it is finished too, or cancelled; and it is finished once" {
  let (stood, far, _, link) = linked()
  far.opens = _ => Some(replied(200, b""))
  let (reply, out) = gave(stood.go(() => link.duplex("GET", "/screen")))
  far.finish(4)
  assert_true(gave(stood.go(() => reply.take())) is None)
  // Read to its end: nothing was reset, nothing finished, and the shell still has it.
  assert_eq((stood.times("istream.reset 4"), stood.times("istream.finish 4"), far.flows.get(4).unwrap().dropped), (0, 0, false))
  // It may still be written, and asked whether the peer stopped it.
  assert_eq(ended_as(stood.go(() => out.write(b"last"))), "ok")
  let stopped = stood.go(() => out.stopped())
  assert_eq(ended_as(stopped), "waiting")
  // Finished: let go of. Finished again, the shell (which would refuse a second) is asked nothing.
  assert_eq(ended_as(stood.go(() => out.finish())), "ok")
  assert_true(gave(stopped) is None)
  assert_true(far.flows.get(4).unwrap().dropped)
  assert_eq(ended_as(stood.go(() => out.finish())), "ok")
  assert_eq(stood.times("istream.finish 4"), 1)
  // Whether its peer stopped it is asked before that: after, it is the program's mistake, and the shell is asked
  // nothing of a stream it has let go of.
  let asked = stood.said.length()
  assert_true(ended_as(stood.go(() => out.stopped())).has_prefix("invalid_params: "))
  assert_eq(stood.said.length(), asked)
}

///|
test "whether the peer stopped a stream, of one its program cancelled: none, waiting as it is cancelled and asked after, the mesh's own answer (the shell answers that wait only as the connection ends)" {
  let (stood, far, _, link) = linked()
  far.opens = _ => Some(replied(200, b""))
  let (reply, out) = gave(stood.go(() => link.duplex("GET", "/screen")))
  let waiting = stood.go(() => out.stopped())
  assert_eq(ended_as(waiting), "waiting")
  reply.cancel()
  stood.run()
  assert_true(gave(waiting) is None)
  let asked = stood.said.length()
  assert_true(gave(stood.go(() => out.stopped())) is None)
  assert_eq(stood.said.length(), asked)
}

///|
test "whether the peer stopped a stream, of one let go of here for a write that failed or was given up: cut, waiting as it happens and asked after, the mesh's own answer; and a stop the peer did send is not said to be none" {
  // A write given up while a wait on what was written is out: the shell answers that wait only as the connection
  // ends, and the mesh answers it as the stream is let go of.
  let (stood, far, _, link) = linked()
  far.opens = _ => Some(replied(200, b""))
  let (_, out) = gave(stood.go(() => link.duplex("GET", "/screen")))
  let waiting = stood.go(() => out.stopped())
  stood.holding = "istream.write"
  let writing = stood.go(() => out.write(b"x"))
  assert_eq((ended_as(waiting), ended_as(writing)), ("waiting", "waiting"))
  writing.interrupt()
  stood.run()
  assert_eq((ended_as(writing), ended_as(waiting), stood.times("istream.reset 4")), ("interrupted", cut_said, 1))
  let asked = stood.said.length()
  assert_eq(ended_as(stood.go(() => out.stopped())), cut_said)
  assert_eq(stood.said.length(), asked)
  // The peer stops the stream with a code, and a write then fails and lets go of it: asked after, it is cut, not
  // none (what failed the write may be that stop). Waiting as the peer stops it, it is told the code.
  let (stood, far, _, link) = linked()
  far.opens = _ => Some(replied(200, b""))
  let (_, out) = gave(stood.go(() => link.duplex("GET", "/screen")))
  let waiting = stood.go(() => out.stopped())
  far.reset(4, 7)
  assert_true(gave(waiting) == Some(7))
  assert_eq(ended_as(stood.go(() => out.write(b"x"))), cut_said)
  assert_eq(ended_as(stood.go(() => out.stopped())), cut_said)
}

///|
test "a finish the shell refuses is not finished: it fails as cut, and asked again the shell is asked again" {
  let (stood, far, _, link) = linked()
  far.opens = _ => Some(replied(200, b""))
  let (_, out) = gave(stood.go(() => link.duplex("GET", "/screen")))
  stood.holding = "istream.finish"
  let finishing = stood.go(() => out.finish())
  stood.refuse("istream.finish", "no")
  assert_eq((ended_as(finishing), stood.times("istream.finish 4")), (cut_said, 1))
  stood.holding = ""
  assert_eq(ended_as(stood.go(() => out.finish())), "ok")
  assert_eq(ended_as(stood.go(() => out.finish())), "ok")
  assert_eq(stood.times("istream.finish 4"), 2)
}

///|
test "a request given up while the shell opens its stream: the stream that comes is reset, opened for nobody; and the link ended meanwhile, its asker is told so" {
  let (stood, far, mesh, link) = linked()
  stood.holding = "conn.openBi"
  let asking = stood.go(() => link.request("GET", "/x"))
  assert_eq((ended_as(asking), stood.held.length()), ("waiting", 1))
  asking.interrupt()
  stood.run()
  assert_eq(ended_as(asking), "interrupted")
  // The shell opens it all the same (handle 4): reset as it comes, nothing written on it.
  stood.last += 1
  stood.give("conn.openBi", { "id": 4 })
  assert_eq((stood.times("istream.reset 4"), stood.times("istream.write 4"), far.asked.length()), (1, 0, 0))
  // A duplex's, given up in the turn the stream comes, before it took it: reset too.
  let both = stood.go(() => link.duplex("GET", "/screen"))
  stood.last += 1
  stood.answered("conn.openBi", { "id": 5 })
  both.interrupt()
  stood.run()
  assert_eq((ended_as(both), stood.times("istream.reset 5"), stood.times("istream.write 5")), ("interrupted", 1, 0))
  // The mesh closed while one is being opened: the asker is told, not left waiting on a fiber that was cut.
  let last = stood.go(() => link.request("GET", "/x"))
  assert_eq(ended_as(last), "waiting")
  assert_eq(ended_as(stood.go(() => mesh.close())), "ok")
  assert_eq(ended_as(last), cut_said)
}

///|
test "known, and the shell's: a read that waits as its connection ends may be answered the stream's end, and a reply cut so passes for whole" {
  let (stood, far, _, link) = linked()
  // A reply of which "ab" came, the rest never: its connection ends while the read for more waits.
  far.opens = _ => Some([b"{\"status\":200,\"headers\":{\"content-length\":\"6\"}}\nab"])
  let whole = stood.go(() => {
    let reply = link.request("GET", "/long")
    (reply.header("content-length"), reply.rest())
  })
  assert_eq(ended_as(whole), "waiting")
  far.cut_as_end = true
  far.end(2, "bye")
  // The mesh is told an end and has no length of its own to hold a body to: two bytes of six, given as all of it.
  // What a reply's head says of its length is its program's to hold it to.
  assert_true(gave(whole) == (Some("6"), b"ab"))
  // Answered a failure, as the page's shell and the stood-in peer otherwise do, it is cut.
  let (stood, far, _, link) = linked()
  far.opens = _ => Some([b"{\"status\":200,\"headers\":{}}\nab"])
  let cut = stood.go(() => link.request("GET", "/long").rest())
  far.end(2, "bye")
  assert_eq(ended_as(cut), cut_said)
}

///|
test "a socket is a duplex whose head says so; let go of by cancelling its reply, it is stopped both ways and nothing more is written" {
  let (stood, far, _, link) = linked()
  far.opens = _ => Some(replied(101, b""))
  let (reply, out) = gave(stood.go(() => link.duplex("GET", "/ws", more={ "socket": true })))
  assert_eq(reply.status, 101)
  assert_eq(far.asked[0], "0 2 {\"method\":\"GET\",\"path\":\"/ws\",\"headers\":{},\"socket\":true} open")
  assert_eq(ended_as(stood.go(() => out.write(b"hello"))), "ok")
  reply.cancel()
  stood.run()
  assert_eq(stood.times("istream.reset 4"), 1)
  assert_true(gave(stood.go(() => reply.take())) is None)
  // (and nothing more is written on it: the write fails, with nothing asked of the shell)
  let asked = stood.said.length()
  assert_eq(ended_as(stood.go(() => out.write(b"more"))), cut_said)
  assert_eq(stood.said.length(), asked)
}

///|
test "a duplex the peer stops: the wait on what was written is told its code, a write after fails as cut and lets go of the stream, and the reply has ended" {
  let (stood, far, _, link) = linked()
  far.opens = _ => Some(replied(200, b""))
  let (reply, out) = gave(stood.go(() => link.duplex("GET", "/screen")))
  let stopped = stood.go(() => out.stopped())
  assert_eq(ended_as(stopped), "waiting")
  far.reset(4, 7)
  assert_true(gave(stopped) == Some(7))
  assert_eq(ended_as(stood.go(() => out.write(b"late"))), cut_said)
  assert_eq(stood.times("istream.reset 4"), 1)
  // Let go of: nothing more is written or read, and neither asks the shell.
  let asked = stood.said.length()
  assert_eq(ended_as(stood.go(() => out.write(b"later"))), cut_said)
  assert_eq(ended_as(stood.go(() => out.finish())), cut_said)
  assert_true(gave(stood.go(() => reply.take())) is None)
  assert_eq(stood.said.length(), asked)
}

///|
test "a write given up while the stream has not taken it lets go of the stream: what of it went is not known, so nothing is written after it, and the reply has ended" {
  let (stood, far, _, link) = linked()
  far.opens = _ => Some(replied(200, b""))
  let (reply, out) = gave(stood.go(() => link.duplex("GET", "/screen")))
  stood.holding = "istream.write"
  let writing = stood.go(() => out.write(b"half"))
  assert_eq((ended_as(writing), stood.held.length()), ("waiting", 1))
  writing.interrupt()
  stood.run()
  assert_eq((ended_as(writing), stood.times("istream.reset 4")), ("interrupted", 1))
  stood.holding = ""
  let asked = stood.said.length()
  assert_eq(ended_as(stood.go(() => out.write(b"next"))), cut_said)
  assert_true(gave(stood.go(() => reply.take())) is None)
  assert_eq(stood.said.length(), asked)
}

// ── streams the peer opens ──

///|
test "a stream the peer opens is the next the link is asked for: what the peer sends on it as it comes, what goes back as written, each end finishing its own" {
  let (stood, far, _, link) = linked()
  // Opened before anyone asked: kept by the peer's transport until asked for.
  let first = far.open(2)
  assert_eq(stood.times("conn.acceptBi 2"), 0)
  guard gave(stood.go(() => link.accept())) is Some(tunnel) else { fail("no stream given") }
  far.sends(first, b"{\"tunnel\":\"connect\"}\n")
  assert_true(gave(stood.go(() => tunnel.take())) == Some(b"{\"tunnel\":\"connect\"}\n"))
  assert_eq(ended_as(stood.go(() => tunnel.out.write(b"{\"ok\":true}\n"))), "ok")
  assert_true(far.got(first) == b"{\"ok\":true}\n")
  far.sends(first, b"bytes")
  far.finish(first)
  assert_true(gave(stood.go(() => tunnel.take())) == Some(b"bytes"))
  // Finished, and what was written taken (the peer did not stop it), before it is read to its end: with the last
  // of the two the shell lets go of the stream, and nothing is asked of it after.
  assert_eq(ended_as(stood.go(() => tunnel.out.finish())), "ok")
  assert_true(gave(stood.go(() => tunnel.out.stopped())) is None)
  assert_true(gave(stood.go(() => tunnel.take())) is None)
  assert_eq((stood.times("istream.finish \{first}"), stood.times("istream.reset \{first}")), (1, 0))
  assert_true(far.flows.get(first).unwrap().dropped)
  let asked = stood.said.length()
  assert_true(ended_as(stood.go(() => tunnel.out.stopped())).has_prefix("invalid_params: "))
  assert_eq(ended_as(stood.go(() => tunnel.out.finish())), "ok")
  assert_true(gave(stood.go(() => tunnel.take())) is None)
  assert_eq(stood.said.length(), asked)
  // Asked for before the peer opens one: it waits, and is given it as it is opened.
  let waiting = stood.go(() => link.accept())
  assert_eq(ended_as(waiting), "waiting")
  let second = far.open(2)
  guard gave(waiting) is Some(other) else { fail("no stream given") }
  far.sends(second, b"x")
  assert_true(gave(stood.go(() => other.take())) == Some(b"x"))
  // Let go of: stopped both ways.
  other.cancel()
  stood.run()
  assert_eq(stood.times("istream.reset \{second}"), 1)
  assert_true(gave(stood.go(() => other.take())) is None)
  assert_eq(ended_as(stood.go(() => other.out.write(b"y"))), cut_said)
  // One the peer stops while it is read: the read fails as cut, the stream is let go of, and it has ended.
  let third = far.open(2)
  guard gave(stood.go(() => link.accept())) is Some(stopped) else { fail("no stream given") }
  let reading = stood.go(() => stopped.take())
  assert_eq(ended_as(reading), "waiting")
  far.reset(third, 5)
  assert_eq((ended_as(reading), stood.times("istream.reset \{third}")), (cut_said, 1))
  let asked = stood.said.length()
  assert_true(gave(stood.go(() => stopped.take())) is None)
  assert_eq(ended_as(stood.go(() => stopped.out.write(b"z"))), cut_said)
  assert_eq(stood.said.length(), asked)
}

///|
test "a link that ended asks the shell for no stream of the peer's, and one whose hello was refused says that refusal of a duplex as of a request" {
  let (stood, far, _, link) = linked()
  far.end(2, "bye")
  assert_true(gave(stood.go(() => link.accept())) is None)
  assert_eq(stood.times("conn.acceptBi 2"), 0)
  let (stood, far) = Stood::with_peer()
  far.answers = (_, _) => Some("{\"error\":\"credential_expired\"}")
  let refused = stood.opened(stood.mesh(), Source::new().gives())
  let told = "credential_refused: " + say("credential_refused_why", args={ "reason": "credential_expired" })
  assert_eq(ended_as(stood.go(() => refused.duplex("GET", "/screen"))), told)
  assert_eq(ended_as(stood.go(() => refused.request("GET", "/x", more={ "a": 1 }))), told)
}

///|
test "an asker that gives up waiting for a stream of the peer's loses none: the shell is asked once, and the stream that wait brings is the next asker's; two askers are given one each" {
  let (stood, far, _, link) = linked()
  let first = stood.go(() => link.accept())
  assert_eq((ended_as(first), stood.times("conn.acceptBi 2")), ("waiting", 1))
  first.interrupt()
  stood.run()
  assert_eq(ended_as(first), "interrupted")
  // The peer opens one now: nobody waits, and the shell's wait, still under way, takes it.
  let opened = far.open(2)
  assert_eq(far.offered.get(2).map(streams => streams.length()).unwrap_or(0), 0)
  // The next asker is given that one at once, with no other wait asked of the shell.
  guard gave(stood.go(() => link.accept())) is Some(tunnel) else { fail("no stream given") }
  assert_eq(stood.times("conn.acceptBi 2"), 1)
  far.sends(opened, b"it")
  assert_true(gave(stood.go(() => tunnel.take())) == Some(b"it"))
  // Two ask at once: one wait at the shell at a time, and each stream the peer opens goes to one of them.
  let one = stood.go(() => link.accept())
  let two = stood.go(() => link.accept())
  assert_eq((ended_as(one), ended_as(two), stood.times("conn.acceptBi 2")), ("waiting", "waiting", 2))
  ignore(far.open(2))
  assert_eq((ended_as(one), ended_as(two), stood.times("conn.acceptBi 2")), ("ok", "waiting", 3))
  ignore(far.open(2))
  assert_eq((ended_as(one), ended_as(two), stood.times("conn.acceptBi 2")), ("ok", "ok", 3))
  assert_true(gave(one) is Some(_) && gave(two) is Some(_))
}

// ── the link gone, the mesh closed ──

///|
/// On a link: a duplex whose reply is being read (stream 4), a wait on what was written on it, a request waiting
/// for its reply's head (stream 5, the peer keeping its answer back), and a wait for a stream of the peer's.
fn all_waiting(
  stood : Stood,
  far : Peer,
  link : Link,
) -> (@effect.Fiber[Bytes?], @effect.Fiber[Int?], @effect.Fiber[Reply], @effect.Fiber[Inbound?], Reply, Out) raise {
  far.opens = head => if head.contains("/screen") { Some(replied(200, b"")) } else { None }
  let (reply, out) = gave(stood.go(() => link.duplex("GET", "/screen")))
  let reading = stood.go(() => reply.take())
  let stopped = stood.go(() => out.stopped())
  far.holds = true
  let asking = stood.go(() => link.request("GET", "/slow"))
  let accepting = stood.go(() => link.accept())
  assert_eq((ended_as(reading), ended_as(stopped), ended_as(asking), ended_as(accepting)), ("waiting", "waiting", "waiting", "waiting"))
  (reading, stopped, asking, accepting, reply, out)
}

///|
test "a link let go of by its program with streams open on it: every wait on them is told, as cut or as no stream to come, each stream is let go of, and what is asked of them after fails without the shell" {
  let (stood, far, mesh, link) = linked()
  let (reading, stopped, asking, accepting, reply, out) = all_waiting(stood, far, link)
  mesh.drop_link(peer, reason="gone")
  stood.run()
  assert_eq(far.closes, ["2 gone"])
  assert_eq((ended_as(reading), ended_as(stopped), ended_as(asking)), (cut_said, cut_said, cut_said))
  assert_true(gave(accepting) is None)
  // (the reply's stream whose read failed, and the request's that had no head yet, are reset)
  assert_eq((stood.times("istream.reset 4"), stood.times("istream.reset 5")), (1, 1))
  // After: the reply has ended, a write fails and nothing comes; none of it asks the shell of the connection.
  assert_true(gave(stood.go(() => reply.take())) is None)
  assert_eq(ended_as(stood.go(() => out.write(b"late"))), cut_said)
  let asked = stood.times("conn.acceptBi 2") + stood.times("conn.openBi 2")
  assert_true(gave(stood.go(() => link.accept())) is None)
  assert_eq(ended_as(stood.go(() => link.duplex("GET", "/screen"))), cut_said)
  assert_eq(ended_as(stood.go(() => link.request("GET", "/x", body=b"abc", wrote=_ => ()))), cut_said)
  assert_eq(stood.times("conn.acceptBi 2") + stood.times("conn.openBi 2"), asked)
}

///|
test "a connection the peer ends with streams open on it: every wait on them is told, and the link gives no more streams" {
  let (stood, far, _, link) = linked()
  let (reading, stopped, asking, accepting, _, _) = all_waiting(stood, far, link)
  far.end(2, "bye")
  assert_eq((ended_as(reading), ended_as(stopped), ended_as(asking)), (cut_said, cut_said, cut_said))
  assert_true(gave(accepting) is None)
  assert_true(gave(stood.go(() => link.accept())) is None)
}

///|
test "the mesh closed with streams open on a link: every wait on them is told, at whichever turn of asking for a stream of the peer's it closes" {
  for late in 0..<4 {
    let (stood, far, mesh, link) = linked()
    let (reading, stopped, asking, _, _, _) = all_waiting(stood, far, link)
    // (one more asker, begun in the turn the mesh closes: its wait at the shell may never be asked)
    let last = stood.start(() => link.accept())
    let closing = stood.start(() => {
      for _ in 0..<late {
        @effect.pause()
      }
      mesh.close()
    })
    stood.run()
    assert_eq(ended_as(closing), "ok")
    assert_eq((ended_as(reading), ended_as(stopped), ended_as(asking)), (cut_said, cut_said, cut_said))
    assert_true(gave(last) is None)
    assert_true(gave(stood.go(() => link.accept())) is None)
    // (the endpoint closed once; after it only the streams let go of by those told)
    assert_eq(stood.times("iroh.close 1"), 1)
    let after = stood.said[stood.said.search("iroh.close 1").unwrap() + 1:].to_owned()
    assert_eq(after.filter(op => !op.has_prefix("istream.reset ")), [])
  }
}

///|
test "a stream of the peer's asked for in the turn the mesh closes, before the mesh's wait for it took a step: the asker is told there is none" {
  let (stood, _, mesh, link) = linked()
  let accepting = stood.start(() => link.accept())
  let closing = stood.start(() => mesh.close())
  stood.run()
  assert_eq(ended_as(closing), "ok")
  assert_true(gave(accepting) is None)
  // (cut before its first step, the mesh's wait never asked the shell)
  assert_eq(stood.times("conn.acceptBi 2"), 0)
}
