// Sharing in (share.mbt) over the fixture (share_fixture.mbt): the sheet, a chat tapped (shareIn.open, the chat opened),
// a new chat on a station chosen.

///|
fn share_tester(mode : String) -> @ui.Tester {
  reset()
  let src = fixture(mode)
  open_drive_fixture(mode)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0)
  t.draw()
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
  assert_true(share_in.shared is None)
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
    text: "",
    put_text: None,
    quotes: [],
    comments: {},
    files: [],
    error: None,
    loaded: true,
    kept: "",
    changed_at: 0.0,
    warmed: 0.0,
    focus: 0,
    id: "",
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
