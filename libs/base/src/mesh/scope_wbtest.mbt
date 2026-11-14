// Links by scope and peer, on the peer that answers by itself (stood_wbtest.mbt): one peer in two scopes, the link
// there is now (`Mesh::current`), a link let go of by its program (`Mesh::drop_link`), whoever holds one told it is
// no more the one there (`Mesh::replaced`), and what each of those must look at again after it waited.

///|
/// Whether `link` is the one `mesh` has now to `peer` in `scope`.
fn Mesh::has(self : Mesh, link : Link, scope? : String = "") -> Bool {
  self.current(peer, scope~) is Some(now) && physical_equal(now, link)
}

///|
test "one peer in two scopes: a link each, on a connection of its own, let in by its own credential and renewed with its own" {
  let (stood, far) = Stood::with_peer()
  let mesh = stood.mesh()
  let one = Source::new(of="a")
  let two = Source::new(of="b")
  let a = stood.opened(mesh, one.gives(), scope="one")
  let b = stood.opened(mesh, two.gives(), scope="two")
  assert_true(!physical_equal(a, b))
  assert_eq((a.peer, a.scope, b.peer, b.scope), (peer, "one", peer, "two"))
  // Dialled twice, to the one peer, each hello its scope's credential.
  assert_eq(far.dials, [0L, 0L])
  assert_eq(
    far.heard.join("\n"),
    (
      #|0 2 {"credential":"a1"}
      #|0 4 {"credential":"b1"}
    ),
  )
  // Asked for again, each is the one there, and so says `current`, which dials nothing: not for a scope with no
  // link either, which a program that names none has as well.
  assert_true(physical_equal(stood.opened(mesh, one.gives(), scope="one"), a))
  assert_true(physical_equal(stood.opened(mesh, two.gives(), scope="two"), b))
  assert_true(mesh.has(a, scope="one") && mesh.has(b, scope="two"))
  assert_true(mesh.current(peer) is None && mesh.current(peer, scope="three") is None)
  assert_eq(far.dials.length(), 2)
  // Each is renewed with a credential of its own source, on its own connection, and pinged with that from then on.
  far.takes = 20
  stood.rt.advance(renew_ms)
  assert_eq(first_saying(far.heard, "a2"), "300000 2 {\"credential\":\"a2\"}")
  assert_eq(first_saying(far.heard, "b2"), "300000 4 {\"credential\":\"b2\"}")
  stood.rt.advance(2 * tick_ms)
  assert_eq((a.credential, b.credential), ("a2", "b2"))
  for line in far.heard {
    assert_true(!line.contains(" 2 {\"credential\":\"b") && !line.contains(" 4 {\"credential\":\"a"))
  }
  assert_eq((one.asked, two.asked), (["kept", "kept"], ["kept", "kept"]))
  assert_true(a.usable() && b.usable())
}

///|
test "a renewal refused in one scope: that link alone is no more usable and is opened again, the other's stays as it was" {
  let (stood, far) = Stood::with_peer()
  let mesh = stood.mesh()
  let one = Source::new(of="a")
  let two = Source::new(of="b")
  far.answers = (line, _) => Some(if line.contains("\"b2\"") { "{\"error\":\"credential_revoked\"}" } else { "{\"ok\":true}" })
  let a = stood.opened(mesh, one.gives(), scope="one")
  let b = stood.opened(mesh, two.gives(), scope="two")
  stood.rt.advance(renew_ms)
  assert_true(a.usable() && !b.usable())
  assert_eq(a.credential, "a2")
  let again = stood.opened(mesh, two.gives(), scope="two")
  assert_true(!physical_equal(again, b) && again.usable())
  assert_true(mesh.has(again, scope="two"))
  // (the third dial is the second scope's; the first scope's link was neither dialled for nor asked a credential)
  assert_eq(far.dials.length(), 3)
  assert_true(physical_equal(stood.opened(mesh, one.gives(), scope="one"), a))
  assert_eq((one.asked, two.asked), (["kept", "kept"], ["kept", "kept", "kept"]))
}

///|
test "three pings missed in one scope: that scope's link is let go and dialled anew in its scope, with its own credential; the other scope's is not touched" {
  let (stood, far) = Stood::with_peer()
  let mesh = stood.mesh()
  let one = Source::new(of="a")
  let two = Source::new(of="b")
  // The peer lets every hello in, and refuses each ping that presents a credential of the first scope's.
  far.answers = (line, hello) => Some(if !hello && line.contains("\"a") { "{\"error\":\"not now\"}" } else { "{\"ok\":true}" })
  let a = stood.opened(mesh, one.gives(), scope="one")
  let b = stood.opened(mesh, two.gives(), scope="two")
  stood.rt.advance(3 * tick_ms)
  assert_true(!a.usable() && b.usable())
  assert_eq((a.missed, b.missed), (3, 0))
  assert_eq(far.closes, ["2 closed"])
  // Dialled anew at that tick: connection 6, its hello the first scope's next credential, the link that scope's.
  assert_eq(far.dials, [0L, 0L, 15000L])
  assert_eq(first_saying(far.heard, "a2"), "15000 6 {\"credential\":\"a2\"}")
  guard mesh.current(peer, scope="one") is Some(again) else { fail("no link in the scope whose link was let go") }
  assert_true(!physical_equal(again, a) && again.usable())
  assert_eq(again.scope, "one")
  assert_true(mesh.has(b, scope="two") && mesh.current(peer) is None)
  assert_eq((one.asked, two.asked), (["kept", "kept"], ["kept"]))
}

///|
test "a link let go of by its program: closed with the reason it gives, no more the one there, the next asked for dialled anew; the same peer's link in another scope stays" {
  let (stood, far) = Stood::with_peer()
  let mesh = stood.mesh()
  let one = Source::new(of="a")
  let two = Source::new(of="b")
  let a = stood.opened(mesh, one.gives(), scope="one")
  let b = stood.opened(mesh, two.gives(), scope="two")
  mesh.drop_link(peer, scope="one", reason="signed out")
  stood.run()
  // The peer is told the program's reason, on that scope's connection alone.
  assert_eq(far.closes, ["2 signed out"])
  assert_true(mesh.current(peer, scope="one") is None)
  assert_true(!a.usable())
  guard a.ended() is Some(why) else { fail("a link let go of says it has not ended") }
  assert_eq(why.kind, "local")
  // The other scope's is the one there still, usable, and pinged on.
  assert_true(mesh.has(b, scope="two") && b.usable())
  stood.rt.advance(tick_ms)
  assert_eq(
    far.heard.join("\n"),
    (
      #|0 2 {"credential":"a1"}
      #|0 4 {"credential":"b1"}
      #|5000 4 {"credential":"b1"}
    ),
  )
  // Nothing dials for the one let go of by itself; asked for, it is dialled anew, with the credential its source has.
  assert_eq(far.dials.length(), 2)
  let again = stood.opened(mesh, one.gives(), scope="one")
  assert_true(!physical_equal(again, a) && again.usable() && mesh.has(again, scope="one"))
  assert_eq(far.dials, [0L, 0L, 5000L])
  assert_eq(one.asked, ["kept", "kept"])
  // With no reason said the peer is told "closed", as by `Link::close`.
  mesh.drop_link(peer, scope="two")
  stood.run()
  assert_eq(far.closes, ["2 signed out", "4 closed"])
  // And where there is none to let go of, nothing is done.
  mesh.drop_link(peer)
  mesh.drop_link(peer, scope="three")
  stood.run()
  assert_eq(far.closes.length(), 2)
  assert_true(again.usable() && mesh.has(again, scope="one"))
}

///|
test "whoever holds a link is told once each time it is no more the one at its place: not by its pings, its renewal or its end, but as another is opened there, as it is let go for its pings or by its program, and at the close" {
  let (stood, far) = Stood::with_peer()
  let mesh = stood.mesh()
  let source = Source::new()
  let first = stood.opened(mesh, source.gives())
  // A holder as one that reads a stream on a link is: told its link was replaced, it asks for the link again and
  // goes on with that one.
  let told = Ref(0)
  let held : Ref[Link] = Ref(first)
  let holder = stood.go(() => {
    while true {
      mesh.replaced(held.val)
      told.val += 1
      held.val = mesh.link(peer, source.gives())
    }
  })
  // Its pings and two renewals: the link is the one there throughout.
  stood.rt.advance(2 * renew_ms + tick_ms)
  assert_eq(told.val, 0)
  // The peer ends its connection: ended, it is still the one there (its end is `Link::closed`'s to tell) until
  // someone asks for the link again and another is opened in its place.
  far.end(2, "bye")
  assert_eq(told.val, 0)
  assert_true(mesh.has(first) && !first.usable())
  let second = stood.opened(mesh, source.gives())
  assert_eq(told.val, 1)
  assert_true(!physical_equal(second, first) && physical_equal(held.val, second))
  assert_eq(far.dials, [0L, 605000L])
  // Three pings missed: told as it is let go, and the holder's asking and the mesh's own dial are one dial (the
  // mesh's opening is the place's in the step the link is let go in, and the holder, told, joins it).
  far.quiet = true
  stood.rt.advance(2 * tick_ms + ping_timeout_ms)
  assert_eq((second.missed, told.val), (2, 1))
  far.quiet = false
  stood.rt.advance(tick_ms)
  assert_eq(told.val, 2)
  assert_eq(far.dials, [0L, 605000L, 623000L])
  let third = held.val
  assert_true(!physical_equal(third, second) && third.usable() && mesh.has(third))
  // Let go of by its program: told, and the holder's asking dials anew.
  mesh.drop_link(peer, reason="gone")
  stood.run()
  assert_eq(told.val, 3)
  assert_eq(far.dials.length(), 4)
  let fourth = held.val
  assert_true(!physical_equal(fourth, third) && fourth.usable() && mesh.has(fourth))
  // What becomes of a link in another scope tells this one's holder nothing.
  ignore(stood.opened(mesh, Source::new(of="b").gives(), scope="other"))
  mesh.drop_link(peer, scope="other")
  stood.run()
  stood.rt.advance(tick_ms)
  assert_eq(told.val, 3)
  // The mesh closed: told, and asking for the link again says so.
  assert_eq(ended_as(stood.go(() => mesh.close())), "ok")
  assert_eq(told.val, 4)
  assert_eq(ended_as(holder), "mesh: " + say("closed"))
}

///|
test "everyone who holds a link is told as it is replaced, and one asked of a link that is no more the one there is told at once" {
  let (stood, far) = Stood::with_peer()
  let mesh = stood.mesh()
  let source = Source::new()
  let link = stood.opened(mesh, source.gives())
  let one = stood.go(() => mesh.replaced(link))
  let other = stood.go(() => mesh.replaced(link))
  stood.rt.advance(tick_ms)
  assert_eq((ended_as(one), ended_as(other)), ("waiting", "waiting"))
  mesh.drop_link(peer)
  stood.run()
  assert_eq((ended_as(one), ended_as(other)), ("ok", "ok"))
  // Asked after: at once, while there is none there, while another is being opened there, and once that is open.
  assert_eq(ended_as(stood.go(() => mesh.replaced(link))), "ok")
  far.away = true
  let opening = stood.go(() => mesh.link(peer, source.gives()))
  assert_eq(ended_as(opening), "waiting")
  assert_true(mesh.current(peer) is None)
  assert_eq(ended_as(stood.go(() => mesh.replaced(link))), "ok")
  far.away = false
  stood.dialled()
  guard opening.poll() is Some(Succeeded(next)) else { fail("the link did not open: \{ended_as(opening)}") }
  assert_eq(ended_as(stood.go(() => mesh.replaced(link))), "ok")
  // (and the new one's holder waits)
  assert_eq(ended_as(stood.go(() => mesh.replaced(next))), "waiting")
}

// ── looked at again after a wait ──

///|
test "a link let go of while it is being opened: whoever waits for it is told closed, its dial is given up, and the next asked for is dialled anew" {
  let (stood, far) = Stood::with_peer()
  let mesh = stood.mesh()
  let source = Source::new()
  far.away = true
  // (the one that dials, and one that joins its opening)
  let first = stood.go(() => mesh.link(peer, source.gives()))
  let second = stood.go(() => mesh.link(peer, source.gives()))
  assert_eq((ended_as(first), ended_as(second)), ("waiting", "waiting"))
  mesh.drop_link(peer)
  stood.run()
  assert_eq((ended_as(first), ended_as(second)), ("mesh: " + say("closed"), "mesh: " + say("closed")))
  // (given up at the shell, not left going until its time runs out)
  assert_eq(stood.held.length(), 0)
  assert_true(mesh.current(peer) is None)
  // Nothing comes of it later, and nothing dials by itself.
  stood.rt.advance(2 * connect_timeout_ms)
  assert_eq(far.dials, [0L])
  far.away = false
  let link = stood.opened(mesh, source.gives())
  assert_true(link.usable() && mesh.has(link))
  assert_eq(far.dials.length(), 2)
  // And the mesh closes with nobody left waiting on the opening let go of.
  assert_eq(ended_as(stood.go(() => mesh.close())), "ok")
}

///|
test "a link let go of while being opened whose dial the shell could not stop: the connection that comes after is closed to be forgotten, and the link asked for meanwhile stays the one there" {
  let (stood, far) = Stood::with_peer()
  let mesh = stood.mesh()
  let source = Source::new()
  far.away = true
  stood.cancels = false
  let first = stood.go(() => mesh.link(peer, source.gives()))
  mesh.drop_link(peer)
  stood.run()
  assert_eq(ended_as(first), "mesh: " + say("closed"))
  // (its dial goes on at the shell)
  assert_eq(stood.held.length(), 1)
  // Asked for again: another opening, its connection 2.
  far.away = false
  let link = stood.opened(mesh, source.gives())
  assert_true(link.usable() && mesh.has(link))
  // The first dial's connection comes now (3 is the link's control stream, so it is 4): closed, to be forgotten, no
  // stream opened on it, and the link there is the one asked for after.
  stood.dialled()
  assert_eq(stood.times("conn.close 4"), 1)
  assert_true(stood.forgot.contains(4))
  assert_eq(stood.times("conn.openBi 4"), 0)
  assert_true(link.usable() && mesh.has(link))
  assert_eq(far.closes, ["4 opening ended"])
}

///|
test "a link let go of in the turn its dial is answered: the connection is closed to be forgotten, whoever waited is told closed, and no link is there" {
  let (stood, far) = Stood::with_peer()
  let mesh = stood.mesh()
  let source = Source::new()
  far.away = true
  let first = stood.go(() => mesh.link(peer, source.gives()))
  // The dial is answered and, before the opening took a step on with it, its program lets go of the link.
  stood.dial_answered()
  mesh.drop_link(peer)
  stood.run()
  assert_eq(ended_as(first), "mesh: " + say("closed"))
  assert_true(mesh.current(peer) is None)
  assert_eq(stood.times("conn.close 2"), 1)
  assert_true(stood.forgot.contains(2))
  // Nothing of it is left going: no ping a tick later, no renewal.
  let asked = stood.said.length()
  stood.rt.advance(renew_ms)
  assert_eq(stood.said.length(), asked)
  far.away = false
  let link = stood.opened(mesh, source.gives())
  assert_true(link.usable() && mesh.has(link))
}

///|
test "a link let go of at each turn of its opening from its hello on: cut before it is handed out or let go of just after, its connection is closed once, no link is there and nothing of it goes on" {
  let cut = Ref(0)
  let handed = Ref(0)
  for late in 0..<6 {
    let (stood, far) = Stood::with_peer()
    let mesh = stood.mesh()
    let source = Source::new()
    far.away = true
    let first = stood.go(() => mesh.link(peer, source.gives()))
    // The dial is answered, and a fiber lets go of the link `late` turns after its hello was written: before the
    // opening's last step, in the turn it hands the link out, or before the link's own fibers took their first.
    stood.dial_answered()
    let dropping = stood.start(() => {
      // (looked at between the others' steps, for far more turns than an opening takes)
      for turns = 0; far.heard.length() == 0; turns = turns + 1 {
        guard turns < 1000 else { fail("the opening sent no hello in 1000 turns") }
        @effect.pause()
      }
      for _ in 0..<late {
        @effect.pause()
      }
      mesh.drop_link(peer, reason="gone")
    })
    stood.run()
    assert_eq(ended_as(dropping), "ok")
    match first.poll() {
      // Handed out already: let go of as any open link, the peer told the program's reason.
      Some(Succeeded(link)) => {
        handed.val += 1
        assert_true(!link.usable())
        assert_eq(far.closes, ["2 gone"])
      }
      // Still being opened: whoever waited is told closed, and the opening closes what it had made.
      _ => {
        cut.val += 1
        assert_eq(ended_as(first), "mesh: " + say("closed"))
        assert_eq(far.closes, ["2 opening ended"])
      }
    }
    assert_true(mesh.current(peer) is None)
    assert_eq(mesh.live.length(), 0)
    // Nothing of it goes on: no ping, no renewal, no dial.
    let asked = stood.said.length()
    stood.rt.advance(renew_ms)
    assert_eq(stood.said.length(), asked)
    assert_eq(far.dials, [0L])
    assert_eq(ended_as(stood.go(() => mesh.close())), "ok")
  }
  // (both sides of the hand-out were let go of: were an opening to take more turns, more are to be tried here)
  assert_true(cut.val > 0 && handed.val > 0)
}

///|
/// A link whose third ping in a row is out, the first two refused outright: its mesh, the peer and the link. The
/// clock is at 15 s, and the ping's time runs out at 18 s.
fn third_ping_out() -> (Stood, Peer, Mesh, Link, Source) raise {
  let (stood, far) = Stood::with_peer()
  let mesh = stood.mesh()
  let source = Source::new()
  far.answers = (_, hello) => Some(if hello { "{\"ok\":true}" } else { "{\"error\":\"not now\"}" })
  let link = stood.opened(mesh, source.gives())
  stood.rt.advance(2 * tick_ms)
  assert_eq(link.missed, 2)
  far.quiet = true
  stood.rt.advance(tick_ms)
  assert_eq(far.heard.length(), 4)
  assert_true(link.usable())
  (stood, far, mesh, link, source)
}

///|
test "a link let go of by its program while its third ping is out: the ping's verdict dials nothing for it" {
  let (stood, far, mesh, link, _) = third_ping_out()
  mesh.drop_link(peer, reason="gone")
  stood.run()
  assert_eq(far.closes, ["2 gone"])
  stood.rt.advance(ping_timeout_ms)
  assert_eq(link.missed, 3)
  // (let go of by its program, it is not the mesh's to dial for: only who asks next does)
  stood.rt.advance(10 * tick_ms)
  assert_eq(far.dials, [0L])
  assert_true(mesh.current(peer) is None)
}

///|
test "a link let go of by its program while its third ping is out, and asked for again meanwhile: the ping's verdict leaves the opening that is the place's now, and dials none beside it" {
  let (stood, far, mesh, link, source) = third_ping_out()
  mesh.drop_link(peer)
  stood.run()
  // Asked for again, its dial not yet answered as the ping's time runs out.
  far.away = true
  let asked = stood.go(() => mesh.link(peer, source.gives()))
  assert_eq(far.dials, [0L, 15000L])
  stood.rt.advance(ping_timeout_ms)
  assert_eq(link.missed, 3)
  assert_eq(ended_as(asked), "waiting")
  assert_eq(far.dials.length(), 2)
  // The dial is answered: that link is the place's, and whoever waits on a link there is told of it alone.
  far.away = false
  far.quiet = false
  far.answers = (_, _) => Some("{\"ok\":true}")
  stood.dialled()
  guard asked.poll() is Some(Succeeded(next)) else { fail("the link did not open: \{ended_as(asked)}") }
  assert_true(next.usable() && mesh.has(next))
  let replaced = stood.go(() => mesh.replaced(next))
  stood.rt.advance(3 * tick_ms)
  assert_eq(ended_as(replaced), "waiting")
  assert_eq(far.dials.length(), 2)
}

///|
test "a link let go for its pings whose holder, as it is told, has the place let go of: the mesh's own dial for it is ended there, and nothing is dialled for a link its program let go of" {
  let (stood, far, mesh, link, _) = third_ping_out()
  // A holder as a program signing out is: told its link is no more the one there, it lets go of the place. It runs
  // in the turn the link is let go for its pings, before anything the mesh forked there takes a step.
  let found : Ref[Link?] = Ref(Some(link))
  let holder = stood.go(() => {
    mesh.replaced(link)
    found.val = mesh.current(peer)
    mesh.drop_link(peer, reason="signed out")
  })
  assert_eq(ended_as(holder), "waiting")
  // (the peer would answer a dial, and let its hello in)
  far.quiet = false
  far.answers = (_, _) => Some("{\"ok\":true}")
  stood.rt.advance(ping_timeout_ms)
  assert_eq(link.missed, 3)
  assert_eq(ended_as(holder), "ok")
  assert_true(found.val is None)
  // The link was closed for its pings, saying so; the place let go of after is the mesh's opening for it, ended
  // before it dialled: no dial then, and none later, well past every wait the mesh has.
  assert_eq(far.closes, ["2 closed"])
  assert_eq(far.dials, [0L])
  stood.rt.advance(2 * renew_ms)
  assert_eq(far.dials, [0L])
  assert_eq(far.closes, ["2 closed"])
  assert_true(mesh.current(peer) is None)
  assert_eq((mesh.links.length(), mesh.live.length()), (0, 0))
  // Asked for again, it is dialled anew, as after any `drop_link`.
  let again = stood.opened(mesh, Source::new().gives())
  assert_true(again.usable() && mesh.has(again))
  assert_eq(far.dials.length(), 2)
  assert_eq(ended_as(stood.go(() => mesh.close())), "ok")
}
