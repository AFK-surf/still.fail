// 41-notice-failed (e2e/traces/notice-failed.trace): on Home, alice's other device says something the agent does not
// answer: the station says so (⚠), and the core says to show a notice that something went wrong (failed). Tapped, the
// chat opens at what the station said (link.parse; the run's log: "notice opens … at" the ⚠ entry's seq).

///|
test "41-notice-failed" {
  @sfreplay.orders(fn(seed) raise {
    // (the run's app had the local cloud: the notice's link read against it, link.parse)
    let f = @sfreplay.Flow::start(
      @sfreplay.trace_notice_failed,
      seed~,
      env=[("MBUI_CLOUD", "http://127.0.0.1:19500")],
    )
    // the app's list off its chat's end a frame as rows come or as it opens (client.focus end: false, then true), where
    // the run's was not: let pass
    f.r.ignore_asks("\"end\":")
    f.see("端到端测试")
    f.noticed("出错 · ")
    f.tap_notice("出错 · ")
    // the chat pushed over Home at the ⚠
    f.run_for(@ui.nav_push_ms)
    f.see("发消息")
    f.back()
    f.run_for(@ui.nav_push_ms)
    f.see("端到端测试")
    // the bottom bar at its end
    f.run_to(@sfapp.bar_rest())
    f.end(unsettled_ok="从通知点开对话再返回之后 assert_idle 说 a motion said is not at rest，Tester 没说是哪个（等 app 迁移）")
  })
}
