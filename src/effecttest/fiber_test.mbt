///|
test "join gives the value, raises the failure, and Interrupt for an interrupted fiber" {
  let rt = @effect.Runtime::new()
  let out = []
  // when a and b end; c is interrupted then, long before its own end
  let ends = 5
  ignore(
    rt.fork(() => @effect.scoped(s => {
      let a = s.fork(async fn() {
        @effect.sleep(ends)
        1
      })
      let b : @effect.Fiber[Int] = s.fork(async fn() {
        @effect.sleep(ends)
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
  rt.advance(ends)
  assert_eq(out, ["a 1", "b: b broke", "c: interrupted"])
  // c's timer went with it
  assert_idle(rt)
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
  // the victim cannot be interrupted until `held`; the killer asks at `asked`
  let held = 30
  let asked = 10
  ignore(
    rt.fork(async fn() {
      let rt2 = @effect.runtime()
      let f = rt2.fork(async fn() {
        defer log.push("victim: finalizer done")
        @effect.uninterruptible(() => @effect.sleep(held))
        @effect.sleep(1000)
      })
      @effect.sleep(asked)
      let exit = f.interrupt_and_wait()
      log.push("killer: \{exit is Interrupted} at \{@effect.now()}")
    }),
  )
  rt.advance(held)
  assert_eq(log, ["victim: finalizer done", "killer: true at \{held}"])
  assert_idle(rt)
}

///|
test "race_first: the first to end wins; the other is interrupted, its finalizers run" {
  let rt = @effect.Runtime::new()
  let log = []
  // when the fast side ends
  let fast = 10
  let f = rt.fork(() => @effect.race_first(
    async fn() {
      defer log.push("slow cleaned up")
      @effect.sleep(100)
      log.push("slow woke (wrong)")
      "slow"
    },
    async fn() {
      @effect.sleep(fast)
      "fast"
    },
  ))
  rt.advance(fast)
  assert_eq(log, ["slow cleaned up"])
  assert_eq(outcome(f), "ok fast")
  // the loser's timer went with it
  assert_idle(rt)
}

///|
test "race_first: a failure that comes first is the answer" {
  let rt = @effect.Runtime::new()
  // when the failing side ends; the other is interrupted then
  let first = 5
  let f : @effect.Fiber[String] = rt.fork(() => @effect.race_first(
    async fn() {
      @effect.sleep(first)
      raise Broke("first broke")
    },
    async fn() {
      @effect.sleep(10)
      "late"
    },
  ))
  rt.advance(first)
  assert_eq(outcome(f), "failed: first broke")
  assert_idle(rt)
}

///|
test "race: the first success wins, a failure leaves it to the other; both failing says both" {
  let rt = @effect.Runtime::new()
  // the last of the four sides to end
  let last = 10
  let one : @effect.Fiber[String] = rt.fork(() => @effect.race(
    async fn() {
      @effect.sleep(5)
      raise Broke("first broke")
    },
    async fn() {
      @effect.sleep(last)
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
  rt.advance(last)
  assert_eq(outcome(one), "ok late but fine")
  assert_eq(outcome(both), "failed: both failed: b broke; a broke")
  assert_idle(rt)
}

///|
test "a race that is itself interrupted interrupts both sides" {
  let rt = @effect.Runtime::new()
  let log = []
  // both sides sleep `long`; the race is interrupted at `cut`, before either ends
  let long = 100
  let cut = 10
  let f = rt.fork(() => @effect.race_first(
    async fn() {
      defer log.push("a cleaned up")
      @effect.sleep(long)
    },
    async fn() {
      defer log.push("b cleaned up")
      @effect.sleep(long)
    },
  ))
  rt.advance(cut)
  f.interrupt()
  ignore(rt.run_ready())
  assert_eq(log, ["a cleaned up", "b cleaned up"])
  assert_eq(outcome(f), "interrupted")
  assert_idle(rt)
}

///|
test "all: the values in order; the first failure fails it and interrupts the rest" {
  let rt = @effect.Runtime::new()
  let log = []
  // the slowest of `ok`'s; `bad` fails before it
  let slowest = 30
  let ok = rt.fork(() => @effect.all([
    async fn() {
      @effect.sleep(slowest)
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
  rt.advance(slowest)
  assert_eq(outcome(ok), "ok [a, b, c]")
  assert_eq(outcome(bad), "failed: one broke")
  assert_eq(log, ["slow one cleaned up"])
  // the slow one's timer went with it
  assert_idle(rt)
}

///|
test "timeout: the value in time, None (and the work interrupted) when late" {
  let rt = @effect.Runtime::new()
  let log = []
  // the time both are given
  let limit = 50
  let quick = rt.fork(() => @effect.timeout(limit, async fn() {
    @effect.sleep(10)
    1
  }))
  let slow = rt.fork(() => @effect.timeout(limit, async fn() {
    defer log.push("slow work interrupted")
    @effect.sleep(100)
    2
  }))
  rt.advance(limit)
  assert_eq(outcome(quick), "ok Some(1)")
  assert_eq(outcome(slow), "ok None")
  assert_eq(log, ["slow work interrupted"])
  assert_idle(rt)
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
  // the failing side raises at once: no time goes by
  ignore(rt.run_ready())
  assert_eq(out, ["err nope"])
  assert_idle(rt)
}
