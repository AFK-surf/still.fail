// A link's card open over its row as the pointer rests on it, the row then carried from under the still pointer by the
// room over it growing on a way: the card stays as the row goes (what the pointer is over is not worked out on the
// way), and goes once the way is over and the row is found no longer under it (Tree::hand_at_end).

///|
/// How long the room over it takes to grow, carrying it off.
let carried_ms : Double = 300.0

///|
test "a link's card, its row carried from under a still pointer on a way: open as it goes, gone once the way is over" {
  @sfbase.reset()
  let src = @sfbase.made_source()
  let grow = @motion.Way::new(40.0)
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=800.0, h=800.0, native=Mouse, pointing=Mouse)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    root.box(fn(col) {
      col.box(fn(b) { b.height(By(fn() { Some(grow.shown_on(b)) })) |> ignore }) |> ignore
      col.box(fn(row) {
        row
        .width(Is(Some(200.0)))
        .height(Is(Some(32.0)))
        .on_press(fn() {  })
        .says(Is(Some(@view.said(Button, label="PR #4466"))))
        |> ignore
        web_peek_node(row, src, "st", fn() { "https://github.com/AFK-surf/Cue/pull/4466" }, fn() { "PR #4466" })
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let (x, y, w, h) = t.get(@ui.Role::Button, label="PR #4466").rect
  t.move_to(x + w / 2.0, y + h / 2.0)
  t.run_for(hover_open_ms * 2.0)
  let card = fn() { t.semantics().filter(fn(s) { s.role == Group && s.label.has_prefix("PR #4466") }).length() }
  let opened = card()
  let tree = @ui.view_tree().unwrap()
  let at = t.time()
  tree.event(at, fn() { grow.go(240.0, @motion.tween(carried_ms, ease=Out), at~) })
  t.run_for(carried_ms - hover_close_ms)
  let midway = card()
  t.run_for(hover_close_ms + (hover_close_ms + hover_out_ms) * 2.0)
  assert_eq((opened, midway, card()), (1, 1, 0))
}

///|
test "a link's card: what its page is called on two lines at most, the second ending in an ellipsis (peek_tile_title), as the old view's card drew it" {
  @sfbase.reset()
  let src = @sfbase.made_source()
  let words = "一个名字很长很长的网页，长到在卡片里放两行都放不下，后面还有很多字要被收进省略号里去才对；" +
    "再写上一大段，让它在最宽的卡片里也要排到第三行、第四行去，看它是不是在第二行的末尾收住"
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=800.0, h=800.0, native=Mouse, pointing=Mouse)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    root.box(fn(row) {
      row
      .width(Is(Some(200.0)))
      .height(Is(Some(32.0)))
      .on_press(fn() {  })
      .says(Is(Some(@view.said(Button, label="链接"))))
      |> ignore
      web_peek_node(row, src, "st", fn() { "https://example.com/a/long/page" }, fn() { words })
    })
    |> ignore
  })
  t.draw()
  let (x, y, w, h) = t.get(@ui.Role::Button, label="链接").rect
  t.move_to(x + w / 2.0, y + h / 2.0)
  t.run_for(hover_open_ms * 2.0)
  let lines = t.lines_of("一个名字")
  assert_eq(lines.length(), 2, msg="\{Repr(lines)}")
  assert_true(lines[1].has_suffix("…"), msg="\{Repr(lines)}")
}
