///|
test "a scope's finalizers run last first: on success, on failure, on interruption" {
  let rt = @effect.Runtime::new()
  let log = []
  // how long cut's slow finalizer sleeps
  let slow = 10
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
      @effect.sleep(slow)
      log.push("cut 2 (slow)")
    })
    @effect.sleep(1000)
    log.push("cut woke (wrong)")
    3
  }))
  ignore(rt.run_ready())
  cut.interrupt()
  ignore(rt.run_ready())
  // the finalizer sleeps on the virtual clock, uninterrupted
  assert_eq(log, ["ok 2", "ok 1", "bad 2", "bad 1"])
  rt.advance(slow)
  assert_eq(log, ["ok 2", "ok 1", "bad 2", "bad 1", "cut 2 (slow)", "cut 1"])
  assert_eq(outcome(ok), "ok 1")
  assert_eq(outcome(bad), "failed: bad broke")
  assert_eq(outcome(cut), "interrupted")
  assert_idle(rt)
}

///|
test "interrupted while its finalizers run, a fiber still runs them all" {
  let rt = @effect.Runtime::new()
  let log = []
  // the body sleeps `body`, then the slow finalizer `slow`; it is interrupted at `cut`, in that finalizer, and
  // looked at `a_while` after
  let body = 10
  let slow = 100
  let cut = 50
  let a_while = 10
  let f = rt.fork(() => @effect.scoped(s => {
    s.add_finalizer(() => log.push("added first"))
    s.add_finalizer(async fn() {
      @effect.sleep(slow)
      log.push("slow finalizer done")
    })
    @effect.sleep(body)
    0
  }))
  rt.advance(cut)
  // in the slow finalizer now
  f.interrupt()
  rt.advance(a_while)
  assert_eq(log, [])
  // to the slow finalizer's end
  rt.advance(body + slow - rt.now().to_int())
  assert_eq(log, ["slow finalizer done", "added first"])
  // its body had ended: the interruption came too late to change the outcome
  assert_eq(outcome(f), "ok 0")
  assert_idle(rt)
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
  // nothing here sleeps: no time goes by
  ignore(rt.run_ready())
  assert_eq(log, ["last", "first"])
  assert_eq(outcome(f), "ok body")
  assert_eq(rt.defects.length(), 1)
  assert_idle(rt)
}

///|
test "acquisition is uninterruptible, and what it acquired is released" {
  let rt = @effect.Runtime::new()
  let log = []
  // acquiring takes `acquiring`; it is asked to stop at `cut`, halfway
  let acquiring = 100
  let cut = 50
  let f = rt.fork(() => @effect.scoped(s => {
    let r = s.acquire_release(
      async fn() {
        @effect.sleep(acquiring)
        log.push("acquired")
        7
      },
      async fn(x) { log.push("released \{x}") },
    )
    log.push("using \{r} (wrong: asked to stop during acquisition)")
    @effect.sleep(1000)
    r
  }))
  rt.advance(cut)
  f.interrupt()
  ignore(rt.run_ready())
  assert_eq(log, [])
  // to the acquisition's end
  rt.advance(acquiring - cut)
  assert_eq(log, ["acquired", "released 7"])
  assert_eq(outcome(f), "interrupted")
  // the body's sleep never began
  assert_idle(rt)
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
  // the parent closes a while after, its child's fiber asleep
  let a_while = 5
  rt.advance(a_while)
  parent.close_now()
  ignore(rt.run_ready())
  assert_eq(log, ["child's fiber", "child", "parent"])
  assert_true(child.is_closed())
  assert_idle(rt)
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
  // it is interrupted as it sleeps: no time goes by
  ignore(rt.run_ready())
  assert_eq(log, ["finalized", "closed"])
  assert_eq(outcome(f), "interrupted")
  assert_idle(rt)
}
