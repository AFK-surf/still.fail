// Processes: started, their output kept in a file of this process's own, waited for

///|
let finished : Map[Int, Int] = Map::new() // slot: exit code, of those that ended while waiting for another

///|
let tmp_count : Ref[Int] = { val: 0 }

///|
fn tmp_dir() -> Bytes {
  for v in ["TMPDIR", "TEMP", "TMP"] {
    match getenv(v) {
      Some(d) if d.length() > 0 => return d
      _ => ()
    }
  }
  b"/tmp"
}

///|
/// A new file name for a process's output
fn tmp_path(what : String) -> Bytes {
  tmp_count.val = tmp_count.val + 1
  path_join(tmp_dir(), utf8("mbc-\{c_getpid()}-\{tmp_count.val}-\{what}"))
}

///|
/// Starts argv, its output (stdout and stderr) into `out` (empty: this process's own): its slot, -1 when it could
/// not be started
fn spawn(argv : Array[Bytes], out : Bytes) -> Int {
  let words = @buffer.new()
  for w in argv {
    words.write_bytes(w)
    words.write_byte(b'\x00')
  }
  c_spawn(words.to_bytes(), list2cmdline(argv), out)
}

///|
/// Waits for the process in `slot`: its exit code
fn wait_slot(slot : Int) -> Int {
  match finished.get(slot) {
    Some(code) => {
      finished.remove(slot)
      return code
    }
    None => ()
  }
  while true {
    let s = c_wait_any()
    if s < 0 {
      return 127
    }
    let code = c_status()
    if s == slot {
      return code
    }
    finished[s] = code
  }
  127
}

///|
/// Waits for any process started: (its slot, its exit code), (-1, _) when none is running
fn wait_any() -> (Int, Int) {
  for s, code in finished {
    finished.remove(s)
    return (s, code)
  }
  let s = c_wait_any()
  (s, if s < 0 { 127 } else { c_status() })
}

///|
/// Runs argv: (exit code, its output: stdout and stderr together)
fn run_capture(argv : Array[Bytes]) -> (Int, Bytes) {
  let out = tmp_path("out")
  let slot = spawn(argv, out)
  if slot < 0 {
    let _ = c_remove(out)
    return (127, utf8("cannot run \{str(argv[0])}\n"))
  }
  let code = wait_slot(slot)
  let text = read_file(out).unwrap_or(b"")
  let _ = c_remove(out)
  (code, text)
}

///|
/// Runs argv with this process's output: its exit code
fn run_inherit(argv : Array[Bytes]) -> Int {
  let slot = spawn(argv, b"")
  if slot < 0 {
    eprint("mbc: cannot run \{str(argv[0])}")
    return 127
  }
  wait_slot(slot)
}

///|
fn now_s() -> Double {
  @env.now().to_double() / 1000.0
}

///|
fn secs(t0 : Double) -> String {
  let d = now_s() - t0
  let t = (d * 10.0 + 0.5).to_int()
  "\{t / 10}.\{t % 10}"
}
