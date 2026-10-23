///|
test "the menu bar: the app's menu, 编辑 and 窗口, 检查更新 the app's own, in the app's words" {
  let zh = menu_bar_json()
  assert_true(zh.contains("{\"title\":\"退出 {app}\",\"role\":\"quit\"}"))
  assert_true(zh.contains("{\"title\":\"检查更新…\",\"action\":\"update.check\"}"))
  assert_true(zh.contains("\"title\":\"窗口\""))
  assert_true(zh.contains("\"role\":\"window\""))
  @sf.set_language(Some("en"))
  let en = menu_bar_json()
  @sf.set_language(None)
  assert_true(en.contains("{\"title\":\"Quit {app}\",\"role\":\"quit\"}"))
  assert_true(en.contains("{\"title\":\"Paste\",\"role\":\"paste\"}"))
}
