// 24-close-option (e2e/traces/close-option.trace): an option the agent made to close the card (action=close) ends the
// wait without a message (decision.answer, its option closing it): the card stays as it is on screen, none pressed any
// more (how it went is its line once out of sight: cards_wbtest.mbt).

///|
test "24-close-option" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("close-option"), seed~)
    f.tap("端到端测试")
    f.run_for(@ui.move_most_ms)
    f.see("=studio")
    f.tap("发消息")
    f.type_text("部署吗 083209 card:要不要部署 083209|现在部署 083209*|不需要部署 083209!")
    f.tap("icon:arrow-up")
    f.run_for(@sfapp.flight_ms)
    f.gone("正在发送")
    f.see("=不需要部署 083209")
    f.tap("=不需要部署 083209")
    f.answered("decision.answer", 1)
    f.see("=不需要部署 083209")
    f.check(@sfapp.under_rest() < 0.0, "something under the post moves: \{@sfapp.under_rest()}")
    f.end()
  })
}
