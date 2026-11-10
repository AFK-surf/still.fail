// A station program's host: the program's one thread runs an effect runtime on the machine's clock, and between its
// turns waits (host.c) for what comes from outside: the lines its parent writes on stdin (and the shell's answers from
// its own threads, client/shell, once a call of it that answers later is asked). Nothing waits for real time but that
// one wait, for the next of those or the runtime's next timer.

///|
#borrow(dir)
extern "C" fn start_ffi(dir : Bytes) -> Int = "sfh_start"

///|
extern "C" fn wait_ffi(ms : Int64) -> Bytes = "sfh_wait"

///|
#borrow(b)
extern "C" fn out_ffi(b : Bytes) -> Int = "sfh_out"

///|
extern "C" fn now_ffi() -> Int64 = "sfh_now"

///|
#borrow(op, json)
extern "C" fn shell_sync_ffi(op : Bytes, json : Bytes) -> Bytes = "sfh_shell_sync"

///|
/// What the program is given: its stdin's lines, the shell, its stdout.
pub struct Host {
  rt : @effect.Runtime
  lines : @effect.Queue[String]
  /// Stdin's bytes, made lines.
  priv input : @wire.Lines
}

///|
/// A C string: `s` in UTF-8, NUL-terminated.
fn cstr(s : String) -> Bytes {
  let b = @utf8.encode(s)
  let out = FixedArray::make(b.length() + 1, b'\x00')
  for i = 0; i < b.length(); i = i + 1 {
    out[i] = b[i]
  }
  Bytes::from_array(out)
}

///|
/// Asks the shell at once (what it answers on the calling thread: `sql.*`).
pub fn Host::shell_sync(self : Host, op : String, args : Json) -> Json raise @wire.ShellError {
  ignore(self)
  let out = shell_sync_ffi(cstr(op), @utf8.encode(args.stringify()))
  @wire.answered(@utf8.decode_lossy(out))
}

///|
/// The next line its parent wrote (without its newline); None once stdin has ended.
pub async fn Host::line(self : Host) -> String? {
  Some(self.lines.take()) catch {
    @effect.QueueShutdown => None
    e => raise e
  }
}

///|
/// Writes `text` and a newline to stdout.
pub fn Host::say(self : Host, text : String) -> Unit {
  ignore(self)
  ignore(out_ffi(@utf8.encode(text + "\n")))
}

///|
/// Writes `text` and a newline to stderr, for the station's log.
pub fn note(text : String) -> Unit {
  eprintln(text)
}

///|
fn Host::dispatch(self : Host, e : Bytes) -> Unit {
  match @wire.Event::read(e) {
    Input(data) => for line in self.input.push(data) { ignore(self.lines.try_offer(line)) }
    End => self.lines.shutdown()
    // (no call of the shell's that answers later is asked yet)
    Answer(_) | Other => ()
  }
}

///|
/// Runs `main` to its end on this thread with the shell keeping its files in `shell_dir` (none: no shell), answering
/// stdin's lines and the shell's answers as they come; the program's exit code.
pub fn run(shell_dir? : String, main : async (Host) -> Unit) -> Int {
  let dir = match shell_dir {
    Some(d) => cstr(d)
    None => b"\x00"
  }
  if start_ffi(dir) == 0 {
    note("the shell did not start")
    return 1
  }
  let rt = @effect.Runtime::live(now_ffi)
  let failed = Ref(false)
  rt.on_defect(e => {
    note("failed: \{e}")
    failed.val = true
  })
  let host = {
    rt,
    lines: @effect.Queue::unbounded(),
    input: @wire.Lines::new(),
  }
  let fiber = rt.fork(() => main(host), name="main")
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
          if left < 0L {
            0L
          } else {
            left
          }
        }
        None => -1L
      }
    }
    let first = wait_ffi(wait)
    if first.length() > 0 {
      host.dispatch(first)
      // what else came meanwhile, before the runtime's next turn
      while true {
        let more = wait_ffi(0L)
        if more.length() == 0 {
          break
        }
        host.dispatch(more)
      }
    }
  }
  match fiber.poll() {
    Some(Failed(e)) => {
      note("failed: \{e}")
      1
    }
    Some(_) => if failed.val { 1 } else { 0 }
    None => 1
  }
}

///|
extern "C" fn exit_ffi(code : Int) = "exit"

///|
/// Ends the program with `code`.
pub fn exit(code : Int) -> Unit {
  exit_ffi(code)
}

///|
extern "C" fn args_ffi() -> Bytes = "sfh_args"

///|
/// The program's arguments, its own name first (as the system gives them, whatever the target the program was made
/// for: host.c `sfh_args`).
pub fn args() -> Array[String] {
  let all = args_ffi()
  let out = []
  let mut start = 0
  for i = 0; i < all.length(); i = i + 1 {
    if all[i] == b'\x00' {
      out.push(@utf8.decode_lossy(all[start:i]))
      start = i + 1
    }
  }
  out
}

///|
/// A clock that never goes back, in ms (host.c `sfh_now`).
pub fn now() -> Int64 {
  now_ffi()
}

///|
extern "C" fn pid_ffi() -> Int = "sfh_pid"

///|
/// This process's id.
pub fn pid() -> Int {
  pid_ffi()
}
