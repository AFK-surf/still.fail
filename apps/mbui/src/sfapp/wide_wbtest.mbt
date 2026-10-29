// The wide frame (wide.mbt) over the fixture, at a desktop's size; its calls kept as composer_wbtest.mbt keeps them.

///|
/// The app over the fixture in a window `w` wide, its calls kept in `calls` (the fixture answers the rest).
fn wide_tester(
  calls : Array[Made],
  mode? : String = "home",
  w? : Double = 1280.0,
  h? : Double = 800.0,
  platform? : Int = 0,
  window_corner? : Double = 0.0,
  window_inset? : Bool = false,
) -> @ui.Tester {
  reset()
  let base = fixture(mode)
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done, heard: None })
      (base.call)(name, params, done)
    },
  }
  if mode.has_prefix("chat") {
    open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w~, h~, platform~, window_corner~, window_inset~)
  t
}

///|
test "wide: existing chat messages are fully visible in the first frame" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat")
  assert_eq(t.look_of("做完了：").map(fn(l) { l.2 }), Some(1.0))
}

///|
test "wide: the rail, the chats' list beside it and a page in the rest; below the breakpoint the phone's Home" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  assert_true(@sfdesk.is_wide(t.ctx()))
  // the list's band and its days
  assert_true(t.find("新建对话") is Some(_))
  assert_true(t.find("今天") is Some(_))
  let (x, _) = t.find("整理发布清单").unwrap()
  assert_true(x < @sfdesk.rail_w + 240.0)
  // nothing open: a new chat beside the list (the fixture keeps no chat last open)
  assert_true(app.nav.top() == NewChat)
  // a phone's width: the phone's Home, the same stack
  t.resize(390.0, 844.0)
  assert_false(@sfdesk.is_wide(t.ctx()))
  assert_true(t.find("新建对话") is None)
}

///|
/// The `client.focus` the app told of its attention, those that say a new chat is on top (`newChat`).
fn new_chat_told(calls : Array[Made]) -> Array[String] {
  named(calls, "client.focus").filter_map(fn(m) {
    match field(Some(m.params), "newChat") {
      Some(String(w)) => Some(w)
      _ => None
    }
  })
}

///|
test "wide: a new chat on top is told the core as what its workspace goes back to (the app opened again lands there), a chat opened over it not" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  assert_true(app.nav.top() == NewChat)
  assert_eq(new_chat_told(calls).last(), Some("ws1"))
  let before = new_chat_told(calls).length()
  t.tap_text("夜里的构建又失败了")
  assert_true(app.nav.top() is Chat(_))
  assert_eq(new_chat_told(calls).length(), before)
  // the chat's own, as it shows (chat_list.mbt tell_focus): what the workspace goes back to now
  assert_true(named(calls, "client.focus").last().map(fn(m) { field(Some(m.params), "newChat") is None }) == Some(true))
  t.tap_text("新建对话")
  t.draw()
  assert_true(app.nav.top() == NewChat)
  assert_eq(new_chat_told(calls).length(), before + 1)
  assert_eq(new_chat_told(calls).last(), Some("ws1"))
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
test "wide: a row's menu keeps its chat out of the archive (保留, chat.keep) and lets it go (取消保留); pinned, none: a pin keeps it already" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="home-pins")
  let menu = fn(title : String) {
    let (x, y) = t.find(title).unwrap()
    t.right_click(x, y)
  }
  menu("夜里的构建又失败了")
  assert_true(t.query(MenuItem, label="固定") is Some(_))
  t.click(MenuItem, label="保留")
  let kept = named(calls, "chat.keep")
  assert_eq(kept.length(), 1)
  assert_true(flag(Some(kept[0].params), "kept"))
  t.key(@ui.key_escape)
  menu("盯着 CI，绿了告诉我")
  t.click(MenuItem, label="取消保留")
  assert_true(!flag(Some(named(calls, "chat.keep")[1].params), "kept"))
  t.key(@ui.key_escape)
  menu("给设置页加一个深色模式开关")
  assert_true(t.query(MenuItem, label="取消固定") is Some(_))
  assert_true(t.query(MenuItem, label="保留") is None)
  assert_true(t.query(MenuItem, label="取消保留") is None)
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
test "wide: ⌘K over a chat lists what can be done only as the core finds it for the words (commands.find), Enter runs the first" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat")
  t.key(@ui.key_of_char('k'), mods=@ui.mod_cmd)
  // words that name no command: only the chats
  t.type_text("发布")
  t.frame()
  assert_true(named(calls, "commands.find").length() > 0)
  assert_true(t.find("⌘,") is None)
  // 设置: the core's 设置 first, with its keys, then the chats it names
  t.clear()
  t.type_text("设置")
  t.frame()
  assert_true(t.find("⌘,") is Some(_))
  assert_true(t.find("给设置页加一个深色模式开关") is Some(_))
  t.enter()
  assert_true(t.find("搜索全部内容和操作") is None)
  assert_true(t.find("返回会话") is Some(_))
}

///|
test "wide: ⌘K over a chat offers what its keys and bar do (归档, 执行历史, 发送文件, 接力), and runs it" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat")
  t.key(@ui.key_of_char('k'), mods=@ui.mod_cmd)
  for words in ["执行历史", "发送文件", "接力到频道"] {
    t.clear()
    t.type_text(words)
    t.frame()
    assert_true(t.find(words) is Some(_), msg=words + ": " + t.words().map(fn(w) { w.0 }).join("|"))
  }
  t.clear()
  t.type_text("归档对话")
  t.frame()
  t.enter()
  t.frame()
  assert_true(t.find("搜索全部内容和操作") is None)
  assert_true(
    named(calls, "chat.archive").length() == 1 || t.find("仍在运行") is Some(_),
    msg="into the archive, or asked first: " + t.words().map(fn(w) { w.0 }).join("|"),
  )
}

///|
test "wide: ⌘K finds 检查更新 by its name or \"check update\", where the app asks for its builds; picked, the update dialog" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  update.source = Some({ check: fn(_, _, _) {  }, url: fn(f) { f } })
  t.key(@ui.key_of_char('k'), mods=@ui.mod_cmd)
  t.type_text("check update")
  t.frame()
  assert_true(t.find("检查更新") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
  t.clear()
  t.type_text("检查更新")
  t.frame()
  t.enter()
  t.frame()
  assert_true(t.find("搜索全部内容和操作") is None)
  assert_true(update_dialog_open())
  update.source = None
}

///|
test "wide: the 奏 page shows the decision the core shows: a row pressed (decision.show), ⌥↓ and ⌥↑ through its list" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="decisions")
  open_decisions()
  t.run_for(@ui.nav_push_ms)
  // nothing picked yet: the first (its post on the page, as its chat draws it; its options under it)
  assert_true(t.find("量过一次就记住") is Some(_))
  assert_true(t.find("一起换") is Some(_))
  // ⌥↓: the next one shown (the core keeps which), ⌥↑ back
  t.key(@ui.key_code_down, mods=@ui.mod_alt)
  t.frame()
  assert_eq(named(calls, "decision.show").length(), 1)
  t.run_for(@sfdesk.zou_rise_ms)
  t.frame()
  assert_true(t.find("我不会把它写进仓库") is Some(_))
  t.key(@ui.key_code_down, mods=@ui.mod_alt)
  t.frame()
  assert_eq(named(calls, "decision.show").length(), 1, msg="none past the last")
  t.key(@ui.key_code_up, mods=@ui.mod_alt)
  t.frame()
  t.run_for(@sfdesk.zou_rise_ms)
  t.frame()
  assert_true(t.find("量过一次就记住") is Some(_))
}

///|
test "wide: the 奏 page's decision answered by an option (decision.answer), set aside (待定: decision.defer), let go (不再提醒: decision.dismiss), replied to in words (decision.reply)" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="decisions")
  open_decisions()
  t.run_for(@ui.nav_push_ms)
  t.tap_text("一起换")
  t.frame()
  let answered = named(calls, "decision.answer")
  assert_eq(answered.length(), 1)
  assert_eq(text(Some(answered[0].params), "option"), "一起换")
  t.run_for(@sfdesk.zou_rise_ms)
  t.tap_text("待定")
  t.frame()
  assert_eq(named(calls, "decision.defer").length(), 1)
  t.run_for(@sfdesk.zou_rise_ms)
  t.tap_text("不再提醒")
  t.frame()
  assert_eq(named(calls, "decision.dismiss").length(), 1)
  // a text card's reply in the composer at the foot
  let t2 = wide_tester(calls, mode="decisions-text")
  open_decisions()
  t2.run_for(@ui.nav_push_ms)
  t2.tap_text("sk_test_…")
  t2.type_text("sk_test_123")
  t2.enter()
  t2.frame()
  t2.frame()
  let replied = named(calls, "decision.reply")
  assert_eq(replied.length(), 1)
  assert_eq(text(Some(replied[0].params), "text"), "sk_test_123")
}

///|
test "wide: settings from the rail's gear, its list in the sidebar, its first row's page (the account's) beside it; back to the chats" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  t.key(@ui.key_of_char(','), mods=@ui.mod_cmd)
  assert_true(t.find("返回会话") is Some(_))
  assert_true(app.nav.top() == Setting(@settings.Route::Me))
  assert_true(t.find("已登录的设备") is Some(_))
  t.tap_text("返回会话")
  assert_true(t.find("新建对话") is Some(_))
}

///|
test "wide: settings' sidebar taller than a short window scrolls to its last rows (this device's), which open their pages" {
  let calls : Array[Made] = []
  let h = 430.0
  let t = wide_tester(calls, h~)
  t.key(@ui.key_of_char(','), mods=@ui.mod_cmd)
  t.run_for(@ui.nav_push_ms)
  let below = match t.rect_of("本机缓存") {
    Some((_, y, _, _)) => y
    None => fail("no 本机缓存 row")
  }
  assert_true(below > h, msg="under the window's foot at first: \{below}")
  let (x, _) = t.find("返回会话").unwrap()
  t.wheel(x, h / 2.0, 3000.0)
  t.run_for(@ui.nav_push_ms)
  let (_, y, _, rh) = t.rect_of("本机缓存").unwrap()
  assert_true(y + rh <= h, msg="scrolled into the window: \{y}")
  t.tap_text("本机缓存")
  t.run_for(@ui.nav_push_ms)
  assert_true(app.nav.top() == Setting(@settings.Route::KeptFiles))
}

///|
test "wide: Enter sends the composer's words, ⇧Enter is a new line" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat")
  t.tap_text("发消息")
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
test "wide: words dragged in from another app and let go anywhere on the chat go into its composer at its caret; on the chats' list, nowhere" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat")
  // on a message (the chat's pane, no field there): into the composer, which takes the focus
  let (x, y) = t.find("做完了：").unwrap()
  t.drop_words(x, y, "对话 ID：c1")
  t.frame()
  t.frame()
  assert_true(t.ime().0)
  assert_eq(t.ime().1, "对话 ID：c1")
  // on the chats' list beside the chat: nothing takes them
  let (lx, ly) = t.find("今天").unwrap()
  t.drop_words(lx, ly, "，消息 ID：m9")
  t.frame()
  t.frame()
  assert_eq(t.ime().1, "对话 ID：c1")
  // on another message: after them, at the caret
  let (mx, my) = t.find("推送截图前要先登录 gh").unwrap()
  t.drop_words(mx, my, "，消息 ID：m9")
  t.frame()
  t.frame()
  assert_eq(t.ime().1, "对话 ID：c1，消息 ID：m9")
}

///|
test "wide: where this machine is no station, files from the Finder let go on the chat go into its composer as their paths, a line each, not as files" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat")
  let (x, y) = t.find("做完了：").unwrap()
  t.drop_files(x, y, [("报告.pdf", b"%PDF"), ("截图/", b"")], paths=["/Users/lin/报告.pdf", "/Users/lin/截图"])
  t.frame()
  t.frame()
  assert_true(t.ime().0)
  assert_eq(t.ime().1, "/Users/lin/报告.pdf\n/Users/lin/截图")
  // (nothing went up: they were not taken as files)
  assert_eq(named(calls, "composer.add").length(), 0)
}

///|
test "wide: where this machine is a station, files from the Finder let go on the chat or its field go into its draft by that station and path, not as words" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat")
  @sfbase.machine_here.val = Some("ws1/st1")
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "", station_name: "" }
  let refs = fn() { @sfbase.writings.get(draft_key(r)).map(fn(d) { d.files }).unwrap_or([]) }
  // on a message: each by where it is on this machine's station (named by its path: the chat's default)
  let (x, y) = t.find("做完了：").unwrap()
  t.drop_files(x, y, [("报告.pdf", b"%PDF"), ("截图/", b"")], paths=["/Users/lin/报告.pdf", "/Users/lin/截图"])
  t.frame()
  t.frame()
  assert_eq(refs().length(), 2)
  assert_eq(text(field(refs().get(0), "ref"), "station"), "ws1/st1")
  assert_eq(text(field(refs().get(0), "ref"), "stationName"), "Studio")
  assert_eq(text(field(refs().get(0), "ref"), "path"), "/Users/lin/报告.pdf")
  assert_eq(text(field(refs().get(0), "ref"), "mode"), "path")
  // (where the station reads it from, should it go as a file: its folder, its name there)
  let added = named(calls, "composer.add")
  assert_eq(added.length(), 1)
  let handed = match field(Some(added[0].params), "files") {
    Some(Array([one, ..])) => Some(one)
    _ => None
  }
  assert_eq(text(field(handed, "drive"), "station"), "ws1/st1")
  assert_eq(text(field(handed, "drive"), "root"), "/Users/lin")
  assert_eq(text(field(handed, "drive"), "path"), "报告.pdf")
  assert_true(flag(field(refs().get(1), "ref"), "dir"))
  assert_eq(@sfbase.writings.get(draft_key(r)).map(fn(d) { d.text.get() }), Some(""))
  // on the composer's field itself: the same, its words untouched
  let (fx, fy) = t.find("发消息").unwrap()
  t.drop_files(fx, fy, [("a.txt", b"a")], paths=["/Users/lin/a.txt"])
  t.frame()
  t.frame()
  assert_eq(refs().length(), 3)
  assert_eq(text(field(refs().get(2), "ref"), "path"), "/Users/lin/a.txt")
  assert_eq(@sfbase.writings.get(draft_key(r)).map(fn(d) { d.text.get() }), Some(""))
  // (none was read: they go as the station has them)
  assert_true(named(calls, "composer.add").iter().all(fn(m) { m.bytes is None }))
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
  t.run_for(@sfpages.find_typing_ms * 2.0)
  assert_true(named(calls, "chat.find").length() > 0)
  let (at, total) = @sfpages.find_position()
  assert_true(total >= 2)
  assert_true(t.find("\{at}/\{total}") is Some(_))
  // gone to: its words marked in it
  let first = @sfpages.find_at()
  t.enter()
  // (where the reader goes is the core's: asked once the frame is built, answered the next)
  t.frame()
  t.frame()
  let (next, _) = @sfpages.find_position()
  assert_eq(next, if at == total { 1 } else { at + 1 })
  assert_true(@sfpages.find_at() != first || @sfpages.find_k() > 0 || total == 1)
  assert_eq(@sfpages.find_words_in("ws1/st1\u{1}s-c1"), ["截图"])
  t.key(@ui.key_escape)
  t.frame()
  assert_true(t.find("在对话中查找") is None)
  assert_eq(@sfpages.find_chat(), "")
  assert_true(find_marking.val.is_empty())
  // opened again: empty
  t.key(@ui.key_of_char('f'), mods=@ui.mod_cmd)
  assert_eq(@sfpages.find_query(), "")
}

///|
test "wide: a new chat as the web's: its scene and the composer in the pane's middle, where it runs and on what in the composer's row" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  t.frame()
  assert_true(app.nav.top() == NewChat)
  assert_true(t.find("想让 agent 做什么？") is Some(_))
  assert_true(t.find("做任何事") is Some(_))
  // the composer in the middle of the pane, not at its foot
  let (_, y) = t.find("做任何事").unwrap()
  assert_true(y < 600.0, msg="in the middle")
  // where it runs: its stations in a panel beside it (the presenters')
  let station = t.query(Button, label="Studio")
  assert_true(station is Some(_))
  t.click(Button, label="Studio")
  t.run_for(@kit.presence_in_ms)
  assert_true(t.query(Button, label="MBA") is Some(_))
  t.key(@ui.key_escape)
  t.run_for(@kit.presence_in_ms)
  assert_true(t.query(Button, label="MBA") is None)
}

///|
test "wide: the machine's own sessions offered under the composer as its station answers, the composer staying where it is; pointed at, the offer lit" {
  reset()
  let base = fixture("home")
  let held : Array[(Result[Json, Json]) -> Unit] = []
  // (its station read whole: what it has, its overview, read; what its machine kept asked of it)
  let read_whole = fn(s : Json?) -> Json {
    match s {
      Some(Object(o)) => {
        let m = o.copy()
        m["overview"] = Json::object({})
        Json::object(m)
      }
      Some(v) => v
      None => Json::null()
    }
  }
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      if name == "machineSessions.list" {
        held.push(done)
      } else {
        (base.call)(name, params, done)
      }
    },
    topic: fn(name, params) {
      let t = (base.topic)(name, params)
      match (name, t.value) {
        ("newChat", Some(Object(v))) => {
          let m = v.copy()
          m["station"] = read_whole(v.get("station"))
          { ..t, value: Some(Json::object(m)) }
        }
        _ => t
      }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=1280.0, h=800.0, platform=0)
  t.frame()
  t.frame()
  assert_true(app.nav.top() == NewChat)
  let offer = "继续 Studio 终端中的会话"
  assert_true(t.find(offer) is None)
  let (bx, by, _, bh) = composer_glass(t)
  // the station says what its machine kept, a while after the page asked
  assert_true(held.length() > 0, msg="machineSessions.list asked")
  let session = Json::object({
    "id": Json::string("m1"),
    "runtime": Json::string("claude"),
    "title": Json::string("整理构建脚本"),
    "meta": Json::string("Claude Code · 3 小时前"),
  })
  for done in held {
    done(Ok(Json::object({ "sessions": Json::array([session]) })))
  }
  t.frame()
  let (ox, oy) = match t.find(offer) {
    Some(at) => at
    None => fail("no offer once the station answered")
  }
  // under the composer, which has not moved for it
  assert_at((bx, by), { let (x, y, _, _) = composer_glass(t); (x, y) })
  assert_true(oy > by + bh, msg="the offer at \{oy} under the composer \{(by, bh)}")
  let ground = fn() {
    t.drawn_rects().iter().any(fn(r) { r.4 == @sf.theme().p.hover && r.2 < 400.0 && ox > r.0 && ox < r.0 + r.2 && oy > r.1 && oy < r.1 + r.3 })
  }
  let inks = fn() {
    t.drawn_glyphs().filter(fn(g) { (g.1 - oy).abs() < 12.0 && (g.0 - ox).abs() < 100.0 }).map(fn(g) { g.2 })
  }
  assert_false(ground())
  assert_true(inks().length() > 0 && inks().iter().all(fn(k) { k == @sf.theme().p.muted }), msg="quiet: \{inks()}")
  // pointed at: its ground, its words the text's
  t.move(ox, oy)
  t.draw()
  assert_true(ground(), msg="the hover's ground under the offer")
  assert_true(inks().iter().all(fn(k) { k == @sf.theme().p.text }), msg="lit: \{inks()}")
  // left: quiet again
  t.leave()
  assert_false(ground())
}

///|
/// The fixture's app over its new chat as the core gives it station by station: on Studio, read whole, its frequent
/// combinations and its machine's own session to go on with; on MBA none of them, but what is wrong for now and what it
/// waits for.
fn new_chat_by_station(h? : Double = 800.0) -> @ui.Tester {
  reset()
  let base = fixture("home")
  let session = Json::object({
    "id": Json::string("m1"),
    "runtime": Json::string("claude"),
    "title": Json::string("整理构建脚本"),
    "meta": Json::string("Claude Code · 3 小时前"),
  })
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      match (name, params) {
        ("machineSessions.list", Object(p)) => {
          let kept = if p.get("station") == Some(Json::string("ws1/st1")) { [session] } else { [] }
          done(Ok(Json::object({ "sessions": Json::array(kept) })))
        }
        _ => (base.call)(name, params, done)
      }
    },
    topic: fn(name, params) {
      let t = (base.topic)(name, params)
      match (name, t.value) {
        ("newChat", Some(Object(v))) => {
          let m = v.copy()
          if text(v.get("station"), "id") == "st2" {
            m["frequent"] = Json::array([])
            m["spent"] = Json::string("Opus 5.5 的额度已用完，发出的消息会等它恢复")
            m["problem"] = Json::string("MBA 上还没有选好要用的模型")
          } else {
            match v.get("station") {
              Some(Object(o)) => {
                let st = o.copy()
                st["overview"] = Json::object({})
                m["station"] = Json::object(st)
              }
              _ => ()
            }
          }
          { ..t, value: Some(Json::object(m)) }
        }
        _ => t
      }
    },
  }
  @ui.Tester::new(fn(c) { view(c, src) }, w=1280.0, h~, platform=0)
}

///|
test "wide: a new chat's composer stays where it is as another station is picked, what is under it coming and going" {
  let t = new_chat_by_station()
  t.frame()
  t.frame()
  assert_true(app.nav.top() == NewChat)
  let offer = "继续 Studio 终端中的会话"
  assert_true(t.find(offer) is Some(_), msg="Studio's machine's session offered")
  // (a combination's words in parts, the model, how hard it thinks: found by what it is called)
  assert_true(t.query(Button, label="Opus 5.5 · 高") is Some(_), msg="Studio's frequent combinations")
  let (bx, by, _, _) = composer_glass(t)
  let pick = fn(from : String, to : String) raise {
    t.click(Button, label=from)
    t.run_for(@kit.presence_in_ms)
    t.click(Button, label=to)
    t.run_for(@kit.presence_in_ms)
  }
  // MBA: no combinations nor session of its own; what is wrong for now and what it waits for in their place
  pick("Studio", "MBA")
  assert_true(t.find("MBA 上还没有选好要用的模型") is Some(_))
  assert_true(t.find("Opus 5.5 的额度已用完，发出的消息会等它恢复") is Some(_))
  assert_true(t.query(Button, label="Opus 5.5 · 高") is None)
  assert_true(t.find(offer) is None)
  assert_at((bx, by), { let (x, y, _, _) = composer_glass(t); (x, y) })
  // Studio again: as it was
  pick("MBA", "Studio")
  assert_true(t.find(offer) is Some(_))
  assert_true(t.query(Button, label="Opus 5.5 · 高") is Some(_))
  assert_at((bx, by), { let (x, y, _, _) = composer_glass(t); (x, y) })
}

///|
test "wide: in a window as short as it goes, what is under a new chat's composer stays in the window" {
  let t = new_chat_by_station(h=560.0)
  t.frame()
  t.frame()
  t.frame()
  let (_, oy) = match t.find("继续 Studio 终端中的会话") {
    Some(at) => at
    None => fail("no offer")
  }
  assert_true(oy < 560.0 - 10.0, msg="the offer at \{oy}, under the window's foot")
  let (_, ay) = t.find("想让 agent 做什么？").unwrap()
  assert_true(ay > 0.0, msg="the scene's title at \{ay}, over the window's top")
}

///|
/// The composer's ground as drawn now (the lowest glass in the pane, right of the sidebar): x, y, w, h.
fn composer_glass(t : @ui.Tester) -> (Double, Double, Double, Double) raise {
  let mut best : (Double, Double, Double, Double)? = None
  for g in t.drawn_glass() {
    let (x, y, w, h, _, _) = g
    if x > @sfdesk.rail_w + 240.0 && w > 400.0 {
      match best {
        Some((_, by, _, _)) if by >= y => ()
        _ => best = Some((x, y, w, h))
      }
    }
  }
  match best {
    Some(b) => b
    None => fail("no composer drawn at \{t.time()}")
  }
}

///|
/// How far the composer's ground stands under the lowest line of the chat's messages over it.
fn composer_gap(t : @ui.Tester) -> Double raise {
  let (gx, gy, gw, _) = composer_glass(t)
  let mut last = -1.0e9
  for g in t.drawn_glyphs() {
    if g.0 > gx && g.0 < gx + gw && g.1 < gy - 2.0 && g.1 > last {
      last = g.1
    }
  }
  gy - last
}

///|
test "wide: a line more or less in the composer, the chat's last row goes with its ground as it reshapes, not ahead of it" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat")
  t.frame()
  let (gx, gy, gw, gh) = composer_glass(t)
  t.tap(gx + gw / 2.0, gy + gh / 2.0)
  t.type_text("一一")
  t.run_for(@sfpages.morph_ms)
  let gap = composer_gap(t)
  // a line more: half way, its ground on its way up and the row with it
  t.key(@ui.key_code_enter, mods=@ui.mod_shift_key)
  t.type_text("二二")
  t.run_for(@sfpages.morph_ms / 4.0)
  assert_true((composer_gap(t) - gap).abs() < 1.0, msg="growing: \{composer_gap(t)} from \{gap}")
  t.run_for(@sfpages.morph_ms)
  assert_true((composer_gap(t) - gap).abs() < 1.0)
  // and the line taken out again
  t.key(@ui.key_code_backspace)
  t.key(@ui.key_code_backspace)
  t.key(@ui.key_code_backspace)
  t.run_for(@sfpages.morph_ms / 4.0)
  assert_true((composer_gap(t) - gap).abs() < 1.0, msg="shrinking: \{composer_gap(t)} from \{gap}")
  t.run_for(@sfpages.morph_ms)
  assert_true((composer_gap(t) - gap).abs() < 1.0)
}

///|
test "wide: a new chat becomes its chat as the web's: its scene up and away, the composer down to the chat's foot, the words up into their bubble" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  t.frame()
  t.tap_text("做任何事")
  let words = "把发布说明写一下"
  t.type_text(words)
  t.draw()
  // its heading
  let heading_h = match t.words().iter().find_first(fn(w) { w.0 == "想让 agent 做什么？" }) {
    Some(w) => w.4
    None => fail("no heading")
  }
  let heading = fn() {
    t.words().iter().find_first(fn(w) { w.0 == "想让 agent 做什么？" && (w.4 - heading_h).abs() < 0.5 }).map(fn(w) { w.2 })
  }
  let title = heading().unwrap()
  let (bx, by, bw, bh) = composer_glass(t)
  t.enter()
  t.draw()
  let sent = t.time()
  // the chat at once, its words where they were typed (in the composer in the middle), the composer where it was
  assert_true(app.nav.top() is Chat(_))
  let typed = seen_once(t, words)
  assert_true(typed.1 > by && typed.1 < by + bh)
  assert_at((bx, by), { let (x, y, _, _) = composer_glass(t); (x, y) })
  // half way: the scene gone up as it fades
  t.run_for(new_leave_ms / 2.0)
  let up = match heading() {
    Some(y) => y
    None => fail("the scene gone at once")
  }
  assert_true(up < title - 8.0, msg="the scene goes up: \{title} → \{up}")
  // the scene gone at 140 ms
  t.run_for(new_leave_ms / 2.0 + 1.0)
  assert_true(heading() is None)
  // half the words' way: the composer on its way down and wider, on their way (flight.mbt)
  t.run_for(sent + flight_desk_ms / 2.0 - t.time())
  let (mx, my, mw, mh) = composer_glass(t)
  // (as tall as the new chat's box was, about: focused, the chat's is a box too, Chat.tsx multiline)
  ignore(mh)
  assert_true(my > by + 20.0 && mx < bx && mw > bw, msg="the composer on its way: \{(mx, my, mw, mh)} from \{(bx, by, bw, bh)}")
  // the composer at the chat's foot as the words land (520 ms), a capsule as wide as the column and its curves
  t.run_for(sent + flight_desk_ms + 1.0 - t.time())
  let (ex, ey, ew, eh) = composer_glass(t)
  assert_true(ey + eh > 800.0 - 30.0, msg="at the foot: \{(ex, ey, ew, eh)}")
  assert_true(ew > bw)
  t.frame()
  assert_at((ex, ey), { let (x, y, _, _) = composer_glass(t); (x, y) })
  // the words in their bubble under the chat's bar, gone across to its right
  t.run_for(sent + flight_carry_ms + 34.0 - t.time())
  assert_true(send_flight.get() is None)
  let landed = seen_once(t, words)
  assert_true(landed.1 < typed.1 - 200.0 && landed.0 > typed.0 + 100.0, msg="landed at \{landed} from \{typed}")
}

///|
/// Where the first of the words written in the composer is drawn: the leftmost glyph in the text's ink in the upper
/// half of its ground (its field's line, over its row of controls).
fn first_words_glyph(t : @ui.Tester) -> (Double, Double) raise {
  let (gx, gy, gw, gh) = composer_glass(t)
  let mut first : (Double, Double)? = None
  for g in t.drawn_glyphs() {
    if g.2 == @sf.theme().p.text && g.0 > gx && g.0 < gx + gw && g.1 > gy && g.1 < gy + gh / 2.0 {
      match first {
        Some((x, _)) if x <= g.0 => ()
        _ => first = Some((g.0, g.1))
      }
    }
  }
  match first {
    Some(at) => at
    None => fail("no words drawn in the composer at \{t.time()}")
  }
}

///|
/// Whether the composer's hint is drawn: glyphs in its ground in the hint's ink.
fn hint_drawn(t : @ui.Tester) -> Bool raise {
  let (gx, gy, gw, gh) = composer_glass(t)
  // (on the field's line, the glass's upper half, as the words typed are: the choices under it are in the same grey)
  t.drawn_glyphs().iter().any(fn(g) { g.0 > gx && g.0 < gx + gw && g.1 > gy && g.1 < gy + gh / 2.0 && g.2 == @sf.theme().p.subtle })
}

///|
test "wide: a new chat's first words stay where they were typed while the chat is made and read, the hint gone under them, then up into their bubble" {
  let held : Map[String, () -> Unit] = {}
  let unread = Ref(true)
  let t = held_core(held, unread, w=1280.0, h=800.0, platform=0)
  t.frame()
  assert_true(app.nav.top() == NewChat)
  t.tap_text("做任何事")
  let words = "把发布说明写一下"
  t.type_text(words)
  t.draw()
  // where they are drawn in the field (in the window: the pane is beside the sidebar, its corner not the window's)
  let in_field = first_words_glyph(t)
  t.enter()
  t.draw()
  // sent, the field emptied under them: they stay where they were, its hint not over them
  assert_at(in_field, first_words_glyph(t))
  let typed = seen_once(t, words)
  assert_false(hint_drawn(t), msg="the hint under the words sent")
  // the chat made, the message sent to it: the page is the chat, its view not read yet
  match held.get("newChat.create") {
    Some(give) => give()
    None => fail("no chat asked for")
  }
  t.draw()
  assert_at(typed, seen_once(t, words))
  match held.get("chat.send") {
    Some(give) => give()
    None => fail("the message not sent")
  }
  t.draw()
  assert_true(app.nav.top() is Chat(_))
  // the new chat's choices leave as what was by the composer does: fading where they are, on its ground as it goes
  choices_in_ground(t)
  t.run_for(new_fade_ms + 1.0)
  let (gx, _, gw, _) = composer_glass(t)
  assert_true(seen_words(t, "Studio").iter().all(fn(p) { p.0 < gx || p.0 > gx + gw }), msg="the choices gone")
  t.run_for(read_late_ms - new_fade_ms - 1.0)
  assert_at(typed, seen_once(t, words))
  assert_false(hint_drawn(t), msg="the hint under the words sent, the composer gone to the chat's foot")
  // read: their row laid out, and they go at once, up with the list, no frame where they are not, nor a jump
  unread.val = false
  t.draw()
  let placed = t.time()
  let landed = up_till(t, words, placed + flight_carry_ms + 34.0, 120.0)
  assert_true(send_flight.get() is None)
  assert_true(landed.1 < typed.1 - 200.0, msg="landed at \{landed} from \{typed}")
  // out of the composer: its hint still away while its field has the cursor, back once it is let go of
  t.run_for(@sf.hint_back_ms)
  assert_false(hint_drawn(t), msg="the hint over the field with the cursor")
  t.ctx().blur()
  t.run_for(@sfpages.let_go_ms + @sfpages.morph_ms + @sf.hint_back_ms)
  assert_true(hint_drawn(t), msg="the hint back once the field is let go of")
}

///|
/// The new chat's choices (its station's name) drawn within the composer's ground.
fn choices_in_ground(t : @ui.Tester) -> Unit raise {
  let (gx, gy, gw, gh) = composer_glass(t)
  let at = seen_words(t, "Studio").filter(fn(p) { p.0 > gx && p.0 < gx + gw })
  assert_true(
    at.length() > 0 && at.iter().all(fn(p) { p.1 >= gy && p.1 <= gy + gh }),
    msg="the choices at \{at}, the composer's ground \{(gx, gy, gw, gh)} at \{t.time()}",
  )
}

///|
test "wide: a chat and a new chat switched by the sidebar: the composer goes between their places, a new chat left leaves by its own way, what comes in is there at once" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat")
  let (_, cy, _, ch) = composer_glass(t)
  // to a new chat: the composer from the chat's foot up to its place in the page, the scene there at once (no page
  // crossfades)
  t.tap_text("新建对话")
  t.draw()
  let went = t.time()
  assert_true(app.nav.top() == NewChat)
  let (_, y0, _, h0) = composer_glass(t)
  assert_true((y0 + h0 - (cy + ch)).abs() < 1.0, msg="from the chat's foot: \{(y0, h0)} \{(cy, ch)}")
  assert_eq(t.look_of("想让 agent 做什么？").map(fn(l) { l.2 }), Some(1.0))
  // what it holds there and did not at the chat's foot (the new chat's choices) carried on its ground all the way
  choices_in_ground(t)
  t.run_for(@sfpages.page_move_ms / 2.0)
  choices_in_ground(t)
  t.run_for(went + @sfpages.page_move_ms + 1.0 - t.time())
  let (_, y1, _, h1) = composer_glass(t)
  assert_true(y1 + h1 < cy - 100.0, msg="in the page's middle: \{(y1, h1)}")
  assert_eq(t.look_of("想让 agent 做什么？").map(fn(l) { l.2 }), Some(1.0))
  // back to the chat by its row: the composer down to its foot, the new chat's scene up out of view as it fades (its
  // own way, as one become its chat leaves), the chat there at once under it
  t.tap_text("整理发布清单")
  t.draw()
  let back = t.time()
  assert_true(app.nav.top() is Chat(_))
  t.run_for(new_leave_ms / 2.0)
  match t.look_of("想让 agent 做什么？") {
    Some((_, _, a)) => assert_true(a > 0.05 && a < 0.95, msg="leaving: \{a}")
    None => fail("the new chat gone at once")
  }
  t.run_for(back + new_leave_ms + 1.0 - t.time())
  assert_true(t.find("想让 agent 做什么？") is None)
  t.run_for(back + @sfpages.page_move_ms + 1.0 - t.time())
  let (_, y2, _, h2) = composer_glass(t)
  assert_true((y2 + h2 - (cy + ch)).abs() < 1.0, msg="at the chat's foot again: \{(y2, h2)}")
}

///|
/// Where words `s` of a paragraph are drawn (their first line's), else the test fails.
fn words_rect(t : @ui.Tester, s : String) -> (Double, Double, Double, Double) raise {
  match t.run_rects(s) {
    [r, ..] => r
    _ => fail("「\{s}」 not drawn at \{t.time()}")
  }
}

///|
test "wide: a right click in a chat as the desktop app's: a link's 在浏览器中打开链接 and 复制链接, words picked 复制" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat")
  // Ana's message, its address a link
  for _ in 0..<12 {
    match t.run_rects("example.com/review/42") {
      [(_, y, _, _), ..] if y > 100.0 && y < 600.0 => break
      _ => t.wheel(900.0, 400.0, -200.0)
    }
  }
  let (x, y, w, h) = words_rect(t, "example.com/review/42")
  t.right_click(x + w / 2.0, y + h / 2.0)
  t.frame()
  assert_true(t.find("在浏览器中打开链接") is Some(_))
  t.tap_text("复制链接")
  t.frame()
  assert_eq(t.clipboard(), "https://example.com/review/42")
  // (its menu, the presenters', gone as it goes)
  t.run_for(@kit.presence_out_ms)
  assert_true(t.find("在浏览器中打开链接") is None)
  // the words before it with nothing picked: its turn shared alone (a message of the chat's list)
  let (px, py, pw, ph) = words_rect(t, "第二屏的插画")
  t.right_click(px + pw / 2.0, py + ph / 2.0)
  t.frame()
  assert_true(t.find("分享这一轮") is Some(_))
  assert_true(@sfdesk.context.share is Some(_) && @sfdesk.context.link == "" && @sfdesk.context.words == "")
  t.key(@ui.key_escape)
  t.run_for(@kit.presence_out_ms)
  // words picked with the pointer: 复制 alone, and what is picked copied
  t.drag(px + 1.0, py + ph / 2.0, px + pw - 1.0, py + ph / 2.0)
  t.frame()
  assert_eq(t.ctx().selected_text(), "第二屏的插画")
  t.right_click(px + pw / 2.0, py + ph / 2.0)
  t.frame()
  // (no link's item: 已复制链接 said a moment ago is the toast's)
  assert_true(!t.words().iter().any(fn(w) { w.0 == "复制链接" }))
  t.tap_text("复制")
  t.frame()
  assert_eq(t.clipboard(), "第二屏的插画")
}

///|
test "wide: words picked in a message are what ⌘C copies while the composer keeps the focus" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat")
  let (fx, fy) = match t.find("发消息") {
    Some(at) => at
    None => fail("no composer")
  }
  t.tap(fx, fy)
  t.type_text("发布前再看一眼")
  t.frame()
  for _ in 0..<12 {
    match t.run_rects("第二屏的插画") {
      [(_, y, _, _), ..] if y > 100.0 && y < 600.0 => break
      _ => t.wheel(900.0, 400.0, -200.0)
    }
  }
  let (px, py, pw, ph) = words_rect(t, "第二屏的插画")
  t.drag(px + 1.0, py + ph / 2.0, px + pw - 1.0, py + ph / 2.0)
  t.frame()
  assert_eq(t.ctx().selected_text(), "第二屏的插画")
  assert_true(t.ctx().field_focused())
  t.key(@ui.key_code_copy, mods=@ui.mod_cmd)
  t.frame()
  assert_eq(t.clipboard(), "第二屏的插画")
  assert_true(t.ctx().field_focused())
}

///|
test "wide: a right click on the composer's words as the desktop app's: 剪切, 复制, 粘贴, 全选 as they can be done" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat")
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "", station_name: "" }
  let (fx, fy) = match t.find("发消息") {
    Some(at) => at
    None => fail("no composer")
  }
  t.tap(fx, fy)
  t.type_text("发布前再看一眼")
  t.frame()
  // (on the field's words, where its caret is: the composer opened to a box as it took the focus)
  let field_at = fn() {
    let (x, y, _, h) = t.ime_rect()
    (x + 1.0, y + h / 2.0)
  }
  let (fx, fy) = field_at()
  t.right_click(fx, fy)
  t.frame()
  // nothing picked: 剪切 and 复制 there, not to be chosen
  assert_true(t.find("剪切") is Some(_) && t.find("全选") is Some(_))
  t.tap_text("全选")
  t.frame()
  t.right_click(fx, fy)
  t.frame()
  t.tap_text("剪切")
  t.frame()
  assert_eq(t.clipboard(), "发布前再看一眼")
  assert_eq(@sfbase.writings.get(draft_key(r)).map(fn(d) { d.text.get() }), Some(""))
  // 粘贴: the clipboard read, its words put in
  t.clipboard_gives("再看一眼签名")
  let (fx, fy) = field_at()
  t.right_click(fx, fy)
  t.frame()
  t.tap_text("粘贴")
  t.frame()
  t.frame()
  assert_eq(@sfbase.writings.get(draft_key(r)).map(fn(d) { d.text.get() }), Some("再看一眼签名"))
  // a picture on the clipboard: put in as a file, as ⌘V puts one
  t.clipboard_gives_png(@pixels.png(2, 2, FixedArray::make(16, b'\xff')))
  let (fx, fy) = field_at()
  t.right_click(fx, fy)
  t.frame()
  t.tap_text("粘贴")
  t.frame()
  t.frame()
  assert_eq(@sfbase.writings.get(draft_key(r)).map(fn(d) { d.files.map(fn(f) { text(Some(f), "name") }) }), Some(["image.png"]))
}

///|
test "wide: a right click on a message's image: 复制图片, the picture on the clipboard as PNG" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat")
  // an image of the chat's in view, at the pane's middle
  let mut at : (Double, Double)? = None
  for _ in 0..<12 {
    match t.drawn_images().iter().find_first(fn(i) { i[0] > 400.0 && i[2] > 100.0 && i[1] > 80.0 && i[1] + i[3] / 2.0 < 700.0 }) {
      Some(i) => {
        at = Some((i[0] + i[2] / 2.0, i[1] + dmin(i[3], 200.0) / 2.0))
        break
      }
      None => t.wheel(900.0, 400.0, -200.0)
    }
  }
  let (x, y) = match at {
    Some(p) => p
    None => fail("no image in view")
  }
  t.right_click(x, y)
  t.frame()
  // (its menu, the presenters': a small panel at the pointer with a mouse, in)
  t.run_for(@kit.presence_in_ms)
  assert_true(@sfpages.offered_image() != "", msg="its picture's source")
  t.add_pixels(@sfpages.offered_image(), 2, 2, FixedArray::make(16, b'\xff'))
  t.tap_text("复制图片")
  t.frame()
  t.frame()
  match t.clipboard_png() {
    Some(png) => assert_true(@pixels.is_png(png))
    None => fail("no picture copied")
  }
}

///|
test "wide: words picked in a message with the pointer: 引用 over them quotes them into the chat's draft" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat")
  let (px, py, pw, ph) = words_rect(t, "高度先按 90 估")
  t.drag(px + 1.0, py + ph / 2.0, px + pw - 1.0, py + ph / 2.0)
  t.frame()
  // the pill 8 over where the pointer let go: its line, its end
  let (qx, qy) = match t.words().filter(fn(w) { w.0 == "引用" && w.2 < py && w.2 > py - 60.0 }) {
    [w, ..] => (w.1, w.2)
    _ => fail("no 引用 over what is picked")
  }
  assert_true((qx - (px + pw)).abs() < 40.0, msg="引用 at \{(qx, qy)}")
  t.tap(qx + 4.0, qy + 4.0)
  t.frame()
  // into the chat's draft as the core keeps it (composer.quote), whose words with them
  let quoted = named(calls, "composer.quote")
  assert_eq(quoted.length(), 1)
  assert_eq(text(Some(quoted[0].params), "key"), "ws1/st1:s-c1")
  assert_eq(text(field(Some(quoted[0].params), "quote"), "text"), "高度先按 90 估")
  assert_eq(text(field(Some(quoted[0].params), "quote"), "author"), "Claude")
  assert_eq(t.ctx().selected_text(), "")
}

///|
test "wide: words picked with the pointer from a message's heading into its list: 引用 over them quotes all of them, a line each" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat")
  for _ in 0..<12 {
    match t.run_rects("做了什么") {
      [(_, y, _, _), ..] if y > 100.0 && y < 500.0 => break
      _ => t.wheel(900.0, 400.0, -200.0)
    }
  }
  let (hx, hy, _, hh) = words_rect(t, "做了什么")
  let (ix, iy, iw, ih) = words_rect(t, "滚动位置记成")
  t.drag(hx + 1.0, hy + hh / 2.0, ix + iw - 1.0, iy + ih / 2.0)
  t.frame()
  let picked = t.ctx().selected_text()
  assert_true(picked.has_prefix("做了什么\n") && picked.has_suffix("滚动位置记成"), msg=picked)
  // the pill over where the pointer let go: the line of the list's item, not the heading where it went down
  let (qx, qy) = match t.words().filter(fn(w) { w.0 == "引用" && w.2 < iy && w.2 > iy - 60.0 }) {
    [w, ..] => (w.1, w.2)
    _ => fail("no 引用 over where the pointer let go")
  }
  assert_true(qy > hy && (qx - (ix + iw)).abs() < 40.0, msg="引用 at \{(qx, qy)}")
  // dragged up the other way, over the heading where it let go, at its start
  t.drag(ix + iw - 1.0, iy + ih / 2.0, hx + 1.0, hy + hh / 2.0)
  t.frame()
  assert_eq(t.ctx().selected_text(), picked)
  let (qx, qy) = match t.words().filter(fn(w) { w.0 == "引用" && w.2 < hy && w.2 > hy - 60.0 }) {
    [w, ..] => (w.1, w.2)
    _ => fail("no 引用 over where the pointer let go")
  }
  assert_true((qx - hx).abs() < 40.0, msg="引用 at \{(qx, qy)}")
  t.tap(qx + 4.0, qy + 4.0)
  t.frame()
  let quoted = named(calls, "composer.quote")
  assert_eq(quoted.length(), 1)
  assert_eq(text(field(Some(quoted[0].params), "quote"), "text"), picked)
  assert_eq(text(field(Some(quoted[0].params), "quote"), "ts"), "ts3")
}

///|
test "wide: settings' pages as the web's: 通知 (提醒方式, each kind), 权限, 归档 (the hint, each station's), a station's archiving" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  t.key(@ui.key_of_char(','), mods=@ui.mod_cmd)
  // the sidebar has them all
  for label in ["通知", "归档", "自动决策", "本机缓存", "关于"] {
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
  let t = wide_tester([], mode="settings")
  t.draw()
  app.nav.push(Setting(@settings.Route::StationArchiving("ws1/st1")))
  t.run_for(@ui.nav_push_ms)
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
  // (the sidebar closing to the rail's bar as the web's: brand.tsx moveSidebar)
  t.run_for(@sfdesk.side_move_ms)
  assert_true(t.find("添加 station") is None && t.find("添加 Profile") is None && t.find("新建对话") is None)
}

///|
test "wide: to 连接 or 用量 the block closes holding the sidebar it had, as wide, never the chats' list; from there a place's own opens" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  app.nav.replace(Place("stations"))
  t.run_for(@sfdesk.side_move_ms)
  assert_true(t.find("添加 station") is Some(_))
  let s = @sfdesk.wide.side_w
  t.click(Button, label="用量")
  // halfway closed: the stations' list as it was
  t.run_for(@sfdesk.side_move_ms / 2.0)
  assert_true(t.find("添加 station") is Some(_), msg="the stations' list as it closes")
  assert_true(t.find("新建对话") is None, msg="not the chats' list")
  assert_eq(@sfdesk.wide.side_w, s)
  t.run_for(@sfdesk.side_move_ms)
  assert_true(t.find("添加 station") is None && t.find("新建对话") is None)
  // on to 连接: closed, nothing in it drawn
  t.click(Button, label="连接")
  t.run_for(@sfdesk.side_move_ms / 2.0)
  assert_true(t.find("添加 station") is None && t.find("新建对话") is None)
  t.run_for(@sfdesk.side_move_ms)
  // to Profile: its own list as it opens, from its first frame
  t.click(Button, label="Profile")
  t.frame()
  assert_true(t.find("添加 Profile") is Some(_), msg="the profiles' list as it opens")
  assert_true(t.find("添加 station") is None && t.find("新建对话") is None)
  t.run_for(@sfdesk.side_move_ms)
  assert_true(t.find("添加 Profile") is Some(_))
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
  // a shared folder opens in the pane, in columns (the sidebar's 文档, not the pane's)
  let (dx, dy) = t.locate("文档").filter(fn(p) { p.0 < @sfdesk.rail_w + @sfdesk.wide.side_w })[0]
  t.tap(dx, dy)
  t.run_for(@ui.nav_push_ms)
  match app.nav.top() {
    Drive(at) => assert_eq(at.root, Some(fix_docs))
    _ => fail("no folder open")
  }
  assert_true(t.query(Radio, label="分栏") is Some(_))
  // in columns a folder pressed opens beside its column
  t.tap_text("设计稿")
  assert_true(t.find("配色说明.md") is Some(_), msg="设计稿 beside")
  // (the columns open to the folder shown: the page's, as the web's address is)
  match app.nav.top() {
    Drive(at) => assert_eq(at.path, "设计稿")
    _ => fail("no folder open")
  }
  // a list (of 设计稿): a click chooses, a double click goes in
  t.click(Radio, label="列表")
  assert_eq(text(fix_browse.prefs.get("driveViews").map(fn(m) { Json::object(m) }), "page"), "list")
  assert_true(named(calls, "prefs.set").length() > 0)
  t.tap_text("旧版")
  match app.nav.top() {
    Drive(at) => assert_eq(at.path, "设计稿")
    _ => fail("left the folder")
  }
  t.tap_text("旧版")
  match app.nav.top() {
    Drive(at) => assert_eq(at.path, "设计稿/旧版")
    _ => fail("no folder open")
  }
  // 收藏: in the sidebar's 个人收藏 then
  let before = named(calls, "prefs.set").length()
  t.click(Button, label="把「旧版」加入个人收藏")
  assert_eq(named(calls, "prefs.set").length(), before + 1)
  assert_true(t.query(Button, label="从个人收藏移除「旧版」") is Some(_))
}

///|
test "wide: 文件's tabs as Finder's: ⌘T a new one, the bar's split shows two folders side by side, a press in the other side puts it in front; kept (files.tabs)" {
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
  let opened = named(calls, "files.tabs").filter(fn(m) { text(Some(m.params), "act") == "open" })
  assert_eq(opened.length(), 1, msg="kept by the core")
  // split: the same folder on both sides, the right one in front
  t.click(Button, label="左右分栏")
  t.frame()
  assert_true(t.query(Button, label="取消分栏") is Some(_))
  // in a list (in columns a half's room holds one column: a folder pressed is beside it, in its place), the other
  // side's 会议记录 pressed twice: that side in front, gone into
  t.click(Radio, label="列表")
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
  // the side pressed in front, gone into; the other still 文档
  let shown = t.all(Tab).filter(fn(n) { n.selected == Some(true) })
  assert_eq(shown.map(fn(n) { n.label }), ["Studio › 会议记录 | Studio › 文档"])
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
  @sfdesk.open_settings()
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
test "wide: ⌘⇧G goes to a folder by its path (~ the home: the core's files.go), its station's button to another station's same folder or home" {
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
  // (worked out by the core)
  assert_true(named(calls, "files.go").length() > 0)
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
  fix_browse_prefs_set({ "driveViews": { "page": "list" } }) |> ignore
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
test "wide: a place of the rail pressed with ⌘ held and dragged up a place is kept there (prefs.set rails), ⌘ let go of on the way or not; pressed without it, not moved (Rail.tsx drag)" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  let (rx, ry, rw, rh) = t.query(Button, label="文件").unwrap().rect
  let (x, y) = (rx + rw / 2.0, ry + rh / 2.0)
  t.drag(x, y, x, y - @sfdesk.rail_pitch)
  t.frame()
  assert_false(
    named(calls, "prefs.set").iter().any(fn(m) { field(Some(m.params), "rails") is Some(_) }),
    msg="moved without ⌘",
  )
  t.hold_mods(@ui.mod_cmd)
  t.press_at(x, y)
  t.hold_mods(0)
  for k in 1..=10 {
    t.move(x, y - @sfdesk.rail_pitch * k.to_double() / 10.0)
  }
  t.release(x, y - @sfdesk.rail_pitch)
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
test "wide: 快捷键 changed by pressing new ones (keys.set), and the new keys do it; 检查更新 from the menu bar opens 关于" {
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
  let set = named(calls, "keys.set")
  assert_eq(set.length(), 1)
  assert_eq(field(Some(set[0].params), "action"), Some(Json::string("chat.switch")))
  t.frame()
  assert_true(t.find("⌘J") is Some(_))
  assert_false(@sfdesk.switcher_open())
  t.key(@ui.key_of_char('j'), mods=@ui.mod_cmd)
  t.frame()
  assert_true(@sfdesk.switcher_open(), msg="⌘J opens it now")
  // 检查更新 from the menu bar: the update dialog over the page in view, not 关于 (here, where no newer build is asked
  // for, why it is not)
  t.key(@ui.key_escape)
  t.post(@hostapi.system_channel, "{\"menu\":\"update.check\"}")
  t.frame()
  t.run_for(@kit.dialog_ms)
  assert_true(app.nav.top() == Setting(@settings.Route::Shortcuts))
  assert_true(update_dialog_open())
  assert_true(t.find("检查更新失败") is Some(_))
  assert_true(t.find("开发版不检查更新") is Some(_))
}

///|
test "wide: 文件's preview beside the list (⌘⇧P): the row chosen, its start read, what it is and where; a video or a folder says how to open it; kept (prefs.set driveViews.preview)" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  app.nav.replace(Files)
  app.nav.push(Drive({ station: "ws1/st1", root: Some(fix_docs), path: "" }))
  t.run_for(@ui.nav_push_ms)
  t.click(Radio, label="列表")
  t.frame()
  assert_true(t.find("选中一个文件来预览") is None)
  t.click(Button, label="显示预览")
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
  assert_true(t.query(Button, label="显示预览") is Some(_))
}

///|
/// A folder of the files' page's tree (at Studio's 文档) opened, as its disclosure opens it (the made-up core told).
fn files_tree_open(path : String) -> Unit {
  fix_browse_do(None, "", "drive.browse", {
    "act": "tree",
    "owner": "page",
    "station": "ws1/st1",
    "root": Json::string(fix_docs),
    "path": "",
    "folder": Json::string(path),
    "open": true,
  })
  |> ignore
}

///|
/// The files' page at Studio's 文档 in a list (or as `view` says), its calls kept in `calls`.
fn files_dragging(calls : Array[Made], view? : String = "list") -> @ui.Tester {
  let t = wide_tester(calls)
  app.nav.replace(Files)
  app.nav.push(Drive({ station: "ws1/st1", root: Some(fix_docs), path: "" }))
  fix_browse_prefs_set({ "driveViews": { "page": Json::string(view) } }) |> ignore
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
  // what comes and goes in the rail's key: it goes (as the core says)
  assert_true(t.query(Button, label="1 个传输 · 37%") is Some(_), msg="the rail's transfers' key")
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
    files_tree_open(open)
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
  let (ex, ey, ew, eh) = t.query(Separator, label="调整栏宽").unwrap().rect
  let (x, y) = (ex + ew / 2.0, ey + eh / 2.0)
  let (cx, _) = t.find("设计稿").unwrap()
  // that column wider by 60
  t.drag(x, y, x + 60.0, y)
  t.frame()
  let (ex2, _, _, _) = t.query(Separator, label="调整栏宽").unwrap().rect
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
  let (ex3, ey3, ew3, eh3) = t.query(Separator, label="调整栏宽").unwrap().rect
  t.tap(ex3 + ew3 / 2.0, ey3 + eh3 / 2.0)
  t.tap(ex3 + ew3 / 2.0, ey3 + eh3 / 2.0)
  t.frame()
  let (ex4, _, _, _) = t.query(Separator, label="调整栏宽").unwrap().rect
  assert_true(ex4 < ex3, msg="fitted to its names")
  ignore(cx)
}

///|
test "wide: the rail as the web's: the stations their glyph and how they are; the workspaces 6 apart, another's tone at its corner; the ＋ over them its menu" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  // the stations' place says how they are (RailStations' label)
  assert_true(t.query(Button, label="Station：" + @sfdesk.rail_stations_label(fixture("home"), "ws1")) is Some(_))
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
  // 新建 workspace: its dialog (NewWorkspaceDialog), its name typed and made
  let (mx, my) = t.find("新建 workspace").unwrap()
  t.tap(mx, my)
  t.frame()
  assert_true(sheet_host.kind == NoSheet)
  assert_true(t.find("workspace 是一组人和他们共用的 station。你会成为它的 owner。") is Some(_))
  t.frame()
  // (its name's field has the keys as it opens)
  t.type_text("产品团队")
  t.frame()
  let (bx2, by2, bw2, bh2) = t.query(Button, label="新建").unwrap().rect
  t.tap(bx2 + bw2 / 2.0, by2 + bh2 / 2.0)
  t.frame()
  let made = named(calls, "workspace.create")
  assert_eq(made.length(), 1)
  assert_eq(text(Some(made[0].params), "name"), "产品团队")
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

///|
test "wide: the workspace's page as on a phone: its name its title, who you are there; 成员 and those waiting, 添加成员 at the title's end, a person pressed for what can be done; 中继; leaving and deleting in red, asked first" {
  reset()
  let page = @settings.fixture_page("settings-workspace")
  let src = fixture("settings")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=1280.0, h=1000.0, platform=0)
  open_setting(page)
  t.draw()
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("星火工作室") is Some(_))
  assert_true(t.find("你是Owner") is Some(_), msg="who you are")
  assert_true(t.find("成员") is Some(_))
  assert_true(t.query(Button, label="添加成员") is Some(_))
  assert_true(t.find("管理员") is Some(_), msg="a role at its row's end")
  // the relays and the ways behind one row (workspace_page.mbt ws_ways_panel)
  assert_true(t.find("连接方式") is Some(_))
  assert_true(t.find("添加中继") is None)
  // a person pressed: what can be done about them, beside them
  assert_false(@sf.presenting())
  t.tap_text("ana@example.com")
  t.frame()
  assert_true(@sf.presenting())
  assert_true(t.find("移出 workspace") is Some(_), msg=t.drawn_text())
  t.key(@ui.key_escape)
  t.run_for(@ui.nav_push_ms)
  t.tap_text("退出此 workspace")
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("退出「星火工作室」？") is Some(_), msg="asked again")
}

///|
test "wide: 字体's faces a row each under the places' choice, the chosen one checked; picked, kept as the device's; 外观's 拖入 chat 的文件's switch" {
  reset()
  let src = fixture("settings")
  let calls : Array[Made] = []
  let src2 : Source = {
    ..src,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done, heard: None })
      (src.call)(name, params, done)
    },
  }
  // (tall enough for the whole page: 拖入 chat 的文件 at its end in view)
  let t = @ui.Tester::new(fn(c) { view(c, src2) }, w=1280.0, h=1600.0, platform=0)
  open_setting("fonts")
  t.draw()
  t.run_for(@ui.nav_push_ms)
  for label in ["默认", "Inter", "思源黑体"] {
    assert_true(t.query(Button, label~) is Some(_), msg=label)
  }
  t.click(Button, label="思源黑体")
  t.frame()
  let set = named(calls, "prefs.set").filter(fn(m) { text(field(Some(m.params), "fonts"), "ui") == "noto-sans-sc" })
  assert_eq(set.length(), 1)
  // 代码 (the switch's, not the words over it): the code faces
  let (x, y) = t.find_last("代码").unwrap()
  t.tap(x, y)
  t.frame()
  assert_true(t.query(Button, label="JetBrains Mono") is Some(_))
  open_setting("appearance")
  t.draw()
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("拖入 chat 的文件") is Some(_))
  assert_true(t.find("发文件") is Some(_))
}

///|
test "wide: 连接 as the web's: one list of every station's, each its station's tag, who added it and how it is; 全部 under the title, what a connect is beside it" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  app.nav.replace(Place("connects"))
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("星火助手") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
  assert_true(t.find("林（你）") is Some(_), msg="who added it")
  assert_true(t.find("Studio") is Some(_), msg="its station's tag")
  assert_true(t.find("MBA · 离线") is None, msg="no station's heading")
  assert_true(t.query(Button, label="说明") is Some(_), msg="what a connect is")
  assert_true(t.query(Button, label="添加连接") is Some(_))
  // the filter under the title (MineFilter): its menu, 我的 picked
  let (fx, fy, fw, fh) = t.query(Button, label="筛选连接：全部").unwrap().rect
  let (_, hy, _, _) = t.query(Button, label="添加连接").unwrap().rect
  assert_true(fy > hy, msg="under the head")
  t.tap(fx + fw / 2.0, fy + fh / 2.0)
  t.frame()
  assert_true(t.find("全部连接") is Some(_), msg="its menu: " + t.words().map(fn(w) { w.0 }).join("|"))
  let (mx, my) = t.find_last("我的").unwrap()
  t.tap(mx, my)
  t.run_for(@ui.nav_push_ms)
  assert_true(t.query(Button, label="筛选连接：我的") is Some(_), msg="the filter says it")
  // back to 全部; a row pressed: its page
  let (gx, gy, gw, gh) = t.query(Button, label="筛选连接：我的").unwrap().rect
  t.tap(gx + gw / 2.0, gy + gh / 2.0)
  t.frame()
  let (ax, ay) = t.find("全部连接").unwrap()
  t.tap(ax, ay)
  t.run_for(@ui.nav_push_ms)
  assert_true(t.query(Button, label="筛选连接：全部") is Some(_))
  let (rx, ry) = t.find("星火助手").unwrap()
  t.tap(rx, ry)
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("运行方式") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
}

///|
test "wide: a connect's page: back to the connects, who it is and how it is, how it runs, its sessions; its ⋯; its way of making sessions says what switching does before it is done" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  app.nav.replace(Place("connects"))
  t.run_for(@ui.nav_push_ms)
  let (rx, ry) = t.find("星火助手").unwrap()
  t.tap(rx, ry)
  t.run_for(@ui.nav_push_ms)
  // its head: back over it, its name, how it is, where it is reached, its station, who owns it
  assert_true(t.query(Link, label="连接") is Some(_), msg="back: " + t.words().map(fn(w) { w.0 }).join("|"))
  for w in ["星火助手", "在线", "星火", "Studio", "所属"] {
    assert_true(t.find(w) is Some(_), msg=w)
  }
  // how it runs, in the core's words; its latest sessions
  for w in ["运行方式", "每个 thread 一个会话", "在 thread 中 @ 它即开启一个新会话", "最近会话", "Slack 里问的报销流程"] {
    assert_true(t.find(w) is Some(_), msg=w)
  }
  assert_true(t.find("运行于 Claude Code") is Some(_), msg="its runtime its own")
  // its ⋯: what is done to it less often
  t.click(Button, label="更多")
  t.frame()
  for w in ["重新连接", "更换 token", "停用", "更改所属用户", "删除连接"] {
    assert_true(t.find(w) is Some(_), msg="its menu: " + w)
  }
  t.key(@ui.key_escape)
  t.run_for(@ui.nav_push_ms)
  // its way of making sessions, a row: the ways, what switching to all in one does (the core's), its button the core's
  // words
  t.click(Link, label="会话")
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("更改会话方式") is Some(_), msg="its dialog: " + t.words().map(fn(w) { w.0 }).join("|"))
  assert_true(t.find("更改后") is None, msg="nothing said while nothing changes")
  t.click(Radio, label="所有 thread 共用一个会话")
  t.frame()
  assert_true(t.find("更改后") is Some(_), msg="what it does: " + t.words().map(fn(w) { w.0 }).join("|"))
  assert_true(t.find("下一条消息将开始新的单会话") is Some(_))
  assert_true(t.find("仅在被 @ 时唤醒") is Some(_), msg="whether it waits for an @, in the chosen one")
  t.click(Button, label="改为单会话")
  t.run_for(@ui.nav_push_ms)
  let put = named(calls, "connect.put")
  assert_eq(put.length(), 1)
  assert_eq(text(field(Some(put[0].params), "input"), "mode"), "single-session")
  assert_true(t.find("更改会话方式") is None, msg="closed as it goes")
  // back: the connects (the page's back, over its head: the settings' list beside it has 连接 too)
  let links = t.all(Link, label="连接")
  links.sort_by(fn(a, b) { b.rect.0.compare(a.rect.0) })
  let (bx, by, bw, bh) = links[0].rect
  t.tap(bx + bw / 2.0, by + bh / 2.0)
  t.run_for(@ui.nav_push_ms)
  assert_true(t.query(Button, label="添加连接") is Some(_), msg="the list again")
}

///|
test "wide: a Slack connect's app folded on its page, a row opening it: its look and permissions; 应用 writes it with what it started from" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, h=1400.0)
  app.nav.replace(Place("connects"))
  t.run_for(@ui.nav_push_ms)
  let (rx, ry) = t.find("星火助手").unwrap()
  t.tap(rx, ry)
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("名字、头像和权限") is Some(_), msg="its fold: " + t.words().map(fn(w) { w.0 }).join("|"))
  assert_true(t.find("应用到 Slack") is None, msg="folded")
  t.click(Link, label="Slack app")
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("权限 · 已开启 4 / 16") is Some(_), msg="its permissions counted: " + t.words().map(fn(w) { w.0 }).join("|"))
  assert_true(t.find("在 Slack 中打开此 app") is Some(_))
  // its permissions unfolded: by section, the one only admins allow marked
  t.click(Button, label="权限 · 已开启 4 / 16 项")
  t.frame()
  for w in ["文件和文档", "主动发私信", "需管理员"] {
    assert_true(t.find(w) is Some(_), msg=w + ": " + t.words().map(fn(w) { w.0 }).join("|"))
  }
  // all turned on: 应用 writes the draft with what it started from
  let (ax, ay) = t.find("全部打开").unwrap()
  t.tap(ax, ay)
  t.frame()
  t.click(Button, label="应用到 Slack")
  t.frame()
  let put = named(calls, "connect.putSlackApp")
  assert_eq(put.length(), 1)
  let p = Some(put[0].params)
  assert_true(flag(field(field(p, "input"), "groups"), "connect"), msg="its draft")
  assert_true(!flag(field(field(p, "from"), "groups"), "connect"), msg="what it started from")
}

///|
test "wide: a new connect in a dialog as the web's: the core's wizard a step at a time, its title and count, the Slack workspaces to make its app in; 下一步 goes on as the core says" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  app.nav.replace(Place("connects"))
  t.run_for(@ui.nav_push_ms)
  t.click(Button, label="添加连接")
  t.run_for(@ui.nav_push_ms)
  // the wizard opened on the one station online, as the desktop's (not a phone's)
  let opened = named(calls, "connect.flow.open")
  assert_eq(opened.length(), 1)
  assert_eq(text(Some(opened[0].params), "station"), "ws1/st1")
  assert_true(!flag(field(Some(opened[0].params), "input"), "mobile"))
  for w in ["Slack 工作区", "1 / 4", "星火", "实验室", "添加工作区的配置 token"] {
    assert_true(t.find(w) is Some(_), msg=w + ": " + t.words().map(fn(w) { w.0 }).join("|"))
  }
  t.click(Button, label="下一步")
  t.frame()
  let go = named(calls, "connect.flow.go")
  assert_eq(go.length(), 1)
  assert_eq(text(field(Some(go[0].params), "input"), "to"), "app")
  // closed: its wizard let go of
  t.click(Button, label="关闭")
  t.run_for(@ui.nav_push_ms)
  assert_eq(named(calls, "connect.flow.drop").length(), 1)
}

///|
test "wide: 用量 as the web's: what it counts beside its title, who spent it the list shown first, how it is counted at its foot" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  app.nav.replace(Place("usage"))
  // (the chats' sidebar closing to the rail's bar meanwhile, as the web's)
  t.run_for(@sfdesk.side_move_ms)
  assert_true(t.query(Button, label="说明") is Some(_), msg="what it counts")
  assert_true(t.find("整理发布清单") is None, msg="not the chats' list first: " + t.words().map(fn(w) { w.0 }).join("|"))
  let (bx, by) = t.find_last("按对话").unwrap()
  t.tap(bx, by)
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("整理发布清单") is Some(_), msg="the chats' list picked")
}

///|
test "wide: ⌘V with a picture or files on the clipboard puts them in as files (as a page's paste takes them); its words where it has none" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat")
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "", station_name: "" }
  t.tap_text("发消息")
  // (the host's ⌘V with a picture on the clipboard: the app's key, mac_app.m)
  t.clipboard_gives_png(@pixels.png(2, 2, FixedArray::make(16, b'\xff')))
  t.key(@ui.key_of_char('v'), mods=@ui.mod_cmd)
  t.frame()
  t.frame()
  match @sfbase.writings.get(draft_key(r)) {
    Some(d) => {
      assert_eq(d.files.length(), 1)
      assert_eq(text(Some(d.files[0]), "name"), "image.png")
      assert_eq(d.text.get(), "")
    }
    None => fail("no draft")
  }
  // words alone: put in as words
  t.clipboard_gives("再看一眼签名")
  t.key(@ui.key_of_char('v'), mods=@ui.mod_cmd)
  t.frame()
  t.frame()
  assert_eq(@sfbase.writings.get(draft_key(r)).map(fn(d) { d.text.get() }), Some("再看一眼签名"))
  // files copied in Finder (their names beside them as words): the files themselves, by their names, not the words
  t.clipboard_gives_files([("发布清单.pdf", b"%PDF-1.7"), ("截图.jpg", b"\xff\xd8\xff")], text="发布清单.pdf\n截图.jpg")
  t.key(@ui.key_of_char('v'), mods=@ui.mod_cmd)
  t.frame()
  t.frame()
  match @sfbase.writings.get(draft_key(r)) {
    Some(d) => {
      assert_eq(d.files.map(fn(f) { text(Some(f), "name") }), ["image.png", "发布清单.pdf", "截图.jpg"])
      assert_eq(d.text.get(), "再看一眼签名")
    }
    None => fail("no draft")
  }
}

///|
test "wide: an agent's card over its picture beside its message (AgentCard.tsx), laid out as the web's over the window" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat-agent-card")
  let word = fn(s : String) { t.words().filter(fn(w) { w.0 == s && w.5 > 0.5 }) }
  // the last of its messages' names; its picture in the margin before it
  let names = word("Claude")
  let last = match names.iter().fold(init=None, fn(acc : (String, Double, Double, Double, Double, Double)?, w) {
      match acc {
        Some(a) if a.2 >= w.2 => acc
        _ => Some(w)
      }
    }) {
    Some(w) => w
    None => fail("no agent's message")
  }
  assert_eq(word("Claude · Opus 5.5").length(), 0)
  t.move(last.1 - 20.0, last.2 + last.4 / 2.0)
  t.run_for(@sfpages.hover_open_ms * 2.0)
  // its label and its account under it, where it stands, its latest lines, the figures side by side, the quiet line
  let label = word("Claude · Opus 5.5")
  assert_eq(label.length(), 1, msg="its label in its card")
  let lines = word("读了 src/ui/list.mbt")
  // (where it stands alone: no clock while it neither waits nor works, as AgentCard.tsx)
  let status = word("做完了").filter(fn(w) {
    label.length() == 1 && lines.length() == 1 && w.2 > label[0].2 && w.2 < lines[0].2
  })
  let cost = word("$4.20")
  let cache = word("91%")
  let names_of = word("费用估算")
  let account = word("林的 Max")
  let quiet = word("8 轮 · 共干了 1 小时 12 分")
  assert_true(
    status.length() == 1 && lines.length() == 1 && cost.length() == 1 && cache.length() == 1 &&
    account.length() == 1 &&
    quiet.length() == 1 &&
    names_of.length() == 1,
    msg="\{(status, lines, cost, cache, account, quiet, names_of)}",
  )
  // 288 wide, its words 16 in from the panel's edge (its padding, 6, and a row's 10): the quiet line as wide as it
  let left = quiet[0].1
  assert_eq(quiet[0].3, 288.0)
  // the label after its 28 mark, 10 apart; where it stands and its lines 14 in, after the dot
  assert_eq(label[0].1, left + 38.0)
  assert_eq(lines[0].1, left + 14.0)
  assert_true(status[0].1 >= left + 14.0 && status[0].1 < left + 15.0, msg="\{status[0].1 - left}")
  // the figures side by side on one line; each part under the one before
  assert_eq(cost[0].2, cache[0].2)
  assert_true(cache[0].1 > cost[0].1)
  // (its account under its label, what it runs as one thing, before where it stands)
  assert_true(
    label[0].2 < account[0].2 &&
    account[0].2 < status[0].2 &&
    status[0].2 < lines[0].2 &&
    lines[0].2 < cost[0].2 &&
    cost[0].2 < quiet[0].2,
  )
  assert_eq(account[0].1, label[0].1)
  // in the window, by the picture: over it (no room under it), its start where the picture's is
  assert_true(quiet[0].2 + quiet[0].4 < last.2, msg="over the picture")
  assert_true(left - 16.0 >= 0.0 && left + 288.0 + 16.0 <= 1280.0)
  // gone once the pointer has left it
  t.move(900.0, 300.0)
  t.run_for(@sfpages.hover_close_ms * 2.0)
  assert_eq(word("Claude · Opus 5.5").length(), 0)
}

///|
/// The middle of the words `s` in the chat's last message (chat-peeks: a link of each kind).
fn peek_words_at(t : @ui.Tester, s : String) -> (Double, Double) raise {
  let (x, y, w, h) = words_rect(t, s)
  (x + w / 2.0, y + h / 2.0)
}

///|
test "wide: a web link in a message has its page's card while the pointer rests on it, read by the core (LinkHover)" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat-peeks")
  let word = fn(s : String) { t.words().filter(fn(w) { w.0 == s && w.5 > 0.5 }) }
  let (x, y) = peek_words_at(t, "https://example.com/bench/list")
  assert_eq(word("列表滚动的性能数据").length(), 0)
  t.move(x, y)
  t.run_for(@sfpages.hover_open_ms * 2.0)
  // its card: the page's title over its site and where it goes
  assert_eq(word("列表滚动的性能数据").length(), 1, msg="its title")
  assert_eq(word("Example · example.com/bench/list").length(), 1, msg="where it goes")
  // gone once the pointer has left it
  t.move(900.0, 100.0)
  t.run_for(@sfpages.hover_close_ms * 2.0)
  assert_eq(word("列表滚动的性能数据").length(), 0)
}

///|
test "wide: a pull request's link in a message has its card as GitHub says it: its state, where it is, its size and checks (PullRequestCard)" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat-peeks")
  let word = fn(s : String) { t.words().filter(fn(w) { w.0 == s && w.5 > 0.5 }) }
  let (x, y) = peek_words_at(t, "https://github.com/acme/shop/pull/128")
  let said = ["已合并", "acme/shop #128", "3 小时前", "首页列表按天分组", "lin", "+120", "4 个文件", "检查通过 9"]
  // (some said elsewhere too: a message's time)
  let before = said.map(fn(w) { word(w).length() })
  t.move(x, y)
  t.run_for(@sfpages.hover_open_ms * 2.0)
  for k, w in said {
    assert_eq(word(w).length(), before[k] + 1, msg=w)
  }
}

///|
test "wide: a file an agent names by its path is a chip in its words, its card a few of its lines while the pointer rests on it, its path to copy (FileRef)" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat-peeks")
  let word = fn(s : String) { t.words().filter(fn(w) { w.0 == s && w.5 > 0.5 }) }
  // its chip: its path and the line it names, as the core shortened it
  let (x, y) = peek_words_at(t, "src/list/place.mbt:12")
  assert_eq(t.locate("self.anchor = self.anchor + n").length(), 0)
  t.move(x, y)
  t.run_for(@sfpages.hover_open_ms * 2.0)
  // its card: its name and line, its whole path (home as ~), its lines round the one named
  assert_eq(word("place.mbt:12").length(), 1, msg="its name and line")
  assert_true(t.locate("~/shop/src/list/place.mbt").length() >= 1, msg="its whole path")
  assert_true(t.locate("self.anchor = self.anchor + n").length() >= 1, msg="its lines")
  // its path copied from its foot
  t.tap_text("复制路径")
  t.frame()
  assert_eq(t.clipboard(), "/Users/lin/shop/src/list/place.mbt")
}

///|
test "wide: a file an agent names by its path opens itself in the preview as its chip is clicked, read by its path (FileRef open)" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat-peeks")
  let (x, y) = peek_words_at(t, "src/list/place.mbt:12")
  t.tap(x, y)
  t.run_for(fly_open_ms)
  let v = viewer.val.unwrap()
  assert_true(v.named)
  assert_eq(v.file.path, "src/list/place.mbt")
  assert_true(v.bytes.get() is Some(_), msg="read by its path, whole in its first part")
}

///|
test "wide: a reference to a chat in a message has the chat's card while the pointer rests on it, as the list has it (RefPreview)" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat-peeks")
  let word = fn(s : String) { t.words().filter(fn(w) { w.0 == s && w.5 > 0.5 }) }
  let said = "奏 · 分组的标题用相对日期还是具体日期？"
  // (its @ and its title one link: from either, the same card)
  let (x, y) = peek_words_at(t, "@首页的列表改成按天分组")
  assert_eq(word(said).length(), 0)
  t.move(x, y)
  t.run_for(@sfpages.hover_open_ms * 2.0)
  // read by the core as the pointer came onto it, the chat found in the workspace's list: where it stands
  assert_true(calls.filter(fn(m) { m.name == "link.parse" }).length() >= 1)
  assert_eq(word(said).length(), 1, msg="where it stands")
  t.move(900.0, 100.0)
  t.run_for(@sfpages.hover_close_ms * 2.0)
  assert_eq(word(said).length(), 0)
}

///|
test "wide: an agent's card says over each of its allowance's chips what is left of it (QuotaBars' tip)" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat-agent-card")
  let word = fn(s : String) { t.words().filter(fn(w) { w.0 == s && w.5 > 0.5 }) }
  // its card over its picture beside its last message
  let names = word("Claude")
  let last = match names.iter().fold(init=None, fn(acc : (String, Double, Double, Double, Double, Double)?, w) {
      match acc {
        Some(a) if a.2 >= w.2 => acc
        _ => Some(w)
      }
    }) {
    Some(w) => w
    None => fail("no agent's message")
  }
  t.move(last.1 - 20.0, last.2 + last.4 / 2.0)
  t.run_for(@sfpages.hover_open_ms * 2.0)
  assert_eq(word("林的 Max").length(), 1, msg="its card")
  // its weekly window's chip, 18% left: what it says over it once the pointer rests there (which window, what is
  // left, when it refills, as the web's tip), the card staying open
  let chip = word("18%")
  assert_eq(chip.length(), 1, msg="\{chip}")
  let tip = fn() {
    t.words().filter(fn(w) { (w.0.contains("每周剩余 18%") || w.0.contains("2 天 4 小时后刷新")) && w.5 > 0.5 })
  }
  assert_eq(tip().length(), 0)
  t.move(chip[0].1 + chip[0].3 / 2.0, chip[0].2 + chip[0].4 / 2.0)
  t.run_for(@sf.tip_delay_ms * 2.0)
  assert_true(
    tip().iter().any(fn(w) { w.0.contains("每周剩余 18%") }) && tip().iter().any(fn(w) { w.0.contains("2 天 4 小时后刷新") }),
    msg="its tip: \{tip()}",
  )
  assert_eq(word("林的 Max").length(), 1, msg="the card stays")
}

///|
test "wide: the station a chat's agent runs on, beside its mark in the bar, has its card while the pointer rests on it (StationHover)" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat-agent-card")
  let word = fn(s : String) { t.words().filter(fn(w) { w.0 == s && w.5 > 0.5 }) }
  // its part of the tile: in the chat's bar, named for what it is
  let part = t.locate("=Studio").filter(fn(p) { p.1 < 60.0 && p.0 > 400.0 })
  assert_eq(part.length(), 1, msg="\{t.locate("=Studio")}")
  assert_eq(word("机器详情").length(), 0)
  t.move(part[0].0, part[0].1)
  t.run_for(@sfpages.hover_open_ms * 2.0)
  // its card: its name, what it says of itself, where to go on from it
  assert_eq(word("机器详情").length(), 1, msg="its card")
  // gone once the pointer has left it
  t.move(900.0, 400.0)
  t.run_for(@sfpages.hover_close_ms * 2.0)
  assert_eq(word("机器详情").length(), 0)
}

///|
test "wide: a working agent's card has its stop at the end of where it stands, under its label (the corner rule sees it)" {
  reset()
  let base = fixture("chat-agent-card")
  // (its agents at work, as a turn under way has them: chat_fixture.mbt)
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      let got = (base.topic)(name, params)
      match (name, got.value) {
        ("chat", Some(Object(m))) => {
          let o = m.copy()
          o["agents"] = Json::array(
            items(got.value, "agents").map(fn(a) {
              match a {
                Object(am) => {
                  let w = am.copy()
                  w["status"] = Json::string("running")
                  Json::object(w)
                }
                _ => a
              }
            }),
          )
          { ..got, value: Some(Json::object(o)) }
        }
        _ => got
      }
    },
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=1280.0, h=800.0, platform=0)
  let word = fn(s : String) { t.words().filter(fn(w) { w.0 == s && w.5 > 0.5 }) }
  let last = word("Claude").iter().fold(init=None, fn(acc : (String, Double, Double, Double, Double, Double)?, w) {
    match acc {
      Some(a) if a.2 >= w.2 => acc
      _ => Some(w)
    }
  })
  guard last is Some(name) else { fail("no agent's message") }
  t.move(name.1 - 20.0, name.2 + name.4 / 2.0)
  t.run_for(@sfpages.hover_open_ms * 2.0)
  // its stop shown on the line under its label's, not beside it (the label's line its own); nothing in the card's
  // corners (nor anywhere) breaks the rule
  let stop = word("停止当前任务")
  let label = word("Claude · Opus 5.5")
  assert_true(stop.length() == 1 && label.length() == 1, msg="\{(stop, label)}")
  assert_true(stop[0].2 >= label[0].2 + label[0].4, msg="its stop under its label: \{(stop, label)}")
  assert_eq(t.corner_faults(), [])
}

///|
test "wide: an agent's card's latest lines run on as they change (AgentCard.tsx useLinesMotion), the first gone leaving" {
  reset()
  let latest : Ref[(Array[(String, String)], Int)] = Ref(
    ([("k1", "读了 src/ui/list.mbt"), ("k2", "跑了列表的测试"), ("k3", "改了 src/ui/list.mbt")], 1),
  )
  let base = fixture("chat-agent-card")
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      if name == "agentCard" {
        let (lines, v) = latest.val
        {
          value: Some({
            "latest": Json::array(
              lines.map(fn(l) { Json::object({ "key": Json::string(l.0), "text": Json::string(l.1) }) }),
            ),
            "attention": [],
          }),
          error: None,
          version: v,
        }
      } else {
        (base.topic)(name, params)
      }
    },
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=1280.0, h=800.0, platform=0)
  let word = fn(s : String) { t.words().filter(fn(w) { w.0 == s && w.5 > 0.0 }) }
  let last = word("Claude").iter().fold(init=None, fn(acc : (String, Double, Double, Double, Double, Double)?, w) {
    match acc {
      Some(a) if a.2 >= w.2 => acc
      _ => Some(w)
    }
  })
  guard last is Some(name) else { fail("no agent's message") }
  t.move(name.1 - 20.0, name.2 + name.4 / 2.0)
  t.run_for(@sfpages.hover_open_ms * 2.0)
  // where the three are at rest: a line apart
  let near = fn(a : Double, b : Double) { (a - b).abs() < 0.01 }
  let y_of = fn(s : String) { word(s)[0].2 }
  let y1 = y_of("读了 src/ui/list.mbt")
  let y2 = y_of("跑了列表的测试")
  let y3 = y_of("改了 src/ui/list.mbt")
  let pitch = y2 - y1
  assert_true(pitch > 10.0 && near(y3 - y2, pitch), msg="\{(y1, y2, y3)}")
  // one more done: the first goes, the next comes
  latest.val = ([("k2", "跑了列表的测试"), ("k3", "改了 src/ui/list.mbt"), ("k4", "提交了改动")], 2)
  t.frame()
  // as they were: those that stay where they were drawn, the new one faint a line beyond the last, the first's copy
  // where it was, whole
  assert_true(near(y_of("跑了列表的测试"), y2) && near(y_of("改了 src/ui/list.mbt"), y3))
  assert_eq(word("提交了改动").length(), 0)
  let gone = word("读了 src/ui/list.mbt")
  assert_true(gone.length() == 1 && near(gone[0].2, y1) && gone[0].5 > 0.99, msg="\{gone}")
  // half way: on their way up together, the copy with them
  t.run_for(@sfpages.lines_ms / 2.0)
  let mid = y_of("跑了列表的测试")
  assert_true(mid < y2 - 1.0 && mid > y1 + 1.0, msg="\{mid}")
  let (m3, m4, m1) = (y_of("改了 src/ui/list.mbt"), y_of("提交了改动"), y_of("读了 src/ui/list.mbt"))
  assert_true(
    near(m3 - mid, pitch) && near(m4 - mid, pitch * 2.0) && near(m1, mid - pitch),
    msg="\{(mid, m3, m4, m1, pitch)}",
  )
  // there: a line up each, the new one whole, the copy gone
  t.run_for(@sfpages.lines_ms / 2.0)
  assert_true(near(y_of("跑了列表的测试"), y1) && near(y_of("改了 src/ui/list.mbt"), y2))
  let new = word("提交了改动")
  assert_true(near(new[0].2, y3) && new[0].5 > 0.99, msg="\{new}")
  t.frame()
  assert_eq(word("读了 src/ui/list.mbt").length(), 0)
}

///|
/// Whether the row named `name` is chosen (its semantics' selected).
fn files_row_chosen(t : @ui.Tester, name : String) -> Bool {
  match t.query(Button, label=name) {
    Some(n) => n.selected == Some(true)
    None => false
  }
}

///|
test "wide: 文件's rows as the core says them (driveBrowse, drive.browse): a press chooses, the arrows move it, a right click chooses that one and opens its menu; a list's head orders it" {
  let calls : Array[Made] = []
  let t = files_dragging(calls, view="columns")
  // a folder pressed in columns: chosen, open beside
  t.tap_text("会议记录")
  t.frame()
  assert_true(files_row_chosen(t, "会议记录"))
  assert_true(t.find("说明.txt") is Some(_), msg="会议记录 beside")
  // ↓: the next in its column
  t.key(@ui.key_code_down)
  t.frame()
  t.frame()
  assert_true(files_row_chosen(t, "设计稿"), msg="moved down")
  assert_false(files_row_chosen(t, "会议记录"))
  // a right click: that one chosen, its menu at the pointer
  let (x, y) = t.find("发布清单.md").unwrap()
  t.right_click(x, y)
  t.frame()
  t.frame()
  assert_true(t.find("重命名") is Some(_), msg="its menu")
  t.key(@ui.key_escape)
  t.run_for(@kit.presence_out_ms)
  // (the menu gone: the page's rows to be asked of again)
  assert_true(files_row_chosen(t, "发布清单.md"), msg="chosen by its right click")
  assert_false(files_row_chosen(t, "设计稿"))
  // a list: its heads, 大小 pressed orders it by size
  t.click(Radio, label="列表")
  t.frame()
  let before = named(calls, "drive.arrange").length()
  t.tap_text("大小")
  t.frame()
  assert_eq(named(calls, "drive.arrange").length(), before + 1)
  assert_eq(text(Some(named(calls, "drive.arrange")[before].params), "by"), "size")
}

///|
test "wide: 字体's 本机字体 lists the families installed here; one chosen is the place's face, the host's family" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  t.set_local_fonts("[\"Menlo\",\"Avenir Next\",\"Helvetica\"]")
  app.nav.replace(Setting(@settings.Route::Fonts))
  t.run_for(@ui.nav_push_ms)
  // (本机字体 the faces' last row, under the chat they set: the page scrolled to it)
  t.wheel(900.0, 400.0, 400.0)
  t.run_for(@ui.nav_push_ms)
  t.click(Button, label="本机字体")
  t.frame()
  // every one listed, in the host's order (its person's language's: the app sorts nothing of its own)
  let (_, ya) = t.find("Avenir Next").unwrap()
  let (_, yh) = t.find("Helvetica").unwrap()
  let (mx, my) = t.find("Menlo").unwrap()
  assert_true(my < ya && ya < yh, msg="the host's order")
  t.tap(mx, my)
  t.frame()
  let set = named(calls, "prefs.set").filter(fn(m) { field(Some(m.params), "fonts") is Some(_) })
  assert_eq(set.length(), 1)
  assert_eq(field(field(Some(set[0].params), "fonts"), "ui"), Some(Json::string("local:Menlo")))
  t.frame()
  // the app's words in it: the host's family given to their face
  assert_eq(t.family_given(@hostapi.face_ui), "Menlo")
}

///|
test "wide: 密钥's waiting request is its card as in its chat (Vault.tsx Request): 使用「…」, its command, 允许 for the chat, 拒绝, 打开对话" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  app.nav.replace(Setting(@settings.Route::Vault))
  t.run_for(@ui.nav_push_ms)
  for w in ["使用「GitHub token」", "git push origin main", "允许", "拒绝", "本对话内", "打开对话"] {
    assert_true(t.find(w) is Some(_), msg=w)
  }
  // no more numbered rows of grants
  assert_true(t.find("仅本次") is None)
  t.tap_text("允许")
  t.frame()
  let made = named(calls, "vault.approve")
  assert_eq(made.length(), 1)
  assert_eq(field(Some(made[0].params), "request"), Some(Json::string("r1")))
  assert_eq(field(Some(made[0].params), "scope"), Some(Json::string("chat")))
}

///|
test "wide: 文件's tabs as the core keeps them (filesTabs, files.tabs): the address arrives, a new tab, split and one again by ⌘⌥D, a tab closed" {
  let calls : Array[Made] = []
  let t = files_dragging(calls)
  t.frame()
  let acts = fn() { named(calls, "files.tabs").map(fn(m) { text(Some(m.params), "act") }) }
  assert_eq(acts(), ["arrive"])
  // one tab alone has none shown, only the bar's buttons
  assert_eq(t.all(Tab).length(), 0)
  t.click(Button, label="新标签")
  t.frame()
  t.frame()
  assert_eq(acts().filter(fn(a) { a == "open" }).length(), 1)
  assert_eq(t.all(Tab).length(), 2, msg="two tabs")
  assert_eq(t.all(Tab).filter(fn(n) { n.selected == Some(true) }).length(), 1)
  // split: two sides, the bar's button says it undoes it; ⌘⌥D one again
  t.click(Button, label="左右分栏")
  t.frame()
  t.frame()
  assert_true(t.query(Button, label="取消分栏") is Some(_), msg="split")
  t.key(@ui.key_of_char('d'), mods=@ui.mod_cmd + @ui.mod_alt)
  t.frame()
  t.frame()
  assert_true(t.query(Button, label="左右分栏") is Some(_), msg="one again")
  // the tab shown closed: the other left alone, no tabs shown
  let (x, y, w, h) = t.all(Button, label="关闭标签")[0].rect
  t.tap(x + w / 2.0, y + h / 2.0)
  t.frame()
  t.frame()
  assert_eq(acts().filter(fn(a) { a == "close" }).length(), 1)
  assert_eq(t.all(Tab).length(), 0, msg="one tab left")
}

///|
test "wide: 文件's Pin 文件夹 is the web's (Drive.tsx useAddFolder, PickerDialog): which station, then its folders from its home, pinned (drive.setRoots)" {
  let calls : Array[Made] = []
  let t = files_dragging(calls)
  t.tap_text("Pin 文件夹")
  t.frame()
  // (two stations it can be done on: which first)
  assert_true(t.find("选择一台 station，然后选择其中要 pin 的文件夹") is Some(_), msg="which station")
  t.click(Button, label="Studio")
  t.frame()
  t.frame()
  assert_true(t.find("从 station 的主目录开始，进入要 pin 的文件夹后选择它") is Some(_), msg="the picker")
  assert_true(named(calls, "drive.folders").length() > 0, msg="its folders asked")
  t.frame()
  t.click(Button, label="Pin 这个文件夹")
  t.frame()
  let set = named(calls, "drive.setRoots")
  assert_eq(set.length(), 1)
  assert_eq(text(Some(set[0].params), "station"), "ws1/st1")
}

///|
/// `v` with each row of chat `id` given `more` (wherever the view has it).
fn with_row(v : Json, id : String, more : Map[String, Json]) -> Json {
  match v {
    Object(m) => {
      let out : Map[String, Json] = {}
      for k, x in m {
        out[k] = with_row(x, id, more)
      }
      if m.get("id") == Some(Json::string(id)) {
        for k, x in more {
          out[k] = x
        }
      }
      Json::object(out)
    }
    Array(a) => Json::array(a.map(fn(x) { with_row(x, id, more) }))
    x => x
  }
}

///|
test "wide: a row pressed on its state line while the core says which message that is about opens its chat there, flashing it (ChatMark.tsx jumpFromLine); on its title, where it opens" {
  reset()
  let base = fixture("chat")
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      let r = (base.topic)(name, params)
      if name != "chats" {
        return r
      }
      match r.value {
        Some(v) =>
          {
            ..r,
            value: Some(
              with_row(v, "c1", {
                "stateText": "等你回复：发布前要不要再跑一遍",
                "stateAbout": 8,
              }),
            ),
          }
        None => r
      }
    },
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=1280.0, h=800.0, platform=0)
  t.draw()
  let rd = readings.get("ws1/st1\u{1}s-c1").unwrap()
  // its title: the chat as it is
  let (tx, ty) = t.find("整理发布清单").unwrap()
  t.tap(tx, ty)
  t.frame()
  assert_eq(rd.flash, "")
  // its state line: the message the state is about, flashing
  let (lx, ly) = t.find("等你回复：发布前要不要再跑一遍").unwrap()
  t.tap(lx, ly)
  t.frame()
  assert_eq(rd.flash, "ts8")
}

///|
test "wide: Esc goes to what the frame opened first (a row's menu), then to the page's own (the chat's ⌘F bar)" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat")
  t.key(@ui.key_of_char('f'), mods=@ui.mod_cmd)
  t.frame()
  assert_true(@sfpages.find_chat() != "")
  let (x, y) = t.find("夜里的构建又失败了").unwrap()
  t.right_click(x, y)
  assert_true(t.find("复制会话链接") is Some(_))
  // the menu closed, the bar still open
  t.key(@ui.key_escape)
  t.frame()
  assert_true(t.find("复制会话链接") is None)
  assert_true(@sfpages.find_chat() != "")
  // then the bar
  t.key(@ui.key_escape)
  t.frame()
  assert_eq(@sfpages.find_chat(), "")
}

///|
test "wide: 通知's 服务开着很久, the bell's alone: 点亮铃铛 on every system (prefs.set badgeKinds services), no banner of it" {
  let calls : Array[Made] = []
  // (tall enough for the kinds' last row opened)
  let t = wide_tester(calls, h=1400.0)
  app.nav.replace(Setting(@settings.Route::Notifications))
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("服务开着很久") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
  t.click(Button, label="服务开着很久")
  t.draw()
  assert_true(t.find("点亮铃铛") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
  assert_true(t.find("计入红点") is None)
  t.click(Switch, label="点亮铃铛")
  t.frame()
  let set = named(calls, "prefs.set").filter(fn(m) { field(Some(m.params), "badgeKinds") is Some(_) })
  assert_eq(set.length(), 1)
  assert_eq(field(field(Some(set[0].params), "badgeKinds"), "services"), Some(Json::boolean(false)))
}
