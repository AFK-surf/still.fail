// The device side of the mesh: this device's iroh endpoint (the shell's) and its links to peers, as the
// TypeScript mesh keeps them (client/core-ts/src/mesh.ts), whose bytes and times these are: the endpoint's key the
// device key (kept under `device`, 32 bytes), a link dialled on the protocol its user names and let in by the
// credential its user gives, said in the control stream's first line with what its user says in every one; the
// credential presented again every `tick_ms` as the link's ping and every `renew_ms` as its renewal; a request a
// stream (link.mbt). A link that ended, or whose renewal was refused, is opened again by the next `link`.
//
// One connection to a peer, on the one endpoint, through the relays given (and direct, where the endpoint may): what
// that mesh does beside that is not here yet (the choice among several ways and relays, each relay's own
// endpoint, a peer dialled at the addresses it said, peers looked up on the LAN and in the DHT, a suspect link raced
// against a new one, the endpoint bound anew when stuck, traces, the day's tally, waking). `Options` and `Link` are
// where those go: a way more is a link more to the same peer, chosen among under `Mesh::link`.

///|
/// The key the device's key is kept under.
pub let device_key : String = "device"

///|
/// How often a link presents a fresh credential.
pub let renew_ms : Int = 5 * 60_000

///|
/// How long an opening may take once the endpoint is on a relay, and how long it waits to be on one before that counts
/// all the same (looked at every `onto_recheck_ms`).
pub let connect_timeout_ms : Int = 10_000

///|
pub let onto_max_ms : Int = 30_000

///|
let onto_recheck_ms : Int = 250

///|
/// How often a link is pinged (its credential presented again, answered by the peer itself), and when a ping not
/// answered counts as missed.
pub let tick_ms : Int = 5_000

///|
pub let ping_timeout_ms : Int = 3_000

///|
/// Pings in a row a link may miss before it is let go, and its peer dialled anew.
let dead_pings : Int = 3

///|
/// The fields of a control line that are the mesh's own to write: what `Options.says` may not name.
let own_fields : Array[String] = ["credential", "traceparent"]

///|
/// Where the mesh keeps what it keeps (the device's key): small values by key.
pub(all) struct Store {
  get : async (String) -> Bytes?
  set : async (String, Bytes) -> Unit
}

///|
/// The shell's own keeping (`storage.*`): a file a key in the directory the shell was started with.
pub fn shell_store(shell : @shell.Shell) -> Store {
  {
    get: key => shell.call("storage.get", { "key": Json::string(key) }).bytes,
    set: (key, value) => ignore(shell.call("storage.set", { "key": Json::string(key) }, bytes=value)),
  }
}

///|
/// What a mesh is made with: its user's protocol, none of which it says itself.
pub(all) struct Options {
  /// The protocol its links are dialled on (what the peer's endpoint takes).
  alpn : String
  /// The relays the endpoint is on, and a peer is dialled through.
  relays : Array[String]
  /// Through the relays alone: the endpoint has no way direct.
  relay_only : Bool
  /// What every line of a link's control stream says after its credential, the first and those that present it again;
  /// none: the credential alone. Never `credential` nor `traceparent`, a line's own.
  says : Map[String, Json]?
  /// What a peer's refusal of a link's first line is, by its answer as parsed (an object with `error`) and the reason
  /// it gave, where it refuses for something else than the credential; none, or None of it: the credential refused.
  refusal : ((Json, String) -> Error?)?
}

///|
/// How an opening ended.
priv enum Opened {
  Open(Link)
  /// What it failed with, and whether for no answer in time.
  Failed(Error, Bool)
}

///|
/// An opening, shared by everyone who asks for the same peer meanwhile.
priv struct Opening {
  done : @effect.Deferred[Link]
  mut result : Opened?
}

///|
/// The opening's time ran out: whether the connection was made by then.
priv suberror OpeningTimeout {
  OpeningTimeout(Bool)
}

///|
pub struct Mesh {
  priv shell : @shell.Shell
  priv options : Options
  /// The endpoint at the shell, and its id.
  priv endpoint : Json
  priv id : String
  /// Its fibers: the dials, each link's answer, pings and renewal.
  priv scope : @effect.Scope
  /// The links, by peer.
  priv links : Map[String, Opening]
  priv mut closed : Bool
}

///|
/// Binds the endpoint with the device key kept in `store` (made and kept the first time).
pub async fn Mesh::make(shell : @shell.Shell, store : Store, options : Options) -> Mesh {
  if options.says is Some(says) {
    for field in own_fields {
      if says.contains(field) {
        // (its user's mistake: no link would say what it means)
        raise MeshError(code="invalid_params", message="Options.says names \{field}: a control line's own, which the mesh writes", cause="")
      }
    }
  }
  let kept = (store.get)(device_key) catch { e => raise MeshError(code="host", message=text_of(e), cause="") }
  let secret = match kept {
    Some(secret) if secret.length() == 32 => secret
    _ => {
      let secret = @shell.random(32)
      (store.set)(device_key, secret) catch {
        e => raise MeshError(code="host", message=text_of(e), cause="")
      }
      secret
    }
  }
  let relays = Json::array(options.relays.map(relay => Json::string(relay)))
  let bound = shell.call(
    "iroh.bind",
    { "relayUrls": relays, "relayOnly": Json::boolean(options.relay_only), "lookup": false },
    bytes=secret,
  ) catch {
    e => raise under("bind_failed", e)
  }
  guard bound.json is { "id": endpoint, .. } else { raise failed("bind_failed") }
  let id = match (shell.ask("iroh.endpointId", { "id": endpoint }) catch { e => raise under("bind_failed", e) }) {
    String(id) => id
    _ => raise failed("bind_failed")
  }
  { shell, options, endpoint, id, scope: shell.rt.scope(), links: Map([]), closed: false }
}

///|
/// This device's endpoint id (64 hex): the public half of its key.
pub fn Mesh::device_id(self : Mesh) -> String {
  self.id
}

///|
fn is_id(id : String) -> Bool {
  guard id.length() == 64 else { return false }
  for c in id {
    if !((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) {
      return false
    }
  }
  true
}

///|
/// The link to `peer` (its endpoint id), open: the one there is, the one being opened, or one opened now, with the
/// credential `credentials` gives (asked with this device's id, and whether for a new one: the last was refused). It is
/// handed out as its credential is sent (`Link::admitted` waits for the peer's answer). Fails as the peer could not be
/// reached.
pub async fn Mesh::link(self : Mesh, peer : String, credentials : async (String, Bool) -> Presented) -> Link {
  let mut fresh = false
  if self.links.get(peer) is Some(existing) {
    match existing.result {
      None => {
        // Being opened: as that dial ends, unless it gave up for no answer before this waited `connect_timeout_ms` on
        // it: begun earlier, that says nothing of now, and the peer is dialled again.
        let asked = self.shell.rt.now()
        let joined = attempt(() => existing.done.wait())
        match joined {
          Did(link) => return link
          Fell(e) => {
            let unanswered = existing.result is Some(Failed(_, true))
            if !unanswered || self.shell.rt.now() - asked >= connect_timeout_ms.to_int64() {
              raise e
            }
            return self.link(peer, credentials)
          }
        }
      }
      Some(Open(link)) => {
        if link.usable() {
          return link
        }
        // (refused for something its user named, the credential was fine: no new one asked of its source)
        fresh = link.refused is Some(_) && !link.control.named
      }
      Some(Failed(e, _)) => fresh = code_of(e) == "credential_refused"
    }
  }
  guard !self.closed else { raise failed("closed") }
  let opening : Opening = { done: @effect.Deferred::new(), result: None }
  self.links[peer] = opening
  ignore(
    self.scope.fork(name="mesh open", () => {
      let opened = attempt(() => self.open(peer, credentials, fresh))
      match opened {
        Did(link) => {
          opening.result = Some(Open(link))
          self.adopt(peer, opening, link)
          ignore(opening.done.succeed(link))
        }
        Fell(OpeningTimeout(_)) => {
          let e = failed("no_answer")
          opening.result = Some(Failed(e, true))
          ignore(opening.done.fail(e))
        }
        Fell(e) => {
          opening.result = Some(Failed(e, false))
          ignore(opening.done.fail(e))
        }
      }
    }),
  )
  opening.done.wait()
}

///|
/// Whether the endpoint is on one of its relays (at once with none).
fn Mesh::on_a_relay(self : Mesh) -> Bool {
  let said = self.shell.ask("iroh.relayStatus", { "id": self.endpoint }) catch { _ => return true }
  guard said is Array(relays) else { return true }
  if relays.length() == 0 {
    return true
  }
  for relay in relays {
    if relay is { "connected": True, .. } {
      return true
    }
  }
  false
}

///|
/// Connects, presents the first credential, and starts renewing it. The credential is asked for while the connection
/// is being made; the link is handed out as soon as the credential is sent (the peer reads it before any request
/// stream). A refusal closes the connection; the requests on it fail, and the next `link` starts over.
async fn Mesh::open(self : Mesh, peer : String, credentials : async (String, Bool) -> Presented, fresh : Bool) -> Link {
  guard is_id(peer) else {
    raise MeshError(code="invalid_params", message=say("bad_station_id", args={ "id": peer }), cause="")
  }
  let shell = self.shell
  // The handshake, a fiber of the mesh's and not of this opening: the shell finishes it whoever waits, so its answer
  // is taken whatever became of the opening, and the connection closed if the opening has ended. Given up with the
  // opening (`give_up`): left going, it sends to every way to the peer until the connection's idle timeout.
  let abandoned = Ref(false)
  let call : Ref[Int64?] = Ref(None)
  let connection : Ref[Json?] = Ref(None)
  let dialled : @effect.Deferred[Json] = @effect.Deferred::new()
  let addr : Json = { "id": Json::string(peer), "relays": Json::array(self.options.relays.map(relay => Json::string(relay))) }
  ignore(
    self.scope.fork(name="mesh dial", () => {
      let made = attempt(() => shell.call(
        "iroh.connect",
        { "id": self.endpoint, "addr": addr },
        bytes=@utf8.encode(self.options.alpn),
        called=id => call.val = Some(id),
      ))
      call.val = None
      match made {
        Did({ json: { "id": conn, .. }, .. }) =>
          if abandoned.val {
            shell.tell("conn.close", { "id": conn, "code": 0, "reason": "opening ended" })
          } else {
            connection.val = Some(conn)
            ignore(dialled.succeed(conn))
          }
        Did(_) => ignore(dialled.fail(failed("unreached")))
        Fell(e) => ignore(dialled.fail(unreached(e)))
      }
    }),
  )
  let opened = Ref(false)
  defer {
    if !opened.val {
      abandoned.val = true
      if call.val is Some(id) {
        shell.give_up(id)
      }
      if connection.val is Some(conn) {
        shell.tell("conn.close", { "id": conn, "code": 0, "reason": "opening ended" })
      }
    }
  }
  let link = @effect.race_first(
    () => {
      let presented = credentials(self.id, fresh)
      let conn = dialled.wait()
      let first = shell.call("conn.openBi", { "id": conn }) catch { e => raise unreached(e) }
      guard first.json is { "id": stream, .. } else { raise failed("unreached") }
      let stream : Stream = { shell, id: stream }
      let control : Control = {
        stream,
        lines: { stream, carry: @wire.Carry::new() },
        says: self.options.says,
        refusal: self.options.refusal,
        named: false,
      }
      control.send(presented.credential, also?=presented.also)
      let link : Link = {
        peer,
        shell,
        conn,
        control,
        lock: @effect.Semaphore::new(1),
        credentials,
        credential: presented.credential,
        renewal_failed: false,
        refused: None,
        answer: None,
        answered: @effect.Deferred::new(),
        gone: @effect.Deferred::new(),
        came: 0,
        missed: 0,
        pinging: false,
        rx: 0,
      }
      link
    },
    // The opening's time: counted from when the endpoint is on a relay (getting onto one takes several round trips to
    // it), and it covers the whole opening, a handshake made whose credential or first stream never goes too.
    () => {
      for waited = 0; waited < onto_max_ms && !self.on_a_relay(); waited = waited + onto_recheck_ms {
        @effect.sleep(onto_recheck_ms)
      }
      @effect.sleep(connect_timeout_ms)
      raise OpeningTimeout(connection.val is Some(_))
    },
  )
  opened.val = true
  // Its end, waited for once: why it ended.
  ignore(
    self.scope.fork(name="mesh closed", () => {
      let said = attempt(() => shell.call("conn.closed", { "id": link.conn }))
      let closed = match said {
        Did(answer) => closed_of(answer.json).unwrap_or({ kind: "other", reason: "" })
        Fell(e) => { kind: "other", reason: text_of(e) }
      }
      ignore(link.gone.succeed(closed))
    }),
  )
  // The peer's answer to the first credential, while requests already go: a refusal closes the link.
  ignore(
    self.scope.fork(name="mesh answer", () => {
      let answer = attempt(() => link.lock.with_permit(() => link.control.answer()))
      match answer {
        Did(answer) => link.answer = Some(answer)
        Fell(e) => {
          link.renewal_failed = true
          link.refused = Some(e)
          shell.tell("conn.close", { "id": link.conn, "code": 0, "reason": "credential refused" })
        }
      }
      ignore(link.answered.succeed(()))
    }),
  )
  ignore(self.scope.fork(name="mesh renew", () => self.renew(link)))
  link
}

///|
/// Presents a fresh credential every `renew_ms` until the link closes; one not had or refused leaves the link to run
/// out, and the next `link` opens another.
async fn Mesh::renew(self : Mesh, link : Link) -> Unit {
  while true {
    let closed = @effect.race_first(
      () => {
        @effect.sleep(renew_ms, later=true)
        false
      },
      () => {
        ignore(link.closed())
        true
      },
    )
    if closed {
      return
    }
    let renewed = attempt(() => {
      let presented = (link.credentials)(self.id, false)
      ignore(link.exchange(presented.credential))
      link.credential = presented.credential
    })
    if renewed is Fell(_) {
      link.renewal_failed = true
      return
    }
  }
}

///|
/// A link just opened is the peer's, pinged from now on; one opened for a mesh closed meanwhile, or a peer let go of,
/// is closed.
fn Mesh::adopt(self : Mesh, peer : String, opening : Opening, link : Link) -> Unit {
  if self.closed || !(self.links.get(peer) is Some(current) && physical_equal(current, opening)) {
    link.close()
    return
  }
  ignore(self.scope.fork(name="mesh pings", () => self.steer(peer, opening, link)))
}

///|
/// The link's pings, every `tick_ms` while it is its peer's and usable: how a peer gone from under it is found. One
/// that missed `dead_pings` in a row is let go and its peer dialled anew.
async fn Mesh::steer(self : Mesh, peer : String, opening : Opening, link : Link) -> Unit {
  while true {
    @effect.sleep(tick_ms, later=true)
    guard !self.closed && self.links.get(peer) is Some(current) && physical_equal(current, opening) && link.usable() else {
      return
    }
    self.ping(link)
    if link.missed >= dead_pings {
      self.links.remove(peer)
      link.close()
      ignore(self.scope.fork(name="mesh again", () => ignore(attempt(() => self.link(peer, link.credentials)))))
      return
    }
  }
}

///|
/// One ping: the credential presented again, waited for `ping_timeout_ms`. One not answered by then is missed, unless
/// the link's replies brought something meanwhile (it waits behind them on the line); its exchange goes on, and no
/// other is sent over it until it ends.
async fn Mesh::ping(self : Mesh, link : Link) -> Unit {
  if link.pinging {
    if !link.brought() {
      link.missed += 1
    }
    return
  }
  link.pinging = true
  ignore(link.brought())
  let answered : @effect.Deferred[Bool] = @effect.Deferred::new()
  let late = Ref(false)
  ignore(
    self.scope.fork(name="mesh ping", () => {
      let exchanged = attempt(() => link.exchange(link.credential))
      link.pinging = false
      if late.val && exchanged is Did(_) {
        link.missed = 0
      }
      ignore(answered.succeed(exchanged is Did(_)))
    }),
  )
  match @effect.timeout(ping_timeout_ms, () => answered.wait()) {
    Some(true) => link.missed = 0
    _ => {
      late.val = true
      if !link.brought() {
        link.missed += 1
      }
    }
  }
}

///|
/// Closes the links, then the endpoint: nothing is asked of it after.
pub async fn Mesh::close(self : Mesh) -> Unit {
  self.closed = true
  for _, opening in self.links {
    if opening.result is Some(Open(link)) {
      ignore(attempt(() => self.shell.call("conn.close", { "id": link.conn, "code": 0, "reason": "closed" })))
    }
  }
  self.links.clear()
  self.scope.close()
  ignore(attempt(() => self.shell.call("iroh.close", { "id": self.endpoint })))
}

///|
/// The wait between tries of something that failed (a link that went, a stream that ended): `first` ms, twice as long
/// each time, `most` at most; back to `first` once it went well (`reset`).
pub struct Backoff {
  first : Int
  most : Int
  priv mut wait : Int
}

///|
pub fn Backoff::new(first? : Int = 1_000, most? : Int = 30_000) -> Backoff {
  { first, most, wait: first }
}

///|
pub fn Backoff::reset(self : Backoff) -> Unit {
  self.wait = self.first
}

///|
/// Waits, and the next wait is twice as long.
pub async fn Backoff::pause(self : Backoff) -> Unit {
  @effect.sleep(self.wait)
  self.wait = if self.wait * 2 > self.most { self.most } else { self.wait * 2 }
}

///|
/// How something tried ended: what it gave, or what it failed with.
priv enum Tried[X] {
  Did(X)
  Fell(Error)
}

///|
/// What `f` gave, or what it failed with (a fiber's interruption is neither: it goes on out).
async fn[X] attempt(f : async () -> X) -> Tried[X] {
  try {
    Did(f())
  } catch {
    e => Fell(e)
  }
}
