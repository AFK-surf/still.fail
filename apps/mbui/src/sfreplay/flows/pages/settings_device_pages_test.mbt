// 87-device-pages (e2e/traces/settings-device-pages.trace): 下方栏: Station's "−" on the first bar, 用量 added from its
// sheet (prefs.set barsBy); 本机缓存 (cache.usage); 更新日志; 用量 → 价目表.

///|
test "87-device-pages" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("settings-device-pages"), seed~)
    f.tap("icon:settings")
    f.run_to(@ui.nav_rest())
    f.wheel_at("Workspace", 500.0)
    f.tap("=下方栏")
    f.run_to(@ui.nav_rest())
    f.see("第 1 栏")
    // Station's "−" (an icon, no words) at its icon's top right
    f.tap_at(345.0, 199.0)
    f.tap("=添加")
    f.run_to(@kit.sheet_rest("settings-sheet"))
    f.see("添加到第 1 栏")
    f.tap("=用量")
    f.run_to(@kit.sheet_rest("settings-sheet"))
    f.back()
    f.run_to(@ui.nav_rest())
    f.tap("=本机缓存")
    f.run_to(@ui.nav_rest())
    // (the local station's chats have no titles: each by its thread, as KeptFiles.kt)
    f.see("chat #1")
    f.back()
    f.run_to(@ui.nav_rest())
    f.tap("=更新日志")
    f.run_to(@ui.nav_rest())
    f.back()
    f.run_to(@ui.nav_rest())
    f.wheel_at("=本机缓存", -500.0)
    f.tap("=用量")
    f.run_to(@ui.nav_rest())
    f.tap("查看价目表")
    f.run_to(@ui.nav_rest())
    // (用量's days: its thumb a cover, placed where its choice is in the frame it shows, no motion of its own)
    f.see("=价目表")
    f.end()
  })
}
