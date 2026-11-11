// Sharing in (share.mbt) over the fixture (share_fixture.mbt): the sheet, a chat tapped (shareIn.open, the chat opened),
// a new chat on a station chosen.

///|
fn share_tester(mode : String) -> @ui.Tester {
  new_run()
  let src = fixture(mode)
  open_drive_fixture(mode)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  // the fixture's pages in
  nav_rested(t)
  t
}

///|
test "shared in: what is shared, 发到 the chats (the one the site went to last first, saying so), 新建对话" {
  let t = share_tester("share-in")
  assert_true(t.find("列表滑动的十个细节") is Some(_))
  assert_true(t.find("发到") is Some(_))
  assert_true(t.find("youtube.com 的链接上次发到这里") is Some(_))
  assert_true(t.find("新建对话") is Some(_))
  assert_true(t.find("整理发布清单") is Some(_))
}

///|
test "a chat tapped: what is shared goes to its composer and the chat opens; 新建对话 rises a new chat" {
  let t = share_tester("share-in")
  t.tap_text("收集视频")
  match app.nav.top() {
    Chat(r) => assert_eq(r.session, "s-c4")
    _ => fail("not the chat")
  }
  // (what the sheet shows kept as it was while it sinks away, let go of once it has gone)
  assert_true(share_in.shared.get() is Some(_))
  sheet_rested(t, "sf-present")
  t.frame()
  assert_true(share_in.shared.get() is None)
  let n = share_tester("share-in-stations")
  // (the station chosen on the new chat's page, as any new chat's: not listed here)
  n.tap_text("新建对话")
  assert_true(app.nav.top() is NewChat)
  nav_rested(n)
}

///|
test "over another app (ShareActivity): only the sheet; a chat tapped opens the app at it, over Home" {
  let t = share_tester("share-in")
  t.post(@hostapi.system_channel, "{\"over\":true}")
  t.frame()
  assert_true(share_over.get())
  assert_true(t.find("发到") is Some(_))
  t.tap_text("收集视频")
  assert_eq(t.overs_done(), [true])
  assert_eq(app.nav.depth(), 2)
  match app.nav.top() {
    Chat(r) => assert_eq(r.session, "s-c4")
    _ => fail("not the chat")
  }
}

///|
test "over another app, the sheet closed: the app goes once it has sunk away, back to where the person was" {
  let t = share_tester("share-in")
  t.post(@hostapi.system_channel, "{\"over\":true}")
  t.frame()
  lower_sheet()
  t.frame()
  assert_eq(t.overs_done(), [])
  sheet_rested(t, "sf-present")
  t.frame()
  assert_eq(t.overs_done(), [false])
}

///|
test "over another app signed out: to sign in in the app first, 打开 still.fail opens it" {
  new_run()
  let src = fixture("signin")
  share_in.shared.set(Some(fix_shared))
  share_in.env_taken.set(true)
  raise_sheet(ShareSheet)
  share_in.raised.set(true)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.post(@hostapi.system_channel, "{\"over\":true}")
  t.frame()
  sheet_rested(t, "sf-present")
  assert_true(t.find("先在 still.fail 里登录，再来分享") is Some(_))
  t.tap_text("打开 still.fail")
  assert_eq(t.overs_done(), [true])
}

///|
/// Where a toast's words end over another app with the navigation bar `foot` high under the view (the host's `bars`).
fn over_toast_foot(foot : Double) -> Double raise {
  let t = share_tester("share-in")
  t.post(@hostapi.system_channel, "{\"over\":true,\"bars\":{\"top\":24,\"bottom\":\{foot},\"left\":0,\"right\":0}}")
  t.frame()
  sheet_rested(t, "sf-present")
  @sfbase.toast_later("发到了")
  // (come in: where its words are drawn as it rests)
  t.run_for(@kit.presence_in_ms)
  match t.rect_of("发到了") {
    Some((_, y, _, h)) => y + h
    None => fail("no toast")
  }
}

///|
test "over another app, the view under the bars: the toasts kept above the navigation bar" {
  let bare = over_toast_foot(0.0)
  assert_eq(@ui.system_bars().bottom, 0.0)
  let under = over_toast_foot(48.0)
  assert_eq(@ui.system_bars().bottom, 48.0)
  assert_eq(bare - under, 48.0)
}
