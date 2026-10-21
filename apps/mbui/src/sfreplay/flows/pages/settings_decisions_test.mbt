// 86-decisions (e2e/traces/settings-decisions.trace): 自动决策 → 归档建议: 启用 switched on, 保存修改 refused (no model to
// check with), switched back and saved.

///|
test "86-decisions" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace_settings_decisions, seed~)
    f.tap("icon:settings")
    f.run_to(@ui.nav_rest())
    f.wheel_at("Workspace", 300.0)
    f.tap("=自动决策")
    f.run_to(@ui.nav_rest())
    f.tap("归档建议")
    f.run_to(@ui.nav_rest())
    f.tap("=启用")
    f.tap("保存修改")
    f.see("请选择用于完成检查的模型")
    f.tap("=启用")
    f.tap("保存修改")
    f.gone("保存修改")
    f.toast_gone()
    f.end()
  })
}
