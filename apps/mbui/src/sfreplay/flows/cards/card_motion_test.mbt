// 70-card-motion (e2e/traces/card-motion.trace): an options card answered in the chat as the Android app shows it
// (Decisions.kt DecisionUnder): the option tapped, the options and 忽略 go and 你 选择了「…」 comes in their place; then
// another card let go with 忽略 (280 ms, ArchiveEase, its room closing). The motions as the run's motion log had them:
// the options fading to 90% and their room closing on the rows' spring after, the line's room opening; 忽略 to 85%.

///|
test "70-card-motion" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("card-motion"), seed~)
    f.tap("端到端测试")
    f.run_for(@ui.nav_push_ms)
    f.see("=studio")
    f.tap("发消息")
    f.type_text("选一个颜色 083209 card:按钮用什么颜色 083209|橙色 083209*|灰色 083209")
    f.tap("icon:arrow-up")
    f.run_for(@sfapp.flight_ms)
    f.gone("正在发送")
    f.see("=灰色 083209")
    f.tap_now("=橙色 083209") |> ignore
    // answered (decision.answer): the options fade and shrink to 90% on their 200 ms from the frame that took the
    // chat's change saying the card decided (its `chosen`: messages.mbt's `resolved`), their room closing on the rows'
    // spring after them; how it went comes in their place, its room opening
    // (the change can come with the tap's own frame, from a station that answers at once: its motion said there)
    if !f.t.moving().iter().any(fn(l) { l.contains("under-look/options/") }) {
      f.until_moving("under-look/options/") |> ignore
    }
    let from = f.message_taken(fn(m) { m.stringify().contains("\"chosen\"") })
    // (checks: while a script is written over a trace the app has outgrown, said and the steps after written all the
    // same)
    f.check(
      f.t.rest_of("under-look/options/") == from + @sfapp.options_out_ms,
      "the options at rest at \{f.t.rest_of("under-look/options/")}, not \{from + @sfapp.options_out_ms}",
    )
    f.check(f.t.rest_of("under/options/") > from + @sfapp.options_out_ms, "their room closes after them")
    f.check(f.t.rest_of("under/outcome/") > from, "how it went comes in their place")
    // (their shrinking to 90% not checked here: Tester::look_of by words takes the first node holding them, and the
    // message sent, card: and all, holds the option's words before the option does)
    f.run_to(@sfapp.under_rest())
    f.see("选择了「橙色 083209」")
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
    let after = f.tap_now("=忽略")
    // let go (decision.dismiss): 忽略 goes from the frame after the one that took the tap (decide.mbt ask_dismiss), on
    // ArchiveEase's 280 ms, to 85% from its top left, its room closing
    let end = f.until_moving("under/dismiss/")
    f.check(end == after + @sfapp.archive_ms, "忽略 at rest at \{end}, not \{after + @sfapp.archive_ms}")
    f.gone("=忽略")
    // to 85% on ArchiveEase, its room closing with it: gone at rest (while a script is written over a trace the app
    // has outgrown, no motion to check: said above, the steps after written all the same)
    if end >= 0.0 {
      f.shrinks("忽略", to=@sfapp.archive_scale, ease=@sfapp.archive_ease, ms=@sfapp.archive_ms, rest=end)
    }
    // the card's options going with it, their room closing on the rows' spring after
    f.run_to_rest("under/")
    f.gone("=设置页 083209")
    f.end()
  })
}
