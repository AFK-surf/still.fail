// 89-run-settings (e2e/traces/settings-run-settings.trace): the chat's agent → 历史 → 详情 → its model picker;
// 思考深度 high and a model picked, each saved as it is chosen.

///|
test "89-run-settings" {
  @sfreplay.orders(fn(seed) {
    // (the agent's card read by the chat's sheet, then by 详情: the run let it go as the sheet went (a frame took what
    // came meanwhile) and asked again for the tab; handed over between two frames as a device's is, it is one watch all
    // along now, what came for the second given to the first)
    let f = @sfreplay.Flow::start(@sfreplay.trace("settings-run-settings"), seed~, drop=[
      "{\"id\":34,\"unsubscribe\":true}", "{\"id\":36,\"subscribe\":{\"topic\":\"agentCard\"",
    ])
    f.tap("端到端测试")
    f.run_to(@ui.nav_rest)
    f.see("=willow")
    f.tap("icon:info")
    // the chat's own sheet (decide.mbt's)
    f.run_to(@sf.presented_rest)
    // the agent's part of the same sheet
    // (its first row's: under it, the pull requests' and the public links' have one too)
    f.tap("icon:chevron-right", top=true)
    f.tap("=历史")
    f.run_to(@ui.nav_rest)
    // 详情: a tab of the history page
    f.tap("=详情")
    // How it runs: the shared model picker rises from the foot.
    f.tap("icon:chevron-down")
    f.run_to(@sf.presented_rest)
    // 思考深度: its stops in the sheet itself (@sf.stops), a level a tap; the third of its five (低 to 最高) is 高, the
    // middle of its track. No model is picked yet, so the core keeps none of it (`saved: false`) and the track goes
    // back to none: that it was asked is held at the flow's end, as every ask of the run's is.
    let (x, y, w, h) = f.t.query(@ui.Role::Slider, label="思考深度").map(fn(s) { s.rect }).unwrap_or((0.0, 0.0, 0.0, 0.0))
    f.tap_at(f.measured(x + w / 2.0), f.measured(y + h / 2.0))
    f.tap("Sonnet")
    f.see("已更改，下一轮起生效")
    f.toast_gone()
    f.end()
  })
}
