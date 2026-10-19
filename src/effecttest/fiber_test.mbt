///|
test "join gives the value, raises the failure, and Interrupt for an interrupted fiber" {
  let rt = @effect.Runtime::new()
  let out = []
  ignore(
    rt.fork(() => @effect.scoped(s => {
      let a = s.fork(async fn() {
        @effect.sleep(5)
        1
      })
      let b : @effect.Fiber[Int] = s.fork(async fn() {
        @effect.sleep(5)
        raise Broke("b broke")
      })
      let c = s.fork(async fn() {
        @effect.sleep(50)
        3
      })
      out.push("a \{a.join()}")
      out.push(b.join().to_string()) catch {
        e => out.push("b: \{describe(e)}")
      }
      c.interrupt()
      out.push(c.join().to_string()) catch {
        e => out.push("c: \{describe(e)}")
      }
    })),
  )
  assert_true(rt.settle())
  assert_eq(out, ["a 1", "b: b broke", "c: interrupted"])
  assert_eq(rt.now(), 5L)
}

///|
test "interrupted before it ever ran, a fiber never runs" {
  let rt = @effect.Runtime::new()
  let ran = Ref(false)
  let f = rt.fork(() => ran.val = true)
  f.interrupt()
  ignore(rt.run_ready())
  assert_true(!ran.val)
  assert_eq(outcome(f), "interrupted")
}

///|
test "interrupt_and_wait waits until its finalizers have run" {
  let rt = @effect.Runtime::new()
  let log = []
  ignore(
    rt.fork(async fn() {
      let rt2 = @effect.runtime()
      let f = rt2.fork(async fn() {
        defer log.push("victim: finalizer done")
        @effect.uninterruptible(() => @effect.sleep(30))
        @effect.sleep(1000)
      })
      @effect.sleep(10)
      let exit = f.interrupt_and_wait()
      log.push("killer: \{exit is Interrupted} at \{@effect.now()}")
    }),
  )
  assert_true(rt.settle())
  assert_eq(log, ["victim: finalizer done", "killer: true at 30"])
}

///|
test "race_first: the first to end wins; the other is interrupted, its finalizers run" {
  let rt = @effect.Runtime::new()
  let log = []
  let f = rt.fork(() => @effect.race_first(
    async fn() {
      defer log.push("slow cleaned up")
      @effect.sleep(100)
      log.push("slow woke (wrong)")
      "slow"
    },
    async fn() {
      @effect.sleep(10)
      "fast"
    },
  ))
  assert_true(rt.settle())
  assert_eq(log, ["slow cleaned up"])
  assert_eq(outcome(f), "ok fast")
  // the loser's timer went with it
  assert_eq(rt.now(), 10L)
}

///|
test "race_first: a failure that comes first is the answer" {
  let rt = @effect.Runtime::new()
  let f : @effect.Fiber[String] = rt.fork(() => @effect.race_first(
    async fn() {
      @effect.sleep(5)
      raise Broke("first broke")
    },
    async fn() {
      @effect.sleep(10)
      "late"
    },
  ))
  assert_true(rt.settle())
  assert_eq(outcome(f), "failed: first broke")
}

///|
test "race: the first success wins, a failure leaves it to the other; both failing says both" {
  let rt = @effect.Runtime::new()
  let one : @effect.Fiber[String] = rt.fork(() => @effect.race(
    async fn() {
      @effect.sleep(5)
      raise Broke("first broke")
    },
    async fn() {
      @effect.sleep(10)
      "late but fine"
    },
  ))
  let both : @effect.Fiber[String] = rt.fork(() => @effect.race(
    async fn() {
      @effect.sleep(7)
      raise Broke("a broke")
    },
    async fn() {
      @effect.sleep(3)
      raise Broke("b broke")
    },
  ))
  assert_true(rt.settle())
  assert_eq(outcome(one), "ok late but fine")
  assert_eq(outcome(both), "failed: both failed: b broke; a broke")
}

///|
test "a race that is itself interrupted interrupts both sides" {
  let rt = @effect.Runtime::new()
  let log = []
  let f = rt.fork(() => @effect.race_first(
    async fn() {
      defer log.push("a cleaned up")
      @effect.sleep(100)
    },
    async fn() {
      defer log.push("b cleaned up")
      @effect.sleep(100)
    },
  ))
  rt.advance(10)
  f.interrupt()
  assert_true(rt.settle())
  assert_eq(log, ["a cleaned up", "b cleaned up"])
  assert_eq(outcome(f), "interrupted")
}

///|
test "all: the values in order; the first failure fails it and interrupts the rest" {
  let rt = @effect.Runtime::new()
  let log = []
  let ok = rt.fork(() => @effect.all([
    async fn() {
      @effect.sleep(30)
      "a"
    },
    async fn() {
      @effect.sleep(10)
      "b"
    },
    async fn() {
      @effect.sleep(20)
      "c"
    },
  ]))
  let bad : @effect.Fiber[Array[String]] = rt.fork(() => @effect.all([
    async fn() {
      defer log.push("slow one cleaned up")
      @effect.sleep(300)
      "x"
    },
    async fn() {
      @effect.sleep(15)
      raise Broke("one broke")
    },
  ]))
  assert_true(rt.settle())
  assert_eq(outcome(ok), "ok [a, b, c]")
  assert_eq(outcome(bad), "failed: one broke")
  assert_eq(log, ["slow one cleaned up"])
  assert_eq(rt.now(), 30L)
}

///|
test "timeout: the value in time, None (and the work interrupted) when late" {
  let rt = @effect.Runtime::new()
  let log = []
  let quick = rt.fork(() => @effect.timeout(50, async fn() {
    @effect.sleep(10)
    1
  }))
  let slow = rt.fork(() => @effect.timeout(50, async fn() {
    defer log.push("slow work interrupted")
    @effect.sleep(100)
    2
  }))
  assert_true(rt.settle())
  assert_eq(outcome(quick), "ok Some(1)")
  assert_eq(outcome(slow), "ok None")
  assert_eq(log, ["slow work interrupted"])
}

///|
test "errors are checked: catch narrows what a fiber raised" {
  let rt = @effect.Runtime::new()
  let out = []
  ignore(
    rt.fork(async fn() {
      let quick = async fn() {
        @effect.sleep(1)
        2
      }
      try @effect.race_first(async fn() -> Int { raise Broke("nope") }, quick) catch {
        Broke(m) => out.push("err \{m}")
        e => out.push("other \{e}")
      } noraise {
        x => out.push("ok \{x}")
      }
    }),
  )
  assert_true(rt.settle())
  assert_eq(out, ["err nope"])
}
