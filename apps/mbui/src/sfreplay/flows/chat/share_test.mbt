// 48-share (e2e/traces/share.trace: Mini1 against the local still.fail, 82 messages): sharing in and out
// (ShareActivity.kt, ShareSheet.kt; DriveScreen.kt's 分享). A link shared in from another app's share sheet opens the
// sheet of chats (发到, shareIn.open); the test chat tapped: the link a card in its composer, sent as its words (its
// title, then the link). Then a file of the drive held, ⋯ → 分享: read through the core (drive.read) and handed to the
// system's share sheet (@ui.share).

///|
test "48-share" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace_share, seed~)
    f.share_in("https://www.youtube.com/watch?v=e2e105609", title="列表视频105609")
    // the sheet of chats raised
    f.run_to(@kit.sheet_rest("sheet"))
    f.see("发到")
    f.see("列表视频105609")
    f.see("新 chat")
    f.tap("端到端测试")
    // the sheet going down as the chat comes up: the sheet's the later
    f.run_to(@kit.sheet_rest("sheet"))
    f.see("youtube.com")
    f.tap("icon:arrow-up")
    f.run_for(@sfapp.flight_ms)
    f.gone("正在发送")
    f.see("列表视频105609")
    f.back()
    f.run_to(@ui.nav_rest())
    f.see("端到端测试")
    f.tap("icon:folder")
    f.see("=文件")
    // the notch's icon swapping to 文件's ＋
    f.run_for(@sfapp.icon_swap_ms)
    f.tap("=e2e-105609")
    f.run_to(@ui.nav_rest())
    f.hold("说明.txt", @ui.long_press_ms)
    f.see("已选 1 项")
    f.tap("icon:more")
    f.run_to(@kit.sheet_rest("dv-sheet"))
    f.tap("分享")
    f.run_to(@kit.sheet_rest("dv-sheet"))
    // the file, read through the core, handed to the system's share sheet as it is
    let shared = f.t.shared_out()
    assert_eq(shared.length(), 1)
    assert_eq(shared[0].1, "说明.txt")
    // the bottom bar's springs and tweens to their declared end
    f.run_to(@sfapp.bar_rest())
    f.end()
  })
}
