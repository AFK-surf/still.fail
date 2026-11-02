// A thing held for its menu, lifted over its sheet (lift_over), where it hangs past the window's foot (a tall picture in
// a message under the composer): pushed up before the sheet as it comes up, no further than it has come, from where
// it was, and back down with it as it goes.

///|
let lift_test_ground : Int64 = 0x22AA66FFL

///|
/// A 600 high box from 400 down a 390 by 844 window (past its foot), lifted for its menu while `open`, the menu's 300
/// high sheet up meanwhile; where the sheet's top was as each frame was laid out, kept in `tops`.
fn lift_hanging(open : Ref[Bool], tops : Array[Double?]) -> @ui.Tester {
  @ui.Tester::new(
    fn(c) {
      c.box(fn() {
        let above = c.box(h=Px(400.0), fn() {  })
        let b = c.box(w=Px(200.0), h=Px(600.0), bg=lift_test_ground, fn() {  })
        lift_over(c, b, "hanging", lift_of(c, "hanging", false, open.val), 1.0)
        // (read as lift_over reads it, beside it)
        @motion.placed(c, above, fn() {
          tops.push(@kit.sheet_top(c))
          @ui.still_look
        })
      })
      |> ignore
      @kit.sheet(c, "lift-hanging", open.val, h=300.0, fn() {  }) |> ignore
    },
    w=390.0,
    h=844.0,
    platform=2,
  )
}

///|
test "a thing held for its menu, hanging past the window's foot: lifted no further than the sheet has come up, from where it was as the sheet starts and back to it as it goes" {
  let open = Ref(false)
  let tops : Array[Double?] = []
  let t = lift_hanging(open, tops)
  t.draw()
  let at = fn() {
    t.drawn_rects().filter(fn(d) { d.4 == lift_test_ground }).map(fn(d) { d.1 }).fold(init=-1.0, fn(_, v) { v })
  }
  let rest = at()
  assert_eq(rest, 400.0)
  // (how far it is above where it was, and how far the sheet is up into the window, as this frame was laid out, to
  // the whole point the box is drawn on)
  let now = fn() {
    let up = match tops.last() {
      Some(Some(top)) => (844.0 - top).ceil()
      _ => 0.0
    }
    (rest - at(), up)
  }
  open.val = true
  t.draw()
  t.run_for(t.frame_period())
  let (pushed, up) = now()
  assert_true(pushed <= up, msg="as the sheet starts: pushed \{pushed}, the sheet up \{up}")
  t.run_for(@kit.sheet_rest("lift-hanging") - t.time())
  let (pushed, up) = now()
  assert_eq(up, 300.0)
  assert_true(pushed > 0.0 && pushed <= up, msg="the sheet up: pushed \{pushed}")
  open.val = false
  t.draw()
  // (a frame before the sheet is gone)
  t.run_for(@kit.sheet_rest("lift-hanging") - t.time() - t.frame_period())
  let (pushed, up) = now()
  assert_true(pushed <= up, msg="as the sheet goes: pushed \{pushed}, the sheet up \{up}")
}
