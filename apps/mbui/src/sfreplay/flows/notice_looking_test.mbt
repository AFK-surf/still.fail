// 42-notice-looking (e2e/traces/notice-looking.trace): the test chat open while alice's other device asks for a card
// in it: no notice for the chat looked at (the app told the core it shows it, client.focus); the card comes in the
// chat.

///|
test "42-notice-looking" {
  @sfreplay.orders(fn(seed) raise {
    // (whether and when a list is off its end a frame is the run's timing: its client.focus end:false left out)
    let f = @sfreplay.Flow::start(@sfreplay.trace_notice_looking, seed~, drop=["\"end\":false"])
    // the run's list was off its end a moment as the card's rows came (client.focus end: false, then true again once
    // it followed, twice): this one's follows them in the frame they come, its chat at its end throughout
    f.r.drop_but_first("\"end\":true") |> ignore
    f.r.ignore_asks("\"end\":")
    f.tap("端到端测试")
    f.run_for(@ui.nav_push_ms)
    f.see("=studio")
    f.see("发消息")
    f.see_n(2, "这个不该通知 083209")
    f.no_notice("这个不该通知 083209")
    f.back()
    f.run_for(@ui.nav_push_ms)
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
