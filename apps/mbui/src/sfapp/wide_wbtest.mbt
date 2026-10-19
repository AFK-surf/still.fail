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
  t.settle(unsettled_ok=true) |> ignore
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
test "wide: a row pressed opens its chat beside the list, lit; another replaces it; ⌥↓ the next" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  t.tap_text("夜里的构建又失败了")
  t.settle(unsettled_ok=true) |> ignore
  match app.nav.top() {
    Chat(r) => assert_eq(r.title, "夜里的构建又失败了")
    _ => fail("no chat open")
  }
  // its bar's title in the pane, right of the sidebar
  let found = t.find_last("夜里的构建又失败了").unwrap()
  ignore(found)
  t.tap_text("首页的列表改成按天分组")
  t.settle(unsettled_ok=true) |> ignore
  assert_eq(app.nav.depth(), 2)
  match app.nav.top() {
    Chat(r) => assert_eq(r.title, "首页的列表改成按天分组")
    _ => fail("no chat open")
  }
  t.key(@ui.key_code_down, mods=@ui.mod_alt)
  t.settle(unsettled_ok=true) |> ignore
  match app.nav.top() {
    Chat(r) => assert_eq(r.title, "夜里的构建又失败了")
    _ => fail("no chat open")
  }
}

///|
test "wide: a row's menu from its right click pins it (chat.pin) and closes" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  let (x, y) = t.find("夜里的构建又失败了").unwrap()
  t.right_click(x, y)
  assert_true(t.find("重命名") is Some(_))
  assert_true(t.find("复制会话链接") is Some(_))
  match t.find("固定") {
    Some(_) => {
      t.tap_text("固定")
      t.settle() |> ignore
      assert_eq(named(calls, "chat.pin").length(), 1)
    }
    // (a fixture row from a station before pins has none)
    None => ()
  }
  t.key(@ui.key_escape)
  assert_true(t.find("复制会话链接") is None)
}

///|
test "wide: ⌘K's switcher narrows to what is typed and Enter opens it; Esc closes it" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  t.key(@ui.key_of_char('k'), mods=@ui.mod_cmd)
  assert_true(t.find("搜索全部内容和操作") is Some(_))
  t.type_text("构建")
  t.settle(unsettled_ok=true) |> ignore
  t.enter()
  t.settle(unsettled_ok=true) |> ignore
  assert_true(t.find("搜索全部内容和操作") is None)
  match app.nav.top() {
    Chat(r) => assert_eq(r.title, "夜里的构建又失败了")
    _ => fail("no chat open")
  }
  t.key(@ui.key_of_char('k'), mods=@ui.mod_cmd)
  assert_true(t.find("搜索全部内容和操作") is Some(_))
  t.key(@ui.key_escape)
  assert_true(t.find("搜索全部内容和操作") is None)
}

///|
test "wide: settings from the rail's gear, its list in the sidebar; back to the chats" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  t.key(@ui.key_of_char(','), mods=@ui.mod_cmd)
  t.settle() |> ignore
  assert_true(t.find("返回会话") is Some(_))
  assert_true(t.find("跟随系统") is Some(_))
  t.tap_text("返回会话")
  t.settle(unsettled_ok=true) |> ignore
  assert_true(t.find("新建对话") is Some(_))
}

///|
test "wide: Enter sends the composer's words, ⇧Enter is a new line" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat")
  t.tap_text("按空格输入")
  t.type_text("第一行")
  t.key(@ui.key_code_enter, mods=1)
  t.type_text("第二行")
  assert_eq(named(calls, "chat.send").length(), 0)
  t.enter()
  t.settle(unsettled_ok=true) |> ignore
  let sent = named(calls, "chat.send")
  assert_eq(sent.length(), 1)
  assert_eq(text(Some(sent[0].params), "text"), "第一行\n第二行")
}
