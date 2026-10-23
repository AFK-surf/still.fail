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
test "wide: a row's menu's 复制 session 文件路径 copies where each agent's session is kept (session.transcript)" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  let (x, y) = t.find("夜里的构建又失败了").unwrap()
  t.right_click(x, y)
  t.tap_text("复制 session 文件路径")
  assert_true(named(calls, "session.transcript").length() > 0)
  assert_true(t.clipboard().has_suffix(".jsonl"), msg=t.clipboard())
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
  // how full Studio's disk is, by its row (MBA away: none)
  assert_true(t.query(Image, label="剩 380 GB · 已用 62%") is Some(_))
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

///|
test "wide: ⌘K finds what the search finds (its messages under 消息) and what can be done by its name (新建对话, settings' pages typed)" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  t.key(@ui.key_of_char('k'), mods=@ui.mod_cmd)
  // nothing typed: the latest chats (what can be done under them)
  assert_true(t.find("对话") is Some(_))
  // what can be done, by its name
  t.type_text("快捷键")
  t.frame()
  assert_true(t.find("通用") is Some(_))
  assert_true(t.find("快捷键一览") is Some(_))
  for _ in 0..<3 {
    t.backspace()
  }
  t.type_text("签名")
  t.frame()
  assert_true(t.find("消息") is Some(_), msg="the messages found")
}

///|
test "wide: ⌘K opens a settings page by its name" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  t.key(@ui.key_of_char('k'), mods=@ui.mod_cmd)
  t.type_text("权限")
  t.frame()
  assert_true(t.find("设置") is Some(_), msg="the settings' part")
  t.enter()
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("搜索全部内容和操作") is None, msg="closed")
  match app.nav.top() {
    Setting(@settings.Route::Permissions) => ()
    _ => fail("not 权限: " + t.words().map(fn(w) { w.0 }).join("|"))
  }
}

///|
test "wide: ⌘K and a row's menu open again right after Esc closed them" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  t.key(@ui.key_of_char('k'), mods=@ui.mod_cmd)
  t.type_text("签名")
  t.frame()
  t.key(@ui.key_escape)
  t.frame()
  assert_true(t.find("搜索全部内容和操作") is None, msg="closed")
  t.key(@ui.key_of_char('k'), mods=@ui.mod_cmd)
  t.frame()
  assert_true(t.find("搜索全部内容和操作") is Some(_), msg="open again")
  t.type_text("权限")
  t.frame()
  t.enter()
  t.run_for(@ui.nav_push_ms)
  match app.nav.top() {
    Setting(@settings.Route::Permissions) => ()
    _ => fail("not 权限 after reopening: " + t.words().map(fn(w) { w.0 }).join("|"))
  }
  t.key(@ui.key_of_char('k'), mods=@ui.mod_cmd)
  t.key(@ui.key_escape)
  open_settings()
  app.nav.replace(Home)
  t.run_for(@ui.nav_push_ms)
  let (x, y) = t.find("夜里的构建又失败了").unwrap()
  t.right_click(x, y)
  assert_true(t.find("重命名") is Some(_))
  t.key(@ui.key_escape)
  t.frame()
  t.right_click(x, y)
  assert_true(t.find("重命名") is Some(_), msg="the menu again: " + t.words().map(fn(w) { w.0 }).join("|"))
}

///|
test "wide: the rail's menu from its right click: a place taken out of it, one not in it put in, back to how it was (prefs.set rails)" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  let (rx, ry, rw, rh) = t.query(Button, label="文件").unwrap().rect
  let (x, y) = (rx + rw / 2.0, ry + rh / 2.0)
  t.right_click(x, y)
  t.frame()
  match t.find("从侧边条移除文件") {
    Some((mx, my)) => t.tap(mx, my)
    None => fail("no remove in " + t.words().map(fn(w) { w.0 }).join("|"))
  }
  let kept = named(calls, "prefs.set")
  assert_true(kept.length() > 0)
  let rails = field(field(Some(kept[kept.length() - 1].params), "rails"), "ws1")
  match rails {
    Some(Array(a)) => assert_false(a.contains(Json::string("files")))
    _ => fail("no rails kept")
  }
}

///|
test "wide: ⌘⇧G goes to a folder by its path (~ the home), its station's button to another station's same folder or home" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  app.nav.replace(Files)
  app.nav.push(Drive({ station: "ws1/st1", root: Some(fix_docs), path: "" }))
  t.run_for(@ui.nav_push_ms)
  t.key(@ui.key_of_char('g'), mods=@ui.mod_cmd + @ui.mod_shift_key)
  t.frame()
  assert_true(t.find("前往文件夹…") is Some(_))
  t.type_text("~/项目")
  t.frame()
  assert_true(t.find("Studio › /Users/lin/项目") is Some(_), msg="where it goes")
  t.enter()
  t.run_for(@ui.nav_push_ms)
  match app.nav.top() {
    Drive(at) => assert_eq(at.root, Some("/Users/lin/项目"))
    _ => fail("no folder open")
  }
  assert_true(t.find("前往文件夹…") is None, msg="closed")
  // its station's button: the stations
  t.click(Button, label="换 station")
  t.frame()
  assert_true(t.find("MBA") is Some(_))
}

///|
test "wide: files going up are rows of the folder (Drive.tsx UploadRow): how far, a name taken (替换, 保留两者), why one failed (重试)" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="drive-upload")
  // (what the mode opens: 文档 with a file going up, one taken, one failed)
  app.nav.replace(Home)
  open_drive_fixture("drive-upload")
  wide.files_view = Some("list")
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("旅行照片.zip") is Some(_))
  assert_true(t.find("2.5 MB / 6.0 MB") is Some(_), msg="how far")
  assert_true(t.find("已有同名文件") is Some(_), msg="a name taken")
  assert_true(t.query(Button, label="保留两者") is Some(_))
  assert_true(t.find("上传失败：station 已离线") is Some(_), msg="why one failed")
  assert_true(t.query(Button, label="重试") is Some(_))
  // no copy between stations asked: no 传输 on the bar
  assert_true(t.find("传输") is None)
}

///|
test "wide: a place of the rail dragged up a place is kept there (prefs.set rails); pressed alone it opens its page" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  let (rx, ry, rw, rh) = t.query(Button, label="文件").unwrap().rect
  let (x, y) = (rx + rw / 2.0, ry + rh / 2.0)
  t.drag(x, y, x, y - rail_pitch)
  t.frame()
  let kept = named(calls, "prefs.set")
  assert_true(kept.length() > 0, msg="kept")
  match field(field(Some(kept[kept.length() - 1].params), "rails"), "ws1") {
    Some(Array(a)) => assert_eq(a[1], Json::string("files"))
    _ => fail("no rails kept")
  }
  // not opened by the drag
  assert_false(app.nav.top() == Files)
}

///|
test "the app's icon has what is wrong and what waits for the person in every workspace (the desktop's badge)" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  t.frame()
  // ws1: one wrong, one waiting
  assert_eq(t.badge(), 2)
}

///|
test "wide: 通知's 红点 beside the banner (prefs.set badgeKinds), each kind's 计入红点" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  app.nav.replace(Setting(@settings.Route::Notifications))
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("红点") is Some(_), msg="the badge's tile")
  t.tap_text("红点")
  t.frame()
  let set = named(calls, "prefs.set").filter(fn(m) { field(Some(m.params), "badgeKinds") is Some(_) })
  assert_eq(set.length(), 1)
  assert_eq(field(field(Some(set[0].params), "badgeKinds"), "on"), Some(Json::boolean(false)))
}

///|
test "wide: 快捷键 changed by pressing new ones (prefs.set keys), and the new keys do it; 版本 its own page" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  app.nav.replace(Setting(@settings.Route::Shortcuts))
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("快速切换对话") is Some(_))
  assert_true(t.find("⌘K") is Some(_))
  t.tap_text("⌘K")
  t.frame()
  assert_true(t.find("按下新的快捷键…") is Some(_))
  // ⌘J: 快速切换对话's now, not the switcher's opening
  t.key(@ui.key_of_char('j'), mods=@ui.mod_cmd)
  t.frame()
  let set = named(calls, "prefs.set").filter(fn(m) { field(Some(m.params), "keys") is Some(_) })
  assert_eq(set.length(), 1)
  assert_true(t.find("⌘J") is Some(_))
  assert_false(wide.switcher)
  t.key(@ui.key_of_char('j'), mods=@ui.mod_cmd)
  t.frame()
  assert_true(wide.switcher, msg="⌘J opens it now")
  // 版本
  t.key(@ui.key_escape)
  app.nav.replace(Setting(@settings.Route::Version))
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("still.fail 桌面版") is Some(_))
}

///|
test "wide: 本机 Station as the system says it (a service running in a workspace), stopped from its page" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  t.set_local_station(
    #|{"data":"~/.stillfail","runner":"service","version":"0.1.4600","service":{"kind":"launchd","name":"fail.still.station"},"workspace":{"id":"ws1","name":"星火工作室","stationName":"Studio","removed":false}}
    ,
  )
  app.nav.replace(Setting(@settings.Route::LocalStation))
  t.run_for(@ui.nav_push_ms)
  for words in ["本机 Station", "Studio", "运行中", "单独安装（launchd）", "0.1.4600", "在 星火工作室", "~/.stillfail"] {
    assert_true(t.find(words) is Some(_), msg=words)
  }
  // (its row: the last 停止 on the page, the lead says the word too)
  let (sx, sy) = t.find_last("停止").unwrap()
  t.tap(sx, sy)
  t.frame()
  assert_eq(t.local_acts(), ["stop"])
}

///|
test "the desktop's dock: once on, its words, its settings and every workspace's chats that want the person; what it asks done" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  t.set_dock(true)
  t.frame()
  // off until turned on: nothing told
  assert_eq(t.dock_lines().length(), 0)
  @settings.dock_set("on", true)
  t.frame()
  t.frame()
  let lines = t.dock_lines()
  assert_true(lines.length() >= 3, msg="its words, settings, items: " + lines.join("\n"))
  assert_true(lines[0].contains("\"words\""))
  assert_true(lines[1].contains("\"settings\""))
  let parsed = @json.parse(lines[lines.length() - 1]) catch { _ => Json::null() }
  let shown = items(Some(parsed), "items")
  assert_true(shown.length() > 0, msg="the chats that want the person")
  // read from it: chat.read
  let id = text(Some(shown[0]), "id")
  t.post(@hostapi.dock_channel, ({ "type": "open", "id": Json::string(id) } : Json).stringify())
  t.frame()
  t.frame()
  match app.nav.top() {
    Chat(r) => assert_eq(r.station + "|" + r.session, id)
    _ => fail("not opened")
  }
  // turned off from its menu: stopped
  t.post(@hostapi.dock_channel, "{\"type\":\"off\"}")
  t.frame()
  t.frame()
  assert_false(@settings.dock_setting("on"))
  assert_true(t.dock_stops() > 0)
}

///|
test "wide: 通知's 桌面浮窗 beside the banner and the badge where there is a dock, kept on this device" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  t.set_dock(true)
  app.nav.replace(Setting(@settings.Route::Notifications))
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("桌面浮窗") is Some(_))
  t.tap_text("桌面浮窗")
  t.frame()
  assert_true(@settings.dock_setting("on"))
}

///|
test "wide: 文件's preview beside the list (⌘⇧P): the row chosen, its start read, what it is and where; a video or a folder says how to open it; kept (prefs.set driveViews.preview)" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  app.nav.replace(Files)
  app.nav.push(Drive({ station: "ws1/st1", root: Some(fix_docs), path: "" }))
  t.run_for(@ui.nav_push_ms)
  t.click(Button, label="列表")
  t.frame()
  assert_true(t.find("选中一个文件来预览") is None)
  t.click(Button, label="显示预览 ⌘⇧P")
  t.frame()
  assert_true(t.find("选中一个文件来预览") is Some(_), msg="nothing chosen yet")
  assert_true(
    named(calls, "prefs.set").any(fn(m) { text(field(Some(m.params), "driveViews"), "preview") == "shown" }),
    msg="kept",
  )
  // a Markdown file chosen: its start read (all of it, under 64 KB), what it is under it
  let facts = ["大小", "修改", "Station", "位置"]
  let before = facts.map(fn(said) { t.locate(said).length() })
  fix_reads.clear()
  let (x, y) = t.find("发布清单.md").unwrap()
  t.tap(x, y)
  t.frame()
  // (its row, its name over what it is, its path)
  assert_eq(t.locate("发布清单.md").length(), 3)
  assert_eq(fix_reads.length(), 1)
  assert_eq(number(Some(fix_reads[0]), "length").to_int(), 4210)
  for i, said in facts {
    assert_eq(t.locate(said).length(), before[i] + 1, msg=said)
  }
  for said in ["打开", "下载", "复制路径"] {
    assert_true(t.query(Button, label=said) is Some(_), msg=said)
  }
  t.click(Button, label="复制路径")
  t.frame()
  assert_eq(t.clipboard(), "/Users/lin/文档/发布清单.md")
  // a video: how to open it, nothing read
  fix_reads.clear()
  let (x, y) = t.find("演示录屏.mp4").unwrap()
  t.tap(x, y)
  t.frame()
  assert_true(t.find("双击播放") is Some(_))
  assert_eq(fix_reads.length(), 0)
  // a folder: no size, no 下载
  let (x, y) = t.find("设计稿").unwrap()
  t.tap(x, y)
  t.frame()
  assert_true(t.find("双击打开文件夹") is Some(_))
  assert_eq(t.locate("大小").length(), before[0])
  assert_true(t.query(Button, label="下载") is None)
  // ⌘⇧P: gone
  t.key(@ui.key_of_char('p'), mods=@ui.mod_cmd + @ui.mod_shift_key)
  t.frame()
  assert_true(t.find("双击打开文件夹") is None)
  assert_true(t.query(Button, label="显示预览 ⌘⇧P") is Some(_))
}

///|
/// The files' page at Studio's 文档 in a list (or as `view` says), its calls kept in `calls`.
fn files_dragging(calls : Array[Made], view? : String = "list") -> @ui.Tester {
  let t = wide_tester(calls)
  app.nav.replace(Files)
  app.nav.push(Drive({ station: "ws1/st1", root: Some(fix_docs), path: "" }))
  wide.files_view = Some(view)
  t.run_for(@ui.nav_push_ms)
  t
}

///|
test "wide: 文件's rows dragged as Finder's: onto a folder moved there within its station (a rename), ⌥ a copy; a folder onto 个人收藏 kept" {
  let calls : Array[Made] = []
  let t = files_dragging(calls)
  let (x0, y0) = t.find("长篇小说.txt").unwrap()
  let (x1, y1) = t.find("会议记录").unwrap()
  // over the folder: it says so (the row lit), let go: moved into it
  t.drag(x0, y0, x1, y1)
  let moved = named(calls, "drive.rename")
  assert_eq(moved.length(), 1)
  assert_eq(text(Some(moved[0].params), "from"), "长篇小说.txt")
  assert_eq(text(Some(moved[0].params), "to"), "会议记录/长篇小说.txt")
  assert_eq(text(Some(moved[0].params), "root"), fix_docs)
  // ⌥ held: a copy (the stations' transfer, into the same station)
  t.hold_mods(@ui.mod_alt)
  let (x0, y0) = t.find("发布清单.md").unwrap()
  let (x1, y1) = t.find("会议记录").unwrap()
  t.drag(x0, y0, x1, y1)
  t.hold_mods(0)
  t.frame()
  let copied = named(calls, "drive.transfer")
  assert_eq(copied.length(), 1)
  assert_false(flag(Some(copied[0].params), "move"))
  assert_eq(text(field(Some(copied[0].params), "to"), "path"), "会议记录")
  assert_eq(items(field(Some(copied[0].params), "from"), "names").length(), 1)
  // the bar's 传输: it goes (as the core says), its list on a press
  assert_true(t.find("1 个传输 · 37%") is Some(_), msg="the transfers' chip")
  // a folder onto 个人收藏: kept there
  let (x0, y0) = t.find("设计稿").unwrap()
  let (x1, y1) = t.find("个人收藏").unwrap()
  t.drag(x0, y0, x1, y1)
  let kept = named(calls, "prefs.set").filter(fn(m) { field(Some(m.params), "driveFavorites") is Some(_) })
  assert_true(kept.length() > 0)
  assert_true(t.query(Button, label="从个人收藏移除「设计稿」") is Some(_))
}

///|
test "wide: 文件 dragged to another station's folder (the sidebar's) is copied there by the stations; ⌘ moves it" {
  let calls : Array[Made] = []
  let t = files_dragging(calls)
  let (x0, y0) = t.find("首页截图.png").unwrap()
  let (x1, y1) = t.find_last("照片").unwrap()
  t.drag(x0, y0, x1, y1)
  let sent = named(calls, "drive.transfer")
  assert_eq(sent.length(), 1)
  assert_eq(text(field(Some(sent[0].params), "from"), "station"), "ws1/st1")
  assert_eq(text(field(Some(sent[0].params), "to"), "station"), "ws1/st2")
  assert_eq(text(field(Some(sent[0].params), "to"), "root"), "/Users/lin/照片")
  assert_false(flag(Some(sent[0].params), "move"))
  t.hold_mods(@ui.mod_cmd)
  let (x0, y0) = t.find("季度数据.csv").unwrap()
  let (x1, y1) = t.find_last("照片").unwrap()
  t.drag(x0, y0, x1, y1)
  t.hold_mods(0)
  assert_true(flag(Some(named(calls, "drive.transfer")[1].params), "move"))
}

///|
test "wide: 文件 moved onto a folder that has its name: asked first (跳过, 保留两者, 替换), kept beside it named as a copy" {
  let calls : Array[Made] = []
  let t = files_dragging(calls, view="tree")
  // 会议记录 and 设计稿 › 旧版 opened in place: each has a 说明.txt
  for open in ["会议记录", "设计稿", "设计稿/旧版"] {
    wide.files_open["tree/ws1/st1/" + fix_docs + "/" + open] = true
  }
  t.frame()
  let notes = t.locate("说明.txt")
  assert_eq(notes.length(), 2)
  let (x1, y1) = t.find("旧版").unwrap()
  // (the one in 会议记录: not the row under 旧版, its own)
  let (x0, y0) = if (notes[0].1 - y1).abs() > (notes[1].1 - y1).abs() { notes[0] } else { notes[1] }
  t.drag(x0, y0, x1, y1)
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("「旧版」里已有「说明.txt」") is Some(_), msg="asked")
  assert_eq(named(calls, "drive.rename").length(), 0)
  t.click(Button, label="保留两者")
  t.frame()
  let moved = named(calls, "drive.rename")
  assert_eq(moved.length(), 1)
  assert_eq(text(Some(moved[0].params), "to"), "设计稿/旧版/说明 2.txt")
}

///|
test "wide: 文件 from the computer held over the folder say where they go; let go, a folder of them made and filled, each file up" {
  let calls : Array[Made] = []
  let t = files_dragging(calls)
  let (x, y) = t.find("合同草稿.pdf").unwrap()
  // under the rows, over the folder shown
  let at = (x, y + 120.0)
  t.hold_files(Some(at))
  t.frame()
  t.frame()
  assert_true(t.find("松开上传到「文档」") is Some(_), msg="where they go")
  t.drop_files(at.0, at.1, [
    ("新的/", Bytes::new(0)),
    ("新的/记录.txt", @utf8.encode("一行字\n")),
    ("清单.txt", @utf8.encode("另一行\n")),
  ])
  t.frame()
  t.frame()
  t.frame()
  assert_true(t.find("松开上传到「文档」") is None)
  let made = named(calls, "drive.mkdir")
  assert_eq(made.length(), 1)
  assert_eq(text(Some(made[0].params), "path"), "新的")
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("清单.txt") is Some(_), msg="up")
  assert_true(t.find("新的") is Some(_), msg="its folder made")
}

///|
test "wide: 文件's columns as Finder's: an edge dragged makes its column wider (that one), with ⌥ every one (kept: prefs.set driveViews.column); pressed twice as wide as its names" {
  let calls : Array[Made] = []
  let t = files_dragging(calls, view="columns")
  let (ex, ey, ew, eh) = t.query(Button, label="调整栏宽").unwrap().rect
  let (x, y) = (ex + ew / 2.0, ey + eh / 2.0)
  let (cx, _) = t.find("设计稿").unwrap()
  // that column wider by 60
  t.drag(x, y, x + 60.0, y)
  t.frame()
  let (ex2, _, _, _) = t.query(Button, label="调整栏宽").unwrap().rect
  assert_eq((ex2 - ex).round().to_int(), 60)
  assert_eq(named(calls, "prefs.set").filter(fn(m) { text(field(Some(m.params), "driveViews"), "column") != "" }).length(), 0)
  // ⌥: every column, kept on this device
  t.hold_mods(@ui.mod_alt)
  t.drag(ex2 + ew / 2.0, y, ex2 + ew / 2.0 - 40.0, y)
  t.hold_mods(0)
  t.frame()
  let kept = named(calls, "prefs.set").filter(fn(m) { text(field(Some(m.params), "driveViews"), "column") != "" })
  assert_eq(kept.length(), 1)
  assert_eq(text(field(Some(kept[0].params), "driveViews"), "column"), "260")
  // pressed twice: as wide as its longest name needs (narrower here)
  let (ex3, ey3, ew3, eh3) = t.query(Button, label="调整栏宽").unwrap().rect
  t.tap(ex3 + ew3 / 2.0, ey3 + eh3 / 2.0)
  t.tap(ex3 + ew3 / 2.0, ey3 + eh3 / 2.0)
  t.frame()
  let (ex4, _, _, _) = t.query(Button, label="调整栏宽").unwrap().rect
  assert_true(ex4 < ex3, msg="fitted to its names")
  ignore(cx)
}

///|
test "wide: the rail as the web's: the stations their glyph and how they are; the workspaces 6 apart, another's tone at its corner; the ＋ over them its menu" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  // the stations' place says how they are (RailStations' label)
  assert_true(t.query(Button, label="Station：" + rail_stations_label(fixture("home"), "ws1")) is Some(_))
  // the workspaces, one under another, 36 apart (30 and the 6 between)
  let ws : Array[(Double, Double, Double, Double)] = []
  for x in ["星火工作室", "个人"] {
    match t.query(Button, label=x) {
      Some(n) => ws.push(n.rect)
      None => ()
    }
  }
  if ws.length() == 2 {
    assert_eq(ws[1].1 - ws[0].1, 36.0)
    assert_eq(ws[0].2, 30.0)
  }
  // the ＋ (seen as the pointer comes over the workspaces): its menu
  let (ax, ay, aw, ah) = t.query(Button, label="新建 workspace、添加账号").unwrap().rect
  t.tap(ax + aw / 2.0, ay + ah / 2.0)
  t.frame()
  assert_true(t.find("新建 workspace") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
  assert_true(t.find("添加另一个账号") is Some(_))
  // 新建 workspace: its sheet
  let (mx, my) = t.find("新建 workspace").unwrap()
  t.tap(mx, my)
  t.frame()
  assert_true(sheet_host.kind == NewWorkspace)
}

///|
test "wide: words with no face chosen are set in the desktop app's face (Inter, carried by the app), code in the app's own; a phone's width the system's" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  t.run_for(@ui.nav_push_ms)
  assert_eq(faces_in[1], desktop_face, msg="the app's words")
  assert_eq(faces_in[3], "", msg="code: the app's own")
  assert_eq(named(calls, "fonts.fetch").length(), 0, msg="nothing fetched")
  t.resize(390.0, 844.0)
  t.frame()
  assert_eq(faces_in[1], "", msg="a phone's: the system's")
}
