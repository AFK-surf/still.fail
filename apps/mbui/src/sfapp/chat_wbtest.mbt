///|
/// The made-up chat open over Home (chat_fixture.mbt), from its start: pushed in.
fn chat_tester(mode : String) -> @ui.Tester {
  reset()
  let src = fixture(mode)
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0)
  t.run_for(@ui.nav_push_ms)
  t
}

///|
test "a chat opens at its end: its bar, its last messages, the composer's room under them" {
  let t = chat_tester("chat")
  assert_true(t.find("整理发布清单") is Some(_))
  let (_, y) = t.find("做完了：列表、跳到最新的按钮").unwrap()
  // the last message over the composer's capsule
  assert_true(y < 844.0 - 110.0 && y > 500.0)
  assert_true(t.find("归档此对话") is Some(_))
  assert_true(t.find("发消息") is Some(_))
  // an options card, a login card, a failing notice
  assert_true(t.find("一起换") is Some(_))
  assert_true(t.find("在 Studio 上登录 gh") is Some(_))
  assert_true(t.find("Studio 上 codex 的登录已失效") is Some(_))
  // no way to the newest at the newest
  assert_true(!readings.get("ws1/st1\u{1}s-c1").unwrap().jump)
  t.assert_idle()
}

///|
test "scrolled up, the way to the newest shows; tapped, the list glides back to its end" {
  let t = chat_tester("chat")
  t.move(195.0, 400.0)
  t.wheel(195.0, 400.0, -900.0)
  let rd = readings.get("ws1/st1\u{1}s-c1").unwrap()
  assert_true(rd.jump)
  assert_true(t.find("做完了：列表、跳到最新的按钮") is None)
  // over the send button, the composer's room under it
  t.tap(390.0 - 18.0 - 18.0, 844.0 - 112.0 - 18.0)
  assert_true(t.find("做完了：列表、跳到最新的按钮") is Some(_))
  assert_true(!rd.jump)
}

///|
test "the viewer's words on the right, everyone else's under their name" {
  let t = chat_tester("chat")
  t.move(195.0, 400.0)
  t.wheel(195.0, 400.0, -500.0)
  // a bubble ending at the list's right edge (14 in), an agent's words from its left
  let (bx, _, bw, _) = t.rect_of("还有深色模式也看一下").unwrap()
  assert_true(bx > 195.0 && (bx + bw - (390.0 - 14.0 - 14.0)).abs() < 1.0)
  let (ax, _, _, _) = t.rect_of("高度先按 90 估").unwrap()
  assert_eq(ax, 14.0)
}

///|
test "near the top the page before comes in, and what is in view stays where it is" {
  let t = chat_tester("chat")
  t.move(195.0, 400.0)
  // up to the first message: the page before is asked for there, and comes in above it
  let mut tries = 0
  while t.find("Studio 上的 claude 已启动") is None && tries < 40 {
    t.wheel(195.0, 400.0, -300.0)
    tries = tries + 1
  }
  let (_, y0) = t.find("Studio 上的 claude 已启动").unwrap()
  // from here on it moves by what is scrolled, never more (the pages coming in above do not push it)
  let mut y = y0
  for _ in 0..<3 {
    t.wheel(195.0, 400.0, -100.0)
    let (_, y1) = t.find("Studio 上的 claude 已启动").unwrap()
    assert_true(y1 - y <= 100.5)
    y = y1
  }
  t.wheel(195.0, 400.0, -300.0)
  assert_true(t.find("第 1 页之前的第 10 条") is Some(_) || t.find("第 2 页之前的第 10 条") is Some(_))
}

///|
test "a reference to another chat is its chip, and opens that chat" {
  let t = chat_tester("chat")
  t.move(195.0, 400.0)
  let mut scrolled = -1.0
  for _ in 0..<4 {
    if t.find("性能数据放在") is Some(_) {
      break
    }
    t.wheel(195.0, 400.0, -400.0)
    scrolled = t.time()
  }
  assert_true(t.find("@首页的列表改成按天分组") is Some(_))
  t.tap_run("首页的列表改成按天分组")
  assert_eq(app.nav.depth(), 3)
  match app.nav.top() {
    Chat(r) => {
      assert_eq(r.station, "ws1/st1")
      assert_eq(r.session, "s-c2")
    }
    _ => fail("not a chat")
  }
  // the chat pushed in
  t.run_for(@ui.nav_push_ms)
  // and the scroll bar of the list under it gone: shown since its last wheel, then faded out
  if scrolled >= 0.0 {
    t.run_for(scrolled + @ui.scrollbar_hold_ms + @ui.scrollbar_fade_ms - t.time())
  }
  t.assert_idle()
}

///|
test "while the chat is read: its bar, the messages to come, the composer" {
  let t = chat_tester("chat-loading")
  assert_true(t.find("发消息") is Some(_))
  assert_true(t.find("整理发布清单") is None)
}

///|
test "references and addresses in plain words" {
  let runs = ref_runs("看 [首页](https://app.still.fail/w/ws1/s/st1/chats/s-c2) 和 https://example.com/a。")
  assert_eq(runs.length(), 6)
  assert_eq(runs[1].text, "@")
  assert_eq(runs[2].text, "首页")
  assert_eq(runs[2].link, "https://app.still.fail/w/ws1/s/st1/chats/s-c2")
  assert_eq(runs[3].text, " 和 ")
  assert_eq(runs[4].link, "https://example.com/a")
  assert_eq(runs[5].text, "。")
}

///|
test "images take their own proportions before they load" {
  let a : Attachment = {
    name: "a.png",
    path: "a.png",
    size: 0.0,
    width: 1170.0,
    height: 2532.0,
    thumbhash: "",
    owner: "",
  }
  assert_eq(image_box(a, 16.0), (139.0, 300.0, false))
  assert_eq(image_box({ ..a, width: 1600.0, height: 900.0 }, 16.0), (360.0, 203.0, false))
  assert_eq(image_box({ ..a, width: 0.0, height: 0.0 }, 16.0), (240.0, 160.0, false))
  assert_eq(file_size(18432.0), "18 KB")
  assert_eq(file_size(812000.0), "793 KB")
  assert_eq(file_size(4.5 * 1048576.0), "4.5 MB")
  assert_eq(elapsed(200000.0), "3m 20s")
}

///|
/// (Here, after the chat's own: a chat scrolled leaves the made-up chat as it is for the tests after it.)
test "a file card in the chat opens its preview" {
  reset()
  let src = fixture("chat")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0)
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  t.run_for(@ui.nav_push_ms)
  t.move(195.0, 400.0)
  t.wheel(195.0, 400.0, -600.0)
  t.tap_text("build.log")
  assert_true(viewer.val is Some(_))
  assert_eq(viewer.val.unwrap().file.name, "build.log")
  // the preview flown open, its bars left alone till they rest
  t.run_for(fly_open_ms)
  t.run_for(rest_ms)
  t.assert_idle()
}

///|
test "what waits to be decided and is out of view: a bell over the way to the end; tapped, the first one's post" {
  let t = chat_tester("chat")
  t.draw()
  let rd = readings.get("ws1/st1\u{1}s-c1").unwrap()
  // both cards in view at the end: no bell
  assert_true(!rd.ask)
  // dragged down (a finger's: no easing to wait for), the cards below what shows
  t.drag(195.0, 150.0, 195.0, 750.0)
  t.drag(195.0, 150.0, 195.0, 750.0)
  t.draw()
  assert_true(rd.ask)
  assert_true(rd.jump)
  // over the way to the end, once it has risen (the list, still flung, is stopped by a tap first: it takes that one)
  t.run_for(ask_lift_ms)
  let (bx, by) = (390.0 - 18.0 - 18.0, 844.0 - composer_room_of(t.ctx()) - 2.0 - 44.0 - 18.0)
  if t.list_moving() {
    t.tap(bx, by)
  }
  assert_true(!t.list_moving())
  t.tap(bx, by)
  t.draw()
  assert_eq(rd.flash, "ts8")
  // the next tap goes to the next one's
  assert_eq(ask_turns.get("ws1/st1\u{1}s-c1"), Some(1))
}
