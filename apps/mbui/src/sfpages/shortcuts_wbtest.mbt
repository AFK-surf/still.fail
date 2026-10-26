// 快捷键 (shortcuts.mbt) alone, at each width, with a finger and with a mouse: each group's actions and their keys.

///|
test "快捷键, at each width and with either hand: each group's actions and their keys" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(Shortcuts, w, platform~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("快捷键") is Some(_), msg=at)
    assert_true(t.find("快速切换对话") is Some(_), msg=at)
  }
}
