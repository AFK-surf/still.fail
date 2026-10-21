// An agent at work in a chat (Chat.kt Activity): its ring of eight arcs steps round, a step every 100 ms (Spokes.kt;
// the steps themselves: src/sf/spokes_test.mbt).

///|
test "activity: its ring steps round" {
  reset()
  let clock : Ref[Double] = { val: 0.0 }
  fix_clock.val = Some(fn() { clock.val })
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0)
  t.run_for(@ui.nav_push_ms)
  t.tap_text("发消息")
  t.type_text("测试一下")
  tap_send(t)
  // delivered: its agent at work (the station's clock stays, so its turn's time does too)
  clock.val = clock.val + fix_deliver_ms
  t.draw()
  t.run_for(flight_wait_ms + composer_morph_ms + 1000.0)
  assert_true(t.find(tr("android-chat.chat.working")) is Some(_))
  // the keyboard put away: the field's caret no longer blinks
  t.keyboard_gone()
  let at = t.drawlist()
  t.run_for(@sf.spoke_step_ms)
  assert_true(t.drawlist() != at)
  fix_clock.val = None
}
