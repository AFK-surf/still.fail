// The workspace's page (workspace_page.mbt) alone, at each width, with a finger and with a mouse: its people, its
// relays, leaving it asked first; a person pressed on a phone.

///|
test "the workspace, at each width and with either hand: its name, its people and those waiting, leaving it asked first" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(Workspace, w, platform~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("星火工作室") is Some(_), msg=at)
    assert_true(t.find("lin@example.com") is Some(_), msg=at)
    assert_false(@sf.presenting(), msg=at)
  }
}

///|
test "the workspace's ways its devices reach its stations, at each width: one row saying how many are off; pressed, a panel with each on or off, Tailscale's turned off asks still.fail cloud (workspace.setWay)" {
  for case in page_cases {
    let (w, platform) = case
    let calls : Array[(String, Json)] = []
    let t = setting_tester(Workspace, w, platform~, h=2400.0, over=fn(s) {
      { ..s, call: fn(name, params, done) { calls.push((name, params)); (s.call)(name, params, done) } }
    })
    let at = "\{w} platform \{platform}"
    // the page: the row alone, what is off said at its end
    assert_true(t.find("已关闭 1 项") is Some(_), msg=at)
    assert_true(t.find("Tailscale") is None, msg=at)
    t.tap_text("连接方式")
    t.run_for(@ui.move_most_ms)
    assert_true(@sf.presenting(), msg=at)
    assert_true(t.find("北京") is Some(_), msg=at)
    assert_eq(t.get(Switch, label="打洞").check, Some(Off), msg=at)
    let (x, y, sw, sh) = t.get(Switch, label="Tailscale").rect
    t.tap(x + sw / 2.0, y + sh / 2.0)
    t.frame()
    let asked = calls.filter(fn(c) { c.0 == "workspace.setWay" })
    assert_eq(asked.length(), 1, msg=at)
    assert_eq(text(Some(asked[0].1), "way"), "tailnet", msg=at)
    assert_false(flag(Some(asked[0].1), "on"), msg=at)
    @sf.presenters_reset()
  }
}

///|
test "the workspace on a phone: a person pressed, what can be done about them in a sheet; moving them out asked first" {
  let t = setting_tester(Workspace, 390.0, platform=2)
  assert_false(@sf.presenting())
  t.tap_text("ana@example.com")
  t.frame()
  // the owner's: their role, moving them out
  assert_true(@sf.presenting())
  assert_true(t.find("移出 workspace") is Some(_), msg=t.drawn_text())
  assert_true(t.find("管理所有内容") is Some(_))
}
