// A link's pings measured, how its place is told to be, and a link suspect raced against a new one (health.mbt), on
// the peer that answers by itself (stood_wbtest.mbt). At the TypeScript mesh's numbers (client/core-ts/src/mesh.ts):
// a ping's round trip smoothed an eighth and a quarter, the first not counted, one not answered in time counted as
// 3 s; a link suspect when it misses a ping after one answered in under 1.5 s; its probe 5 s; a link another took
// the place of closed 10 s later.

///|
/// A link's pings so far, in a line to compare.
fn Link::measured(self : Link) -> (Int, Double, Double, Int, Int?) {
  let pings = self.pings()
  (pings.samples, pings.srtt, pings.dev, pings.missed, pings.answered_ms)
}

///|
/// A link whose first ping was answered at once, so that one it misses next makes it suspect: its shell, peer and
/// mesh, the link (connection 2, its control stream 3) and its credential's source. The clock is at 5 s: the next
/// ping goes at 10 s, and is missed at 13 s.
fn quick_link() -> (Stood, Peer, Mesh, Link, Source) raise {
  let (stood, far) = Stood::with_peer()
  let mesh = stood.mesh()
  let source = Source::new()
  let link = stood.opened(mesh, source.gives())
  stood.rt.advance(tick_ms)
  assert_eq(link.measured(), (0, 0.0, 0.0, 0, Some(0)))
  (stood, far, mesh, link, source)
}

///|
/// The handle of a link's connection at the stood-in shell.
fn Link::conn_handle(self : Link) -> Int {
  handle_of({ "id": self.conn })
}

///|
/// The control lines the peer heard on connection `conn`.
fn Peer::heard_on(self : Peer, conn : Int) -> Array[String] {
  self.heard.filter(line => line.contains(" \{conn} {"))
}

// ── its pings measured ──

///|
test "a link's pings are measured: the first answered is not counted, each after is smoothed an eighth into the mean and a quarter into the deviation, one not answered in time counts as 3 s and again as what it took once it is answered" {
  let (stood, far) = Stood::with_peer()
  let mesh = stood.mesh()
  let link = stood.opened(mesh, Source::new().gives())
  assert_eq(link.measured(), (0, 0.0, 0.0, 0, None))
  // The first, 100 ms: it carried the link's own start, and is how long the last answered took, no sample.
  far.takes = 100
  stood.rt.advance(tick_ms + 100)
  assert_eq(link.measured(), (0, 0.0, 0.0, 0, Some(100)))
  // 200 ms: the first sample is the mean, its deviation from nothing.
  far.takes = 200
  stood.rt.advance(tick_ms + 200)
  assert_eq(link.measured(), (1, 200.0, 0.0, 0, Some(200)))
  // 400 ms: dev = 3/4·0 + 1/4·|400 − 200| = 50; srtt = 7/8·200 + 1/8·400 = 225.
  far.takes = 400
  stood.rt.advance(tick_ms + 400)
  assert_eq(link.measured(), (2, 225.0, 50.0, 0, Some(400)))
  // 1600 ms: dev = 37.5 + 1/4·1375 = 381.25; srtt = 196.875 + 200 = 396.875.
  far.takes = 1600
  stood.rt.advance(tick_ms + 1600)
  assert_eq(link.measured(), (3, 396.875, 381.25, 0, Some(1600)))
  // 4 s: not answered at 3 s, it is missed and counts as 3000:
  // dev = 285.9375 + 1/4·2603.125 = 936.71875; srtt = 347.265625 + 375 = 722.265625.
  far.takes = 4_000
  stood.rt.advance(tick_ms + ping_timeout_ms)
  assert_eq(link.measured(), (4, 722.265625, 936.71875, 1, Some(1600)))
  // (its last answer took 1.6 s, not under half a ping's time: missing one makes it no suspect)
  assert_eq((mesh.racing.length(), far.dials), (0, [0L]))
  // Answered a second later, it is not missing, only slow, and counts again as the 4000 it took:
  // dev = 702.5390625 + 1/4·3277.734375 = 1521.97265625; srtt = 631.982421875 + 500 = 1131.982421875.
  stood.rt.advance(1_000)
  assert_eq(link.measured(), (5, 1131.982421875, 1521.97265625, 0, Some(4000)))
  // 9 s: 3000 as its time runs out, 3000 more a tick later while it is still out (no other is sent), then its 9000.
  far.takes = 9_000
  stood.rt.advance(tick_ms - 1_000 + ping_timeout_ms)
  assert_eq((link.pings().samples, link.pings().missed), (6, 1))
  stood.rt.advance(tick_ms)
  assert_eq((link.pings().samples, link.pings().missed), (7, 2))
  stood.rt.advance(1_000)
  assert_eq((link.pings().samples, link.pings().missed, link.pings().answered_ms), (8, 0, Some(9000)))
  assert_eq(far.dials, [0L])
}

// ── how a place is ──

///|
test "how a place is, told once each time it changes: answering as a link opens there, not as its third ping in a row is missed, answering as another opens, not as it is let go of; and by nothing else" {
  let (stood, far) = Stood::with_peer()
  let mesh = stood.mesh()
  let source = Source::new()
  // A watcher as what reads a stream on a link is: it says what it last knew, and is told what it is now.
  let told : Array[Bool] = []
  let watcher = stood.go(() => {
    let mut up = false
    while true {
      up = mesh.health_change(peer, up)
      told.push(up)
    }
  })
  // No link there: no way stands, none answers, and nothing is told.
  assert_eq((mesh.standing(peer), mesh.healthy(peer), told), (false, false, []))
  let link = stood.opened(mesh, source.gives())
  assert_eq((mesh.standing(peer), mesh.healthy(peer), told), (true, true, [true]))
  // Its pings answered, a renewal: nothing to tell.
  stood.rt.advance(renew_ms + tick_ms)
  assert_eq(told, [true])
  // The peer answers pings slowly from here (so that one missed makes the link no suspect), then not at all, nor a
  // dial. A ping missed: a way is still there, though it does not stand; a second: the same.
  far.takes = 2_000
  stood.rt.advance(tick_ms + 2_000)
  assert_eq(link.pings().answered_ms, Some(2000))
  far.quiet = true
  far.away = true
  stood.rt.advance(tick_ms + ping_timeout_ms)
  assert_eq((link.missed, mesh.standing(peer), mesh.healthy(peer), told), (1, false, true, [true]))
  stood.rt.advance(tick_ms)
  assert_eq((link.missed, mesh.standing(peer), mesh.healthy(peer), told), (2, false, true, [true]))
  // The third: told, once, as the link is let go; the dial for it that is not answered tells nothing more.
  stood.rt.advance(tick_ms)
  assert_eq((link.missed, mesh.standing(peer), mesh.healthy(peer), told), (3, false, false, [true, false]))
  stood.rt.advance(2 * connect_timeout_ms)
  assert_eq(told, [true, false])
  // A link opens there again: told.
  far.quiet = false
  far.away = false
  far.takes = 0
  let second = stood.opened(mesh, source.gives())
  assert_eq((mesh.standing(peer), told), (true, [true, false, true]))
  // The peer ends its connection: no way stands, but that is the link's end to tell (`Link::closed`), not this;
  // nor is another opened over it news, the place answering as it was last said to.
  let closed = stood.go(() => second.closed())
  far.end(second.conn_handle(), "bye")
  assert_eq(ended_as(closed), "ok")
  assert_eq((mesh.standing(peer), mesh.healthy(peer), told), (false, false, [true, false, true]))
  let third = stood.opened(mesh, source.gives())
  assert_true(!physical_equal(third, second))
  assert_eq(told, [true, false, true])
  // Let go of by its program: told. A link in another scope coming and going tells this place's watcher nothing.
  mesh.drop_link(peer)
  stood.run()
  assert_eq(told, [true, false, true, false])
  ignore(stood.opened(mesh, Source::new(of="b").gives(), scope="other"))
  mesh.drop_link(peer, scope="other")
  stood.run()
  assert_eq(told, [true, false, true, false])
  assert_eq(ended_as(watcher), "waiting")
  // The mesh closed: whoever waits is told so.
  assert_eq(ended_as(stood.go(() => mesh.close())), "ok")
  assert_eq(ended_as(watcher), "mesh: " + say("closed"))
  assert_eq(told.length(), 4)
}

///|
test "everyone who waits on a place is told as it changes, one that says what it is not is told at once, and one that gave up waiting is waited for no more" {
  let (stood, far) = Stood::with_peer()
  let mesh = stood.mesh()
  ignore(stood.opened(mesh, Source::new().gives()))
  let one = stood.go(() => mesh.health_change(peer, true))
  let other = stood.go(() => mesh.health_change(peer, true))
  let gone = stood.go(() => mesh.health_change(peer, true))
  // (at once: it is not what this one says it was; and of a place nothing was told of, what it is)
  assert_true(stood.go(() => mesh.health_change(peer, false)).poll() is Some(Succeeded(true)))
  assert_true(stood.go(() => mesh.health_change(peer, true, scope="none")).poll() is Some(Succeeded(false)))
  assert_eq((ended_as(one), ended_as(other), mesh.health_waits.length()), ("waiting", "waiting", 3))
  gone.interrupt()
  stood.run()
  assert_eq((ended_as(gone), mesh.health_waits.length()), ("interrupted", 2))
  mesh.drop_link(peer)
  stood.run()
  assert_true(one.poll() is Some(Succeeded(false)) && other.poll() is Some(Succeeded(false)))
  assert_eq(mesh.health_waits.length(), 0)
  // And one is told a change only: at a place nothing was told of yet, an opening let go of leaves it as it was,
  // no way answering, and whoever waits for one to answer waits on.
  far.away = true
  let waiting = stood.go(() => mesh.health_change(peer, false, scope="new"))
  let opening = stood.go(() => mesh.link(peer, Source::new().gives(), scope="new"))
  mesh.drop_link(peer, scope="new")
  stood.run()
  assert_eq((ended_as(opening), ended_as(waiting)), ("mesh: " + say("closed"), "waiting"))
}

// ── a link suspect, raced ──

///|
test "a peer gone from under a link whose pings it answered quickly: at the first ping missed a new link is dialled beside it and takes its place as it opens; the holder is told once and given it with no dial, and the old one stays open 10 s for what is under way on it" {
  let (stood, far, mesh, old, source) = quick_link()
  let told = Ref(0)
  let held : Ref[Link] = Ref(old)
  let holder = stood.go(() => {
    while true {
      mesh.replaced(held.val)
      told.val += 1
      held.val = mesh.link(peer, source.gives())
    }
  })
  let health = stood.go(() => mesh.health_change(peer, true))
  // The peer's process is gone from under connection 2, and another answers dials in its place. A request is under
  // way on the link, never to be answered (its stream is handle 4).
  far.lose(2)
  let asked = stood.go(() => old.request("GET", "/long"))
  assert_eq(ended_as(asked), "waiting")
  // The ping of 10 s is missed at 13 s, and not a millisecond before is anything done.
  stood.rt.advance(tick_ms + ping_timeout_ms - 1)
  assert_eq((old.missed, told.val, far.dials, mesh.racing.length()), (0, 0, [0L], 0))
  stood.rt.advance(1)
  assert_eq(old.missed, 1)
  // Dialled at once, with the old link's credentials' source (asked as for one it has), connection 5: open, it is
  // the place's link in that turn. 3 s after the ping went unanswered, not 13.
  assert_eq(far.dials, [0L, 13000L])
  assert_eq(first_saying(far.heard, "c2"), "13000 5 {\"credential\":\"c2\"}")
  guard mesh.current(peer) is Some(next) else { fail("no link at the place after the race") }
  assert_true(!physical_equal(next, old) && next.usable())
  assert_eq(mesh.racing.length(), 0)
  // The holder was told once, and its asking for the link dialled nothing and asked no credential.
  assert_eq(told.val, 1)
  assert_true(physical_equal(held.val, next))
  assert_eq(source.asked, ["kept", "kept"])
  // The place answered throughout: nothing to tell of its health.
  assert_eq((mesh.standing(peer), mesh.healthy(peer), ended_as(health)), (true, true, "waiting"))
  // The old link is not closed yet, and what is under way on it still waits;
  assert_true(old.usable())
  assert_eq((far.closes.length(), ended_as(asked)), (0, "waiting"))
  stood.rt.advance(retire_ms - 1)
  assert_eq((far.closes.length(), ended_as(asked)), (0, "waiting"))
  // 10 s after it was replaced it is closed, in the base's own word, and the request on it fails as cut.
  stood.rt.advance(1)
  assert_eq(far.closes, ["2 closed"])
  assert_true(!old.usable())
  assert_eq(ended_as(asked), "mesh: " + say("cut"))
  // The new one was pinged in its turn; on the old one nothing was written after the ping it missed: its probe
  // waited its turn on the line behind that ping, and was never sent.
  assert_eq(far.heard_on(5), [
    "13000 5 {\"credential\":\"c2\"}", "18000 5 {\"credential\":\"c2\"}", "23000 5 {\"credential\":\"c2\"}",
  ])
  assert_eq(far.heard_on(2), [
    "0 2 {\"credential\":\"c1\"}", "5000 2 {\"credential\":\"c1\"}", "10000 2 {\"credential\":\"c1\"}",
  ])
  stood.rt.advance(10 * tick_ms)
  assert_eq((told.val, far.dials.length(), mesh.live.length()), (1, 2, 1))
  assert_eq(ended_as(stood.go(() => mesh.close())), "ok")
  assert_eq(ended_as(holder), "mesh: " + say("closed"))
}

///|
test "a link suspect that answers its probe before a new one opens: it is kept, the holder told nothing, and the new one's dial is given up; one the shell could not stop is closed to be forgotten as its connection comes" {
  for cancels in [true, false] {
    let (stood, far, mesh, old, _) = quick_link()
    let replaced = stood.go(() => mesh.replaced(old))
    // The peer answers 3.5 s late from here, and no dial.
    far.away = true
    stood.cancels = cancels
    far.takes = 3_500
    stood.rt.advance(tick_ms + ping_timeout_ms)
    assert_eq((old.missed, far.dials, mesh.racing.length(), stood.held.length()), (1, [0L, 13000L], 1, 1))
    // The ping of 10 s is answered at 13.5 s: not missing after all. The probe goes then, in its turn on the line.
    stood.rt.advance(500)
    assert_eq(old.missed, 0)
    assert_eq(far.heard_on(2)[3], "13500 2 {\"credential\":\"c1\"}")
    stood.rt.advance(3_499)
    assert_eq(mesh.racing.length(), 1)
    // Answered at 17 s, a second before its time runs out: the old link stays the one there.
    stood.rt.advance(1)
    assert_eq(mesh.racing.length(), 0)
    assert_true(mesh.current(peer) is Some(now) && physical_equal(now, old))
    assert_true(old.usable())
    assert_eq((ended_as(replaced), far.closes.length()), ("waiting", 0))
    if cancels {
      // The dial was given up at the shell.
      assert_eq(stood.held.length(), 0)
    } else {
      // The shell went on with it: its connection, come later (handle 4), is closed to be forgotten, no stream
      // opened on it, and no link comes of it.
      assert_eq(stood.held.length(), 1)
      stood.dialled()
      assert_eq((stood.times("conn.close 4"), stood.times("conn.openBi 4")), (1, 0))
      assert_true(stood.forgot.contains(4))
      assert_eq(far.closes, ["4 opening ended"])
    }
    // It goes on being pinged, the one there, and nothing else is dialled.
    far.takes = 0
    far.away = false
    stood.rt.advance(10 * tick_ms)
    assert_true(mesh.current(peer) is Some(now) && physical_equal(now, old))
    assert_eq((old.missed, far.dials.length(), mesh.live.length(), ended_as(replaced)), (0, 2, 1, "waiting"))
  }
}

///|
test "a link suspect whose peer answers neither it nor a new dial: let go as the dial gives up, the holder and the place's watcher told once, and nothing dialled until the link is asked for" {
  let (stood, far, mesh, old, source) = quick_link()
  let replaced = stood.go(() => mesh.replaced(old))
  let health = stood.go(() => mesh.health_change(peer, true))
  far.lose(2)
  far.away = true
  stood.rt.advance(tick_ms + ping_timeout_ms)
  assert_eq((old.missed, far.dials, mesh.racing.length()), (1, [0L, 13000L], 1))
  // The probe's time runs out at 18 s: the dial is still waited for, and the link still the one there.
  stood.rt.advance(probe_ms)
  assert_eq((mesh.racing.length(), ended_as(replaced), far.closes.length()), (1, "waiting", 0))
  assert_true(mesh.current(peer) is Some(now) && physical_equal(now, old))
  stood.rt.advance(connect_timeout_ms - probe_ms - 1)
  assert_eq((mesh.racing.length(), ended_as(replaced)), (1, "waiting"))
  // The dial gives up at 23 s: neither answered. The old link is closed, in the base's own word, and is no more
  // the one there.
  stood.rt.advance(1)
  assert_eq(far.closes, ["2 closed"])
  assert_true(mesh.current(peer) is None)
  assert_eq(ended_as(replaced), "ok")
  assert_true(health.poll() is Some(Succeeded(false)))
  assert_eq((mesh.standing(peer), mesh.healthy(peer)), (false, false))
  assert_eq((mesh.racing.length(), mesh.links.length(), stood.held.length()), (0, 0, 0))
  // Nothing dials by itself after: a dial was just tried. Whoever asks next does.
  stood.rt.advance(2 * renew_ms)
  assert_eq((far.dials, mesh.live.length()), ([0L, 13000L], 0))
  far.away = false
  let again = stood.opened(mesh, source.gives())
  assert_true(again.usable() && !physical_equal(again, old))
  assert_eq(far.dials.length(), 3)
}

///|
test "a race whose new link's dial fails at once: the old link has what is left of its probe's time, kept if it answers in it, let go as it runs out, its place then told to answer no more" {
  for answers in [true, false] {
    let (stood, far, mesh, old, _) = quick_link()
    let health = stood.go(() => mesh.health_change(peer, true))
    far.away = true
    if answers {
      // (its ping of 10 s answered at 13.5 s, its probe, sent then, at 17 s)
      far.takes = 3_500
    } else {
      far.lose(2)
    }
    stood.rt.advance(tick_ms + ping_timeout_ms)
    assert_eq(mesh.racing.length(), 1)
    stood.refuse("iroh.connect", "no route")
    assert_eq((mesh.racing.length(), far.closes.length()), (1, 0))
    stood.rt.advance(probe_ms - 1_001)
    assert_eq(mesh.racing.length(), 1)
    stood.rt.advance(1)
    if answers {
      assert_eq((mesh.racing.length(), far.closes.length(), ended_as(health)), (0, 0, "waiting"))
      assert_true(mesh.current(peer) is Some(now) && physical_equal(now, old))
      continue
    }
    stood.rt.advance(999)
    assert_eq((mesh.racing.length(), far.closes.length()), (1, 0))
    // 18 s: neither. Two pings missed, not three, and the place is told all the same: it has no link.
    stood.rt.advance(1)
    assert_eq((mesh.racing.length(), far.closes), (0, ["2 closed"]))
    assert_true(mesh.current(peer) is None)
    assert_true(health.poll() is Some(Succeeded(false)))
    stood.rt.advance(2 * renew_ms)
    assert_eq(far.dials, [0L, 13000L])
  }
}

///|
test "a link raced whose third ping in a row is missed meanwhile is the race's to decide: it is not let go nor dialled for beside the race, and is let go as the race finds neither answers" {
  let (stood, far, mesh, old, _) = quick_link()
  far.lose(2)
  far.away = true
  // The endpoint is on no relay as the race dials, and is found on one a second later (looked at every 250 ms):
  // the dial's time is counted from then, so it gives up at 24 s, a second after the third ping is missed.
  stood.rt.advance(tick_ms)
  stood.on_relay = false
  stood.rt.advance(ping_timeout_ms)
  assert_eq((old.missed, mesh.racing.length()), (1, 1))
  stood.rt.advance(750)
  stood.on_relay = true
  stood.rt.advance(tick_ms - 750)
  assert_eq(old.missed, 2)
  stood.rt.advance(tick_ms)
  // 23 s: three missed. No way there answers its pings, and the link is still the one there, open, the one dial of
  // the race the only one.
  assert_eq((old.missed, mesh.healthy(peer), mesh.racing.length()), (3, false, 1))
  assert_true(mesh.current(peer) is Some(now) && physical_equal(now, old))
  assert_eq((far.closes.length(), far.dials), (0, [0L, 13000L]))
  stood.rt.advance(999)
  assert_eq(far.closes.length(), 0)
  stood.rt.advance(1)
  assert_eq(far.closes, ["2 closed"])
  assert_true(mesh.current(peer) is None)
  stood.rt.advance(2 * renew_ms)
  assert_eq((far.dials, mesh.links.length(), mesh.live.length()), ([0L, 13000L], 0, 0))
}

///|
test "a link suspect on which something came while it was raced is there after all: it is kept and the new one closed, though that one opened first; one that ended meanwhile is not" {
  for ends in [false, true] {
    let (stood, far, mesh, old, _) = quick_link()
    let replaced = stood.go(() => mesh.replaced(old))
    far.quiet = true
    far.away = true
    stood.rx[2] = 1000.0
    stood.rt.advance(tick_ms + ping_timeout_ms)
    assert_eq((old.missed, mesh.racing.length()), (1, 1))
    // A second into the race the transport says more came on the old connection (its own packets: the network had
    // only paused), no answer to a ping yet; then the new link's dial is answered (connection 4).
    stood.rt.advance(1_000)
    stood.rx[2] = 1200.0
    if ends {
      far.end(2, "bye")
    }
    far.away = false
    stood.dialled()
    assert_eq(mesh.racing.length(), 0)
    if ends {
      // What came was its end: the new one takes the place.
      guard mesh.current(peer) is Some(next) else { fail("no link at the place after the race") }
      assert_true(!physical_equal(next, old) && next.usable())
      assert_eq(ended_as(replaced), "ok")
    } else {
      // Kept: the new link is closed as it opens, its hello sent, and the holder is told nothing.
      assert_true(mesh.current(peer) is Some(now) && physical_equal(now, old))
      assert_eq(far.closes, ["4 closed"])
      assert_eq((ended_as(replaced), old.usable()), ("waiting", true))
      // Its pings are counted on as they were: still unanswered, it is let go at the third and dialled anew.
      stood.rt.advance(2 * tick_ms - 1_000)
      assert_eq((old.missed, far.closes, far.dials), (3, ["4 closed", "2 closed"], [0L, 13000L, 23000L]))
      assert_eq(ended_as(replaced), "ok")
    }
  }
}

///|
test "a probe whose time ran out while it waited its turn on the line is never sent: the old link's ping answered after, nothing more is written on it but its pings" {
  let (stood, far, mesh, old, _) = quick_link()
  // The peer answers the ping of 10 s at 19 s, a second after the probe's time, and no dial.
  far.away = true
  far.takes = 9_000
  stood.rt.advance(tick_ms)
  far.takes = 0
  stood.rt.advance(ping_timeout_ms + probe_ms)
  assert_eq((old.missed, mesh.racing.length(), far.heard_on(2).length()), (2, 1, 3))
  // (as a transport says of an answer that came)
  stood.rx[2] = 300.0
  stood.rt.advance(1_000)
  assert_eq((old.missed, far.heard_on(2).length()), (0, 3))
  // The dial gives up at 23 s; something came on the old link meanwhile: kept. Its next line is its next ping.
  stood.rt.advance(4_000)
  assert_eq(mesh.racing.length(), 0)
  assert_true(mesh.current(peer) is Some(now) && physical_equal(now, old))
  assert_eq(far.closes.length(), 0)
  assert_eq(far.heard_on(2), [
    "0 2 {\"credential\":\"c1\"}", "5000 2 {\"credential\":\"c1\"}", "10000 2 {\"credential\":\"c1\"}", "23000 2 {\"credential\":\"c1\"}",
  ])
}

///|
test "a probe sent whose time ran out before its answer: the answer is read as it comes, so a link kept after it reads each answer to the line it wrote" {
  let (stood, far, mesh, old, _) = quick_link()
  // The peer numbers its answers by the lines it took on a connection.
  // (two were answered already: its hello and its first ping)
  let taken = Ref(2)
  far.answers = (_, _) => {
    guard far.heard[far.heard.length() - 1].contains(" 2 {") else { return Some("{\"ok\":true}") }
    taken.val += 1
    Some("{\"ok\":true,\"n\":\{taken.val}}")
  }
  far.away = true
  // The ping of 10 s is answered at 13.5 s, so the probe is sent then; its answer takes 6 s, past its time (18 s).
  far.takes = 3_500
  stood.rt.advance(tick_ms)
  far.takes = 6_000
  stood.rt.advance(ping_timeout_ms + 500)
  assert_eq(far.heard_on(2)[3], "13500 2 {\"credential\":\"c1\"}")
  far.takes = 0
  stood.rt.advance(probe_ms - 500)
  assert_eq(mesh.racing.length(), 1)
  // The next ping, of 18 s, waits its turn behind the probe; the probe's answer comes at 19.5 s and is read, and
  // the ping goes then and is answered.
  stood.rt.advance(1_500)
  assert_eq(far.heard_on(2)[4], "19500 2 {\"credential\":\"c1\"}")
  assert_eq(old.missed, 0)
  // The new link's dial is answered at 20 s; something came on the old one meanwhile: kept.
  stood.rx[2] = 500.0
  stood.rt.advance(500)
  far.away = false
  stood.dialled()
  assert_eq(mesh.racing.length(), 0)
  assert_true(mesh.current(peer) is Some(now) && physical_equal(now, old))
  // A line written on its control stream now is answered by its own answer: the sixth line, the sixth answer.
  let exchanged = stood.go(() => old.exchange("c1"))
  guard exchanged.poll() is Some(Succeeded(answer)) else { fail("no answer: \{ended_as(exchanged)}") }
  assert_eq(far.heard_on(2).length(), 6)
  assert_eq(answer.stringify(), "{\"ok\":true,\"n\":6}")
}

///|
test "a link asked for again while it is raced, ended meanwhile: the race is over, its dial given up, and one dial is made for the place" {
  let (stood, far, mesh, old, source) = quick_link()
  far.lose(2)
  far.away = true
  stood.rt.advance(tick_ms + ping_timeout_ms)
  assert_eq((mesh.racing.length(), far.dials, stood.held.length()), (1, [0L, 13000L], 1))
  // The old connection ends at 14 s (the transport gave it up), and its holder asks for the link again.
  stood.rt.advance(1_000)
  far.end(2, "", kind="timeout")
  let asking = stood.go(() => mesh.link(peer, source.gives()))
  assert_eq((mesh.racing.length(), far.dials, stood.held.length()), (0, [0L, 13000L, 14000L], 1))
  assert_eq(ended_as(asking), "waiting")
  far.away = false
  stood.dialled()
  guard asking.poll() is Some(Succeeded(next)) else { fail("the link did not open: \{ended_as(asking)}") }
  assert_true(mesh.current(peer) is Some(now) && physical_equal(now, next) && !physical_equal(next, old))
  stood.rt.advance(2 * connect_timeout_ms)
  assert_eq((far.dials.length(), mesh.live.length(), stood.held.length()), (3, 1, 0))
}

///|
test "one peer in two scopes, both links suspect at once: each is raced by itself, its new link dialled with its own credential and put at its own place, its own holder told" {
  let (stood, far) = Stood::with_peer()
  let mesh = stood.mesh()
  let one = Source::new(of="a")
  let two = Source::new(of="b")
  let a = stood.opened(mesh, one.gives(), scope="one")
  let b = stood.opened(mesh, two.gives(), scope="two")
  stood.rt.advance(tick_ms)
  let told_a = stood.go(() => mesh.replaced(a))
  let told_b = stood.go(() => mesh.replaced(b))
  // The first scope's alone (connection 2) first: the other's link is not raced, nor told anything.
  far.lose(2)
  stood.rt.advance(tick_ms + ping_timeout_ms)
  guard mesh.current(peer, scope="one") is Some(a2) else { fail("no link in the first scope") }
  assert_true(!physical_equal(a2, a) && a2.usable() && a2.scope == "one")
  assert_true(mesh.current(peer, scope="two") is Some(now) && physical_equal(now, b))
  assert_eq((ended_as(told_a), ended_as(told_b), far.dials), ("ok", "waiting", [0L, 0L, 13000L]))
  assert_true(first_saying(far.heard, "a2").has_prefix("13000 ") && first_saying(far.heard, "b2") == "")
  assert_eq((one.asked, two.asked), (["kept", "kept"], ["kept"]))
  // Then both, at one tick: two races, two dials, each hello its scope's next credential.
  let again_a = stood.go(() => mesh.replaced(a2))
  stood.rt.advance(retire_ms)
  far.lose(a2.conn_handle())
  far.lose(b.conn_handle())
  stood.rt.advance(tick_ms + ping_timeout_ms)
  guard mesh.current(peer, scope="one") is Some(a3) else { fail("no link in the first scope") }
  guard mesh.current(peer, scope="two") is Some(b2) else { fail("no link in the second scope") }
  assert_true(!physical_equal(a3, a2) && !physical_equal(b2, b) && a3.usable() && b2.usable())
  assert_eq((a3.scope, b2.scope), ("one", "two"))
  assert_eq((ended_as(again_a), ended_as(told_b), far.dials.length(), mesh.racing.length()), ("ok", "ok", 5, 0))
  assert_true(first_saying(far.heard, "a3") != "" && first_saying(far.heard, "b2") != "")
  assert_eq((one.asked, two.asked), (["kept", "kept", "kept"], ["kept", "kept"]))
  // (and each new link said its hello on a connection of its own)
  assert_true(a3.conn_handle() != b2.conn_handle())
  assert_true(first_saying(far.heard, "a3").contains(" \{a3.conn_handle()} {"))
  assert_true(first_saying(far.heard, "b2").contains(" \{b2.conn_handle()} {"))
}

// ── a link that ended while its ping was out ──

///|
test "a link its peer ends while a ping of it is out is not raced: its end is told with the peer's reason, nothing is dialled in its place, and the next link asked for dials once" {
  let (stood, far, mesh, link, source) = quick_link()
  let replaced = stood.go(() => mesh.replaced(link))
  let closed = stood.go(() => link.closed())
  // The ping of 10 s is out (its answer a second away) as the peer ends the connection, at 10.5 s.
  far.takes = 1_000
  stood.rt.advance(tick_ms + 500)
  far.end(2, "credential_revoked")
  assert_eq((link.missed, mesh.racing.length(), far.dials), (1, 0, [0L]))
  guard link.ended() is Some(why) else { fail("a link whose connection ended says it has not") }
  assert_eq((why.kind, why.reason, why.words()), ("application", "credential_revoked", say("credential_revoked")))
  assert_eq((ended_as(closed), ended_as(replaced)), ("ok", "waiting"))
  // Nothing is dialled by itself after, and the link is the one there until its program asks again.
  far.takes = 0
  stood.rt.advance(2 * renew_ms)
  assert_eq((far.dials, far.heard_on(2).length(), ended_as(replaced)), ([0L], 3, "waiting"))
  assert_true(mesh.current(peer) is Some(now) && physical_equal(now, link))
  let again = stood.opened(mesh, source.gives())
  assert_true(!physical_equal(again, link) && again.usable())
  assert_eq((far.dials.length(), ended_as(replaced)), (2, "ok"))
}

///|
test "a link its peer ends while its third ping in a row is out is not dialled for: its end is told with the peer's reason, and the next link asked for dials once" {
  let (stood, far, mesh, link, source) = third_ping_out()
  let replaced = stood.go(() => mesh.replaced(link))
  // (the third ping went at 15 s; the peer ends the connection a second later)
  stood.rt.advance(1_000)
  far.end(2, "credential_revoked")
  assert_eq((link.missed, far.dials, far.closes.length()), (3, [0L], 0))
  guard link.ended() is Some(why) else { fail("a link whose connection ended says it has not") }
  assert_eq((why.kind, why.reason), ("application", "credential_revoked"))
  // (no way there answers: that much the tick tells; the rest is the link's end to tell)
  assert_eq((mesh.healthy(peer), ended_as(replaced)), (false, "waiting"))
  far.quiet = false
  far.answers = (_, _) => Some("{\"ok\":true}")
  stood.rt.advance(2 * renew_ms)
  assert_eq((far.dials, ended_as(replaced)), ([0L], "waiting"))
  let again = stood.opened(mesh, source.gives())
  assert_true(!physical_equal(again, link) && again.usable())
  assert_eq((far.dials.length(), ended_as(replaced), source.asked), (2, "ok", ["kept", "kept"]))
}

// ── let go of, or closed, while raced ──

///|
test "a place let go of, or the mesh closed, at each turn from the ping missed on, the new link's dial answered at once or not at all: no link is there, every connection made is closed once, and nothing goes on" {
  for closes in [false, true] {
    for away in [false, true] {
      for late in 0..<40 {
        let (stood, far, mesh, old, _) = quick_link()
        far.lose(2)
        far.away = away
        let replaced = stood.go(() => mesh.replaced(old))
        stood.rt.advance(tick_ms + ping_timeout_ms - 1)
        // A fiber that ends it `late` turns into the millisecond the ping is missed in: before the race is begun,
        // as it dials, as the new link opens, once it is the place's.
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
        stood.rt.advance(1)
        assert_eq((ended_as(ending), ended_as(replaced)), ("ok", "ok"))
        assert_true(mesh.current(peer) is None)
        assert_eq((mesh.racing.length(), mesh.links.length(), stood.held.length()), (0, 0, 0))
        stood.rt.advance(retire_ms)
        // Each connection made (the link's, and the race's where it dialled and was answered) closed here once.
        let made = far.conns.length()
        assert_eq((far.closes.length(), mesh.live.length()), (made, 0))
        assert_true(far.closes.filter(one => one.has_prefix("2 ")).length() == 1)
        let said = stood.said.length()
        stood.rt.advance(2 * renew_ms)
        assert_eq(stood.said.length(), said)
        assert_true(far.dials.length() <= 2)
      }
    }
  }
}

///|
/// A race whose new link's dial is the test's to answer (`stood.dial_answered()`: its connection handle 4): the old
/// link's peer gone from under it, the clock at 13 s.
fn race_dialling() -> (Stood, Peer, Mesh, Link) raise {
  let (stood, far, mesh, old, _) = quick_link()
  far.lose(2)
  far.away = true
  stood.rt.advance(tick_ms + ping_timeout_ms)
  assert_eq((old.missed, mesh.racing.length(), stood.held.length()), (1, 1, 1))
  far.away = false
  (stood, far, mesh, old)
}

///|
/// Whether `closes` are those two, in either order.
fn both(closes : Array[String], one : String, other : String) -> Bool {
  closes.length() == 2 && closes.contains(one) && closes.contains(other)
}

///|
test "a place let go of by its program while its link is raced, the new link's dial not answered: both are let go, whoever waits is told, and nothing of the race goes on" {
  let (stood, far, mesh, old, _) = quick_link()
  far.lose(2)
  far.away = true
  stood.rt.advance(tick_ms + ping_timeout_ms)
  assert_eq((mesh.racing.length(), stood.held.length()), (1, 1))
  let replaced = stood.go(() => mesh.replaced(old))
  let health = stood.go(() => mesh.health_change(peer, true))
  let closed = stood.go(() => old.closed())
  mesh.drop_link(peer, reason="signed out")
  stood.run()
  // The old link closed with the program's reason, the dial given up at the shell, the race over.
  assert_eq(far.closes, ["2 signed out"])
  assert_eq((mesh.racing.length(), stood.held.length(), mesh.links.length()), (0, 0, 0))
  assert_eq((ended_as(replaced), ended_as(closed)), ("ok", "ok"))
  assert_true(health.poll() is Some(Succeeded(false)))
  // Nothing goes on: no ping, no probe, no dial, and nothing comes of the race later.
  let said = stood.said.length()
  stood.rt.advance(2 * renew_ms)
  assert_eq((stood.said.length(), far.dials, mesh.live.length()), (said, [0L, 13000L], 0))
  assert_eq(ended_as(stood.go(() => mesh.close())), "ok")
}

///|
test "a place let go of by its program at each turn from the answer of its race's dial on: whichever of the two is the place's link then is closed with the program's reason, the other let go too, no link is there and nothing goes on" {
  let opening = Ref(0)
  let opened = Ref(0)
  let switched = Ref(0)
  for late in 0..<12 {
    let (stood, far, mesh, old) = race_dialling()
    let replaced = stood.go(() => mesh.replaced(old))
    // The dial is answered, and a fiber lets go of the place `late` turns after: while the new link is being
    // opened, once it is open, or once it is the place's.
    stood.dial_answered()
    let dropping = stood.start(() => {
      for _ in 0..<late {
        @effect.pause()
      }
      mesh.drop_link(peer, reason="gone")
    })
    stood.run()
    assert_eq((ended_as(dropping), ended_as(replaced)), ("ok", "ok"))
    assert_true(mesh.current(peer) is None)
    assert_eq((mesh.racing.length(), mesh.links.length()), (0, 0))
    // The old link stays open only where the new one had taken its place: 10 s, then closed.
    stood.rt.advance(retire_ms)
    let closes = far.closes
    if both(closes, "2 gone", "4 opening ended") {
      // Cut while its opening was under way: the opening closed the connection it had made.
      opening.val += 1
    } else if both(closes, "2 gone", "4 closed") {
      // Open, and not yet the place's: closed as the race was ended.
      opened.val += 1
    } else if both(closes, "2 closed", "4 gone") {
      // The place's already: it is the one let go of with the program's reason, the old one closed in its time.
      switched.val += 1
    } else {
      fail("let go of \{late} turns in: \{closes.join(", ")}")
    }
    assert_eq((stood.times("conn.close 4") >= 1, mesh.live.length()), (true, 0))
    let said = stood.said.length()
    stood.rt.advance(2 * renew_ms)
    assert_eq((stood.said.length(), far.dials), (said, [0L, 13000L]))
    assert_eq(ended_as(stood.go(() => mesh.close())), "ok")
  }
  // (each of the three was let go of: were an opening or a race to take more turns, more are to be tried here)
  assert_true(opening.val > 0 && opened.val > 0 && switched.val > 0)
}

///|
test "the mesh closed at each turn from the answer of a race's dial on: both links are closed, whoever waits is told, the race is no more and nothing goes on" {
  let cut = Ref(0)
  let open = Ref(0)
  for late in 0..<12 {
    let (stood, far, mesh, old) = race_dialling()
    let replaced = stood.go(() => mesh.replaced(old))
    let health = stood.go(() => mesh.health_change(peer, true))
    let ended = stood.go(() => old.closed())
    stood.dial_answered()
    let closing = stood.start(() => {
      for _ in 0..<late {
        @effect.pause()
      }
      mesh.close()
    })
    stood.run()
    assert_eq(ended_as(closing), "ok")
    assert_eq((ended_as(replaced), ended_as(ended)), ("ok", "ok"))
    assert_eq(ended_as(health), "mesh: " + say("closed"))
    assert_true(mesh.current(peer) is None)
    assert_eq((mesh.racing.length(), mesh.links.length(), mesh.live.length(), mesh.health_waits.length()), (0, 0, 0, 0))
    // Each connection closed here once and for a reason of the base's, the endpoint after them.
    if both(far.closes, "2 closed", "4 opening ended") {
      cut.val += 1
    } else if both(far.closes, "2 closed", "4 closed") {
      open.val += 1
    } else {
      fail("closed \{late} turns in: \{far.closes.join(", ")}")
    }
    assert_eq(stood.said[stood.said.length() - 1], "iroh.close 1")
    let said = stood.said.length()
    stood.rt.advance(2 * renew_ms)
    assert_eq((stood.said.length(), far.dials), (said, [0L, 13000L]))
  }
  // (closed while the new link was being opened, and once it was open)
  assert_true(cut.val > 0 && open.val > 0)
}

///|
test "the mesh closed while a link is raced and its new link's dial not answered: the dial is given up, whoever waits is told, and nothing goes on" {
  let (stood, far, mesh, old, source) = quick_link()
  far.lose(2)
  far.away = true
  stood.rt.advance(tick_ms + ping_timeout_ms + 1_000)
  assert_eq((mesh.racing.length(), stood.held.length()), (1, 1))
  let replaced = stood.go(() => mesh.replaced(old))
  let health = stood.go(() => mesh.health_change(peer, true))
  assert_eq(ended_as(stood.go(() => mesh.close())), "ok")
  assert_eq((ended_as(replaced), ended_as(health)), ("ok", "mesh: " + say("closed")))
  assert_eq((mesh.racing.length(), stood.held.length(), mesh.live.length()), (0, 0, 0))
  assert_eq(far.closes, ["2 closed"])
  let said = stood.said.length()
  stood.rt.advance(2 * renew_ms)
  assert_eq((stood.said.length(), far.dials), (said, [0L, 13000L]))
  assert_eq(ended_as(stood.go(() => mesh.link(peer, source.gives()))), "mesh: " + say("closed"))
  assert_eq(ended_as(stood.go(() => mesh.health_change(peer, true))), "mesh: " + say("closed"))
}
