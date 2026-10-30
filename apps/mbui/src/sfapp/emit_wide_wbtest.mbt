// An answer coming out of its agent's avatar in the desktop's frame, the chat beside the sidebar: the flying avatar
// drawn where emit.mbt has it in the window, not off by where the chat stands in it.

///|
test "wide: an agent's picture in its line is where its answer's is, out in the margin: the flying one lands with no step aside" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat")
  let clock = Ref::new(0.0)
  fix_clock.val = Some(fn() { clock.val })
  t.tap_text("发消息")
  t.type_text("看一下列表")
  tap_send(t)
  clock.val = clock.val + fix_deliver_ms
  t.draw()
  t.run_for(fix_answer_ms)
  clock.val = clock.val + fix_answer_ms
  t.draw()
  t.run_for(Pose::Fold.ms() + Pose::Float.ms() + Pose::Spit.ms() / 2.0)
  let (face, lands) = landing_faces(t)
  assert_true((face - lands).abs() < 0.5, msg="\{face} \{lands}")
  fix_clock.val = None
}

///|
test "wide: the avatar an answer comes out of is drawn where it flies in the window, the chat beside the sidebar" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat")
  let clock = Ref::new(0.0)
  fix_clock.val = Some(fn() { clock.val })
  t.tap_text("发消息")
  t.type_text("看一下列表")
  tap_send(t)
  // the station has it, its agent at work; its answer said a moment on
  clock.val = clock.val + fix_deliver_ms
  t.draw()
  t.run_for(fix_answer_ms)
  clock.val = clock.val + fix_answer_ms
  t.draw()
  let em = emits_of("ws1/st1\u{1}s-c1")
  // folded, then on its way: half way through its float
  t.run_for(Pose::Fold.ms() + Pose::Float.ms() / 2.0)
  guard em.current.get() is Some(turn) && turn.pose == Float else {
    fail("not on its way: \{em.current.get().map(fn(c) { c.pose })}")
  }
  let (x, y, _, _) = emit_flight(t.ctx(), "ws1/st1\u{1}s-c1", em, [turn.agent]).unwrap()
  // its 18 face's ground drawn there (scaled about its middle as it flies)
  let near = t.drawn_rects().filter(fn(r) { (r.0 - x).abs() < 2.0 && (r.1 - y).abs() < 2.0 && r.2 > 14.0 && r.2 < 22.0 })
  assert_true(near.length() > 0, msg="nothing drawn at \{(x, y)}")
  fix_clock.val = None
}
