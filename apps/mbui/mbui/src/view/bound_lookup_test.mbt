///|
test "a marked binding may be removed and replaced before it is pulled" {
  let shown = @signals.signal(true)
  let size = @signals.signal(1.0)
  let current : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.show(fn() { shown.get() }, fn(v) {
      current.val = Some(v)
      v.width(By(fn() { Some(size.get() * 10.0) })).height(Is(Some(20.0))) |> ignore
    })
  })
  tree.frame(400.0, 100.0, now=0.0) |> ignore
  assert_eq(current.val.unwrap().rect().2, 10.0)
  size.set(2.0)
  shown.set(false)
  size.set(3.0)
  shown.set(true)
  tree.frame(400.0, 100.0, now=1.0) |> ignore
  assert_eq(current.val.unwrap().rect().2, 30.0)
  assert_eq(tree.bindings_held(), 1)
  shown.set(false)
  assert_false(size.watched())
  assert_eq(tree.bindings_held(), 0)
  tree.dispose()
}

///|
test "replacing a marked property with a fixed one does not pull the old binding" {
  let size = @signals.signal(1.0)
  let current : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    current.val = Some(root.box(fn(v) {
      v.width(By(fn() { Some(size.get() * 10.0) })) |> ignore
    }))
  })
  tree.frame(400.0, 100.0, now=0.0) |> ignore
  size.set(2.0)
  current.val.unwrap().width(Is(Some(77.0))) |> ignore
  tree.frame(400.0, 100.0, now=1.0) |> ignore
  assert_eq(current.val.unwrap().rect().2, 77.0)
  assert_false(size.watched())
  assert_eq(tree.bindings_held(), 0)
  tree.dispose()
}

///|
test "a binding pulled in a change is not read again after it is marked and replaced" {
  let size = @signals.signal(1.0)
  let reads = Ref(0)
  let current : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    current.val = Some(root.box(fn(v) {
      v.width(By(fn() {
        reads.val += 1
        Some(size.get() * 10.0)
      })) |> ignore
    }))
  })
  tree.frame(400.0, 100.0, now=0.0) |> ignore
  let before = reads.val
  let seen : Array[Double] = []
  tree.event(1.0, fn() {
    size.set(2.0)
    seen.push(current.val.unwrap().laid_size().0)
    size.set(3.0)
    current.val.unwrap().width(Is(Some(77.0))) |> ignore
    seen.push(current.val.unwrap().laid_size().0)
  })
  assert_eq(seen, [20.0, 77.0])
  assert_eq(reads.val - before, 1)
  tree.frame(400.0, 100.0, now=2.0) |> ignore
  assert_eq((current.val.unwrap().rect().2, reads.val - before), (77.0, 1))
  assert_false(size.watched())
  tree.dispose()
}
