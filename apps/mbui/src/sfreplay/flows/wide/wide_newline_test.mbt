// 61-wide-newline (e2e/traces/wide-newline.trace: 1280 × 800): in the wide frame ⇧Enter is a new line in the composer
// and Enter sends both lines as one message.

///|
test "61-wide-newline" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace_wide_newline, seed~, w=1280.0, h=800.0)
    f.tap("端到端测试")
    f.see("按空格输入")
    f.tap("按空格输入")
    f.type_text("第一行 082939")
    f.key("shift+enter")
    f.type_text("第二行 082939")
    f.field("第一行 082939\n第二行 082939")
    f.enter()
    f.run_for(@sfapp.flight_ms)
    f.see("第二行 082939")
    f.gone("正在发送")
    f.end()
  })
}
