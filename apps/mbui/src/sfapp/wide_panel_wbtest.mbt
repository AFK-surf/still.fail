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
  // (the popover goes as a popover does: gone once its going is over; the panel slid in)
  t.run_for(dmax(@kit.presence_out_ms, side_in_ms))
  // beside the chat, at its right: the chats written with
  let (x, _) = t.find("接手监督 mbui").unwrap()
  assert_true(x > 800.0, msg="at the pane's right")
  assert_true(t.find("BFT 备份尺寸分析") is Some(_))
  assert_true(t.find("参与") is None, msg="the popover gone")
  // its switch closes it; the bar's opens it again, at the first agent's history
  t.click(Button, label="收起侧栏")
  t.run_for(side_out_ms)
  assert_true(t.find("接手监督 mbui") is None)
  t.click(Button, label="打开侧栏")
  t.run_for(side_in_ms)
  assert_true(t.find("只看收发") is Some(_), msg="its history's head")
}

///|
test "wide: an agent's history's head as the web's: its control, 只看收发 leaving its steps out, 详情 folding" {
  reset()
  let src = fixture("chat")
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.nav_push_ms)
  // the bar's switch: its first agent's history beside it
  t.click(Button, label="打开侧栏")
  t.run_for(side_in_ms)
  assert_eq(side_now(r), (["s-c1"], "s-c1"))
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
test "wide: Station 文件 from the chat's \"…\" beside it (kept by the core: chat.tabs.open); a row's 添加到消息 into its message" {
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
  t.run_for(dmax(@kit.presence_out_ms, side_in_ms))
  let opened = named(calls, "chat.tabs.open")
  assert_eq(opened.length(), 1)
  assert_eq(text(Some(opened[0].params), "chat"), "ws1/st1:s-c1")
  assert_eq(text(Some(opened[0].params), "tab"), "files")
  assert_eq(side_now(r), (["files"], "files"))
  // its tab, and the station's home in it at the pane's right
  assert_true(t.find("主目录") is Some(_))
  // a file's menu: 添加到消息, into the chat's draft, named by its path
  ftab.places["ws1"] = Some({ station: "ws1/st1", root: Some(fix_docs), path: "" })
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
  t.run_for(side_out_ms)
  assert_true(t.find("主目录") is None)
  let closed = named(calls, "chat.tabs.close")
  assert_eq(closed.length(), 1)
  assert_eq(text(Some(closed[0].params), "chat"), "new:ws1")
  t.click(Button, label="Station 文件")
  t.run_for(side_in_ms)
  assert_true(t.find("主目录") is Some(_))
  // a file's 添加到消息: into the new chat's draft, named by its path
  ftab.places["ws1"] = Some({ station: "ws1/st1", root: Some(fix_docs), path: "" })
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

///|
test "wide: the side panel's tabs are the core's (chat.tabs.*): an agent's history before 任务, the last left in front, the panel's switch closes them all" {
  reset()
  let src = fixture("chat")
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.nav_push_ms)
  assert_eq(side_now(r), ([], ""))
  side_change(r, "open", Some("jobs"))
  t.frame()
  side_change(r, "open", Some("s-c1"))
  t.frame()
  // (the history after the histories open, before the other tabs; in front as it is opened)
  assert_eq(side_now(r), (["s-c1", "jobs"], "s-c1"))
  t.run_for(side_in_ms)
  assert_true(t.find("只看收发") is Some(_), msg="its history in front")
  side_change(r, "close", Some("s-c1"))
  t.frame()
  assert_eq(side_now(r), (["jobs"], "jobs"))
  t.click(Button, label="收起侧栏")
  t.frame()
  assert_eq(side_now(r), ([], ""))
  assert_true(t.query(Button, label="打开侧栏") is Some(_))
}

///|
test "wide: the side panel slides in from the pane's right edge over 280 ms and out over 240, the chat narrowing and widening with it (useSidePanel)" {
  reset()
  let src = fixture("chat")
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.nav_push_ms)
  t.click(Button, label="打开侧栏")
  t.frame()
  // on its way in: its head further right than it will rest, as the column it shows through has widened so far
  t.run_for(side_in_ms / 2.0)
  let (mid, _) = t.find("只看收发").unwrap()
  t.run_for(side_in_ms / 2.0)
  let (end, _) = t.find("只看收发").unwrap()
  assert_true(mid > end, msg="in from the right: \{mid} then \{end}")
  // as it rests, no further
  t.run_for(side_in_ms)
  assert_eq(t.find("只看收发").map(fn(at) { at.0 }), Some(end))
  // closed: still there on its way out (what it showed), gone at its end
  t.click(Button, label="收起侧栏")
  t.frame()
  t.run_for(side_out_ms / 2.0)
  let (going, _) = t.find("只看收发").unwrap()
  assert_true(going > end, msg="out to the right: \{going}")
  t.run_for(side_out_ms / 2.0)
  assert_true(t.find("只看收发") is None)
  // opened again: in again, to where it rested
  t.click(Button, label="打开侧栏")
  t.run_for(side_in_ms)
  assert_eq(t.find("只看收发").map(fn(at) { at.0 }), Some(end))
}
