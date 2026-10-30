// Profiles' scrollbar stays in the sidebar gutter and can be dragged independently of its resize handle.

///|
fn profiles_side_bar(t : @ui.Tester) -> (Double, Double, Double, Double, Int64) {
  t.drawn_rects().filter(fn(r) { r.0 < 400.0 && r.2 == @ui.scroll_bar_size && r.3 > @ui.scroll_bar_least })[0]
}

///|
test "profiles: the sidebar thumb is outside its rows, dragging it scrolls without resizing, and the edge still resizes" {
  let t = wide_tester([], mode="settings", h=360.0)
  app.nav.replace(Place("profiles"))
  t.draw()
  let row = t.boxes().iter().find_first(fn(b) { b.x == 56.0 && b.w == 232.0 && b.h == 54.0 }).unwrap()
  let width = @sfdesk.wide.side_w.get()
  let edge = @sfdesk.rail_w + width
  t.wheel(260.0, 200.0, 100.0)
  t.run_for(@ui.scrollbar_fade_ms)
  let bar = profiles_side_bar(t)
  assert_true(bar.0 >= row.x + row.w)
  // (as far in from the panel's line (B1) as a bar is from what holds it: what the panel holds is cut at its line's
  // inside)
  assert_eq(bar.0 + bar.2, edge - 1.0 - @ui.scroll_bar_inset)
  let x = bar.0 + bar.2 / 2.0
  let y = bar.1 + bar.3 / 2.0
  t.move(x, y)
  t.drag(x, y, x, y - 80.0)
  assert_true(profiles_side_bar(t).1 < bar.1)
  assert_eq(@sfdesk.wide.side_w.get(), width)
  assert_false(@sfdesk.wide.folded.get())
  t.drag(edge + 2.0, 200.0, edge + 62.0, 200.0)
  assert_eq(@sfdesk.wide.side_w.get(), width + 60.0)
}
