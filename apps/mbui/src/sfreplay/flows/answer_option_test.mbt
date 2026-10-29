// 22-answer-option (e2e/traces/answer-option.trace: Studio against the local still.fail): the agent asks with an
// options card (e2e/fake/claude.mjs `card:`), its options under its words, the recommended one marked; one tapped
// answers it (decision.answer: the viewer's message quoting the post), its options closing on screen to how it went
// as the answer comes in (cards_wbtest.mbt).

///|
test "22-answer-option" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("answer-option"), seed~)
    f.tap("端到端测试")
    // the chat pushed over Home: in place once its push is over
    f.run_for(@ui.move_most_ms)
    f.see("=studio")
    f.tap("发消息")
    f.type_text("给我几个选项 083209 card:要不要换图标 083209|先不换 083209|一起换 083209*|不用了 083209!")
    f.tap("icon:arrow-up")
    // the words flown to their bubble
    f.run_for(@sfapp.flight_ms)
    f.gone("正在发送")
    f.see("=一起换 083209")
    f.tap("=一起换 083209")
    f.answered("decision.answer", 1)
    // the answer handed to the agent, its turn on it to its end (the fake's own posts nothing: the station says so),
    // the chat's mark at work gone with it
    f.see("本轮 agent 未在对话中回复")
    // the card decided long since: its options closed as the answer came (docs/list-motion.md), nothing under the
    // post going or coming
    f.gone("=先不换 083209")
    // (closed as the core said it decided: to its end)
    let closing = @sfapp.under_rest()
    if closing > f.t.time() {
      f.run_to(closing)
    }
    f.check(@sfapp.under_rest() < 0.0, "something under the post moves: \{@sfapp.under_rest()}")
    f.end()
  })
}
