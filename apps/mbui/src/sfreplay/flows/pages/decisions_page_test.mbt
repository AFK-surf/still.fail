// 28-decisions-page (e2e/traces/decisions-page.trace): the 奏 page (MBUI_OPEN_PAGE=decisions, opened at the start):
// the card alice's other device asked for, the chat's title over the post and its options; one tapped answers it
// (decision.answer) and the page says none are left.

///|
test "28-decisions-page" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace_decisions_page, seed~)
    // the 奏 page over Home from the start, as MBUI_OPEN_PAGE=decisions opened it
    f.open_page(@sfapp.Page::Decisions)
    // (a live run's step beside the app, the trace has what came of it)
    f.peer("peer send 还有一个问题 085454 card:发布到哪里 085454|测试版 085454*|正式版 085454")
    f.see("=测试版 085454")
    f.tap("=测试版 085454")
    // answered at once (decision.answer): the card up and away
    f.t.draw()
    f.run_to(@sfapp.deck_rest())
    f.see("奏折已全部批完")
    f.end()
  })
}
