// The station's entrances in MoonBit (station/AGENTS.md: the entrance moves to station/mb's program, what it does not
// answer itself carried to Node). So far: a listening socket served by carrying each connection, byte for byte both
// ways, to a port of this machine (`forward`), as the Windows launcher's entrance does for Node (native/launcher's
// proxy.rs): the shell carries its bytes (`tcp.pipe`), none of them through this program.

///|
/// A socket of the shell's (`tcp.*`).
struct Conn {
  host : @host.Host
  id : Json
}

///|
async fn Conn::close(self : Conn) -> Unit {
  ignore(self.host.shell("tcp.close", { "id": self.id })) catch {
    _ => ()
  }
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
          @host.note("forward: 127.0.0.1:\{to} not reached: \{match opened { Err(e) => message(e); _ => "no socket" }}")
          client.close()
          return
        }
        // (carried by the shell itself, both ways: nothing of it passes through this program)
        ignore(host.shell("tcp.pipe", { "ids": [client.id, sid] })) catch {
          e => @host.note("forward: a connection failed: \{message(e)}")
        }
      }),
    )
  }
}

///|
fn message(e : Error) -> String {
  match e {
    @wire.ShellError(m) => m
    e => e.to_string()
  }
}
