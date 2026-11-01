///|
test "squeeze_faults finds an unannounced ellipsis in the window tree" {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=100.0, tree=fn(root) {
    root.box(fn(v) {
      v.width(Is(Some(20.0)))
      .height(Is(Some(20.0)))
      .words(Is("10:06"), look={ size: 10.0, weight: 400, line: 14.0, wrap: false })
      |> ignore
    }) |> ignore
  })
  t.draw()
  let drawn = view_tree().unwrap().drawn().filter(fn(d) { d.words == "10:06" })
  assert_eq(drawn.length(), 1)
  // The tree's painter cuts one-line words once their measured width exceeds their laid-out width by half a point.
  let c = g()
  let full = layout_text("10:06", c.sp(10.0), 400, 1.0e9, false, line=c.sp(14.0), style=view_words_style())
  assert_true(full.w > drawn[0].w + 0.5)
  assert_eq(t.squeeze_faults().length(), 1, msg=t.squeeze_faults().join("\n"))
}

///|
test "a window tree's deliberately cut words are permitted" {
  let allowed = @signals.signal(true)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=100.0, tree=fn(root) {
    root.box(fn(v) {
      v.width(Is(Some(20.0)))
      .height(Is(Some(20.0)))
      .words(Is("10:06"), look={ size: 10.0, weight: 400, line: 14.0, wrap: false })
      .allow_ellipsis(By(fn() { allowed.get() }))
      |> ignore
    }) |> ignore
  })
  t.draw()
  assert_eq(t.squeeze_faults(), [])
  allowed.set(false)
  t.frame()
  assert_eq(t.squeeze_faults().length(), 1, msg=t.squeeze_faults().join("\n"))
}

///|
test "squeeze_faults finds cut words in styled runs in the window tree" {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=100.0, tree=fn(root) {
    root.box(fn(v) {
      v.width(Is(Some(20.0)))
      .height(Is(Some(20.0)))
      .words_runs(Is([@view.words_run("10:"), @view.words_run("06", weight=600)]),
        look={ size: 10.0, weight: 400, line: 14.0, wrap: false })
      |> ignore
    }) |> ignore
  })
  t.draw()
  let faults = t.squeeze_faults()
  assert_eq(faults.length(), 1, msg=faults.join("\n"))
}

///|
test "a window tree's invisible words do not report an ellipsis" {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=100.0, tree=fn(root) {
    root.box(fn(holder) {
      holder.alpha(Is(0.0)) |> ignore
      holder.box(fn(v) {
        v.width(Is(Some(20.0)))
        .height(Is(Some(20.0)))
        .words(Is("10:06"), look={ size: 10.0, weight: 400, line: 14.0, wrap: false })
        |> ignore
      }) |> ignore
    }) |> ignore
  })
  t.draw()
  assert_eq(t.squeeze_faults(), [])
}

///|
test "a window tree's words entirely outside a clipping holder are not reported" {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=100.0, tree=fn(root) {
    root.box(fn(holder) {
      holder.width(Is(Some(20.0))).height(Is(Some(20.0))).clips(Is(true)) |> ignore
      holder.box(fn(v) {
        v.over(Is(true))
        .offset(Is((40.0, 0.0)))
        .width(Is(Some(20.0)))
        .height(Is(Some(20.0)))
        .words(Is("10:06"), look={ size: 10.0, weight: 400, line: 14.0, wrap: false })
        |> ignore
      }) |> ignore
    }) |> ignore
  })
  t.draw()
  let drawn = view_tree().unwrap().drawn().filter(fn(d) { d.words == "10:06" })
  assert_eq(drawn.length(), 1)
  assert_true(drawn[0].x >= 20.0)
  assert_eq(t.squeeze_faults(), [])
}
