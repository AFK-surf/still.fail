// The shell, for a program on mbui's `@effect`: what does a program's IO, iroh among it, asked by name, with JSON and
// bytes (its ops: `iroh.bind`, `iroh.connect`, `conn.openBi`, `istream.read`, `storage.get`…). This package is its
// binding and nothing else: the shell started, a call that answers later as a fiber's wait, a call that answers at
// once, a clock and random bytes. What the ops mean is their users' (the mesh).
//
// There are two shells behind it, one a target, and what is here is the same over both:
//   native   the Rust shell (client/shell, a static library the program is linked to), through its C interface
//            (shell_native.mbt, shell.c): its answers come from its own threads into one queue, which the program's
//            one thread takes between its runtime's turns (`Shell::pump`; `run` is that loop);
//   js       a page: iroh for the browser (client/iroh-wasm) and the page's own storage, clock and
//            randomness, asked by the same names with the same JSON (shell_js.mbt, which says what a page cannot do
//            of them); its answers come as the page's own events, each followed by a turn of the runtime.
// Each gives `Shell::start`, `now`, `random`, and the two below that a call goes out by (`send`, `asked`).
//
// And a third that is no target's, for a test of what stands on a shell (the mesh) with nothing linked and no page:
// `Shell::stood_in`, whose calls are given to the test, which answers them (`Shell::answer`, `Shell::refuse`). So a
// shell carries its own ways out (`calls`, `asks`, `draws`), and nothing above this package asks which it is.

///|
/// What the shell said went wrong, in its words.
pub(all) suberror ShellError {
  ShellError(String)
}

///|
/// What a call is answered: its JSON, and the bytes it carries where it carries any.
pub(all) struct Answer {
  json : Json
  bytes : Bytes?
}

///|
/// The shell, started: one a process (a page).
pub struct Shell {
  rt : @effect.Runtime
  /// The calls not answered yet, by their ids.
  priv waiting : Map[Int64, @effect.Deferred[Answer]]
  priv mut next : Int64
  /// How a call goes out, answered later as its id; how one is asked that answers at once; where random bytes come
  /// from. The target's (`Shell::of_target`), or a test's (`Shell::stood_in`).
  priv calls : (Int64, String, Json, Bytes?) -> Unit
  priv asks : (String, Json) -> Json raise ShellError
  priv draws : (Int) -> Bytes
}

///|
/// The target's shell for the fibers of `rt`, once it is started (`Shell::start`).
fn Shell::of_target(rt : @effect.Runtime) -> Shell {
  {
    rt,
    waiting: Map([]),
    next: 0L,
    calls: (id, op, args, bytes) => send(id, op, args.stringify(), bytes),
    asks: (op, args) => {
      let json : Json = @json.parse(asked(op, args.stringify())) catch {
        e => raise ShellError("the shell's answer is not JSON: \{e}")
      }
      match json {
        { "error": String(e), .. } => raise ShellError(e)
        { "value": v, .. } => v
        _ => Json::null()
      }
    },
    draws: random,
  }
}

///|
/// A shell that is a test's: every call asked of it is given to `calls` with its id, to be answered when the test
/// says (`Shell::answer`, `Shell::refuse`: at once, later or never), and what is asked at once is `asks`'s to answer
/// or to fail. Its random bytes are `draws`'s, so a key made on it is the same each run. Nothing of a target's shell
/// is reached through it: what is tested on it links no library and loads no page.
pub fn Shell::stood_in(
  rt : @effect.Runtime,
  calls~ : (Int64, String, Json, Bytes?) -> Unit,
  asks~ : (String, Json) -> Json raise ShellError,
  draws~ : (Int) -> Bytes,
) -> Shell {
  { rt, waiting: Map([]), next: 0L, calls, asks, draws }
}

///|
/// The call `id` of a test's shell is answered: its JSON and, where it carries any, its bytes.
pub fn Shell::answer(self : Shell, id : Int64, json : Json, bytes? : Bytes) -> Unit {
  guard self.waiting.get(id) is Some(done) else { return }
  self.waiting.remove(id)
  ignore(done.succeed({ json, bytes }))
}

///|
/// The call `id` of a test's shell failed, in the shell's words.
pub fn Shell::refuse(self : Shell, id : Int64, why : String) -> Unit {
  self.settle(id, 2, why, b"")
}

///|
/// `n` bytes of the shell's randomness (a key): the system's, under a target's shell.
pub fn Shell::random(self : Shell, n : Int) -> Bytes {
  (self.draws)(n)
}

///|
/// Asks the shell `op`, answered later: the fiber waits, the others go on. `bytes`: what the call carries beside its
/// JSON (a key, what is written). `called` is told the call's id as it is asked, for `give_up`. A fiber interrupted
/// while it waits lets the answer go: the shell still does what was asked.
pub async fn Shell::call(
  self : Shell,
  op : String,
  args : Json,
  bytes? : Bytes,
  called? : (Int64) -> Unit,
) -> Answer {
  self.next += 1L
  let id = self.next
  if called is Some(f) {
    f(id)
  }
  let done : @effect.Deferred[Answer] = @effect.Deferred::new()
  self.waiting[id] = done
  (self.calls)(id, op, args, bytes)
  done.wait()
}

///|
/// Asks the shell `op` and waits for no answer: what is done on the way out of something (a stream let go of, a
/// connection closed), from code that is no fiber's too.
pub fn Shell::tell(self : Shell, op : String, args : Json, bytes? : Bytes) -> Unit {
  self.next += 1L
  (self.calls)(self.next, op, args, bytes)
}

///|
/// Asks the shell what it answers at once, on this thread (what is known of a handle: `iroh.endpointId`, `conn.paths`).
pub fn Shell::ask(self : Shell, op : String, args : Json) -> Json raise ShellError {
  (self.asks)(op, args)
}

///|
/// Gives up the call `id` where the shell lets one be given up (a dial under way, `iroh.connect`): it is answered
/// "cancelled" then, and what it had begun is dropped.
pub fn Shell::give_up(self : Shell, id : Int64) -> Unit {
  ignore(self.ask("fetch.cancel", { "id": Json::number(id.to_double()) })) catch {
    _ => ()
  }
}

///|
/// The call `id` is answered, and the fiber that waits for it is given the answer: `kind` 0 its JSON alone (`text`),
/// 1 its JSON and `bytes`, 2 its error (`text`). One nobody waits for (told, or let go of) is nothing.
fn Shell::settle(self : Shell, id : Int64, kind : Int, text : String, bytes : Bytes) -> Unit {
  guard self.waiting.get(id) is Some(done) else { return }
  self.waiting.remove(id)
  if kind == 2 {
    ignore(done.fail(ShellError(text)))
    return
  }
  let json : Json = @json.parse(text) catch { _ => Json::null() }
  ignore(done.succeed({ json, bytes: if kind == 1 { Some(bytes) } else { None } }))
}
