// An agent at work in a chat (Chat.kt Activity): its ring of eight arcs steps round, a step every 100 ms (Spokes.kt;
// the steps themselves: src/sf/spokes_test.mbt).

///|
test "activity: its ring steps round" {
  new_run()
  let clock : Ref[Double] = { val: 0.0 }
  fix_clock.val = Some(fn() { clock.val })
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
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
/// The working agent's card, returned only for that agent as the core would return it.
fn activity_card_tester(w : Double, h : Double, platform : Int) -> @ui.Tester {
  new_run()
  let base = fixture("chat-working")
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      let got = (base.topic)(name, params)
      if name == "agentCard" && text(Some(Json::object(params)), "key") != "s-c1" {
        { ..got, value: None }
      } else {
        got
      }
    },
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~)
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// The centre of the picture in the working agent's activity line.
fn activity_picture(t : @ui.Tester) -> (Double, Double) raise {
  let lines = t.all(Button).filter(fn(s) { s.label.has_prefix("Claude：") })
  assert_eq(lines.length(), 1, msg="the working agent's line")
  let (x, y, _, h) = lines[0].rect
  (x + 12.0, y + h / 2.0)
}

///|
test "activity: the picture opens its agent's card under the pointer, and still opens its history when pressed" {
  for (w, h) in [(390.0, 844.0), (900.0, 800.0), (1280.0, 800.0)] {
    let t = activity_card_tester(w, h, 0)
    let (x, y) = activity_picture(t)
    assert_true(t.find("8 轮 · 共干了 1 小时 12 分") is None)
    let (wx, wy, ww, wh) = t.rect_of(@sffixture.working_step).unwrap()
    t.move(wx + ww / 2.0, wy + wh / 2.0)
    t.run_for(@sfpages.hover_open_ms * 2.0)
    assert_true(t.find("8 轮 · 共干了 1 小时 12 分") is None, msg="the activity's words do not open the card")
    t.move(x, y)
    t.run_for(@sfpages.hover_open_ms * 2.0)
    let card = t.rect_of("8 轮 · 共干了 1 小时 12 分")
    assert_true(card is Some(_), msg="the working agent's card appears over its picture")
    let (cx, cy, cw, ch) = card.unwrap()
    // The pointer can cross into the card and use it without it disappearing.
    t.move(cx + cw / 2.0, cy + ch / 2.0)
    t.run_for(@sfpages.hover_close_ms * 2.0)
    assert_true(t.find("8 轮 · 共干了 1 小时 12 分") is Some(_))
    t.move(1.0, 1.0)
    t.run_for(@sfpages.hover_close_ms * 2.0)
    assert_true(t.find("8 轮 · 共干了 1 小时 12 分") is None)
    t.tap(x, y)
    t.frame()
    let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
    if w >= 600.0 {
      assert_eq(side_now(r).1, "s-c1", msg="pressing the picture opens this agent's history")
    } else {
      assert_true(app.nav.top() is History(_, "s-c1", _), msg="pressing the picture opens this agent's history")
    }
  }
}

///|
test "activity: a touch on the picture still opens its agent's history" {
  let t = activity_card_tester(390.0, 844.0, 2)
  let (x, y) = activity_picture(t)
  t.tap(x, y)
  t.frame()
  assert_true(app.nav.top() is History(_, "s-c1", _))
}

///|
test "activity: a mouse used with a touch-native system opens the same card" {
  let t = activity_card_tester(390.0, 844.0, 2)
  let (x, y) = activity_picture(t)
  t.host_says_finger(Some(false))
  t.move(x, y)
  t.run_for(@sfpages.hover_open_ms * 2.0)
  assert_true(t.find("8 轮 · 共干了 1 小时 12 分") is Some(_))
}

///|
test "activity: its line coming in at the list's end is followed, the list gliding to its end as the line opens" {
  new_run()
  let clock : Ref[Double] = { val: 0.0 }
  fix_clock.val = Some(fn() { clock.val })
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
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
  assert_true(em.watched)
  assert_true(em.current is None)
  assert_true(t.find(tr("android-chat.chat.working")) is Some(_))
  // (the copy that flew is gone: the activity's own avatar shows again)
  assert_eq(em.copied, "")
  emit_restore()
}
