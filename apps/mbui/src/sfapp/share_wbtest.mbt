// Sharing in (share.mbt) over the fixture (share_fixture.mbt): the sheet, a chat tapped (shareIn.open, the chat opened),
// a new chat on a station chosen.

///|
fn share_tester(mode : String) -> @ui.Tester {
  reset()
  let src = fixture(mode)
  open_drive_fixture(mode)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
  // the fixture's pages in
  nav_rested(t)
  t
}

///|
test "shared in: what is shared, 发到 the chats (the one the site went to last first, saying so), 新 chat" {
  let t = share_tester("share-in")
  assert_true(t.find("列表滑动的十个细节") is Some(_))
  assert_true(t.find("发到") is Some(_))
  assert_true(t.find("youtube.com 的链接上次发到这里") is Some(_))
  assert_true(t.find("新 chat") is Some(_))
  assert_true(t.find("整理发布清单") is Some(_))
}

///|
test "a chat tapped: what is shared goes to its composer and the chat opens; a new chat on a station chosen rises" {
  let t = share_tester("share-in")
  t.tap_text("收集视频")
  match app.nav.top() {
    Chat(r) => assert_eq(r.session, "s-c4")
    _ => fail("not the chat")
  }
  assert_true(share_in.shared.get() is None)
  let n = share_tester("share-in-stations")
  assert_true(n.find("MBA") is Some(_))
  n.tap_text("MBA")
  assert_true(app.nav.top() is NewChat)
  nav_rested(n)
}

///|
test "a shared link in a draft: a card with its site, sent as words after what is written" {
  let d : Draft = {
    key: "ws1/st1:s-c4",
    text: @signals.signal(""),
    put_text: @signals.signal(None),
    field: @ui.Field::new(),
    quotes: @sf.LiveArray::from([]),
    comments: @sf.LiveMap::from({}),
    files: @sf.LiveArray::from([]),
    error: @signals.signal(None),
    loaded: @signals.signal(true),
    kept: @signals.signal(""),
    changed_at: @signals.signal(0.0, same=fn(a, b) { a == b }),
    warm_n: @signals.signal(1, same=fn(a, b) { a == b }),
    focus: @signals.signal(0, same=fn(a, b) { a == b }),
    id: @signals.signal("", same=fn(a, b) { a == b }),
  }
  fill_draft(d, {
    "text": "帮我下这个",
    "quotes": [],
    "files": [],
    "links": [{ "url": "https://www.youtube.com/watch?v=x", "title": "列表滑动", "site": "youtube.com" }],
  })
  assert_eq(d.files.length(), 1)
  assert_eq(up_files(d).length(), 0)
  assert_eq(with_link_words("帮我下这个", d), "帮我下这个\n列表滑动\nhttps://www.youtube.com/watch?v=x")
  assert_true(draft_view(d).get("links") is Some(_))
}

///|
test "over another app (ShareActivity): only the sheet; a chat tapped opens the app at it, over Home" {
  let t = share_tester("share-in")
  t.post(@hostapi.system_channel, "{\"over\":true}")
  t.frame()
  assert_true(share_over.val)
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
  reset()
  let src = fixture("signin")
  share_in.shared.set(Some(fix_shared))
  share_in.env_taken.set(true)
  raise_sheet(ShareSheet)
  share_in.raised.set(true)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
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
  app.toast.set("发到了")
  app.toast_n.set(app.toast_n.get() + 1)
  t.frame()
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
