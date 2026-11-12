// 48-share (e2e/traces/share.trace: a local still.fail, 82 messages): sharing in and out
// (a drive's file's 分享). A link shared in from another app's share sheet opens the
// sheet of chats (发到, shareIn.open); the test chat tapped: the link a card in its composer, sent as its words (its
// title, then the link). Then a file of the drive right clicked, 分享: read through the core (drive.read) and handed to the
// system's share sheet (@ui.share).
// (its folder lent first: e2e/flows/15-drive-lend)
// before it: 15-drive-lend

///|
test "48-share" {
  @sfreplay.orders(fn(seed) {
    let f = @sfreplay.Flow::start(@sfreplay.trace("share"), seed~)
    f.share_in("https://www.youtube.com/watch?v=e2e105609", title="列表视频105609")
    // the sheet of chats raised
    f.run_to(@sf.presented_rest)
    f.see("发到")
    f.see("列表视频105609")
    f.see("新建对话")
    f.tap("端到端测试")
    // the sheet going down as the chat comes up: the sheet's the later
    f.run_to(@sf.presented_rest)
    f.see("youtube.com")
    f.tap("icon:arrow-up")
    f.run_for(@sfapp.flight_ms)
    f.gone("正在发送")
    f.see("列表视频105609")
    f.back()
    f.run_to(@ui.nav_rest)
    f.see("端到端测试")
    f.tap("icon:folder")
    f.see("=文件")
    // the notch's icon swapping to 文件's ＋
    f.run_for(@sfapp.icon_swap_ms)
    f.tap("=e2e-105609")
    f.run_to(@ui.nav_rest)
    f.right_click("说明.txt")
    f.run_for(@kit.presence_in_ms)
    f.tap("分享")
    f.run_for(@kit.presence_out_ms)
    // the file, read through the core, handed to the system's share sheet as it is
    f.until(fn() { f.t.shared_out().length() > 0 })
    let shared = f.t.shared_out()
    f.check(shared.length() == 1, "the share sheet was not given exactly one file")
    f.check(shared.iter().any(fn(item) { item.1 == "说明.txt" }), "the share sheet was not given 说明.txt")
    // the bottom bar's springs and tweens to their declared end
    f.run_to(@sfapp.bar_rest)
    f.end()
  })
}
