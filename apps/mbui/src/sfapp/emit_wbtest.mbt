// An agent's answer coming out of its activity's avatar (emit.mbt, ChatMotion.kt), over the fixture's station: what
// is sent sets its agent to work (its activity shows), its answer is said while the chat shows.

///|
/// The fixture's chat open, its clock the test's; words sent and taken by the station (its agent then at work).
fn emit_core(clock : Ref[Double]) -> @ui.Tester {
  reset()
  fix_clock.val = Some(fn() { clock.val })
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0)
  // the chat pushed in over Home
  t.run_for(@ui.nav_push_ms)
  t.tap_text("发消息")
  t.type_text("看一下列表")
  tap_send(t)
  // the station has it: in the chat, its agent at work
  clock.val = clock.val + fix_deliver_ms
  t.draw()
  // (the station answers fix_answer_ms after it took them: that time passes on the page too, the words sent landed
  // and the agent's line come in their turns meanwhile)
  t.run_for(fix_answer_ms)
  t
}

///|
/// A message's whole way out of its avatar: fold, float, spit, return.
fn emit_all_ms() -> Double {
  Pose::Fold.ms() + Pose::Float.ms() + Pose::Spit.ms() + Pose::Return.ms()
}

///|
fn emit_restore() -> Unit {
  fix_clock.val = None
}

///|
test "an answer said while its agent's activity shows waits, then comes out of its avatar: fold, float, spit, return" {
  let clock = Ref::new(0.0)
  let t = emit_core(clock)
  // at work: its activity
  assert_true(t.find("看一下列表") is Some(_))
  let em = emits_of("ws1/st1\u{1}s-c1")
  clock.val = clock.val + fix_answer_ms
  t.draw()
  // the answer is taken: it waits (folding, then the avatar on its way), not in the list yet
  assert_eq(em.queue.length() + (if em.current is Some(_) { 1 } else { 0 }), 1)
  assert_true(t.find("收到：「看一下列表」") is None)
  // fold and float: it comes into the list as the avatar lands
  t.run_for(Pose::Fold.ms() + Pose::Float.ms())
  assert_true(t.find("收到：「看一下列表」") is Some(_))
  t.run_for(Pose::Spit.ms() + Pose::Return.ms())
  assert_true(em.current is None)
  assert_true(t.find("收到：「看一下列表」") is Some(_))
  emit_restore()
}

///|
test "with the reader scrolled up (not watched), an answer just appears" {
  let clock = Ref::new(0.0)
  let t = emit_core(clock)
  t.wheel(195.0, 400.0, -600.0)
  let em = emits_of("ws1/st1\u{1}s-c1")
  clock.val = clock.val + fix_answer_ms
  t.draw()
  assert_true(em.current is None)
  assert_eq(em.queue.length(), 0)
  assert_false(emit_held(em, 102.0))
  emit_restore()
}

///|
test "the answer coming in does not end its own motion: float, spit and return each played whole, the avatar drawn" {
  let clock = Ref::new(0.0)
  let t = emit_core(clock)
  let em = emits_of("ws1/st1\u{1}s-c1")
  clock.val = clock.val + fix_answer_ms
  t.draw()
  let frames : Map[String, Int] = {}
  // frame by frame over its whole way out
  let end = t.time() + emit_all_ms()
  while t.time() < end {
    t.frame()
    match em.current {
      Some(turn) => {
        let k = turn.pose.to_string()
        frames[k] = frames.get(k).unwrap_or(0) + 1
        // the flying copy is drawn in every pose after the fold (emit_flyer)
        if turn.pose != Fold {
          assert_true(emit_flight(t.ctx(), "ws1/st1\u{1}s-c1", em, [turn.agent]) is Some(_))
        }
      }
      None => ()
    }
  }
  // 16 ms frames: Float 440 ms, Spit 380, Return 320 (ChatMotion.kt), each to its end
  assert_true(frames.get("Float").unwrap_or(0) >= 26)
  assert_true(frames.get("Spit").unwrap_or(0) >= 22)
  assert_true(frames.get("Return").unwrap_or(0) >= 18)
  assert_true(em.current is None)
  emit_restore()
}
