///|
test "an overlay in a measured child appears when that child is later placed" {
  let show = @signals.signal(false)
  let width = @signals.signal(100.0)
  let pulse = @signals.signal(0)
  let overlay : Ref[View?] = Ref(None)
  let measured = Ref(0)
  let pressed = Ref(0)
  let tree = Tree::new(fn(root) {
    let child = root.box(fn(v) {
      v.box(fn(words) {
        words.measured(Is(()), fn(_, w) { measured.val += 1; (w.unwrap_or(20.0), 20.0) }) |> ignore
      }) |> ignore
      overlay.val = Some(v.box(fn(layer) {
        layer.over(Is(true)).ground(Is(0x112233ffL)).on_press(fn() { pressed.val += 1 }) |> ignore
      }))
    })
    root.layout_box(By(fn() { (show.get(), width.get(), pulse.get()) }), fn(l, state) {
      let (visible, w, _) = state
      l.measure(child, w, height=200.0) |> ignore
      if visible { l.place(child, 25.0, 30.0) }
    }) |> ignore
  })
  tree.frame(300.0, 300.0) |> ignore
  let layer = overlay.val.unwrap()
  assert_true(tree.out_at(layer.at))
  assert_false(tree.press(50.0, 50.0))
  let count = measured.val
  assert_true(count > 0)
  pulse.set(1)
  tree.frame(300.0, 300.0) |> ignore
  assert_eq(measured.val, count, msg="an unplaced child keeps its measured layout")
  show.set(true)
  let before = tree.work().computes
  tree.frame(300.0, 300.0) |> ignore
  assert_eq(tree.work().computes - before, 1, msg="placing the child takes one layout")
  assert_eq(layer.rect(), (25.0, 30.0, 100.0, 200.0))
  assert_true(tree.drawn().iter().any(fn(d) { d.id == layer.id() }))
  let drawn = tree.drawn_of(layer.id()).unwrap()
  assert_eq((drawn.x, drawn.y, drawn.w, drawn.h), (25.0, 30.0, 100.0, 200.0))
  assert_true(tree.press(50.0, 50.0))
  assert_eq(pressed.val, 1)
  assert_eq(measured.val, count, msg="revealing an unchanged child reuses its measured layout")
  assert_false(tree.frame(300.0, 300.0), msg="no extra frame is owed")
  width.set(140.0)
  tree.frame(300.0, 300.0) |> ignore
  assert_eq(layer.rect(), (25.0, 30.0, 140.0, 200.0))
  show.set(false)
  width.set(160.0)
  tree.frame(300.0, 300.0) |> ignore
  assert_false(tree.press(50.0, 50.0))
  show.set(true)
  tree.frame(300.0, 300.0) |> ignore
  assert_eq(layer.rect(), (25.0, 30.0, 160.0, 200.0))
  assert_true(tree.press(50.0, 50.0))
  assert_eq(pressed.val, 2)
  tree.dispose()
}

///|
test "a nested measured child can be revealed after its enclosing child" {
  let outer = @signals.signal(false)
  let inner = @signals.signal(false)
  let overlay : Ref[View?] = Ref(None)
  let pressed = Ref(0)
  let tree = Tree::new(fn(root) {
    let container = root.box(fn(box) {
      let row = box.box(fn(r) {
        overlay.val = Some(r.box(fn(layer) {
          layer.over(Is(true)).ground(Is(0x112233ffL)).on_press(fn() { pressed.val += 1 }) |> ignore
        }))
      })
      box.layout_box(By(fn() { inner.get() }), fn(l, visible) {
        l.measure(row, 80.0, height=100.0) |> ignore
        if visible { l.place(row, 10.0, 15.0) }
      }) |> ignore
    })
    root.layout_box(By(fn() { outer.get() }), fn(l, visible) {
      l.measure(container, 150.0, height=200.0) |> ignore
      if visible { l.place(container, 20.0, 30.0) }
    }) |> ignore
  })
  tree.frame(300.0, 300.0) |> ignore
  outer.set(true)
  tree.frame(300.0, 300.0) |> ignore
  let layer = overlay.val.unwrap()
  assert_true(tree.out_at(layer.at))
  assert_false(tree.press(50.0, 60.0))
  inner.set(true)
  let before = tree.work().computes
  tree.frame(300.0, 300.0) |> ignore
  assert_eq(tree.work().computes - before, 1)
  assert_eq(layer.rect(), (30.0, 45.0, 80.0, 100.0))
  let drawn = tree.drawn_of(layer.id()).unwrap()
  assert_eq((drawn.x, drawn.y, drawn.w, drawn.h), (30.0, 45.0, 80.0, 100.0))
  assert_true(tree.press(50.0, 60.0))
  assert_eq(pressed.val, 1)
  assert_false(tree.frame(300.0, 300.0))
  tree.dispose()
}

///|
test "a measured child without overlays publishes its descendants when placed" {
  let show = @signals.signal(false)
  let row : Ref[View?] = Ref(None)
  let pressed = Ref(0)
  let tree = Tree::new(fn(root) {
    let child = root.box(fn(v) {
      row.val = Some(v.box(fn(r) {
        r.height(Is(Some(40.0))).ground(Is(0x112233ffL)).on_press(fn() { pressed.val += 1 }) |> ignore
      }))
    })
    root.layout_box(By(fn() { show.get() }), fn(l, visible) {
      l.measure(child, 100.0, height=200.0) |> ignore
      if visible { l.place(child, 25.0, 30.0) }
    }) |> ignore
  })
  tree.frame(300.0, 300.0) |> ignore
  show.set(true)
  tree.frame(300.0, 300.0) |> ignore
  let r = row.val.unwrap()
  let drawn = tree.drawn_of(r.id()).unwrap()
  assert_eq((drawn.x, drawn.y, drawn.w, drawn.h), (25.0, 30.0, 100.0, 40.0))
  assert_true(tree.press(50.0, 50.0))
  assert_eq(pressed.val, 1)
  tree.dispose()
}
