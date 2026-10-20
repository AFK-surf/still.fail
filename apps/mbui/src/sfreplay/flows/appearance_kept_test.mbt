// 34-appearance-kept (e2e/traces/appearance-kept.trace): the app started again: dark from its first frame, as the
// core kept it (its prefs: appearance dark); 跟随系统 chosen again for the runs after (prefs.set appearance system).

///|
test "34-appearance-kept" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace_appearance_kept, seed~)
    f.see("端到端测试")
    assert_true(@sf.theme().dark)
    f.tap("icon:settings")
    f.run_for(@ui.nav_push_ms)
    f.see("外观")
    f.tap("外观")
    f.run_for(@ui.nav_push_ms)
    f.see("跟随系统")
    f.tap("=跟随系统", top=true)
    f.back()
    f.run_for(@ui.nav_push_ms)
    f.see("Workspace")
    // the appearance page's segmented choices: their thumbs chase last frame's layout on a spring
    f.end(unsettled_ok="sfapp/settings/parts.mbt:508 外观页分段选择的滑块用 c.spring 追上一帧的布局、自己要帧（等 app 迁移）")
  })
}
