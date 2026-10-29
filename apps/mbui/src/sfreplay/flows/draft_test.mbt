// 06-draft (e2e/traces/draft.trace): words left in the field, the chat left and opened again: they are back (the
// core keeps them: composer.text; nothing sent).

///|
test "06-draft" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("draft"), seed~)
    f.tap("端到端测试")
    f.run_for(@ui.move_most_ms)
    f.see("=studio")
    f.tap("发消息")
    f.type_text("还没发出去的草稿 082947")
    // kept by the core as it is typed (composer.text; the next run, 07, finds it there)
    f.answered("composer.text", 1)
    f.tap("icon:chevron-left")
    f.run_for(@ui.move_most_ms)
    f.see("端到端测试")
    f.tap("端到端测试")
    f.run_for(@ui.move_most_ms)
    f.see("=studio")
    // the draft back in the field (its words where 发消息 was)
    let field = f.t.get(@ui.Role::TextField)
    f.check(field.value.contains("还没发出去的草稿 082947"), "the field holds \{field.value.escape()}")
    // the bar moved by what this did (the field focused, the chat left) at rest
    f.run_to(@sfapp.bar_rest())
    f.end()
  })
}
