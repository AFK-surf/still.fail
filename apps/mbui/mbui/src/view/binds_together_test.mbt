// Properties bound together (View::binds_together): one watch for all of them, each set as it would be alone; one
// bound again alone is that binding's, the others still theirs; all let go with the node.

///|
test "binds_together: one watch for them all, each set again as what it read changes, one bound again alone its own" {
  let w = @signals.signal(40.0, same=fn(a, b) { a == b })
  let h = @signals.signal(30.0, same=fn(a, b) { a == b })
  let own = @signals.signal(10.0, same=fn(a, b) { a == b })
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let node : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.show(fn() { on.get() }, fn(v) {
      v.box(fn(b) {
        node.val = Some(b)
        b.binds_together(fn() {
          b.width(By(fn() { Some(w.get()) })).height(By(fn() { Some(h.get()) })) |> ignore
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
  // (its height bound again alone: followed by that, not by what the two read together)
  b.height(By(fn() { Some(own.get()) })) |> ignore
  tree.frame(390.0, 844.0) |> ignore
  assert_eq(b.laid_size(), (50.0, 10.0))
  h.set(60.0)
  w.set(70.0)
  tree.frame(390.0, 844.0) |> ignore
  assert_eq(b.laid_size(), (70.0, 10.0))
  // (its width bound alone too: the two's watch let go, nothing read for them)
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
