///|
test "the menu bar: the system's menus, the pages' actions with their keys here, 检查更新 the app's own, in the app's words" {
  let zh = menu_bar_json(None, false)
  assert_true(zh.contains("{\"title\":\"退出 {app}\",\"role\":\"quit\"}"))
  assert_true(zh.contains("{\"title\":\"检查更新…\",\"action\":\"update.check\"}"))
  assert_true(zh.contains("\"title\":\"窗口\""))
  assert_true(zh.contains("\"role\":\"window\""))
  // the pages' own: their keys, those of a chat only with one open
  assert_true(zh.contains("{\"title\":\"新建对话\",\"action\":\"chat.new\",\"enabled\":true,\"keys\":\"Mod+N\"}"))
  assert_true(zh.contains("{\"title\":\"归档对话\",\"action\":\"chat.archive\",\"enabled\":false,\"keys\":\"Mod+Shift+E\"}"))
  assert_true(
    menu_bar_json(None, true).contains("{\"title\":\"归档对话\",\"action\":\"chat.archive\",\"enabled\":true"),
  )
  // keys changed in 快捷键: those
  let changed : Json = { "keys": { "chat.new": ["Mod+Alt+N"] } }
  assert_true(menu_bar_json(Some(changed), false).contains("\"action\":\"chat.new\",\"enabled\":true,\"keys\":\"Mod+Alt+N\""))
  @sf.set_language(Some("en"))
  let en = menu_bar_json(None, false)
  @sf.set_language(None)
  assert_true(en.contains("{\"title\":\"Quit {app}\",\"role\":\"quit\"}"))
  assert_true(en.contains("{\"title\":\"Paste\",\"role\":\"paste\"}"))
}

///|
test "the menu bar's items are their keys: 收起/展开侧边栏 chosen folds the sidebar, as ⌘\\ does" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  let before = wide.folded
  t.post(@hostapi.system_channel, "{\"menu\":\"sidebar.toggle\"}")
  t.frame()
  assert_eq(wide.folded, !before)
  // done once: the frame after does nothing more
  t.frame()
  assert_eq(wide.folded, !before)
}
