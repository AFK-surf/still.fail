// 44-notice-cancel (e2e/traces/notice-cancel.trace): a notice shown on Home; the chat then opened from its row, not
// from the notice: its notification goes (App.kt: a chat on top takes its notification off).

///|
test "44-notice-cancel" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace_notice_cancel, seed~)
    f.see("端到端测试")
    f.noticed("看一眼就行 083209")
    f.tap("端到端测试")
    f.run_for(@ui.nav_push_ms)
    f.see_n(2, "看一眼就行 083209")
    f.no_notice("看一眼就行 083209")
    // the bottom bar at its end
    f.run_to(@sfapp.bar_rest())
    f.end()
  })
}
