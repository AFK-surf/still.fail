// The wide frame (wide.mbt) over the fixture, at a desktop's size; its calls kept as composer_wbtest.mbt keeps them.

///|
/// The app over the fixture in a window `w` wide, its calls kept in `calls` (the fixture answers the rest).
fn wide_tester(calls : Array[Made], mode? : String = "home", w? : Double = 1280.0, h? : Double = 800.0) -> @ui.Tester {
  reset()
  let base = fixture(mode)
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done, heard: None })
      (base.call)(name, params, done)
    },
  }
  if mode == "chat" {
    open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w~, h~, platform=0)
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
  match app.nav.top() {
    Chat(r) => assert_eq(r.title, "夜里的构建又失败了")
    _ => fail("no chat open")
  }
  // its bar's title in the pane, right of the sidebar
  let found = t.find_last("夜里的构建又失败了").unwrap()
  ignore(found)
  t.tap_text("首页的列表改成按天分组")
  assert_eq(app.nav.depth(), 2)
  match app.nav.top() {
    Chat(r) => assert_eq(r.title, "首页的列表改成按天分组")
    _ => fail("no chat open")
  }
  t.key(@ui.key_code_down, mods=@ui.mod_alt)
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
  t.enter()
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
  assert_true(t.find("返回会话") is Some(_))
  assert_true(t.find("跟随系统") is Some(_))
  t.tap_text("返回会话")
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
  let sent = named(calls, "chat.send")
  assert_eq(sent.length(), 1)
  assert_eq(text(Some(sent[0].params), "text"), "第一行\n第二行")
}

///|
test "wide: ⌘F's bar in the chat's bar looks in all of it (chat.find), Enter the next, Esc closes it and forgets" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat")
  t.key(@ui.key_of_char('f'), mods=@ui.mod_cmd)
  assert_true(t.find("在对话中查找") is Some(_))
  // the bar in place of the chat's buttons
  assert_true(t.query(Button, label="关闭查找") is Some(_))
  t.type_text("截图")
  t.frame()
  assert_true(named(calls, "chat.find").length() > 0)
  let (at, total) = find_position()
  assert_true(total >= 2)
  assert_true(t.find("\{at}/\{total}") is Some(_))
  // gone to: its words marked in it
  let first = wide.find_at
  t.enter()
  t.frame()
  let (next, _) = find_position()
  assert_eq(next, if at == total { 1 } else { at + 1 })
  assert_true(wide.find_at != first || wide.find_k > 0 || total == 1)
  assert_eq(find_marking.val, ["截图"])
  t.key(@ui.key_escape)
  t.frame()
  assert_true(t.find("在对话中查找") is None)
  assert_eq(wide.find_chat, "")
  assert_true(find_marking.val.is_empty())
  // opened again: empty
  t.key(@ui.key_of_char('f'), mods=@ui.mod_cmd)
  assert_eq(wide.find_query, "")
}

///|
test "wide: a new chat as the web's: its scene and the composer in the pane's middle, where it runs and on what in the composer's row" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  t.frame()
  assert_true(app.nav.top() == NewChat)
  assert_true(t.find("新对话") is Some(_))
  assert_true(t.find("做任何事") is Some(_))
  // the composer in the middle of the pane, not at its foot
  let (_, y) = t.find("做任何事").unwrap()
  assert_true(y < 600.0, msg="in the middle")
  // where it runs: its stations in a menu
  let station = t.query(Button, label="Studio")
  assert_true(station is Some(_))
  t.click(Button, label="Studio")
  t.frame()
  assert_true(wide.station_menu)
  t.key(@ui.key_escape)
  t.frame()
  assert_false(wide.station_menu)
}

///|
test "wide: settings' pages as the web's: 通知 (提醒方式, each kind), 权限, 归档 (the hint, each station's), a station's archiving" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  t.key(@ui.key_of_char(','), mods=@ui.mod_cmd)
  // the sidebar has them all
  for label in ["权限", "更新日志", "关于", "自动决策"] {
    assert_true(t.find(label) is Some(_), msg=label)
  }
  app.nav.push(Setting(@settings.Route::Notifications))
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("提醒方式") is Some(_))
  assert_true(t.find("通知类别") is Some(_))
  assert_true(t.find("待你决定") is Some(_))
  assert_true(t.find("横幅（离开时）") is Some(_), msg="a done turn's banner while away")
  app.nav.push(Setting(@settings.Route::Permissions))
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("已允许") is Some(_))
  app.nav.push(Setting(@settings.Route::Archiving))
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("提示归档") is Some(_))
  assert_true(t.find("自动归档") is Some(_))
  assert_true(t.find("Studio") is Some(_))
  // a station's own (the settings' fixture's Studio: idle a day, Slack's three)
  let t = settings_tester("archiving:ws1/st1")
  assert_true(t.find("怎么自动归档") is Some(_))
  assert_true(t.find("空闲多久") is Some(_))
  assert_true(t.find("只在 Slack 里的对话") is Some(_))
}

///|
test "wide: Station and Profile a list of their own beside their page; 连接 and 用量 across the pane, no sidebar" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  app.nav.replace(Place("stations"))
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("添加 station") is Some(_))
  assert_true(t.find("新建对话") is None, msg="not the chats' list")
  app.nav.replace(Place("profiles"))
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("添加 Profile") is Some(_))
  app.nav.replace(Place("usage"))
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("添加 station") is None && t.find("添加 Profile") is None && t.find("新建对话") is None)
}

///|
test "wide: 文件 as the web's Finder: 个人收藏, each station, 团队共享 in the sidebar; a row chosen by a click, opened by a double click; the bar's ways and 收藏" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  app.nav.replace(Files)
  t.run_for(@ui.nav_push_ms)
  for label in ["个人收藏", "团队共享", "Station"] {
    assert_true(t.find(label) is Some(_), msg=label)
  }
  // a station opened: its places (drive.folders), read once
  t.click(Button, label="展开 Studio")
  t.frame()
  assert_eq(named(calls, "drive.folders").length(), 1)
  assert_true(t.find("外接硬盘") is Some(_))
  t.frame()
  assert_eq(named(calls, "drive.folders").length(), 1)
  // a shared folder opens in the pane, in columns
  t.tap_text("文档")
  t.run_for(@ui.nav_push_ms)
  match app.nav.top() {
    Drive(at) => assert_eq(at.root, Some(fix_docs))
    _ => fail("no folder open")
  }
  assert_true(t.query(Button, label="分栏") is Some(_))
  // in columns a folder pressed opens beside its column
  t.tap_text("设计稿")
  assert_true(t.find("配色说明.md") is Some(_), msg="设计稿 beside")
  // a list: a click chooses, a double click goes in
  t.click(Button, label="列表")
  assert_eq(wide.files_view, Some("list"))
  assert_true(named(calls, "prefs.set").length() > 0)
  t.tap_text("会议记录")
  match app.nav.top() {
    Drive(at) => assert_eq(at.path, "")
    _ => fail("left the folder")
  }
  t.tap_text("会议记录")
  match app.nav.top() {
    Drive(at) => assert_eq(at.path, "会议记录")
    _ => fail("no folder open")
  }
  // 收藏: in the sidebar's 个人收藏 then
  let before = named(calls, "prefs.set").length()
  t.click(Button, label="把「会议记录」加入个人收藏")
  assert_eq(named(calls, "prefs.set").length(), before + 1)
  assert_true(t.query(Button, label="从个人收藏移除「会议记录」") is Some(_))
}

///|
test "wide: 文件's tabs as Finder's: ⌘T a new one, the bar's split shows two folders side by side, a press in the other side puts it in front; kept (prefs.set filesTabs)" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  app.nav.replace(Files)
  app.nav.push(Drive({ station: "ws1/st1", root: Some(fix_docs), path: "" }))
  t.run_for(@ui.nav_push_ms)
  // one tab: none shown
  assert_true(t.query(Button, label="关闭标签") is None)
  t.key(@ui.key_of_char('t'), mods=@ui.mod_cmd)
  t.frame()
  assert_true(t.query(Button, label="关闭标签") is Some(_), msg="two tabs shown")
  let kept = named(calls, "prefs.set").filter(fn(m) { text(Some(m.params), "filesTabs") != "" || field(Some(m.params), "filesTabs") is Some(_) })
  assert_true(kept.length() > 0)
  // split: the same folder on both sides, the right one in front
  t.click(Button, label="左右分栏")
  t.frame()
  assert_true(t.query(Button, label="取消分栏") is Some(_))
  // in a list (in columns a half's room holds one column: a folder pressed is beside it, in its place), the other
  // side's 会议记录 pressed twice: that side in front, gone into
  t.click(Button, label="列表")
  t.frame()
  let rows = t.locate("会议记录")
  assert_eq(rows.length(), 2)
  let (x, y) = rows[0]
  t.tap(x, y)
  t.tap(x, y)
  match app.nav.top() {
    Drive(at) => assert_eq(at.path, "会议记录")
    _ => fail("no folder open")
  }
  // the other side still 文档
  assert_true(t.find("长篇小说.txt") is Some(_))
  // one again: the side in front kept
  t.click(Button, label="取消分栏")
  t.frame()
  assert_true(t.query(Button, label="左右分栏") is Some(_))
  assert_true(t.find("说明.txt") is Some(_))
  assert_true(t.find("长篇小说.txt") is None)
}
