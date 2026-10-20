// 35-station-rename (e2e/traces/station-rename.trace): Settings → Station → the test station's page → "…" → 重命名:
// the new name in the bar and the list at once (station.rename); named back after.

///|
test "35-station-rename" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace_station_rename, seed~)
    f.see("端到端测试")
    f.tap("icon:settings")
    f.run_for(@ui.nav_push_ms)
    f.tap("=Station")
    f.run_for(@ui.nav_push_ms)
    f.tap("=studio")
    f.run_for(@ui.nav_push_ms)
    f.see("在此 station 上")
    for name in ["e2e-082939", "studio"] {
      f.tap("icon:more")
      f.run_to(@kit.sheet_rest("settings-sheet"))
      f.tap("重命名")
      f.run_to(@kit.sheet_rest("settings-sheet"))
      f.see("station 名称")
      f.clear()
      f.type_text(name)
      f.tap("=保存")
      f.run_to(@kit.sheet_rest("settings-sheet"))
      f.see("=" + name)
    }
    // 已重命名 said for its time, then gone
    // (its time out at the last frame: it starts going with the one after)
    f.run_for(@sfapp.toast_ms)
    f.t.draw()
    f.run_to_rest("toast")
    f.end()
  })
}
