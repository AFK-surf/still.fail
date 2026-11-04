///|
test "a descendant uses its holder's current height in the same layout, including after resize" {
  let height = @signals.signal(80.0)
  let inset = @signals.signal(10.0)
  let leaf : Ref[View?] = Ref(None)
  let t = Tree::new(fn(root) {
    root.box(fn(parent) {
      parent.width(Is(Some(300.0))).height(By(fn() { Some(height.get()) })) |> ignore
      let context = parent.height_context()
      parent.box(fn(middle) {
        middle.box(fn(node) {
          leaf.val = Some(node)
          let previous : Ref[Double?] = Ref(None)
          context.bind(node, By(fn() { inset.get() }), fn(h, offset) {
            let wanted = h.unwrap_or(0.0) / 2.0 - offset
            if previous.val == Some(wanted) { return false }
            previous.val = Some(wanted)
            node.height(Is(Some(wanted))) |> ignore
            true
          })
        }) |> ignore
      }) |> ignore
    }) |> ignore
  })
  t.frame(300.0, 300.0, now=0.0) |> ignore
  let id = leaf.val.unwrap().id()
  assert_eq((leaf.val.unwrap().rect().3, t.work.computes), (30.0, 1))
  height.set(200.0)
  t.frame(300.0, 300.0, now=10.0) |> ignore
  assert_eq((leaf.val.unwrap().rect().3, t.work.computes), (90.0, 2))
  inset.set(20.0)
  t.frame(300.0, 300.0, now=20.0) |> ignore
  assert_eq((leaf.val.unwrap().rect().3, t.work.computes), (80.0, 3))
  assert_eq(leaf.val.unwrap().id(), id)
  t.dispose()
}

///|
test "a lazy child receives the current height before its first measurement" {
  let row : Ref[View?] = Ref(None)
  let t = Tree::new(fn(root) {
    root.box(fn(parent) {
      parent.width(Is(Some(300.0))).height(Is(Some(100.0))) |> ignore
      let context = parent.height_context()
      parent.layout_box(Is(0), fn(l, _) {
        let child = l.child("row", fn(n) {
          row.val = Some(n)
          context.bind(n, By(fn() { 10.0 }), fn(h, inset) {
            n.height(Is(Some(h.unwrap_or(0.0) - inset))) |> ignore
            true
          })
        })
        l.measure(child, l.width) |> ignore
        l.place(child, 0.0, 0.0)
      }) |> ignore
    }) |> ignore
  })
  t.frame(300.0, 200.0, now=0.0) |> ignore
  assert_eq((row.val.unwrap().rect().3, t.work.computes), (90.0, 1))
  t.dispose()
}
