// 34-appearance-kept (e2e/traces/appearance-kept.trace): the app started again: dark from its first frame, as the
// core kept it (its prefs: appearance dark); 跟随系统 chosen again for the runs after (prefs.set appearance system).

///|
test "34-appearance-kept" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("appearance-kept"), seed~)
    f.see("端到端测试")
    assert_true(@sf.theme().dark)
    f.tap("icon:settings")
    f.run_for(@ui.nav_push_ms)
    f.see("外观")
    f.tap("外观")
    f.run_for(@ui.nav_push_ms)
    f.see("跟随系统")
    f.tap("=跟随系统", top=true)
    // its thumb slides there (Ctx::cover), from this tap to the end of its slide
    f.run_for(@ui.cover_slide_ms)
    f.back()
    f.run_for(@ui.nav_push_ms)
    f.see("Workspace")
    f.end()
  })
}
