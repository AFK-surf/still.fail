// 06-draft (e2e/traces/draft.trace): words left in the field, the chat left and opened again: they are back (the
// core keeps them: draft.set; nothing sent).

///|
test "06-draft" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace_draft, seed~)
    f.tap("端到端测试")
    f.run_for(@ui.nav_push_ms)
    f.see("=studio")
    f.tap("发消息")
    f.type_text("还没发出去的草稿 082947")
    // kept a moment after the change
    f.run_for(@sfapp.draft_keep_ms)
    f.tap("icon:chevron-left")
    f.run_for(@ui.nav_push_ms)
    f.see("端到端测试")
    f.tap("端到端测试")
    f.run_for(@ui.nav_push_ms)
    f.see("=studio")
    // the draft back in the field
    f.tap("发消息")
    f.field("还没发出去的草稿 082947")
    // the bar moved by what this did (the field focused, the chat left) at rest
    f.run_to(@sfapp.bar_rest())
    f.end()
  })
}
