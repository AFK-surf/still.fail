// How a place is, by its pings, and a link suspect raced against a new one: as the TypeScript mesh does both
// (client/core-ts/src/mesh.ts: `standing`, `healthy`, `healthChange`; `#suspect`, `#race`, `#switch`), with its
// numbers, but for how the old link is asked whether it answers (`Mesh::race` says).

///|
/// The usable links to a place: the ways requests may go there. Today the one in `links`, where it is usable; where
/// a place comes to have several ways, the others are counted here, and what goes by "any way" or "no other way"
/// (`standing`, `healthy`, `suspect`) goes by all of them with nothing else changed.
fn Mesh::ways(self : Mesh, place : Place) -> Array[Link] {
  match self.links.get(place) {
    Some({ result: Some(Open(link)), .. }) if link.usable() => [link]
    _ => []
  }
}

///|
/// Whether a way to `peer` in `scope` is up: one open that answered its last ping (one not pinged yet: its
/// handshake did). Asked as what went on a link ended: with a way standing, it goes on at once on that.
pub fn Mesh::standing(self : Mesh, peer : String, scope? : String = "") -> Bool {
  self.ways({ scope, peer }).iter().any(way => way.missed == 0)
}

///|
/// Whether a way to `peer` in `scope` answers its pings: one open that has not missed `dead_pings` in a row (none
/// open: no).
pub fn Mesh::healthy(self : Mesh, peer : String, scope? : String = "") -> Bool {
  self.ways({ scope, peer }).iter().any(way => way.missed < dead_pings)
}

///|
/// Waits until whether a way to `peer` in `scope` answers its pings is no more `was`, and gives what it is then: as
/// the ticks find it (a link's pings, every `tick_ms`), as a link is opened there (it answers) and as one is let go
/// of. At once where what was last told is not `was` (nothing told yet: what `healthy` says). What a link's end
/// alone does to it is not told: that is `Link::closed`'s, and `Mesh::replaced`'s once another is opened there.
/// Fails as closed once the mesh is.
///
/// What reads a stream on a link waits here beside it, `was` what it last knew: no more answered while the stream
/// is quiet, its place is not reached, and answered again it is (not the stream's end: that the stream says).
pub async fn Mesh::health_change(self : Mesh, peer : String, was : Bool, scope? : String = "") -> Bool {
  let place : Place = { scope, peer }
  guard !self.closed else { raise failed("closed") }
  let now = self.health.get(place).unwrap_or(self.healthy(peer, scope~))
  if now != was {
    return now
  }
  let told : @effect.Deferred[Bool] = @effect.Deferred::new()
  self.health_waits.push((place, was, told))
  // (given up while it waits, it is no more waited for)
  defer {
    self.health_waits.retain(wait => !physical_equal(wait.2, told))
  }
  told.wait()
}

///|
/// How `place` is now, told to whoever waits for it to be no more what they said, where it is not what was last
/// told. It is worked out of what is at the place as this is called, so it is right whoever calls it, after
/// whatever wait.
fn Mesh::tell_health(self : Mesh, place : Place) -> Unit {
  let now = self.healthy(place.peer, scope=place.scope)
  guard self.health.get(place) != Some(now) else { return }
  self.health[place] = now
  // (those told wake a step later, and take themselves out then)
  for wait in self.health_waits {
    if wait.0 == place && wait.1 != now {
      ignore(wait.2.succeed(now))
    }
  }
}

///|
/// A race: the link suspect, and the new one opened beside it. While one is in `racing`, its old link is the one
/// at its place: whatever puts another there or takes it out ends the race first (`Mesh::end_race`), or is the
/// race's own verdict.
priv struct Race {
  old : Link
  /// The race's own fiber, and the one that opens the new link: cut where the race is ended from outside.
  mut fiber : @effect.Fiber[Unit]?
  mut dial : @effect.Fiber[Unit]?
  /// The new link once it is open, until it has a place or is closed.
  mut next : Link?
  /// Whether the old link's answer is still waited for: its probe goes on the line only while it is.
  mut probing : Bool
}

///|
/// How a race ended.
priv enum Won {
  Old
  New(Link)
  Neither
}

///|
/// Which of a race's two came first: whether the old link answered in its time, or the new one as its opening ended
/// (none: it did not open).
priv enum First {
  Probed(Bool)
  Dialled(Link?)
}

///|
/// The link at `place` missed its ping, its last one answered quickly (in under half a ping's time), and no other
/// way there is up: a new link is raced beside it at once (`Mesh::race`), not after `dead_pings`. A peer whose
/// process ended and started again leaves its old connection open and silent until the transport's idle timeout. A
/// link whose pings take near `ping_timeout_ms` misses them for its slowness alone, and is not dialled again for
/// each. Asked of a link that is usable (`Mesh::steer`): one that ended is not a way, and is not raced.
fn Mesh::suspect(self : Mesh, place : Place, opening : Opening, link : Link) -> Unit {
  guard !self.racing.contains(place) else { return }
  guard link.missed == 1 && link.answered_ms is Some(took) && took < ping_timeout_ms / 2 else { return }
  // (no other way up: with one link a place there is never another, `Mesh::ways`)
  guard !self.ways(place).iter().any(way => !physical_equal(way, link) && way.missed == 0) else { return }
  let race : Race = { old: link, fiber: None, dial: None, next: None, probing: true }
  // (in `racing` from this step: what lets go of the place before the race's fiber took its first finds it)
  self.racing[place] = race
  race.fiber = Some(self.scope.fork(name="mesh race", () => self.race(place, opening, race)))
}

///|
/// A link suspect against a new one opened beside it at once: whichever answers first. The new one is dialled with
/// the old one's credentials' source; the old one is asked its credential again and given `probe_ms` to answer. The
/// old one answering first, the new one is let go (its dial given up, or closed); the new one opening first, it
/// takes the place (`Mesh::switch`); neither, the old one is let go and nothing dialled: the next `link` does. And
/// where anything came on the old one meanwhile, the transport's own packets too, and it has not ended, it is there
/// after all (the network only paused, and moving would cut what is open on it): it is kept, whichever came first.
///
/// The old link is asked the `Mesh::ping` way: its exchange is a fiber of the mesh's that nothing cuts short, in
/// its turn on the control stream behind whatever exchange is out on it (the ping it missed), and what waits
/// `probe_ms` is this race, not the exchange. Its time run out before its turn came, nothing is sent; run out with
/// its line sent, its answer is still read as it comes. So the control stream is never left with a line sent and
/// its answer unread, and a link kept after its probe's time ran out reads its answers in their order. (The
/// TypeScript mesh gives the exchange itself up at that time, its line sent or not, and may keep the link all the
/// same, one answer behind.)
async fn Mesh::race(self : Mesh, place : Place, opening : Opening, race : Race) -> Unit {
  let old = race.old
  let heard = old.heard()
  let dialled : @effect.Deferred[Link?] = @effect.Deferred::new()
  race.dial = Some(
    self.scope.fork(name="mesh race dial", () => {
      let made = attempt(() => self.open(place, old.credentials, false))
      // (cut as the race ends otherwise, it comes to nothing here: an interruption is this fiber's as it next
      // resumes, which is inside the opening, whose own leaving closes what it made)
      match made {
        Did(link) => {
          race.next = Some(link)
          ignore(dialled.succeed(Some(link)))
        }
        Fell(_) => ignore(dialled.succeed(None))
      }
    }),
  )
  let answered : @effect.Deferred[Bool] = @effect.Deferred::new()
  ignore(
    self.scope.fork(name="mesh probe", () => {
      let asked = attempt(() => old.lock.with_permit(() => {
        guard race.probing else { return false }
        old.control.send(old.credential)
        ignore(old.control.answer())
        true
      }))
      ignore(answered.succeed(asked is Did(true)))
    }),
  )
  // (the probe's time is its own, as the dial's is: where the dial fails first, the old link has what is left of it)
  let probed : @effect.Deferred[Bool] = @effect.Deferred::new()
  ignore(
    self.scope.fork(name="mesh probe time", () => {
      let said = @effect.timeout(probe_ms, () => answered.wait())
      race.probing = false
      ignore(probed.succeed(said == Some(true)))
    }),
  )
  let first = @effect.race_first(() => Probed(probed.wait()), () => Dialled(dialled.wait()))
  let won : Won = match first {
    Probed(true) => Old
    Probed(false) =>
      match dialled.wait() {
        Some(link) => New(link)
        None => Neither
      }
    Dialled(Some(link)) => New(link)
    Dialled(None) => if probed.wait() { Old } else { Neither }
  }
  // Something came on the old one meanwhile, its probe answered or not: it is there after all.
  let won : Won = if !(won is Old) && old.ended() is None && old.heard() > heard { Old } else { won }
  // (ended from outside while this waited, this fiber was cut there and is not here: `Mesh::end_race`)
  race.probing = false
  self.racing.remove(place)
  match won {
    Old => race.let_go()
    Neither =>
      // (the old one let go, if it is its place's still: this waited)
      if self.links.get(place) is Some(current) && physical_equal(current, opening) {
        old.close()
        self.links.remove(place)
        self.changed()
        self.tell_health(place)
      }
    New(next) => {
      race.next = None
      self.switch(place, opening, old, next)
    }
  }
}

///|
/// The new link of a race is let go: closed where it is open, its dial given up where it is not (the opening
/// closes a connection made by then, or one the shell could not stop as it comes: `Mesh::open`).
fn Race::let_go(self : Race) -> Unit {
  match self.next {
    Some(next) => {
      self.next = None
      next.close()
    }
    None => if self.dial is Some(dial) { dial.interrupt() }
  }
}

///|
/// The race at `place` is ended from outside: its place is let go of (`drop_link`) or asked for anew
/// (`Mesh::dial`), and it has nothing left to decide. No more its place's, its new link let go, and its own fiber
/// cut. It is taken out here and not by that fiber: one cut before its first step runs nothing, and would leave
/// the place raced for good.
fn Mesh::end_race(self : Mesh, place : Place) -> Unit {
  guard self.racing.get(place) is Some(race) else { return }
  self.racing.remove(place)
  race.probing = false
  if race.fiber is Some(fiber) {
    fiber.interrupt()
  }
  race.let_go()
}

///|
/// `next` takes the place of `old`, whose opening `opening` was, if that is the place's still (else `next` is
/// closed: the place was let go of, or asked for again, while they raced). It is the place's link in this step,
/// open: whoever holds `old` is told (`Mesh::replaced`) and, asking for the link, is given `next` with no dial.
/// `old` is no more a way to go back to, and is closed `retire_ms` later, so that what is under way on it may
/// still end.
fn Mesh::switch(self : Mesh, place : Place, opening : Opening, old : Link, next : Link) -> Unit {
  guard !self.closed && self.links.get(place) is Some(current) && physical_equal(current, opening) else {
    next.close()
    return
  }
  let taken : Opening = { done: @effect.Deferred::new(), result: Some(Open(next)), fiber: None }
  ignore(taken.done.succeed(next))
  self.links[place] = taken
  self.changed()
  self.adopt(place, taken, next)
  // (cut as the mesh closes, which closes every link not ended itself: `live`)
  ignore(
    self.scope.fork(name="mesh retire", () => {
      @effect.sleep(retire_ms, later=true)
      old.close()
    }),
  )
}
