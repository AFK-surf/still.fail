// 36-archive-restore (e2e/traces/archive-restore.trace): a chat archived by alice's other device (chat.archive) leaves
// Home; Home's filter → 已归档: it is there, by day. Restored from its row (还原): it leaves the archive.

///|
test "36-archive-restore" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("archive-restore"), seed~)
    f.see("端到端测试")
    // (a live run's step beside the app, the trace has what came of it)
    f.peer("peer archive 要归档的对话 083209 post:归档前的回复 083209")
    f.gone("要归档的对话 083209")
    f.tap("icon:filter")
    f.see("=已归档")
    f.tap("=已归档")
    // the archive pushed over Home
    f.run_for(@ui.move_most_ms)
    f.see("要归档的对话 083209")
    f.see("归档前的回复 083209")
    f.tap("icon:retry", top=true)
    f.gone("要归档的对话 083209")
    f.see("已恢复到列表")
    let shown = f.t.time()
    // the bottom bar at its end
    f.run_to(@sfapp.bar_rest())
    // 已恢复到列表 said for its time (counted from the frame after it showed: @kit.toaster's `after(later=true)`), then
    // gone
    f.run_for(@sfapp.toast_ms + @sfreplay.frame_ms - (f.t.time() - shown))
    f.run_to_rest("toast")
    f.end()
  })
}
