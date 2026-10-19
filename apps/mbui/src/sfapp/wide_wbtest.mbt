// The wide frame (wide.mbt) over the fixture, at a desktop's size; its calls kept as composer_wbtest.mbt keeps them.

///|
/// The app over the fixture in a window `w` wide, its calls kept in `calls` (the fixture answers the rest).
fn wide_tester(calls : Array[Made], mode? : String = "home", w? : Double = 1280.0, h? : Double = 800.0) -> @ui.Tester {
  reset()
  let base = fixture(mode)
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done })
      (base.call)(name, params, done)
    },
  }
  if mode == "chat" {
    open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w~, h~, platform=0)
  t.settle() |> ignore
  t
}

///|
test "wide: the rail, the chats' list beside it and a page in the rest; below the breakpoint the phone's Home" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  assert_true(wide_on.val)
  // the list's band and its days
  assert_true(t.find("新建对话") is Some(_))
  assert_true(t.find("今天") is Some(_))
  let (x, _) = t.find("整理发布清单").unwrap()
  assert_true(x < rail_w + 240.0)
  // nothing open: a new chat beside the list (the fixture keeps no chat last open)
  assert_true(app.nav.top() == NewChat)
  // a phone's width: the phone's Home, the same stack
  t.resize(390.0, 844.0)
  assert_false(wide_on.val)
  assert_true(t.find("新建对话") is None)
}

///|
test "wide: a row pressed opens its chat beside the list, lit; another replaces it" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  t.tap_text("夜里的构建又失败了")
  t.settle() |> ignore
  match app.nav.top() {
    Chat(r) => assert_eq(r.title, "夜里的构建又失败了")
    _ => fail("no chat open")
  }
  // its bar's title in the pane, right of the sidebar
  let found = t.find_last("夜里的构建又失败了").unwrap()
  ignore(found)
  t.tap_text("首页的列表改成按天分组")
  t.settle() |> ignore
  assert_eq(app.nav.depth(), 2)
  match app.nav.top() {
    Chat(r) => assert_eq(r.title, "首页的列表改成按天分组")
    _ => fail("no chat open")
  }
}

///|
test "wide: settings from the rail's gear, its list in the sidebar; back to the chats" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  t.tap(rail_w / 2.0, 800.0 - 28.0)
  t.settle() |> ignore
  assert_true(t.find("返回会话") is Some(_))
  assert_true(t.find("跟随系统") is Some(_))
  t.tap_text("返回会话")
  t.settle() |> ignore
  assert_true(t.find("新建对话") is Some(_))
}

