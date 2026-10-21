// What the core does outside itself goes through services it is given (Effect's
// R, as an explicit struct): the network, files, the host's callbacks. Each has
// a simulated version on the runtime's virtual clock, whose random choices
// (latency, jitter, loss, the order things arrive in) come from the runtime's
// seed: a test runs the whole program, and a seed replays it exactly.

///|
/// Something outside failed (a file, a host call).
pub suberror IoError {
  IoError(String)
} derive(Show)

///|
/// A message between two endpoints.
pub(all) struct Packet {
  from : String
  to : String
  body : String
} derive(Show, Eq)

///|
/// An endpoint of the network, as the core sees it. Real (a host's sockets,
/// iroh over its C ABI: the host's callbacks hand what arrives to `deliver`)
/// or simulated (`SimNet::endpoint`): the core cannot tell.
pub(all) struct Net {
  name : String
  /// Sends `body` to the endpoint `to`; it may arrive later, or not at all.
  send : (String, String) -> Unit
  /// The next packet that arrived, waiting for one.
  recv : async () -> Packet
}

///|
/// A network on the runtime's virtual clock: each packet arrives after
/// `latency` plus a jitter drawn from the seed (so two packets can arrive in
/// either order), or is lost with probability `loss`.
pub struct SimNet {
  priv rt : Runtime
  priv inboxes : Map[String, Queue[Packet]]
  priv mut latency : Int
  priv mut jitter : Int
  priv mut loss : Double
  /// Packets so far, as they arrived (or were lost), with the time.
  log : Array[String]
}

///|
pub fn SimNet::new(
  rt : Runtime,
  latency? : Int = 20,
  jitter? : Int = 0,
  loss? : Double = 0.0,
) -> SimNet {
  { rt, inboxes: {}, latency, jitter, loss, log: [] }
}

///|
/// Changes how it behaves from now on (a network getting worse, mid-test).
pub fn SimNet::set(
  self : SimNet,
  latency? : Int,
  jitter? : Int,
  loss? : Double,
) -> Unit {
  if latency is Some(x) {
    self.latency = x
  }
  if jitter is Some(x) {
    self.jitter = x
  }
  if loss is Some(x) {
    self.loss = x
  }
}

///|
fn SimNet::inbox(self : SimNet, name : String) -> Queue[Packet] {
  match self.inboxes.get(name) {
    Some(q) => q
    None => {
      let q = Queue::unbounded()
      self.inboxes.set(name, q)
      q
    }
  }
}

///|
fn SimNet::send(self : SimNet, p : Packet) -> Unit {
  let rt = self.rt
  if self.loss > 0.0 && rt.rng.chance(self.loss) {
    self.log.push("\{rt.now()} lost \{p.from}->\{p.to} \{p.body}")
    return
  }
  let delay = self.latency + rt.rng.between(0, self.jitter)
  rt.after(delay, () => {
    self.log.push("\{rt.now()} \{p.from}->\{p.to} \{p.body}")
    ignore(self.inbox(p.to).try_offer(p))
  })
}

///|
/// The endpoint called `name`.
pub fn SimNet::endpoint(self : SimNet, name : String) -> Net {
  let inbox = self.inbox(name)
  {
    name,
    send: (to, body) => self.send({ from: name, to, body }),
    recv: () => inbox.take(),
  }
}

///|
/// The device's files, as the core sees them.
pub(all) struct Files {
  /// The file's bytes; None when there is none.
  read : async (String) -> Bytes?
  write : async (String, Bytes) -> Unit
}

///|
/// Files in memory, each read and write taking `latency` (plus a seeded
/// jitter) on the virtual clock; `fail_writes` makes writes fail (a full disk).
pub struct SimFiles {
  priv rt : Runtime
  data : Map[String, Bytes]
  priv latency : Int
  priv jitter : Int
  priv mut fail_writes : Bool
}

///|
/// From now on writes fail (true) or work again (false).
pub fn SimFiles::fail_writes(self : SimFiles, on : Bool) -> Unit {
  self.fail_writes = on
}

///|
pub fn SimFiles::new(rt : Runtime, latency? : Int = 1, jitter? : Int = 0) -> SimFiles {
  { rt, data: {}, latency, jitter, fail_writes: false }
}

///|
pub fn SimFiles::files(self : SimFiles) -> Files {
  let wait = async fn() {
    sleep(self.latency + self.rt.rng.between(0, self.jitter))
  }
  {
    read: path => {
      wait()
      self.data.get(path)
    },
    write: (path, bytes) => {
      wait()
      if self.fail_writes {
        raise IoError("no space left writing \{path}")
      }
      self.data.set(path, bytes)
    },
  }
}

///|
/// Waits for a host operation that answers by callback (a fetch, a socket
/// opening, a dialog): `start` begins it and is given `done`, for the host's
/// callback to call with the answer, on the host's thread. The runtime is told
/// (`on_wake`) and the waiting fiber goes on at the next `tick`. Interrupted
/// before the answer, `cancel` tells the host to stop.
pub async fn[X] host_call(
  start : ((Result[X, Error]) -> Unit) -> Unit,
  cancel? : () -> Unit = () => (),
) -> X {
  let d : Deferred[X] = Deferred::new()
  start(r => match r {
    Ok(x) => ignore(d.succeed(x))
    Err(e) => ignore(d.fail(e))
  })
  defer {
    if !d.is_done() {
      cancel()
    }
  }
  d.wait()
}
