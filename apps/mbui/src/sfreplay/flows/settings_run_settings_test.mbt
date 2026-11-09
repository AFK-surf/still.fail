// 89-run-settings (e2e/traces/settings-run-settings.trace): the chat's agent → 历史 → 详情 → its model picker;
// 思考深度 high and a model picked, each saved as it is chosen.

///|
test "89-run-settings" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("settings-run-settings"), seed~)
    f.tap("端到端测试")
    f.run_to(@ui.nav_rest())
    f.see("=willow")
    f.tap("icon:info")
    // the chat's own sheet (decide.mbt's)
    f.run_to(@kit.sheet_rest("sf-present"))
    // the agent's part of the same sheet
    // (its first row's: under it, the pull requests' and the public links' have one too)
    f.tap("icon:chevron-right", top=true)
    f.tap("=历史")
    f.run_to(@ui.nav_rest())
    // 详情: a tab of the history page
    f.tap("=详情")
    // How it runs: the shared model picker rises from the foot.
    f.tap("icon:chevron-down")
    f.run_to(@kit.sheet_rest("sf-present"))
    f.tap("思考深度")
    f.run_to(@kit.sheet_rest("sf-present"))
    f.tap("=高")
    f.run_to(@kit.sheet_rest("sf-present"))
    f.tap("Sonnet")
    f.see("已更改，下一轮起生效")
    f.toast_gone()
    f.end()
  })
}
