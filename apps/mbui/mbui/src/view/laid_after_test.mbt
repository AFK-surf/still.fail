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
