///|
test "Deferred: waiters wait for its one outcome; a second one is refused" {
  let rt = @effect.Runtime::new()
  let d : @effect.Deferred[Int] = @effect.Deferred::new()
  let ws = Array::makei(3, _ => rt.fork(() => d.wait()))
  ignore(rt.run_ready())
  assert_eq(outcome(ws[0]), "running")
  // one of them is interrupted while it waits: the others are not disturbed
  ws[1].interrupt()
  ignore(rt.run_ready())
  assert_true(d.succeed(5))
  assert_true(!d.succeed(6))
  assert_true(!d.fail(Broke("late")))
  ignore(rt.run_ready())
  assert_eq(ws.map(outcome), ["ok 5", "interrupted", "ok 5"])
  // waiting on one already done does not wait
  let late = rt.fork(() => d.wait())
  ignore(rt.run_ready())
  assert_eq(outcome(late), "ok 5")
}

///|
test "Deferred: its failure is raised in every waiter" {
  let rt = @effect.Runtime::new()
  let d : @effect.Deferred[Int] = @effect.Deferred::new()
  let w = rt.fork(() => d.wait())
  // when it fails
  let fails_at = 20
  rt.after(fails_at, () => ignore(d.fail(Broke("no answer"))))
  ignore(rt.run_ready())
  assert_eq(outcome(w), "running")
  rt.advance(fails_at)
  assert_eq(outcome(w), "failed: no answer")
  assert_idle(rt)
}

///|
test "Queue: take waits for an item; items come out in order" {
  let rt = @effect.Runtime::new()
  let q : @effect.Queue[String] = @effect.Queue::unbounded()
  let got = []
  ignore(
    rt.fork(async fn() {
      for _ in 0..<3 {
        got.push("\{q.take()} at \{@effect.now()}")
      }
    }),
  )
  // when the first item is offered, and when the other two
  let first = 10
  let rest = 20
  rt.after(first, () => ignore(q.try_offer("a")))
  rt.after(rest, () => {
    ignore(q.try_offer("b"))
    ignore(q.try_offer("c"))
  })
  rt.advance(rest)
  assert_eq(got, ["a at \{first}", "b at \{rest}", "c at \{rest}"])
  assert_idle(rt)
}

///|
test "Queue: on a bounded one, offer waits for room" {
  let rt = @effect.Runtime::new()
  let q : @effect.Queue[Int] = @effect.Queue::bounded(2)
  let log = []
  ignore(
    rt.fork(async fn() {
      for i in 0..<4 {
        q.offer(i)
        log.push("offered \{i} at \{@effect.now()}")
      }
    }),
  )
  // the taker takes one each `gap`, twice
  let gap = 100
  ignore(
    rt.fork(async fn() {
      @effect.sleep(gap)
      log.push("took \{q.take()}")
      @effect.sleep(gap)
      log.push("took \{q.take()}")
    }),
  )
  rt.advance(2 * gap)
  assert_eq(log, [
    "offered 0 at 0", "offered 1 at 0", "took 0", "offered 2 at 100", "took 1", "offered 3 at 200",
  ])
  assert_true(!q.try_offer(9))
  assert_eq(q.size(), 2)
  assert_idle(rt)
}

///|
test "Queue: shut down, takes end once it is empty and offers fail" {
  let rt = @effect.Runtime::new()
  let q : @effect.Queue[Int] = @effect.Queue::unbounded()
  let got = []
  let taker = rt.fork(async fn() { while true { got.push(q.take()) } })
  ignore(q.try_offer(1))
  ignore(q.try_offer(2))
  q.shutdown()
  let offer = rt.fork(() => q.offer(3))
  // nothing here sleeps: no time goes by
  ignore(rt.run_ready())
  assert_eq(got, [1, 2])
  assert_eq(outcome(taker), "failed: queue shut down")
  assert_eq(outcome(offer), "failed: queue shut down")
  assert_idle(rt)
}

///|
test "Queue: an interrupted taker loses nothing (many seeds)" {
  @effect.for_seeds(count=50, fn(seed) {
    let rt = @effect.Runtime::new(seed~)
    let q : @effect.Queue[Int] = @effect.Queue::bounded(2)
    let got = []
    // the most a taker rests after an item, the offerer between items, and the latest a taker is interrupted
    let take_rest = 5
    let offer_rest = 3
    let cut_by = 40
    let items = 20
    let takers = Array::makei(3, _ => rt.fork(async fn() {
      while true {
        got.push(q.take())
        @effect.sleep(rt.rng.between(0, take_rest))
      }
    }))
    ignore(
      rt.fork(async fn() {
        for i in 0..<items {
          q.offer(i)
          @effect.sleep(rt.rng.between(0, offer_rest))
        }
      }),
    )
    // two of the three takers are interrupted at times the seed picks: parked
    // in take or not, no item is lost or taken twice
    for k in 0..<2 {
      rt.after(rt.rng.between(1, cut_by), () => takers[k].interrupt())
    }
    // all is taken by then, whatever the seed drew: each item offered and taken a rest apart at most, after the
    // interruptions
    rt.advance(cut_by + items * (offer_rest + take_rest))
    got.sort()
    assert_eq(got, Array::makei(items, i => i))
    assert_eq(outcome(takers[0]), "interrupted")
    // the last taker waits in take, with nothing set
    assert_idle(rt)
  })
}

///|
test "Semaphore: never more holders than permits (many seeds); released however it ends" {
  @effect.for_seeds(count=50, fn(seed) {
    let rt = @effect.Runtime::new(seed~)
    let sem = @effect.Semaphore::new(2)
    let holding = Ref(0)
    let most = Ref(0)
    // the longest one holds a permit, and the latest the last one is interrupted
    let hold_most = 20
    let cut_by = 30
    let n = 6
    let fibers = Array::makei(n, i => rt.fork(async fn() {
      sem.with_permit(async fn() {
        holding.val += 1
        most.val = if holding.val > most.val { holding.val } else { most.val }
        defer {
          holding.val -= 1
        }
        @effect.sleep(rt.rng.between(1, hold_most))
        if i == 3 {
          raise Broke("holder broke")
        }
      })
    }))
    rt.after(rt.rng.between(1, cut_by), () => fibers[n - 1].interrupt())
    // all have held and let go by then, whatever the seed drew: one after another at the most
    rt.advance(cut_by + n * hold_most)
    assert_true(most.val <= 2)
    assert_eq(most.val, 2)
    assert_eq(sem.available(), 2)
    assert_eq(holding.val, 0)
    assert_idle(rt)
  })
}
