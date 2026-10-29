// 27-pin (e2e/traces/pin.trace): the chat's own sheet ("…"): pinned to the top of the list and let go again (chat.pin;
// the run's check read the station's pins after each: 1, then 0).

///|
test "27-pin" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("pin"), seed~)
    f.tap("端到端测试")
    f.run_for(@ui.move_most_ms)
    f.see("=studio")
    f.see("发消息")
    f.tap("icon:more")
    // the chat's sheet risen
    f.run_to(@kit.sheet_rest("sf-present"))
    f.see("=固定到列表顶部")
    f.tap("=固定到列表顶部")
    f.see("=取消固定")
    f.tap("=取消固定")
    f.see("=固定到列表顶部")
    // the sheet at its height again
    f.run_to(@kit.sheet_rest("sf-present"))
    // the bottom bar at its end
    f.run_to(@sfapp.bar_rest())
    // the test chat ended all done: the bar's 归档 comes in meanwhile, to the end it sets out
    let rest = f.t.rest_of("bar-archive/")
    if rest > f.t.time() {
      f.run_to(rest)
    }
    f.end()
  })
}
