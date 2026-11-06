///|
test "an overlay follows its landing through a width change and scrolling in the same placement, without drawing motion" {
  let wide = @signals.signal(120.0)
  let shift = @signals.signal((0.0, -20.0))
  let shown = @signals.signal(true)
  let target : Ref[@view.View?] = Ref(None)
  let copy : Ref[@view.View?] = Ref(None)
  let told = Ref(0)
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
    copy.val = Some(root.box(fn(overlay) {
      let rect = fn() { landing.owed_laid_window().unwrap_or((0.0, 0.0, 0.0, 0.0)) }
      overlay.over(Is(true)).offset(By(fn() { (rect().0, rect().1) }))
      .width(By(fn() { Some(rect().2) })).height(By(fn() { Some(rect().3) })) |> ignore
      overlay.reacts(fn() { landing.owed_laid_window() }, fn(_) { told.val += 1 })
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
  let count = told.val
  tree.frame(400.0, 300.0) |> ignore
  assert_eq(told.val, count)
  shown.set(false)
  tree.frame(400.0, 300.0) |> ignore
  assert_eq(target.val.unwrap().owed_laid_window(), None)
}

///|
test "a detached overlay follows its hidden landing's drawn rectangle including its moving and scaled holder" {
  let drawing = @signals.signal((50.0, 70.0))
  let scale = @signals.signal(0.5)
  let shown = @signals.signal(true)
  let target : Ref[@view.View?] = Ref(None)
  let copy : Ref[@view.View?] = Ref(None)
  let told = Ref(0)
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
      let rect = fn() { landing.owed_drawn_window().unwrap_or((0.0, 0.0, 0.0, 0.0)) }
      overlay.over(Is(true)).offset(By(fn() { (rect().0, rect().1) }))
      .width(By(fn() { Some(rect().2) })).height(By(fn() { Some(rect().3) })) |> ignore
      overlay.reacts(fn() { landing.owed_drawn_window() }, fn(_) { told.val += 1 })
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
  let count = told.val
  tree.frame(400.0, 300.0) |> ignore
  assert_eq(told.val, count)
  shown.set(false)
  tree.frame(400.0, 300.0) |> ignore
  assert_eq(target.val.unwrap().owed_drawn_window(), None)
  shown.set(true)
  tree.frame(400.0, 300.0) |> ignore
  assert_eq(copy.val.unwrap().rect(), (45.0, 15.0, 180.0, 60.0))
}
