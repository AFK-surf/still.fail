// 33-settings-appearance (e2e/traces/settings-appearance.trace): settings from Home's gear; 外观 → 浅色, then 深色: the
// app drawn so at once, and the core keeps it on the device (prefs.set appearance, light then dark).

///|
test "33-settings-appearance" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace_settings_appearance, seed~)
    f.see("端到端测试")
    f.tap("icon:settings")
    f.run_for(@ui.nav_push_ms)
    f.see("Workspace")
    f.see("外观")
    f.tap("外观")
    f.run_for(@ui.nav_push_ms)
    f.see("跟随系统")
    f.tap("=浅色")
    assert_true(!@sf.theme().dark)
    f.tap("=深色")
    assert_true(@sf.theme().dark)
    f.back()
    f.run_for(@ui.nav_push_ms)
    f.see("Workspace")
    // the appearance page's segmented choices: their thumbs chase last frame's layout on a spring
    f.end(unsettled_ok="sfapp/settings/parts.mbt:508 外观页分段选择的滑块用 c.spring 追上一帧的布局、自己要帧（等 app 迁移）")
  })
}
