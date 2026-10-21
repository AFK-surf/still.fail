// 60-wide-send (e2e/traces/wide-send.trace: a 1280 × 800 window against the local still.fail): the wide frame (a
// desktop's window, src/sfapp/wide.mbt); the test chat pressed in the sidebar's list opens beside it; words typed in its
// composer go with Enter, as the web's do; the bubble, then sent.

///|
test "60-wide-send" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace_wide_send, seed~, w=1280.0, h=800.0)
    f.see("新建对话")
    f.tap("端到端测试")
    f.see("按空格输入")
    f.tap("按空格输入")
    f.type_text("宽屏里发出的消息 082939")
    f.enter()
    // the words flown to their bubble
    f.run_for(@sfapp.flight_ms)
    f.see("宽屏里发出的消息 082939")
    f.gone("正在发送")
    f.end()
  })
}
