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
#borrow(op, json, bytes)
extern "C" fn shell_call_ffi(id : Int64, op : Bytes, json : Bytes, bytes : Bytes, has : Int) = "sfh_shell_call"

///|
/// What the program is given: its stdin's lines, the shell, its stdout.
pub struct Host {
  rt : @effect.Runtime
  lines : @effect.Queue[String]
  /// Stdin's bytes, made lines.
  priv input : @wire.Lines
  /// The shell's calls not answered yet, by their ids.
  priv waiting : Map[Int64, @effect.Deferred[(Json, Bytes?)]]
  priv mut next : Int64
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
/// Asks the shell what it answers later (its network, its sockets: client/shell's `run`), with `bytes` where the call
/// carries them; its JSON and the bytes its answer carries. Other fibers go on meanwhile. `called` is told the call's
/// id as it is asked: what gives up a call the shell lets be given up (`fetch.cancel`: a fetch, a dial).
pub async fn Host::shell(
  self : Host,
  op : String,
  args : Json,
  bytes? : Bytes,
  called? : (Int64) -> Unit,
) -> (Json, Bytes?) {
  self.next += 1L
  let id = self.next
  if called is Some(f) {
    f(id)
  }
  let done = @effect.Deferred::new()
  self.waiting[id] = done
  match bytes {
    Some(b) => shell_call_ffi(id, cstr(op), @utf8.encode(args.stringify()), b, 1)
    None => shell_call_ffi(id, cstr(op), @utf8.encode(args.stringify()), b"", 0)
  }
  done.wait()
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
/// Writes `text` and a newline to stdout, U+2028 and U+2029 written as JSON escapes (`\u2028`, `\u2029`): the station
/// reads each line with node:readline, which ends a line at either of them too, so a chat's text with one cut the
/// answer that held it in two, neither JSON, and its read was never answered (2026-11-14). A line said here is JSON,
/// where they can stand only in a string, and so are the same escaped.
pub fn Host::say(self : Host, text : String) -> Unit {
  ignore(self)
  let line = if text.contains("\u{2028}") || text.contains("\u{2029}") {
    text.replace_all(old="\u{2028}", new="\\u2028").replace_all(old="\u{2029}", new="\\u2029")
  } else {
    text
  }
  ignore(out_ffi(@utf8.encode(line + "\n")))
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
    Answer(id, answer, carried) =>
      match self.waiting.get(id) {
        Some(done) => {
          self.waiting.remove(id)
          match answer {
            Ok(json) => ignore(done.succeed((json, carried)))
            Err(e) => ignore(done.fail(e))
          }
        }
        None => ()
      }
    Other => ()
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
    waiting: Map([]),
    next: 0L,
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
