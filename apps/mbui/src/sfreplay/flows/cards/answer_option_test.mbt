// 22-answer-option (e2e/traces/answer-option.trace: Studio against the local still.fail): the agent asks with an
// options card (e2e/fake/claude.mjs `card:`), its options under its words, the recommended one marked; one tapped
// answers it (decision.answer: the viewer's message quoting the post), the card saying how it went.

///|
test "22-answer-option" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("answer-option"), seed~)
    f.tap("端到端测试")
    // the chat pushed over Home: in place once its push is over
    f.run_for(@ui.nav_push_ms)
    f.see("=studio")
    f.tap("发消息")
    f.type_text("给我几个选项 083209 card:要不要换图标 083209|先不换 083209|一起换 083209*|不用了 083209!")
    f.tap("icon:arrow-up")
    // the words flown to their bubble
    f.run_for(@sfapp.flight_ms)
    f.gone("正在发送")
    f.see("=一起换 083209")
    f.tap("=一起换 083209")
    f.see("选择了")
    // the options gone, 你 选择了「…」 in their place: their motions (from the chat's change saying the card decided,
    // which may come after the message quoting it) to their end, in a scripted run too (the list back at its end as
    // the room closes, told to the core)
    f.until_moving("under-look/options/") |> ignore
    f.run_to(@sfapp.under_rest())
    f.gone("=先不换 083209")
    // the answer handed to the agent, its turn on it to its end (the fake's own posts nothing: the station says so),
    // the chat's mark at work gone with it
    f.see("本轮 agent 未在对话中回复")
    f.end()
  })
}
