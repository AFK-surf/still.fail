// Geometry is an output of layout. Reading it may paint or answer the next input, but cannot feed another
// layout or rebuild the tree while that output is being published.

///|
test "panic a published size cannot resize another node in the same layout" {
  let t = Tree::new(fn(root) {
    let a = root.box(fn(a) { a.height(Is(Some(40.0))) |> ignore })
    root.box(fn(b) {
      b.height(By(fn() { Some(a.laid_size_told().map(fn(s) { s.1 }).unwrap_or(0.0)) })) |> ignore
    }) |> ignore
  })
  t.frame(200.0, 300.0) |> ignore
}

///|
test "panic a published size cannot create children in the same layout" {
  let t = Tree::new(fn(root) {
    let a = root.box(fn(a) { a.height(Is(Some(40.0))) |> ignore })
    root.show(fn() { a.laid_size_told() is Some(_) }, fn(b) {
      b.height(Is(Some(20.0))) |> ignore
    })
  })
  t.frame(200.0, 300.0) |> ignore
}

///|
test "panic measuring content cannot dirty a sibling's layout" {
  let t = Tree::new(fn(root) {
    let a = root.box(fn(a) { a.height(Is(Some(20.0))) |> ignore })
    root.box(fn(b) {
      b.measured(Is(0), fn(_, _) {
        a.height(Is(Some(40.0))) |> ignore
        (20.0, 20.0)
      }) |> ignore
    }) |> ignore
  })
  t.frame(200.0, 300.0) |> ignore
}

///|
test "published geometry can paint in the same frame without computing layout again" {
  let height = @signals.signal(40.0, same=fn(a, b) { a == b })
  let node : Ref[NodeId?] = Ref(None)
  let t = Tree::new(fn(root) {
    let a = root.box(fn(a) { a.height(By(fn() { Some(height.get()) })) |> ignore })
    root.box(fn(b) {
      node.val = Some(b.id())
      b.height(Is(Some(20.0))).ground(Is(0x112233ffL))
      .alpha(By(fn() { a.laid_size_told().map(fn(s) { s.1 / 100.0 }).unwrap_or(0.0) })) |> ignore
    }) |> ignore
  })
  let before = t.work.computes
  t.frame(200.0, 300.0, now=0.0) |> ignore
  assert_eq(t.work.computes - before, 1, msg="one layout produces the whole frame")
  assert_eq(t.drawn_of(node.val.unwrap()).unwrap().alpha, 0.4)
  height.set(60.0)
  let before = t.work.computes
  t.frame(200.0, 300.0, now=10.0) |> ignore
  assert_eq(t.work.computes - before, 1)
  assert_eq(t.drawn_of(node.val.unwrap()).unwrap().alpha, 0.6)
  t.dispose()
}

///|
test "an input may read the preceding layout to change the next one" {
  let a : Ref[View?] = Ref(None)
  let b : Ref[View?] = Ref(None)
  let t = Tree::new(fn(root) {
    a.val = Some(root.box(fn(n) {
      n.height(Is(Some(40.0))) |> ignore
      n.laid_size_told() |> ignore
    }))
    b.val = Some(root.box(fn(n) { n.height(Is(Some(20.0))) |> ignore }))
  })
  t.frame(200.0, 300.0, now=0.0) |> ignore
  t.event(10.0, fn() {
    b.val.unwrap().height(Is(a.val.unwrap().laid_size_told().map(fn(s) { s.1 }))) |> ignore
  })
  t.frame(200.0, 300.0, now=10.0) |> ignore
  assert_eq(t.nodes[b.val.unwrap().id().at].lh, 40.0)
  t.dispose()
}
