// 53-settings-sheet-sinking (e2e/traces/settings-sheet-sinking.trace): a settings sheet let go of: Station → the test
// station → "…" → 重命名, a new name typed, the scrim tapped; the sheet goes down on the sheet's spring, only drawn:
// 保存 tapped where it is drawn as it goes renames nothing (no station.rename asked).

///|
test "53-settings-sheet-sinking" {
  @sfreplay.orders(fn(seed) raise {
    // (memory.get: in the run, one of the taps below that went through once the sheet was down landed on the station
    // page's 记忆 row and opened it; the page's bar is now as tall as Android's NavBar with its line under the title,
    // the rows 16 lower, and that tap lands under the row)
    let f = @sfreplay.Flow::start(@sfreplay.trace_settings_sheet_sinking, seed~, skip=["client.device", "memory.get"])
    f.tap("icon:settings")
    f.run_for(@ui.nav_push_ms)
    f.tap("=Station")
    f.run_for(@ui.nav_push_ms)
    f.tap("=studio")
    f.run_for(@ui.nav_push_ms)
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
