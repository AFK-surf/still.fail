// Beside a chat in the wide frame (wide_panel.mbt): its "…" a popover under its button, agent 往来 from it opened in the
// side panel at its right, the panel closed by its switch and opened again at the first agent's history.

///|
test "wide: the chat's \"…\" opens under its button; agent 往来 from it opens beside the chat; the panel closes and opens" {
  new_run()
  let src = fixture("chat-letters-info")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms)
  assert_true(@sfdesk.is_wide(t.ctx()))
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
  t.run_for(dmax(@kit.presence_out_ms, @ui.move_most_ms))
  // beside the chat, at its right: the chats written with
  let (x, _) = t.find("接手监督 mbui").unwrap()
  assert_true(x > 800.0, msg="at the pane's right")
  assert_true(t.find("BFT 备份尺寸分析") is Some(_))
  assert_true(t.find("参与") is None, msg="the popover gone")
  // its switch closes it; the bar's opens it again, at the first agent's history
  t.click(Button, label="收起侧栏")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("接手监督 mbui") is None)
  t.click(Button, label="打开侧栏")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("只看收发") is Some(_), msg="its history's head")
}

///|
test "wide: an agent's history's head as the web's: its control, 只看收发 leaving its steps out, 详情 folding" {
  new_run()
  let src = fixture("chat")
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms)
  // the bar's switch: its first agent's history beside it
  t.click(Button, label="打开侧栏")
  t.run_for(@ui.move_most_ms)
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
  assert_true(@sfpages.history_only_io())
}

///|
test "wide: a quota running out beside an agent's history's control is whole however narrow its head: the control's parts leave first, its figure never cut" {
  new_run()
  let base = fixture("chat")
  // (its agent's account's weekly window running out, as the core says it beside the control)
  let note : Json = {
    "kind": "quota",
    "text": "每周额度剩 23%",
    "quota": { "left": 23, "mark": "W", "level": "amber" },
  }
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      let got = (base.topic)(name, params)
      match (name, got.value) {
        ("chat", Some(Object(chat)) as v) => {
          let agents = items(v, "agents").map(fn(a) {
            match a {
              Object(o) => {
                let o = o.copy()
                o["attention"] = [note]
                Json::object(o)
              }
              other => other
            }
          })
          let chat = chat.copy()
          chat["agents"] = Json::array(agents)
          { ..got, value: Some(Json::object(chat)) }
        }
        _ => got
      }
    },
  }
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1600.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="打开侧栏")
  t.run_for(@ui.move_most_ms)
  let figure = fn() { t.words().filter(fn(w) { w.0 == "23%" && w.5 > 0.5 }) }
  let wide = figure()
  assert_true(wide.length() == 1, msg="\{wide}")
  let whole = wide[0].3
  // the panel from as narrow as it is beside the chat (360) to wider: its figure as wide as it is everywhere
  for w = 1100.0; w <= 1600.0; w = w + 20.0 {
    t.resize(w, 800.0)
    t.frame()
    let now = figure()
    assert_true(now.length() == 1 && now[0].3 >= whole - 0.5, msg="\{w}: \{now} (whole: \{whole})")
  }
}

///|
test "wide: Station 文件 from the chat's \"…\" beside it (kept by the core: chat.tabs.open); a row's 添加到消息 into its message" {
  new_run()
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
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="对话信息")
  t.frame()
  t.frame()
  t.tap_text("Station 文件")
  t.run_for(dmax(@kit.presence_out_ms, @ui.move_most_ms))
  let opened = named(calls, "chat.tabs.open")
  assert_eq(opened.length(), 1)
  assert_eq(text(Some(opened[0].params), "chat"), "ws1/st1:s-c1")
  assert_eq(text(Some(opened[0].params), "tab"), "files")
  assert_eq(side_now(r), (["files"], "files"))
  // its tab, and the station's home in it at the pane's right
  assert_true(t.find("主目录") is Some(_))
  // a file's menu: 添加到消息, into the chat's draft, named by its path
  @sfdesk.tab_place_set("ws1", Some({ station: "ws1/st1", root: Some(fix_docs), path: "" }))
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
  let refs = @sfbase.writings.get(draft_key(r)).map(fn(d) { d.files }).unwrap_or([])
  assert_eq(refs.length(), 1)
  assert_eq(text(field(Some(refs[0]), "ref"), "path"), fix_docs + "/发布清单.md")
  assert_eq(text(field(Some(refs[0]), "ref"), "stationName"), "Studio")
  // another row dragged off the tab onto the chat (ChatSide.tsx useChatDrop): let go there, into its draft too
  let (x, y) = match t.find("长篇小说.txt") {
    Some(at) => at
    None => fail("no 长篇小说.txt in the tab")
  }
  t.drag(x, y, 400.0, 400.0)
  t.frame()
  t.frame()
  let refs = @sfbase.writings.get(draft_key(r)).map(fn(d) { d.files }).unwrap_or([])
  assert_eq(refs.length(), 2)
  assert_eq(text(field(refs.get(1), "ref"), "path"), fix_docs + "/长篇小说.txt")
}

///|
test "wide: a new chat's Station 文件 beside it (NewChat.tsx): kept open, closed and opened by its bar's button; a row's 添加到消息 into its draft" {
  new_run()
  let calls : Array[Made] = []
  let base = fixture("newchat-files")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done, heard: None })
      (base.call)(name, params, done)
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() == NewChat)
  // kept open for the workspace's new chat: its tab, the station's home in it
  assert_true(t.find("主目录") is Some(_))
  t.click(Button, label="收起侧栏")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("主目录") is None)
  let closed = named(calls, "chat.tabs.close")
  assert_eq(closed.length(), 1)
  assert_eq(text(Some(closed[0].params), "chat"), "new:ws1")
  t.click(Button, label="Station 文件")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("主目录") is Some(_))
  // a file's 添加到消息: into the new chat's draft, named by its path
  @sfdesk.tab_place_set("ws1", Some({ station: "ws1/st1", root: Some(fix_docs), path: "" }))
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
  let refs = @sfbase.writings.get("new:ws1").map(fn(d) { d.files }).unwrap_or([])
  assert_eq(refs.length(), 1)
  assert_eq(text(field(Some(refs[0]), "ref"), "path"), fix_docs + "/发布清单.md")
}

///|
test "wide: the side panel's tabs are the core's (chat.tabs.*): an agent's history before 任务, the last left in front, the panel's switch closes them all" {
  new_run()
  let src = fixture("chat")
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms)
  assert_eq(side_now(r), ([], ""))
  side_change(r, "open", Some("jobs"))
  t.frame()
  side_change(r, "open", Some("s-c1"))
  t.frame()
  // (the history after the histories open, before the other tabs; in front as it is opened)
  assert_eq(side_now(r), (["s-c1", "jobs"], "s-c1"))
  t.run_for(@ui.move_most_ms)
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
  new_run()
  let src = fixture("chat")
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="打开侧栏")
  t.frame()
  // on its way in: its head further right than it will rest, as the column it shows through has widened so far
  t.run_for(@ui.move_most_ms / 2.0)
  let (mid, _) = t.find("只看收发").unwrap()
  t.run_for(@ui.move_most_ms / 2.0)
  let (end, _) = t.find("只看收发").unwrap()
  assert_true(mid > end, msg="in from the right: \{mid} then \{end}")
  // as it rests, no further
  t.run_for(@ui.move_most_ms)
  assert_eq(t.find("只看收发").map(fn(at) { at.0 }), Some(end))
  // closed: still there on its way out (what it showed), gone at its end
  t.click(Button, label="收起侧栏")
  t.frame()
  t.run_for(@ui.move_most_ms / 2.0)
  let (going, _) = t.find("只看收发").unwrap()
  assert_true(going > end, msg="out to the right: \{going}")
  t.run_for(@ui.move_most_ms / 2.0)
  assert_true(t.find("只看收发") is None)
  // opened again: in again, to where it rested
  t.click(Button, label="打开侧栏")
  t.run_for(@ui.move_most_ms)
  assert_eq(t.find("只看收发").map(fn(at) { at.0 }), Some(end))
}

///|
test "wide: an agent's history asked as a page (a link's ?history=…&entry=…) is its chat with the history beside it (ChatPage.tsx history)" {
  new_run()
  let src = fixture("chat")
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms)
  app.nav.push(History(r, "s-c1", Some(3)))
  t.frame()
  t.frame()
  // the chat's page, in place of the page asked; the history in front beside it
  assert_true(app.nav.top() == Chat(r), msg="the chat's page")
  assert_eq(side_now(r), (["s-c1"], "s-c1"))
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("只看收发") is Some(_))
}

///|
/// The chat as a Slack thread alone shows it (the core's page of an agent with no chat here: no thread, where its
/// Slack thread is and the way there).
fn slack_only(base : Source) -> Source {
  {
    ..base,
    topic: fn(name, params) {
      let got = (base.topic)(name, params)
      guard name == "chat" && got.value is Some(Object(v)) else { return got }
      let v = v.copy()
      v["thread"] = Json::null()
      v["place"] = Json::string("#ops")
      v["slackUrl"] = Json::string("https://afk.slack.com/archives/C1/p12")
      v.remove("xshare")
      v.remove("publish")
      @sfbase.topic_as_read(name, params, { ..got, value: Some(Json::object(v)) })
    },
  }
}

///|
test "wide: a chat of a Slack thread alone has its \"…\" too: where it is, its agents, the way to it in Slack" {
  new_run()
  let src = slack_only(fixture("chat"))
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="对话信息")
  t.frame()
  t.frame()
  assert_true(t.find("Slack · #ops") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
  assert_true(t.find("在 Slack 中打开") is Some(_))
  // (what only a chat of its own here has: who started it, when)
  assert_true(t.find("发起") is None)
}
