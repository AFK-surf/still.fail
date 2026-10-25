// 快捷键, one page in every frame (src/sfdesk shortcuts.mbt): at a width of each tier, with a finger and with a mouse;
// each group's actions and their keys, a row pressed records new ones.

///|
test "快捷键, at each width and with either hand: each group's actions and their keys; a row pressed records" {
  for case in one_page_cases {
    let (w, platform, regular, _) = case
    let t = one_page_tester(@settings.Route::Shortcuts, w, platform~, regular~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("快捷键") is Some(_), msg=at)
    assert_true(t.find("快速切换对话") is Some(_), msg=at)
  }
}
