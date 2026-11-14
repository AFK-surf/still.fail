// 51-sheets-sinking (e2e/traces/sheets-sinking.trace): what leaves is only drawn: the workspaces' sheet let go of (its
// scrim tapped), the bar's 文件 tapped under it as it sinks opens 文件; then the chat's own sheet (ⓘ) let go of, and
// the composer tapped through it as it goes down takes the words, sent; nothing of the sheet was tapped on the way (no
// chat.pin asked).

///|
test "51-sheets-sinking" {
  @sfreplay.orders(fn(seed) {
    let f = @sfreplay.Flow::start(@sfreplay.trace("sheets-sinking"), seed~)
    f.see("端到端测试")
    f.tap("=Dev")
    f.run_to(@sf.presented_rest)
    // its scrim tapped: it sinks, only drawn; the bar's 文件 tapped under it as it goes
    f.tap_at(195.0, 120.0)
    f.tap("icon:folder")
    f.see("=文件")
    f.run_to(@sf.presented_rest)
    f.gone("切换 workspace")
    f.tap("icon:chats")
    f.run_for(@ui.move_most_ms)
    f.tap("端到端测试")
    f.run_for(@ui.move_most_ms)
    f.see("发消息")
    f.tap("icon:info")
    f.run_to(@sf.presented_rest)
    // its scrim tapped, and the composer tapped through it as it goes down: the words typed there, sent
    f.tap_at(195.0, 60.0)
    f.tap_at(120.0, -36.0)
    f.type_text("穿过下去的面板 082939")
    f.tap("icon:arrow-up")
    // the words flown to their bubble; the sheet sunk away after
    f.run_for(@sfapp.flight_ms)
    f.run_to(@sf.presented_rest)
    f.see("穿过下去的面板 082939")
    f.gone("正在发送")
    // the test station's agent answers with a failure (no model there), its notice offering 上报: looked for, so the run
    // ends once it is in, as the replay does (else whether its row was built before the end is the run's luck)
    f.see("上报")
    f.end()
  })
}
