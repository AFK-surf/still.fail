// 25-archive (e2e/traces/archive.trace): 归档此对话 under the agent's last all-done post (a chat of its own, made on the
// other device before the app started): Home at once, the chat gone from the list, 已归档 said (chat.archive).

///|
test "25-archive" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace_archive, seed~)
    f.see("归档用的对话 085454")
    f.see("这件事做完了 085454")
    f.tap("归档用的对话 085454")
    f.run_for(@ui.nav_push_ms)
    f.see("归档此对话")
    f.tap("=归档此对话")
    // Home again, the chat popped
    f.run_for(@ui.nav_push_ms)
    f.see("=已归档")
    f.gone("归档用的对话 085454")
    // Home again (the chat popped), and 已归档 said for its time
    f.run_for(@sfapp.toast_rest_ms)
    f.end()
  })
}
