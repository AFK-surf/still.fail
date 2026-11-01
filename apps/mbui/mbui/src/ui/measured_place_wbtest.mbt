// Where a change lays things out read before it is placed (View::laid_size: Tree::measured_now), more than once, other
// changes between: what each read laid out placed once things are placed, whatever was laid out again after it, and
// nothing placed again once nothing changes.

///|
test "a row's box made wider and read, then another row's and read: once placed, what comes after each where its box now ends; drawn again unchanged, nothing placed again" {
  let a_w = @signals.signal(40.0, same=fn(a, b) { a == b })
  let b_w = @signals.signal(40.0, same=fn(a, b) { a == b })
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  let seen : Array[@view.View] = []
  set_view_app(fn(root) {
    for w in [a_w, b_w] {
      root.box(fn(row) {
        row.row(Is(true)).height(Is(Some(20.0))) |> ignore
        let box = row.box(fn(b) { b.width(By(fn() { Some(w.get()) })) |> ignore })
        let after = row.box(fn(d) { d.width(Is(Some(10.0))) |> ignore })
        seen.push(box)
        seen.push(after)
      })
      |> ignore
    }
  })
  t.draw()
  // (A wider, read; then B wider, read: each laid out to be read, nothing placed yet)
  a_w.set(70.0)
  let a_read = seen[0].laid_size().0
  b_w.set(90.0)
  let b_read = seen[2].laid_size().0
  t.frame()
  let placed = (seen[1].rect().0, seen[3].rect().0)
  let tree = view_tree().unwrap()
  let work = tree.work()
  t.frame()
  let again = tree.work()
  assert_eq(
    (a_read, b_read, placed, again.laid - work.laid, again.visited - work.visited),
    (70.0, 90.0, (70.0, 90.0), 0, 0),
  )
}
