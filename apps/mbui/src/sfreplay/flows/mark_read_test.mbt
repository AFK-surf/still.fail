// 14-mark-read (e2e/traces/mark-read.trace): on Home, alice's other device asks the agent something; its answer
// comes unread; the chat opened, the app tells the core it is read at its end (client.focus, end: true).

///|
test "14-mark-read" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("mark-read"), seed~)
    f.see("端到端测试")
    // (alice's other device asks: a live run's step beside the app)
    f.peer("peer send 再问一次 post:这一条应当显示为未读 082947")
    f.see("=这一条应当显示为未读 082947")
    f.tap("=这一条应当显示为未读 082947")
    f.run_for(@ui.move_most_ms)
    f.see_n(2, "这一条应当显示为未读 082947")
    assert_true(f.t.at_end())
    f.tap("icon:chevron-left")
    f.run_for(@ui.move_most_ms)
    // the page popped is let go at the frame after its slide (the core told it is left then)
    f.t.draw()
    f.core()
    f.see("端到端测试")
    // the bar moved by what this did (the field focused, the chat left) at rest
    f.run_to(@sfapp.bar_rest())
    f.end()
  })
}
