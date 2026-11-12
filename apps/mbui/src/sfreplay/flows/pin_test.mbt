// 27-pin (e2e/traces/pin.trace): the chat's "…" menu: pinned to the top of the list and let go again (chat.pin;
// the run's check read the station's pins after each: 1, then 0).

///|
test "27-pin" {
  @sfreplay.orders(fn(seed) {
    // (the run's list of chats, under the chat, let go of the rows under the block that came as the chat was pinned
    // (已固定) and made them again, their watch of `doing` let go of and asked again with them: a block that comes
    // now leaves the rows that show as they are (mbui's list_window.mbt), and the watch goes on)
    let f = @sfreplay.Flow::start(@sfreplay.trace("pin"), seed~, drop=[
      "{\"id\":11,\"unsubscribe\":true}", "{\"id\":47,\"subscribe\":{\"topic\":\"doing\"}",
    ])
    f.tap("端到端测试")
    f.run_for(@ui.move_most_ms)
    f.see("=willow")
    f.see("发消息")
    f.tap("icon:more")
    // the chat's menu risen: 固定 chosen, it goes
    f.run_to(@sf.presented_rest)
    f.see("=固定")
    f.tap("=固定")
    f.run_to(@sf.presented_rest)
    // opened again, it says 取消固定 now
    f.tap("icon:more")
    f.run_to(@sf.presented_rest)
    f.see("=取消固定")
    f.tap("=取消固定")
    f.run_to(@sf.presented_rest)
    // the bottom bar at its end
    f.run_to(@sfapp.bar_rest)
    // the test chat ended all done: the bar's 归档 comes in meanwhile, to the end it sets out
    let rest = f.t.rest_of("bar-archive/")
    if rest > f.t.time() {
      f.run_to(fn() { rest })
    }
    f.end()
  })
}
