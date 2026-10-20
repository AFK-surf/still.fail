// 13-delete-failed (e2e/traces/delete-failed.trace): a message that did not go (the station frozen), deleted (删除):
// gone from the chat, and never sent again.

///|
test "13-delete-failed" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace_delete_failed, seed~)
    f.tap("端到端测试")
    f.run_for(@ui.nav_push_ms)
    f.see("=studio")
    f.tap("发消息")
    f.type_text("这条没发出去就删掉 082947")
    // (the station out of reach as it goes, before the app knows it: a live run's step beside the app; once it knows,
    // the composer is locked, Composer.kt's `locked = offline || archived`)
    f.peer("freeze")
    f.tap("icon:arrow-up")
    f.run_for(@sfapp.flight_ms)
    f.see("未发送")
    f.tap("=删除")
    f.gone("这条没发出去就删掉 082947")
    f.peer("thaw")
    // its row's copy fades where it was: to its end, as it set out (mbui's "<key> leaving")
    f.run_to(f.t.rest_of(" leaving"))
    f.end()
  })
}
