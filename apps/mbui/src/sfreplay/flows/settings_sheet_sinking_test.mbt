// 53-settings-sheet-sinking (e2e/traces/settings-sheet-sinking.trace): a sheet let go of: Station → the test station →
// "…" → 重命名 (the presenters' sheets on a phone), a new name typed, the scrim tapped; the sheet goes down on the
// sheet's spring, only drawn: 保存 tapped where it is drawn as it goes renames nothing (no station.rename asked).

///|
test "53-settings-sheet-sinking" {
  @sfreplay.orders(fn(seed) {
    let f = @sfreplay.Flow::start(@sfreplay.trace("settings-sheet-sinking"), seed~)
    f.tap("icon:settings")
    f.run_for(@ui.move_most_ms)
    f.tap("=Station")
    f.run_for(@ui.move_most_ms)
    f.tap("=willow")
    f.run_for(@ui.move_most_ms)
    // (the page under it at its 设置: a sinking sheet is only drawn, a tap where its 保存 is drawn goes to what is
    // under it, here its versions' words, which take none; the overview has its rows to go to there)
    f.tap("=设置")
    f.tap("icon:more")
    f.run_to(@sf.presented_rest)
    f.tap("=重命名")
    f.run_to(@sf.presented_rest)
    f.clear()
    f.type_text("e2e-not-082939")
    // the scrim tapped: the sheet sinks, only drawn; 保存 tapped where it is drawn on its way down takes nothing
    // (near its end, past where the page's rows under it keep what they are pressed at (their card's words' inset), so
    // the taps meet none of them whatever height the rows are drawn)
    let save = f.t.query(@ui.Role::Button, label="保存").map(fn(x) { x.rect }).unwrap_or((0.0, 0.0, 0.0, 0.0))
    let (sx, sy) = (f.measured(save.0 + save.2 - 6.0), f.measured(save.1 + save.3 / 2.0))
    f.tap_at(195.0, 60.0)
    for dy in [0.0, 30.0, 60.0, 90.0] {
      f.tap_at(sx, sy + dy)
    }
    f.run_to(@sf.presented_rest)
    f.gone("station 名称")
    f.see("=willow")
    f.end()
  })
}
