// 03-send-text (e2e/traces/send-text.trace: Studio against the local still.fail, 54 messages): a chat opened from
// Home, words typed and sent; the bubble, then sent.

///|
test "03-send-text" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace_send_text, seed~)
    f.tap("端到端测试")
    // the chat pushed over Home: in place once its push is over
    f.run_for(@ui.nav_push_ms)
    f.see("=studio")
    f.tap("发消息")
    f.type_text("第一条来自 mbui 的消息 053246")
    f.tap("icon:arrow-up")
    // the words flown to their bubble
    f.run_for(@sfapp.flight_ms)
    f.see("第一条来自 mbui 的消息 053246")
    f.gone("正在发送")
    // after the station's two rows came (the message, the agent's turn) the run's app told the core the chat was off
    // its end (client.focus end: false): its list had not followed them yet, this one's has
    f.end(unmade=["\"end\":false"])
  })
}
