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

///|
test "a bar notification that changes its own width is laid out and told again in the same change" {
  let width = @signals.signal(100.0, same=fn(a, b) { a == b })
  let seen : Array[Bool] = []
  let id : Ref[NodeId?] = Ref(None)
  let t = Tree::new(fn(root) {
    root.lines_up(Is(Some(Start))) |> ignore
    root.box(fn(n) {
      id.val = Some(n.id())
      n.width(By(fn() { Some(width.get()) })).height(Is(Some(100.0))) |> ignore
      n.reacts(fn() { n.bar_near(10.0) }, fn(near) {
        seen.push(near)
        if near { width.set(200.0) }
      })
    }) |> ignore
  })
  t.frame(300.0, 200.0, now=0.0) |> ignore
  seen.clear()
  // A stationary pointer is newly allowed by a modal change. Set the location without delivering a separate move;
  // the modal notification itself must deliver the bar change and any geometry that change causes.
  t.pointer_xy = (95.0, 10.0)
  t.event(10.0, fn() { t.modals_told() })
  assert_eq(t.nodes[id.val.unwrap().at].lw, 200.0, msg="the bar callback's width was placed before return; seen=\{seen}")
  assert_eq(seen, [true, false], msg="moving the edge away from the stationary pointer was told too")
  t.dispose()
}


///|
test "a bar notification that changes its own width keeps the layout pass guard" {
  let faults : Array[String] = []
  faults_stop.val = false
  fault_told.val = Some(fn(s) { faults.push(s) })
  defer {
    faults_stop.val = true
    fault_told.val = None
  }
  let width = @signals.signal(100.0, same=fn(a, b) { a == b })
  let armed = Ref(false)
  let steps = Ref(0)
  let t = Tree::new(fn(root) {
    root.lines_up(Is(Some(Start))) |> ignore
    root.box(fn(n) {
      n.width(By(fn() { Some(width.get()) })).height(Is(Some(100.0))) |> ignore
      n.reacts(fn() { n.bar_near(10.0) }, fn(near) {
        if armed.val {
          steps.val += 1
          if steps.val < 100 { width.set(if near { 200.0 } else { 100.0 }) }
        }
      })
    }) |> ignore
  })
  t.frame(300.0, 200.0, now=0.0) |> ignore
  t.pointer_xy = (95.0, 10.0)
  armed.val = true
  t.event(10.0, fn() { t.modals_told() })
  println("bar feedback: steps=\{steps.val}, faults=\{faults}, due=\{t.due}, layout_due=\{t.layout_due}")
  assert_true(steps.val > 1 && steps.val < 100, msg="feedback must stop at the layout guard, steps=\{steps.val}")
  assert_true(faults.iter().any(fn(s) { s.contains("layout passes in one") }), msg="\{faults}")
  t.dispose()
}
