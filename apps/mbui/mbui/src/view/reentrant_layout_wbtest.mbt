///|
test "a host's change notification while layout changes the drawn clock does not reenter layout" {
  for change_in_layout in [false, true] {
    let width = @signals.signal(20.0, same=fn(a, b) { a == b })
    let due = @signals.signal(0)
    let host_calls = Ref(0)
    let armed = Ref(false)
    let changed = Ref(false)
    let within = Ref(false)
    let id : Ref[NodeId?] = Ref(None)
    let t = Tree::new(
      fn(root) {
        root.lines_up(Is(Some(Start))) |> ignore
        root.box(fn(n) {
          id.val = Some(n.id())
          n.width(By(fn() { Some(width.get()) }))
          .height(Is(Some(20.0)))
          .ground(Is(1L))
          .alpha(By(fn() { if n.drawn_past(75.0) { 0.5 } else { 1.0 } }))
          |> ignore
          n.reacts(fn() { n.pointer_within() }, fn(on) { within.val = on })
          n.reacts(fn() { due.get() }, fn(_) {
            if armed.val && change_in_layout && n.tree.standing && !changed.val {
              changed.val = true
              width.set(40.0)
            }
          })
        }) |> ignore
      },
      time=fn() { 50.0 },
    )
    t.frame(300.0, 300.0, now=0.0) |> ignore
    t.point_at(if change_in_layout { 35.0 } else { 25.0 }, 10.0)
    t.frame(300.0, 300.0, now=0.0) |> ignore
    assert_true(!within.val, msg="outside before the width changes")
    // As the real host does, publish that the tree has work as a signal; what reads it can itself change the tree.
    t.on_due(fn() {
      host_calls.val += 1
      // Stop the broken feedback loop at 20 so the assertion fails without overflowing the test process's stack.
      if host_calls.val < 20 {
        due.set(due.untracked() + 1)
      }
    })
    // A frame is to be shown at 100, while the event was at 50, on opposite sides of the look's change at 75.
    t.at(100.0)
    armed.val = true
    t.event(50.0, fn() { width.set(30.0) })
    assert_true(host_calls.val < 20, msg="host notifications did not recursively enter layout: \{host_calls.val}")
    if change_in_layout {
      assert_true(changed.val, msg="the host's notification changed the width during layout")
    }
    assert_true(within.val, msg="the pointer was told of the final width before another frame")
    assert_eq(t.drawn_of(id.val.unwrap()).unwrap().w, if change_in_layout { 40.0 } else { 30.0 })
    t.frame(300.0, 300.0, now=50.0) |> ignore
    assert_eq(t.drawn_of(id.val.unwrap()).unwrap().alpha, 0.5, msg="the look is of the drawn clock")
    let told = host_calls.val
    t.event(60.0, fn() { width.set(10.0) })
    assert_true(host_calls.val > told, msg="a later change tells the host again")
    assert_true(!within.val, msg="the pointer is told of that change before another frame")
  }
}

///|
test "a host that draws while being told is told again for work made after that frame" {
  let width = @signals.signal(20.0, same=fn(a, b) { a == b })
  let id : Ref[NodeId?] = Ref(None)
  let t = Tree::new(fn(root) {
    root.box(fn(n) {
      id.val = Some(n.id())
      n.width(By(fn() { Some(width.get()) })).height(Is(Some(20.0))).ground(Is(1L)) |> ignore
    }) |> ignore
  })
  t.frame(300.0, 300.0, now=0.0) |> ignore
  let host_calls = Ref(0)
  t.on_due(fn() {
    host_calls.val += 1
    if host_calls.val == 1 {
      t.frame(300.0, 300.0, now=0.0) |> ignore
      width.set(40.0)
    }
  })
  width.set(30.0)
  assert_eq(host_calls.val, 2, msg="a frame consumed the first notification; the later work has its own")
  t.frame(300.0, 300.0, now=0.0) |> ignore
  assert_eq(t.drawn_of(id.val.unwrap()).unwrap().w, 40.0)
}
