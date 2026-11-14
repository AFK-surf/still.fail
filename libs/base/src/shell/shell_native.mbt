// The native shell: the Rust shell (client/shell, a static library the program is linked to), through its C
// interface as shell.c gives it. The shell answers from its own threads; shell.c keeps the answers in one queue, and
// the program's one thread takes them between its runtime's turns (`Shell::pump`): nothing of MoonBit runs on another
// thread. `run` is that loop for a program with nothing else to wait for; one with a UI pumps from its own.

///|
#borrow(dir)
extern "C" fn start_ffi(dir : Bytes) -> Int = "bsh_start"

///|
extern "C" fn wait_ffi(ms : Int64) -> Bytes = "bsh_wait"

///|
#borrow(op, json, bytes)
extern "C" fn call_ffi(id : Int64, op : Bytes, json : Bytes, bytes : Bytes, has : Int) = "bsh_call"

///|
#borrow(op, json)
extern "C" fn ask_ffi(op : Bytes, json : Bytes) -> Bytes = "bsh_ask"

///|
extern "C" fn now_ffi() -> Int64 = "bsh_now"

///|
extern "C" fn random_ffi(n : Int) -> Bytes = "bsh_random"

///|
/// `s` as C reads it: UTF-8, ended by a NUL.
fn cstr(s : String) -> Bytes {
  let b = @utf8.encode(s)
  let out = FixedArray::make(b.length() + 1, b'\x00')
  for i = 0; i < b.length(); i = i + 1 {
    out[i] = b[i]
  }
  Bytes::from_array(out)
}

///|
/// Starts the shell for the fibers of `rt`, keeping what it keeps (`storage.*`) in the directory `dir`, made if it is
/// not there, its user's alone.
pub fn Shell::start(rt : @effect.Runtime, dir : String) -> Shell raise ShellError {
  if start_ffi(cstr(dir)) == 0 {
    raise ShellError("the shell did not start in \{dir}")
  }
  { rt, waiting: Map([]), next: 0L }
}

///|
/// A call out: `op` with its JSON and, where it carries any, its bytes, answered later as `id`.
fn send(id : Int64, op : String, json : String, bytes : Bytes?) -> Unit {
  match bytes {
    Some(b) => call_ffi(id, cstr(op), @utf8.encode(json), b, 1)
    None => call_ffi(id, cstr(op), @utf8.encode(json), b"", 0)
  }
}

///|
/// What the shell answers `op` at once: `{"value": …}` or `{"error": …}`.
fn asked(op : String, json : String) -> String {
  @utf8.decode_lossy(ask_ffi(cstr(op), @utf8.encode(json)))
}

///|
fn le(b : Bytes, at : Int, n : Int) -> Int64 {
  let mut out = 0L
  for i = n - 1; i >= 0; i = i - 1 {
    out = (out << 8) | b[at + i].to_int64()
  }
  out
}

///|
/// One answer as shell.c packs it, given to the fiber that waits for it.
fn Shell::answered(self : Shell, a : Bytes) -> Unit {
  guard a.length() >= 13 else { return }
  let id = le(a, 0, 8)
  let n = le(a, 9, 4).to_int()
  guard 13 + n <= a.length() else { return }
  self.settle(id, a[8].to_int(), @utf8.decode_lossy(a[13:13 + n]), a[13 + n:].to_owned())
}

///|
/// Waits at most `ms` for an answer of the shell's (negative: until one comes; 0: not at all) and gives every answer
/// that is in to its fiber, which runs at the runtime's next turn. Whether any came.
pub fn Shell::pump(self : Shell, ms : Int64) -> Bool {
  let first = wait_ffi(ms)
  if first.length() == 0 {
    return false
  }
  self.answered(first)
  while true {
    let more = wait_ffi(0L)
    if more.length() == 0 {
      break
    }
    self.answered(more)
  }
  true
}

///|
/// A clock that never goes back, in ms: what a runtime of the shell's programs goes by.
pub fn now() -> Int64 {
  now_ffi()
}

///|
/// `n` bytes of the system's randomness (a key).
pub fn random(n : Int) -> Bytes {
  random_ffi(n)
}

///|
/// Runs `main` to its end on this thread, as a fiber of a runtime on the machine's clock, with the shell keeping its
/// files in `dir`: between the runtime's turns the thread waits for the shell's next answer or the runtime's next
/// timer, and for nothing else. `failed` is told what `main`, or a fiber it left behind, failed with. The program's
/// exit code: 0 once `main` ended well.
pub fn run(dir : String, main : async (Shell) -> Unit, failed~ : (Error) -> Unit) -> Int {
  let rt = @effect.Runtime::live(now_ffi)
  let shell = Shell::start(rt, dir) catch {
    e => {
      failed(e)
      return 1
    }
  }
  rt.on_defect(failed)
  let fiber = rt.fork(() => main(shell), name="main")
  while true {
    rt.tick()
    if fiber.is_done() {
      break
    }
    let wait = if !rt.idle() {
      0L
    } else {
      match rt.next_timer() {
        Some(at) => {
          let left = at - now_ffi()
          if left < 0L { 0L } else { left }
        }
        None => -1L
      }
    }
    ignore(shell.pump(wait))
  }
  match fiber.poll() {
    Some(Succeeded(_)) => 0
    Some(Failed(e)) => {
      failed(e)
      1
    }
    _ => 1
  }
}
