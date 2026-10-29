// 53-settings-sheet-sinking (e2e/traces/settings-sheet-sinking.trace): a sheet let go of: Station → the test station →
// "…" → 重命名 (the presenters' sheets on a phone), a new name typed, the scrim tapped; the sheet goes down on the
// sheet's spring, only drawn: 保存 tapped where it is drawn as it goes renames nothing (no station.rename asked).

///|
test "53-settings-sheet-sinking" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("settings-sheet-sinking"), seed~)
    f.tap("icon:settings")
    f.run_for(@ui.move_most_ms)
    f.tap("=Station")
    f.run_for(@ui.move_most_ms)
    f.tap("=studio")
    f.run_for(@ui.move_most_ms)
    // (the page under it at its 软件与设备: a sinking sheet is only drawn, a tap where its 保存 is drawn goes to what is
    // under it, here its versions' words, which take none; the overview has its rows to go to there)
    f.tap("=软件与设备")
    f.tap("icon:more")
    f.run_to(@kit.sheet_rest("sf-present"))
    f.tap("=重命名")
    f.run_to(@kit.sheet_rest("sf-present"))
    f.clear()
    f.type_text("e2e-not-082939")
    // the scrim tapped: the sheet sinks, only drawn; 保存 tapped where it is drawn on its way down takes nothing
    let (sx, sy) = f.t.reachable("=保存")[0]
    f.tap_at(195.0, 60.0)
    for dy in [0.0, 30.0, 60.0, 90.0] {
      f.tap_at(sx, sy + dy)
    }
    f.run_to(@kit.sheet_rest("sf-present"))
    f.gone("station 名称")
    f.see("=studio")
    f.end()
  })
}
