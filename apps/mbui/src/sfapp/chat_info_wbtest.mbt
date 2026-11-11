// The open chat's bar on 大屏 (sfdesk's chat_page.mbt): its title while a new one goes (chat_title), its info's
// popover (chat_info: its pull requests, what else was said in it), its services' popover (chat_jobs_pop).

///|
/// The fixture's chat (`mode`) on 大屏 with a Mac's keys, its calls kept in `calls` and answered with nothing; each
/// topic as `over` makes it.
fn bar_chat(calls : Array[Made], mode? : String = "chat", over? : (String, Topic) -> Topic = fn(_, t) { t }) -> @ui.Tester {
  new_run()
  let base = fixture(mode)
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done })
      done(Ok(Json::object({})))
    },
    topic_read: fn(name, params) { over(name, base.topic(name, params).get().snapshot()) },
  }
  open_fixture_over(mode, src)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// The core's `doing` with one `chat.rename` of the fixture's chat to `title`, at `stage` ("failed": why `error`).
fn renaming(title : String, stage? : String = "sent", error? : String = "") -> (String, Topic) -> Topic {
  fn(name, tp) {
    guard name == "doing" else { return tp }
    let d : Json = {
      "call": "chat.rename",
      "stage": Json::string(stage),
      "error": Json::string(error),
      "params": { "station": "ws1/st1", "session": "s-c1", "title": Json::string(title) },
    }
    { ..tp, value: Some({ "doing": [d] }) }
  }
}

///|
test "大屏: a chat being renamed has its new title in its bar at once, a turning mark beside it saying 正在重命名" {
  let calls : Array[Made] = []
  let t = bar_chat(calls, over=renaming("发布清单 v2"))
  assert_true(t.find("发布清单 v2") is Some(_), msg="\{Repr(t.words().map(fn(w) { w.0 }))}")
  // (the bar's title: its old one only where the list's row still says it, not in the bar)
  let bar_words = t.words().filter(fn(w) { w.2 < 60.0 && w.1 > 300.0 }).map(fn(w) { w.0 })
  assert_true(!bar_words.contains("整理发布清单"), msg="\{Repr(bar_words)}")
  let (x, y, w, h) = t.rect_of("发布清单 v2").unwrap()
  t.move_to(x + w + 12.0, y + h / 2.0)
  t.run_for(@ui.move_most_ms * 3.0)
  assert_true(t.find("正在重命名") is Some(_), msg="\{Repr(t.words().map(fn(w) { w.0 }))}")
}

///|
test "大屏: a rename that failed leaves the chat's own title in its bar, a mark beside it saying why" {
  let calls : Array[Made] = []
  let t = bar_chat(calls, over=renaming("发布清单 v2", stage="failed", error="无法重命名：Willow 不在线"))
  assert_true(t.find("发布清单 v2") is None)
  let bar = t.words().filter(fn(w) { w.2 < 60.0 && w.1 > 300.0 && w.0 == "整理发布清单" })
  assert_true(bar.length() == 1, msg="\{Repr(t.words().map(fn(w) { (w.0, w.1, w.2) }))}")
  let (_, x, y, w, h, _) = bar[0]
  t.move_to(x + w + 12.0, y + h / 2.0)
  t.run_for(@ui.move_most_ms * 3.0)
  assert_true(t.find("无法重命名：Willow 不在线") is Some(_), msg="\{Repr(t.words().map(fn(w) { w.0 }))}")
}

///|
test "大屏: the chat's info lists its first three pull requests, each pressed opened by its link; 全部 4 个 PR opens what was said beside the chat" {
  let calls : Array[Made] = []
  let t = bar_chat(calls)
  t.click(Button, label="对话信息")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("列表里的图片按需解码") is Some(_), msg="\{Repr(t.words().map(fn(w) { w.0 }))}")
  assert_true(t.find("#131") is Some(_))
  // (the fourth only among all of them)
  assert_true(t.find("去掉旧的分页加载") is None)
  t.click(Link, label="列表里的图片按需解码")
  t.draw()
  let parsed = named(calls, "link.parse")
  assert_true(parsed.iter().any(fn(m) { text(Some(m.params), "url") == "https://github.com/acme/shop/pull/131" }))
  t.click(Button, label="对话信息")
  t.run_for(@ui.move_most_ms)
  t.tap_text("全部 4 个 PR")
  t.draw()
  let opened = named(calls, "chat.tabs.open")
  assert_eq(opened.length(), 1)
  assert_eq(text(Some(opened[0].params), "tab"), "things")
}

///|
test "大屏: the chat's info says how much else was said in it (图片、文件和链接); pressed, that opens beside the chat" {
  let calls : Array[Made] = []
  let t = bar_chat(calls)
  t.click(Button, label="对话信息")
  t.run_for(@ui.move_most_ms)
  t.tap_text("图片、文件和链接")
  t.draw()
  let opened = named(calls, "chat.tabs.open")
  assert_eq(opened.length(), 1)
  assert_eq(text(Some(opened[0].params), "tab"), "things")
  // (its popover gone with it)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("全部 4 个 PR") is None)
}

///|
test "大屏: a service chosen in the chat's services' popover opens 任务 beside the chat; a job there opens and closes in place" {
  let calls : Array[Made] = []
  let t = bar_chat(calls, mode="chat-jobs-pop")
  // (the job the fixture opened: its last notice in place)
  assert_true(t.find("第 3 步通过：单元测试全部通过") is Some(_), msg="\{Repr(t.words().map(fn(w) { w.0 }))}")
  t.tap_text("盯 CI")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("第 3 步通过：单元测试全部通过") is None)
  assert_eq(named(calls, "chat.tabs.open").length(), 0)
  t.tap_text("web")
  t.draw()
  let opened = named(calls, "chat.tabs.open")
  assert_true(opened.iter().any(fn(m) { text(Some(m.params), "tab") == "jobs" }), msg="\{Repr(calls.map(fn(m) { m.name }))}")
}

///|
test "大屏: the chat's bar shows five of its people at most, +n for the rest; its info says how many take part" {
  let people : Array[Json] = []
  for i in 0..<7 {
    people.push({ "id": Json::string("p\{i}"), "shown": { "name": Json::string("成员\{i}"), "display": Json::string("成员\{i}") } })
  }
  let calls : Array[Made] = []
  let t = bar_chat(calls, over=fn(name, tp) {
    guard name == "chat" && tp.value is Some(Object(m)) else { return tp }
    let o = m.copy()
    o["people"] = Json::array(people)
    { ..tp, value: Some(Json::object(o)) }
  })
  assert_true(t.find("+2") is Some(_), msg="\{Repr(t.words().map(fn(w) { w.0 }))}")
  t.click(Button, label="对话信息")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("7 人") is Some(_), msg="\{Repr(t.words().map(fn(w) { w.0 }))}")
}
