// 25-archive (e2e/traces/archive.trace): 归档此对话 under the agent's last all-done post (a chat of its own, made on the
// other device before the app started): Home at once, the chat gone from the list, 已归档 said (chat.archive).

///|
test "25-archive" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace_archive, seed~)
    // (made by alice's other device before the app starts: a live run's step, the trace has what came of it)
    f.before("peer create 归档用的对话 085454 post:这件事做完了 085454")
    f.before("wait-chat 归档用的对话 085454")
    f.see("归档用的对话 085454")
    f.see("这件事做完了 085454")
    f.tap("归档用的对话 085454")
    f.run_for(@ui.nav_push_ms)
    f.see("归档此对话")
    f.tap("=归档此对话")
    // Home at once, 已归档 said: its time on screen, the chat popped meanwhile
    f.see("=已归档")
    f.run_for(@sfapp.toast_ms)
    f.gone("归档用的对话 085454")
    // the toast gone
    // (its time out at the last frame: it starts going with the one after)
    f.t.draw()
    f.run_to_rest("toast")
    f.end()
  })
}
