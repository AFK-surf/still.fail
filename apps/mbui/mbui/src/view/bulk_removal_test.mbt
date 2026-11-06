///|
test "a keyed row's cleanup sees earlier removals and its own node still held" {
  let items = @signals.signal([1, 2, 3])
  let slot : Ref[@view.View?] = Ref(None)
  let sizes : Array[Int] = []
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(row) {
      row.each(fn() { items.get() }, fn(k) { k }, fn(v, _) {
        slot.val = v.parent()
        v.owns(fn() { sizes.push(slot.val.unwrap().kids().length()) }) |> ignore
      })
    }) |> ignore
  })
  tree.event(1.0, fn() { items.set([]) })
  assert_eq(sizes, [3, 2, 1])
  assert_eq(slot.val.unwrap().kids().length(), 0)
  tree.dispose()
}

///|
test "a keyed row's cleanup can read layout after each earlier removal" {
  let items = @signals.signal([1, 2, 3])
  let last : Ref[@view.View?] = Ref(None)
  let seen : Array[Double] = []
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(row) {
      row.row(Is(true)).width(Is(Some(300.0))).height(Is(Some(20.0))) |> ignore
      row.each(fn() { items.get() }, fn(k) { k }, fn(v, item) {
        let k = item.get()
        v.width(Is(Some(20.0))).height(Is(Some(20.0))) |> ignore
        if k == 3 { last.val = Some(v) }
        v.owns(fn() {
          if k < 3 { seen.push(last.val.unwrap().laid_window_now().0) }
        }) |> ignore
      })
    }) |> ignore
  })
  tree.frame(300.0, 100.0, now=0.0) |> ignore
  tree.event(1.0, fn() { items.set([]) })
  assert_eq(seen, [40.0, 20.0])
  tree.dispose()
}

///|
test "a keyed row's cleanup may make another box while earlier rows are being removed" {
  let items = @signals.signal([1, 2, 3])
  let last : Ref[@view.View?] = Ref(None)
  let extra : Ref[@view.View?] = Ref(None)
  let chosen = Ref(0)
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(row) {
      row.row(Is(true)).width(Is(Some(300.0))).height(Is(Some(20.0))) |> ignore
      row.each(fn() { items.get() }, fn(k) { k }, fn(v, item) {
        let k = item.get()
        v.width(Is(Some(20.0))).height(Is(Some(20.0))).on_press(fn() { chosen.val = k }) |> ignore
        if k == 3 { last.val = Some(v) }
        v.owns(fn() {
          if k == 2 {
            extra.val = Some(row.box(fn(x) {
              x.width(Is(Some(20.0))).height(Is(Some(20.0))).on_press(fn() { chosen.val = 4 }) |> ignore
            }))
          }
        }) |> ignore
      })
    }) |> ignore
  })
  tree.frame(300.0, 100.0, now=0.0) |> ignore
  tree.event(1.0, fn() { items.set([3]) })
  tree.frame(300.0, 100.0, now=1.0) |> ignore
  assert_eq(last.val.unwrap().rect().0, 0.0)
  assert_eq(extra.val.unwrap().rect().0, 20.0)
  assert_true(tree.press(10.0, 10.0))
  assert_eq(chosen.val, 3)
  assert_true(tree.press(30.0, 10.0))
  assert_eq(chosen.val, 4)
  tree.dispose()
}

///|
test "one keyed removal can change another list from its cleanup" {
  let outer = @signals.signal([1, 2])
  let inner = @signals.signal([1, 2])
  let last : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(column) {
      column.each(fn() { outer.get() }, fn(k) { k }, fn(v, item) {
        let k = item.get()
        v.owns(fn() { if k == 1 { inner.set([2]) } }) |> ignore
      })
      column.box(fn(row) {
        row.row(Is(true)).width(Is(Some(100.0))).height(Is(Some(20.0))) |> ignore
        row.each(fn() { inner.get() }, fn(k) { k }, fn(v, item) {
          v.width(Is(Some(20.0))).height(Is(Some(20.0))) |> ignore
          if item.get() == 2 { last.val = Some(v) }
        })
      }) |> ignore
    }) |> ignore
  })
  tree.frame(100.0, 100.0, now=0.0) |> ignore
  assert_eq(last.val.unwrap().rect().0, 20.0)
  tree.event(1.0, fn() { outer.set([]) })
  assert_eq(last.val.unwrap().laid_window_now().0, 0.0)
  tree.frame(100.0, 100.0, now=1.0) |> ignore
  assert_eq(last.val.unwrap().rect().0, 0.0)
  tree.dispose()
}

///|
fn removal_with_frames(between : Bool) -> (Array[Int], Double, Int) raise {
  let items = @signals.signal([1, 2, 3, 4])
  let last : Ref[@view.View?] = Ref(None)
  let released : Array[Int] = []
  let chosen = Ref(0)
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(row) {
      row.row(Is(true)).width(Is(Some(100.0))).height(Is(Some(20.0))) |> ignore
      row.each(fn() { items.get() }, fn(k) { k }, fn(v, item) {
        let k = item.get()
        if k == 4 { last.val = Some(v) }
        v.width(Is(Some(20.0))).height(Is(Some(20.0)))
        .on_press(fn() { chosen.val = k })
        .owns(fn() { released.push(k) }) |> ignore
      })
    }) |> ignore
  })
  tree.frame(100.0, 100.0, now=0.0) |> ignore
  tree.event(1.0, fn() { items.set([1, 3, 4]) })
  if between { tree.frame(100.0, 100.0, now=1.0) |> ignore }
  tree.event(2.0, fn() { items.set([1, 4]) })
  tree.frame(100.0, 100.0, now=2.0) |> ignore
  let x = last.val.unwrap().rect().0
  assert_true(tree.press(30.0, 10.0))
  let result = (released.copy(), x, chosen.val)
  tree.dispose()
  result
}

///|
test "keyed removals have the same cleanup order, layout and hit with a frame between or none" {
  assert_eq(removal_with_frames(false), ([2, 3], 20.0, 4))
  assert_eq(removal_with_frames(true), removal_with_frames(false))
}
