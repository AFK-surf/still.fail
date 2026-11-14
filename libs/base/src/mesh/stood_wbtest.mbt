// A peer for the mesh's tests, with no network: a shell stood in (`@shell.Shell::stood_in`) that answers what the
// mesh asks of iroh as a shell does, by the same names with the same JSON, and holds back the calls a test answers
// itself, when it says: a dial (`iroh.connect`), a read (`istream.read`), a connection's end (`conn.closed`). On a
// runtime of the test's own clock (`@effect.Runtime::new`): nothing here waits on real time or on a thread.
//
// Most tests go a step at a time, each run as far as it goes by itself (`go`, `give`). What depends on which of two
// fibers comes first within one turn is set up without running (`start`, `answered`) and then run at once (`run`):
// the runtime takes what is ready in the order it was made ready.

///|
priv struct Stood {
  rt : @effect.Runtime
  shell : Ref[@shell.Shell?]
  /// Every op asked, in order, each with the handle it was asked of (`conn.close 2`; 0: none).
  said : Array[String]
  /// The calls held back for the test to answer: the call's id, its op, its handle.
  held : Array[(Int64, String, Int)]
  /// The handles given out so far: the last one's number.
  mut last : Int
  /// The connections closed here, and why (what `conn.closeReason` answers of one).
  ended : Map[Int, Json]
  /// The connections let go of: closed with `forget`, as the mesh does of one whose end it was told. A page's shell
  /// forgets such a one, and answers nothing of it after.
  forgot : Map[Int, Unit]
  /// An op held back besides (`conn.openBi`, for an opening that stops with its connection made); "": none.
  mut holding : String
  /// Whether a dial given up is given up at the shell (`fetch.cancel`); false: it goes on, and is answered when the
  /// test says, as a dial the shell could no longer stop.
  mut cancels : Bool
}

///|
/// The handle `args` names (`{"id": n}`), 0 where it names none.
fn handle_of(args : Json) -> Int {
  match args {
    { "id": Number(n, ..), .. } => n.to_int()
    _ => 0
  }
}

///|
fn Stood::new() -> Stood {
  let rt = @effect.Runtime::new()
  let stood : Stood = {
    rt,
    shell: Ref(None),
    said: [],
    held: [],
    last: 0,
    ended: Map([]),
    forgot: Map([]),
    holding: "",
    cancels: true,
  }
  let answer = (id : Int64, json : Json) => stood.shell.val.unwrap().answer(id, json)
  let shell = @shell.Shell::stood_in(
    rt,
    calls=(id, op, args, _) => {
      let handle = handle_of(args)
      stood.said.push("\{op} \{handle}")
      if op == stood.holding {
        stood.held.push((id, op, handle))
        return
      }
      match op {
        "iroh.bind" | "conn.openBi" =>
          if stood.ended.contains(handle) {
            stood.shell.val.unwrap().refuse(id, "connection closed: closed")
          } else {
            stood.last += 1
            answer(id, { "id": Json::number(stood.last.to_double()) })
          }
        "istream.write" | "istream.finish" | "istream.reset" | "iroh.close" => answer(id, {})
        "conn.close" => {
          if !stood.ended.contains(handle) {
            stood.ended[handle] = { "kind": "local", "reason": "closed" }
          }
          if args is { "forget": True, .. } {
            stood.forgot[handle] = ()
          }
          answer(id, {})
        }
        "iroh.connect" | "istream.read" | "conn.closed" => stood.held.push((id, op, handle))
        _ => stood.shell.val.unwrap().refuse(id, "the stood-in shell has no \{op}")
      }
    },
    asks=(op, args) => {
      let handle = handle_of(args)
      match op {
        "iroh.endpointId" => Json::string("ab".repeat(32))
        "iroh.relayStatus" | "conn.paths" => Json::array([])
        "conn.closeReason" => {
          if stood.forgot.contains(handle) {
            raise @shell.ShellError("no handle \{handle}")
          }
          stood.ended.get(handle).unwrap_or(Json::null())
        }
        "fetch.cancel" => {
          if !stood.cancels {
            return Json::boolean(false)
          }
          for i, call in stood.held {
            if call.0.to_int() == handle && call.1 == "iroh.connect" {
              ignore(stood.held.remove(i))
              stood.shell.val.unwrap().refuse(call.0, "cancelled")
              return Json::boolean(true)
            }
          }
          Json::boolean(false)
        }
        _ => raise @shell.ShellError("the stood-in shell has no \{op}")
      }
    },
    draws=n => Bytes::make(n, b'\x07'),
  )
  stood.shell.val = Some(shell)
  stood
}

///|
/// The oldest call of `op` held back, taken: its id and its handle. The test's mistake where none is held.
fn Stood::taken(self : Stood, op : String) -> (Int64, Int) raise {
  for i, call in self.held {
    if call.1 == op {
      ignore(self.held.remove(i))
      return (call.0, call.2)
    }
  }
  fail("the mesh asked no \{op} that is not answered yet: \{self.said.join(", ")}")
}

///|
/// The oldest `op` held back is answered `json` (and `bytes`), and the fibers it woke run.
fn Stood::give(self : Stood, op : String, json : Json, bytes? : Bytes) -> Unit raise {
  self.answered(op, json, bytes?)
  self.run()
}

///|
/// The oldest `op` held back is answered, and nothing runs yet: the fiber it woke is ready, behind what was before.
fn Stood::answered(self : Stood, op : String, json : Json, bytes? : Bytes) -> Unit raise {
  let (id, _) = self.taken(op)
  self.shell.val.unwrap().answer(id, json, bytes?)
}

///|
/// All that is ready runs, and what that makes ready, until nothing is.
fn Stood::run(self : Stood) -> Unit {
  ignore(self.rt.run_ready())
}

///|
/// `f` as a fiber of the test's runtime, ready and not yet run: it takes its first step behind what is ready now.
fn[X] Stood::start(self : Stood, f : async () -> X) -> @effect.Fiber[X] {
  self.rt.fork(f)
}

///|
/// The oldest `op` held back fails, in the shell's words, and the fibers it woke run.
fn Stood::refuse(self : Stood, op : String, why : String) -> Unit raise {
  let (id, _) = self.taken(op)
  self.shell.val.unwrap().refuse(id, why)
  ignore(self.rt.run_ready())
}

///|
/// The dial under way is answered: a connection, the next handle.
fn Stood::dialled(self : Stood) -> Unit raise {
  self.dial_answered()
  self.run()
}

///|
/// The same, and nothing runs yet.
fn Stood::dial_answered(self : Stood) -> Unit raise {
  self.last += 1
  self.answered("iroh.connect", { "id": Json::number(self.last.to_double()) })
}

///|
/// `f` as a fiber of the test's runtime, run as far as it goes by itself.
fn[X] Stood::go(self : Stood, f : async () -> X) -> @effect.Fiber[X] {
  let fiber = self.rt.fork(f)
  ignore(self.rt.run_ready())
  fiber
}

///|
/// How many times `said` (an op and its handle) was asked.
fn Stood::times(self : Stood, said : String) -> Int {
  self.said.filter(one => one == said).length()
}

///|
/// A mesh on the stood-in shell, its key kept already.
fn Stood::mesh(self : Stood) -> Mesh raise {
  let made = self.go(() => Mesh::make(
    self.shell.val.unwrap(),
    { get: _ => Some(Bytes::make(32, b'\x01')), set: (_, _) => () },
    { alpn: "test/1", relays: [], relay_only: true, says: None, refusal: None },
  ))
  guard made.poll() is Some(Succeeded(mesh)) else { fail("the mesh was not made: \{self.said.join(", ")}") }
  mesh
}

///|
/// The peer the tests dial.
let peer : String = "cd".repeat(32)

///|
/// A link to `peer`, open and let in: dialled, its credential sent, the peer's answer `{"ok":true}` read. The
/// endpoint is handle 1, the connection 2, its control stream 3.
fn Stood::link(self : Stood, mesh : Mesh) -> Link raise {
  let opening = self.go(() => mesh.link(peer, (_, _) => { credential: "c", also: None }))
  self.dialled()
  self.give("istream.read", {}, bytes=b"{\"ok\":true}\n")
  guard opening.poll() is Some(Succeeded(link)) else { fail("the link did not open: \{self.said.join(", ")}") }
  link
}

///|
/// What a fiber ended with, in a line: `ok`, the mesh's code and words of what it failed with, `interrupted`, or
/// `waiting` while it has not ended.
fn[X] ended_as(fiber : @effect.Fiber[X]) -> String {
  match fiber.poll() {
    None => "waiting"
    Some(Succeeded(_)) => "ok"
    Some(Failed(e)) => said(e)
    Some(Interrupted) => "interrupted"
  }
}
