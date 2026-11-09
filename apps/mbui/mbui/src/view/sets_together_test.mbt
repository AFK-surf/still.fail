// Properties set together (View::sets_together): one binding for all of them, each set as said; one bound again by
// another is that one's, the others still theirs; the binding let go with the last of them, or with the node.

///|
test "sets_together: one binding for them all, set again as what it read changes, one bound again by another its own" {
  let w = @signals.signal(40.0, same=fn(a, b) { a == b })
  let h = @signals.signal(30.0, same=fn(a, b) { a == b })
  let own = @signals.signal(10.0, same=fn(a, b) { a == b })
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let node : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.show(fn() { on.get() }, fn(v) {
      v.box(fn(b) {
        node.val = Some(b)
        b.sets_together(fn() { (w.get(), h.get()) }, fn(s) {
          b.width(Is(Some(s.0))).height(Is(Some(s.1))) |> ignore
        })
        |> ignore
      })
      |> ignore
    })
  })
  tree.frame(390.0, 844.0) |> ignore
  let b = node.val.unwrap()
  let before = tree.bindings_held()
  assert_eq(b.laid_size(), (40.0, 30.0))
  w.set(50.0)
  tree.frame(390.0, 844.0) |> ignore
  assert_eq(b.laid_size(), (50.0, 30.0))
  // (its height bound again by another: followed by that, not set again by what sets the two)
  b.height(By(fn() { Some(own.get()) })) |> ignore
  tree.frame(390.0, 844.0) |> ignore
  assert_eq(b.laid_size(), (50.0, 10.0))
  h.set(60.0)
  w.set(70.0)
  tree.frame(390.0, 844.0) |> ignore
  assert_eq(b.laid_size(), (70.0, 10.0))
  // (its width set by another too: the two's binding let go, nothing read for them)
  b.width(Is(Some(20.0))) |> ignore
  tree.frame(390.0, 844.0) |> ignore
  assert_eq(b.laid_size(), (20.0, 10.0))
  assert_false(w.watched())
  assert_false(h.watched())
  assert_eq(tree.bindings_held(), before)
  // (the node let go: what is bound alone let go with it)
  on.set(false)
  tree.frame(390.0, 844.0) |> ignore
  assert_false(own.watched())
}

///|
test "sets_together: its binding let go with the node" {
  let w = @signals.signal(40.0, same=fn(a, b) { a == b })
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let tree = @view.Tree::new(fn(root) {
    root.show(fn() { on.get() }, fn(v) {
      v.box(fn(b) { b.sets_together(fn() { w.get() }, fn(x) { b.width(Is(Some(x))) |> ignore }) |> ignore })
      |> ignore
    })
  })
  tree.frame(390.0, 844.0) |> ignore
  assert_true(w.watched())
  let before = tree.bindings_held()
  on.set(false)
  tree.frame(390.0, 844.0) |> ignore
  assert_false(w.watched())
  assert_eq(tree.bindings_held(), before - 1)
}
