// An agent at work in a chat (Chat.kt Activity): its ring of eight arcs steps round, a step every 100 ms (Spokes.kt;
// the steps themselves: src/sf/spokes_test.mbt).

///|
test "activity: its ring steps round" {
  reset()
  let clock : Ref[Double] = { val: 0.0 }
  fix_clock.val = Some(fn() { clock.val })
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  t.tap_text("发消息")
  t.type_text("测试一下")
  tap_send(t)
  // delivered: its agent at work (the station's clock stays, so its turn's time does too)
  clock.val = clock.val + fix_deliver_ms
  t.draw()
  t.run_for(flight_wait_ms + @ui.move_most_ms + 1000.0)
  assert_true(t.find(tr("android-chat.chat.working")) is Some(_))
  // the keyboard put away: the field's caret no longer blinks
  t.keyboard_gone()
  let at = t.drawlist()
  t.run_for(@sf.spoke_step_ms)
  assert_true(t.drawlist() != at)
  fix_clock.val = None
}

///|
/// How soon after the words sent land their agent starts in activity_followed: soon enough that its line comes in
/// while the list has just come to rest at its end.
let agent_soon_ms : Double = 100.0

///|
/// The frames of a 120 Hz display, each drawn (a host's, not only the moments something is due).
let display_frame_ms : Double = 1000.0 / 120.0

///|
test "activity: its line coming in at the list's end is followed, the list gliding to its end as the line opens" {
  reset()
  let clock : Ref[Double] = { val: 0.0 }
  fix_clock.val = Some(fn() { clock.val })
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
  // (its line's first frame laid out twice, its room not opened yet at the first: a glide that set out then is under
  // way at the second, not over with the line still to open under the composer)
  t.set_frame_period(display_frame_ms)
  t.run_for(@ui.move_most_ms)
  t.tap_text("发消息")
  t.type_text("测试一下")
  tap_send(t)
  // delivered, its agent not at work yet; at work a moment later
  fix_later(fix_deliver_ms + 1.0, fn() { fix_chat("s-c1").working = -1.0 })
  clock.val = clock.val + fix_deliver_ms + 1.0
  t.draw()
  t.run_for(agent_soon_ms)
  assert_true(t.at_end())
  fix_later(1.0, fn() { fix_chat("s-c1").working = clock.val })
  clock.val = clock.val + 1.0
  t.draw()
  t.run_for(flight_wait_ms)
  assert_true(t.find(tr("android-chat.chat.working")) is Some(_))
  assert_true(t.at_end())
  fix_clock.val = None
}

///|
test "its avatar is back in its activity once a message has come out of it, the agent still at work" {
  let clock = Ref::new(0.0)
  let t = emit_core(clock)
  let em = emits_of("ws1/st1\u{1}s-c1")
  clock.val = clock.val + fix_answer_ms
  t.draw()
  t.run_for(emit_all_ms())
  assert_true(em.watched.get())
  assert_true(em.current.get() is None)
  assert_true(t.find(tr("android-chat.chat.working")) is Some(_))
  // (the copy that flew is gone: the activity's own avatar shows again)
  assert_eq(em.copied.get(), "")
  emit_restore()
}
