// 04-chinese-enter (e2e/traces/chinese-enter.trace): Chinese through the input method (composed, then committed),
// ⇧Enter a new line, not a send (recorded with keyboard and mouse, where Enter sends: a phone's Enter, a new line, is the unit
// tests', composer_wbtest.mbt); both lines sent as one message.

///|
test "04-chinese-enter" {
  @sfreplay.orders(fn(seed) raise {
    // (the run's first flow: its app gave the core the account it was started with, migrate)
    let f = @sfreplay.Flow::start(@sfreplay.trace("chinese-enter"), seed~)
    f.tap("端到端测试")
    f.run_for(@ui.move_most_ms)
    f.see("=studio")
    f.tap("发消息")
    f.compose("ni'hao")
    f.type_text("你好")
    f.key("shift+enter")
    f.compose("di'er'hang")
    f.type_text("第二行 085022")
    // ⇧Enter sent nothing: both lines in the field
    f.field("你好\n第二行 085022")
    f.tap("icon:arrow-up")
    f.run_for(@sfapp.flight_ms)
    f.see("第二行 085022")
    f.gone("正在发送")
    f.end()
  })
}
