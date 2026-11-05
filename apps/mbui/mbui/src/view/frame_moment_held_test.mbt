// A frame is worked out as of its one moment (Tree::now_of_change): what it lays out and what is placed by where that
// puts things, however long the working out takes on the host's clock, which goes on as it works (a phone's: the clock
// read anew on each pass of a layout following sizes that a leaving changes, never coming to rest, 2026-11-05).

///|
test "a frame and what is placed by where its layout puts things are of the frame's moment, however the host's clock goes on meanwhile" {
  let host = Ref(0.0)
  let reads = Ref(0)
  let tall_h : Ref[Double] = Ref(0.0)
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(col) {
        col.width(Is(Some(300.0))).height(Is(Some(600.0))) |> ignore
        // (growing with the clock, as a leaving row's room closes: 20 at 0, 30 at 100)
        let grows = col.box(fn(g) {
          g
          .width(Is(Some(80.0)))
          .height(By(fn() { Some(20.0 + g.tree.drawn_at() / 10.0) }))
          .shrink(Is(0.0))
          |> ignore
        })
        // (placed by how tall that is laid out, as the tree is placed: Live's Placed)
        col.box(fn(t) {
          t
          .width(Is(Some(40.0)))
          .height(Is(Some(10.0)))
          .offset(Placed(fn() {
            tall_h.val = grows.laid_size().1
            (0.0, 0.0)
          }))
          |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    // (the host's clock, 7 ms on each time it is read: it goes on as the frame is worked out)
    time=fn() {
      reads.val += 1
      host.val += 7.0
      host.val
    },
  )
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  reads.val = 0
  host.val = 200.0
  tree.at(100.0)
  tree.frame(390.0, 844.0, now=100.0) |> ignore
  assert_eq(reads.val, 0)
  assert_eq(tree.logic_at(), 100.0)
  assert_eq(tree.drawn_at(), 100.0)
  assert_eq(tall_h.val, 30.0)
}

///|
test "what comes after a change is told whole is of its own moment, nothing written before it" {
  let host = Ref(0.0)
  let open = @signals.signal(false)
  let pressed_at : Ref[Double] = Ref(-1.0)
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(col) {
        col.width(Is(Some(300.0))).height(Is(Some(600.0))) |> ignore
        col.box(fn(b) {
          b
          .width(Is(Some(100.0)))
          .height(Is(Some(40.0)))
          .shrink(Is(0.0))
          // (what it reads marked with the change that sets it, of that change's moment)
          .alpha(By(fn() { if open.get() { 1.0 } else { 0.5 } }))
          .on_press(fn() { pressed_at.val = b.cause_at() })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { host.val },
  )
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  // (a change from outside at 100: its moment taken as it marks what reads it)
  host.val = 100.0
  open.set(true)
  // (a press at 500, nothing written since that change was told whole: of 500, not of the change before it)
  host.val = 500.0
  assert_true(tree.press(20.0, 20.0))
  assert_eq(pressed_at.val, 500.0)
}

///|
test "a structure told of a change is of that change's moment, not of one before it that marked it and changed nothing it reads" {
  let host = Ref(0.0)
  let n = @signals.signal(1)
  // (what it reads: whether n is past 2, worked out again as n changes, the same for 1 and 2)
  let past = @signals.computed(fn(_) { n.get() > 2 }, same=fn(a, b) { a == b })
  let told_at : Array[Double] = []
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(col) {
        col.width(Is(Some(300.0))).height(Is(Some(600.0))) |> ignore
        col.reacts(fn() { past.get() }, fn(p) { if p { told_at.push(col.cause_at()) } })
      })
      |> ignore
    },
    time=fn() { host.val },
  )
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  // (at 100, a change that marks it and changes nothing it reads; at 300, one that does)
  host.val = 100.0
  n.set(2)
  host.val = 300.0
  n.set(3)
  assert_eq(told_at, [300.0])
}

///|
test "what is made as of a moment on the timeline (View::logic_past) is of that moment, a frame between or none, whatever else was due between" {
  for frames in [false, true] {
    let told_at : Array[Double] = []
    let tree = @view.Tree::new(fn(root) {
      root.box(fn(col) {
        col.width(Is(Some(300.0))).height(Is(Some(600.0))) |> ignore
        col.reacts(fn() { col.logic_past(100.0) }, fn(p) { if p { told_at.push(col.cause_at()) } })
        // (something else due later, before the frame that first draws past 100)
        col.at_moment(200.0, fn() {  }) |> ignore
      })
      |> ignore
    })
    tree.frame(390.0, 844.0, now=0.0) |> ignore
    if frames {
      tree.frame(390.0, 844.0, now=60.0) |> ignore
    }
    tree.frame(390.0, 844.0, now=300.0) |> ignore
    assert_eq(told_at, [100.0], msg="frames between: \{frames}")
  }
}

///|
test "a moment on the timeline read no more (View::logic_past) is waited for no more: the tree wakes for the one read now, none for one read before" {
  let till = @signals.signal(1000.0, same=fn(a, b) { a == b })
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(col) {
      col.width(Is(Some(300.0))).height(By(fn() { Some(if col.logic_past(till.get()) { 100.0 } else { 200.0 }) }))
      |> ignore
    })
    |> ignore
  })
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  let first = tree.wake_waited()
  // (held till 500 instead: what was due at 1000 for it called off with it)
  till.set(500.0)
  tree.frame(390.0, 844.0, now=10.0) |> ignore
  let then = tree.wake_waited()
  tree.frame(390.0, 844.0, now=600.0) |> ignore
  assert_eq((first, then, tree.wake_waited()), (Some(1000.0), Some(500.0), None))
}

///|
test "what was due before a structure told inside a flush is done once the flush is over, each told whole: what it sets going finds things where they stood before it, not laid out with it already" {
  let tall = @signals.signal(100.0, same=fn(a, b) { a == b })
  let seen : Array[Double] = []
  let box : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(col) {
      col.width(Is(Some(300.0))).height(Is(Some(600.0))) |> ignore
      // (a structure told in the flush that moving the drawn clock sets going, as a frame's host moves it first)
      col.reacts(fn() { col.drawn_past(150.0) }, fn(_) {  })
      // (due before that frame: a change of its own, at its moment)
      col.at_moment(100.0, fn() { tall.set(200.0) }) |> ignore
      col.box(fn(b) {
        box.val = Some(b)
        b.height(By(fn() { Some(tall.get()) })) |> ignore
        // (where it stands as a change comes laid out and placed then: what moves for a cause moves from there)
        b.laid_before_causes()
        b.reacts(fn() { tall.get() }, fn(_) { seen.push(b.rect().3) })
      })
      |> ignore
    })
    |> ignore
  })
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  let laid = seen.copy()
  tree.at(200.0)
  tree.frame(390.0, 844.0, now=200.0) |> ignore
  // (told of the change at 100 as tall as it stood before it, then laid out as it is)
  assert_eq((seen.length(), seen.last(), box.val.map(fn(b) { b.rect().3 })), (laid.length() + 1, Some(100.0), Some(200.0)))
}
