///|
test "the menu bar: the system's menus, the pages' actions with their keys here, 检查更新 the app's own, in the app's words" {
  // the core's keymap (the fixture's: keymap_fixture.mbt), keys changed here or none
  let prefs = fn(changed : Map[String, Array[String]]) -> Json? { Some({ "keymap": fixture_keymap(changed) }) }
  // (the app's words, as it says them as it starts)
  @sf.set_words(fill)
  let zh = menu_bar_json(prefs({}), false)
  assert_true(zh.contains("{\"title\":\"退出 {app}\",\"role\":\"quit\"}"))
  assert_true(zh.contains("{\"title\":\"检查更新…\",\"action\":\"update.check\"}"))
  assert_true(zh.contains("\"title\":\"窗口\""))
  assert_true(zh.contains("\"role\":\"window\""))
  // the menu of the app's icon in Windows' notification area: back, or quit
  assert_true(
    zh.contains(
      "{\"title\":\"打开 {app}\",\"items\":[{\"title\":\"打开 {app}\",\"role\":\"show\"},{\"separator\":true},{\"title\":\"退出 {app}\",\"role\":\"quit\"}],\"role\":\"tray\"}",
    ),
  )
  // the pages' own: their keys, those of a chat only with one open
  assert_true(zh.contains("{\"title\":\"新建对话\",\"action\":\"chat.new\",\"enabled\":true,\"keys\":\"Mod+N\"}"))
  assert_true(zh.contains("{\"title\":\"归档对话\",\"action\":\"chat.archive\",\"enabled\":false,\"keys\":\"Shift+Mod+E\"}"))
  assert_true(
    menu_bar_json(prefs({}), true).contains("{\"title\":\"归档对话\",\"action\":\"chat.archive\",\"enabled\":true"),
  )
  // keys changed in 快捷键: those
  assert_true(
    menu_bar_json(prefs({ "chat.new": ["Alt+Mod+N"] }), false).contains(
      "\"action\":\"chat.new\",\"enabled\":true,\"keys\":\"Alt+Mod+N\"",
    ),
  )
  @sf.set_language(Some("en"))
  let en = menu_bar_json(prefs({}), false)
  @sf.set_language(None)
  assert_true(en.contains("{\"title\":\"Quit {app}\",\"role\":\"quit\"}"))
  assert_true(en.contains("{\"title\":\"Paste\",\"role\":\"paste\"}"))
  assert_true(en.contains("{\"title\":\"Open {app}\",\"role\":\"show\"}"))
}

///|
test "the menu bar's items are their keys: 收起/展开侧边栏 chosen folds the sidebar, as ⌘\\ does" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  let before = @sfdesk.wide.folded.get()
  t.post(@hostapi.system_channel, "{\"menu\":\"sidebar.toggle\"}")
  t.frame()
  assert_eq(@sfdesk.wide.folded.get(), !before)
  // done once: the frame after does nothing more
  t.frame()
  assert_eq(@sfdesk.wide.folded.get(), !before)
}
