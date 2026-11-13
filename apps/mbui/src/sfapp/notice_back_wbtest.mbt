// Notifications and outside links bring their target page into view on the tape (Medium) so system back returns to the
// sidebar rather than leaving the app, while sidebar clicks still keep the sidebar in use.

///|
fn notice_back_case(
  w : Double,
  h : Double,
  opens : String,
  async_parse? : Bool = false,
  delay_chat? : Bool = false,
  setup? : (@ui.Tester) -> Unit = fn(_) {  },
) -> (@ui.Tester, @signals.Signal[@sfbase.Topic]) raise {
  new_run()
  let base = fixture("home")
  let chat_sig : @signals.Signal[@sfbase.Topic] = @signals.signal({ value: None, error: None, version: 1 })
  let pending_parse : Ref[(() -> Unit)?] = Ref(None)
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      if delay_chat && name == "chat" && @sfbase.text(Some(Json::object(params)), "session") == "s-c2" {
        chat_sig.get()
      } else {
        base.topic(name, params).get().snapshot()
      }
    },
    call: fn(name, params, done) {
      if async_parse && name == "link.parse" {
        let url = text(Some(params), "url")
        pending_parse.val = Some(fn() { done(Ok(fixture_link_parse(url))) })
      } else {
        (base.call)(name, params, done)
      }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform=2)
  t.run_for(@ui.move_most_ms)
  setup(t)
  @ui.notice_show(channel="消息", tag="back", title="通知", body="打开", opens~)
  guard t.tap_notice("打开") else { fail("notice not tapped") }
  t.draw()
  if async_parse {
    t.frame()
    match pending_parse.val {
      Some(f) => f()
      None => ()
    }
    t.draw()
  }
  (t, chat_sig)
}

///|
test "foldable tape: notifications bring their page over from the sidebar and take system back back to the sidebar" {
  let cases = [
    ("item", "/o/ws1/st1/s-c2\n2", false, fn(_ : @ui.Tester) {  }, @sfdesk.TapePane::Side, false),
    ("async item", "/o/ws1/st1/s-c2\n2", true, fn(_ : @ui.Tester) {  }, @sfdesk.TapePane::Side, false),
    ("other workspace item", "/o/ws2/st9/s-x\n1", true, fn(_ : @ui.Tester) {  }, @sfdesk.TapePane::Side, false),
    ("service", "/w/ws1/s/st1/services/j-web", false, fn(_ : @ui.Tester) {  }, @sfdesk.TapePane::Side, false),
    ("chat link", "/w/ws1/s/st1/chats/s-c2", false, fn(_ : @ui.Tester) {  }, @sfdesk.TapePane::Side, false),
    ("from files", "/o/ws1/st1/s-c2\n2", false, fn(t : @ui.Tester) {
      @sfbase.go_place("files") |> ignore
      t.draw()
      t.run_for(@ui.move_most_ms)
    }, @sfdesk.TapePane::Side, false),
    ("from side after chat back", "/o/ws1/st1/s-c2\n2", false, fn(t : @ui.Tester) {
      open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
      @sfdesk.bring_page()
      t.draw()
      t.run_for(@ui.move_most_ms)
      t.back()
      t.run_for(@ui.move_most_ms)
    }, @sfdesk.TapePane::Side, false),
    ("adb settings", "settings:adb:", false, fn(_ : @ui.Tester) {  }, @sfdesk.TapePane::Side, true),
  ]
  for w in [826.0, 690.0] {
    for c in cases {
      let (name, opens, async_parse, setup, back_pane, back_still_takes) = c
      let (t, _) = notice_back_case(w, 749.0, opens, async_parse~, setup~)
      assert_true(t.takes_back(), msg="\{w} \{name}: takes back immediately")
      t.run_for(@ui.move_most_ms)
      assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page, msg="\{w} \{name}: page brought over")
      assert_true(t.takes_back(), msg="\{w} \{name}: takes back settled")
      t.back()
      t.run_for(@ui.move_most_ms)
      assert_eq(@sfdesk.wide.tape_at.get(), back_pane, msg="\{w} \{name}: back to sidebar")
      assert_eq(t.takes_back(), back_still_takes, msg="\{w} \{name}: takes back after returning")
    }
  }
}

///|
test "foldable tape: back pressed while a notified chat is still loading cancels the bring instead of exiting" {
  let (t, chat_sig) = notice_back_case(826.0, 749.0, "/o/ws1/st1/s-c2\n2", delay_chat=true)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
  assert_eq(@sfdesk.wide.tape_ask.get(), Some(@sfdesk.TapePane::Page))
  assert_true(t.takes_back(), msg="takes back while waiting to bring page")
  t.back()
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
  assert_eq(@sfdesk.wide.tape_ask.get(), None)
  assert_false(t.takes_back())
  // now let a second notice load its chat, wait for Page to arrive, and back returns to Side
  chat_sig.set(fixture("home").topic("chat", { "station": "ws1/st1", "session": "s-c2" }).get().snapshot())
  @ui.notice_show(channel="消息", tag="back2", title="通知", body="再打开", opens="/o/ws1/st1/s-c2\n2")
  assert_true(t.tap_notice("再打开"))
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page)
  assert_true(t.takes_back())
  t.back()
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
  assert_false(t.takes_back())
}

///|
test "foldable tape: choosing a chat from the sidebar itself still leaves the sidebar in use" {
  new_run()
  let src = fixture("home")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=826.0, h=749.0, platform=2)
  t.run_for(@ui.move_most_ms)
  t.tap_text("首页的列表改成按天分组")
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
  assert_false(t.takes_back())
}

///|
test "phone: notifications open over Home and system back returns to Home without exiting" {
  for c in [
    ("/o/ws1/st1/s-c2\n2", true),
    ("/o/ws2/st9/s-x\n1", true),
    ("/w/ws1/s/st1/chats/s-c2", false),
    ("/w/ws1/s/st1/services/j-web", false),
    ("settings:adb:", false),
  ] {
    let (opens, async_parse) = c
    let (t, _) = notice_back_case(390.0, 844.0, opens, async_parse~, setup=fn(t) {
      t.tap_text("文件")
      t.draw()
      t.run_for(@ui.move_most_ms)
    })
    assert_true(t.takes_back(), msg=opens)
    t.run_for(@ui.move_most_ms)
    assert_true(t.takes_back(), msg=opens)
    t.back()
    t.run_for(@ui.move_most_ms)
    assert_true(app.nav.top() == Home, msg=opens)
    assert_false(t.takes_back(), msg=opens)
  }
}
