// The mesh on a stood-in shell (stood_wbtest.mbt): what it does as it is closed, what it lets go of at the shell,
// and how much of a reply it keeps. No server, no relay, no real time.

///|
test "closed while a dial is under way: every fiber waiting for that link is told so" {
  let stood = Stood::new()
  let mesh = stood.mesh()
  let credentials : async (String, Bool) -> Presented = (_, _) => { credential: "c", also: None }
  // (the one that dials, and one that joins its opening)
  let first = stood.go(() => mesh.link(peer, credentials))
  let second = stood.go(() => mesh.link(peer, credentials))
  assert_eq(ended_as(first), "waiting")
  assert_eq(ended_as(second), "waiting")
  let closing = stood.go(() => mesh.close())
  assert_eq(ended_as(closing), "ok")
  assert_eq(ended_as(first), "mesh: " + say("closed"))
  assert_eq(ended_as(second), "mesh: " + say("closed"))
  // (and one asked of it after is told the same, at once)
  assert_eq(ended_as(stood.go(() => mesh.link(peer, credentials))), "mesh: " + say("closed"))
  // (the dial was given up at the shell, not left going)
  assert_eq(stood.held.length(), 0)
}

///|
test "closed while a link waits for the peer's answer and for its end: both waits end" {
  let stood = Stood::new()
  let mesh = stood.mesh()
  let opening = stood.go(() => mesh.link(peer, (_, _) => { credential: "c", also: None }))
  stood.dialled()
  guard opening.poll() is Some(Succeeded(link)) else { fail("the link was not handed out as its credential went") }
  // (the peer has not answered the credential, and the shell has not said the connection ended)
  let admitted = stood.go(() => link.admitted())
  let closed = stood.go(() => link.closed())
  assert_eq(ended_as(admitted), "waiting")
  assert_eq(ended_as(closed), "waiting")
  let closing = stood.go(() => mesh.close())
  assert_eq(ended_as(closing), "ok")
  assert_eq(ended_as(admitted), "mesh: " + say("closed"))
  guard closed.poll() is Some(Succeeded(why)) else { fail("the wait for its end did not end: \{ended_as(closed)}") }
  assert_eq((why.kind, why.reason), ("local", "closed"))
  assert_true(!link.usable())
}

///|
test "a link whose end the mesh was told is let go of at the shell, and still says why it ended" {
  let stood = Stood::new()
  let mesh = stood.mesh()
  let link = stood.link(mesh)
  assert_true(link.ended() is None)
  // The peer closes it: the shell says why to the one fiber that waits for it.
  stood.ended[2] = { "kind": "application", "reason": "bye" }
  stood.give("conn.closed", { "kind": "application", "reason": "bye" })
  // Closed once more now that it ended: what a page's shell forgets it by (natively nothing).
  assert_eq(stood.times("conn.close 2"), 1)
  assert_true(stood.forgot.contains(2))
  // And asked of after, it answers from what the mesh kept: the shell has no such handle any more.
  guard link.ended() is Some(why) else { fail("a link that ended says it has not") }
  assert_eq((why.kind, why.reason), ("application", "bye"))
  assert_true(!link.usable())
}

///|
test "a reply whose read failed is let go of at the shell: its stream is reset" {
  let stood = Stood::new()
  let mesh = stood.mesh()
  let link = stood.link(mesh)
  let asked = stood.go(() => link.request("GET", "/x"))
  // (its stream is handle 4: the head comes, then a read fails)
  stood.give("istream.read", {}, bytes=b"{\"status\":200,\"headers\":{}}\n")
  guard asked.poll() is Some(Succeeded(reply)) else { fail("no reply: \{ended_as(asked)}") }
  let taking = stood.go(() => reply.take())
  assert_eq(stood.times("istream.reset 4"), 0)
  stood.refuse("istream.read", "stream reset by its peer")
  assert_eq(ended_as(taking), "mesh: " + say("cut"))
  assert_eq(stood.times("istream.reset 4"), 1)
  // (and it is not read again: it ended)
  assert_eq(ended_as(stood.go(() => reply.take())), "ok")
  assert_eq(stood.times("istream.read 4"), 2)
}

///|
/// A reply to a request on `link` whose head came with nothing after it: its stream is handle `4`.
fn Stood::reply(self : Stood, link : Link) -> Reply raise {
  let asked = self.go(() => link.request("GET", "/x"))
  self.give("istream.read", {}, bytes=b"{\"status\":200,\"headers\":{}}\n")
  guard asked.poll() is Some(Succeeded(reply)) else { fail("no reply: \{ended_as(asked)}") }
  reply
}

///|
test "a reply's body is its pieces in order, joined once" {
  let stood = Stood::new()
  let link = stood.link(stood.mesh())
  let asked = stood.go(() => link.request("GET", "/x"))
  // (the first piece comes with the head's line)
  stood.give("istream.read", {}, bytes=b"{\"status\":200,\"headers\":{}}\nab")
  guard asked.poll() is Some(Succeeded(reply)) else { fail("no reply: \{ended_as(asked)}") }
  let rest = stood.go(() => reply.rest())
  stood.give("istream.read", {}, bytes=b"cd")
  stood.give("istream.read", {}, bytes=b"")
  stood.give("istream.read", {}, bytes=b"efg")
  stood.give("istream.read", { "end": true })
  guard rest.poll() is Some(Succeeded(body)) else { fail("no body: \{ended_as(rest)}") }
  assert_eq(body, b"abcdefg")
  // (read to its end and nothing more: the shell lets go of a stream finished and ended by itself)
  assert_eq(stood.times("istream.reset 4"), 0)
}

///|
test "a reply's body past the bound a device keeps by default is refused, and its stream let go of" {
  let stood = Stood::new()
  let link = stood.link(stood.mesh())
  let reply = stood.reply(link)
  let rest = stood.go(() => reply.rest())
  // 16 MiB and a byte more, a MiB a piece: refused as the piece that passes the bound comes, not read to its end.
  let piece = Bytes::make(1024 * 1024, b'x')
  for _ in 0..<16 {
    stood.give("istream.read", {}, bytes=piece)
  }
  assert_eq(ended_as(rest), "waiting")
  stood.give("istream.read", {}, bytes=b"x")
  assert_eq(ended_as(rest), "too_long: " + say("reply_unreadable"))
  assert_eq(stood.times("istream.reset 4"), 1)
  assert_eq(stood.held.length(), 1)
}

///|
test "a reply's body is kept up to the bound it is asked with, to the byte" {
  let stood = Stood::new()
  let link = stood.link(stood.mesh())
  // 7 bytes asked with 7: all of it.
  let whole = stood.reply(link)
  let rest = stood.go(() => whole.rest(most=7))
  stood.give("istream.read", {}, bytes=b"abcd")
  stood.give("istream.read", {}, bytes=b"efg")
  stood.give("istream.read", { "end": true })
  guard rest.poll() is Some(Succeeded(body)) else { fail("no body: \{ended_as(rest)}") }
  assert_eq(body, b"abcdefg")
  // Asked with 6: refused as the piece that passes it comes (its stream is handle 5), a program told so by its code.
  let long = stood.reply(link)
  let rest = stood.go(() => long.rest(most=6))
  stood.give("istream.read", {}, bytes=b"abcd")
  assert_eq(ended_as(rest), "waiting")
  stood.give("istream.read", {}, bytes=b"efg")
  guard rest.poll() is Some(Failed(e)) else { fail("a body past its bound was kept: \{ended_as(rest)}") }
  assert_eq(code_of(e), "too_long")
  assert_eq(stood.times("istream.reset 5"), 1)
  // (and nothing more is read of it)
  assert_eq(stood.times("istream.read 5"), 3)
  assert_eq(ended_as(stood.go(() => long.take())), "ok")
  assert_eq(stood.times("istream.read 5"), 3)
}

///|
test "a link that ended and was let go of asks the shell nothing more: a request on it fails as cut" {
  let stood = Stood::new()
  let link = stood.link(stood.mesh())
  stood.ended[2] = { "kind": "timeout", "reason": "" }
  stood.give("conn.closed", { "kind": "timeout", "reason": "" })
  let asked = stood.said.length()
  assert_eq(ended_as(stood.go(() => link.request("GET", "/x"))), "mesh: " + say("cut"))
  assert_true(link.ended() is Some({ kind: "timeout", .. }))
  assert_eq(stood.said.length(), asked)
}

///|
test "closed in the turn a link is asked for, before its opening took a step: the one who asked is told so" {
  let stood = Stood::new()
  let mesh = stood.mesh()
  // Asked, then closed, with nothing run between: the close cuts the opening's fiber before its first step, where a
  // fiber runs nothing at all, not even what it would have said as it was interrupted.
  let asked = stood.start(() => mesh.link(peer, (_, _) => { credential: "c", also: None }))
  let closing = stood.start(() => mesh.close())
  stood.run()
  assert_eq(ended_as(closing), "ok")
  assert_eq(stood.times("iroh.connect 1"), 0)
  assert_eq(ended_as(asked), "mesh: " + say("closed"))
}

///|
test "closed in the turn a link is handed out, before its fibers took a step: its answer and its end are still said" {
  let stood = Stood::new()
  let mesh = stood.mesh()
  let opening = stood.go(() => mesh.link(peer, (_, _) => { credential: "c", also: None }))
  // The dial is answered, and a fiber closes the mesh the moment the opening has its link: after the opening's last
  // step, before the fibers that step forked (the link's answer, its end, its renewal, its pings) have taken one.
  stood.dial_answered()
  let closing = stood.start(() => {
    // (looked at between the others' steps, for far more turns than an opening takes: one that stalled fails the
    // test here, where a wait with no bound would never give the run back)
    for turns = 0; !(mesh.links.get(peer) is Some({ result: Some(_), .. })); turns = turns + 1 {
      guard turns < 1000 else { fail("the opening handed out no link in 1000 turns") }
      @effect.pause()
    }
    mesh.close()
  })
  stood.run()
  assert_eq(ended_as(closing), "ok")
  guard opening.poll() is Some(Succeeded(link)) else { fail("the link was not handed out: \{ended_as(opening)}") }
  // (that it was so: the fiber that waits for the connection's end never asked the shell for it)
  assert_eq(stood.times("conn.closed 2"), 0)
  let admitted = stood.go(() => link.admitted())
  let closed = stood.go(() => link.closed())
  assert_eq(ended_as(admitted), "mesh: " + say("closed"))
  guard closed.poll() is Some(Succeeded(why)) else { fail("the wait for its end did not end: \{ended_as(closed)}") }
  assert_eq((why.kind, why.reason), ("local", "closed"))
  assert_true(!link.usable())
}

///|
test "an opening given up with its connection made closes it to be forgotten: a page keeps nothing of it" {
  let stood = Stood::new()
  let mesh = stood.mesh()
  // The connection is made and its first stream never opens: the opening's time runs out.
  stood.holding = "conn.openBi"
  let opening = stood.go(() => mesh.link(peer, (_, _) => { credential: "c", also: None }))
  stood.dialled()
  assert_eq(ended_as(opening), "waiting")
  stood.rt.advance(connect_timeout_ms)
  assert_eq(ended_as(opening), "mesh: " + say("no_answer"))
  assert_eq(stood.times("conn.close 2"), 1)
  assert_true(stood.forgot.contains(2))
}

///|
test "a dial that comes after its opening was given up is closed to be forgotten too" {
  let stood = Stood::new()
  let mesh = stood.mesh()
  // The shell could not stop the dial as the opening's time ran out: its connection comes after.
  stood.cancels = false
  let opening = stood.go(() => mesh.link(peer, (_, _) => { credential: "c", also: None }))
  stood.rt.advance(connect_timeout_ms)
  assert_eq(ended_as(opening), "mesh: " + say("no_answer"))
  stood.dialled()
  assert_eq(stood.times("conn.close 2"), 1)
  assert_true(stood.forgot.contains(2))
}

///|
test "a ping's verdict on a link put over meanwhile leaves the opening that is its peer's now: no dial beside it, and its waiter told at the close" {
  let stood = Stood::new()
  let mesh = stood.mesh()
  let link = stood.link(mesh)
  // Two pings fail outright (the control stream's read does), each a tick after the one before.
  for _ in 0..<2 {
    stood.rt.advance(tick_ms)
    stood.refuse("istream.read", "stream reset by its peer")
  }
  assert_eq(link.missed, 2)
  // The third is under way, waited for, as the connection ends at the shell and its peer is asked for again: a new
  // opening is put over the link's, its dial under way.
  stood.rt.advance(tick_ms)
  assert_eq(stood.times("istream.read 3"), 4)
  stood.ended[2] = { "kind": "timeout", "reason": "" }
  stood.give("conn.closed", { "kind": "timeout", "reason": "" })
  let asked = stood.go(() => mesh.link(peer, (_, _) => { credential: "c", also: None }))
  assert_eq(ended_as(asked), "waiting")
  assert_eq(stood.times("iroh.connect 1"), 2)
  // The ping's time runs out: its link is dead, and is no more its peer's. The opening that is stays, alone.
  stood.rt.advance(ping_timeout_ms)
  assert_eq(link.missed, 3)
  assert_eq(stood.times("iroh.connect 1"), 2)
  assert_eq(ended_as(asked), "waiting")
  let closing = stood.go(() => mesh.close())
  assert_eq(ended_as(closing), "ok")
  assert_eq(ended_as(asked), "mesh: " + say("closed"))
}

///|
test "the fiber that closes the mesh interrupted as it waits on the shell: whoever waited is told all the same, and the endpoint closed" {
  let stood = Stood::new()
  let mesh = stood.mesh()
  let link = stood.link(mesh)
  let closed = stood.go(() => link.closed())
  let asking = stood.go(() => mesh.link("ef".repeat(32), (_, _) => { credential: "c", also: None }))
  // The shell does not answer the close of the link's connection, and the closing fiber is asked to stop there.
  stood.holding = "conn.close"
  let closing = stood.go(() => mesh.close())
  closing.interrupt()
  stood.run()
  guard closed.poll() is Some(Succeeded(why)) else { fail("the wait for its end did not end: \{ended_as(closed)}") }
  assert_eq((why.kind, why.reason), ("local", "closed"))
  assert_eq(ended_as(asking), "mesh: " + say("closed"))
  // It stops once the close is done, not in the middle of it: the shell answers, and the endpoint is closed.
  assert_eq(ended_as(closing), "waiting")
  stood.give("conn.close", {})
  assert_eq(ended_as(closing), "interrupted")
  assert_eq(stood.times("iroh.close 1"), 1)
}
