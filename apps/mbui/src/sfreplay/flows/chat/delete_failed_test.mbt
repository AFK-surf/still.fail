// 13-delete-failed (e2e/traces/delete-failed.trace): a message that did not go (the station frozen), deleted (删除):
// gone from the chat, and never sent again.

///|
test "13-delete-failed" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace_delete_failed, seed~)
    f.tap("端到端测试")
    f.run_for(@ui.nav_push_ms)
    f.see("=studio")
    f.tap("发消息")
    f.type_text("这条没发出去就删掉 082947")
    f.tap("icon:arrow-up")
    f.run_for(@sfapp.flight_ms)
    f.see("未发送")
    f.tap("=删除")
    f.gone("这条没发出去就删掉 082947")
    // its row's leaving copy fades where it was (out_leave_ms: mbui has no rest to ask for a list's leaving copies)
    f.run_for(@sfapp.out_leave_ms)
    f.end()
  })
}
