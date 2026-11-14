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

///|
test "phone: cold start, overlays, and predictive back return to Home" {
  // Existing chat -> another chat notice -> predictive back (0 -> 1 -> 2)
  let (t1, _) = notice_back_case(390.0, 844.0, "/o/ws1/st1/s-c2?message=2\n2", async_parse=true, setup=fn(t) {
    t.check_looks(false)
    say_room(t, "compact", "medium")
    open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
    t.draw()
    t.run_for(@ui.move_most_ms)
  })
  assert_true(t1.takes_back(), msg="existing chat immediate")
  t1.run_for(@ui.move_most_ms)
  assert_true(t1.takes_back(), msg="existing chat settled")
  t1.back_raw(0, 0.0, t1.time())
  t1.back_raw(1, 50.0, t1.time())
  t1.back_raw(2, 50.0, t1.time())
  t1.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() == Home, msg="existing chat back -> Home")
  assert_false(t1.takes_back(), msg="existing chat Home takes_back false")

  // Same chat -> notice -> predictive back
  let (t2, _) = notice_back_case(390.0, 844.0, "/o/ws1/st1/s-c2\n2", async_parse=true, setup=fn(t) {
    t.check_looks(false)
    say_room(t, "compact", "medium")
    open_chat({ station: "ws1/st1", session: "s-c2", title: "另一个", station_name: "Willow" })
    t.draw()
    t.run_for(@ui.move_most_ms)
  })
  assert_true(t2.takes_back(), msg="same chat immediate")
  t2.run_for(@ui.move_most_ms)
  assert_true(t2.takes_back(), msg="same chat settled")
  t2.back_raw(0, 0.0, t2.time())
  t2.back_raw(2, 50.0, t2.time())
  t2.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() == Home, msg="same chat back -> Home")

  // Delayed chat (still loading) on Small -> immediate back & after loaded
  let (t3, chat_sig) = notice_back_case(390.0, 844.0, "/o/ws1/st1/s-c2\n2", delay_chat=true, setup=fn(t) {
    t.check_looks(false)
  })
  assert_true(t3.takes_back(), msg="delayed chat immediate")
  chat_sig.set(fixture("home").topic("chat", { "station": "ws1/st1", "session": "s-c2" }).get().snapshot())
  t3.run_for(@ui.move_most_ms)
  assert_true(t3.takes_back(), msg="delayed chat loaded")
  t3.back()
  t3.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() == Home, msg="delayed chat back -> Home")

  // Cold start before first draw & with delayed workspaces
  new_run()
  let base = fixture("home")
  let ws_ready = @signals.signal(false)
  let src_cold : Source = {
    ..base,
    topic_read: fn(name, params) {
      if name == "workspaces" && !ws_ready.get() {
        return { value: None, error: None, version: 0 }
      }
      base.topic(name, params).get().snapshot()
    },
  }
  let t4 = @ui.Tester::new(fn(c) { view(c, src_cold) }, tree=app_tree(src_cold), w=390.0, h=844.0, platform=2)
  @ui.notice_show(channel="消息", tag="cold", title="通知", body="冷启动", opens="/o/ws1/st1/s-c2\n2")
  assert_true(t4.tap_notice("冷启动"))
  t4.draw()
  ws_ready.set(true)
  t4.draw()
  assert_true(t4.takes_back(), msg="cold start immediate takes_back")
  t4.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() is Chat(_), msg="cold start opened chat")
  assert_true(t4.takes_back(), msg="cold start chat takes_back")
  t4.back()
  t4.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() == Home, msg="cold start back -> Home")

  // Tap before first frame when workspaces are already available
  new_run()
  let src_first = fixture("home")
  let t5 = @ui.Tester::new(fn(c) { view(c, src_first) }, tree=app_tree(src_first), w=390.0, h=844.0, platform=2)
  @ui.notice_show(channel="消息", tag="first", title="通知", body="首帧", opens="/o/ws1/st1/s-c2\n2")
  assert_true(t5.tap_notice("首帧"))
  t5.draw()
  assert_true(t5.takes_back(), msg="first frame takes_back")
  t5.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() is Chat(_), msg="first frame opened chat")
  t5.back()
  t5.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() == Home, msg="first frame back -> Home")
}

///|
test "phone: mid-slide, pages, overlays, and menu return to Home on back" {
  // Mid-slide back gesture during push animation
  new_run()
  let src1 = fixture("home")
  let t1 = @ui.Tester::new(fn(c) { view(c, src1) }, tree=app_tree(src1), w=390.0, h=844.0, platform=2)
  t1.draw()
  @ui.notice_show(channel="c", tag="p1", title="t", body="p1", opens="/o/ws1/st1/s-c2\n2")
  t1.draw()
  assert_true(t1.tap_notice("p1"))
  t1.draw()
  assert_true(t1.takes_back(), msg="mid-slide immediate takes_back")
  t1.run_for(@ui.move_most_ms / 4.0)
  assert_true(t1.takes_back(), msg="mid-slide takes_back")
  t1.back_gesture(150.0, true, steps=4)
  t1.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() == Home, msg="mid-slide back -> Home")
  assert_false(t1.takes_back(), msg="mid-slide Home takes_back false")

  // Search overlay, Confirm modal, InviteLink sheet, app.menu, Files, History -> notice -> Home
  for case_name in ["search", "confirm", "sheet", "menu", "files", "history"] {
    new_run()
    let src = fixture("home")
    let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
    t.draw()
    match case_name {
      "search" => {
        t.tap_text("搜索全部内容")
        t.run_for(@ui.move_most_ms)
      }
      "confirm" => {
        @sf.confirm("Confirm?", "body", "OK", fn() {  })
        t.run_for(@ui.move_most_ms)
      }
      "sheet" => {
        raise_sheet(InviteLink)
        t.run_for(@ui.move_most_ms)
      }
      "menu" => {
        app.menu = true
        t.draw()
      }
      "files" => {
        open_page(Files)
        t.run_for(@ui.move_most_ms)
      }
      "history" => {
        let c1 : @sfbase.ChatRef = { station: "ws1/st1", session: "s-c1", title: "c1", station_name: "st1" }
        open_page(@sfbase.Page::Chat(c1))
        t.run_for(@ui.move_most_ms)
        open_page(@sfbase.Page::History(c1, "", None))
        t.run_for(@ui.move_most_ms)
      }
      _ => ()
    }
    @ui.notice_show(channel="c", tag="ov", title="t", body="ov", opens="/w/ws1/s/st1/chats/s-c2")
    t.draw()
    assert_true(t.tap_notice("ov"), msg=case_name)
    t.draw()
    assert_true(t.takes_back(), msg="\{case_name} immediate takes_back")
    t.run_for(@ui.move_most_ms)
    assert_true(app.nav.top() is Chat(_), msg="\{case_name} opened chat")
    assert_true(t.takes_back(), msg="\{case_name} settled takes_back")
    t.back()
    t.run_for(@ui.move_most_ms)
    assert_true(app.nav.top() == Home, msg="\{case_name} back -> Home")
  }

  // Bell (待处理) row -> chat -> back -> Home
  new_run()
  let t5 = tester("home-attention")
  t5.frame()
  let (bx, by, bw, bh) = named_at(t5, "待处理").unwrap()
  t5.tap(bx + bw / 2.0, by + bh / 2.0)
  t5.run_for(@ui.move_most_ms)
  t5.frame()
  let (rx, ry, rw, rh) = t5.rect_of("整理发布清单").unwrap()
  t5.tap(rx + rw / 2.0, ry + rh / 2.0)
  t5.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() is Chat(_), msg="attention opened chat")
  assert_true(t5.takes_back(), msg="attention takes_back")
  t5.back()
  t5.run_for(@ui.move_most_ms)
  if app.nav.top() != Home {
    t5.back()
    t5.run_for(@ui.move_most_ms)
  }
  assert_true(app.nav.top() == Home, msg="attention back -> Home")

  // Service URL (?service=) & history link (?history=) pop through Chat to Home
  for opens in ["/o/ws1/st1/s-c2?service=j-web", "/w/ws1/s/st1/chats/s-c2?history=s-c2"] {
    new_run()
    let src = fixture("home")
    let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
    t.draw()
    @ui.notice_show(channel="c", tag="deep", title="t", body="deep", opens~)
    t.draw()
    assert_true(t.tap_notice("deep"), msg=opens)
    t.draw()
    assert_true(t.takes_back(), msg="\{opens} immediate")
    t.run_for(@ui.move_most_ms)
    assert_true(t.takes_back(), msg="\{opens} settled")
    t.back()
    t.run_for(@ui.move_most_ms)
    if app.nav.top() != Home {
      assert_true(t.takes_back(), msg="\{opens} intermediate takes_back")
      t.back()
      t.run_for(@ui.move_most_ms)
    }
    assert_true(app.nav.top() == Home, msg="\{opens} back -> Home")
  }
}
