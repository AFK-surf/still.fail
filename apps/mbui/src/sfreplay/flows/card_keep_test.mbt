// 71-card-keep (e2e/traces/card-keep.trace): 保留 under the agent's last all-done post (Chat.kt ArchiveUnder): the chat
// kept (chat.keep, 已保留… said); the two buttons go (280 ms, ArchiveEase) and the bar's 归档 with them.

///|
test "71-card-keep" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace_card_keep, seed~)
    f.see("保留用的对话 083209")
    f.see("这件事也做完了 083209")
    f.tap("保留用的对话 083209")
    f.run_for(@ui.nav_push_ms)
    f.see("归档此对话")
    f.see("icon:archive")
    f.tap("=保留")
    f.see("已保留")
    f.gone("=归档此对话")
    f.gone("icon:archive")
    // the buttons gone, their room closed; 已保留 said for its time
    f.run_to(@sfapp.under_rest())
    f.run_for(@sfapp.toast_rest_ms)
    f.end()
  })
}
