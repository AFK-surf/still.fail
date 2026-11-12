// 86-decisions (e2e/traces/settings-decisions.trace): 自动决策 → 归档建议: 启用 switched on, 保存修改 refused (no model to
// check with), switched back: nothing left to save (the form as it was saved).

///|
test "86-decisions" {
  @sfreplay.orders(fn(seed) { flow_86_decisions(seed) })
}

///|
/// The flow of 86-decisions in the pass `seed` (@sfreplay.orders): its end's screen.
fn flow_86_decisions(seed : UInt) -> String {
  let f = @sfreplay.Flow::start(@sfreplay.trace("settings-decisions"), seed~)
  f.tap("icon:settings")
  f.run_to(@ui.nav_rest)
  f.tap("=自动决策")
  f.run_to(@ui.nav_rest)
  f.tap("归档建议")
  f.run_to(@ui.nav_rest)
  f.tap("switch:启用")
  f.tap("保存修改")
  f.see("请选择用于完成检查的模型")
  f.tap("switch:启用")
  f.gone("保存修改")
  f.toast_gone()
  f.end()
}
