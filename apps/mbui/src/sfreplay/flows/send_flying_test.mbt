// 39-send-flying (e2e/traces/send-flying.trace): two messages sent back to back, the second while the first's words
// still fly to their bubble: both land in their own bubbles, in order, each once; the composer empty after.

///|
test "39-send-flying" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("send-flying"), seed~)
    f.tap("端到端测试")
    f.run_for(@ui.move_most_ms)
    f.see("=studio")
    f.tap("发消息")
    f.type_text("先飞的一条 082947")
    f.tap("icon:arrow-up")
    // (no time on: the first still flies)
    f.type_text("紧跟着的一条 082947")
    f.tap("icon:arrow-up")
    f.run_for(@sfapp.flight_ms)
    f.see("先飞的一条 082947")
    f.see("紧跟着的一条 082947")
    f.gone("正在发送")
    f.field("")
    f.end()
  })
}
