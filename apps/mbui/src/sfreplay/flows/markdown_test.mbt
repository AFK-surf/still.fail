// 74-markdown (e2e/traces/markdown.trace): an agent's Markdown: a table, TypeScript highlighted, the code's long line
// scrolled sideways by a finger, a link held: its menu, 复制链接 (已复制链接), the address on the clipboard, nothing
// opened.

///|
test "74-markdown" {
  @sfreplay.orders(fn(seed) {
    let f = @sfreplay.Flow::start(@sfreplay.trace("markdown"), seed~)
    f.tap("端到端测试")
    f.run_for(@ui.move_most_ms)
    f.see("=willow")
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
    if f.saw(rest > f.t.time()) {
      f.run_to(fn() { rest })
    }
    // (and the agent's line gone, its room closed: Reading's going, in every timing)
    f.gone("处理中")
    let closed = f.t.rest_of("a list's rows' heights")
    if f.saw(closed > f.t.time()) {
      f.run_to(fn() { closed })
    }
    // (what the screen says here is the strict pass's to judge: a pace pass gives the same inputs, f.check)
    let at = fn(what : String, i : Int) -> Double {
      match f.t.locate(what) {
        [p, ..] => if i == 0 { p.0 } else { p.1 }
        [] => -1.0
      }
    }
    let field = fn() { f.t.query(@ui.Role::TextField) }
    let x0 = at("placeRows", 0)
    let y0 = at("聊天页的列表和输入框", 1)
    let field0 = field()
    f.check(field0.map(fn(x) { x.focused }).unwrap_or(false), "the field focused before the drag")
    f.drag("placeRows", -220.0, 0.0, steps=30)
    // the code scrolled sideways under the finger (its words gone left, or out of its box), not the list
    let after = f.t.locate("placeRows")
    f.check(after.length() == 0 || after[0].0 < x0, "the code not scrolled sideways: \{Repr(after)}")
    // the touch on the list lets go of the field: the composer closes to its one row, the field lower in it, a line as
    // tall as before; the list keeps the room of an opened composer (composer_room_for), so its words stay where they
    // were: the page does not jump
    let field1 = field()
    match (field0, field1) {
      (Some(a), Some(b)) => {
        f.check(!b.focused, "the field still focused after the touch on the list")
        f.check(b.rect.3 == a.rect.3, "the field's line \{b.rect.3} tall, not \{a.rect.3}")
        f.check(b.rect.1 > a.rect.1, "the field not lower: \{b.rect.1}, was \{a.rect.1}")
      }
      _ => f.check(false, "no field")
    }
    f.check(at("聊天页的列表和输入框", 1) == y0, "the list's words moved")
    f.hold("example.com/e2e", @ui.long_press_ms)
    f.see("=复制链接")
    f.tap("=复制链接")
    f.see("=已复制链接")
    f.check(f.t.clipboard().has_prefix("https://example.com/e2e/"), "the clipboard holds \{f.t.clipboard()}")
    f.check(f.t.opened().length() == 0, "a link opened")
    // the code's sideways fling, the link's menu going, the toast coming: to their ends, as each set out
    let rests = [f.t.rest_of("a fling"), f.t.rest_of("link-menu"), f.t.rest_of("presence/toast")]
    f.run_to(fn() { rests.fold(init=-1.0, fn(a, b) { if b > a { b } else { a } }) })
    f.end()
  })
}
