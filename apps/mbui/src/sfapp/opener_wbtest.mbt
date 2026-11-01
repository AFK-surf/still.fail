// A chat an agent made (chat_create) and the chat whose agent made it: the way from either to the other, its row's mark
// and menu, the chat's info (…: beside the chat on Medium and Large, its sheet on Small); nothing else of either goes
// by the other.

///|
/// The chat the way back leads to: the one the fixture's chat-opener names (和 Ana 一起看新版的引导页).
fn opener_open(t : @ui.Tester) -> Unit raise {
  ignore(t)
  match app.nav.top() {
    Chat(r) => {
      assert_eq(r.session, "s-c6")
      assert_eq(r.station, "ws1/st1")
      assert_eq(r.title, "和 Ana 一起看新版的引导页")
    }
    _ => fail("no chat open")
  }
}

///|
test "wide: a row another chat's agent made is marked so, that chat named on the mark; its menu's 打开「…」 opens that chat" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat-opener")
  t.draw()
  assert_true(t.query(Image, label="由「和 Ana 一起看新版的引导页」创建") is Some(_))
  let (x, y) = t.find("首页的列表改成按天分组").unwrap()
  t.right_click(x, y)
  assert_true(t.query(MenuItem, label="打开「和 Ana 一起看新版的引导页」") is None)
  t.key(@ui.key_escape)
  let (x, y) = t.find("夜里的构建又失败了").unwrap()
  t.right_click(x, y)
  t.click(MenuItem, label="打开「和 Ana 一起看新版的引导页」")
  opener_open(t)
}

///|
test "wide: a chat another chat's agent made has that chat in its info (…); pressed, that chat opens" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat-opener")
  t.click(Button, label="对话信息")
  t.run_for(@ui.move_most_ms)
  // (its 发起: that chat, not a person)
  t.click(Link, label="由「和 Ana 一起看新版的引导页」创建")
  opener_open(t)
}

///|
test "wide: a chat whose agent made others has how many in its info (…), each where it stands in the menu that opens left of it as it is pointed at; one chosen opens" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat-opened")
  t.click(Button, label="对话信息")
  t.run_for(@ui.move_most_ms)
  // (not each of them in it: one row)
  assert_true(t.query(MenuItem, label="旧版引导页的截图 · 已归档") is None)
  let (x, y, _, _) = t.rect_of("创建了 3 个对话").unwrap()
  let (px, _, _, _) = t.rect_of("发起").unwrap()
  t.move(x + 4.0, y + 4.0)
  t.run_for(@ui.move_most_ms)
  // left of the info's panel, not over it
  let (mx, _, mw, _) = t.rect_of("旧版引导页的截图 · 已归档").unwrap()
  ignore(mx)
  assert_true(mx + mw < px)
  t.click(MenuItem, label="夜里的构建又失败了")
  match app.nav.top() {
    Chat(r) => assert_eq(r.session, "s-c3")
    _ => fail("no chat open")
  }
}

///|
test "a chat another chat's agent made has that chat in its own sheet (…); pressed, that chat opens" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat-opener")
  t.click(Button, label="对话信息")
  t.run_for(@ui.move_most_ms)
  t.click(Link, label="由「和 Ana 一起看新版的引导页」创建")
  t.run_for(@ui.move_most_ms)
  opener_open(t)
}

///|
test "a chat whose agent made others has how many in its own sheet (…), each in the menu it opens; one chosen opens" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat-opened")
  t.click(Button, label="对话信息")
  t.run_for(@ui.move_most_ms)
  t.tap_text("创建了 3 个对话")
  t.run_for(@ui.move_most_ms)
  // (a menu on Small: a sheet from the foot, a button each)
  t.click(Button, label="给设置页加一个深色模式开关")
  t.run_for(@ui.move_most_ms)
  match app.nav.top() {
    Chat(r) => assert_eq(r.session, "s-c4")
    _ => fail("no chat open")
  }
}
