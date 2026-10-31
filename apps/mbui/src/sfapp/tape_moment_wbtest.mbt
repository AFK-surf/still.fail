// The tape as nodes of the window's tree (sfdesk's tape_view.mbt): its shell and its panels made once, kept as the tape
// moves, a side panel opens and closes and the window goes to 大屏 and back; where it is at a moment a function of that
// moment and what was done at which moment, whatever frames were drawn between (one jump, a late one, many).

///|
/// Where the tape's row is drawn across and how wide the page's panel is, as the tree has them now.
fn tape_now() -> (Double, Double) {
  match @sfdesk.tape_seen() {
    Some((_, x, w)) => (x, w)
    None => (-1.0, -1.0)
  }
}

///|
/// The page brought over (bring_page) at `t0 + 10` between frames, the sidebar in use before: where the tape is at
/// `t0 + 160`, frames drawn at `t0 +` each of `frames` between; which is in use.
fn tape_brought(frames : Array[Double]) -> (Double, Double, @sfdesk.TapePane) {
  let t = tape_chat(0, 720.0, 840.0)
  let t0 = t.time()
  t.advance(10.0)
  @sfdesk.bring_page()
  for f in frames {
    t.frame_at(t0 + f)
  }
  t.frame_at(t0 + 160.0)
  let (x, w) = tape_now()
  (x, w, @sfdesk.wide.tape_at.get())
}

///|
test "on the tape the page brought over between frames goes from that moment: where it is at a moment the same, whichever frames came between" {
  let one = tape_brought([])
  let late = tape_brought([40.0])
  let many = tape_brought([11.0, 13.0, 16.0, 24.0, 33.0, 80.0, 120.0])
  assert_eq((late, many), (one, one))
  let (x, _, at) = one
  assert_eq(at, @sfdesk.TapePane::Page)
  // (on its way: off where the sidebar had it, not yet where the page has it)
  let t = tape_chat(0, 720.0, 840.0)
  let (rest_side, _) = tape_now()
  page_over(t, 720.0)
  let (rest_page, _) = tape_now()
  assert_true(x < rest_side && x > rest_page, msg="\{rest_side} > \{x} > \{rest_page}")
}

///|
/// With the page in use, its chat's side panel opened at `t0 + 10` (the tape setting out to it, the page narrowing with
/// it), back at `t0 + 110` while it goes (the page brought over again, from where the tape is then): where the tape is
/// and how wide the page's panel is at `t0 + 300`, frames drawn at `t0 +` each of `before` and `after` between; which is
/// in use; how far the tape went from a ms before back to a ms after it.
fn tape_turned(before : Array[Double], after : Array[Double]) -> (Double, Double, @sfdesk.TapePane, Double) {
  let t = tape_chat(0, 720.0, 840.0)
  page_over(t, 720.0)
  // (the pointer gone from it: no tip shown under it as the panel comes, which back would close first)
  let (px, py, pw, ph) = said_at(t, "打开侧栏").unwrap()
  let t0 = t.time()
  t.advance(10.0)
  t.tap(px + pw / 2.0, py + ph / 2.0)
  t.leave()
  for f in before {
    t.frame_at(t0 + f)
  }
  t.frame_at(t0 + 109.0)
  let (x_before, _) = tape_now()
  t.advance(t0 + 110.0 - t.time())
  t.back()
  t.frame_at(t0 + 111.0)
  let (x_after, _) = tape_now()
  for f in after {
    t.frame_at(t0 + f)
  }
  t.frame_at(t0 + 300.0)
  let (x, w) = tape_now()
  (x, w, @sfdesk.wide.tape_at.get(), (x_after - x_before).abs())
}

///|
test "on the tape a side panel opened and the page brought back while the tape goes to it: from where it is then, the same at a moment whichever frames came between" {
  let one = tape_turned([], [])
  let many = tape_turned([12.0, 20.0, 37.0, 60.0, 90.0], [130.0, 170.0, 220.0, 260.0])
  let late = tape_turned([95.0], [250.0])
  assert_eq((many, late), (one, one))
  let (_, _, at, jump) = one
  assert_eq(at, @sfdesk.TapePane::Page)
  // (back set out from where the tape was: no jump at its moment, two ms of a move apart at most)
  assert_true(jump < 8.0, msg="the tape went \{jump} in the two ms round back")
}

///|
/// What shows of the page at the right pulled across to the window's middle by a finger, let go: moved there in
/// `steps` moves (none: down, then let go there, no move told between).
fn tape_pulled_over(steps : Int) -> @sfdesk.TapePane raise {
  let t = tape_chat(2, 720.0, 840.0, width="medium", height="medium")
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
  let x0 = 720.0 - @sfdesk.tape_shows / 2.0
  if steps == 0 {
    t.press_at(x0, 400.0)
    t.advance(@ui.input_step_ms * 6.0)
    t.release(360.0, 400.0)
  } else {
    t.drag(x0, 400.0, 360.0, 400.0, steps~)
  }
  t.run_for(@ui.move_most_ms)
  @sfdesk.wide.tape_at.get()
}

///|
test "on the tape what shows of the page pulled across and let go brings it over, its moves told or only where it was let go" {
  assert_eq(tape_pulled_over(6), @sfdesk.TapePane::Page)
  assert_eq(tape_pulled_over(0), @sfdesk.TapePane::Page)
}

///|
test "on the tape its shell and its panels made once: the same nodes as the page comes over, a side panel opens and closes, the edge is dragged" {
  let t = tape_chat(0, 720.0, 840.0)
  let ids = @sfdesk.tape_seen().unwrap().0
  page_over(t, 720.0)
  assert_eq(@sfdesk.tape_seen().unwrap().0, ids)
  tap_said(t, "打开侧栏")
  t.leave()
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Panel)
  assert_eq(@sfdesk.tape_seen().unwrap().0, ids)
  t.back()
  t.run_for(@ui.move_most_ms)
  t.back()
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
  // the sidebar's edge dragged 40 wider: the page beside it from further, nothing made anew
  let (ex, ey, ew, eh) = said_at(t, "调整侧边栏宽度").unwrap()
  let (_, w0) = tape_now()
  t.drag(ex + ew / 2.0, ey + eh / 2.0, ex + ew / 2.0 + 40.0, ey + eh / 2.0, steps=4)
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfdesk.tape_seen().unwrap().0, ids)
  ignore(w0)
}

///|
test "on the tape the window made 大屏 and 中屏 again: off the tape, then the tape made anew where it is in use, as it is made at first" {
  let t = tape_chat(0, 720.0, 840.0)
  page_over(t, 720.0)
  let was = tape_now()
  t.resize(1280.0, 840.0)
  t.run_for(@ui.move_most_ms)
  assert_true(@sfdesk.tape_seen() is None)
  assert_false(@sfdesk.wide.tape)
  t.resize(720.0, 840.0)
  t.run_for(@ui.move_most_ms)
  assert_true(@sfdesk.wide.tape)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page)
  assert_eq(tape_now(), was)
}
