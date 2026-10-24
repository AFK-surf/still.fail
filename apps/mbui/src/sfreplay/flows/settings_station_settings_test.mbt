// 82-station-settings (e2e/traces/settings-station-settings.trace): the test station's page: its 设置's Agent 环境变量,
// edited where it is (agentEnv.form.*): a variable typed and saved, then taken away; its 软件与设备's 检查更新
// (software.check).

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
    f.tap("=设置")
    // (its variables under its permissions and logins: past the window's foot)
    f.wheel_at("=软件与设备", 600.0)
    f.tap("HTTPS_PROXY=")
    f.type_text("E2E_PROXY_080726=http://127.0.0.1:9")
    // 取消 once the core's draft has what is typed: 保存 takes it from then
    f.see("=取消")
    f.tap("=保存")
    // said as the station answers (its toast's time its own: looked at as it shows), gone before the next one
    f.see("已保存")
    f.toast_gone()
    f.gone("=取消")
    // taken away again: the field by its words, once the station's text is in it
    f.tap("field:E2E_PROXY_080726=http")
    f.clear()
    f.see("=取消")
    f.tap("=保存")
    // said as it shows, and its time out before 检查更新 is pressed where it shows (a toast waits while the pointer is
    // on it)
    f.see("已保存")
    f.toast_gone()
    f.gone("=取消")
    // (back up to its parts)
    f.wheel_at("=Agent 环境变量", -1200.0)
    f.tap("=软件与设备")
    // (under its software, a row each: past the window's foot)
    f.wheel_at("=软件与更新", 2000.0)
    f.tap("=检查更新")
    f.end()
  })
}
