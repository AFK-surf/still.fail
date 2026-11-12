// The keyboard's focus is only in what shows (the one rule: Ctx::focus_taken_under, the stack its third caller,
// Nav::told_focus): a chat's message field with the focus, a page put over the chat (its web service's, by its card in
// the chat or pushed) takes it; nothing typed there goes into the field under it, its input method put away, a panel
// of nodes opened there closed by Escape; back on the chat, the field has it again, what was written still there. A
// page gone before it is come back to takes it with it, at that cause; one kept shown in place till the one put there
// has its view (大屏's pane) keeps it till it is let go. With a keyboard and mouse (the chat gives its field the focus
// as it opens) and with a finger (the field pressed first).

///|
/// The chat-screens fixture's chat open on 小屏, its message field with the focus (a finger's pressed; a keyboard's
/// given it as the chat opens) and "写" written in it.
fn covered_chat(platform : Int, mode? : String = "chat-screens") -> @ui.Tester raise {
  @sf.presenters_reset()
  new_run()
  let src = fixture(mode)
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform~)
  t.run_for(@ui.move_most_ms)
  if platform == 2 {
    t.act(TextField, Focus, label="发消息")
  }
  t.type_text("写")
  t.draw()
  assert_eq(t.focused().map(fn(s) { s.label }), Some("发消息"))
  assert_eq(composer_said(t), "写")
  t
}

///|
/// The chat's web service opened by its card in the chat (its words' link: open_link, open_page), slid in.
fn covered_by_card(t : @ui.Tester) -> Unit raise {
  scroll_to_words(t, "打开定价页")
  middle_words(t, "打开定价页")
  t.tap_text("打开定价页")
  t.frame()
  t.frame()
  t.run_for(@ui.move_most_ms)
  guard app.nav.top() is Service(_, _) else { fail("no service on top") }
}

///|
/// The field's: none of the focus, the input method put away, nothing typed going into it.
fn covered_none_of_it(t : @ui.Tester, msg : String) -> Unit raise {
  assert_false(t.focused().map(fn(s) { s.label }) == Some("发消息"), msg="\{msg}: the focus under it: \{t.focus_said()}")
  assert_false(t.ime().0, msg="\{msg}: the input method up under it: \{Repr(t.ime())}")
  t.type_text("q")
  t.draw()
}

///|
/// Back on the chat (`back`), slid there: the field with the focus and its input method again, "写" in it, nothing typed
/// over it.
fn covered_back(t : @ui.Tester, back : () -> Unit, msg : String) -> Unit raise {
  back()
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  guard app.nav.top() is Chat(_) else { fail("\{msg}: not back on the chat") }
  assert_eq(t.focused().map(fn(s) { s.label }), Some("发消息"), msg="\{msg}: the focus back: \{t.focus_said()}")
  assert_true(t.ime().0, msg="\{msg}: the input method back: \{Repr(t.ime())}")
  t.type_text("回")
  t.draw()
  assert_eq(composer_said(t), "写回", msg="\{msg}: what was written still there, nothing typed over it")
}

///|
test "小屏: a chat's field with the focus, its web service opened by its card over it: none of the field's there; back, all of it again" {
  for platform in [0, 2] {
    let msg = "platform \{platform}"
    let t = covered_chat(platform)
    covered_by_card(t)
    covered_none_of_it(t, msg)
    covered_back(t, fn() { app.nav.pop() |> ignore }, msg)
  }
}

///|
test "小屏: the web service pushed over a chat whose field has the focus: none of it there, a panel of nodes there closed by Escape" {
  for platform in [0, 2] {
    let msg = "platform \{platform}"
    let t = covered_chat(platform, mode="service")
    app.nav.push(Service("ws1/st1", "j-web"))
    t.frame()
    t.run_for(@ui.move_most_ms)
    covered_none_of_it(t, msg)
    svc_open(t, "资源加载 75% · 3/4")
    t.run_for(@ui.move_most_ms)
    assert_true(@sf.presenter_visible(), msg="\{msg}: the panel up")
    t.key(@ui.key_escape)
    t.run_for(@ui.move_most_ms)
    t.run_for(@ui.move_most_ms)
    assert_false(@sf.presenter_visible(), msg="\{msg}: Escape closes it")
    covered_back(t, fn() { app.nav.pop() |> ignore }, msg)
  }
}

///|
test "小屏: back to the chat by the system's back gesture: the focus back as it goes back; called off, nothing changes" {
  let t = covered_chat(2)
  covered_by_card(t)
  // (begun and called off: the service stays, the focus none of the field's)
  t.back_gesture(200.0, false)
  t.run_for(@ui.move_most_ms)
  guard app.nav.top() is Service(_, _) else { fail("called off: the service stays") }
  covered_none_of_it(t, "called off")
  // (gone back)
  covered_back(t, fn() { t.back_gesture(200.0, true) }, "gone back")
}

///|
test "小屏: the chat gone from the stack before it is come back to: what had the focus in it gone with it" {
  for platform in [0, 2] {
    let msg = "platform \{platform}"
    let t = covered_chat(platform)
    covered_by_card(t)
    // (back to Home, the chat and its service taken off at once)
    app.nav.pop_to(1) |> ignore
    t.run_for(@ui.move_most_ms)
    t.run_for(@ui.move_most_ms)
    guard app.nav.top() is Home else { fail("\{msg}: not Home") }
    assert_eq(t.focused().map(fn(s) { s.label }), None, msg="\{msg}: \{t.focus_said()}")
    assert_false(t.ime().0, msg="\{msg}: \{Repr(t.ime())}")
  }
}

///|
test "小屏: back to Home from a chat whose field has the focus: none of it from that moment, nothing typed going into the chat sliding away" {
  for platform in [0, 2] {
    let msg = "platform \{platform}"
    let t = covered_chat(platform)
    app.nav.pop_to(1) |> ignore
    // (typed at the cause's moment, no frame between: the chat still drawn as it slides away)
    t.type_text("z")
    assert_eq(composer_said(t), "写", msg="\{msg}: typed into the chat leaving")
    assert_false(t.focused().map(fn(s) { s.label }) == Some("发消息"), msg="\{msg}: \{t.focus_said()}")
    assert_false(t.ime().0, msg="\{msg}: \{Repr(t.ime())}")
    t.run_for(@ui.move_most_ms)
    guard app.nav.top() is Home else { fail("\{msg}: not Home") }
    assert_eq(t.focused().map(fn(s) { s.label }), None, msg="\{msg}: \{t.focus_said()}")
  }
}

///|
/// The rect of the message field drawn (the one shown), and what is written in it.
fn composer_seen(t : @ui.Tester) -> ((Double, Double, Double, Double), String) {
  let s = t.semantics().iter().find_first(fn(s) { s.role == TextField && s.label == "发消息" })
  (s.map(fn(s) { s.rect }).unwrap_or((-1.0, -1.0, -1.0, -1.0)), s.map(fn(s) { s.value }).unwrap_or("?"))
}

///|
test "大屏: another chat put in place, the one before kept shown till it has its view: that one's field keeps the focus and its shape meanwhile; let go, the focus the chat come's" {
  new_run()
  let answered = @signals.signal(false)
  let src = over_source(answered)
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.draw()
  t.run_for(@ui.move_most_ms)
  t.type_text("写")
  assert_eq(t.focused().map(fn(s) { s.label }), Some("发消息"), msg=t.focus_said())
  let before = composer_seen(t)
  assert_eq(before.1, "写")
  // (put in place: the one before kept while it waits)
  @sfbase.open_page(Chat(over_chat))
  t.frame()
  assert_true(app.nav.top() is Chat({ session: "s-c2", .. }))
  assert_eq(t.focused().map(fn(s) { s.label }), Some("发消息"), msg="kept: \{t.focus_said()}")
  t.run_for(@ui.move_most_ms)
  assert_eq(composer_seen(t), before)
  assert_eq(t.focused().map(fn(s) { s.label }), Some("发消息"), msg="kept a while: \{t.focus_said()}")
  // (its view given: the one kept let go, the chat come's field with the focus, nothing of the one before's in it)
  answered.set(true)
  t.run_for(@ui.move_most_ms)
  assert_eq(t.focused().map(fn(s) { s.label }), Some("发消息"), msg="come: \{t.focus_said()}")
  assert_eq(composer_seen(t).1, "")
  t.type_text("新")
  assert_eq(composer_seen(t).1, "新")
}

///|
/// The card's preview is the card's, by its key: scrolled up to it, the older page coming in before it (its row built
/// at another place in the list, its ids with it), it goes on as it was, asked of its station once and its picture
/// handed to the host once.
test "小屏: a screen card's preview goes on as older messages come in before its row: asked once, its picture handed over once" {
  let t = covered_chat(0)
  let (first, _) = t.visible()
  assert_eq(@sfbase.peek_views.val, 1)
  scroll_to_words(t, "打开定价页")
  middle_words(t, "打开定价页")
  t.run_for(@ui.move_most_ms)
  let (now, _) = t.visible()
  assert_true(now > first, msg="its row at another place: \{first} then \{now}")
  assert_eq(@sfbase.peek_views.val, 1)
  let mut got = 0
  for _, p in @sfbase.peeks {
    got += p.got
  }
  assert_eq(got, 1)
}
