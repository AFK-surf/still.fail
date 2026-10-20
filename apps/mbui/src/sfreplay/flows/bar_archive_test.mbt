// 72-bar-archive (e2e/traces/bar-archive.trace): the chat's bar's 归档 (Chat.kt ChatBar, shown while nothing is left in
// the chat): Home at once, 已归档 said, the chat gone from the list (chat.archive).

///|
test "72-bar-archive" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace_bar_archive, seed~)
    f.see("从栏上归档 085454")
    f.see("都弄好了 085454")
    f.tap("从栏上归档 085454")
    f.run_for(@ui.nav_push_ms)
    f.see("icon:archive")
    f.tap("icon:archive")
    // Home again, the chat popped
    f.run_for(@ui.nav_push_ms)
    f.see("=已归档")
    f.gone("从栏上归档 085454")
    f.run_for(@sfapp.toast_rest_ms)
    f.end()
  })
}
