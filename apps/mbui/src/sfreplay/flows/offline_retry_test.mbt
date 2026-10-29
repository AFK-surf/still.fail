// 12-offline-retry (e2e/traces/offline-retry.trace): the station out of reach (frozen) as a message goes: the core
// says it did not go, 未发送; back in reach, 重试 sends it, and its agent answers.

///|
test "12-offline-retry" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("offline-retry"), seed~)
    f.tap("端到端测试")
    f.run_for(@ui.move_most_ms)
    f.see("=studio")
    f.tap("发消息")
    f.type_text("断网时发出的消息 082947 post:重试后收到 082947")
    // (the station out of reach as it goes, before the app knows it: a live run's step beside the app; once it knows,
    // what is sent waits for it in the outbox, 连上后发出, and goes once it is reached)
    f.peer("freeze")
    f.tap("icon:arrow-up")
    f.run_for(@sfapp.flight_ms)
    f.see("未发送")
    f.peer("thaw")
    f.tap("=重试")
    f.gone("未发送")
    f.gone("正在发送")
    // its agent's answer, its turn over (the run's end after it: nothing of the turn left going)
    f.see("=重试后收到 082947")
    f.end()
  })
}
