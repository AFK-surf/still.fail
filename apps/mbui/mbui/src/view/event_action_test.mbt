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
test "a state reaction snapshots its size at the cause even if it opens again before a frame" {
  let open = @signals.signal(true)
  let height = @signals.signal(120.0)
  let seen : Array[(Double, Double)] = []
  let tree = @view.Tree::new(fn(root) {
    let content = root.box(fn(v) { v.height(By(fn() { Some(height.get()) })) |> ignore })
    root.reacts(fn() { open.get() }, fn(on) {
      if !on {
        root.event_action(fn() { seen.push((root.cause_at(), content.laid_size().1)) })
      }
    })
  }, time=fn() { 0.0 })
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  tree.event(10.0, fn() { height.set(200.0); open.set(false) })
  tree.event(20.0, fn() { open.set(true) })
  assert_eq(seen, [(10.0, 200.0)])
  assert_true(open.get())
}

///|
test "after-event action measures a node opened in that event without a frame" {
  let open = @signals.signal(false)
  let height = @signals.signal(120.0)
  let extent : Ref[@view.View?] = Ref(None)
  let root_ref : Ref[@view.View?] = Ref(None)
  let seen : Array[(Double, Double)] = []
  let before_commit = Ref((false, false))
  let tree = @view.Tree::new(fn(root) {
    root_ref.val = Some(root)
    root.show(fn() { open.get() }, fn(v) {
      extent.val = Some(v)
      v.height(By(fn() { Some(height.get()) })) |> ignore
    })
  }, time=fn() { 0.0 })
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  tree.event(10.0, fn() {
    open.set(true)
    height.set(200.0)
    let before = extent.val is None
    let root : @view.View = root_ref.val.unwrap()
    root.after_event_action(fn() {
      let new_extent : @view.View = extent.val.unwrap()
      seen.push((root.cause_at(), new_extent.laid_size().1))
    })
    before_commit.val = (before, seen.is_empty())
  })
  assert_eq(before_commit.val, (true, true))
  assert_eq(seen, [(10.0, 200.0)])
}

///|
test "after-event action waits for structures even when the reacting watcher runs first" {
  let open = @signals.signal(false)
  let extent : Ref[@view.View?] = Ref(None)
  let seen : Array[(Double, Double)] = []
  let tree = @view.Tree::new(fn(root) {
    root.reacts(fn() { open.get() }, fn(on) {
      if on {
        root.after_event_action(fn() {
          let new_extent : @view.View = extent.val.unwrap()
          seen.push((root.cause_at(), new_extent.laid_size().1))
        })
      }
    })
    root.show(fn() { open.get() }, fn(v) {
      extent.val = Some(v)
      v.height(Is(Some(200.0))) |> ignore
    })
  }, time=fn() { 0.0 })
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  tree.event(10.0, fn() { open.set(true) })
  assert_eq(seen, [(10.0, 200.0)])
}

///|
test "after-event action takes a programmatic open at the current cause, with or without a batch" {
  for batched in [false, true] {
    let now = Ref(0.0)
    let open = @signals.signal(false)
    let root_ref : Ref[@view.View?] = Ref(None)
    let extent : Ref[@view.View?] = Ref(None)
    let seen : Array[(Double, Double)] = []
    let tree = @view.Tree::new(fn(root) {
      root_ref.val = Some(root)
      root.show(fn() { open.get() }, fn(v) {
        extent.val = Some(v)
        v.height(Is(Some(200.0))) |> ignore
      })
    }, time=fn() { now.val })
    tree.frame(390.0, 844.0, now=0.0) |> ignore
    now.val = 50.0
    if batched { @signals.start_batch() }
    open.set(true)
    let root : @view.View = root_ref.val.unwrap()
    root.after_event_action(fn() {
      let new_extent : @view.View = extent.val.unwrap()
      seen.push((root.cause_at(), new_extent.laid_size().1))
    })
    if batched { @signals.end_batch() }
    assert_eq(seen, [(50.0, 200.0)], msg="batched=\{batched}")
  }
}

///|
test "panic an after-event action cannot be started by a binding" {
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(v) {
      v.height(By(fn() {
        @signals.untracked(fn() { root.after_event_action(fn() { v.laid_size() |> ignore }) })
        Some(10.0)
      })) |> ignore
    }) |> ignore
  })
  tree.frame(390.0, 844.0) |> ignore
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

///|
test "panic a before-removal callback in layout cannot start a geometry event" {
  let shown = @signals.signal(true)
  let host : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    host.val = Some(root)
    root.box(fn(v) {
      v.height(Is(Some(20.0))).layout_box(By(fn() { shown.get() }), fn(l, visible) {
        if visible {
          let child = l.child("child", fn(c) {
            c.before_removed(fn() { root.event_action(fn() { c.laid_size() |> ignore }) }) |> ignore
          })
          l.measure(child, l.width) |> ignore
          l.place(child, 0.0, 0.0)
        }
      }) |> ignore
    }) |> ignore
  })
  tree.frame(390.0, 844.0) |> ignore
  tree.event(10.0, fn() { shown.set(false); host.val.unwrap().laid_size() |> ignore })
}
