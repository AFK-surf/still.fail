// Waits for an event, not a time (detlint's script-wait): a line of a log another process writes, or a process's end
// (kqueue's on macOS, inotify's and a pidfd's on Linux: events.c).
//
//     chk logwait [--log FILE --line REGEX] [--pid PID] [--gone PATH] [--fail-log FILE --fail-line REGEX]
//                 [--deadline S]
//
// --log/--line: until a line of FILE (as it is written: its write events, from the start) matches REGEX; that line
// printed, exit 0. --pid: the process PID (any of this user's: a simulator's app, a child left running) watched for its
// end: with --line, its end without such a line is exit 1 (what was read gone over once more first); alone, its end is
// exit 0. --gone: until PATH is no more (its directory's changes: a lock let go), exit 0. --fail-log/--fail-line: a
// line of another FILE (as it is written) that says the event will not come (a launch refused): that line printed on
// stderr, exit 1. --deadline: how long at most (s, default 600; what a run that hangs is given before it fails, not
// what it is expected to take): exit 2.

///|
extern "C" fn ev_init() -> Int = "chk_ev_init"

///|
#borrow(path)
extern "C" fn ev_open(k : Int, path : Bytes) -> Int = "chk_ev_open"

///|
#borrow(path)
extern "C" fn ev_open_path(k : Int, path : Bytes) -> Int = "chk_ev_open_path"

///|
extern "C" fn ev_read(k : Int) -> Bytes = "chk_ev_read"

///|
extern "C" fn ev_file(k : Int) -> Int = "chk_ev_file"

///|
#borrow(path)
extern "C" fn ev_dir(path : Bytes) -> Int = "chk_ev_dir"

///|
extern "C" fn ev_pid(pid : Int) -> Int = "chk_ev_pid"

///|
extern "C" fn ev_wait(ms : Int) -> Int = "chk_ev_wait"

///|
fn path_bytes(p : String) -> Bytes {
  @utf8.encode(p)
}

///|
/// A file read as it is written, cut into its lines as they end (\n, \r\n or \r: Python's text mode)
priv struct Lines {
  k : Int
  pat : @re.Regex
  buf : Array[Byte]
}

///|
/// The first line, of those ended since, that matches; `last`: what is left is a line too
fn Lines::next(self : Lines, last : Bool) -> String? {
  for b in ev_read(self.k) {
    self.buf.push(b)
  }
  if last {
    self.buf.push(b'\n')
  }
  let mut start = 0
  let mut i = 0
  let mut found = None
  while i < self.buf.length() {
    let b = self.buf[i]
    if b == b'\n' || b == b'\r' {
      // (a \r at the end of what came: its \n may be still to come)
      if b == b'\r' && i + 1 == self.buf.length() && !last {
        break
      }
      let line = @utf8.decode_lossy(Bytes::from_array(self.buf[start:i].to_array())[:])
      i += if b == b'\r' && i + 1 < self.buf.length() && self.buf[i + 1] == b'\n' {
        2
      } else {
        1
      }
      start = i
      if self.pat.search(line) is Some(_) {
        found = Some(line)
        break
      }
      continue
    }
    i += 1
  }
  let rest = self.buf[start:].to_array()
  self.buf.clear()
  self.buf.append(rest)
  found
}

///|
fn deadline_text(d : Double) -> String {
  if d == d.floor() && d.abs() < 1.0e15 {
    d.to_int64().to_string()
  } else {
    d.to_string()
  }
}

///|
fn logwait_usage(why : String) -> Int {
  @sys.eprintln(
    "usage: chk logwait [--log FILE --line REGEX] [--pid PID] [--gone PATH] [--fail-log FILE --fail-line REGEX] [--deadline S]",
  )
  @sys.eprintln("chk logwait: error: \{why}")
  2
}

///|
fn logwait(args : Array[String]) -> Int {
  let opts : Map[String, String] = Map::new()
  let known = ["--log", "--line", "--pid", "--gone", "--fail-log", "--fail-line", "--deadline"]
  let mut i = 0
  while i < args.length() {
    let a = args[i]
    match a.find("=") {
      Some(k) if a.has_prefix("--") => {
        opts[a.view(end_offset=k).to_string()] = a.view(start_offset=k + 1).to_string()
        i += 1
        continue
      }
      _ => ()
    }
    if !known.contains(a) || i + 1 >= args.length() {
      return logwait_usage("unrecognized or incomplete argument: \{a}")
    }
    opts[a] = args[i + 1]
    i += 2
  }
  let log = opts.get("--log")
  let line = opts.get("--line")
  let pid = match opts.get("--pid") {
    Some(p) =>
      match int_of(p) {
        Some(n) => Some(n)
        None => return logwait_usage("argument --pid: invalid int value: '\{p}'")
      }
    None => None
  }
  let gone_path = opts.get("--gone")
  let deadline = match opts.get("--deadline") {
    Some(s) =>
      match double_of(s) {
        Some(d) => d
        None => return logwait_usage("argument --deadline: invalid float value: '\{s}'")
      }
    None => 600.0
  }
  if log is Some(_) != line is Some(_) ||
    !(log is Some(_) || pid is Some(_) || gone_path is Some(_)) {
    return logwait_usage("--log with --line, and/or --pid, or --gone")
  }
  if ev_init() == 0 {
    @sys.eprintln("chk logwait: this system's events are not known here")
    return 2
  }
  let mut gone = false
  match pid {
    Some(p) => gone = ev_pid(p) == 0
    None => ()
  }
  match gone_path {
    Some(g) => {
      let d = @sys.dirname(@sys.abspath(g))
      let _ = ev_dir(path_bytes(if d == "" { "." } else { d }))
    }
    None => ()
  }
  let f = match (log, line) {
    (Some(l), Some(pat)) => {
      if ev_open(0, path_bytes(l)) == 0 {
        @sys.eprintln("chk logwait: no such file: '\{l}'")
        return 1
      }
      let _ = ev_open_path(0, path_bytes(l))
      let _ = ev_file(0)
      Some({ k: 0, pat: rx(pat), buf: [] })
    }
    _ => None
  }
  let ff = match opts.get("--fail-log") {
    Some(l) => {
      // (made when it is not there yet)
      if !@sys.exists(l) {
        let _ = @sys.write_text(l, "")
      }
      let _ = ev_open(1, path_bytes(l))
      let _ = ev_open_path(1, path_bytes(l))
      let _ = ev_file(1)
      Some({ k: 1, pat: rx(opts.get("--fail-line").unwrap_or("")), buf: [] })
    }
    None => None
  }
  let end = @env.now().to_double() + deadline * 1000.0
  while true {
    match gone_path {
      Some(g) => if !@sys.exists(g) { return 0 }
      None => ()
    }
    match f {
      Some(f) =>
        match f.next(false) {
          Some(l) => {
            say(l)
            return 0
          }
          None => ()
        }
      None => ()
    }
    match ff {
      Some(ff) =>
        match ff.next(false) {
          Some(l) => {
            @sys.eprintln(l)
            return 1
          }
          None => ()
        }
      None => ()
    }
    if gone {
      match f {
        Some(f) =>
          match f.next(true) {
            Some(l) => {
              say(l)
              return 0
            }
            None => return 1
          }
        None => return 0
      }
    }
    let left = end - @env.now().to_double()
    if left <= 0.0 {
      let what = match (f, gone_path, pid) {
        (Some(_), _, _) => "no line /\{line.unwrap_or("")}/ in \{log.unwrap_or("")}"
        (None, Some(g), None) => "\{g} still there"
        _ => "process \{pid.unwrap_or(0)} still running"
      }
      @sys.eprintln("logwait: past the deadline (\{deadline_text(deadline)} s): \{what}")
      return 2
    }
    if ev_wait(left.to_int()) != 0 {
      gone = true
    }
  }
  0
}

///|
fn int_of(s : String) -> Int? {
  let t = trim(s)
  if t == "" {
    return None
  }
  let mut n = 0
  let mut neg = false
  for i, ch in t.to_array() {
    if i == 0 && (ch == '-' || ch == '+') {
      neg = ch == '-'
      continue
    }
    if ch < '0' || ch > '9' {
      return None
    }
    n = n * 10 + (ch.to_int() - '0'.to_int())
  }
  Some(if neg { -n } else { n })
}

///|
/// A number of seconds: digits, a point and digits
fn double_of(s : String) -> Double? {
  let t = trim(s)
  let mut whole = 0.0
  let mut frac = 0.0
  let mut scale = 1.0
  let mut point = false
  let mut digits = 0
  for ch in t {
    if ch == '.' && !point {
      point = true
      continue
    }
    if ch < '0' || ch > '9' {
      return None
    }
    digits += 1
    let d = (ch.to_int() - '0'.to_int()).to_double()
    if point {
      scale = scale / 10.0
      frac = frac + d * scale
    } else {
      whole = whole * 10.0 + d
    }
  }
  if digits == 0 {
    None
  } else {
    Some(whole + frac)
  }
}
