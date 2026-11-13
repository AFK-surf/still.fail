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
    root.show(at_once=true, fn() { on.get() }, fn(v) {
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
    root.show(at_once=true, fn() { on.get() }, fn(v) {
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

///|
/// A node in a window (its width always set together, 40; its height too where `tall()` says one, not the first time
/// maybe), shown while `on`, kept in `node`.
fn together_tree(
  on : @signals.Signal[Bool],
  tall : @signals.Signal[Double?],
  node : Ref[@view.View?],
) -> @view.Tree {
  @view.Tree::new(fn(root) {
    root.lines_up(Is(Some(Start))) |> ignore
    root.show(at_once=true, fn() { on.get() }, fn(v) {
      v.box(fn(b) {
        node.val = Some(b)
        b.sets_together(fn() { tall.get() }, fn(t) {
          b.width(Is(Some(40.0))) |> ignore
          match t {
            Some(h) => b.height(Is(Some(h))) |> ignore
            None => ()
          }
        })
        |> ignore
      })
      |> ignore
    })
  })
}

///|
test "sets_together: one it sets only later is set then, as one set the first time is; said no more, left as it last set it" {
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let tall : @signals.Signal[Double?] = @signals.signal(None, same=fn(a, b) { a == b })
  let node : Ref[@view.View?] = Ref(None)
  let tree = together_tree(on, tall, node)
  tree.frame(390.0, 844.0) |> ignore
  let b = node.val.unwrap()
  let seen = [b.laid_size()]
  tall.set(Some(30.0))
  tree.frame(390.0, 844.0) |> ignore
  seen.push(b.laid_size())
  tall.set(Some(50.0))
  tree.frame(390.0, 844.0) |> ignore
  seen.push(b.laid_size())
  // (said no more: as it last set it, the caller's to set otherwise)
  tall.set(None)
  tree.frame(390.0, 844.0) |> ignore
  seen.push(b.laid_size())
  assert_eq(seen, [(40.0, 0.0), (40.0, 30.0), (40.0, 50.0), (40.0, 50.0)])
}

///|
test "sets_together: one it sets only later, bound by another before: that one's, not taken" {
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let tall : @signals.Signal[Double?] = @signals.signal(None, same=fn(a, b) { a == b })
  let own = @signals.signal(10.0, same=fn(a, b) { a == b })
  let node : Ref[@view.View?] = Ref(None)
  let tree = together_tree(on, tall, node)
  tree.frame(390.0, 844.0) |> ignore
  let b = node.val.unwrap()
  b.height(By(fn() { Some(own.get()) })) |> ignore
  tree.frame(390.0, 844.0) |> ignore
  tall.set(Some(30.0))
  tree.frame(390.0, 844.0) |> ignore
  let seen = [b.laid_size()]
  own.set(20.0)
  tree.frame(390.0, 844.0) |> ignore
  seen.push(b.laid_size())
  assert_eq(seen, [(40.0, 10.0), (40.0, 20.0)])
}

///|
test "sets_together: one taken later, then bound by another: that one's, set by it no more; the node let go, nothing left" {
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let tall : @signals.Signal[Double?] = @signals.signal(None, same=fn(a, b) { a == b })
  let own = @signals.signal(10.0, same=fn(a, b) { a == b })
  let node : Ref[@view.View?] = Ref(None)
  let tree = together_tree(on, tall, node)
  tree.frame(390.0, 844.0) |> ignore
  let held = tree.bindings_held()
  let b = node.val.unwrap()
  tall.set(Some(30.0))
  tree.frame(390.0, 844.0) |> ignore
  assert_eq(b.laid_size(), (40.0, 30.0))
  assert_eq(tree.bindings_held(), held)
  b.height(By(fn() { Some(own.get()) })) |> ignore
  tree.frame(390.0, 844.0) |> ignore
  tall.set(Some(60.0))
  tree.frame(390.0, 844.0) |> ignore
  let seen = [b.laid_size()]
  // (said again by it: still not its)
  tall.set(Some(70.0))
  tree.frame(390.0, 844.0) |> ignore
  seen.push(b.laid_size())
  assert_eq(seen, [(40.0, 10.0), (40.0, 10.0)])
  // (the node let go: what it bound and what bound it let go with it)
  on.set(false)
  tree.frame(390.0, 844.0) |> ignore
  assert_false(tall.watched())
  assert_false(own.watched())
}

///|
test "sets_together: one of its set once by another with Is: that one's, not taken back as it sets it again" {
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let tall : @signals.Signal[Double?] = @signals.signal(Some(30.0), same=fn(a, b) { a == b })
  let node : Ref[@view.View?] = Ref(None)
  let tree = together_tree(on, tall, node)
  tree.frame(390.0, 844.0) |> ignore
  let b = node.val.unwrap()
  b.width(Is(Some(20.0))) |> ignore
  tree.frame(390.0, 844.0) |> ignore
  tall.set(Some(50.0))
  tree.frame(390.0, 844.0) |> ignore
  assert_eq(b.laid_size(), (20.0, 50.0))
}
