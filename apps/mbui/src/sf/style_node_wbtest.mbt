// A style laid on a node (style_node) that says a property only some of the time: what it has said so far is what it
// sets, so a property said for the first time after the node was made is set, and one said before and said no more is
// put back to none.

///|
/// A window holding one node styled `said` where `on()`, `plain` where not, kept in `at`.
fn style_tester(on : @signals.Signal[Bool], plain : @ui.Style, said : @ui.Style, at : Ref[@view.View?]) -> @ui.Tester {
  parts_reset()
  let t = @ui.Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  @ui.set_view_app(fn(root) {
    root.padding(Is((20.0, 20.0, 0.0, 0.0))).lines_up(Is(Some(Start))) |> ignore
    root.box(fn(b) {
      at.val = Some(b)
      style_node(b, fn() { if on.get() { said } else { plain } })
    })
    |> ignore
  })
  t.draw()
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// Whether node `at` is drawn on the hover's ground.
fn style_grounded(t : @ui.Tester, at : Ref[@view.View?]) -> Bool {
  let (x, y, w, h) = at.val.unwrap().placed_window_now()
  let hover = @ui.tree_theme().color(Hover)
  t.drawn_rects().iter().any(fn(r) { r.4 == hover && r.0 == x && r.1 == y && r.2 == w && r.3 == h })
}

///|
test "style_node: a ground said only after the node was made is drawn, and goes as it is said no more" {
  let on = @signals.signal(false, same=fn(a, b) { a == b })
  let at : Ref[@view.View?] = Ref(None)
  let plain = @ui.style(w=Fixed(64.0), h=Fixed(32.0))
  let t = style_tester(on, plain, plain.then(@ui.css("bg=Hover")), at)
  let seen = [style_grounded(t, at)]
  on.set(true)
  t.run_for(@ui.move_most_ms)
  seen.push(style_grounded(t, at))
  on.set(false)
  t.run_for(@ui.move_most_ms)
  seen.push(style_grounded(t, at))
  on.set(true)
  t.run_for(@ui.move_most_ms)
  seen.push(style_grounded(t, at))
  assert_eq(seen, [false, true, false, true])
}

///|
test "style_node: a ground said as the node was made goes as it is said no more, and comes back as it is said again" {
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let at : Ref[@view.View?] = Ref(None)
  let plain = @ui.style(w=Fixed(64.0), h=Fixed(32.0))
  let t = style_tester(on, plain, plain.then(@ui.css("bg=Hover")), at)
  let seen = [style_grounded(t, at)]
  on.set(false)
  t.run_for(@ui.move_most_ms)
  seen.push(style_grounded(t, at))
  on.set(true)
  t.run_for(@ui.move_most_ms)
  seen.push(style_grounded(t, at))
  assert_eq(seen, [true, false, true])
}

///|
test "style_node: a least height said only after the node was made is laid out, and goes as it is said no more" {
  let on = @signals.signal(false, same=fn(a, b) { a == b })
  let at : Ref[@view.View?] = Ref(None)
  let plain = @ui.style(w=Fixed(64.0))
  let t = style_tester(on, plain, plain.then(@ui.style(min_h=Fixed(50.0))), at)
  let high = fn() { at.val.unwrap().placed_window_now().3 }
  let seen = [high()]
  on.set(true)
  t.run_for(@ui.move_most_ms)
  seen.push(high())
  on.set(false)
  t.run_for(@ui.move_most_ms)
  seen.push(high())
  assert_eq(seen, [0.0, 50.0, 0.0])
}
