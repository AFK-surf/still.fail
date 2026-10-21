// Tester::run_for: straight to the time it is given, a frame at each moment something is due on the way.

///|
test "what a motion's end sets off comes at that end, however far the clock is run past it in one go" {
  let target = Ref(0.0)
  let landed = Ref(-1.0)
  let t = Tester::new(
    fn(c) {
      let x = c.spring("x", target.val, from=0.0)
      // (the app goes on once its slide is over: a page gone, a core told)
      if target.val > 0.0 && x == target.val && landed.val < 0.0 {
        landed.val = c.now()
      }
      c.text("x", wrap=false) |> ignore
    },
    w=100.0,
    h=100.0,
  )
  target.val = 100.0
  t.draw()
  let end = rest_of("x")
  assert_true(end > t.time())
  let past_it = 1000.0
  t.run_for(end - t.time() + past_it)
  assert_eq(landed.val, end)
  t.assert_idle()
}
