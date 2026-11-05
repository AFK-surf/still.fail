///|
test "intrinsic sibling height is consumed in one layout without geometry publication" {
  let size = @signals.signal(40.0, same=fn(a, b) { a == b })
  let source : Ref[View?] = Ref(None)
  let target : Ref[View?] = Ref(None)
  let tree = Tree::new(fn(root) {
    let s = root.box(fn(s) {
      s.box(fn(child) { child.height(By(fn() { Some(size.get()) })) |> ignore }) |> ignore
    })
    source.val = Some(s)
    target.val = Some(root.box(fn(t) {
      t.height_measured(Is(s.natural_height(300.0).plus(height(12.0)))) |> ignore
    }))
  })
  defer { tree.dispose() }
  tree.frame(300.0, 300.0, now=0.0) |> ignore
  assert_eq(target.val.unwrap().laid_size().1, 52.0)
  assert_true(tree.sized.is_empty())
  let before = tree.work.computes
  size.set(80.0)
  tree.frame(300.0, 300.0, now=100.0) |> ignore
  assert_eq(target.val.unwrap().laid_size().1, 92.0)
  assert_eq(tree.work.computes - before, 1)
  assert_true(tree.sized.is_empty())
  assert_false(tree.height_cycle(target.val.unwrap().id(), [source.val.unwrap().id()]))
  assert_true(tree.height_cycle(source.val.unwrap().id(), [target.val.unwrap().id()]))
}

///|
test "a geometry source cannot contain its consumer and disposal removes its dependency edges" {
  let holder : Ref[View?] = Ref(None)
  let target : Ref[View?] = Ref(None)
  let tree = Tree::new(fn(root) {
    holder.val = Some(root)
    let s = root.box(fn(s) { s.height(Is(Some(40.0))) |> ignore })
    target.val = Some(root.box(fn(t) { t.height_measured(Is(s.natural_height(300.0))) |> ignore }))
  })
  assert_true(tree.height_cycle(target.val.unwrap().id(), [holder.val.unwrap().id()]))
  tree.dispose()
  assert_true(tree.height_users.is_empty())
  assert_true(tree.height_sources.is_empty())
}
