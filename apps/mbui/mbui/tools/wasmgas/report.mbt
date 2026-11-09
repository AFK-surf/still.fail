// What a profiled run counted (mbui's wasm_shell.c's file, MBUI_PROFILE_FILE: its head says the lines), said: a frame
// on average, each kind of instruction and its weighted count, the functions that ran the most; or two runs side by
// side, a change's before and after. Numbers only, no verdict: what they say is the reader's to weigh (the user,
// 2026-11-09).

///|
/// Rough cycles an instruction of each kind costs (kinds' order), what the counts are weighted by: to be fitted to the
/// native build's or a device's timings. Alloc, free and rc as a call's: on linear memory what the allocator and the
/// counts run inside is counted in their own kinds already.
let weights : FixedArray[Double] = [
  0.0, 0.25, 1.0, 1.0, 1.0, 2.0, 15.0, 3.0, 3.0, 5.0, 10.0, 40.0, 6.0, 5.0, 30.0, 1.0, 5.0, 5.0,
]

///|
priv struct Run {
  frames : Array[Int64]
  kinds : Array[Int64]
  // each function's over all frames: own, calls, inclusive, by its index among the defined
  own : Map[Int, Int64]
  calls : Map[Int, Int64]
  incl : Map[Int, Int64]
  names : Map[Int, String]
  imported : Int
  // what the functions counted apart (the test's host) ran over all frames, and their calls
  mut apart : Int64
  mut apart_calls : Int64
  // each frame's allocations and the bytes they asked for (M lines; none in a profile from before they were counted)
  allocs : Array[Int64]
  alloc_bytes : Array[Int64]
}

///|
fn number(s : String) -> Int64 {
  let mut v = 0L
  for c in s {
    if c < '0' || c > '9' {
      fail("not a number: \{s}")
    }
    v = v * 10L + (c.to_int() - '0'.to_int()).to_int64()
  }
  v
}

///|
fn imported_functions(data : Bytes) -> Int {
  check_magic(data)
  let r = Reader::new(data, 8)
  let mut n = 0
  while r.p < data.length() {
    let id = r.byte()
    let size = r.uint()
    let end = r.p + size
    if id == 2 {
      let count = r.uint()
      for _ in 0..<count {
        ignore(r.name())
        ignore(r.name())
        match r.byte() {
          0 => {
            ignore(r.uint())
            n += 1
          }
          1 => {
            ignore(r.byte())
            r.limits()
          }
          2 => r.limits()
          3 => {
            ignore(r.byte())
            ignore(r.byte())
          }
          k => fail("an import this reads not (\{k})")
        }
      }
    }
    r.p = end
  }
  n
}

///|
/// A run: the profile's file, and the program (as profiled or before) for its functions' names
fn read_run(program : String, profile : String) -> Run {
  let data = match @sys.read_bytes(program) {
    Some(d) => d
    None => fail("\{program}: cannot be read")
  }
  let text = match @sys.read_text(profile) {
    Some(t) => t
    None => fail("\{profile}: cannot be read")
  }
  let run : Run = {
    frames: [],
    kinds: [],
    own: {},
    calls: {},
    incl: {},
    names: function_names(data),
    imported: imported_functions(data),
    apart: 0L,
    apart_calls: 0L,
    allocs: [],
    alloc_bytes: [],
  }
  for line in text.split("\n") {
    let p = line.split(" ").map(fn(v) { v.to_owned() }).to_array()
    match p {
      ["FRAME", _, sum] => run.frames.push(number(sum))
      ["TOTAL", i, own, calls, incl] => {
        let k = number(i).to_int()
        run.own[k] = number(own)
        run.calls[k] = number(calls)
        run.incl[k] = number(incl)
      }
      ["M", _, n, bytes] => {
        run.allocs.push(number(n))
        run.alloc_bytes.push(number(bytes))
      }
      ["APART", n, calls] => {
        run.apart = number(n)
        run.apart_calls = number(calls)
      }
      ["KINDS", .. cs] => for c in cs {
        run.kinds.push(number(c))
      }
      _ => ()
    }
  }
  if run.frames.is_empty() || run.kinds.is_empty() {
    fail("\{profile}: no frames measured, or the run did not end")
  }
  run
}

///|
fn Run::name(self : Run, k : Int) -> String {
  match self.names.get(self.imported + k) {
    Some(n) => n
    None => "#\{self.imported + k}"
  }
}

///|
fn Run::per_frame(self : Run, v : Int64) -> Double {
  v.to_double() / self.frames.length().to_double()
}

///|
fn Run::kind(self : Run, k : Int) -> Double {
  if k < self.kinds.length() {
    self.per_frame(self.kinds[k])
  } else {
    0.0
  }
}

///|
fn Run::weighted(self : Run) -> Double {
  let mut w = 0.0
  for k in 0..<kinds.length() {
    w += self.kind(k) * weights[k]
  }
  w
}

///|
fn Run::all(self : Run) -> Double {
  let mut a = 0.0
  for k in 0..<kinds.length() {
    a += self.kind(k)
  }
  a
}

///|
/// The frames' counts sorted
fn Run::sorted(self : Run) -> Array[Int64] {
  let s = self.frames.copy()
  s.sort()
  s
}

///|
fn Run::at(self : Run, q : Double) -> Double {
  let s = self.sorted()
  s[(s.length().to_double() * q).to_int().min(s.length() - 1)].to_double()
}

///|
fn sum(vs : Array[Int64]) -> Int64 {
  let mut t = 0L
  for v in vs {
    t += v
  }
  t
}

///|
/// The value at `q` of `vs` sorted (0: the least, 1: the most)
fn quantile(vs : Array[Int64], q : Double) -> Int64 {
  let s = vs.copy()
  s.sort()
  s[(s.length().to_double() * q).to_int().min(s.length() - 1)]
}

///|
/// The allocations said: a frame's on average, p50, p90, the most; the frames with none; the bytes
fn alloc_lines(run : Run) -> Array[String] {
  if run.allocs.is_empty() {
    return ["allocations: not counted (a profile from before wasmgas counted them)"]
  }
  let a = run.allocs
  let none = a.filter(fn(v) { v == 0L }).length()
  [
    "allocations: \{sum(a)} in all; a frame: mean \{tenths(run.per_frame(sum(a)))}, p50 \{quantile(a, 0.5)}, p90 \{quantile(a, 0.9)}, max \{quantile(a, 1.0)}; \{none} of \{a.length()} frames none",
    "  their bytes: \{sum(run.alloc_bytes)} in all; a frame: mean \{tenths(run.per_frame(sum(run.alloc_bytes)))}, max \{quantile(run.alloc_bytes, 1.0)}",
  ]
}

///|
/// Thousands, a decimal: 1,234.5K
fn k(v : Double) -> String {
  let t = (v.abs() / 100.0).round().to_int64()
  let whole = (t / 10L).to_string()
  let sb = StringBuilder::new()
  if v < 0.0 && t != 0L {
    sb.write_char('-')
  }
  let n = whole.length()
  for i, c in whole.to_array() {
    if i > 0 && (n - i) % 3 == 0 {
      sb.write_char(',')
    }
    sb.write_char(c)
  }
  sb.write_string(".\{t % 10L}K")
  sb.to_string()
}

///|
fn signed(s : String, v : Double) -> String {
  if v >= 0.0 && !s.has_prefix("-") {
    "+" + s
  } else {
    s
  }
}

///|
fn pct(before : Double, after : Double) -> String {
  if before == 0.0 {
    return if after == 0.0 { "0.0%" } else { "new" }
  }
  let t = ((after - before) / before * 1000.0).round().to_int64()
  let a = t.abs()
  (if t < 0L { "-" } else { "+" }) + "\{a / 10L}.\{a % 10L}%"
}

///|
fn weight(w : Double) -> String {
  if w == w.floor() {
    w.to_int().to_string()
  } else {
    w.to_string()
  }
}

///|
/// A count, a decimal: 12.5
fn tenths(v : Double) -> String {
  let t = (v * 10.0).round().to_int64()
  "\{t / 10L}.\{t % 10L}"
}

///|
fn spaces(n : Int) -> String {
  let sb = StringBuilder::new()
  for _ in 0..<n {
    sb.write_char(' ')
  }
  sb.to_string()
}

///|
fn pad(s : String, w : Int) -> String {
  if s.length() >= w {
    s
  } else {
    spaces(w - s.length()) + s
  }
}

///|
fn padr(s : String, w : Int) -> String {
  if s.length() >= w {
    s
  } else {
    s + spaces(w - s.length())
  }
}

///|
fn row(cells : Array[(String, Int)]) -> Unit {
  let sb = StringBuilder::new()
  for i, c in cells {
    sb.write_string(if i == 0 { padr(c.0, c.1) } else { " " + pad(c.0, c.1) })
  }
  @sys.println_out(sb.to_string())
}

///|
/// The functions by `by` (own, inclusive: a frame on average), the `top` most
fn top_functions(run : Run, top : Int, inclusive : Bool) -> Unit {
  let ks = run.own.keys().to_array()
  let of = fn(k : Int) {
    if inclusive {
      run.incl.get(k).unwrap_or(0L)
    } else {
      run.own.get(k).unwrap_or(0L)
    }
  }
  ks.sort_by(fn(a, b) { of(b).compare(of(a)) })
  row([("", 0), ("own", 10), ("inclusive", 10), ("calls", 8)])
  for i in 0..<top.min(ks.length()) {
    let f = ks[i]
    row([
      ("", 0),
      (k(run.per_frame(run.own.get(f).unwrap_or(0L))), 10),
      (k(run.per_frame(run.incl.get(f).unwrap_or(0L))), 10),
      (tenths(run.per_frame(run.calls.get(f).unwrap_or(0L))), 8),
      (" " + run.name(f), 0),
    ])
  }
}

///|
/// One run: wasmgas report PROGRAM PROFILE [TOP]
fn report(run : Run, top : Int) -> Unit {
  @sys.println_out(
    "\{run.frames.length()} frames measured; a frame: mean \{k(run.all())}, p10 \{k(run.at(0.1))}, p50 \{k(run.at(0.5))}, p90 \{k(run.at(0.9))}, max \{k(run.at(1.0))}",
  )
  @sys.println_out("")
  row([("kind", 9), ("a frame", 10), ("weight", 6), ("weighted", 10)])
  for i in 0..<kinds.length() {
    row([
      (kinds[i], 9),
      (k(run.kind(i)), 10),
      (weight(weights[i]), 6),
      (k(run.kind(i) * weights[i]), 10),
    ])
  }
  row([("all", 9), (k(run.all()), 10), ("", 6), (k(run.weighted()), 10)])
  @sys.println_out(
    "apart, not counted above (the test's stand-in for the host, a device's host's own code): \{k(run.per_frame(run.apart))} a frame, in \{tenths(run.per_frame(run.apart_calls))} calls (each one host call above)",
  )
  @sys.println_out("")
  for l in alloc_lines(run) {
    @sys.println_out(l)
  }
  @sys.println_out("")
  @sys.println_out("by their own instructions, a frame on average:")
  top_functions(run, top, false)
  @sys.println_out("")
  @sys.println_out("by all their calls ran, a frame on average:")
  top_functions(run, top, true)
}

///|
/// Two runs: wasmgas compare BEFORE_PROGRAM BEFORE_PROFILE AFTER_PROGRAM AFTER_PROFILE [TOP]
fn compare(a : Run, b : Run, top : Int) -> Unit {
  @sys.println_out("frames measured: \{a.frames.length()} before, \{b.frames.length()} after")
  row([("a frame", 9), ("before", 10), ("after", 10), ("change", 10), ("", 7)])
  for q in [("mean", -1.0), ("p10", 0.1), ("p50", 0.5), ("p90", 0.9), ("max", 1.0)] {
    let (x, y) = if q.1 < 0.0 { (a.all(), b.all()) } else { (a.at(q.1), b.at(q.1)) }
    row([(q.0, 9), (k(x), 10), (k(y), 10), (signed(k(y - x), y - x), 10), (pct(x, y), 7)])
  }
  @sys.println_out("")
  row([
    ("kind", 9),
    ("before", 10),
    ("after", 10),
    ("change", 10),
    ("", 7),
    ("weight", 6),
    ("weighted change", 15),
  ])
  for i in 0..<kinds.length() {
    let x = a.kind(i)
    let y = b.kind(i)
    row([
      (kinds[i], 9),
      (k(x), 10),
      (k(y), 10),
      (signed(k(y - x), y - x), 10),
      (pct(x, y), 7),
      (weight(weights[i]), 6),
      (signed(k((y - x) * weights[i]), y - x), 15),
    ])
  }
  let (x, y) = (a.all(), b.all())
  row([("all", 9), (k(x), 10), (k(y), 10), (signed(k(y - x), y - x), 10), (pct(x, y), 7)])
  let (x, y) = (a.weighted(), b.weighted())
  row([("weighted", 9), (k(x), 10), (k(y), 10), (signed(k(y - x), y - x), 10), (pct(x, y), 7)])
  let (x, y) = (a.per_frame(a.apart), b.per_frame(b.apart))
  row([("apart", 9), (k(x), 10), (k(y), 10), (signed(k(y - x), y - x), 10), (pct(x, y), 7)])
  @sys.println_out(
    "(apart: not in the counts above, what the test's stand-in for the host ran, a device's host's own code; its calls \{tenths(a.per_frame(a.apart_calls))} before, \{tenths(b.per_frame(b.apart_calls))} after, each one host call above)",
  )
  @sys.println_out("")
  if a.allocs.is_empty() || b.allocs.is_empty() {
    @sys.println_out("allocations: not counted in one of them (a profile from before wasmgas counted them)")
  } else {
    row([("allocs", 9), ("before", 10), ("after", 10), ("change", 10), ("", 7)])
    let n = fn(v : Int64) { v.to_string() }
    let line = fn(name : String, x : Int64, y : Int64) {
      let d = y - x
      row([
        (name, 9),
        (n(x), 10),
        (n(y), 10),
        (if d > 0L { "+" + n(d) } else { n(d) }, 10),
        (pct(x.to_double(), y.to_double()), 7),
      ])
    }
    line("in all", sum(a.allocs), sum(b.allocs))
    line("max", quantile(a.allocs, 1.0), quantile(b.allocs, 1.0))
    line("p50", quantile(a.allocs, 0.5), quantile(b.allocs, 0.5))
    line("bytes", sum(a.alloc_bytes), sum(b.alloc_bytes))
    let none = fn(r : Run) { r.allocs.filter(fn(v) { v == 0L }).length() }
    @sys.println_out(
      "(frames with none: \{none(a)} of \{a.allocs.length()} before, \{none(b)} of \{b.allocs.length()} after)",
    )
  }
  // each function's own a frame, by its name (the two programs number them apart)
  let own_a = by_name(a)
  let own_b = by_name(b)
  let names = own_a.keys().to_array()
  for n in own_b.keys() {
    if !own_a.contains(n) {
      names.push(n)
    }
  }
  let change = fn(n : String) { own_b.get(n).unwrap_or(0.0) - own_a.get(n).unwrap_or(0.0) }
  names.sort_by(fn(p, q) { change(q).abs().compare(change(p).abs()) })
  @sys.println_out("")
  @sys.println_out("the functions whose own instructions a frame changed the most:")
  row([("", 0), ("before", 10), ("after", 10), ("change", 10)])
  for i in 0..<top.min(names.length()) {
    let n = names[i]
    let x = own_a.get(n).unwrap_or(0.0)
    let y = own_b.get(n).unwrap_or(0.0)
    if x == y {
      break
    }
    row([("", 0), (k(x), 10), (k(y), 10), (signed(k(y - x), y - x), 10), (" " + n, 0)])
  }
}

///|
fn by_name(run : Run) -> Map[String, Double] {
  let m : Map[String, Double] = {}
  for f, own in run.own {
    let n = run.name(f)
    m[n] = m.get(n).unwrap_or(0.0) + run.per_frame(own)
  }
  m
}

///|
/// Each scene's allocations held to a bar that only falls (the user, 2026-11-09: as detlint's counts): `kept` the bars,
/// a line each, `scene allocations` (all its measured frames'), `#` a comment; `runs` each scene's profile. A scene
/// over its bar or under it fails, under it with what to lower it to; one with no bar fails too. With `update`,
/// the bars written as the runs counted them, nothing failed. The count is the same every run, whatever the machine
/// (profile.mbt: the allocator's outermost calls), so a bar crossed is the code's.
fn allocs(kept : String, update : Bool, runs : Array[(String, String)]) -> Bool {
  let text = @sys.read_text(kept).unwrap_or("")
  let bars : Map[String, Int64] = {}
  let head : Array[String] = []
  for line in text.split("\n") {
    let l = line.trim(chars=" \t\r").to_string()
    if l.has_prefix("#") || l == "" {
      if bars.is_empty() && l != "" {
        head.push(l)
      }
      continue
    }
    match l.split(" ").filter(fn(p) { p != "" }).map(fn(p) { p.to_string() }).to_array() {
      [scene, n] => bars[scene] = number(n)
      _ => fail("\{kept}: not `scene allocations`: \{l}")
    }
  }
  let now : Array[(String, Int64)] = []
  for r in runs {
    let (scene, profile) = r
    let t = @sys.read_text(profile).unwrap_or("")
    let mut n : Int64? = None
    for line in t.split("\n") {
      match line.split(" ").map(fn(p) { p.to_string() }).to_array() {
        ["ALLOCS", c, _] => n = Some(number(c))
        _ => ()
      }
    }
    match n {
      Some(c) => now.push((scene, c))
      None => fail("\{profile}: no allocations counted (the run did not end, or a shell from before they were)")
    }
  }
  if update {
    for s in now {
      bars[s.0] = s.1
    }
    let sb = StringBuilder::new()
    for h in head {
      sb.write_string(h + "\n")
    }
    let names = bars.keys().to_array()
    names.sort()
    for s in names {
      sb.write_string("\{s} \{bars[s]}\n")
    }
    if !@sys.write_text(kept, sb.to_string()) {
      fail("\{kept}: cannot be written")
    }
    @sys.println_out("allocs: \{kept} written")
    return true
  }
  let mut ok = true
  for s in now {
    let (scene, n) = s
    match bars.get(scene) {
      None => {
        ok = false
        @sys.println_out("\{scene}: \{n} allocations, no bar: add it (allocs … update)")
      }
      Some(b) if n > b => {
        ok = false
        @sys.println_out(
          "\{scene}: \{n} allocations, over the bar \{b} by \{n - b}: what allocates more is in the change (instrbench.sh's report says where)",
        )
      }
      Some(b) if n < b => {
        ok = false
        @sys.println_out("\{scene}: \{n} allocations, under the bar \{b}: lower it to what is now (allocs … update), so it stays there")
      }
      Some(_) => @sys.println_out("\{scene}: \{n} allocations, the bar")
    }
  }
  ok
}
