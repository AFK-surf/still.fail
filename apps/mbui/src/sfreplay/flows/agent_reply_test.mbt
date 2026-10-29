// 05-agent-reply (e2e/traces/agent-reply.trace: Studio against the local still.fail, 50 messages): words sent in the
// open chat, the agent's answer coming in and the list following its end to show it.

///|
test "05-agent-reply" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("agent-reply"), seed~)
    f.tap("端到端测试")
    // the chat pushed over Home: in place once its push is over
    f.run_for(@ui.move_most_ms)
    f.see("=studio")
    f.tap("发消息")
    f.type_text("请回答一句 064618 post:收到，这是 agent 的回复 064618")
    f.tap("icon:arrow-up")
    // the words flown to their bubble
    f.run_for(@sfapp.flight_ms)
    f.gone("正在发送")
    f.see_n(2, "收到，这是 agent 的回复 064618")
    assert_true(f.t.at_end())
    f.end()
  })
}
