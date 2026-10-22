// 07-draft-restart (e2e/traces/draft-restart.trace, after 06-draft's run): the app started again, the draft is still
// there (the core gives it back); emptied, it is gone (the core told).

///|
test "07-draft-restart" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("draft-restart"), seed~)
    f.tap("端到端测试")
    f.run_for(@ui.nav_push_ms)
    f.see("=studio")
    // the draft back in the field
    f.tap("发消息")
    f.field("还没发出去的草稿 082947")
    f.clear()
    f.field("")
    // kept a moment after the change
    f.run_for(@sfapp.draft_keep_ms)
    // the bar moved by what this did (the field focused, the chat left) at rest
    f.run_to(@sfapp.bar_rest())
    f.end()
  })
}
