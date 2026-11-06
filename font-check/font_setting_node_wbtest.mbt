// The preview's held height is part of its own layout. A shorter face must not move the rows while the hand is there.

///|
test "font preview keeps its greatest height only for this visit of the pointer" {
  let natural = @signals.signal(40.0, same=fn(a, b) { a == b })
  let holding = @signals.signal(false, same=fn(a, b) { a == b })
  let held = Ref(0.0)
  let after : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.reacts(fn() { holding.get() }, fn(on) { if !on { held.val = 0.0 } })
    root.box(fn(col) {
      font_held_node(col, holding, held, fn(child) { child.height(By(fn() { Some(natural.get()) })) |> ignore })
      after.val = Some(col.box(fn(row) { row.height(Is(Some(10.0))) |> ignore }))
    }) |> ignore
  })
  tree.frame(390.0, 844.0) |> ignore
  assert_eq(after.val.unwrap().rect().1, 40.0)
  holding.set(true)
  natural.set(80.0)
  tree.frame(390.0, 844.0) |> ignore
  assert_eq(after.val.unwrap().rect().1, 80.0)
  natural.set(30.0)
  tree.frame(390.0, 844.0) |> ignore
  assert_eq(after.val.unwrap().rect().1, 80.0)
  natural.set(100.0)
  tree.frame(390.0, 844.0) |> ignore
  assert_eq(after.val.unwrap().rect().1, 100.0)
  // The pointer can leave and return before another frame. The next visit starts with its own height.
  holding.set(false)
  holding.set(true)
  natural.set(25.0)
  tree.frame(390.0, 844.0) |> ignore
  assert_eq(after.val.unwrap().rect().1, 25.0)
  holding.set(false)
  natural.set(15.0)
  tree.frame(390.0, 844.0) |> ignore
  assert_eq(after.val.unwrap().rect().1, 15.0)
  tree.dispose()
}
