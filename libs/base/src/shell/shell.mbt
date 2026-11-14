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
  send(id, op, args.stringify(), bytes)
  done.wait()
}

///|
/// Asks the shell `op` and waits for no answer: what is done on the way out of something (a stream let go of, a
/// connection closed), from code that is no fiber's too.
pub fn Shell::tell(self : Shell, op : String, args : Json, bytes? : Bytes) -> Unit {
  self.next += 1L
  send(self.next, op, args.stringify(), bytes)
}

///|
/// Asks the shell what it answers at once, on this thread (what is known of a handle: `iroh.endpointId`, `conn.paths`).
pub fn Shell::ask(self : Shell, op : String, args : Json) -> Json raise ShellError {
  ignore(self)
  let json : Json = @json.parse(asked(op, args.stringify())) catch {
    e => raise ShellError("the shell's answer is not JSON: \{e}")
  }
  match json {
    { "error": String(e), .. } => raise ShellError(e)
    { "value": v, .. } => v
    _ => Json::null()
  }
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
