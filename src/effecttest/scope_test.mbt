///|
test "a scope's finalizers run last first: on success, on failure, on interruption" {
  let rt = @effect.Runtime::new()
  let log = []
  let ok = rt.fork(() => @effect.scoped(s => {
    s.add_finalizer(() => log.push("ok 1"))
    s.add_finalizer(() => log.push("ok 2"))
    1
  }))
  let bad : @effect.Fiber[Int] = rt.fork(() => @effect.scoped(s => {
    s.add_finalizer(() => log.push("bad 1"))
    s.add_finalizer(() => log.push("bad 2"))
    raise Broke("bad broke")
  }))
  let cut = rt.fork(() => @effect.scoped(s => {
    s.add_finalizer(() => log.push("cut 1"))
    s.add_finalizer(async fn() {
      @effect.sleep(10)
      log.push("cut 2 (slow)")
    })
    @effect.sleep(1000)
    log.push("cut woke (wrong)")
    3
  }))
  ignore(rt.run_ready())
  cut.interrupt()
  assert_true(rt.settle())
  assert_eq(log, ["ok 2", "ok 1", "bad 2", "bad 1", "cut 2 (slow)", "cut 1"])
  assert_eq(outcome(ok), "ok 1")
  assert_eq(outcome(bad), "failed: bad broke")
  assert_eq(outcome(cut), "interrupted")
  // the finalizer slept 10 on the virtual clock, uninterrupted
  assert_eq(rt.now(), 10L)
}

///|
test "interrupted while its finalizers run, a fiber still runs them all" {
  let rt = @effect.Runtime::new()
  let log = []
  let f = rt.fork(() => @effect.scoped(s => {
    s.add_finalizer(() => log.push("added first"))
    s.add_finalizer(async fn() {
      @effect.sleep(100)
      log.push("slow finalizer done")
    })
    @effect.sleep(10)
    0
  }))
  rt.advance(50)
  // in the slow finalizer now
  f.interrupt()
  rt.advance(10)
  assert_eq(log, [])
  assert_true(rt.settle())
  assert_eq(log, ["slow finalizer done", "added first"])
  // its body had ended: the interruption came too late to change the outcome
  assert_eq(outcome(f), "ok 0")
  assert_eq(rt.now(), 110L)
}

///|
test "a finalizer that fails is a defect; the others still run" {
  let rt = @effect.Runtime::new()
  let log = []
  let f = rt.fork(() => @effect.scoped(s => {
    s.add_finalizer(() => log.push("first"))
    s.add_finalizer(async fn() { raise Broke("finalizer broke") })
    s.add_finalizer(() => log.push("last"))
    "body"
  }))
  assert_true(rt.settle())
  assert_eq(log, ["last", "first"])
  assert_eq(outcome(f), "ok body")
  assert_eq(rt.defects.length(), 1)
}

///|
test "acquisition is uninterruptible, and what it acquired is released" {
  let rt = @effect.Runtime::new()
  let log = []
  let f = rt.fork(() => @effect.scoped(s => {
    let r = s.acquire_release(
      async fn() {
        @effect.sleep(100)
        log.push("acquired")
        7
      },
      async fn(x) { log.push("released \{x}") },
    )
    log.push("using \{r} (wrong: asked to stop during acquisition)")
    @effect.sleep(1000)
    r
  }))
  rt.advance(50)
  f.interrupt()
  assert_true(rt.settle())
  assert_eq(log, ["acquired", "released 7"])
  assert_eq(outcome(f), "interrupted")
  assert_eq(rt.now(), 100L)
}

///|
test "a child scope closes with its parent, before the parent's earlier finalizers" {
  let rt = @effect.Runtime::new()
  let log = []
  let parent = rt.scope()
  parent.add_finalizer(() => log.push("parent"))
  let child = parent.child()
  child.add_finalizer(() => log.push("child"))
  ignore(child.fork(async fn() {
    defer log.push("child's fiber")
    @effect.sleep(1_000_000)
  }))
  rt.advance(5)
  parent.close_now()
  assert_true(rt.settle())
  assert_eq(log, ["child's fiber", "child", "parent"])
  assert_true(child.is_closed())
}

///|
test "forked into a closed scope, a fiber never runs; a finalizer added runs soon" {
  let rt = @effect.Runtime::new()
  let s = rt.scope()
  s.close_now()
  ignore(rt.run_ready())
  let ran = Ref(false)
  let f = s.fork(() => ran.val = true)
  let fin = Ref(false)
  s.add_finalizer(() => fin.val = true)
  ignore(rt.run_ready())
  assert_true(!ran.val)
  assert_eq(outcome(f), "interrupted")
  assert_true(fin.val)
}

///|
test "a fiber closing its own scope does not wait for itself" {
  let rt = @effect.Runtime::new()
  let s = rt.scope()
  let log = []
  s.add_finalizer(() => log.push("finalized"))
  let f = s.fork(async fn() {
    s.close()
    log.push("closed")
    @effect.sleep(10)
    log.push("woke (wrong)")
  })
  assert_true(rt.settle())
  assert_eq(log, ["finalized", "closed"])
  assert_eq(outcome(f), "interrupted")
}
