// 44-notice-cancel (e2e/traces/notice-cancel.trace): a notice shown on Home; the chat then opened from its row, not
// from the notice: its notification goes (App.kt: a chat on top takes its notification off).

///|
test "44-notice-cancel" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("notice-cancel"), seed~)
    f.see("端到端测试")
    // (a live run's step beside the app, the trace has what came of it)
    f.peer("peer send 打开就消失 083209 card:看一眼就行 083209|好 083209|不好 083209")
    f.noticed("看一眼就行 083209")
    f.tap("端到端测试")
    f.run_for(@ui.move_most_ms)
    f.see_n(2, "看一眼就行 083209")
    f.no_notice("看一眼就行 083209")
    // the bottom bar at its end
    f.run_to(@sfapp.bar_rest())
    f.end()
  })
}
