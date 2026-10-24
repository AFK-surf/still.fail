// 66-wide-resize (e2e/traces/wide-resize.trace: 390 × 844, resized): the window across the breakpoint: a phone's Home
// at 390, the wide frame at 1280 (the list in the sidebar, the chat pressed there beside it), then 390 again: the same
// chat as the phone's page, words sent from it.

///|
test "66-wide-resize" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("wide-resize"), seed~)
    f.see("端到端测试")
    f.resize(1280.0, 800.0)
    f.see("新建对话")
    f.tap("端到端测试")
    f.see("发消息")
    f.resize(390.0, 844.0)
    f.gone("新建对话")
    f.see("发消息")
    f.tap("发消息")
    f.type_text("窗口变窄后发出 082939")
    f.tap("icon:arrow-up")
    f.run_for(@sfapp.flight_ms)
    f.see("窗口变窄后发出 082939")
    f.gone("正在发送")
    // the bottom bar's own motion (gone under the page pushed, its ball) to its declared end
    f.run_to(@sfapp.bar_rest())
    f.end()
  })
}
