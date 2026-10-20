// 70-card-motion (e2e/traces/card-motion.trace): an options card answered in the chat as the Android app shows it
// (Decisions.kt DecisionUnder): the option tapped, the options and 忽略 go and 你 选择了「…」 comes in their place; then
// another card let go with 忽略 (280 ms, ArchiveEase, its room closing).

///|
test "70-card-motion" {
  @sfreplay.orders(fn(seed) raise {
    // (whether and when a list is off its end a frame is the run's timing: its client.focus end:false left out)
    let f = @sfreplay.Flow::start(@sfreplay.trace_card_motion, seed~, drop=["\"end\":false"])
    // the run's list was off its end a moment as the chat opened and as the answer's rows came (client.focus end: false,
    // then true again once it followed): this one's follows them in the frame they come; its own such asks let pass
    f.r.drop_but_first("\"end\":true") |> ignore
    f.r.ignore_asks("\"end\":")
    f.tap("端到端测试")
    f.run_for(@ui.nav_push_ms)
    f.see("=studio")
    f.tap("发消息")
    f.type_text("选一个颜色 083209 card:按钮用什么颜色 083209|橙色 083209*|灰色 083209")
    f.tap("icon:arrow-up")
    f.run_for(@sfapp.flight_ms)
    f.gone("正在发送")
    f.see("=灰色 083209")
    f.tap("=橙色 083209")
    f.see("选择了「橙色 083209」")
    f.gone("=灰色 083209")
    // the options gone, the line in their place
    f.run_to(@sfapp.under_rest())
    f.tap("发消息")
    f.type_text("再选一个 083209 card:先做哪一页 083209|首页 083209|设置页 083209")
    // the words in the field long enough to be kept as the chat's draft, as the run's were (draft.put)
    f.run_for(@sfapp.draft_keep_ms)
    f.tap("icon:arrow-up")
    f.run_for(@sfapp.flight_ms)
    f.gone("正在发送")
    f.see("=设置页 083209")
    f.tap("=忽略")
    f.gone("=忽略")
    f.gone("=设置页 083209")
    f.run_to(@sfapp.under_rest())
    f.end()
  })
}
