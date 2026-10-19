///|
test "without a seed, ready fibers run in the order they became ready" {
  let rt = @effect.Runtime::new()
  let seen = []
  for i in 0..<5 {
    ignore(rt.fork(() => seen.push(i)))
  }
  ignore(rt.run_ready())
  assert_eq(seen, [0, 1, 2, 3, 4])
}

///|
fn order(seed : Int) -> Array[Int] raise {
  let rt = @effect.Runtime::new(seed~)
  let seen = []
  for i in 0..<6 {
    ignore(
      rt.fork(async fn() {
        seen.push(i)
        @effect.pause()
        seen.push(i + 10)
      }),
    )
  }
  assert_true(rt.settle())
  seen
}

///|
test "a seed draws which ready fiber runs next; the same seed, the same order" {
  let first = order(7)
  assert_eq(order(7), first)
  let mut other = 0
  for s in 1..=20 {
    if order(s) != order(1) {
      other += 1
    }
  }
  // the seeds try different interleavings
  assert_true(other > 10)
}

///|
test "sleep waits on the virtual clock: advance fires each timer at its time" {
  let rt = @effect.Runtime::new()
  let woke : Array[Int64] = []
  ignore(
    rt.fork(async fn() {
      @effect.sleep(100)
      woke.push(@effect.now())
    }),
  )
  ignore(
    rt.fork(async fn() {
      @effect.sleep(50)
      woke.push(@effect.now())
      @effect.sleep(100)
      woke.push(@effect.now())
    }),
  )
  rt.advance(99)
  assert_eq(woke, [50L])
  rt.advance(1)
  assert_eq(woke, [50L, 100L])
  // a long way on, at once: nothing waits for real time
  rt.advance(1_000_000_000)
  assert_eq(woke, [50L, 100L, 150L])
  assert_eq(rt.now(), 1_000_000_100L)
}

///|
test "settle runs from timer to timer until nothing is left" {
  let rt = @effect.Runtime::new(start=1000L)
  let n = Ref(0)
  ignore(
    rt.fork(async fn() {
      for _ in 0..<5 {
        @effect.sleep(30_000)
        n.val += 1
      }
    }),
  )
  assert_true(rt.settle())
  assert_eq(n.val, 5)
  assert_eq(rt.now(), 151_000L)
  // a fiber that sleeps for ever: settle stops at its limit
  ignore(rt.fork(async fn() { while true { @effect.sleep(1000) } }))
  assert_true(!rt.settle(max_ms=10_000))
}

///|
test "on the host's clock: the host ticks, a callback's answer wakes the fiber" {
  let clock = Ref(5000L)
  let rt = @effect.Runtime::live(() => clock.val)
  let wakes = Ref(0)
  rt.on_wake(() => wakes.val += 1)
  let pending : Array[(Result[String, Error]) -> Unit] = []
  let f = rt.fork(async fn() {
    let a = @effect.host_call(done => pending.push(done))
    @effect.sleep(100)
    a + "!"
  })
  // forked from outside a turn: the host is told to tick
  assert_eq(wakes.val, 1)
  rt.tick()
  assert_eq(pending.length(), 1)
  assert_eq(rt.next_timer(), None)
  // the host's callback, later, on its own thread's turn
  (pending[0])(Ok("answer"))
  assert_eq(wakes.val, 2)
  rt.tick()
  assert_eq(rt.next_timer(), Some(5100L))
  clock.val = 5099L
  rt.tick()
  assert_eq(outcome(f), "running")
  clock.val = 5100L
  rt.tick()
  assert_eq(outcome(f), "ok answer!")
}

///|
test "a host call interrupted before its answer tells the host to stop" {
  let rt = @effect.Runtime::new()
  let cancelled = Ref(false)
  let f : @effect.Fiber[Int] = rt.fork(async fn() {
    @effect.host_call(_ => (), cancel=() => cancelled.val = true)
  })
  ignore(rt.run_ready())
  f.interrupt()
  ignore(rt.run_ready())
  assert_true(cancelled.val)
  assert_eq(outcome(f), "interrupted")
}

///|
test "a fiber of the root scope that fails is a defect, told and kept" {
  let rt = @effect.Runtime::new()
  ignore(rt.fork(async fn() -> Unit { raise Broke("lost") }))
  ignore(rt.run_ready())
  assert_eq(rt.defects.length(), 1)
}

///|
test "shutdown interrupts everything and runs every finalizer" {
  let rt = @effect.Runtime::new()
  let log = []
  for i in 0..<3 {
    ignore(
      rt.fork(async fn() {
        defer log.push("fiber \{i} cleaned up")
        @effect.sleep(1000)
      }),
    )
  }
  rt.root().add_finalizer(() => log.push("root finalizer"))
  rt.advance(10)
  rt.shutdown()
  ignore(rt.run_ready())
  assert_eq(log, [
    "fiber 0 cleaned up", "fiber 1 cleaned up", "fiber 2 cleaned up", "root finalizer",
  ])
  assert_true(rt.settle())
}

///|
test "the seeded random draws the same on every backend" {
  let r = @effect.Rng::new(42)
  let a = Array::makei(5, _ => r.below(1000))
  let r2 = @effect.Rng::new(42)
  assert_eq(Array::makei(5, _ => r2.below(1000)), a)
  inspect(a, content=(
    #|[791, 314, 751, 389, 144]
  ))
  for _ in 0..<1000 {
    let x = r.between(3, 7)
    assert_true(x >= 3 && x <= 7)
  }
}

///|
test "seeds: 1 to n, or only SEED when the environment says one" {
  let s = @effect.seeds(count=4)
  assert_true(s == [1, 2, 3, 4] || s.length() == 1)
}
