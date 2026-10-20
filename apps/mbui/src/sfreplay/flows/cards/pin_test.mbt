// 27-pin (e2e/traces/pin.trace): the chat's own sheet ("…"): pinned to the top of the list and let go again (chat.pin;
// the run's check read the station's pins after each: 1, then 0).

///|
test "27-pin" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace_pin, seed~)
    f.tap("端到端测试")
    f.run_for(@ui.nav_push_ms)
    f.see("=studio")
    f.see("发消息")
    f.tap("icon:more")
    // the chat's sheet risen
    f.run_to(@kit.sheet_rest("decide-sheet"))
    f.see("=固定到列表顶部")
    f.tap("=固定到列表顶部")
    f.see("=取消固定")
    f.tap("=取消固定")
    f.see("=固定到列表顶部")
    // the sheet at its height again
    f.run_to(@kit.sheet_rest("decide-sheet"))
    // the bottom bar at its end
    f.run_to(@sfapp.bar_rest())
    // the test chat ended all done: 保留 and 归档此对话 come under its last post meanwhile
    f.run_to(@sfapp.under_rest())
    f.end()
  })
}
