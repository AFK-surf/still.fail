// 70-card-motion (e2e/traces/card-motion.trace): an options card answered in the chat: on screen it stays as it is,
// the one picked marked, none pressed any more, nothing under the post going or coming; then another card let go
// with 忽略, which fades where it is (280 ms, ArchiveEase), its room kept (sfbase's list_turns.mbt Turns::in_turn:
// what is answered goes only out of sight).

///|
test "70-card-motion" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("card-motion"), seed~)
    f.tap("端到端测试")
    f.run_for(@ui.move_most_ms)
    f.see("=studio")
    f.tap("发消息")
    f.type_text("选一个颜色 083209 card:按钮用什么颜色 083209|橙色 083209*|灰色 083209")
    f.tap("icon:arrow-up")
    f.run_for(@sfapp.flight_ms)
    f.gone("正在发送")
    f.see("=灰色 083209")
    f.tap_now("=橙色 083209") |> ignore
    f.answered("decision.answer", 1)
    // answered on screen (decision.answer): its options close as the answer comes in, one move (docs/list-motion.md)
    f.gone("=灰色 083209")
    f.tap("发消息")
    f.type_text("再选一个 083209 card:先做哪一页 083209|首页 083209|设置页 083209")
    // the words in the field long enough to be kept as the chat's draft, as the run's were (draft.put)
    f.run_for(@sfapp.draft_keep_ms)
    f.tap("icon:arrow-up")
    f.run_for(@sfapp.flight_ms)
    f.gone("正在发送")
    f.see("=设置页 083209")
    // (the list come to its end after the card, its 忽略 in view under it: at a quicker pace it is still gliding there)
    let glide = f.t.rest_of("a list gliding")
    if glide > f.t.time() {
      f.run_to(glide)
    }
    f.see("=忽略")
    f.tap_now("=忽略") |> ignore
    f.answered("decision.dismiss", 1)
    // let go on screen (decision.dismiss): 忽略 and the card's options close (docs/list-motion.md)
    f.run_for(@sfapp.archive_ms)
    f.gone("=忽略")
    f.gone("=设置页 083209")
    let closing = @sfapp.under_rest()
    if closing > f.t.time() {
      f.run_to(closing)
    }
    f.check(f.t.rest_of("under/") < 0.0, "something under the post moves till \{f.t.rest_of("under/")}")
    f.end()
  })
}
