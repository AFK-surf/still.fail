// What a program's word that its connections are suspect does (`Mesh::wake`), and the endpoint bound anew where it
// is stuck: as the TypeScript mesh does at a wake and for a stuck endpoint (client/core-ts/src/mesh.ts: `#watch`,
// `#hedge`, `#rebind`), but for when an endpoint may be bound anew (`Mesh::rebind` says).

///|
/// How long after the endpoint was bound anew it is not bound anew again.
pub let rebind_ms : Int = 5_000

///|
/// The program says its connections are suspect: it was away and is back, its network changed, or its person asks
/// to try again. Which of those, and how long away counts, is the program's to decide: the mesh is told only when
/// it is so (a device asleep runs no clock of the mesh's to measure it by; the TypeScript mesh's program says so
/// for a network changed, a person's retry, or 30 s away). At once, waiting for nothing:
///
/// - the shell is told the network may have changed (`iroh.networkChange`: the endpoint looks at its ways anew);
/// - every link that is its place's and usable is raced against a new one (`Mesh::race`, as a link that missed a
///   ping is, but by the two answers alone), unless one is raced already;
/// - every opening under way has a second dial tried beside its first, once (`Mesh::hedge`).
///
/// What else a wake comes to do goes here, each with what it is of: speeds seen on the network of before
/// forgotten (there only where the network changed: a word this call is given then), the addresses a peer said
/// tried again, and the endpoints of other ways told as this one is.
pub fn Mesh::wake(self : Mesh) -> Unit {
  guard !self.closed else { return }
  // (being bound anew: the endpoint that comes is new to its network, and nothing is on either)
  guard !self.rebinding else { return }
  self.shell.tell("iroh.networkChange", { "id": self.endpoint })
  for place, opening in self.links {
    match opening.result {
      Some(Open(link)) =>
        if link.usable() && !self.racing.contains(place) {
          self.begin_race(place, opening, link, false)
        }
      None => self.hedge(place, opening)
      Some(Failed(_, _)) => ()
    }
  }
}

///|
/// A second dial beside the first of an opening under way, on the same endpoint, with what the first is dialled
/// with: whichever brings a link first is the opening's, and the other is given up (`Mesh::dialled`). Once an
/// opening: a wake after leaves both to end.
fn Mesh::hedge(self : Mesh, place : Place, opening : Opening) -> Unit {
  guard opening.result is None && opening.hedge is None else { return }
  opening.dials += 1
  // (cut as its opening ends otherwise, or the mesh closes, it says nothing: whoever ended the opening said it)
  opening.hedge = Some(
    self.scope.fork(name="mesh hedge", () => {
      let made = attempt(() => self.open(place, opening.credentials, opening.fresh))
      self.dialled(place, opening, true, made)
    }),
  )
}

///|
/// Whether nothing is on the endpoint: no link whose connection has not ended (`live`: a place's, one another took
/// the place of and not yet closed, one a race opened; a stream of its peer's waited for is a link's), no opening
/// under way (with the dial tried beside it), no race. What comes to hold the endpoint otherwise is counted here.
fn Mesh::idle(self : Mesh) -> Bool {
  self.live.length() == 0 && self.racing.length() == 0 && !self.links.values().any(opening => opening.result is None)
}

///|
/// Whether what is on the endpoint all ends by itself, in a time the mesh bounds: something is, and no connection
/// is open. What is left then is an opening under way (its time: `connect_timeout_ms` once the endpoint is on a
/// relay, `onto_max_ms` more where it is on none; and that again from a wake that tried it a second time), a race
/// whose old link ended (its dial is an opening's), a link ended whose answer is not said yet (its read fails
/// with it). A connection open has no such time: with one, the endpoint is dialled on as it is.
fn Mesh::settling(self : Mesh) -> Bool {
  !self.idle() && !self.live.iter().any(link => !link.gone.is_done())
}

///|
/// Whether the endpoint was last bound anew long enough ago.
fn Mesh::may_rebind(self : Mesh) -> Bool {
  match self.rebound_at {
    Some(at) => self.shell.rt.now() - at >= rebind_ms.to_int64()
    None => true
  }
}

///|
/// The endpoint bound anew with the same key, and the one before closed. Only while nothing is on the endpoint
/// (`Mesh::idle`), and nothing comes to be while it is under way: every dial is a `link`'s, which waits to be told
/// it ended (`Mesh::hold`), or needs a link there is none of. So no fiber holds the handle of before, but a dial
/// the shell could not stop for an opening given up, whose connection, should it still come, is closed to be
/// forgotten as ever.
///
/// And an endpoint taken for stuck comes to have nothing on it: from the first `link` that finds it so with no
/// connection open on it and `rebind_ms` gone since the last bind, no new dial is begun on it (`Mesh::link`), so
/// it is bound anew as the last opening under way ends, an opening's time after at the most (`Mesh::settling`),
/// however many places are asked for meanwhile; if nobody waits by then, by the next `link`.
///
/// A fiber of the mesh's that nothing cuts short once begun: the shell binds whoever waits, and an endpoint bound
/// for nobody would stay. So `Mesh::close` waits for it with its other fibers, and it looks again as the shell
/// answers: the mesh closed meanwhile, the new endpoint never was its and is closed here, the close closing the one
/// of before; else the new one is the mesh's from that step, whoever waited goes on at once, and the one of before
/// is closed here after, by this fiber still. Each is closed once. Cut before its first step it asked nothing, and
/// the close told whoever waited. One that fails leaves the endpoint as it was, and the next is not tried before
/// `rebind_ms`.
fn Mesh::rebind(self : Mesh) -> Unit {
  self.rebinding = true
  self.rebound_at = Some(self.shell.rt.now())
  ignore(
    self.scope.fork(name="mesh rebind", () => @effect.uninterruptible(() => {
      let bound = attempt(() => bind(self.shell, self.options, self.secret))
      // (this waited: closed meanwhile, the endpoint that came is nobody's)
      let gone = match bound {
        Did(endpoint) =>
          if self.closed {
            Some(endpoint)
          } else {
            let before = self.endpoint
            self.endpoint = endpoint
            self.stuck = false
            Some(before)
          }
        Fell(_) => None
      }
      self.rebinding = false
      self.eased()
      if gone is Some(endpoint) {
        ignore(attempt(() => self.shell.call("iroh.close", { "id": endpoint })))
      }
    })),
  )
}
