///|
test "event action snapshots two changed sizes before a layout-removed owner closes both" {
  let owner_shown = @signals.signal(true)
  let first_open = @signals.signal(true)
  let second_open = @signals.signal(true)
  let first_h = @signals.signal(120.0)
  let second_h = @signals.signal(150.0)
  let sink = @signals.signal(0.0)
  let host : Ref[@view.View?] = Ref(None)
  let first : Ref[@view.View?] = Ref(None)
  let second : Ref[@view.View?] = Ref(None)
  let close = fn() {
    let root : @view.View = host.val.unwrap()
    root.event_action(fn() {
      let a : @view.View = first.val.unwrap()
      let b : @view.View = second.val.unwrap()
      let ah = a.laid_size().1
      let bh = b.laid_size().1
      let both = if ah > bh { ah } else { bh }
      sink.set(both)
      first_open.set(false)
      second_open.set(false)
    })
  }
  let tree = @view.Tree::new(fn(root) {
    host.val = Some(root)
    root.box(fn(page) {
      page.height(Is(Some(20.0))).layout_box(By(fn() { owner_shown.get() }), fn(l, visible) {
        if visible {
          let owner = l.child("owner", fn(v) { v.owns(close) |> ignore })
          l.measure(owner, l.width) |> ignore
          l.place(owner, 0.0, 0.0)
        }
      }) |> ignore
    }) |> ignore
    root.show(fn() { first_open.get() }, leave_by=fn(v) {
      let h = v.laid_size().1
      let down = sink.get()
      if h > down { h } else { down }
    }, fn(v) {
      first.val = Some(v)
      v.laid_before_causes()
      v.height(By(fn() { Some(first_h.get()) })) |> ignore
    })
    root.show(fn() { second_open.get() }, leave_by=fn(v) {
      let h = v.laid_size().1
      let down = sink.get()
      if h > down { h } else { down }
    }, fn(v) {
      second.val = Some(v)
      v.height(By(fn() { Some(second_h.get()) })) |> ignore
    })
  }, time=fn() { 0.0 })
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  tree.event(10.0, fn() { first_h.set(200.0); second_h.set(300.0); owner_shown.set(false) })
  assert_false(first_open.get())
  assert_false(second_open.get())
  assert_eq(sink.get(), 300.0)
  assert_eq((first.val.unwrap().leaves_at(), second.val.unwrap().leaves_at()), (310.0, 310.0))
}

///|
test "panic event action cannot be started in a tracked binding, even through untracked" {
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(v) {
      v.height(By(fn() {
        @signals.untracked(fn() { root.event_action(fn() { v.laid_size() |> ignore }) })
        Some(10.0)
      })) |> ignore
    }) |> ignore
  })
  tree.frame(390.0, 844.0) |> ignore
}

///|
test "panic event action cannot be started by layout itself" {
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(v) {
      v.height(Is(Some(20.0))).layout_box(Is(()), fn(_, _) {
        root.event_action(fn() { v.laid_size() |> ignore })
      }) |> ignore
    }) |> ignore
  })
  tree.frame(390.0, 844.0) |> ignore
}
