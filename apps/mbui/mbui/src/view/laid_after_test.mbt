// One thing's place and size worked out of another's in the frame's one layout (View::laid_after: laid out alone once
// all else is, by where that is laid out then, read plainly), or drawn by where another is drawn as the tree is placed
// (Live's Placed): nothing of where things are laid out told back as a change of its own (docs/retained.md rule 10).

///|
test "an overlay laid out after its landing follows it through a width change and scrolling in the same frame, laid out again only as anything is" {
  let wide = @signals.signal(120.0)
  let shift = @signals.signal((0.0, -20.0))
  let shown = @signals.signal(true)
  let target : Ref[@view.View?] = Ref(None)
  let copy : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(viewport) {
      viewport.height(Is(Some(100.0))).clips(Is(true)).offset(Is((15.0, 25.0))) |> ignore
      viewport.box(fn(held) {
        held.offset(By(fn() { shift.get() })).drawn_off(Is((50.0, 70.0))) |> ignore
        target.val = Some(held.box(fn(row) {
          row.width(By(fn() { Some(wide.get()) })).height(Is(Some(40.0)))
          .laid_nowhere(By(fn() { !shown.get() })) |> ignore
        }))
      }) |> ignore
    }) |> ignore
    let landing = target.val.unwrap()
    // (where its landing is placed and how big, once that is laid out)
    copy.val = Some(root.box(fn(overlay) {
      overlay.laid_after(fn() {
        let (x, y, w, h) = landing.placed_window_now()
        (x, y, Some(w), Some(h))
      }) |> ignore
    }))
  })
  tree.frame(400.0, 300.0) |> ignore
  assert_eq(copy.val.unwrap().rect(), (15.0, 5.0, 120.0, 40.0))
  @signals.start_batch()
  wide.set(230.0)
  shift.set((0.0, -65.0))
  @signals.end_batch()
  tree.frame(400.0, 300.0) |> ignore
  assert_eq(copy.val.unwrap().rect(), (15.0, -40.0, 230.0, 40.0))
  assert_eq(copy.val.unwrap().rect(), target.val.unwrap().placed_window_now())
  // (nothing changed: nothing laid out)
  let computes = tree.work().computes
  tree.frame(400.0, 300.0) |> ignore
  assert_eq(tree.work().computes, computes)
  shown.set(false)
  tree.frame(400.0, 300.0) |> ignore
  assert_true(target.val.unwrap().shown_nowhere())
}

///|
test "a detached overlay drawn where its hidden landing is drawn, its holder moving and scaled, as the tree is placed" {
  let drawing = @signals.signal((50.0, 70.0))
  let scale = @signals.signal(0.5)
  let shown = @signals.signal(true)
  let target : Ref[@view.View?] = Ref(None)
  let copy : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(viewport) {
      viewport.height(Is(Some(50.0))).clips(Is(true)).offset(Is((15.0, 25.0))) |> ignore
      viewport.box(fn(held) {
        held.offset(Is((0.0, -20.0))).drawn_off(By(fn() { drawing.get() }))
        .scale(By(fn() { scale.get() }), about=At(0.0, 0.0)) |> ignore
        target.val = Some(held.box(fn(row) {
          row.width(Is(Some(120.0))).height(Is(Some(40.0))).alpha(Is(0.0))
          .laid_nowhere(By(fn() { !shown.get() })) |> ignore
        }))
      }) |> ignore
    }) |> ignore
    let landing = target.val.unwrap()
    copy.val = Some(root.box(fn(overlay) {
      // (as big as its landing is laid out, laid out once that is; where it is drawn and as big, as the tree is placed)
      let drawn = fn() { landing.drawn_window_now().unwrap_or((0.0, 0.0, 0.0, 0.0)) }
      overlay
      .laid_after(fn() {
        let (_, _, w, h) = landing.placed_window_now()
        (0.0, 0.0, Some(w), Some(h))
      })
      .offset(Placed(fn() { (drawn().0, drawn().1) }))
      .scale(Placed(fn() {
        let (_, _, w, _) = landing.placed_window_now()
        if w > 0.0 { drawn().2 / w } else { 1.0 }
      }), about=At(0.0, 0.0))
      |> ignore
    }))
  })
  tree.frame(400.0, 300.0) |> ignore
  assert_eq(copy.val.unwrap().rect(), (65.0, 75.0, 60.0, 20.0))
  drawing.set((30.0, 10.0))
  tree.frame(400.0, 300.0) |> ignore
  assert_eq(copy.val.unwrap().rect(), (45.0, 15.0, 60.0, 20.0))
  scale.set(1.5)
  tree.frame(400.0, 300.0) |> ignore
  assert_eq(copy.val.unwrap().rect(), (45.0, 15.0, 180.0, 60.0))
  shown.set(false)
  tree.frame(400.0, 300.0) |> ignore
  assert_eq(target.val.unwrap().drawn_window_now(), None)
  shown.set(true)
  tree.frame(400.0, 300.0) |> ignore
  assert_eq(copy.val.unwrap().rect(), (45.0, 15.0, 180.0, 60.0))
}

///|
test "panic a property layout reads worked out of where things are laid out" {
  let tree = @view.Tree::new(fn(root) {
    let a = root.box(fn(a) { a.height(Is(Some(10.0))) |> ignore })
    root.box(fn(b) { b.height(Placed(fn() { Some(a.laid_size().1 * 2.0) })) |> ignore }) |> ignore
  })
  tree.frame(400.0, 300.0) |> ignore
}

///|
/// Where things are laid out read plainly in what is followed to make, lay out or say something refuses itself as it
/// is read (layout_read): its change is told to nothing, so what it worked out would stay as of the read, a frame
/// behind or worse (docs/retained.md rule 10).
test "panic where things are laid out read by a binding's read, for a property: refused as it is read" {
  let tree = @view.Tree::new(fn(root) {
    let a = root.box(fn(a) { a.height(Is(Some(10.0))) |> ignore })
    root.box(fn(b) { b.height(By(fn() { Some(a.laid_size().1 * 2.0) })) |> ignore }) |> ignore
  })
  tree.frame(400.0, 300.0) |> ignore
}

///|
test "panic where things are laid out read by a binding's read, for what is painted alone: refused as it is read (Placed is the way)" {
  let tree = @view.Tree::new(fn(root) {
    let a = root.box(fn(a) { a.height(Is(Some(10.0))) |> ignore })
    root.box(fn(b) { b.alpha(By(fn() { if a.rect().3 > 5.0 { 1.0 } else { 0.5 } })) |> ignore }) |> ignore
  })
  tree.frame(400.0, 300.0) |> ignore
}

///|
test "panic where things are laid out read by what a structure reads: refused as it is read" {
  let tree = @view.Tree::new(fn(root) {
    let a = root.box(fn(a) { a.height(Is(Some(10.0))) |> ignore })
    root.show(fn() { a.laid_window_now().3 > 5.0 }, fn(v) { v.box(fn(_) {  }) |> ignore })
  })
  tree.frame(400.0, 300.0) |> ignore
}

///|
test "panic where things are laid out read by what reacts reads: refused as it is read" {
  let tree = @view.Tree::new(fn(root) {
    let a = root.box(fn(a) { a.height(Is(Some(10.0))) |> ignore })
    root.reacts(fn() { a.placed_window_now().3 }, fn(_) {  })
  })
  tree.frame(400.0, 300.0) |> ignore
}

///|
test "where things are laid out read where it may be: as the tree is placed (Placed), by what is laid out after all else, at a cause, once a change is committed" {
  let tall = @signals.signal(10.0)
  let at_cause : Ref[Double] = Ref(0.0)
  let committed : Ref[Double] = Ref(0.0)
  let a_at : Ref[@view.View?] = Ref(None)
  let faded : Ref[@view.View?] = Ref(None)
  let after : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    let a = root.box(fn(a) { a.height(By(fn() { Some(tall.get()) })) |> ignore })
    a_at.val = Some(a)
    faded.val = Some(root.box(fn(b) { b.alpha(Placed(fn() { if a.rect().3 > 15.0 { 1.0 } else { 0.5 } })) |> ignore }))
    after.val = Some(
      root.box(fn(c) { c.laid_after(fn() { (0.0, 0.0, Some(a.laid_size().0), Some(a.laid_size().1 * 2.0)) }) |> ignore }),
    )
    // (what reacts does is at its cause: where things are laid out as of its moment read plainly)
    root.reacts(fn() { tall.get() }, fn(_) {
      at_cause.val = a.laid_size().1
      a.when_committed(fn() { committed.val = a.laid_window_now().3 })
    })
  })
  tree.frame(400.0, 300.0) |> ignore
  tall.set(20.0)
  tree.frame(400.0, 300.0) |> ignore
  assert_eq(
    (at_cause.val, committed.val, tree.drawn_of(faded.val.unwrap().id()).map(fn(d) { d.alpha }), after.val.unwrap().rect().3),
    (20.0, 20.0, Some(1.0), 40.0),
  )
  assert_true(!tree.told_since(), msg="nothing owed")
}
