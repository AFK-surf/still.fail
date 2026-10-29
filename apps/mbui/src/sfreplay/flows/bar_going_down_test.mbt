// 54-bar-going-down (e2e/traces/bar-going-down.trace): the bar going down under a page pushed is only drawn: the test
// chat opened from Home, the composer tapped where the bar still goes down over it takes the words, sent.

///|
test "54-bar-going-down" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("bar-going-down"), seed~)
    f.see("端到端测试")
    f.tap("端到端测试")
    // halfway into the push (the bar going down with it, as long): the bar still over the composer, tapped there
    f.run_for(@ui.move_most_ms / 2.0)
    f.tap_at(200.0, -38.0)
    // the rest of the push: the page in place, the bar gone
    f.run_for(@ui.move_most_ms / 2.0)
    f.type_text("栏下去时点的 082939")
    f.field("栏下去时点的 082939")
    f.tap("icon:arrow-up")
    f.run_for(@sfapp.flight_ms)
    f.see("栏下去时点的 082939")
    f.gone("正在发送")
    f.end()
  })
}
