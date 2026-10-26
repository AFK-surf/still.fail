// What still.fail's app did with the signals (a trace record.sh wrote down: a line a call), done again on mbui's signals
// and timed: every signal and computed made as it was, read, set, disposed of, invalidated, lent, read for another, in
// the order the app did it; a computed's getter, run where the signals run it, does again what that run of the app's
// did (the reads, the sets, the computeds made in it) and answers a value changed or not as the app's did. The
// signals' own work is what is timed: the app's builds, layout and drawing are not in a trace.
//
// The replay checks itself: each computed runs as many times as it ran in the app, in the same order of its runs
// (a run more, or one left over, stops it). So a change to the signals that runs a getter more or less than they did
// as the trace was made is caught here.
//
//   replay.exe <trace>... [--repeats N]   a JSON row a trace: frames, calls by kind, the replay's time

///|
#borrow(path)
extern "C" fn read_file(path : Bytes) -> Bytes = "sbr_read"

///|
extern "C" fn now_ms() -> Double = "sbr_now_ms"

///|
// what a trace's line says
const NEW_SIGNAL : Int = 1

///|
const NEW_COMPUTED : Int = 2

///|
const GET : Int = 3

///|
const SET : Int = 4

///|
const PEEK : Int = 5

///|
const DISPOSE : Int = 6

///|
const INVALIDATE : Int = 7

///|
const LEND : Int = 8

///|
const READING : Int = 9

///|
const UNTRACKED : Int = 10

///|
const ACTIVE : Int = 11

///|
const BATCH : Int = 12

///|
const BATCH_END : Int = 13

///|
const WATCHED : Int = 14

///|
const FRAME : Int = 15

///|
let kinds : Array[String] = [
  "", "signal", "computed", "get", "set", "peek", "dispose", "invalidate", "lend",
  "reading", "untracked", "active", "batch", "batch_end", "watched", "frame",
]

///|
/// A trace, parsed: its blocks (the top's, each run of a computed's, each `reading`'s and `untracked`'s), a block's
/// calls three numbers each (what, and its two numbers) from `start` to `end` of `code`.
priv struct Trace {
  code : Array[Int]
  start : Array[Int]
  end : Array[Int]
  /// a computed's runs, by its number: the blocks, in order
  runs : Array[Array[Int]]
  /// a run's block: whether the value it made was another than the one before
  changed : Array[Bool]
  /// the highest node number
  top : Int
  /// how many calls of each kind, and runs
  counts : FixedArray[Int]
  run_count : Int
  frames : Int
}

///|
fn parse(text : Bytes) -> Trace {
  let blocks : Array[Array[Int]] = [[]]
  let changed : Array[Bool] = [false]
  let runs : Array[Array[Int]] = []
  let counts = FixedArray::make(16, 0)
  let stack : Array[Int] = [0]
  let mut top = 0
  let mut run_count = 0
  let mut frames = 0
  let n = text.length()
  let mut i = 0
  let line : Array[Int] = []
  // a line's numbers (after its letter), into `line`
  let number = fn(start : Int) -> Int {
    let mut j = start
    let mut neg = false
    if j < n && text[j] == b'-' {
      neg = true
      j += 1
    }
    let mut v = 0
    while j < n && text[j] >= b'0' && text[j] <= b'9' {
      v = v * 10 + (text[j].to_int() - 48)
      j += 1
    }
    line.push(if neg { -v } else { v })
    j
  }
  let runs_of = fn(id : Int) -> Array[Int] {
    while runs.length() <= id {
      runs.push([])
    }
    runs[id]
  }
  while i < n {
    let op = text[i]
    line.clear()
    let mut j = i + 1
    while j < n && text[j] == b' ' {
      j = number(j + 1)
    }
    while j < n && text[j] != b'\n' {
      j += 1
    }
    i = j + 1
    for v in line {
      if v > top {
        top = v
      }
    }
    let here = blocks[stack[stack.length() - 1]]
    let put = fn(what : Int, a : Int, b : Int) {
      here.push(what)
      here.push(a)
      here.push(b)
      counts[what] += 1
    }
    match op {
      b'S' => put(NEW_SIGNAL, line[0], 0)
      b'C' => put(NEW_COMPUTED, line[0], 0)
      b'G' => put(GET, line[0], 0)
      b'T' => put(SET, line[0], line[1])
      b'P' => put(PEEK, line[0], 0)
      b'D' => put(DISPOSE, line[0], 0)
      b'I' => put(INVALIDATE, line[0], 0)
      b'L' => put(LEND, line[0], line[1])
      b'A' => put(ACTIVE, line[0], 0)
      b'b' => put(BATCH, 0, 0)
      b'B' => put(BATCH_END, 0, 0)
      b'W' => put(WATCHED, line[0], 0)
      b'F' => {
        put(FRAME, 0, 0)
        frames += 1
      }
      b'[' => {
        let b = blocks.length()
        blocks.push([])
        changed.push(false)
        runs_of(line[0]).push(b)
        stack.push(b)
        run_count += 1
      }
      b']' => {
        let b = stack.pop().unwrap()
        changed[b] = line[1] == 1
      }
      b'(' => {
        let b = blocks.length()
        blocks.push([])
        changed.push(false)
        put(READING, line[0], b)
        stack.push(b)
      }
      b'U' => {
        let b = blocks.length()
        blocks.push([])
        changed.push(false)
        put(UNTRACKED, 0, b)
        stack.push(b)
      }
      b')' | b'u' => ignore(stack.pop())
      b'X' => abort("the trace has an effect, a scope or a trigger: the replay has none")
      _ => abort("the trace's line \{op}: not one of the replay's")
    }
  }
  if stack.length() != 1 {
    abort("the trace ends inside a run or a block (\{stack.length() - 1} open)")
  }
  let code : Array[Int] = []
  let start : Array[Int] = []
  let end : Array[Int] = []
  for b in blocks {
    start.push(code.length())
    for v in b {
      code.push(v)
    }
    end.push(code.length())
  }
  while runs.length() <= top {
    runs.push([])
  }
  { code, start, end, runs, changed, top, counts, run_count, frames }
}

///|
/// The nodes a replay made, by their numbers in the trace, and how far each computed's runs went.
priv struct Replay {
  trace : Trace
  sigs : Array[@signals.Signal[Int]?]
  comps : Array[@signals.Computed[Int]?]
  vals : FixedArray[Int]
  cursor : FixedArray[Int]
  /// a computed's node as its run read it (what the app set reading again, set_active_sub)
  nodes : Array[@signals.ReactiveNode?]
}

///|
fn Replay::new(t : Trace) -> Replay {
  let n = t.top + 1
  {
    trace: t,
    sigs: Array::make(n, None),
    comps: Array::make(n, None),
    vals: FixedArray::make(n, 0),
    cursor: FixedArray::make(n, 0),
    nodes: Array::make(n, None),
  }
}

///|
fn Replay::block(self : Replay, b : Int) -> Unit {
  let t = self.trace
  let code = t.code
  let mut i = t.start[b]
  let end = t.end[b]
  while i < end {
    let what = code[i]
    let a = code[i + 1]
    let x = code[i + 2]
    i += 3
    // (by the kinds' numbers: NEW_SIGNAL 1 … WATCHED 14)
    match what {
      1 => {
        self.sigs[a] = Some(@signals.signal(0))
        self.vals[a] = 0
      }
      2 => {
        let id = a
        self.comps[id] = Some(@signals.computed(fn(prev) { self.run(id, prev) }))
      }
      3 =>
        match self.sigs[a] {
          Some(s) => ignore(s.get())
          None => ignore(self.comps[a].unwrap().get())
        }
      4 => {
        if x == 1 {
          self.vals[a] += 1
        }
        self.sigs[a].unwrap().set(self.vals[a])
      }
      5 => ignore(self.comps[a].unwrap().peek())
      6 => self.comps[a].unwrap().dispose()
      7 => self.comps[a].unwrap().invalidate()
      8 => self.comps[a].unwrap().lend(self.comps[x].unwrap())
      9 => self.comps[a].unwrap().reading(fn() { self.block(x) })
      10 => @signals.untracked(fn() { self.block(x) })
      11 =>
        ignore(@signals.set_active_sub(if a < 0 { None } else { self.nodes[a] }))
      12 => @signals.start_batch()
      13 => @signals.end_batch()
      14 =>
        match self.sigs[a] {
          Some(s) => ignore(s.watched())
          None => ignore(self.comps[a].unwrap().watched())
        }
      _ => ()
    }
  }
}

///|
/// Computed `id`'s getter: its next run in the trace done again, its value another than `prev` as the app's was.
fn Replay::run(self : Replay, id : Int, prev : Int?) -> Int {
  let runs = self.trace.runs[id]
  let k = self.cursor[id]
  if k >= runs.length() {
    abort("computed \{id} ran a time more than the app's did (\{runs.length()})")
  }
  self.cursor[id] = k + 1
  self.nodes[id] = @signals.active_sub()
  let b = runs[k]
  self.block(b)
  match prev {
    None => 0
    Some(p) => if self.trace.changed[b] { p + 1 } else { p }
  }
}

///|
/// The replay done: each computed ran as many times as in the trace.
fn Replay::check(self : Replay) -> Unit {
  for id in 0..<self.trace.runs.length() {
    let want = self.trace.runs[id].length()
    if self.cursor[id] != want {
      abort("computed \{id} ran \{self.cursor[id]} times, the app's \{want}")
    }
  }
}

///|
/// The trace's calls walked through without the signals: what reading them costs, apart from the signals' work.
fn walk(t : Trace) -> Int {
  let mut sum = 0
  for b in 0..<t.start.length() {
    let mut i = t.start[b]
    while i < t.end[b] {
      sum += t.code[i] + t.code[i + 1] + t.code[i + 2]
      i += 3
    }
  }
  sum
}

///|
fn bytes_of(s : String) -> Bytes {
  let a : Array[Byte] = []
  for c in s {
    a.push(c.to_int().to_byte())
  }
  a.push(b'\x00')
  Bytes::from_array(a)
}

///|
fn json_string(s : String) -> String {
  let b = StringBuilder()
  b.write_char('"')
  for c in s {
    match c {
      '"' => b.write_string("\\\"")
      '\\' => b.write_string("\\\\")
      _ => b.write_char(c)
    }
  }
  b.write_char('"')
  b.to_string()
}

///|
fn whole(s : String, default : Int) -> Int {
  let mut n = 0
  for c in s {
    if c < '0' || c > '9' {
      return default
    }
    n = n * 10 + (c.to_int() - 48)
  }
  if n > 0 {
    n
  } else {
    default
  }
}

///|
fn main {
  let args = @env.args()
  let paths : Array[String] = []
  let mut repeats = 5
  let mut i = 1
  while i < args.length() {
    if args[i] == "--repeats" && i + 1 < args.length() {
      repeats = whole(args[i + 1], 5)
      i += 2
    } else {
      paths.push(args[i])
      i += 1
    }
  }
  let mut all_frames = 0
  let mut all_ms = 0.0
  let mut all_walk = 0.0
  let mut all_runs = 0
  let all_counts = FixedArray::make(16, 0)
  let rows : Array[String] = []
  for path in paths {
    let text = read_file(bytes_of(path))
    if text.length() == 0 {
      abort("\{path}: no trace there")
    }
    let t = parse(text)
    // once to check it (and to warm up), then timed
    let first = Replay::new(t)
    first.block(0)
    first.check()
    let samples : Array[Double] = []
    for _ in 0..<repeats {
      let r = Replay::new(t)
      let t0 = now_ms()
      r.block(0)
      let t1 = now_ms()
      samples.push(t1 - t0)
      r.check()
    }
    let w0 = now_ms()
    let w = walk(t)
    let w1 = now_ms()
    let mut min = samples[0]
    for s in samples {
      if s < min {
        min = s
      }
    }
    let calls = StringBuilder()
    for k in 1..<16 {
      if k > 1 {
        calls.write_string(",")
      }
      calls.write_string("\{json_string(kinds[k])}:\{t.counts[k]}")
    }
    let name = StringBuilder()
    for c in path {
      if c == '/' {
        name.reset()
      } else {
        name.write_char(c)
      }
    }
    all_frames += t.frames
    all_ms += min
    all_walk += w1 - w0
    all_runs += t.run_count
    for k in 0..<16 {
      all_counts[k] += t.counts[k]
    }
    let per = fn(v : Int) { (v.to_double() / t.frames.to_double() * 10.0).round() / 10.0 }
    rows.push(
      "| \{name.to_string()} | \{t.frames} | \{per(t.counts[GET])} | \{per(t.run_count)} | \{per(t.counts[SET])} | \{per(t.counts[LEND])} | \{per(t.counts[NEW_COMPUTED])} | \{per(t.counts[DISPOSE])} | \{(min * 1000.0 / t.frames.to_double() * 100.0).round() / 100.0} |",
    )
    println(
      "{\"trace\":\{json_string(name.to_string())},\"frames\":\{t.frames},\"nodes\":\{t.top},\"runs\":\{t.run_count},\"calls\":{\{calls.to_string()}},\"timeMs\":\{min},\"samplesMs\":[\{samples.map(fn(s) { s.to_string() }).join(",")}],\"walkMs\":\{w1 - w0},\"walk\":\{w % 7}}",
    )
  }
  if paths.length() > 1 && all_frames > 0 {
    let per = fn(v : Int) { (v.to_double() / all_frames.to_double() * 10.0).round() / 10.0 }
    println("")
    println("| trace | frames | gets/frame | runs/frame | sets/frame | lends/frame | made/frame | disposed/frame | µs/frame |")
    println("| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
    for r in rows {
      println(r)
    }
    println(
      "| all | \{all_frames} | \{per(all_counts[GET])} | \{per(all_runs)} | \{per(all_counts[SET])} | \{per(all_counts[LEND])} | \{per(all_counts[NEW_COMPUTED])} | \{per(all_counts[DISPOSE])} | \{(all_ms * 1000.0 / all_frames.to_double() * 100.0).round() / 100.0} |",
    )
    println("")
    println("total \{all_ms} ms over \{all_frames} frames (walking the calls alone: \{all_walk} ms)")
  }
}
