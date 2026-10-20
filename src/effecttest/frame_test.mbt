// Frames driving the virtual clock (Runtime::frame, next_frame), what a runtime still holds once it is shut down
// (no cycle left for native's reference counting), and failures `all` does not lose.

///|
test "a frame moves the clock to its time: timers fire at theirs, then the fibers waiting for a frame" {
  let rt = @effect.Runtime::new(start=1000L)
  let log : Array[String] = []
  ignore(
    rt.fork(async fn() {
      @effect.sleep(20)
      log.push("timer \{@effect.now()}")
    }),
  )
  ignore(
    rt.fork(async fn() {
      for _ in 0..<3 {
        @effect.next_frame()
        log.push("frame \{@effect.now()}")
      }
    }),
  )
  ignore(rt.run_ready())
  assert_true(rt.wants_frame())
  rt.frame(1016L)
  rt.frame(1032L)
  rt.frame(1048L)
  assert_eq(log, ["frame 1016", "timer 1020", "frame 1032", "frame 1048"])
  // nothing waits for a frame any more
  assert_true(!rt.wants_frame())
  assert_eq(rt.frames, 3)
}

///|
test "a frame at or before the clock's time does not move it, and still steps what waits for a frame" {
  let rt = @effect.Runtime::new(start=500L)
  let n = Ref(0)
  ignore(
    rt.fork(async fn() {
      while true {
        @effect.next_frame()
        n.val += 1
      }
    }),
  )
  ignore(rt.run_ready())
  rt.frame(400L)
  rt.frame(500L)
  assert_eq(rt.now(), 500L)
  assert_eq(n.val, 2)
}

///|
test "an interrupted fiber waiting for a frame is gone from the frame's waiters" {
  let rt = @effect.Runtime::new()
  let f = rt.fork(async fn() { @effect.next_frame() })
  ignore(rt.run_ready())
  assert_true(rt.wants_frame())
  f.interrupt()
  ignore(rt.run_ready())
  assert_true(f.poll() is Some(Interrupted))
  assert_true(!rt.wants_frame())
}

///|
/// A busy runtime: fibers in scopes and child scopes, sleeping, waiting on frames, a Deferred, a Queue and a
/// Semaphore, racing, with finalizers.
fn busy(rt : @effect.Runtime) -> Unit {
  let q : @effect.Queue[Int] = @effect.Queue::bounded(2)
  let sem = @effect.Semaphore::new(1)
  let d : @effect.Deferred[Int] = @effect.Deferred::new()
  let s = rt.scope()
  let kid = s.child()
  rt.root().add_finalizer(async fn() { s.close() })
  for i in 0..<10 {
    ignore(
      kid.fork(async fn() {
        sem.with_permit(async fn() { @effect.sleep(10 + i) })
        q.offer(i)
        @effect.next_frame()
        ignore(@effect.timeout(1000, () => d.wait()))
      }),
    )
  }
  ignore(
    rt.fork(async fn() {
      while true {
        ignore(q.take())
        @effect.sleep(3)
      }
    }),
  )
  ignore(
    rt.fork(async fn() {
      ignore(
        @effect.race(async fn() { @effect.sleep(1_000_000) }, async fn() {
          @effect.never()
        }),
      )
    }),
  )
}

///|
test "shut down, a runtime holds nothing: no fiber, timer, waiter or finalizer is left to keep alive" {
  @effect.for_seeds(count=20, seed => {
    let rt = @effect.Runtime::new(seed~)
    busy(rt)
    for i in 0..<20 {
      rt.frame((i * 16).to_int64())
    }
    let (live, _, _, _, _, _) = rt.holding()
    assert_true(live > 0)
    rt.shutdown()
    // what the interruptions woke runs; no time goes by
    ignore(rt.run_ready())
    assert_eq(rt.holding(), (0, 0, 0, 0, 0, 0))
  })
}

///|
test "sleeps given up do not pile up in the timer heap" {
  let rt = @effect.Runtime::new()
  for _ in 0..<1000 {
    let f = rt.fork(async fn() { @effect.sleep(1_000_000) })
    ignore(rt.run_ready())
    f.interrupt()
    ignore(rt.run_ready())
  }
  let (live, _, timers, _, _, _) = rt.holding()
  assert_eq(live, 0)
  assert_eq(timers, 0)
  assert_true(rt.timer_slots() < 64)
}

///|
test "all: the first failure fails it, others that failed too are told to on_defect" {
  let rt = @effect.Runtime::new()
  let told : Array[String] = []
  rt.on_defect(e => told.push(describe(e)))
  // when both fail; the third is interrupted then
  let fail_at = 10
  let f = rt.fork(async fn() {
    @effect.all([
      async fn() {
        @effect.sleep(fail_at)
        raise Broke("first")
      },
      async fn() {
        @effect.sleep(fail_at)
        raise Broke("second")
      },
      async fn() {
        @effect.sleep(50)
        1
      },
    ])
  })
  rt.advance(fail_at)
  assert_eq(outcome(f), "failed: first")
  // the root scope tells the failed fiber's error too
  assert_true(told.contains("second"))
  assert_idle(rt)
}
