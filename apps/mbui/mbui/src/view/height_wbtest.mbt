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

///|
test "changing an intrinsic expression under its minimum does not relayout the tree" {
  let extra = @signals.signal(0.0, same=fn(a, b) { a == b })
  let target : Ref[View?] = Ref(None)
  let follower : Ref[View?] = Ref(None)
  let tree = Tree::new(fn(root) {
    let source = root.box(fn(v) { v.height(Is(Some(40.0))) |> ignore })
    let t = root.box(fn(v) {
      v.height_measured(By(fn() {
        source.natural_height(300.0).plus(height(extra.get())).maximum(height(100.0))
      })) |> ignore
    })
    target.val = Some(t)
    follower.val = Some(root.box(fn(v) {
      v.height_measured(Is(t.natural_height(300.0).plus(height(12.0)))) |> ignore
    }))
  })
  defer { tree.dispose() }
  tree.frame(300.0, 300.0, now=0.0) |> ignore
  let before = tree.work.computes
  extra.set(20.0)
  tree.frame(300.0, 300.0, now=100.0) |> ignore
  assert_eq(target.val.unwrap().laid_size().1, 100.0)
  assert_eq(follower.val.unwrap().laid_size().1, 112.0)
  assert_eq(tree.work.computes, before)
  extra.set(80.0)
  tree.frame(300.0, 300.0, now=200.0) |> ignore
  assert_eq(target.val.unwrap().laid_size().1, 120.0)
  assert_eq(follower.val.unwrap().laid_size().1, 132.0)
  assert_eq(tree.work.computes - before, 1)
}

///|
test "intrinsic reads see changed source content even without another frame moment" {
  let size = @signals.signal(40.0, same=fn(a, b) { a == b })
  let target : Ref[View?] = Ref(None)
  let tree = Tree::new(fn(root) {
    let source = root.box(fn(v) { v.height(By(fn() { Some(size.get()) })) |> ignore })
    target.val = Some(root.box(fn(v) { v.height_measured(Is(source.natural_height(300.0))) |> ignore }))
  })
  defer { tree.dispose() }
  tree.frame(300.0, 300.0, now=100.0) |> ignore
  for h in [80.0, 30.0, 90.0] {
    size.set(h)
    tree.frame(300.0, 300.0, now=100.0) |> ignore
    assert_eq(target.val.unwrap().laid_size().1, h)
  }
}
