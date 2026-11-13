///|
test "clock reactions during immediate pointer layout do not reenter layout" {
  for settling in [false, true] {
    let width = @signals.signal(20.0, same=fn(a, b) { a == b })
    let armed = Ref(false)
    let reactions = Ref(0)
    let escaped = Ref(false)
    let within = Ref(false)
    let t = Tree::new(
      fn(root) {
        root.lines_up(Is(Some(Start))) |> ignore
        if settling {
          root.laid_before_causes()
        }
        root.box(fn(n) {
          n.width(By(fn() { Some(width.get()) }))
          .height(Is(Some(20.0)))
          |> ignore
          n.reacts(fn() { n.pointer_within() }, fn(v) { within.val = v })
          n.reacts(fn() { n.drawn_past(75.0) }, fn(past) {
            if armed.val {
              reactions.val += 1
              // Bound the broken cycle so a failing test reports an assertion instead of exhausting its stack.
              if reactions.val == 20 {
                escaped.val = true
                n.tree.withins_at.clear()
              } else {
                width.set(if past { 40.0 } else { 30.0 })
              }
            }
          })
        }) |> ignore
      },
      time=fn() { 50.0 },
    )
    t.frame(300.0, 300.0, now=50.0) |> ignore
    t.point_at(35.0, 10.0)
    t.frame(300.0, 300.0, now=50.0) |> ignore
    assert_true(!within.val)
    t.at(100.0)
    armed.val = true
    if settling {
      t.layout_marked_at(0)
      t.settle_now(50.0)
    } else {
      t.event(50.0, fn() { width.set(30.0) })
    }
    assert_true(!escaped.val, msg="clock reactions must not recursively reenter pointer layout")
    assert_true(reactions.val > 0, msg="the clock reaction was exercised")
    assert_true(within.val, msg="the pointer sees the restored 40-point layout before another frame")
    t.frame(300.0, 300.0, now=100.0) |> ignore
    assert_true(within.val, msg="the next frame keeps the pointer in the 40-point layout")
    t.dispose()
  }
}

///|
test "an immediate layout is still at the event's time when the drawn clock is restored" {
  let id : Ref[NodeId?] = Ref(None)
  let t = Tree::new(fn(root) {
    root.lines_up(Is(Some(Start))) |> ignore
    root.box(fn(n) {
      id.val = Some(n.id())
      n.width(By(fn() { Some(if n.drawn_past(75.0) { 40.0 } else { 30.0 }) }))
      .height(Is(Some(20.0)))
      |> ignore
    }) |> ignore
  })
  t.frame(300.0, 300.0, now=50.0) |> ignore
  t.at(100.0)
  t.cause_at = 50.0
  t.laid_now()
  assert_eq(t.nodes[id.val.unwrap().at].lw, 30.0, msg="the event finds the layout at its own time")
  assert_eq(t.drawn_at(), 100.0, msg="the drawn clock was restored")
  t.cause_at = -1.0
  t.frame(300.0, 300.0, now=100.0) |> ignore
  assert_eq(t.nodes[id.val.unwrap().at].lw, 40.0, msg="the later frame uses its own time")
  t.dispose()
}

///|
test "a pointer observer does not lay out a tree before its first frame" {
  let width = @signals.signal(20.0, same=fn(a, b) { a == b })
  let t = Tree::new(fn(root) {
    root.box(fn(n) {
      n.width(By(fn() { Some(width.get()) })).height(Is(Some(20.0))) |> ignore
      n.reacts(fn() { n.pointer_within() }, fn(_) {  })
    }) |> ignore
  })
  let computed = t.work.computes
  t.event(50.0, fn() { width.set(30.0) })
  assert_eq(t.work.computes, computed, msg="there is no window size to lay out yet")
  t.frame(300.0, 300.0, now=50.0) |> ignore
  assert_true(t.work.computes > computed, msg="the first frame lays out the tree")
  t.dispose()
}
