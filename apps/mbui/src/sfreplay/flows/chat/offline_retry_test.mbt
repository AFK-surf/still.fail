// 12-offline-retry (e2e/traces/offline-retry.trace): the station out of reach (frozen) as a message goes: the core
// says it did not go, 未发送; back in reach, 重试 sends it.

///|
test "12-offline-retry" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace_offline_retry, seed~)
    f.tap("端到端测试")
    f.run_for(@ui.nav_push_ms)
    f.see("=studio")
    // (the station out of reach, then back: a live run's steps beside the app, scripts/e2e-local.sh)
    f.peer("freeze")
    f.tap("发消息")
    f.type_text("断网时发出的消息 082947")
    f.tap("icon:arrow-up")
    f.run_for(@sfapp.flight_ms)
    f.see("未发送")
    f.peer("thaw")
    f.tap("=重试")
    f.gone("未发送")
    f.gone("正在发送")
    // the agent's activity row opening as its turn runs on: to its end, as it set out (its clock comes again each
    // second for as long as it shows: Ctx::every, not waited for)
    f.run_to(f.t.rest_of("open/"))
    f.end()
  })
}
