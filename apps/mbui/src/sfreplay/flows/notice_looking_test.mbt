// 42-notice-looking (e2e/traces/notice-looking.trace): the test chat open while alice's other device asks for a card
// in it: no notice for the chat looked at (the app told the core it shows it, client.focus); the card comes in the
// chat.

///|
test "42-notice-looking" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("notice-looking"), seed~)
    f.tap("端到端测试")
    f.run_for(@ui.move_most_ms)
    f.see("=studio")
    f.see("发消息")
    // (a live run's step beside the app, the trace has what came of it)
    f.peer("peer send 看着的时候 083209 card:这个不该通知 083209|好 083209|不好 083209")
    f.see_n(2, "这个不该通知 083209")
    f.no_notice("这个不该通知 083209")
    f.back()
    f.run_for(@ui.move_most_ms)
    // the chat forgotten the frame after its slide (client.focus left, chat.place)
    f.t.draw()
    f.core()
    f.see("端到端测试")
    f.no_notice("这个不该通知 083209")
    // the bottom bar at its end
    f.run_to(@sfapp.bar_rest())
    f.end()
  })
}
