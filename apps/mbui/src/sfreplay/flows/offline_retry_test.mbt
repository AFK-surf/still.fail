// 12-offline-retry (e2e/traces/offline-retry.trace): the station out of reach (frozen) as a message goes: the core
// says it did not go, 未发送; back in reach, 重试 sends it.

///|
test "12-offline-retry" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace_offline_retry, seed~)
    f.tap("端到端测试")
    f.run_for(@ui.nav_push_ms)
    f.see("=studio")
    f.tap("发消息")
    f.type_text("断网时发出的消息 082947")
    f.tap("icon:arrow-up")
    f.run_for(@sfapp.flight_ms)
    f.see("未发送")
    f.tap("=重试")
    f.gone("未发送")
    f.gone("正在发送")
    f.end(unsettled_ok="a motion said is not at rest（重试那条之后 agent 这一轮录到结尾还在跑）；sfapp/messages.mbt:1583 运行时长每秒一个 wake（等 app 迁移）")
  })
}
