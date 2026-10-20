// 74-markdown (e2e/traces/markdown.trace): an agent's Markdown: a table, TypeScript highlighted, the code's long line
// scrolled sideways by a finger, a link held: its menu, 复制链接 (已复制链接), the address on the clipboard, nothing
// opened.

///|
test "74-markdown" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace_markdown, seed~)
    f.tap("端到端测试")
    f.run_for(@ui.nav_push_ms)
    f.see("=studio")
    f.tap("发消息")
    f.type_text("给个表格 082947 md:表格和代码 082947")
    f.tap("icon:arrow-up")
    f.run_for(@sfapp.flight_ms)
    f.gone("正在发送")
    f.see("聊天页的列表和输入框")
    f.see("placeRows")
    // (the post all done: its 归档 under it coming in, its room opening: at rest before where the rows are is taken)
    f.run_to_rest("under/")
    let x0 = f.t.locate("placeRows")[0].0
    assert_true(f.t.at_end())
    f.drag("placeRows", -220.0, 0.0, steps=30)
    // the code scrolled sideways under the finger (its words gone left, or out of its box), not the list
    let after = f.t.locate("placeRows")
    assert_true(after.length() == 0 || after[0].0 < x0)
    // (the list at its end still: the field let go of with the touch, the composer smaller, the list following its
    // end down as it would, not scrolled by the finger)
    assert_true(f.t.at_end())
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
