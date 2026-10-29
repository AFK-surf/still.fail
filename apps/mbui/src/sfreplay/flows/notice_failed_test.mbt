// 41-notice-failed (e2e/traces/notice-failed.trace): on Home, alice's other device says something the agent does not
// answer: the station says so (⚠), and the core says to show a notice that something went wrong (failed). Tapped, the
// chat opens at what the station said (link.parse; the run's log: "notice opens … at" the ⚠ entry's seq).

///|
test "41-notice-failed" {
  @sfreplay.orders(fn(seed) raise {
    // (the run's app had the local cloud, its trace's env says which: the notice's link read against it, link.parse)
    let f = @sfreplay.Flow::start(@sfreplay.trace("notice-failed"), seed~)
    f.see("端到端测试")
    // (a live run's step beside the app, the trace has what came of it)
    f.peer("peer send 这一条不会有回复 083209")
    f.noticed("出错 · ")
    f.tap_notice("出错 · ")
    // the chat pushed over Home at the ⚠
    f.run_for(@ui.move_most_ms)
    f.see("发消息")
    // the ⚠ gone to flashes, all of its way
    f.run_to(@sfapp.flash_rest())
    f.back()
    f.run_for(@ui.move_most_ms)
    f.see("端到端测试")
    // the bottom bar at its end
    f.run_to(@sfapp.bar_rest())
    f.end()
  })
}
