///|
/// N structures reading one signal, the signal set once (outside a batch, and in one): the most of Tree::at_cause
/// committing at once, as each structure's change is made, and how many showed after.
fn flush_nested_deepest(n : Int, batched : Bool) -> (Int, Int) {
  let s = @signals.signal(0, same=fn(a, b) { a == b })
  let deepest = Ref(0)
  let shown = Ref(0)
  let tree : Ref[Tree?] = Ref(None)
  let t = Tree::new(
    fn(root) {
      for _ in 0..<n {
        root.box(fn(v) {
          v.show(fn() { s.get() >= 1 }, fn(w) {
            if tree.val is Some(t) && t.committing > deepest.val {
              deepest.val = t.committing
            }
            shown.val += 1
            w.box(fn(_) {  }) |> ignore
          })
        })
        |> ignore
      }
    },
    time=fn() { 0.0 },
  )
  tree.val = Some(t)
  t.frame(390.0, 844.0) |> ignore
  if batched {
    @signals.start_batch()
    s.set(1)
    @signals.end_batch()
  } else {
    s.set(1)
  }
  t.frame(390.0, 844.0) |> ignore
  t.dispose()
  (deepest.val, shown.val)
}

///|
test "the structures one change marks are each committed in the flush that tells them, none nested in another's: as deep at 400 as at 2" {
  for batched in [false, true] {
    let (two, two_shown) = flush_nested_deepest(2, batched)
    let (many, many_shown) = flush_nested_deepest(400, batched)
    assert_eq(two_shown, 2)
    assert_eq(many_shown, 400)
    assert_eq(many, two)
  }
}
