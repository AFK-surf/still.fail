// 89-run-settings (e2e/traces/settings-run-settings.trace): the chat's agent → 历史 → 详情 → how it runs: 思考深度 high and
// a model picked (pick.set), 改成 … saved (pick.save).

///|
test "89-run-settings" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace_settings_run_settings, seed~)
    f.tap("端到端测试")
    f.run_to(@ui.nav_rest())
    f.see("=studio")
    f.tap("icon:more")
    // the chat's own sheet (decide.mbt's)
    f.run_to(@kit.sheet_rest("decide-sheet"))
    // the agent's part of the same sheet
    f.tap("icon:chevron-right")
    f.tap("=历史")
    f.run_to(@ui.nav_rest())
    // 详情: a tab of the history page
    f.tap("=详情")
    // how it runs: its page pushed
    f.tap("icon:chevron-down")
    f.run_to(@ui.nav_rest())
    f.see("思考深度")
    f.tap("=high")
    f.tap("=选择模型")
    f.tap("Sonnet")
    f.see("改成")
    f.tap("改成")
    f.see("已更改，下一轮起生效")
    f.toast_gone()
    f.end()
  })
}
