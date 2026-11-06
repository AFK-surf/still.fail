///|
test "a sticky cap remembers the placed measurement, not an earlier provisional one" {
  let memory = LayoutCap::new()
  let widths : Array[Double] = []
  let row : Ref[View?] = Ref(None)
  let tree = Tree::new(fn(root) {
    let child = root.box(fn(box) {
      box.layout_box(Is(()), fn(l, _) {
        widths.push(l.width)
        let height = l.sticky_cap(memory, if l.width < 200.0 { 200.0 } else { 40.0 }, 100.0)
        let part = l.child("content", fn(v) { row.val = Some(v) })
        l.measure(part, l.width, height~) |> ignore
        l.place(part, 0.0, 0.0)
      }) |> ignore
    })
    root.layout_box(Is(()), fn(l, _) {
      l.measure(child, 100.0, height=200.0) |> ignore
      l.measure(child, 300.0, height=200.0) |> ignore
      l.place(child, 0.0, 0.0)
    }) |> ignore
  })
  tree.frame(300.0, 300.0) |> ignore
  assert_eq(widths, [100.0, 300.0])
  assert_false(memory.reached)
  assert_eq(row.val.unwrap().rect().3, 40.0)
  tree.dispose()
}

///|
test "a sticky cap ignores a measured child that was not placed" {
  let memory = LayoutCap::new()
  let placed = @signals.signal(false)
  let tree = Tree::new(fn(root) {
    root.layout_box(By(fn() { placed.get() }), fn(l, visible) {
      let child = l.child("content", fn(v) {
        v.layout_box(Is(()), fn(inner, _) {
          inner.sticky_cap(memory, if inner.width < 200.0 { 200.0 } else { 40.0 }, 100.0) |> ignore
        }) |> ignore
      })
      l.measure(child, if visible { 300.0 } else { 100.0 }, height=200.0) |> ignore
      if visible { l.place(child, 0.0, 0.0) }
    }) |> ignore
  })
  tree.frame(300.0, 300.0) |> ignore
  assert_false(memory.reached)
  placed.set(true)
  tree.frame(300.0, 300.0) |> ignore
  assert_false(memory.reached)
  tree.dispose()
}

///|
test "a sticky cap ignores a provisional overflow when a previous width is restored" {
  let memory = LayoutCap::new()
  let row : Ref[View?] = Ref(None)
  let tree = Tree::new(fn(root) {
    let child = root.box(fn(box) {
      box.layout_box(Is(()), fn(l, _) {
        let height = l.sticky_cap(memory, if l.width < 200.0 { 200.0 } else { 40.0 }, 100.0)
        let part = l.child("content", fn(v) { row.val = Some(v) })
        l.measure(part, l.width, height~) |> ignore
        l.place(part, 0.0, 0.0)
      }) |> ignore
    })
    root.layout_box(Is(()), fn(l, _) {
      l.measure(child, 300.0, height=200.0) |> ignore
      l.measure(child, 100.0, height=200.0) |> ignore
      l.measure(child, 300.0, height=200.0) |> ignore
      l.place(child, 0.0, 0.0)
    }) |> ignore
  })
  tree.frame(300.0, 300.0) |> ignore
  assert_eq(row.val.unwrap().rect().3, 40.0)
  assert_false(memory.reached)
  tree.dispose()
}

///|
test "two sticky caps in one layout keep their own overflow" {
  let first = LayoutCap::new()
  let second = LayoutCap::new()
  let sizes = Ref((0.0, 0.0))
  let tree = Tree::new(fn(root) {
    root.layout_box(Is(()), fn(l, _) {
      sizes.val = (l.sticky_cap(first, 200.0, 100.0), l.sticky_cap(second, 40.0, 100.0))
    }) |> ignore
  })
  tree.frame(300.0, 300.0) |> ignore
  assert_eq(sizes.val, (100.0, 40.0))
  assert_eq(tree.work.computes, 1, msg="remembering a cap does not schedule another layout")
  assert_true(first.reached)
  assert_false(second.reached)
  tree.dispose()
}
