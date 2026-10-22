// 53-settings-sheet-sinking (e2e/traces/settings-sheet-sinking.trace): a settings sheet let go of: Station → the test
// station → "…" → 重命名, a new name typed, the scrim tapped; the sheet goes down on the sheet's spring, only drawn:
// 保存 tapped where it is drawn as it goes renames nothing (no station.rename asked).

///|
test "53-settings-sheet-sinking" {
  @sfreplay.orders(fn(seed) raise {
    // (the station's page asked for its logins and its workspaces as the run had it, all in one page; they are its
    // 设置's now, which this flow does not open: those asks dropped, with what came for them)
    let f = @sfreplay.Flow::start(@sfreplay.trace("settings-sheet-sinking"), seed~, drop=["machineLogins", "memberships"])
    f.tap("icon:settings")
    f.run_for(@ui.nav_push_ms)
    f.tap("=Station")
    f.run_for(@ui.nav_push_ms)
    f.tap("=studio")
    f.run_for(@ui.nav_push_ms)
    // (the page under it at its 软件与设备: a sinking sheet is only drawn, a tap where its 保存 is drawn goes to what is
    // under it, here its versions' words, which take none; the overview has its rows to go to there)
    f.tap("=软件与设备")
    f.tap("icon:more")
    f.run_to(@kit.sheet_rest("settings-sheet"))
    f.tap("重命名")
    f.run_to(@kit.sheet_rest("settings-sheet"))
    f.clear()
    f.type_text("e2e-not-082939")
    // the scrim tapped: the sheet sinks, only drawn; 保存 tapped where it is drawn on its way down takes nothing
    f.tap_at(195.0, 60.0)
    f.tap_at(-60.0, -330.0)
    f.tap_at(-60.0, -300.0)
    f.tap_at(-60.0, -270.0)
    f.tap_at(-60.0, -240.0)
    f.run_to(@kit.sheet_rest("settings-sheet"))
    f.gone("station 名称")
    f.see("=studio")
    f.end()
  })
}
