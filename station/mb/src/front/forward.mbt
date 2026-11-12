// The station's entrances in MoonBit (station/AGENTS.md: the entrance moves to station/mb's program, what it does not
// answer itself carried to Node). So far: a listening socket served by carrying each connection, byte for byte both
// ways, to a port of this machine (`forward`), as the Windows launcher's entrance does for Node (native/launcher's
// proxy.rs).

///|
/// A socket of the shell's (`tcp.*`): read, written, ended, let go.
struct Conn {
  host : @host.Host
  id : Json
}

///|
/// What came next; none once the other end ended what it sends.
async fn Conn::read(self : Conn) -> Bytes? {
  let (said, carried) = self.host.shell("tcp.read", { "id": self.id })
  if said is { "end": True, .. } {
    return None
  }
  Some(carried.unwrap_or(b""))
}

///|
async fn Conn::write(self : Conn, bytes : Bytes) -> Unit {
  ignore(self.host.shell("tcp.write", { "id": self.id }, bytes~))
}

///|
/// Says the end of what this side sends (its other half still read).
async fn Conn::end(self : Conn) -> Unit {
  ignore(self.host.shell("tcp.end", { "id": self.id }))
}

///|
async fn Conn::close(self : Conn) -> Unit {
  ignore(self.host.shell("tcp.close", { "id": self.id })) catch {
    _ => ()
  }
}

///|
/// What `from` sends written to `to` until `from` ends it, then the end said to `to`.
async fn pump(from : Conn, to : Conn) -> Unit {
  while from.read() is Some(bytes) {
    to.write(bytes)
  }
  to.end()
}

///|
/// A listening socket: its id at the shell and its port.
pub struct Listening {
  id : Json
  port : Int
}

///|
/// A socket to serve: `fd` one handed down to this process (a launcher's), else one bound here on 127.0.0.1 at `port`
/// (0: any free one).
pub async fn listen(host : @host.Host, fd? : Int, port? : Int = 0) -> Listening {
  let args : Json = match fd {
    Some(fd) => { "fd": Json::number(fd.to_double()) }
    None => { "port": Json::number(port.to_double()) }
  }
  let (said, _) = host.shell("tcp.listen", args)
  guard said is { "id": id, "port": Number(p, ..), .. } else { fail("the shell gave no listening socket") }
  { id, port: p.to_int() }
}

///|
/// Each connection to `listening` carried to 127.0.0.1:`to`, both ways, each half ended as its side ends it; one whose
/// other end cannot be reached is closed. Runs till the listening socket fails.
pub async fn forward(host : @host.Host, listening : Listening, to : Int) -> Unit {
  while true {
    let (accepted, _) = host.shell("tcp.accept", { "id": listening.id })
    guard accepted is { "id": id, .. } else { continue }
    let client = { host, id }
    ignore(
      host.rt.fork(name="forward", () => {
        let opened = try { Ok(host.shell("tcp.open", { "port": Json::number(to.to_double()) })) } catch { e => Err(e) }
        guard opened is Ok(({ "id": sid, .. }, _)) else {
          @host.note("forward: 127.0.0.1:\{to} not reached: \{match opened { Err(@wire.ShellError(m)) => m; _ => "no socket" }}")
          client.close()
          return
        }
        let server = { host, id: sid }
        let back = host.rt.fork(name="forward back", () => pump(server, client) catch {
          e => @host.note("forward: the server's side failed: \{e}")
        })
        // (the client gone mid-way: the server told the end, so it ends its side too and the way back ends)
        pump(client, server) catch {
          e => {
            @host.note("forward: the client's side failed: \{e}")
            server.end() catch {
              _ => ()
            }
          }
        }
        back.join()
        client.close()
        server.close()
      }),
    )
  }
}
