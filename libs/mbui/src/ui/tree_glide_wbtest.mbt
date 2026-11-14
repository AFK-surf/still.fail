// Columns of the window's tree gliding on by themselves (View::scrolls' fling) told as what moves (Tree::on_glides),
// each its own: two flung one after the other, the later stopping sooner, what moves at rest when the first is; the
// first let go of, at rest as the second is, its end no longer said; the second, still there, stopped by the wheel turned
// on it, at rest at once.

///|
/// Two columns side by side, each 2000 high of nothing to scroll through, the first while `first` says so: their
/// scrolls.
fn two_columns(first : @signals.Signal[Bool]) -> (Tester, @view.Scroll, @view.Scroll) {
  let a = @view.Scroll::new()
  let b = @view.Scroll::new()
  let t = Tester::new(fn(_c) {  }, platform=2, w=400.0, h=600.0)
  set_view_app(fn(root) {
    root.box(fn(row) {
      row.row(Is(true)).grow(Is(1.0)) |> ignore
      row.box(fn(left) {
        left.width(Is(Some(200.0))).height(Is(Some(600.0))) |> ignore
        left.show(at_once=true, fn() { first.get() }, fn(col) {
          col.grow(Is(1.0)).scrolls(a, fn(body) { body.height(Is(Some(2000.0))) |> ignore }) |> ignore
        })
      })
      |> ignore
      row.box(fn(right) {
        right.width(Is(Some(200.0))).height(Is(Some(600.0))).scrolls(b, fn(body) { body.height(Is(Some(2000.0))) |> ignore }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  (t, a, b)
}

///|
test "window tree: two columns flung one after the other, the later stopping sooner: what moves at rest as the first is" {
  let first = @signals.signal(true)
  let (t, a, b) = two_columns(first)
  // (the first flung hard, short of its end, the second gently after it)
  t.drag(100.0, 400.0, 100.0, 200.0, steps=4)
  t.drag(300.0, 300.0, 300.0, 260.0, steps=4)
  let (ea, eb) = (a.glides_till().unwrap(), b.glides_till().unwrap())
  assert_true(eb < ea, msg="first \{ea}, second \{eb}")
  assert_eq(rest_of("a list's fling, the tree's"), ea)
  // (the first let go of: its glide told no more, what moves at rest as the second is)
  first.set(false)
  t.draw()
  assert_eq(rest_of("a list's fling, the tree's"), eb)
  // (the second, still there, stopped by the wheel turned on it: its glide none, nothing said to move)
  t.wheel(300.0, 300.0, 10.0)
  assert_eq(b.glides_till(), None)
  assert_true(rest_of("a list's fling, the tree's") <= t.time())
}
