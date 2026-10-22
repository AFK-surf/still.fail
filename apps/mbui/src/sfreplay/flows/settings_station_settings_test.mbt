// 82-station-settings (e2e/traces/settings-station-settings.trace): the test station's page: Agent 环境变量 → 编辑变量,
// a variable typed and saved (agentEnv.form.*), then taken away; 版本 → 检查更新 (software.check).

///|
test "82-station-settings" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("settings-station-settings"), seed~)
    f.tap("icon:settings")
    f.run_to(@ui.nav_rest())
    f.tap("=Station")
    f.run_to(@ui.nav_rest())
    f.tap("=studio")
    f.run_to(@ui.nav_rest())
    f.wheel_at("在此 station 上", 450.0)
    f.tap("编辑变量")
    f.run_to(@kit.sheet_rest("settings-sheet"))
    f.tap("HTTPS_PROXY=")
    f.type_text("E2E_PROXY_080726=http://127.0.0.1:9")
    f.tap("=保存")
    // said as the station answers, the sheet still going down (its toast's time its own: looked at as it shows), and
    // gone before the next one is looked for
    f.see("已保存")
    f.toast_gone()
    f.see("E2E_PROXY_080726")
    // taken away again: the field by its words, once the station's text is in it (the page's line under the sheet is
    // not to be pressed)
    f.tap("编辑变量")
    f.run_to(@kit.sheet_rest("settings-sheet"))
    f.see("Agent 环境变量")
    f.tap("field:E2E_PROXY_080726=http")
    f.clear()
    f.tap("=保存")
    // said as it shows, and its time out before 检查更新 is pressed where it shows (a toast waits while the pointer is
    // on it)
    f.see("已保存")
    f.toast_gone()
    f.see("暂无变量")
    f.wheel_at("编辑变量", 1500.0)
    f.tap("=检查更新")
    f.end()
  })
}
