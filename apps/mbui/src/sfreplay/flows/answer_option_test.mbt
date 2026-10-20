// 22-answer-option (e2e/traces/answer-option.trace: Studio against the local still.fail): the agent asks with an
// options card (e2e/fake/claude.mjs `card:`), its options under its words, the recommended one marked; one tapped
// answers it (decision.answer: the viewer's message quoting the post), the card saying how it went.

///|
test "22-answer-option" {
  @sfreplay.orders(fn(seed) raise {
    // (the run's first: its core was given the run's account then, `migrate`, as a Tester's is not)
    let f = @sfreplay.Flow::start(@sfreplay.trace_answer_option, seed~, skip=["client.device", "migrate"])
    // the app's list off its chat's end a frame as rows come or as it opens (client.focus end: false, then true), where
    // the run's was not: let pass
    f.r.ignore_asks("\"end\":")
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
    f.gone("=先不换 083209")
    // the options gone, 你 选择了「…」 in their place
    f.run_to(@sfapp.under_rest())
    f.end()
  })
}
