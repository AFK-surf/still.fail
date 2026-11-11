// 连接 and a connect's page (connects.mbt, connect.mbt, slack_app.mbt) alone, at each width, with a finger and with a
// mouse: the connects with how they run, one's page with how it runs and what is done to it
// less often (its ⋯, the presenters' menu).

///|
test "连接, at each width and with either hand: the connects, each with how it runs; one pressed, its page" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(Connects(""), w, platform~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("星火助手") is Some(_), msg=at)
    assert_true(t.find("值班机器人") is Some(_), msg=at)
    let (x, y) = t.find_last("值班机器人").unwrap()
    t.tap(x, y)
    t.draw()
    t.run_for(@ui.move_most_ms)
    assert_true(app.nav.pages().iter().any(fn(p) { p is Setting(Connect(_, _)) }), msg=at)
  }
}

///|
test "a connect's page, at each width and with either hand: who it is, how it runs; its ⋯ a menu of what is done less often" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(Connect("ws1/st1", "k1"), w, platform~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("星火助手") is Some(_), msg=at)
    assert_false(@sf.presenting(), msg=at)
    let (x, y, bw, bh) = t.query(Button, label="更多").unwrap().rect
    t.tap(x + bw / 2.0, y + bh / 2.0)
    t.frame()
    assert_true(@sf.presenting(), msg=at)
  }
}

///|
test "a connect's Slack app, at a phone's width: its fold opened, the buddies and the makers to pick from, a picture to upload" {
  let calls : Array[String] = []
  let t = setting_tester(Connect("ws1/st1", "k1"), 390.0, platform=2, over=fn(s) {
    { ..s, call: fn(name, params, done) { calls.push(name); (s.call)(name, params, done) } }
  })
  t.add_pixels("https://app.still.fail/avatars/backend.webp", 2, 2, FixedArray::make(16, b'\xFF'))
  t.draw()
  let (x, y, w, h) = t.query(Link, label="Slack app").unwrap().rect
  t.tap(x + w / 2.0, y + h / 2.0)
  t.frame()
  // the core's buddies asked for once, then the makers after them
  assert_eq(calls.filter(fn(m) { m == "buddies" }).length(), 1)
  for a in ["后端接口", "移动应用", "写文档", "Anthropic", "OpenAI"] {
    assert_true(t.query(Button, label=a) is Some(_), msg=a)
  }
  // a picture of one's own: its icon's button
  assert_true(t.query(Button, label="上传图片") is Some(_))
}

///|
test "a connect's Slack app's permissions opened: each section's 全选 at its line's end, its title at its start" {
  for case in [(390.0, 2), (1280.0, 0)] {
    let (w, platform) = case
    let at = "\{w} platform \{platform}"
    let t = setting_tester(Connect("ws1/st1", "k1"), w, platform~)
    t.draw()
    let (x, y, bw, bh) = t.query(Link, label="Slack app").unwrap().rect
    t.tap(x + bw / 2.0, y + bh / 2.0)
    t.frame()
    t.run_for(@ui.move_most_ms)
    let (x, y, bw, bh) = drawn(t, "权限 · 已开启 4 / 16 项")
    t.tap(x + bw / 2.0, y + bh / 2.0)
    t.draw()
    t.run_for(@ui.move_most_ms)
    // (as far in from the card's right as its title from its left)
    let title = drawn(t, "消息")
    let all = drawn(t, "全选")
    let card = ground_round(t, title)
    let start = title.0 - card.0
    let end = card.0 + card.2 - (all.0 + all.2)
    assert_true((start - end).abs() < 0.5, msg="\{at}: the title \{start} in at the start, 全选 \{end} at the end")
  }
}
