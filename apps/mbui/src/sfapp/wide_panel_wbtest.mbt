// Beside a chat in the wide frame (wide_panel.mbt): its "…" a popover under its button, agent 往来 from it opened in the
// side panel at its right, the panel closed by its switch and opened again at the first agent's history.

///|
test "wide: the chat's \"…\" opens under its button; agent 往来 from it opens beside the chat; the panel closes and opens" {
  reset()
  let src = fixture("chat-letters-info")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.nav_push_ms)
  assert_true(wide_on.val)
  assert_true(t.find("agent 往来") is None)
  // what is done with it, under its "…": agent 往来 among it, saying how many
  t.click(Button, label="对话信息")
  t.frame()
  t.frame()
  assert_true(t.find("agent 往来") is Some(_))
  assert_true(t.find("4 条") is Some(_))
  assert_true(t.find("参与") is Some(_), msg="its facts")
  t.tap_text("agent 往来")
  // (the popover goes as a popover does: gone once its going is over)
  t.run_for(@kit.presence_out_ms)
  // beside the chat, at its right: the chats written with
  let (x, _) = t.find("接手监督 mbui").unwrap()
  assert_true(x > 800.0, msg="at the pane's right")
  assert_true(t.find("BFT 备份尺寸分析") is Some(_))
  assert_true(t.find("参与") is None, msg="the popover gone")
  // its switch closes it; the bar's opens it again, at the first agent's history
  t.click(Button, label="收起侧栏")
  t.frame()
  assert_true(t.find("接手监督 mbui") is None)
  t.click(Button, label="打开侧栏")
  t.frame()
  assert_true(t.find("只看收发") is Some(_), msg="its history's head")
}

///|
test "wide: an agent's history's head as the web's: its control, 只看收发 leaving its steps out, 详情 folding" {
  reset()
  let src = fixture("chat")
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  open_chat(r)
  side_open(r, "history/s-c1")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.nav_push_ms)
  // (where its transcript is: asked once the frame is built, answered at once)
  t.frame()
  t.frame()
  // 详情 open to begin with: what runs it, its station, where its transcript is
  assert_true(t.find("Studio") is Some(_))
  assert_true(t.query(Button, label="复制路径") is Some(_))
  t.click(Button, label="详情")
  t.frame()
  assert_true(t.query(Button, label="复制路径") is None)
  // its own steps there, then left out
  let steps = t.find("读了 src/ui/list.mbt 等 2 个文件，跑了测试")
  t.click(Button, label="只看收发")
  t.frame()
  if steps is Some(_) {
    assert_true(t.find("读了 src/ui/list.mbt 等 2 个文件，跑了测试") is None)
  }
  assert_true(wide.history_io)
}

///|
test "wide: Station 文件 from the chat's \"…\" beside it (kept: prefs.set chatTabs); a row's 添加到消息 into its message" {
  reset()
  let calls : Array[Made] = []
  let base = fixture("chat")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done, heard: None })
      (base.call)(name, params, done)
    },
  }
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.nav_push_ms)
  t.click(Button, label="对话信息")
  t.frame()
  t.frame()
  t.tap_text("Station 文件")
  t.run_for(@kit.presence_out_ms)
  assert_eq(side_front(r), "files")
  let kept = named(calls, "prefs.set").filter(fn(m) { field(Some(m.params), "chatTabs") is Some(_) })
  assert_true(kept.length() > 0)
  let tabs = field(field(field(Some(kept[kept.length() - 1].params), "chatTabs"), "ws1/st1:s-c1"), "tabs")
  assert_eq(tabs, Some(Json::array([Json::string("files")])))
  // its tab, and the station's home in it at the pane's right
  assert_true(t.find("主目录") is Some(_))
  // a file's menu: 添加到消息, into the chat's draft, named by its path
  ftab.places["ws1"] = Some({ station: "ws1/st1", root: Some(fix_docs), path: "" })
  wide.files_cols["tab\u{2}ws1/st1\u{1}" + fix_docs + "\u{1}"] = ""
  t.frame()
  let (x, y) = match t.find("发布清单.md") {
    Some(at) => at
    None => fail("no 发布清单.md in the tab")
  }
  assert_true(x > 800.0)
  t.right_click(x, y)
  t.frame()
  t.tap_text("添加到消息")
  t.frame()
  t.frame()
  let refs = refs_of(draft_key(r))
  assert_eq(refs.length(), 1)
  assert_eq(refs[0].path, fix_docs + "/发布清单.md")
  assert_eq(refs[0].station_name, "Studio")
}

///|
test "wide: a new chat's Station 文件 beside it (NewChat.tsx): kept open, closed and opened by its bar's button; a row's 添加到消息 into its draft" {
  reset()
  let calls : Array[Made] = []
  let base = fixture("newchat-files")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done, heard: None })
      (base.call)(name, params, done)
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.nav_push_ms)
  assert_true(app.nav.top() == NewChat)
  // kept open for the workspace's new chat: its tab, the station's home in it
  assert_true(t.find("主目录") is Some(_))
  t.click(Button, label="收起侧栏")
  t.frame()
  assert_true(t.find("主目录") is None)
  let kept = named(calls, "prefs.set").filter(fn(m) { field(Some(m.params), "chatTabs") is Some(_) })
  assert_true(kept.length() > 0)
  t.click(Button, label="Station 文件")
  t.frame()
  assert_true(t.find("主目录") is Some(_))
  // a file's 添加到消息: into the new chat's draft, named by its path
  ftab.places["ws1"] = Some({ station: "ws1/st1", root: Some(fix_docs), path: "" })
  wide.files_cols["tab\u{2}ws1/st1\u{1}" + fix_docs + "\u{1}"] = ""
  t.frame()
  let (x, y) = match t.find("发布清单.md") {
    Some(at) => at
    None => fail("no 发布清单.md in the tab")
  }
  t.right_click(x, y)
  t.frame()
  t.tap_text("添加到消息")
  t.frame()
  t.frame()
  let refs = refs_of("new:ws1/st1")
  assert_eq(refs.length(), 1)
  assert_eq(refs[0].path, fix_docs + "/发布清单.md")
}
