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
  t.advance(between_frames_ms)
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
/// it) and back at `t0 + 110` while it goes (the page brought over again, from where the tape is then), each between
/// frames, as the core's state and back say them (no frame drawn by either: side_change, wide_back); frames drawn at
/// `t0 +` each of `before` and `after` between: where the tape is and how wide the page's panel is at `t0 + 300`, which
/// is in use; where the move before back had the tape and the page at `t0 + 110`, and where the move after it sets out
/// from then.
fn tape_turned(
  before : Array[Double],
  after : Array[Double],
) -> ((Double, Double), @sfdesk.TapePane, (Double, Double), (Double, Double)) {
  reset()
  let src = fixture("chat")
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=720.0, h=840.0, platform=0)
  t.run_for(@ui.move_most_ms)
  page_over(t, 720.0)
  let agent = @sfbase.view_of_chat(src, r).0.unwrap().agents[0].key
  let t0 = t.time()
  t.advance(between_frames_ms)
  @sfdesk.side_change(src, r, "open", Some(agent))
  for f in before {
    t.frame_at(t0 + f)
  }
  t.advance(t0 + 110.0 - t.time())
  let tree = @ui.view_tree().unwrap()
  tree.bring_to(t0 + 110.0)
  let was = @sfdesk.tape_along_at(t0 + 110.0)
  (@sfdesk.wide_back(src).unwrap())()
  tree.bring_to(t0 + 110.0)
  let from = @sfdesk.tape_along_at(t0 + 110.0)
  for f in after {
    t.frame_at(t0 + f)
  }
  t.frame_at(t0 + 300.0)
  (tape_now(), @sfdesk.wide.tape_at.get(), was, from)
}

///|
test "on the tape a side panel opened and the page brought back while the tape goes to it: from where it is then, the same at a moment whichever frames came between" {
  let one = tape_turned([], [])
  let many = tape_turned([12.0, 20.0, 37.0, 60.0, 90.0], [130.0, 170.0, 220.0, 260.0])
  let late = tape_turned([95.0], [250.0])
  assert_eq((many, late), (one, one))
  let (_, at, was, from) = one
  assert_eq(at, @sfdesk.TapePane::Page)
  // (back set out from where the move to the panel had the tape and the page's width at its moment, both)
  assert_eq(from, was)
  // (on its way to the panel then: moved past where the page has it, the page not yet as narrow as beside it)
  let (x_was, w_was) = was
  let (x_end, w_end) = one.0
  assert_true(x_was < x_end && w_was > w_end, msg="at back \{was}, at rest \{one.0}")
}

///|
test "on the tape the real button and back: the side panel comes over, back brings the page" {
  let t = tape_chat(0, 720.0, 840.0)
  page_over(t, 720.0)
  tap_said(t, "打开侧栏")
  t.leave()
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Panel)
  t.back()
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page)
}

///|
test "on the tape a page come on top waits anew each time: one waited for before, come back to before the core has it, waits again" {
  reset()
  let late = 10000.0
  let src = round_trip(fixture("chat"), late)
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=720.0, h=800.0, platform=0)
  t.draw()
  t.run_for(late * 6.0 + @ui.move_most_ms)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
  let a : ChatRef = { station: "ws1/st1", session: "s-c2", title: "首页的列表改成按天分组", station_name: "Studio" }
  let b : ChatRef = { station: "ws1/st2", session: "s-c3", title: "夜里的构建又失败了", station_name: "MBA" }
  // a chat whose view is on its way: brought over once its wait is over (page_local_ms), its view not come
  open_chat(a)
  @sfdesk.bring_page()
  t.run_for(page_local_ms + @ui.move_most_ms)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page)
  // the sidebar again; another chat; the first again, brought over: its view still on its way, it waits anew
  @sfdesk.wide.tape_ask.set(Some(@sfdesk.TapePane::Side))
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
  open_chat(b)
  t.run_for(@ui.move_most_ms)
  open_chat(a)
  @sfdesk.bring_page()
  t.run_for(page_local_ms / 2.0)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side, msg="waits anew")
  t.run_for(page_local_ms)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page)
}

///|
test "on the tape a page waiting as the tape is made again (大屏 and back) waits anew from then" {
  reset()
  let late = 10000.0
  let src = round_trip(fixture("chat"), late)
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=720.0, h=800.0, platform=0)
  t.draw()
  t.run_for(late * 6.0 + @ui.move_most_ms)
  open_chat({ station: "ws1/st1", session: "s-c2", title: "首页的列表改成按天分组", station_name: "Studio" })
  t.run_for(page_local_ms * 0.8)
  t.resize(1280.0, 800.0)
  t.run_for(@ui.move_most_ms)
  t.resize(720.0, 800.0)
  @sfdesk.bring_page()
  t.run_for(page_local_ms / 2.0)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side, msg="waits anew")
  t.run_for(page_local_ms)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page)
}

///|
/// What shows of the page at the right pulled across to `x1` by a finger, let go `held` finger's moves' time after it
/// went down: moved there in `steps` moves (none: down, then let go there, no move told between).
fn tape_pulled_over(steps : Int, x1 : Double, held : Int) -> @sfdesk.TapePane raise {
  let t = tape_chat(2, 720.0, 840.0, width="medium", height="medium")
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
  let x0 = 720.0 - @sfdesk.tape_shows / 2.0
  if steps == 0 {
    t.press_at(x0, 400.0)
    t.advance(@ui.input_step_ms * held.to_double())
    t.release(x1, 400.0)
  } else {
    t.drag(x0, 400.0, x1, 400.0, steps~)
  }
  t.run_for(@ui.move_most_ms)
  @sfdesk.wide.tape_at.get()
}

///|
test "on the tape what shows of the page pulled across and let go brings it over, its moves told or only where it was let go" {
  assert_eq(tape_pulled_over(6, 360.0, 6), @sfdesk.TapePane::Page)
  assert_eq(tape_pulled_over(0, 360.0, 6), @sfdesk.TapePane::Page)
  // a short flick, down and let go a little way across soon after, no move told: flung over by its speed from its down
  assert_eq(tape_pulled_over(0, 720.0 - @sfdesk.tape_shows / 2.0 - 60.0, 2), @sfdesk.TapePane::Page)
  // as far, let go slowly: not flung, back
  assert_eq(tape_pulled_over(0, 720.0 - @sfdesk.tape_shows / 2.0 - 60.0, 60), @sfdesk.TapePane::Side)
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
