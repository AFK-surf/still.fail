// Ctx::at_rest: whether a frame left nothing that ends to come, said of a run (asserted: a test's end, assert_idle),
// never waited on.

///|
test "at rest: not while a spring is short of its end or a wake is owed; a spinner turning on does not keep it from it" {
  let target = Ref(0.0)
  let armed = Ref(false)
  // how long the app waits (a toast's stay)
  let stay_ms = 300.0
  let t = Tester::new(
    fn(c) {
      ignore(c.cycle(1000.0))
      ignore(c.spring("x", target.val, from=0.0))
      if armed.val {
        armed.val = false
        c.wake_in(stay_ms)
      }
      c.text("x", wrap=false) |> ignore
    },
    w=100.0,
    h=100.0,
  )
  // a frame each way of its end (the display's)
  let frame_ms = 1000.0 / 60.0
  t.draw()
  assert_true(g().frame_rest, msg=g().rest_why())
  // a spring set out: not at rest until its end, and said why
  target.val = 100.0
  t.draw()
  assert_false(g().frame_rest)
  assert_true(g().rest_why().contains("a motion said is not at rest"), msg=g().rest_why())
  let end = rest_of("x")
  assert_true(end > t.time())
  t.run_for(end - t.time() - frame_ms)
  assert_false(g().frame_rest)
  t.run_for(2.0 * frame_ms)
  assert_true(g().frame_rest, msg=g().rest_why())
  // a wake owed: not at rest until it has come
  armed.val = true
  t.draw()
  assert_false(g().frame_rest)
  assert_true(g().rest_why().contains("a wake in"), msg=g().rest_why())
  t.run_for(stay_ms)
  t.draw()
  assert_true(g().frame_rest, msg=g().rest_why())
}

///|
test "a runtime's timer said once is a wake a run's end sees, with who said it; one said `later` is not" {
  let t = Tester::new(fn(c) { c.text("x", wrap=false) |> ignore }, w=100.0, h=100.0)
  // (a core's retry, as its client says it)
  let retry_ms = 500
  fx.val.after(retry_ms, fn() {  }, who="core: timers")
  fx.val.after(retry_ms * 2, fn() {  }, later=true, who="core: a ping")
  t.draw()
  match t.next_wake() {
    Some((at, by)) => {
      assert_true(by.contains("core: timers"), msg=by)
      assert_false(g().frame_rest)
      t.run_for(at - t.time())
    }
    None => fail("the runtime's timer is a wake")
  }
  t.draw()
  assert_eq(t.next_wake(), None)
  assert_true(g().frame_rest, msg=g().rest_why())
  assert_true(own_clock())
}

///|
test "a Tester asked whether the app is at rest: not while a frame is asked for, at rest once the frames it said are drawn" {
  // (a frame grabbed, then kept, then said: each step in the frame after the last, as still.fail's "save this frame")
  let step = Ref(0)
  let t = Tester::new(fn(c) {
    if step.val > 0 && step.val < 3 {
      step.val += 1
      c.request_frame()
    }
    c.text(if step.val >= 3 { "saved" } else { "x" }, wrap=false) |> ignore
  })
  assert_true(t.at_rest(), msg=t.rest_why())
  step.val = 1
  t.frame()
  assert_false(t.at_rest())
  assert_true(t.rest_why().contains("a frame asked for"), msg=t.rest_why())
  // (steps 2 and 3: the two frames it asks for, then none)
  t.frame()
  assert_false(t.at_rest())
  t.frame()
  assert_true(t.at_rest(), msg=t.rest_why())
  assert_true(t.find("saved") is Some(_))
}
