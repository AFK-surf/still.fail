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
test "a sticky cap remembers an overflowing child placed after it was left out" {
  let memory = LayoutCap::new()
  let placed = @signals.signal(false)
  let widths : Array[Double] = []
  let tree = Tree::new(fn(root) {
    root.layout_box(By(fn() { placed.get() }), fn(l, visible) {
      let child = l.child("content", fn(v) {
        v.layout_box(Is(()), fn(inner, _) {
          widths.push(inner.width)
          inner.sticky_cap(memory, 200.0, 100.0) |> ignore
        }) |> ignore
      })
      l.measure(child, 100.0, height=200.0) |> ignore
      if visible { l.place(child, 0.0, 0.0) }
    }) |> ignore
  })
  tree.frame(300.0, 300.0) |> ignore
  assert_false(memory.reached)
  placed.set(true)
  tree.frame(300.0, 300.0) |> ignore
  assert_true(memory.reached, msg="placed overflowing child must reach the cap; measured widths: \{widths}")
  tree.dispose()
}

///|
test "an omitted cap is not remembered when its layout stops using it before placement" {
  let memory = LayoutCap::new()
  let placed = @signals.signal(false)
  let tree = Tree::new(fn(root) {
    root.layout_box(By(fn() { placed.get() }), fn(l, visible) {
      let child = l.child("content", fn(v) {
        v.layout_box(By(fn() { placed.get() }), fn(inner, show) {
          if !show { inner.sticky_cap(memory, 200.0, 100.0) |> ignore }
        }) |> ignore
      })
      l.measure(child, 100.0, height=200.0) |> ignore
      if visible { l.place(child, 0.0, 0.0) }
    }) |> ignore
  })
  tree.frame(300.0, 300.0) |> ignore
  placed.set(true)
  tree.frame(300.0, 300.0) |> ignore
  assert_false(memory.reached)
  tree.dispose()
}

///|
test "an overflowing cap remains uncommitted beneath an omitted ancestor" {
  let memory = LayoutCap::new()
  let placed = @signals.signal(false)
  let tree = Tree::new(fn(root) {
    let holder = root.box(fn(box) {
      box.box(fn(v) {
        v.layout_box(Is(()), fn(inner, _) {
          inner.sticky_cap(memory, 200.0, 100.0) |> ignore
        }) |> ignore
      }).width(Is(Some(100.0))).height(Is(Some(200.0))) |> ignore
    })
    root.layout_box(By(fn() { placed.get() }), fn(l, visible) {
      l.measure(holder, 100.0, height=200.0) |> ignore
      if visible { l.place(holder, 0.0, 0.0) }
    }) |> ignore
  })
  tree.frame(300.0, 300.0) |> ignore
  assert_false(memory.reached)
  placed.set(true)
  tree.frame(300.0, 300.0) |> ignore
  assert_true(memory.reached)
  tree.dispose()
}

///|
test "a sized layout remembers overflow when it is actually placed" {
  let memory = LayoutCap::new()
  let tree = Tree::new(fn(root) {
    let child = root.box(fn(v) {
      v.layout_box(Is(()), sized=true, fn(l, _) {
        l.size_to(l.sticky_cap(memory, 200.0, 100.0))
      }) |> ignore
    })
    root.layout_box(Is(()), fn(l, _) {
      l.measure(child, 100.0) |> ignore
      l.place(child, 0.0, 0.0)
    }) |> ignore
  })
  tree.frame(300.0, 300.0) |> ignore
  assert_true(memory.reached)
  tree.dispose()
}

///|
test "a sticky cap ignores an intrinsic probe after its placed layout" {
  let memory = LayoutCap::new()
  let relayout = @signals.signal(0)
  let child : Ref[View?] = Ref(None)
  let tree = Tree::new(fn(root) {
    let row = root.box(fn(v) {
      child.val = Some(v)
      v.layout_box(Is(()), sized=true, fn(inner, _) {
        let height = inner.sticky_cap(memory, if inner.width < 200.0 { 200.0 } else { 40.0 }, 100.0)
        inner.size_to(height)
      }) |> ignore
    })
    root.layout_box(By(fn() { relayout.get() }), fn(l, _) {
      l.measure(row, 300.0, height=200.0) |> ignore
      l.place(row, 0.0, 0.0)
    }) |> ignore
  })
  tree.frame(300.0, 300.0) |> ignore
  assert_false(memory.reached)
  let row = child.val.unwrap()
  @flex.measured_height(tree.nodes[row.at].flex, 100.0) |> ignore
  relayout.set(1)
  tree.frame(300.0, 300.0) |> ignore
  assert_false(memory.reached, msg="an intrinsic probe at another width was not the placed layout")
  tree.dispose()
}

///|
test "a sticky cap in a child ignores its ancestor's intrinsic probe" {
  let memory = LayoutCap::new()
  let relayout = @signals.signal(0)
  let parent : Ref[View?] = Ref(None)
  let tree = Tree::new(fn(root) {
    let row = root.box(fn(v) {
      parent.val = Some(v)
      v.layout_box(Is(()), sized=true, fn(l, _) {
        let child = l.child("content", fn(part) {
          part.layout_box(Is(()), fn(inner, _) {
            inner.sticky_cap(memory, if inner.width < 200.0 { 200.0 } else { 40.0 }, 100.0) |> ignore
          }) |> ignore
        })
        l.measure(child, l.width, height=100.0) |> ignore
        l.place(child, 0.0, 0.0)
        l.size_to(100.0)
      }) |> ignore
    })
    root.layout_box(By(fn() { relayout.get() }), fn(l, _) {
      l.measure(row, 300.0, height=200.0) |> ignore
      l.place(row, 0.0, 0.0)
    }) |> ignore
  })
  tree.frame(300.0, 300.0) |> ignore
  assert_false(memory.reached)
  let row = parent.val.unwrap()
  @flex.measured_height(tree.nodes[row.at].flex, 100.0) |> ignore
  relayout.set(1)
  tree.frame(300.0, 300.0) |> ignore
  assert_false(memory.reached, msg="placing a child of a probed layout is still only a probe")
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
