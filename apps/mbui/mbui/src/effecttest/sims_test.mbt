///|
fn arrivals(seed : Int) -> (Array[String], Array[Int64]) {
  let rt = @effect.Runtime::new(seed~)
  // every packet is in by latency + jitter
  let latency = 20
  let jitter = 30
  let net = @effect.SimNet::new(rt, latency~, jitter~)
  let a = net.endpoint("a")
  let b = net.endpoint("b")
  let got = []
  let times = []
  ignore(
    rt.fork(async fn() {
      while true {
        let p = (b.recv)()
        got.push(p.body)
        times.push(@effect.now())
      }
    }),
  )
  for i in 0..<5 {
    (a.send)("b", "m\{i}")
  }
  rt.advance(latency + jitter)
  (got, times)
}

///|
test "SimNet: jitter from the seed reorders packets; the same seed, the same arrivals" {
  let first = arrivals(3)
  assert_eq(arrivals(3), first)
  assert_eq(first.0.length(), 5)
  // each within latency + jitter
  assert_true(first.1.iter().all(t => t >= 20L && t <= 50L))
  let mut reordered = 0
  for s in 1..=20 {
    if arrivals(s).0 != ["m0", "m1", "m2", "m3", "m4"] {
      reordered += 1
    }
  }
  assert_true(reordered > 0)
}

///|
test "SimNet: a lossy network loses packets, as the seed says" {
  let rt = @effect.Runtime::new(seed=11)
  // what is not lost is in by `latency`
  let latency = 5
  let net = @effect.SimNet::new(rt, latency~, loss=0.5)
  let a = net.endpoint("a")
  for i in 0..<40 {
    (a.send)("b", "m\{i}")
  }
  rt.advance(latency)
  let lost = net.log.filter(l => l.contains("lost")).length()
  assert_true(lost > 5 && lost < 35)
  assert_eq(net.log.length(), 40)
  assert_idle(rt)
}

///|
test "SimFiles: reads and writes take time on the clock; a full disk fails writes" {
  let rt = @effect.Runtime::new()
  // four operations one after another, each `latency`
  let latency = 3
  let ops = 4
  let sim = @effect.SimFiles::new(rt, latency~)
  let files = sim.files()
  let out = []
  ignore(
    rt.fork(async fn() {
      (files.write)("a.txt", b"hi")
      out.push("read \{(files.read)("a.txt").map(b => b.length())} at \{@effect.now()}")
      out.push("missing \{(files.read)("b.txt")}")
      sim.fail_writes(true)
      (files.write)("c.txt", b"x") catch {
        e => out.push(describe(e))
      }
    }),
  )
  rt.advance(ops * latency)
  assert_eq(out, [
    "read Some(2) at 6", "missing None", "io: no space left writing c.txt",
  ])
  assert_idle(rt)
}
