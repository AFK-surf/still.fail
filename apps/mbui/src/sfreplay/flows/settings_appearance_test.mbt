// 33-settings-appearance (e2e/traces/settings-appearance.trace): settings from Home's gear; 外观 → 浅色, then 深色: the
// app drawn so at once, and the core keeps it on the device (prefs.set appearance, light then dark).

///|
test "33-settings-appearance" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("settings-appearance"), seed~)
    f.see("端到端测试")
    f.tap("icon:settings")
    f.run_for(@ui.move_most_ms)
    f.see("=设置")
    // (此设备's rows under the fold: what the page holds scrolled to them, the wheel over the window's middle)
    f.wheel(300.0)
    f.see("外观")
    f.tap("外观")
    f.run_for(@ui.move_most_ms)
    f.see("跟随系统")
    f.tap("=浅色")
    assert_true(!@sf.theme().dark)
    f.tap("=深色")
    assert_true(@sf.theme().dark)
    // its thumb slides there (Ctx::cover), from this tap to the end of its slide
    f.run_for(@ui.cover_slide_ms)
    f.back()
    f.run_for(@ui.move_most_ms)
    // (back on the settings where it was left, scrolled to 此设备's rows: the page's title above them)
    f.see("=外观")
    f.end()
  })
}
