// 64-wide-new-chat (e2e/traces/wide-new-chat.trace: 1280 × 800): ⌘N: a new chat beside the list (新建对话 lit); its
// first words sent with Enter make the chat on the station and the page becomes it; its agent answers there; its row
// comes into the list.

///|
test "64-wide-new-chat" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace_wide_new_chat, seed~, w=1280.0, h=800.0)
    f.see("新建对话")
    f.key("cmd+n")
    f.see("想让 agent 做什么？")
    f.tap("做任何事")
    f.type_text("宽屏新对话 085912 post:宽屏新对话的回答 085912")
    f.enter()
    f.run_for(@sfapp.flight_ms)
    f.see("宽屏新对话 085912")
    f.gone("想让 agent 做什么？")
    // its agent's answer in the chat
    f.see("=宽屏新对话的回答 085912")
    // the agent's avatar lingering after its turn ended: once its answer is out of it and it is home again, there a
    // moment, then faded and gone
    f.run_for(@sfapp.emit_out_ms + @sfapp.linger_ms)
    f.end()
  })
}
