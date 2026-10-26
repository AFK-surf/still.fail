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
