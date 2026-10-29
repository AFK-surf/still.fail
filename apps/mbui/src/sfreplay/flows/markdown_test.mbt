// 74-markdown (e2e/traces/markdown.trace): an agent's Markdown: a table, TypeScript highlighted, the code's long line
// scrolled sideways by a finger, a link held: its menu, 复制链接 (已复制链接), the address on the clipboard, nothing
// opened.

///|
test "74-markdown" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("markdown"), seed~)
    f.tap("端到端测试")
    f.run_for(@ui.move_most_ms)
    f.see("=studio")
    f.tap("发消息")
    f.type_text("给个表格 082947 md:表格和代码 082947")
    f.tap("icon:arrow-up")
    f.run_for(@sfapp.flight_ms)
    f.gone("正在发送")
    f.see("聊天页的列表和输入框")
    f.see("placeRows")
    // (the post all done: what comes under it, its room opening, the list gliding to its end after what came, the
    // agent's activity going and its mark ending its pose, the composer letting go of the room it held for the words
    // sent (composer_hold): all that moves at rest before the code is dragged, in every timing)
    let rest = f.t.rest_of("")
    if rest > f.t.time() {
      f.run_to(rest)
    }
    // (and the agent's line gone, its room closed: Reading's going, in every timing)
    f.gone("处理中")
    let closed = f.t.rest_of("a list's rows' heights")
    if closed > f.t.time() {
      f.run_to(closed)
    }
    let x0 = f.t.locate("placeRows")[0].0
    let y0 = f.t.locate("聊天页的列表和输入框")[0].1
    let field0 = f.t.get(@ui.Role::TextField)
    assert_true(field0.focused)
    f.drag("placeRows", -220.0, 0.0, steps=30)
    // the code scrolled sideways under the finger (its words gone left, or out of its box), not the list
    let after = f.t.locate("placeRows")
    assert_true(after.length() == 0 || after[0].0 < x0)
    // the touch on the list lets go of the field: the composer closes to its one row, the field lower in it, a line as
    // tall as before; the list keeps the room of an opened composer (composer_room_for), so its words stay where they
    // were: the page does not jump
    let field1 = f.t.get(@ui.Role::TextField)
    assert_true(!field1.focused)
    assert_eq(field1.rect.3, field0.rect.3)
    assert_true(field1.rect.1 > field0.rect.1)
    assert_true(f.t.locate("聊天页的列表和输入框")[0].1 == y0)
    f.hold("example.com/e2e", @ui.long_press_ms)
    f.see("=复制链接")
    f.tap("=复制链接")
    f.see("=已复制链接")
    assert_true(f.t.clipboard().has_prefix("https://example.com/e2e/"))
    assert_true(f.t.opened().length() == 0)
    // the code's sideways fling, the link's menu going, the toast coming: to their ends, as each set out
    let rests = [f.t.rest_of("a fling"), f.t.rest_of("link-menu"), f.t.rest_of("presence/toast")]
    f.run_to(rests.fold(init=-1.0, fn(a, b) { if b > a { b } else { a } }))
    f.end()
  })
}
