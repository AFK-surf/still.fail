// A program's word that its connections are suspect (`Mesh::wake`): the shell told, every usable link raced, every
// opening under way tried a second time beside its first; and the endpoint bound anew where a dial found it stuck
// (wake.mbt). On the peer that answers by itself (stood_wbtest.mbt). The endpoint is handle 1; one bound anew is
// the next handle then.

///|
/// The endpoint the mesh has now, as the stood-in shell's handle.
fn Mesh::endpoint_handle(self : Mesh) -> Int {
  handle_of({ "id": self.endpoint })
}

///|
/// The dial asked last and still held is answered before the ones asked earlier.
fn Stood::last_dial_first(self : Stood) -> Unit {
  for i = self.held.length() - 1; i >= 0; i = i - 1 {
    if self.held[i].1 == "iroh.connect" {
      let last = self.held.remove(i)
      self.held.insert(0, last)
      return
    }
  }
}

// ── a wake and the links ──

///|
test "a wake tells the shell, and races every link that is its place's and usable: not one that ended, and no second race beside one under way" {
  let (stood, far) = Stood::with_peer()
  let mesh = stood.mesh()
  let a = stood.opened(mesh, Source::new(of="a").gives(), scope="one")
  let b = stood.opened(mesh, Source::new(of="b").gives(), scope="two")
  let c = stood.opened(mesh, Source::new(of="c").gives(), scope="three")
  stood.rt.advance(tick_ms)
  // The second's connection ended; the third's peer is gone from under it, and it is raced already for the ping
  // it missed, its new dial unanswered.
  far.end(4, "bye")
  far.lose(6)
  far.away = true
  stood.rt.advance(tick_ms + ping_timeout_ms)
  assert_eq((mesh.racing.length(), far.dials.length(), stood.held.length()), (1, 4, 1))
  assert_true(a.usable() && !b.usable() && c.usable())
  let told = stood.go(() => mesh.replaced(a))
  mesh.wake()
  stood.run()
  assert_eq(stood.times("iroh.networkChange 1"), 1)
  // One dial more: the first's, raced now. Asked its credential again at once, it answered: kept, the dial for the
  // new one given up, its holder told nothing. The third's race is the one that was.
  assert_eq(far.dials, [0L, 0L, 0L, 13000L, 13000L])
  assert_eq(far.heard_on(2)[far.heard_on(2).length() - 1], "13000 2 {\"credential\":\"a1\"}")
  assert_eq((mesh.racing.length(), stood.held.length(), ended_as(told)), (1, 1, "waiting"))
  assert_true(mesh.current(peer, scope="one") is Some(now) && physical_equal(now, a))
  assert_true(mesh.current(peer, scope="two") is Some(now) && physical_equal(now, b))
  assert_eq(far.closes.length(), 0)
  // A mesh with no link is told the network alone; one closed, nothing.
  let (stood, far) = Stood::with_peer()
  let mesh = stood.mesh()
  mesh.wake()
  stood.run()
  assert_eq((stood.times("iroh.networkChange 1"), far.dials.length()), (1, 0))
  assert_eq(ended_as(stood.go(() => mesh.close())), "ok")
  let said = stood.said.length()
  mesh.wake()
  stood.run()
  assert_eq(stood.said.length(), said)
}

///|
test "a link raced at a wake that answers slower than a new one opens is replaced, whatever came on it meanwhile: the race goes by the two answers alone" {
  let (stood, far, mesh, old, _) = quick_link()
  let told = stood.go(() => mesh.replaced(old))
  // The peer answers a line in 2 s from here, and a dial when the test says.
  far.takes = 2_000
  far.away = true
  stood.rx[2] = 100.0
  mesh.wake()
  stood.run()
  assert_eq((mesh.racing.length(), far.dials), (1, [0L, 5000L]))
  // A second later more came on the old connection, and the new one's dial is answered: the new link takes the
  // place (for a ping missed, what came would have kept the old one).
  stood.rt.advance(1_000)
  stood.rx[2] = 400.0
  far.away = false
  far.takes = 0
  stood.dialled()
  guard mesh.current(peer) is Some(next) else { fail("no link at the place") }
  assert_true(!physical_equal(next, old) && next.usable())
  assert_eq((mesh.racing.length(), ended_as(told), far.closes.length()), (0, "ok", 0))
  // The old one is closed 10 s later, as one replaced for its pings.
  stood.rt.advance(retire_ms)
  assert_eq(far.closes, ["2 closed"])
}

///|
test "a link raced at a wake whose peer answers neither it nor a new dial is let go as the dial gives up, and nothing is dialled until it is asked for" {
  let (stood, far, mesh, old, _) = quick_link()
  far.lose(2)
  far.away = true
  mesh.wake()
  stood.run()
  assert_eq((mesh.racing.length(), far.dials), (1, [0L, 5000L]))
  stood.rt.advance(connect_timeout_ms - 1)
  assert_true(mesh.current(peer) is Some(now) && physical_equal(now, old))
  stood.rt.advance(1)
  assert_eq((far.closes, mesh.racing.length()), (["2 closed"], 0))
  assert_true(mesh.current(peer) is None)
  stood.rt.advance(2 * renew_ms)
  assert_eq(far.dials.length(), 2)
}

// ── a wake and the openings ──

///|
/// An opening under way, its dial unanswered since 0, and a wake a second later: the second dial beside it is
/// under way too. `cancels`: whether the shell can stop a dial given up.
fn hedged(cancels? : Bool = true) -> (Stood, Peer, Mesh, Source, @effect.Fiber[Link]) raise {
  let (stood, far) = Stood::with_peer()
  let mesh = stood.mesh()
  let source = Source::new()
  far.away = true
  stood.cancels = cancels
  let asking = stood.go(() => mesh.link(peer, source.gives()))
  stood.rt.advance(1_000)
  assert_eq((far.dials, stood.held.length()), ([0L], 1))
  mesh.wake()
  stood.run()
  assert_eq((far.dials, stood.held.length(), ended_as(asking)), ([0L, 1000L], 2, "waiting"))
  assert_eq(stood.times("iroh.networkChange 1"), 1)
  far.away = false
  (stood, far, mesh, source, asking)
}

///|
test "an opening under way at a wake has a second dial tried beside its first, once: the first answering first, its link is the opening's and the second is given up" {
  for cancels in [true, false] {
    let (stood, far, mesh, source, asking) = hedged(cancels~)
    // A wake more tries no third.
    mesh.wake()
    stood.run()
    assert_eq((far.dials.length(), stood.held.length()), (2, 2))
    // The first dial is answered: connection 2, its hello the first credential asked for.
    stood.dialled()
    let link = gave(asking)
    assert_true(mesh.current(peer) is Some(now) && physical_equal(now, link))
    assert_eq(far.heard, ["1000 2 {\"credential\":\"c1\"}"])
    assert_eq(source.asked, ["kept", "kept"])
    if cancels {
      assert_eq(stood.held.length(), 0)
    } else {
      // The second, which the shell went on with: its connection (handle 4) is closed to be forgotten as it comes.
      assert_eq(stood.held.length(), 1)
      stood.dialled()
      assert_eq((stood.times("conn.close 4"), stood.times("conn.openBi 4"), far.closes), (1, 0, ["4 opening ended"]))
      assert_true(stood.forgot.contains(4))
    }
    // One link came of it, and nothing more is dialled.
    stood.rt.advance(2 * connect_timeout_ms)
    assert_eq((far.dials.length(), mesh.live.length()), (2, 1))
    assert_true(mesh.current(peer) is Some(now) && physical_equal(now, link) && link.usable())
  }
}

///|
test "the second dial answering first, its link is the opening's, said with the credential that dial asked for, and the first is given up" {
  for cancels in [true, false] {
    let (stood, far, mesh, source, asking) = hedged(cancels~)
    stood.last_dial_first()
    stood.dialled()
    let link = gave(asking)
    assert_true(mesh.current(peer) is Some(now) && physical_equal(now, link))
    assert_eq(far.heard, ["1000 2 {\"credential\":\"c2\"}"])
    assert_eq(source.asked, ["kept", "kept"])
    if cancels {
      assert_eq(stood.held.length(), 0)
    } else {
      stood.dialled()
      assert_eq((stood.times("conn.close 4"), stood.times("conn.openBi 4"), far.closes), (1, 0, ["4 opening ended"]))
    }
    stood.rt.advance(2 * connect_timeout_ms)
    assert_eq((far.dials.length(), mesh.live.length()), (2, 1))
    assert_true(link.usable())
  }
}

///|
test "an opening whose two dials both fail fails with what its first did, whichever failed first; one that fails leaves the other to end" {
  // Neither answered: the first runs out of time at 10 s and the opening waits for the second, which does at 11 s.
  let (stood, far, mesh, _, asking) = hedged()
  far.away = true
  stood.rt.advance(connect_timeout_ms - 1_000)
  assert_eq((ended_as(asking), stood.held.length()), ("waiting", 1))
  stood.rt.advance(999)
  assert_eq(ended_as(asking), "waiting")
  stood.rt.advance(1)
  assert_eq((ended_as(asking), stood.held.length()), ("mesh: " + say("no_answer"), 0))
  // (its first dial ran out of time with no connection made: the endpoint is taken for stuck)
  assert_true(mesh.stuck)
  // The second fails first, at once: the first is still waited for, and its failure is the opening's.
  let (stood, _, mesh, _, asking) = hedged()
  stood.last_dial_first()
  stood.refuse("iroh.connect", "no route")
  assert_eq((ended_as(asking), stood.held.length()), ("waiting", 1))
  stood.refuse("iroh.connect", "refused")
  assert_eq(ended_as(asking), "mesh: " + say("unreached"))
  assert_true(!mesh.stuck && mesh.current(peer) is None)
  // The second fails and the first then answers: its link is the opening's.
  let (stood, _, mesh, _, asking) = hedged()
  stood.last_dial_first()
  stood.refuse("iroh.connect", "no route")
  stood.dialled()
  let link = gave(asking)
  assert_true(mesh.current(peer) is Some(now) && physical_equal(now, link) && link.usable())
  // The first fails and the second then answers: its link is.
  let (stood, far, _, _, asking) = hedged()
  stood.refuse("iroh.connect", "no route")
  assert_eq(ended_as(asking), "waiting")
  stood.dialled()
  assert_true(gave(asking).usable())
  assert_eq(far.heard, ["1000 2 {\"credential\":\"c2\"}"])
  // The first refused at once and the second running out of time at 11 s: the opening waits for that, and fails as
  // its first did, which is no sign of an endpoint stuck.
  let (stood, far, mesh, _, asking) = hedged()
  far.away = true
  stood.refuse("iroh.connect", "no route")
  stood.rt.advance(connect_timeout_ms - 1)
  assert_eq(ended_as(asking), "waiting")
  stood.rt.advance(1)
  assert_eq((ended_as(asking), mesh.stuck), ("mesh: " + say("unreached"), false))
}

///|
test "both dials of an opening answered in one turn: one link is the opening's, the other's connection is closed, and nothing of it goes on" {
  for second_first in [false, true] {
    let (stood, far, mesh, _, asking) = hedged()
    if second_first {
      stood.last_dial_first()
    }
    // (connections 2 and 3, neither run yet)
    stood.dial_answered()
    stood.dial_answered()
    stood.run()
    let link = gave(asking)
    assert_true(mesh.current(peer) is Some(now) && physical_equal(now, link) && link.usable())
    assert_eq((mesh.live.length(), far.closes.length()), (1, 1))
    assert_true(!far.closes[0].has_prefix("\{link.conn_handle()} "))
    stood.rt.advance(2 * tick_ms)
    assert_eq((mesh.live.length(), far.closes.length(), far.dials.length()), (1, 1, 2))
    assert_true(link.usable())
  }
}

///|
test "a place let go of with both dials of its opening under way: whoever waits is told closed, both are given up, and a connection either still brings is closed to be forgotten" {
  for cancels in [true, false] {
    let (stood, far, mesh, source, asking) = hedged(cancels~)
    let other = stood.go(() => mesh.link(peer, source.gives()))
    mesh.drop_link(peer)
    stood.run()
    assert_eq((ended_as(asking), ended_as(other)), ("mesh: " + say("closed"), "mesh: " + say("closed")))
    assert_true(mesh.current(peer) is None)
    if cancels {
      assert_eq(stood.held.length(), 0)
    } else {
      assert_eq(stood.held.length(), 2)
      stood.dialled()
      stood.dialled()
      assert_eq(far.closes, ["2 opening ended", "3 opening ended"])
      assert_true(stood.forgot.contains(2) && stood.forgot.contains(3))
    }
    let said = stood.said.length()
    stood.rt.advance(2 * renew_ms)
    assert_eq((stood.said.length(), far.dials.length(), mesh.live.length(), mesh.links.length()), (said, 2, 0, 0))
  }
}

///|
test "a place let go of, or the mesh closed, at each turn from the answer of the second dial on: no link is there, whoever waited has a link that is closed or is told closed, every connection made is closed once, and nothing goes on" {
  let told = Ref(0)
  let handed = Ref(0)
  for closes in [false, true] {
    for late in 0..<10 {
      let (stood, far, mesh, _, asking) = hedged()
      stood.last_dial_first()
      stood.dial_answered()
      let ending = stood.start(() => {
        for _ in 0..<late {
          @effect.pause()
        }
        if closes {
          mesh.close()
        } else {
          mesh.drop_link(peer, reason="gone")
        }
      })
      stood.run()
      assert_eq(ended_as(ending), "ok")
      assert_true(mesh.current(peer) is None)
      match asking.poll() {
        Some(Succeeded(link)) => {
          handed.val += 1
          assert_true(!link.usable())
          assert_eq(far.closes, [if closes { "2 closed" } else { "2 gone" }])
        }
        _ => {
          told.val += 1
          assert_eq(ended_as(asking), "mesh: " + say("closed"))
          assert_eq(far.closes, ["2 opening ended"])
        }
      }
      // (the first dial, never answered, was given up at the shell)
      assert_eq((stood.held.length(), mesh.live.length(), mesh.links.length()), (0, 0, 0))
      let said = stood.said.length()
      stood.rt.advance(2 * renew_ms)
      assert_eq((stood.said.length(), far.dials.length()), (said, 2))
    }
  }
  assert_true(told.val > 0 && handed.val > 0)
}

// ── the endpoint bound anew ──

///|
/// A mesh whose one dial ran out of time with no connection made: the clock at 10 s, the endpoint taken for stuck,
/// nothing on it. The peer answers no dial.
fn stuck() -> (Stood, Peer, Mesh, Source) raise {
  let (stood, far) = Stood::with_peer()
  let mesh = stood.mesh()
  let source = Source::new()
  far.away = true
  let asking = stood.go(() => mesh.link(peer, source.gives()))
  stood.rt.advance(connect_timeout_ms)
  assert_eq(ended_as(asking), "mesh: " + say("no_answer"))
  assert_true(mesh.stuck && mesh.idle())
  (stood, far, mesh, source)
}

///|
test "a dial that ran out of time with no connection made leaves the endpoint taken for stuck: the next link binds it anew with the same key and closes the one before, then dials on the new one" {
  let (stood, far, mesh, source) = stuck()
  assert_eq((stood.times("iroh.bind 0"), mesh.endpoint_handle()), (1, 1))
  far.away = false
  let link = stood.opened(mesh, source.gives())
  // Bound once more (handle 2), the first closed once, and the dial on the new one: connection 3.
  assert_eq((stood.times("iroh.bind 0"), stood.times("iroh.close 1"), mesh.endpoint_handle()), (2, 1, 2))
  assert_eq((stood.times("iroh.connect 1"), stood.times("iroh.connect 2")), (1, 1))
  assert_true(link.usable() && !mesh.stuck)
  assert_eq(far.heard, ["10000 3 {\"credential\":\"c2\"}"])
  // A link opened: not stuck. Let go of and asked for again, nothing is bound.
  mesh.drop_link(peer)
  stood.run()
  stood.rt.advance(rebind_ms)
  assert_true(stood.opened(mesh, source.gives()).usable())
  assert_eq((stood.times("iroh.bind 0"), mesh.endpoint_handle()), (2, 2))
  // And the mesh closed closes the one it has, once.
  assert_eq(ended_as(stood.go(() => mesh.close())), "ok")
  assert_eq((stood.times("iroh.close 1"), stood.times("iroh.close 2")), (1, 1))
}

///|
test "a dial that ran out of time with its connection made, or that failed otherwise, leaves the endpoint as it is: nothing is bound anew" {
  let (stood, far) = Stood::with_peer()
  let mesh = stood.mesh()
  let source = Source::new()
  // The connection is made and its first stream never opens: the opening runs out of time, connected.
  stood.holding = "conn.openBi"
  let asking = stood.go(() => mesh.link(peer, source.gives()))
  stood.rt.advance(connect_timeout_ms)
  assert_eq((ended_as(asking), mesh.stuck), ("mesh: " + say("no_answer"), false))
  // A dial refused outright.
  stood.holding = ""
  far.away = true
  let refused = stood.go(() => mesh.link(peer, source.gives()))
  stood.refuse("iroh.connect", "no route")
  assert_eq((ended_as(refused), mesh.stuck), ("mesh: " + say("unreached"), false))
  far.away = false
  assert_true(stood.opened(mesh, source.gives()).usable())
  assert_eq((stood.times("iroh.bind 0"), mesh.endpoint_handle()), (1, 1))
}

///|
test "an endpoint taken for stuck is not bound anew while a connection is open on it: a link asked for is dialled on it as it is; with none open and an opening still under way, a link asked for waits, dialling nothing, and binds it anew as that opening ends" {
  let (stood, far) = Stood::with_peer()
  let mesh = stood.mesh()
  let one = Source::new(of="a")
  let two = Source::new(of="b")
  let a = stood.opened(mesh, one.gives(), scope="one")
  far.away = true
  let asking = stood.go(() => mesh.link(peer, two.gives(), scope="two"))
  stood.rt.advance(connect_timeout_ms)
  assert_eq((ended_as(asking), mesh.stuck), ("mesh: " + say("no_answer"), true))
  // A link is open on it, which has no time to end by: the next dial is made on the endpoint as it is.
  let again = stood.go(() => mesh.link(peer, two.gives(), scope="two"))
  assert_eq((stood.times("iroh.bind 0"), stood.times("iroh.connect 1"), ended_as(again), mesh.settling()), (1, 3, "waiting", false))
  // That link let go of and its end told, an opening is still under way on it, which ends by itself: a link asked
  // for in a third scope is not dialled beside it.
  mesh.drop_link(peer, scope="one")
  stood.run()
  assert_true(!a.usable() && mesh.live.length() == 0 && mesh.settling())
  far.away = false
  let third = stood.go(() => mesh.link(peer, Source::new(of="c").gives(), scope="three"))
  assert_eq((stood.times("iroh.bind 0"), stood.times("iroh.connect 1"), ended_as(third), mesh.held.length()), (1, 3, "waiting", 1))
  // A millisecond short of that opening's time: still. As it runs out nothing is on the endpoint: the one that
  // waited binds it anew and is dialled on the new one.
  stood.rt.advance(connect_timeout_ms - 1)
  assert_eq((stood.times("iroh.bind 0"), ended_as(again), ended_as(third)), (1, "waiting", "waiting"))
  stood.rt.advance(1)
  assert_eq(ended_as(again), "mesh: " + say("no_answer"))
  assert_true(gave(third).usable() && !mesh.stuck && mesh.held.length() == 0)
  // (handles 2 and 3 were the first link's: the endpoint bound anew is 4)
  assert_eq((stood.times("iroh.bind 0"), stood.times("iroh.close 1"), mesh.endpoint_handle()), (2, 1, 4))
  assert_eq((stood.times("iroh.connect 1"), stood.times("iroh.connect 4")), (3, 1))
}

///|
test "nor is anything dialled beside a race under way on it whose old link has ended: a link asked for in another scope waits for the race's dial to end, and binds the endpoint anew then" {
  let (stood, far, mesh, old, _) = quick_link()
  far.away = true
  // A dial in a second scope runs out of time with no connection made, at 15 s: stuck, the first link open.
  let asking = stood.go(() => mesh.link(peer, Source::new(of="b").gives(), scope="two"))
  stood.rt.advance(connect_timeout_ms)
  assert_eq((ended_as(asking), mesh.stuck), ("mesh: " + say("no_answer"), true))
  // The first link's peer is gone from under it: the ping of 20 s is missed at 23 s, and it is raced, the new dial
  // unanswered. Then its connection ends: nothing of it is live, and the race's dial is still under way.
  far.lose(2)
  stood.rt.advance(tick_ms + ping_timeout_ms)
  assert_eq((mesh.racing.length(), stood.times("iroh.connect 1")), (1, 3))
  far.end(2, "bye")
  assert_true(!old.usable())
  assert_eq((mesh.live.length(), mesh.racing.length(), mesh.idle(), mesh.settling()), (0, 1, false, true))
  // A link asked for in a third scope binds nothing and dials nothing: it waits.
  far.away = false
  let third = stood.go(() => mesh.link(peer, Source::new(of="c").gives(), scope="three"))
  assert_eq((stood.times("iroh.bind 0"), stood.times("iroh.connect 1"), ended_as(third)), (1, 3, "waiting"))
  // The race's dial runs out of time, the race letting go of the link that ended. Nothing is on it now: the one
  // that waited binds it anew and is dialled on the new one.
  stood.rt.advance(connect_timeout_ms)
  assert_eq((mesh.racing.length(), stood.times("iroh.bind 0"), stood.times("iroh.close 1"), stood.times("iroh.connect 1")), (0, 2, 1, 3))
  assert_true(gave(third).usable())
}

///|
test "an endpoint taken for stuck is bound anew however many places are asked for again and again: no dial is begun on it once it is found so, and it is bound as the last under way ends (or as a link is next asked for, where none waits then), 10 s after at the most on a relay, 40 s off one" {
  // Two scopes, each asked for again as its dial fails, the second begun some seconds after the first, the peer
  // never answering: the first dial runs out at 10 s, the second's by 19 s.
  for pause in [0, 1_000, 3_000] {
    for stagger in [1_000, 3_000, 5_000, 9_000] {
      let (stood, far) = Stood::with_peer()
      let mesh = stood.mesh()
      far.away = true
      let trying = (scope : String) => stood.go(() => {
        while stood.rt.now() < 600_000L {
          ignore(attempt(() => mesh.link(peer, Source::new(of=scope).gives(), scope~)))
          if pause > 0 {
            @effect.sleep(pause)
          } else {
            @effect.pause()
          }
        }
      })
      ignore(trying("one"))
      stood.rt.advance(stagger)
      ignore(trying("two"))
      // A millisecond short of the second dial's end: found stuck at 10 s, nothing was dialled on it since. Bound
      // as that dial ends, by the first scope's asker where it waits by then, else as it next asks (its pause after
      // 10 s): two dials were ever made on the first endpoint.
      stood.rt.advance(connect_timeout_ms - 1)
      assert_eq((stood.times("iroh.bind 0"), stood.times("iroh.connect 1")), (1, 2))
      stood.rt.advance(1 + (if pause > stagger { pause - stagger } else { 0 }))
      assert_eq((stood.times("iroh.bind 0"), stood.times("iroh.connect 1"), stood.times("iroh.close 1")), (2, 2, 1))
      // And so on, for ten minutes: one bound each time the one before is found stuck.
      stood.rt.advance(600_000)
      assert_true(stood.times("iroh.bind 0") >= 40)
    }
  }
  // On no relay an opening has 30 s more: one begun at 35 s ends at 75 s, and the endpoint, found stuck at 40 s,
  // is bound then.
  let (stood, far) = Stood::with_peer()
  let mesh = stood.mesh()
  far.away = true
  stood.on_relay = false
  let first = stood.go(() => mesh.link(peer, Source::new(of="a").gives(), scope="one"))
  stood.rt.advance(35_000)
  let under = stood.go(() => mesh.link(peer, Source::new(of="b").gives(), scope="two"))
  stood.rt.advance(5_000)
  assert_eq((ended_as(first), mesh.stuck), ("mesh: " + say("no_answer"), true))
  let again = stood.go(() => mesh.link(peer, Source::new(of="a").gives(), scope="one"))
  stood.rt.advance(onto_max_ms + connect_timeout_ms - 5_000 - 1)
  assert_eq((stood.times("iroh.bind 0"), stood.times("iroh.connect 1"), ended_as(under), ended_as(again)), (1, 2, "waiting", "waiting"))
  stood.rt.advance(1)
  assert_eq((stood.times("iroh.bind 0"), stood.times("iroh.connect 1"), ended_as(under)), (2, 2, "mesh: " + say("no_answer")))
}

///|
/// A mesh whose endpoint is taken for stuck (a dial in scope "one" ran out of time at 10 s) with an opening still
/// under way on it (scope "two", begun at 5 s), which is given back: what a link asked for now waits for.
fn settling() -> (Stood, Peer, Mesh, @effect.Fiber[Link]) raise {
  let (stood, far) = Stood::with_peer()
  let mesh = stood.mesh()
  far.away = true
  let first = stood.go(() => mesh.link(peer, Source::new(of="a").gives(), scope="one"))
  stood.rt.advance(5_000)
  let under = stood.go(() => mesh.link(peer, Source::new(of="b").gives(), scope="two"))
  stood.rt.advance(5_000)
  guard ended_as(first) == "mesh: " + say("no_answer") && mesh.stuck && mesh.settling() else {
    fail("the endpoint is not taken for stuck with an opening under way")
  }
  (stood, far, mesh, under)
}

///|
test "whoever waits to dial on an endpoint taken for stuck is told: closed as its place is let go of or the mesh closes, nothing kept of one that gives up; and where the opening under way opens after all, nothing is bound and each is dialled on the endpoint as it is" {
  let (stood, _, mesh, under) = settling()
  let a = stood.go(() => mesh.link(peer, Source::new(of="a").gives(), scope="one"))
  let b = stood.go(() => mesh.link(peer, Source::new(of="c").gives(), scope="three"))
  assert_eq((mesh.held.length(), stood.times("iroh.connect 1"), ended_as(a), ended_as(b)), (2, 2, "waiting", "waiting"))
  // Its place let go of: as one whose opening is given up. The other's stays.
  mesh.drop_link(peer, scope="one")
  stood.run()
  assert_eq((ended_as(a), ended_as(b), mesh.held.length()), ("mesh: " + say("closed"), "waiting", 1))
  // Given up: no more waited for.
  b.interrupt()
  stood.run()
  assert_eq((ended_as(b), mesh.held.length()), ("interrupted", 0))
  // The mesh closed: told so in that step.
  let c = stood.go(() => mesh.link(peer, Source::new(of="c").gives(), scope="three"))
  let closing = stood.start(() => mesh.close())
  stood.run()
  assert_eq((ended_as(c), ended_as(under), ended_as(closing), mesh.held.length()), ("mesh: " + say("closed"), "mesh: " + say("closed"), "ok", 0))
  assert_eq((stood.times("iroh.bind 0"), stood.times("iroh.connect 1")), (1, 2))
  // The opening under way opens after all: the endpoint is stuck no more, and those that waited are dialled on it.
  let (stood, far, mesh, under) = settling()
  let a = stood.go(() => mesh.link(peer, Source::new(of="a").gives(), scope="one"))
  let b = stood.go(() => mesh.link(peer, Source::new(of="c").gives(), scope="three"))
  far.away = false
  stood.dialled()
  assert_true(gave(under).usable() && gave(a).usable() && gave(b).usable() && !mesh.stuck)
  assert_eq((stood.times("iroh.bind 0"), stood.times("iroh.connect 1"), mesh.held.length()), (1, 4, 0))
  // The opening under way let go of by its program: nothing is on the endpoint, and the one that waited binds it.
  let (stood, far, mesh, under) = settling()
  let a = stood.go(() => mesh.link(peer, Source::new(of="a").gives(), scope="one"))
  far.away = false
  mesh.drop_link(peer, scope="two")
  stood.run()
  assert_eq((ended_as(under), stood.times("iroh.bind 0"), stood.times("iroh.close 1")), ("mesh: " + say("closed"), 2, 1))
  assert_true(gave(a).usable())
}

///|
test "a link ended whose answer is not said yet is still on the endpoint: whoever waits to dial is told as it is said, and binds the endpoint anew then" {
  // By hand: a link open, its hello not answered; then a dial in another scope runs out of time, unanswered.
  let stood = Stood::new()
  let mesh = stood.mesh()
  let source = Source::new().gives()
  let opening = stood.go(() => mesh.link(peer, source, scope="one"))
  stood.dialled()
  let link = gave(opening)
  let failing = stood.go(() => mesh.link(peer, source, scope="two"))
  stood.rt.advance(connect_timeout_ms)
  assert_eq((ended_as(failing), mesh.stuck, mesh.settling()), ("mesh: " + say("no_answer"), true, false))
  // The link's connection ends: told, and its answer's read still out. Nothing on the endpoint is open now.
  stood.give("conn.closed", { "kind": "application", "reason": "bye" })
  assert_true(!link.usable())
  assert_eq((mesh.live.length(), mesh.settling()), (1, true))
  let asking = stood.go(() => mesh.link(peer, source, scope="two"))
  assert_eq((stood.times("iroh.bind 0"), mesh.held.length(), ended_as(asking)), (1, 1, "waiting"))
  // The read fails with its connection: the link's answer is said, nothing is on the endpoint, and it is bound.
  stood.refuse("istream.read", "connection closed")
  assert_eq((mesh.live.length(), stood.times("iroh.bind 0"), stood.times("iroh.close 1"), mesh.held.length()), (0, 2, 1, 0))
  assert_eq((ended_as(asking), stood.times("iroh.connect \{mesh.endpoint_handle()}")), ("waiting", 1))
}

///|
test "an endpoint that could not be bound anew stays the one it was, and is not tried again for 5 s; a link opened on it meanwhile, it is stuck no more" {
  let (stood, far, mesh, source) = stuck()
  // The bind fails: the dial is made on the endpoint as it was (and refused at once, here).
  stood.holding = "iroh.bind"
  let first = stood.go(() => mesh.link(peer, source.gives()))
  assert_eq((stood.times("iroh.bind 0"), far.dials.length()), (2, 1))
  stood.refuse("iroh.bind", "no socket")
  assert_eq((far.dials.length(), stood.times("iroh.connect 1"), mesh.endpoint_handle()), (2, 2, 1))
  // (no bind is to be tried for 5 s: a link asked for in another scope meanwhile is not kept waiting for one, and
  // is dialled beside the dial under way)
  let beside = stood.go(() => mesh.link(peer, Source::new(of="b").gives(), scope="two"))
  assert_eq((stood.times("iroh.connect 1"), mesh.held.length(), mesh.settling()), (3, 0, true))
  stood.refuse("iroh.connect", "no route")
  stood.refuse("iroh.connect", "no route")
  assert_eq(ended_as(beside), "mesh: " + say("unreached"))
  assert_eq((ended_as(first), mesh.stuck, stood.times("iroh.close 1")), ("mesh: " + say("unreached"), true, 0))
  // Asked for again a millisecond short of 5 s after: no bind, a dial on the same endpoint.
  stood.rt.advance(rebind_ms - 1)
  let second = stood.go(() => mesh.link(peer, source.gives()))
  assert_eq((stood.times("iroh.bind 0"), stood.times("iroh.connect 1")), (2, 4))
  stood.refuse("iroh.connect", "no route")
  assert_eq(ended_as(second), "mesh: " + say("unreached"))
  // At 5 s: bound anew.
  stood.rt.advance(1)
  let third = stood.go(() => mesh.link(peer, source.gives()))
  assert_eq(stood.times("iroh.bind 0"), 3)
  stood.bound()
  assert_eq((mesh.endpoint_handle(), stood.times("iroh.close 1"), stood.times("iroh.connect 2")), (2, 1, 1))
  far.away = false
  stood.dialled()
  assert_true(gave(third).usable() && !mesh.stuck)
}

///|
test "an endpoint taken for stuck is so no more once a link opens on it, or once it was bound anew: neither is bound again for a dial that then fails otherwise" {
  assert_eq(rebind_ms, 5_000)
  // A link opens on the endpoint as it was (its bind anew having failed): not stuck.
  let (stood, far, mesh, source) = stuck()
  stood.holding = "iroh.bind"
  let first = stood.go(() => mesh.link(peer, source.gives()))
  far.away = false
  stood.refuse("iroh.bind", "no socket")
  assert_true(gave(first).usable() && !mesh.stuck)
  assert_eq(mesh.endpoint_handle(), 1)
  // Bound anew, and the dial on the new one refused: not stuck, and 5 s later nothing is bound for the next.
  let (stood, _, mesh, source) = stuck()
  let second = stood.go(() => mesh.link(peer, source.gives()))
  assert_eq((mesh.endpoint_handle(), mesh.stuck), (2, false))
  stood.refuse("iroh.connect", "no route")
  assert_eq(ended_as(second), "mesh: " + say("unreached"))
  stood.rt.advance(rebind_ms)
  let third = stood.go(() => mesh.link(peer, source.gives()))
  assert_eq((stood.times("iroh.bind 0"), stood.times("iroh.connect 2"), ended_as(third)), (2, 2, "waiting"))
}

///|
test "a link asked for while the endpoint is being bound anew waits for that, binds nothing itself and dials on the new one; the asker that began it gone, the others go on" {
  let (stood, far, mesh, source) = stuck()
  far.away = false
  stood.holding = "iroh.bind"
  let first = stood.go(() => mesh.link(peer, source.gives()))
  let second = stood.go(() => mesh.link(peer, Source::new(of="b").gives(), scope="two"))
  let third = stood.go(() => mesh.link(peer, source.gives()))
  // One bind asked, no dial yet; a wake meanwhile tells the shell nothing of an endpoint on its way out.
  assert_eq((stood.times("iroh.bind 0"), far.dials.length()), (2, 1))
  mesh.wake()
  stood.run()
  assert_eq(stood.times("iroh.networkChange 1"), 0)
  // The asker that began it gives up: the bind goes on at the shell, and is the mesh's to take.
  first.interrupt()
  stood.run()
  assert_eq((ended_as(first), ended_as(second), ended_as(third)), ("interrupted", "waiting", "waiting"))
  stood.holding = ""
  stood.bound()
  // Bound: the one before closed once, and each place dialled once, on the new one.
  assert_eq((mesh.endpoint_handle(), stood.times("iroh.bind 0"), stood.times("iroh.close 1")), (2, 2, 1))
  assert_eq((stood.times("iroh.connect 1"), stood.times("iroh.connect 2"), far.dials.length()), (1, 2, 3))
  assert_true(gave(second).usable() && gave(third).usable())
  assert_true(mesh.current(peer) is Some(now) && physical_equal(now, gave(third)))
}

///|
test "three askers of one place while the endpoint is being bound anew: each looks at the place again as it is bound, so one dial is made, and all three are given its link" {
  let (stood, far, mesh, source) = stuck()
  far.away = false
  stood.holding = "iroh.bind"
  let askers = [0, 1].map(_ => stood.go(() => mesh.link(peer, source.gives())))
  // (the shell slow to bind, 5 s and more: one asked for then begins no second bind beside the one under way)
  stood.rt.advance(rebind_ms)
  askers.push(stood.go(() => mesh.link(peer, source.gives())))
  assert_eq((stood.times("iroh.bind 0"), mesh.held.length(), far.dials.length()), (2, 3, 1))
  stood.holding = ""
  stood.bound()
  assert_eq((stood.times("iroh.bind 0"), stood.times("iroh.connect 2"), far.dials.length(), mesh.held.length()), (2, 1, 2, 0))
  let link = gave(askers[0])
  assert_true(link.usable() && physical_equal(gave(askers[1]), link) && physical_equal(gave(askers[2]), link))
  // (asked once more for the one dial)
  assert_eq(source.asked.length(), 2)
}

///|
test "whoever waited for the endpoint bound anew goes on as it is the mesh's: the shell's answer to the close of the one before is waited for by nobody but the mesh's close" {
  let (stood, far, mesh, source) = stuck()
  far.away = false
  stood.holding = "iroh.close"
  let asking = stood.go(() => mesh.link(peer, source.gives()))
  // Bound (handle 2), the close of the first asked and not answered: the link is dialled on the new one, and open.
  assert_true(gave(asking).usable())
  assert_eq((mesh.endpoint_handle(), stood.times("iroh.close 1"), stood.times("iroh.connect 2"), stood.held.length()), (2, 1, 1, 1))
  stood.rt.advance(3_600_000)
  assert_eq((stood.held.length(), mesh.rebinding), (1, false))
  // The mesh closed meanwhile waits for that answer (the fiber that asked is its own), then closes the one it has.
  let closing = stood.go(() => mesh.close())
  assert_eq((ended_as(closing), stood.times("iroh.close 2")), ("waiting", 0))
  stood.give("iroh.close", {})
  assert_eq((ended_as(closing), stood.times("iroh.close 2")), ("waiting", 1))
  stood.give("iroh.close", {})
  assert_eq(ended_as(closing), "ok")
  assert_eq((stood.times("iroh.close 1"), stood.times("iroh.close 2")), (1, 1))
}

///|
test "the mesh closed while its endpoint is being bound anew: whoever waits is told closed in that step, with nothing of the shell; the close alone waits for the shell's answer, and the endpoint that comes is closed and the one before too, each once" {
  let (stood, _, mesh, source) = stuck()
  stood.holding = "iroh.bind"
  let asking = stood.go(() => mesh.link(peer, source.gives()))
  let other = stood.go(() => mesh.link(peer, Source::new(of="b").gives(), scope="two"))
  let health = stood.go(() => mesh.health_change(peer, false))
  assert_eq((ended_as(asking), ended_as(other), ended_as(health), mesh.held.length()), ("waiting", "waiting", "waiting", 2))
  let closing = stood.go(() => mesh.close())
  let closed = "mesh: " + say("closed")
  assert_eq((ended_as(asking), ended_as(other), ended_as(health), ended_as(closing)), (closed, closed, closed, "waiting"))
  // An hour on, the shell has not answered: the close waits still, and nothing else does.
  stood.rt.advance(3_600_000)
  assert_eq((ended_as(closing), stood.times("iroh.close 1"), mesh.held.length()), ("waiting", 0, 0))
  stood.holding = ""
  stood.bound()
  assert_eq(ended_as(closing), "ok")
  assert_eq((stood.times("iroh.close 1"), stood.times("iroh.close 2"), stood.times("iroh.connect 2")), (1, 1, 0))
  // (the new one first, by the fiber that bound it; then the mesh's own, the last thing asked)
  assert_eq(stood.said[stood.said.length() - 2:].to_owned(), ["iroh.close 2", "iroh.close 1"])
}

///|
test "the mesh closed in the turn a link begins to bind the endpoint anew, before that took a step: nothing is asked of the shell for it, and the asker is told closed" {
  let (stood, _, mesh, source) = stuck()
  let asking = stood.start(() => mesh.link(peer, source.gives()))
  let closing = stood.start(() => mesh.close())
  stood.run()
  assert_eq((ended_as(asking), ended_as(closing)), ("mesh: " + say("closed"), "ok"))
  assert_eq((stood.times("iroh.bind 0"), stood.times("iroh.close 1")), (1, 1))
}
