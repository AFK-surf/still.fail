// 07-draft-restart (e2e/traces/draft-restart.trace): the app started again over words left in the field (its run's own:
// e2e/flows/06-draft-left), the draft is still there (the core gives it back); emptied, it is gone (the core told).
// before it: 06-draft-left

///|
test "07-draft-restart" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("draft-restart"), seed~)
    f.tap("端到端测试")
    f.run_for(@ui.move_most_ms)
    f.see("=studio")
    // the draft back in the field
    f.tap("发消息")
    f.field("还没发出去的草稿 082947")
    f.clear()
    f.field("")
    // (the core told as it changed: composer.text)
    f.answered("composer.text", 1)
    // the bar moved by what this did (the field focused, the chat left) at rest
    f.run_to(@sfapp.bar_rest())
    f.end()
  })
}
