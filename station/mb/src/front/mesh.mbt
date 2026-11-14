// The station's iroh endpoint, kept here for the station's Node (station/src/mesh/front.ts) across its handovers: one
// endpoint bound once, the connections and streams on it the Node's that took or made them, the bytes of each stream
// carried by the shell between iroh and a socket of the Node's (`istream.pipe`), none of them through this program.
//
// The Node asks on a Unix socket of this program's (`mesh`'s `path`), a JSON object a line both ways: `{id, op, …}`
// asked, `{id, ok}` or `{id, error}` answered, each as it is done (an `accept` waits for a connection, a `closed` for
// its end). It first says `bind` with where its own Unix socket is (`streams`): each stream it is given comes there,
// a socket of its own whose first 17 bytes say the connection's id and the stream's (8 each, big-endian) and whether
// the Node asked for it (1) or the other end opened it (0), its frames after (client/shell's `istream.pipe`). Those the
// other end opens are taken here as they come and given at once, no ask of the Node's between them. Connections coming go to the Node that bound last (the one taking over, in a handover), or wait for
// one; those a Node has are closed when it closes the endpoint or its socket ends (it stopped, or died).

///|
/// A Node asking (one of its sockets to this program).
priv struct Client {
  conn : Conn
  /// Its order of binding: the last to bind is given what comes.
  mut bound : Int
  /// Where its streams go (its Unix socket).
  mut streams : String
  /// What came for it and it has not taken yet.
  coming : @effect.Queue[Json]
  /// The connections it has, by their ids at the shell.
  conns : Map[String, Json]
  /// The calls it can give up (`giveUp`), by its ids: the shell's ids of them.
  calls : Map[String, Int64]
  mut gone : Bool
}

///|
/// The endpoint and the Nodes asking.
priv struct Mesh {
  host : @host.Host
  /// The endpoint at the shell, and what it was bound with (a `bind` alike is given it; another binds anew).
  mut endpoint : Json?
  mut options : String
  mut said : Json
  /// What came while no Node had bound.
  waiting : Array[Json]
  clients : Array[Client]
  mut binds : Int
}

///|
/// At most this many connections wait for a Node to bind (each a device that dialed meanwhile); the oldest closed.
let waiting_most : Int = 256

///|
/// Serves the mesh on the Unix socket at `path`, until it fails.
pub async fn mesh(host : @host.Host, path : String) -> Unit {
  let (said, _) = host.shell("unix.listen", { "path": Json::string(path) })
  guard said is { "id": listening, .. } else { fail("the shell gave no listening socket") }
  let mesh : Mesh = { host, endpoint: None, options: "", said: Json::null(), waiting: [], clients: [], binds: 0 }
  // `streams`: how it hands Node the streams the other end opens (front.rs `STREAMS`): 2, each with its index.
  host.say(({ "listening": Json::string(path), "streams": 2 } : Json).stringify())
  // Its stdin is the launcher's: ended (the launcher gone, or stopping the station), the endpoint goes with it.
  ignore(
    host.rt.fork(name="mesh parent", () => {
      while host.line() is Some(_) {
        ()
      }
      @host.exit(0)
    }),
  )
  while true {
    let accepted = try { Ok(host.shell("tcp.accept", { "id": listening })) } catch { e => Err(e) }
    guard accepted is Ok(({ "id": id, .. }, _)) else {
      if accepted is Err(e) {
        @host.note("mesh: accept failed: \{message(e)}")
        @effect.sleep(100)
      }
      continue
    }
    let client : Client = {
      conn: { host, id },
      bound: 0,
      streams: "",
      coming: @effect.Queue::unbounded(),
      conns: Map([]),
      calls: Map([]),
      gone: false,
    }
    mesh.clients.push(client)
    ignore(host.rt.fork(name="mesh client", () => mesh.serve(client)))
  }
}

///|
/// A Node's asks, each answered as it is done, till its socket ends.
async fn Mesh::serve(self : Mesh, client : Client) -> Unit {
  let lines = @wire.Lines::new()
  while true {
    let read = try { Ok(self.host.shell("tcp.read", { "id": client.conn.id })) } catch { e => Err(e) }
    guard read is Ok((said, Some(bytes))) && !(said is { "end": true, .. }) else { break }
    for line in lines.push(bytes[:]) {
      let asked = @json.parse(line) catch { _ => continue }
      ignore(self.host.rt.fork(name="mesh ask", () => self.answer(client, asked)))
    }
  }
  self.part(client)
  client.conn.close()
}

///|
/// A Node no longer asking (its socket ended, or it closed the endpoint): its connections closed, what came for it and it
/// did not take given to another.
async fn Mesh::part(self : Mesh, client : Client) -> Unit {
  if client.gone {
    return
  }
  client.gone = true
  client.bound = 0
  let left = []
  while client.coming.try_take() is Some(c) {
    left.push(c)
  }
  client.coming.shutdown()
  for _, conn in client.conns {
    ignore(self.host.shell("conn.close", { "id": conn, "code": 0, "reason": "station stopping" })) catch {
      _ => ()
    }
  }
  client.conns.clear()
  let at = self.clients.search_by(c => physical_equal(c, client))
  if at is Some(i) {
    ignore(self.clients.remove(i))
  }
  for c in left {
    self.give(c)
  }
}

///|
/// What came, given to the Node that bound last, or kept till one does.
fn Mesh::give(self : Mesh, conn : Json) -> Unit {
  let mut to : Client? = None
  for c in self.clients {
    if !c.gone && c.bound > 0 && (to is None || c.bound > to.unwrap().bound) {
      to = Some(c)
    }
  }
  match to {
    Some(c) => {
      if conn is { "conn": id, .. } {
        c.conns[id.stringify()] = id
        self.taking(c, id)
      }
      ignore(c.coming.try_offer(conn))
    }
    None => {
      if self.waiting.length() >= waiting_most {
        if self.waiting.remove(0) is { "conn": id, .. } {
          ignore(self.host.rt.fork(name="mesh drop", () => {
            ignore(self.host.shell("conn.close", { "id": id, "code": 0, "reason": "station starting" })) catch {
              _ => ()
            }
          }))
        }
      }
      self.waiting.push(conn)
    }
  }
}

///|
/// What is known of a connection at once: its other end, its protocol, how it runs and what went over it.
fn Mesh::seen(self : Mesh, id : Json) -> Json raise {
  {
    "conn": id,
    "remote": self.host.shell_sync("conn.remoteId", { "id": id }),
    "alpn": self.host.shell_sync("conn.alpn", { "id": id }),
    "via": self.host.shell_sync("conn.via", { "id": id }),
    "paths": self.host.shell_sync("conn.paths", { "id": id }),
    "stats": self.host.shell_sync("conn.stats", { "id": id }),
  }
}

///|
/// The connections coming to `endpoint`, each given a Node, till it closes.
async fn Mesh::accepting(self : Mesh, endpoint : Json) -> Unit {
  while true {
    let (got, _) = self.host.shell("iroh.accept", { "id": endpoint })
    guard got is { "id": id, .. } else { return }
    let seen = self.seen(id) catch {
      _ => continue
    }
    self.give(seen)
  }
}

///|
/// The endpoint bound as `options` say (`key` its secret key's hex): the one bound already where they are the same.
async fn Mesh::bind(self : Mesh, options : Json, key : Bytes) -> Json {
  let text = options.stringify() + "|" + hex(key)
  if self.endpoint is Some(_) && self.options == text {
    return self.said
  }
  if self.endpoint is Some(old) {
    // (another key or other relays: the Node that binds says what the station is now)
    self.endpoint = None
    ignore(self.host.shell("iroh.close", { "id": old })) catch {
      _ => ()
    }
  }
  let (bound, _) = self.host.shell("iroh.bind", options, bytes=key)
  guard bound is { "id": endpoint, .. } else { fail("the shell bound no endpoint") }
  self.endpoint = Some(endpoint)
  self.options = text
  self.said = {
    "id": self.host.shell_sync("iroh.endpointId", { "id": endpoint }),
    "sockets": self.host.shell_sync("iroh.sockets", { "id": endpoint }),
  }
  ignore(self.host.rt.fork(name="mesh accept", () => self.accepting(endpoint)))
  self.said
}

///|
/// The streams the other end of connection `conn` opens, each given to `client` as it comes by the shell itself
/// (`conn.hand`: its head the ids, a 2 and the stream's index), till the connection is gone.
fn Mesh::taking(self : Mesh, client : Client, conn : Json) -> Unit {
  ignore(
    self.host.rt.fork(name="mesh streams", () => {
      ignore(self.host.shell("conn.hand", { "id": conn, "path": Json::string(client.streams) })) catch {
        _ => ()
      }
      client.conns.remove(conn.stringify())
    }),
  )
}

///|
/// A stream this program opened (`id`, on connection `conn`) given to `client`: a socket of its own to it, the ids and a
/// 1 first, carried from then on by the shell (`istream.hand`). Told once it is under way.
fn Mesh::hand(self : Mesh, client : Client, conn : Json, id : Json) -> Unit {
  let head = FixedArray::make(17, b'\x00')
  for k, v in [conn, id] {
    let n = match v {
      Number(n, ..) => n.to_int64()
      _ => 0L
    }
    for i = 0; i < 8; i = i + 1 {
      head[8 * k + i] = ((n >> (8 * (7 - i))) & 0xFFL).to_byte()
    }
  }
  head[16] = b'\x01'
  ignore(
    self.host.rt.fork(name="mesh stream", () => {
      ignore(
        self.host.shell("istream.hand", { "id": id, "path": Json::string(client.streams) }, bytes=Bytes::from_array(head)),
      ) catch {
        _ => ()
      }
    }),
  )
}

///|
/// The endpoint, or a refusal while none is bound.
fn Mesh::bound(self : Mesh) -> Json raise {
  match self.endpoint {
    Some(e) => e
    None => fail("no endpoint bound")
  }
}

///|
/// One ask answered.
async fn Mesh::answer(self : Mesh, client : Client, asked : Json) -> Unit {
  guard asked is { "id": ask, "op": String(op), .. } else { return }
  let arg = (k : String) => match asked {
    Object(m) => m.get(k).unwrap_or(Json::null())
    _ => Json::null()
  }
  let done = try {
    Ok(self.act(client, ask, op, arg))
  } catch {
    @wire.ShellError(m) => Err(m)
    e => Err(e.to_string())
  }
  client.calls.remove(ask.stringify())
  let line : Json = match done {
    Ok(ok) => { "id": ask, "ok": ok }
    Err(m) => { "id": ask, "error": Json::string(m) }
  }
  // (a Node that closed the endpoint is told it is closed, then nothing more)
  if !client.gone || op == "close" {
    ignore(self.host.shell("tcp.write", { "id": client.conn.id }, bytes=@utf8.encode(line.stringify() + "\n"))) catch {
      _ => ()
    }
  }
}

///|
async fn Mesh::act(self : Mesh, client : Client, ask : Json, op : String, arg : (String) -> Json) -> Json {
  match op {
    "bind" => {
      guard arg("streams") is String(streams) else { fail("no streams") }
      guard arg("key") is String(key) else { fail("no key") }
      let options = arg("options")
      guard options is Object(_) else { fail("no options") }
      let said = self.bind(options, unhex(key))
      client.streams = streams
      self.binds += 1
      client.bound = self.binds
      let waited = self.waiting.copy()
      self.waiting.clear()
      for c in waited {
        self.give(c)
      }
      said
    }
    "accept" => {
      let next = try { Ok(client.coming.take()) } catch { e => Err(e) }
      match next {
        Ok(conn) => conn
        Err(_) => { "end": true }
      }
    }
    "close" => {
      self.part(client)
      Json::null()
    }
    "connect" => {
      guard arg("alpn") is String(alpn) else { fail("no alpn") }
      let endpoint = self.bound()
      let (made, _) = self.host.shell(
        "iroh.connect",
        { "id": endpoint, "addr": arg("addr"), "additional": arg("additional") },
        bytes=unhex(alpn),
        called=id => client.calls[ask.stringify()] = id,
      )
      guard made is { "id": id, .. } else { fail("no connection") }
      if client.gone {
        ignore(self.host.shell("conn.close", { "id": id, "code": 0, "reason": "station stopping" }))
        fail("the endpoint is closed")
      }
      client.conns[id.stringify()] = id
      self.taking(client, id)
      self.seen(id)
    }
    "giveUp" => {
      match client.calls.get(arg("of").stringify()) {
        Some(call) => ignore(self.host.shell_sync("fetch.cancel", { "id": Json::number(call.to_double()) }))
        None => ()
      }
      Json::null()
    }
    "openBi" | "openUni" => {
      let conn = arg("conn")
      let (got, _) = self.host.shell("conn." + op, { "id": conn })
      match got {
        { "id": id, .. } => {
          self.hand(client, conn, id)
          { "stream": id }
        }
        _ => { "end": true }
      }
    }
    "stopped" => self.host.shell("istream.stopped", { "id": arg("stream") }).0
    "reset" => self.host.shell("istream.reset", { "id": arg("stream"), "code": arg("code") }).0
    "conn.close" => {
      let conn = arg("conn")
      client.conns.remove(conn.stringify())
      self.host.shell("conn.close", { "id": conn, "code": arg("code"), "reason": arg("reason") }).0
    }
    "conn.closed" => self.host.shell("conn.closed", { "id": arg("conn") }).0
    "conn.answers" => self.host.shell("conn.answers", { "id": arg("conn"), "within": arg("within") }).0
    "conn.seen" => self.seen(arg("conn"))
    "online" | "insertRelay" | "removeRelay" | "publicRelays" | "keep" | "setCongestion" | "holdIncoming" | "setRelayEntries" | "networkChange" => {
      let args = match asked_args(arg) {
        Object(m) => {
          m["id"] = self.bound()
          Json::object(m)
        }
        _ => { "id": self.bound() }
      }
      self.host.shell("iroh." + op, args).0
    }
    "addAddr" => self.host.shell_sync("iroh.addAddr", { "id": self.bound(), "addr": arg("addr") })
    "relayStatus" => self.host.shell_sync("iroh.relayStatus", { "id": self.bound() })
    _ => fail("no operation \{op}")
  }
}

///|
/// An ask's own arguments (`args`), as the shell takes them.
fn asked_args(arg : (String) -> Json) -> Json {
  match arg("args") {
    Object(m) => Json::object(m.copy())
    _ => Json::object(Map([]))
  }
}

///|
fn hex(b : Bytes) -> String {
  let digits = "0123456789abcdef"
  let out = StringBuilder::new()
  for x in b {
    out.write_char(digits[x.to_int() >> 4].unsafe_to_char())
    out.write_char(digits[x.to_int() & 15].unsafe_to_char())
  }
  out.to_string()
}

///|
fn unhex(s : String) -> Bytes {
  let nibble = (c : Int) => if c >= '0'.to_int() && c <= '9'.to_int() {
    c - '0'.to_int()
  } else if c >= 'a'.to_int() && c <= 'f'.to_int() {
    c - 'a'.to_int() + 10
  } else if c >= 'A'.to_int() && c <= 'F'.to_int() {
    c - 'A'.to_int() + 10
  } else {
    0
  }
  let out = FixedArray::make(s.length() / 2, b'\x00')
  for i = 0; i < out.length(); i = i + 1 {
    out[i] = (nibble(s[2 * i].to_int()) * 16 + nibble(s[2 * i + 1].to_int())).to_byte()
  }
  Bytes::from_array(out)
}
