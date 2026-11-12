// A display's frame a hair from the moment something is due (a wake, a motion's end) is drawn at that moment: the same
// moment summed one way or another, as run_for's frames on its way are (tester_time.mbt on_grid; Tester::at_due).

///|
test "a display's frame a hair before what is due is drawn at it: what changes then has, the frame of its own moment" {
  let due = Ref(0.0)
  let t = Tester::new(
    fn(c) {
      if c.moment() < due.val {
        c.wake_in(due.val - c.moment())
      }
      c.text(if c.moment() >= due.val { "after" } else { "before" }) |> ignore
    },
    w=100.0,
    h=100.0,
  )
  t.draw()
  due.val = t.time() + 500.0
  t.stepped()
  t.draw()
  assert_true(t.find("before") is Some(_))
  // (the display's frames as a host's run had them: one 5e-13 ms short of what is due, as a grid of 7 a second put one
  // short of a fade's end, the next well after it)
  t.set_frame_times([due.val - 5.0e-13, due.val + 100.0])
  t.run_for(due.val - t.time())
  assert_eq(t.time(), due.val)
  assert_true(t.find("after") is Some(_), msg="the frame at what is due drawn as so")
}
