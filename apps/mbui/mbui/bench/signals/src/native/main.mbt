// js-reactivity-benchmark (github.com/transitive-bullshit/js-reactivity-benchmark at 2c273f1, 2026-09-19) on mbui's
// signals compiled natively: its five suites (kairo, mol, s, dynamic, cellx), every case with its sizes, its checks
// and its timing boundaries as src/*Bench.ts has them, the minimum of `repeats` samples after a warm-up. A suite a
// run: `native.exe <suite> [repeats]`, one JSON row a case on stdout (run.sh runs them all). Where it differs: kairo's
// mux makes an array where the benchmark makes an object; `self` checks the benchmark's adapter tests' graphs and
// counts; `mem` that what is made and let go is freed.
//
// What a JS engine's collector does outside the timed samples (explicit gc() between them), reference counting does
// as the last reference goes: what a sample made is held (Hold) until after its clock stops; a computed nothing
// watches but which read something (createComputations, updateComputations) is disposed of with the effects.

///|
extern "C" fn now_ms() -> Double = "sb_now_ms"

///|
let framework = "mbui signals (native)"

///|
let repeats : Ref[Int] = { val: 3 }

///|
/// A signal or a computed, read alike (the benchmark's `Computed<number>`, which its signals are too).
priv enum Node {
  S(@signals.Signal[Double])
  C(@signals.Computed[Double])
}

///|
fn Node::read(self : Node) -> Double {
  match self {
    S(s) => s.get()
    C(c) => c.get()
  }
}

///|
/// What a sample made, kept until its clock stopped.
priv struct Hold {
  keep : () -> Unit
}

///|
let cleanups : Array[() -> Unit] = []

///|
let loose : Array[@signals.Computed[Double]] = []

///|
fn effect(f : () -> Unit) -> Unit {
  cleanups.push(@signals.effect(f))
}

///|
/// util/cleanup.ts's dispose: the effects stopped, the last first; then the computeds nothing watched let go.
fn dispose() -> Unit {
  let pending = cleanups.copy()
  cleanups.clear()
  for i = pending.length() - 1; i >= 0; i = i - 1 {
    (pending[i])()
  }
  let free = loose.copy()
  loose.clear()
  for c in free {
    c.dispose()
  }
}

///|
fn batch(f : () -> Unit) -> Unit {
  @signals.start_batch()
  f()
  @signals.end_batch()
}

///|
fn check(ok : Bool, what : String) -> Unit {
  if !ok {
    abort("check failed: " + what)
  }
}

///|
fn[T] fastest(times : Int, run : () -> T, after : (T) -> Unit) -> Array[Double] {
  let samples : Array[Double] = []
  for _ in 0..<times {
    let t0 = now_ms()
    let r = run()
    let t1 = now_ms()
    samples.push(t1 - t0)
    after(r)
  }
  samples
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
fn log(suite : String, test_name : String, samples : Array[Double]) -> Unit {
  let mut min = samples[0]
  for s in samples {
    if s < min {
      min = s
    }
  }
  let list = samples.map(fn(s) { s.to_string() })
  println(
    "{\"framework\":\{json_string(framework)},\"suite\":\{json_string(suite)},\"test\":\{json_string(test_name)},\"timeMs\":\{min},\"samplesMs\":[\{list.join(",")}]}",
  )
}

// ── kairo (src/kairo/*.ts, src/kairoBench.ts) ───────────────────────────────────────────────────────────────

///|
fn busy() -> Unit {
  let mut a = 0
  for _ in 0..<100 {
    a += 1
  }
  ignore(a)
}

///|
fn kairo_avoidable() -> () -> Unit {
  let head = @signals.signal(0.0)
  let computed1 = @signals.computed(fn(_) { head.get() })
  let computed2 = @signals.computed(fn(_) {
    ignore(computed1.get())
    0.0
  })
  let computed3 = @signals.computed(fn(_) {
    busy()
    computed2.get() + 1.0
  })
  let computed4 = @signals.computed(fn(_) { computed3.get() + 2.0 })
  let computed5 = @signals.computed(fn(_) { computed4.get() + 3.0 })
  effect(fn() {
    ignore(computed5.get())
    busy()
  })
  fn() {
    batch(fn() { head.set(1.0) })
    check(computed5.get() == 6.0, "avoidable")
    for i in 0..<1000 {
      batch(fn() { head.set(i.to_double()) })
      check(computed5.get() == 6.0, "avoidable")
    }
  }
}

///|
fn kairo_broad() -> () -> Unit {
  let head = @signals.signal(0.0)
  let mut last = S(head)
  let calls : Ref[Int] = { val: 0 }
  for i in 0..<50 {
    let current = @signals.computed(fn(_) { head.get() + i.to_double() })
    let current2 = @signals.computed(fn(_) { current.get() + 1.0 })
    effect(fn() {
      ignore(current2.get())
      calls.val += 1
    })
    last = C(current2)
  }
  let last = last
  fn() {
    batch(fn() { head.set(1.0) })
    calls.val = 0
    for i in 0..<50 {
      batch(fn() { head.set(i.to_double()) })
      check(last.read() == (i + 50).to_double(), "broad")
    }
  }
}

///|
fn kairo_deep() -> () -> Unit {
  let len = 50
  let head = @signals.signal(0.0)
  let mut current = S(head)
  for _ in 0..<len {
    let c = current
    current = C(@signals.computed(fn(_) { c.read() + 1.0 }))
  }
  let current = current
  let calls : Ref[Int] = { val: 0 }
  effect(fn() {
    ignore(current.read())
    calls.val += 1
  })
  fn() {
    batch(fn() { head.set(1.0) })
    calls.val = 0
    for i in 0..<50 {
      batch(fn() { head.set(i.to_double()) })
      check(current.read() == (len + i).to_double(), "deep")
    }
  }
}

///|
fn kairo_diamond() -> () -> Unit {
  let width = 5
  let head = @signals.signal(0.0)
  let current = []
  for _ in 0..<width {
    current.push(@signals.computed(fn(_) { head.get() + 1.0 }))
  }
  let sum = @signals.computed(fn(_) {
    current.map(fn(x) { x.get() }).fold(init=0.0, fn(a, b) { a + b })
  })
  let calls : Ref[Int] = { val: 0 }
  effect(fn() {
    ignore(sum.get())
    calls.val += 1
  })
  fn() {
    batch(fn() { head.set(1.0) })
    check(sum.get() == (2 * width).to_double(), "diamond")
    calls.val = 0
    for i in 0..<500 {
      batch(fn() { head.set(i.to_double()) })
      check(sum.get() == ((i + 1) * width).to_double(), "diamond")
    }
  }
}

///|
fn kairo_mux() -> () -> Unit {
  let heads = []
  for _ in 0..<100 {
    heads.push(@signals.signal(0.0))
  }
  let mux = @signals.computed(fn(_) { heads.map(fn(h) { h.get() }) })
  let split = []
  for index in 0..<heads.length() {
    split.push(@signals.computed(fn(_) { mux.get()[index] }))
  }
  let splited = split.map(fn(x) { @signals.computed(fn(_) { x.get() + 1.0 }) })
  for x in splited {
    effect(fn() { ignore(x.get()) })
  }
  fn() {
    for i in 0..<10 {
      batch(fn() { heads[i].set(i.to_double()) })
      check(splited[i].get() == (i + 1).to_double(), "mux")
    }
    for i in 0..<10 {
      batch(fn() { heads[i].set((i * 2).to_double()) })
      check(splited[i].get() == (i * 2 + 1).to_double(), "mux")
    }
  }
}

///|
fn kairo_repeated() -> () -> Unit {
  let size = 30
  let head = @signals.signal(0.0)
  let current = @signals.computed(fn(_) {
    let mut result = 0.0
    for _ in 0..<size {
      result += head.get()
    }
    result
  })
  let calls : Ref[Int] = { val: 0 }
  effect(fn() {
    ignore(current.get())
    calls.val += 1
  })
  fn() {
    batch(fn() { head.set(1.0) })
    check(current.get() == size.to_double(), "repeated")
    calls.val = 0
    for i in 0..<100 {
      batch(fn() { head.set(i.to_double()) })
      check(current.get() == (i * size).to_double(), "repeated")
    }
  }
}

///|
fn count_to(n : Int) -> Double {
  let list = []
  for i in 0..<n {
    list.push(i + 1)
  }
  list.fold(init=0, fn(x, y) { x + y }).to_double()
}

///|
fn kairo_triangle() -> () -> Unit {
  let width = 10
  let head = @signals.signal(0.0)
  let mut current = S(head)
  let list : Array[Node] = []
  for _ in 0..<width {
    let c = current
    list.push(current)
    current = C(@signals.computed(fn(_) { c.read() + 1.0 }))
  }
  let sum = @signals.computed(fn(_) {
    list.map(fn(x) { x.read() }).fold(init=0.0, fn(a, b) { a + b })
  })
  let calls : Ref[Int] = { val: 0 }
  effect(fn() {
    ignore(sum.get())
    calls.val += 1
  })
  fn() {
    let constant = count_to(width)
    batch(fn() { head.set(1.0) })
    check(sum.get() == constant, "triangle")
    calls.val = 0
    for i in 0..<100 {
      batch(fn() { head.set(i.to_double()) })
      check(
        sum.get() == constant - width.to_double() + (i * width).to_double(),
        "triangle",
      )
    }
  }
}

///|
fn odd(x : Double) -> Bool {
  x.to_int() % 2 != 0
}

///|
fn kairo_unstable() -> () -> Unit {
  let head = @signals.signal(0.0)
  let twice = @signals.computed(fn(_) { head.get() * 2.0 })
  let inverse = @signals.computed(fn(_) { -head.get() })
  let current = @signals.computed(fn(_) {
    let mut result = 0.0
    for _ in 0..<20 {
      result += if odd(head.get()) { twice.get() } else { inverse.get() }
    }
    result
  })
  let calls : Ref[Int] = { val: 0 }
  effect(fn() {
    ignore(current.get())
    calls.val += 1
  })
  fn() {
    batch(fn() { head.set(1.0) })
    check(current.get() == 40.0, "unstable")
    calls.val = 0
    for i in 0..<100 {
      batch(fn() { head.set(i.to_double()) })
      let want = if i % 2 != 0 { i * 40 } else { -(i * 20) }
      check(current.get() == want.to_double(), "unstable")
    }
  }
}

///|
fn kairo_bench() -> Unit {
  let cases : Array[(String, () -> () -> Unit)] = [
    ("avoidablePropagation", kairo_avoidable),
    ("broadPropagation", kairo_broad),
    ("deepPropagation", kairo_deep),
    ("diamond", kairo_diamond),
    ("mux", kairo_mux),
    ("repeatedObservers", kairo_repeated),
    ("triangle", kairo_triangle),
    ("unstable", kairo_unstable),
  ]
  for entry in cases {
    let (name, make) = entry
    let iter = make()
    iter()
    let samples = fastest(
      repeats.val,
      fn() {
        for _ in 0..<1000 {
          iter()
        }
      },
      fn(_) {  },
    )
    dispose()
    log("kairo", name, samples)
  }
}

// ── mol (src/molBench.ts) ─────────────────────────────────────────────────────────────────────────────────────

///|
fn fib(n : Int) -> Int {
  if n < 2 {
    1
  } else {
    fib(n - 1) + fib(n - 2)
  }
}

///|
fn hard(n : Int) -> Int {
  n + fib(16)
}

///|
priv struct MolX {
  x : Int
}

///|
fn mol_bench() -> Unit {
  let numbers = [0, 1, 2, 3, 4]
  let observed_h : Ref[Int] = { val: 0 }
  let observed_g : Ref[Int] = { val: 0 }
  let observed_j : Ref[Int] = { val: 0 }
  let a = @signals.signal(0)
  let b = @signals.signal(0)
  let c = @signals.computed(fn(_) { a.get() % 2 + b.get() % 2 })
  let d = @signals.computed(fn(_) {
    numbers.map(fn(i) { MolX::{ x: i + a.get() % 2 - b.get() % 2 } })
  })
  let e = @signals.computed(fn(_) { hard(c.get() + a.get() + d.get()[0].x) })
  let f = @signals.computed(fn(_) {
    let x = d.get()[2].x
    hard(if x != 0 { x } else { b.get() })
  })
  let g = @signals.computed(fn(_) {
    let c1 = c.get()
    let c2 = c.get()
    let either = if c2 != 0 { c2 } else { e.get() % 2 }
    c1 + either + d.get()[4].x + f.get()
  })
  effect(fn() { observed_h.val = hard(g.get()) })
  effect(fn() { observed_g.val = g.get() })
  effect(fn() { observed_j.val = hard(f.get()) })
  let iter = fn(i : Int) {
    batch(fn() {
      b.set(1)
      a.set(1 + i * 2)
    })
    batch(fn() {
      a.set(2 + i * 2)
      b.set(2)
    })
  }
  let verify = fn() {
    check(
      observed_h.val == 3201 && observed_g.val == 1604 && observed_j.val == 3196,
      "molBench",
    )
  }
  iter(1)
  verify()
  let samples = fastest(
    repeats.val,
    fn() {
      for i in 0..<10000 {
        iter(i)
      }
    },
    fn(_) { verify() },
  )
  dispose()
  log("mol", "molBench", samples)
}

// ── s (src/sBench.ts) ─────────────────────────────────────────────────────────────────────────────────────────

///|
fn imax(a : Int, b : Int) -> Int {
  if a > b {
    a
  } else {
    b
  }
}

///|
fn s_report(name : String, run : () -> (Double, Hold), expected : Double) -> Unit {
  let verify = fn(r : (Double, Hold)) {
    check(r.0 == expected, name)
    dispose()
    (r.1.keep)()
  }
  verify(run())
  let samples = fastest(repeats.val, run, verify)
  log("s", name, samples)
}

///|
fn s_bench() -> Unit {
  let count = 100000
  let shapes = [
    (0, 1),
    (1, 1),
    (2, 1),
    (4, 1),
    (1000, 1),
    (1, 2),
    (1, 4),
    (1, 8),
    (1, 1000),
  ]
  s_report(
    "createDataSignals",
    fn() {
      let signals = []
      for i in 0..<count {
        signals.push(@signals.signal(i.to_double()))
      }
      let sum = signals.fold(init=0.0, fn(sum, s) { sum + s.get() })
      (sum, { keep: fn() { ignore(signals) } })
    },
    count.to_double() * (count - 1).to_double() / 2.0,
  )
  for shape in shapes {
    let (inputs, outputs) = shape
    let groups = imax(1, count / imax(inputs, outputs))
    s_report(
      "createComputations\{inputs}to\{outputs}",
      fn() {
        let sources = []
        for _ in 0..<(groups * inputs) {
          sources.push(@signals.signal(1.0))
        }
        let mut sum = 0.0
        for group in 0..<groups {
          for _ in 0..<outputs {
            let computed = @signals.computed(fn(_) {
              let mut value = 0.0
              for input in 0..<inputs {
                value += sources[group * inputs + input].get()
              }
              value
            })
            sum += computed.get()
            loose.push(computed)
          }
        }
        (sum, { keep: fn() { ignore(sources) } })
      },
      (groups * outputs * inputs).to_double(),
    )
  }
  for shape in shapes {
    let (inputs, outputs) = shape
    if inputs == 0 || outputs == 8 {
      continue
    }
    let name = "updateComputations\{inputs}to\{outputs}"
    let writes = imax(2, count * 4 / imax(inputs, outputs))
    let setup = fn() -> (Array[@signals.Signal[Double]], Array[@signals.Computed[Double]]) {
      let sources = []
      for _ in 0..<inputs {
        sources.push(@signals.signal(1.0))
      }
      let leaves = []
      for _ in 0..<outputs {
        let leaf = @signals.computed(fn(_) {
          sources.fold(init=0.0, fn(sum, source) { sum + source.get() })
        })
        loose.push(leaf)
        leaves.push(leaf)
      }
      for leaf in leaves {
        ignore(leaf.get())
      }
      (sources, leaves)
    }
    let run = fn(
      sources : Array[@signals.Signal[Double]],
      leaves : Array[@signals.Computed[Double]],
    ) -> Double {
      let mut sum = 0.0
      for i in 0..<writes {
        batch(fn() { sources[0].set(i.to_double()) })
        for leaf in leaves {
          sum += leaf.get()
        }
      }
      sum
    }
    let w = writes.to_double()
    let expected = outputs.to_double() *
      (w * (w - 1.0) / 2.0 + w * (inputs - 1).to_double())
    let (s0, l0) = setup()
    check(run(s0, l0) == expected, name)
    dispose()
    let samples = []
    for _ in 0..<repeats.val {
      let (sources, leaves) = setup()
      let t0 = now_ms()
      let actual = run(sources, leaves)
      let t1 = now_ms()
      samples.push(t1 - t0)
      check(actual == expected, name)
      dispose()
    }
    log("s", name, samples)
  }
}

// ── dynamic (src/dynamicBench.ts, src/util/dependencyGraph.ts, src/config.ts) ───────────────────────────────

///|
/// The `random` package's (5.5.1) Random("seed"): xoshiro128** seeded by cyrb128.
priv struct Rng {
  mut s0 : UInt
  mut s1 : UInt
  mut s2 : UInt
  mut s3 : UInt
}

///|
fn Rng::new(seed : String) -> Rng {
  let mut s0 = 1779033703U
  let mut s1 = 3144134277U
  let mut s2 = 1013904242U
  let mut s3 = 2773480762U
  for ch in seed {
    let code = ch.to_int().reinterpret_as_uint()
    s0 = s1 ^ ((s0 ^ code) * 597399067U)
    s1 = s2 ^ ((s1 ^ code) * 2869860233U)
    s2 = s3 ^ ((s2 ^ code) * 951274213U)
    s3 = s0 ^ ((s3 ^ code) * 2716044179U)
  }
  s0 = (s2 ^ (s0 >> 18)) * 597399067U
  s1 = (s3 ^ (s1 >> 22)) * 2869860233U
  s2 = (s0 ^ (s2 >> 17)) * 951274213U
  s3 = (s1 ^ (s3 >> 19)) * 2716044179U
  s0 = s0 ^ (s1 ^ s2 ^ s3)
  s1 = s1 ^ s0
  s2 = s2 ^ s0
  s3 = s3 ^ s0
  { s0, s1, s2, s3 }
}

///|
fn rotl(v : UInt, s : Int) -> UInt {
  (v << s) | (v >> (32 - s))
}

///|
fn Rng::next_u32(self : Rng) -> UInt {
  let result = rotl(self.s1 * 5U, 7) * 9U
  let t = self.s1 << 9
  self.s2 = self.s2 ^ self.s0
  self.s3 = self.s3 ^ self.s1
  self.s1 = self.s1 ^ self.s2
  self.s0 = self.s0 ^ self.s3
  self.s2 = self.s2 ^ t
  self.s3 = rotl(self.s3, 11)
  result
}

///|
fn Rng::next(self : Rng) -> Double {
  let high = self.next_u32() >> 5
  let low = self.next_u32() >> 6
  (high.reinterpret_as_int().to_double() * 67108864.0 +
  low.reinterpret_as_int().to_double()) /
  9007199254740992.0
}

///|
priv struct Config {
  name : String
  width : Int
  total_layers : Int
  static_fraction : Double
  n_sources : Int
  read_fraction : Double
  iterations : Int
  expected_sum : Double
  expected_count : Int
}

///|
fn make_row(
  sources : Array[Node],
  counter : Ref[Int],
  static_fraction : Double,
  n_sources : Int,
  rand : Rng,
) -> Array[Node] {
  let n = sources.length()
  let row = []
  for my_dex in 0..<n {
    let my_sources = []
    for source_dex in 0..<n_sources {
      my_sources.push(sources[(my_dex + source_dex) % n])
    }
    let static_node = rand.next() < static_fraction
    if static_node {
      row.push(
        C(
          @signals.computed(fn(_) {
            counter.val += 1
            let mut sum = 0.0
            for src in my_sources {
              sum += src.read()
            }
            sum
          }),
        ),
      )
    } else {
      let first = my_sources[0]
      let tail = my_sources[1:].to_owned()
      row.push(
        C(
          @signals.computed(fn(_) {
            counter.val += 1
            let mut sum = first.read()
            let v = sum.to_int64()
            let should_drop = (v & 1L) != 0L
            let drop_dex = (v % tail.length().to_int64()).to_int()
            for i in 0..<tail.length() {
              if should_drop && i == drop_dex {
                continue
              }
              sum += tail[i].read()
            }
            sum
          }),
        ),
      )
    }
  }
  row
}

///|
fn make_graph(
  config : Config,
  counter : Ref[Int],
) -> (Array[@signals.Signal[Double]], Array[Array[Node]]) {
  let sources = []
  for i in 0..<config.width {
    sources.push(@signals.signal(i.to_double()))
  }
  let rand = Rng::new("seed")
  let rows : Array[Array[Node]] = []
  let mut prev = sources.map(fn(s) { S(s) })
  for _ in 0..<(config.total_layers - 1) {
    let row = make_row(
      prev,
      counter,
      config.static_fraction,
      config.n_sources,
      rand,
    )
    rows.push(row)
    prev = row
  }
  (sources, rows)
}

///|
fn run_graph(
  sources : Array[@signals.Signal[Double]],
  layers : Array[Array[Node]],
  iterations : Int,
  read_fraction : Double,
) -> Double {
  let rand = Rng::new("seed")
  let leaves = layers[layers.length() - 1]
  let skip = (leaves.length().to_double() * (1.0 - read_fraction) + 0.5)
    .floor()
    .to_int()
  let read_leaves = leaves.copy()
  for _ in 0..<skip {
    let rm = (rand.next() * read_leaves.length().to_double()).floor().to_int()
    ignore(read_leaves.remove(rm))
  }
  for leaf in read_leaves {
    effect(fn() { ignore(leaf.read()) })
  }
  for i in 0..<iterations {
    batch(fn() {
      let source_dex = i % sources.length()
      sources[source_dex].set((i + source_dex).to_double())
      for leaf in read_leaves {
        ignore(leaf.read())
      }
    })
  }
  read_leaves.fold(init=0.0, fn(total, leaf) { leaf.read() + total })
}

///|
fn title(config : Config) -> String {
  let dynamic = if config.static_fraction < 1.0 { " - dynamic" } else { "" }
  let read = if config.read_fraction < 1.0 {
    " - read \{(config.read_fraction * 100.0 + 0.5).floor().to_int()}%"
  } else {
    ""
  }
  "\{config.width}x\{config.total_layers} - \{config.n_sources} sources\{dynamic}\{read} (\{config.name})"
}

///|
fn run_once(config : Config) -> (Double, Int, Hold) {
  let counter : Ref[Int] = { val: 0 }
  let (sources, layers) = make_graph(config, counter)
  let sum = run_graph(sources, layers, config.iterations, config.read_fraction)
  (sum, counter.val, { keep: fn() { ignore((sources, layers)) } })
}

///|
fn dynamic_bench() -> Unit {
  let configs : Array[Config] = [
    {
      name: "simple component",
      width: 10,
      total_layers: 5,
      static_fraction: 1.0,
      n_sources: 2,
      read_fraction: 0.2,
      iterations: 600000,
      expected_sum: 19199828.0,
      expected_count: -1,
    },
    {
      name: "dynamic component",
      width: 10,
      total_layers: 10,
      static_fraction: 3.0 / 4.0,
      n_sources: 6,
      read_fraction: 0.2,
      iterations: 15000,
      expected_sum: 302310477860.0,
      expected_count: -1,
    },
    {
      name: "large web app",
      width: 1000,
      total_layers: 12,
      static_fraction: 0.95,
      n_sources: 4,
      read_fraction: 1.0,
      iterations: 7000,
      expected_sum: 29355933696000.0,
      expected_count: -1,
    },
    {
      name: "wide dense",
      width: 1000,
      total_layers: 5,
      static_fraction: 1.0,
      n_sources: 25,
      read_fraction: 1.0,
      iterations: 3000,
      expected_sum: 1171484375000.0,
      expected_count: -1,
    },
    {
      name: "deep",
      width: 5,
      total_layers: 500,
      static_fraction: 1.0,
      n_sources: 3,
      read_fraction: 1.0,
      iterations: 500,
      expected_sum: 3.0239642676898464e241,
      expected_count: -1,
    },
  ]
  for config in configs {
    let name = title(config)
    let verify = fn(r : (Double, Int, Hold)) {
      check(r.0 == config.expected_sum, "\{name}: sum \{r.0}")
      dispose()
      (r.2.keep)()
    }
    verify(run_once(config))
    let samples = fastest(repeats.val, fn() { run_once(config) }, verify)
    log("dynamic", name, samples)
  }
}

///|
/// frameworks.test.ts's graphs and the smoke graph: the sums and how many times the computeds ran (alien-signals'
/// counts, testPullCounts).
fn self_test() -> Unit {
  let graphs : Array[(Config, Int)] = [
    (
      {
        name: "smoke graph",
        width: 3,
        total_layers: 3,
        static_fraction: 1.0,
        n_sources: 2,
        read_fraction: 1.0,
        iterations: 2,
        expected_sum: 16.0,
        expected_count: 11,
      },
      0,
    ),
    (
      {
        name: "static graph, read 2/3 of leaves",
        width: 3,
        total_layers: 3,
        static_fraction: 1.0,
        n_sources: 2,
        read_fraction: 2.0 / 3.0,
        iterations: 10,
        expected_sum: 73.0,
        expected_count: 41,
      },
      0,
    ),
    (
      {
        name: "dynamic graph",
        width: 4,
        total_layers: 2,
        static_fraction: 0.5,
        n_sources: 2,
        read_fraction: 1.0,
        iterations: 10,
        expected_sum: 72.0,
        expected_count: 22,
      },
      0,
    ),
  ]
  for g in graphs {
    let config = g.0
    let (sum, count, _) = run_once(config)
    check(
      sum == config.expected_sum && count == config.expected_count,
      "\{config.name}: sum \{sum} count \{count}",
    )
    dispose()
  }
}

// ── cellx (src/cellxBench.ts) ─────────────────────────────────────────────────────────────────────────────────

///|
priv struct Props {
  p1 : Node
  p2 : Node
  p3 : Node
  p4 : Node
}

///|
fn cellx(layers : Int) -> (Double, Array[Double], Array[Double]) {
  let start1 = @signals.signal(1.0)
  let start2 = @signals.signal(2.0)
  let start3 = @signals.signal(3.0)
  let start4 = @signals.signal(4.0)
  let mut layer : Props = { p1: S(start1), p2: S(start2), p3: S(start3), p4: S(start4) }
  for _ in 0..<layers {
    let m = layer
    let s : Props = {
      p1: C(@signals.computed(fn(_) { m.p2.read() })),
      p2: C(@signals.computed(fn(_) { m.p1.read() - m.p3.read() })),
      p3: C(@signals.computed(fn(_) { m.p2.read() + m.p4.read() })),
      p4: C(@signals.computed(fn(_) { m.p3.read() })),
    }
    effect(fn() { ignore(s.p1.read()) })
    effect(fn() { ignore(s.p2.read()) })
    effect(fn() { ignore(s.p3.read()) })
    effect(fn() { ignore(s.p4.read()) })
    ignore(s.p1.read())
    ignore(s.p2.read())
    ignore(s.p3.read())
    ignore(s.p4.read())
    layer = s
  }
  let end = layer
  let t0 = now_ms()
  let before = [end.p1.read(), end.p2.read(), end.p3.read(), end.p4.read()]
  batch(fn() {
    start1.set(4.0)
    start2.set(3.0)
    start3.set(2.0)
    start4.set(1.0)
  })
  let after = [end.p1.read(), end.p2.read(), end.p3.read(), end.p4.read()]
  let t1 = now_ms()
  (t1 - t0, before, after)
}

///|
fn cellx_reference(depth : Int, initial : Array[Double]) -> Array[Double] {
  let mut a = initial[0]
  let mut b = initial[1]
  let mut c = initial[2]
  let mut d = initial[3]
  for _ in 0..<depth {
    let (na, nb, nc, nd) = (b, a - c, b + d, c)
    a = na
    b = nb
    c = nc
    d = nd
  }
  [a, b, c, d]
}

///|
fn cellx_bench() -> Unit {
  for layers in [10, 20, 30] {
    let want_before = cellx_reference(layers, [1.0, 2.0, 3.0, 4.0])
    let want_after = cellx_reference(layers, [4.0, 3.0, 2.0, 1.0])
    let verify = fn(before : Array[Double], after : Array[Double]) {
      check(before == want_before, "CellX \{layers}: wrong initial values")
      check(after == want_after, "CellX \{layers}: wrong updated values")
    }
    let (_, wb, wa) = cellx(layers)
    verify(wb, wa)
    dispose()
    let samples = []
    for _ in 0..<repeats.val {
      let (elapsed, before, after) = cellx(layers)
      verify(before, after)
      samples.push(elapsed)
      dispose()
    }
    log("cellx", "cellx\{layers}", samples)
  }
}

// ── mem: what is made and let go is freed (reference counting frees nothing left in a cycle) ───────────────

///|
extern "C" fn rss_mb() -> Double = "sb_rss_mb"

///|
/// One round of making and letting go: every kairo graph, a dynamic one, computeds read outside an effect and
/// disposed of (as Kept and Derived do), signals and computeds made and dropped unread, a CellX graph.
fn mem_round() -> Unit {
  let makers = [
    kairo_avoidable, kairo_broad, kairo_deep, kairo_diamond, kairo_mux, kairo_repeated,
    kairo_triangle, kairo_unstable,
  ]
  for make in makers {
    let iter = make()
    iter()
    dispose()
  }
  let config : Config = {
    name: "mem",
    width: 100,
    total_layers: 6,
    static_fraction: 0.75,
    n_sources: 4,
    read_fraction: 1.0,
    iterations: 200,
    expected_sum: 0.0,
    expected_count: -1,
  }
  ignore(run_once(config))
  dispose()
  let s = @signals.signal(1.0)
  for _ in 0..<2000 {
    let c = @signals.computed(fn(_) { s.get() + 1.0 })
    ignore(c.get())
    c.dispose()
  }
  for _ in 0..<2000 {
    ignore(@signals.signal(0.0))
    ignore(@signals.computed(fn(_) { 1.0 }))
  }
  ignore(cellx(30))
  dispose()
}

///|
fn mem_bench() -> Unit {
  for _ in 0..<20 {
    mem_round()
  }
  let before = rss_mb()
  for _ in 0..<300 {
    mem_round()
  }
  let after = rss_mb()
  println(
    "{\"framework\":\{json_string(framework)},\"suite\":\"mem\",\"beforeMB\":\{before},\"afterMB\":\{after}}",
  )
  check(after - before < 1.0, "memory grew from \{before} MB to \{after} MB over 300 rounds")
}

///|
fn parse_count(s : String, default : Int) -> Int {
  let mut n = 0
  for c in s {
    if c < '0' || c > '9' {
      return default
    }
    n = n * 10 + (c.to_int() - '0'.to_int())
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
  let suite = if args.length() > 1 { args[1] } else { "all" }
  if args.length() > 2 {
    repeats.val = parse_count(args[2], 3)
  }
  self_test()
  match suite {
    "self" => println("self test passed")
    "kairo" => kairo_bench()
    "mol" => mol_bench()
    "s" => s_bench()
    "dynamic" => dynamic_bench()
    "cellx" => cellx_bench()
    "mem" => mem_bench()
    _ => {
      kairo_bench()
      mol_bench()
      s_bench()
      dynamic_bench()
      cellx_bench()
    }
  }
}
