///|
test "a node leaves for the duration its size says at the closing event, with no frame in between" {
  let open = @signals.signal(true)
  let tall = @signals.signal(120.0)
  let card : Ref[@view.View?] = Ref(None)
  let gone = Ref(0)
  let tree = @view.Tree::new(fn(root) {
    root.show(fn() { open.get() }, leave_by=fn(v) { v.laid_size().1 }, fn(v) {
      card.val = Some(v)
      v.height(By(fn() { Some(tall.get()) })) |> ignore
      v.owns(fn() { gone.val += 1 }) |> ignore
    })
  }, time=fn() { 0.0 })
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  tree.event(10.0, fn() { tall.set(200.0) })
  tree.event(20.0, fn() { open.set(false) })
  assert_eq(card.val.unwrap().leaves_at(), 220.0)
  let end = 300.0
  let progress = Ref((0.0, 0.0))
  tree.event(100.0, fn() {
    let before = card.val.unwrap().going()
    card.val.unwrap().leaves_no_earlier_than(end) |> ignore
    progress.val = (before, card.val.unwrap().going())
  })
  assert_eq(progress.val.0, progress.val.1)
  tree.advance(end - 1.0)
  assert_eq(gone.val, 0)
  tree.advance(end)
  assert_eq(gone.val, 1)
}

///|
test "a sheet owner removed in layout closes using the changed content size" {
  let owner_shown = @signals.signal(true)
  let open = @signals.signal(true)
  let tall = @signals.signal(120.0)
  let card : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(page) {
      page.height(Is(Some(20.0))).layout_box(By(fn() { owner_shown.get() }), fn(l, visible) {
        if visible {
          let owner = l.child("owner", fn(v) { v.owns(fn() { open.set(false) }) |> ignore })
          l.measure(owner, l.width) |> ignore
          l.place(owner, 0.0, 0.0)
        }
      }) |> ignore
    }) |> ignore
    root.show(fn() { open.get() }, leave_by=fn(v) { v.laid_size().1 }, fn(v) {
      card.val = Some(v)
      v.laid_before_causes()
      v.height(By(fn() { Some(tall.get()) })) |> ignore
    })
  }, time=fn() { 0.0 })
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  tree.event(10.0, fn() { tall.set(200.0); owner_shown.set(false) })
  assert_eq(card.val.unwrap().leaves_at(), 210.0)
}

///|
test "a pending size-based leave is cancelled if the node is shown again during layout" {
  let owner_shown = @signals.signal(true)
  let open = @signals.signal(true)
  let card : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(page) {
      page.height(Is(Some(20.0))).layout_box(By(fn() { owner_shown.get() }), fn(l, visible) {
        if visible {
          let owner = l.child("owner", fn(v) {
            v.owns(fn() { open.set(false); open.set(true) }) |> ignore
          })
          l.measure(owner, l.width) |> ignore
          l.place(owner, 0.0, 0.0)
        }
      }) |> ignore
    }) |> ignore
    root.show(fn() { open.get() }, leave_by=fn(v) { v.laid_size().1 }, fn(v) {
      card.val = Some(v)
      v.laid_before_causes()
      v.height(Is(Some(120.0))) |> ignore
    })
  }, time=fn() { 0.0 })
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  tree.event(10.0, fn() { owner_shown.set(false) })
  assert_true(card.val.unwrap().alive())
  assert_eq(card.val.unwrap().leaves_at(), -1.0)
}
