///|
let sheet_test_late_ms : Double = 500.0

///|
let sheet_test_100_ms : Double = 100.0

///|
let sheet_test_150_ms : Double = 150.0

///|
let sheet_test_250_ms : Double = 250.0

///|
let sheet_test_300_ms : Double = 300.0

///|
let sheet_test_step_ms : Double = 30.0

///|
struct NodeSheetCase {
  open : @signals.Signal[Bool]
  content : @signals.Signal[Double]
  sinks : @signals.Signal[Double]
  extent : Ref[@view.View?]
  shown : Ref[Int]
  gone : Ref[Int]
  pressed : Ref[Int]
  surface : Ref[@view.View?]
}

///|
fn node_sheet_case(tall? : Double = 0.0, fit? : Bool = false, grows? : Bool = false, under? : Double = 0.0, draggable? : Bool = true) -> (@ui.Tester, NodeSheetCase) {
  let k : NodeSheetCase = {
    open: @signals.signal(true), content: @signals.signal(200.0), sinks: @signals.signal(0.0), extent: Ref(None),
    shown: Ref(0), gone: Ref(0), pressed: Ref(0), surface: Ref(None),
  }
  let t = @ui.Tester::new(fn(_) {  }, time=0.0, tree=fn(root : @view.View) {
    root.box(fn(page) {
      page.height(Is(Some(40.0))).focusable(Is(true)).says(Is(Some(@view.said(Button, label="Page")))) |> ignore
    }) |> ignore
    @kit.sheet_node(
      root, fn() { k.open.get() }, fn() { k.open.set(false) },
      tall~, fit~, grows~, under~, draggable~, label=fn() { "Sheet" },
      sinks=fn() { k.sinks.get() },
      extent=fn(v) { k.extent.val = Some(v) },
      shown=fn() { k.shown.val += 1 }, gone=fn() { k.gone.val += 1 },
      fn(sheet) {
        k.surface.val = Some(sheet)
        sheet.box(fn(grip) { grip.height(Is(Some(25.0))) |> ignore }) |> ignore
        sheet.box(fn(b) {
          b.height(By(fn() { Some(k.content.get()) })).focusable(Is(true))
          .says(Is(Some(@view.said(Button, label="Inside"))))
          .on_press(fn() { k.pressed.val += 1 }) |> ignore
        }) |> ignore
      },
    )
  })
  t.draw()
  (t, k)
}

///|
test "tree sheet fits its content, changes with it, and reports its visible height including the system inset" {
  let (t, k) = node_sheet_case(under=42.0)
  t.run_for(sheet_test_late_ms)
  assert_eq(k.shown.val, 1)
  assert_eq(k.extent.val.unwrap().rect().3, 225.0)
  let sheet = k.surface.val.unwrap()
  assert_eq(sheet.rect().1, 844.0 - 225.0)
  k.content.set(300.0)
  t.draw()
  assert_eq(k.extent.val.unwrap().rect().3, 325.0)
  assert_eq(sheet.rect().1, 844.0 - 325.0)
  t.post(@hostapi.system_channel, "{\"bars\":{\"top\":0,\"bottom\":24,\"left\":0,\"right\":0}}")
  t.draw()
  assert_eq(k.extent.val.unwrap().rect().3, 349.0)
  assert_eq(sheet.rect().1, 844.0 - 349.0)
}

///|
test "tree sheet traps the page, returns focus and keeps only its picture until its exit is over" {
  let (t, k) = node_sheet_case()
  t.run_for(sheet_test_late_ms)
  assert_true(t.query(@ui.Role::Button, label="Page") is None)
  assert_false(t.query(@ui.Role::Dialog, label="Sheet").unwrap().actions.contains(Activate))
  t.click(@ui.Role::Button, label="Inside")
  assert_eq(k.pressed.val, 1)
  t.tap(10.0, 10.0)
  assert_false(k.open.get())
  assert_eq(k.gone.val, 0)
  assert_true(t.query(@ui.Role::Button, label="Page") is Some(_))
  assert_true(t.query(@ui.Role::Button, label="Inside") is None)
  t.run_for(sheet_test_late_ms)
  assert_eq(k.gone.val, 1)
}

///|
test "tree sheet: Escape and system back dismiss the open sheet" {
  for back in [false, true] {
    let (t, k) = node_sheet_case()
    t.run_for(sheet_test_late_ms)
    if back { t.back() } else { t.press("Escape") }
    assert_false(k.open.get(), msg="back=\{back}")
    assert_eq(t.backs_out(), 0)
    t.run_for(sheet_test_late_ms)
    assert_eq(k.gone.val, 1)
  }
}

///|
test "tree sheet drag: a short drag returns, a long drag dismisses" {
  let (t, k) = node_sheet_case()
  t.run_for(sheet_test_late_ms)
  let y = k.surface.val.unwrap().rect().1 + 10.0
  t.tap(190.0, y)
  assert_true(k.open.get())
  t.drag(190.0, y, 190.0, y + 40.0)
  t.run_for(sheet_test_late_ms)
  assert_true(k.open.get(), msg="sheet=\{k.surface.val.unwrap().rect()}, extent=\{k.extent.val.unwrap().rect()}")
  assert_eq(k.extent.val.unwrap().rect().3, 225.0)
  t.drag(190.0, y, 190.0, y + 120.0)
  assert_false(k.open.get())
}

///|
test "tree sheet with dragging disabled stays in place when its head is dragged" {
  let (t, k) = node_sheet_case(draggable=false)
  t.run_for(sheet_test_late_ms)
  let sheet = k.surface.val.unwrap()
  let before = sheet.rect()
  t.drag(190.0, before.1 + 10.0, 190.0, before.1 + 160.0)
  assert_true(k.open.get())
  assert_eq(sheet.rect(), before)
  t.press("Escape")
  assert_false(k.open.get())
}

///|
test "tree sheet gives and ticks once as a finger pulls beyond its top detent" {
  let (t, k) = node_sheet_case(tall=0.94, grows=true)
  t.run_for(sheet_test_late_ms)
  t.host_says_finger(Some(true))
  let sheet = k.surface.val.unwrap()
  let y = sheet.rect().1 + 10.0
  t.touch(0, 190.0, y)
  t.touch(1, 190.0, y - 30.0)
  t.draw()
  assert_true(sheet.rect().3 > 844.0 * 0.94)
  assert_eq(t.haptics(), [@ui.Haptic::TextHandleMove])
  t.touch(1, 190.0, y - 45.0)
  t.draw()
  assert_eq(t.haptics(), [@ui.Haptic::TextHandleMove])
  t.touch(2, 190.0, y - 45.0)
  t.run_for(sheet_test_late_ms)
  assert_true(k.open.get())
  assert_true((sheet.rect().3 - 844.0 * 0.94).abs() < 0.01)
}

///|
test "tree sheet with a height share uses the window and excludes its extension from the reported height" {
  let (t, k) = node_sheet_case(tall=0.5, under=42.0)
  t.run_for(sheet_test_late_ms)
  assert_eq(k.extent.val.unwrap().rect().3, 422.0)
  assert_eq(k.surface.val.unwrap().rect().1, 422.0)
}

///|
test "tree sheet can fit changing contents up to a share and only enables detents near that limit" {
  let (t, k) = node_sheet_case(tall=0.7, fit=true, grows=true)
  t.run_for(sheet_test_late_ms)
  let sheet = k.surface.val.unwrap()
  assert_eq(k.extent.val.unwrap().rect().3, 225.0)
  t.tap(190.0, sheet.rect().1 + 10.0)
  t.run_for(sheet_test_late_ms)
  assert_eq(sheet.rect().3, 225.0)
  k.content.set(580.0)
  t.draw()
  assert_true((sheet.rect().3 - 844.0 * 0.7).abs() < 0.01)
  assert_true((k.extent.val.unwrap().rect().3 - 844.0 * 0.7).abs() < 0.01)
  t.tap(190.0, sheet.rect().1 + 10.0)
  t.run_for(sheet_test_late_ms)
  assert_true((sheet.rect().3 - 844.0 * 0.94).abs() < 0.01)
  k.content.set(100.0)
  t.draw()
  assert_eq(sheet.rect().3, 125.0)
  assert_eq(k.extent.val.unwrap().rect().3, 125.0)
  t.tap(190.0, sheet.rect().1 + 10.0)
  t.run_for(sheet_test_late_ms)
  assert_eq(sheet.rect().3, 125.0)
}

///|
test "tree sheet detents: the grabber toggles the sheet and the reported stack height stays its requested height" {
  let (t, k) = node_sheet_case(tall=0.55, grows=true)
  t.run_for(sheet_test_late_ms)
  let y = k.surface.val.unwrap().rect().1 + 10.0
  t.tap(190.0, y)
  t.run_for(sheet_test_late_ms)
  assert_true((k.surface.val.unwrap().rect().3 - 844.0 * 0.94).abs() < 0.01)
  assert_true((k.extent.val.unwrap().rect().3 - 844.0 * 0.55).abs() < 0.01)
  t.tap(190.0, k.surface.val.unwrap().rect().1 + 10.0)
  t.run_for(sheet_test_late_ms)
  assert_true((k.surface.val.unwrap().rect().3 - 844.0 * 0.55).abs() < 0.01)
}

///|
test "tree sheet sent farther down while leaving stays until the new way is over" {
  let (t, k) = node_sheet_case()
  t.run_for(sheet_test_late_ms)
  k.open.set(false)
  t.run_for(sheet_test_100_ms)
  k.sinks.set(800.0)
  t.run_for(sheet_test_250_ms)
  assert_eq(k.gone.val, 0)
  t.run_for(sheet_test_300_ms)
  assert_eq(k.gone.val, 1)
}

///|
test "tree sheet closes from the size its contents changed to at that event, without another frame" {
  let (t, k) = node_sheet_case()
  t.run_for(sheet_test_late_ms)
  k.content.set(600.0)
  k.open.set(false)
  t.run_for(sheet_test_300_ms)
  assert_eq(k.gone.val, 0)
  t.run_for(sheet_test_300_ms)
  assert_eq(k.gone.val, 1)
}

///|
fn sheet_moments(frames : Bool) -> (Double, Double, Int) {
  let (t, k) = node_sheet_case()
  if frames {
    for _ in 0..<5 { t.run_for(sheet_test_step_ms) }
  } else { t.run_for(sheet_test_150_ms) }
  let coming = k.surface.val.unwrap().rect().1
  k.open.set(false)
  if frames {
    for _ in 0..<5 { t.run_for(sheet_test_step_ms) }
  } else { t.run_for(sheet_test_150_ms) }
  let going = k.surface.val.unwrap().rect().1
  (coming, going, k.gone.val)
}

///|
test "tree sheet's entrance and interruption are the same with or without intermediate frames" {
  assert_eq(sheet_moments(true), sheet_moments(false))
}

///|
test "tree sheet caps a long scrolling body while keeping its head and foot in reach" {
  let sheet : Ref[@view.View?] = Ref(None)
  let head : Ref[@view.View?] = Ref(None)
  let foot : Ref[@view.View?] = Ref(None)
  let first : Ref[@view.View?] = Ref(None)
  let t = @ui.Tester::new(fn(_) {  }, time=0.0, tree=fn(root : @view.View) {
    @kit.sheet_node(root, fn() { true }, fn() {  }, fn(s) {
      sheet.val = Some(s)
      head.val = Some(s.box(fn(v) { v.height(Is(Some(50.0))) |> ignore }))
      s.box(fn(sc) {
        sc.shrink(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
        sc.scrolls(@view.Scroll::new(), fn(body) {
          for i in 0..<30 {
            let row = body.box(fn(r) { r.height(Is(Some(50.0))) |> ignore })
            if i == 0 { first.val = Some(row) }
          }
        }) |> ignore
      }) |> ignore
      foot.val = Some(s.box(fn(v) { v.height(Is(Some(50.0))) |> ignore }))
    })
  })
  t.run_for(sheet_test_late_ms)
  let frame = sheet.val.unwrap().rect()
  assert_true((frame.3 - 844.0 * 0.94).abs() < 0.01, msg="sheet=\{frame}")
  let fy = foot.val.unwrap().rect().1
  let hy = head.val.unwrap().rect().1
  let before = first.val.unwrap().rect().1
  t.wheel(190.0, hy + 100.0, 400.0)
  assert_true(first.val.unwrap().rect().1 < before)
  assert_eq(foot.val.unwrap().rect().1, fy)
  assert_eq(head.val.unwrap().rect().1, hy)
  assert_eq(fy + 50.0, 844.0)
}

///|
test "tree sheet fits a changing scrolling body beneath its cap with a fixed head and foot" {
  let content_h = @signals.signal(120.0)
  let sheet : Ref[@view.View?] = Ref(None)
  let head : Ref[@view.View?] = Ref(None)
  let foot : Ref[@view.View?] = Ref(None)
  let content : Ref[@view.View?] = Ref(None)
  let extent : Ref[@view.View?] = Ref(None)
  let t = @ui.Tester::new(fn(_) {  }, time=0.0, tree=fn(root : @view.View) {
    @kit.sheet_node(root, fn() { true }, fn() {  }, tall=0.7, fit=true, under=42.0,
      extent=fn(v) { extent.val = Some(v) }, fn(s) {
        sheet.val = Some(s)
        head.val = Some(s.box(fn(v) { v.height(Is(Some(50.0))) |> ignore }))
        s.box(fn(sc) {
          sc.shrink(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
          sc.scrolls(@view.Scroll::new(), fn(body) {
            content.val = Some(body.box(fn(v) { v.height(By(fn() { Some(content_h.get()) })) |> ignore }))
          }) |> ignore
        }) |> ignore
        foot.val = Some(s.box(fn(v) { v.height(Is(Some(50.0))) |> ignore }))
      })
  })
  t.run_for(sheet_test_late_ms)
  assert_eq(extent.val.unwrap().rect().3, 220.0)
  t.post(@hostapi.system_channel, "{\"bars\":{\"top\":0,\"bottom\":24,\"left\":0,\"right\":0}}")
  t.draw()
  assert_eq(extent.val.unwrap().rect().3, 244.0)
  content_h.set(1000.0)
  t.draw()
  assert_true((extent.val.unwrap().rect().3 - 844.0 * 0.7).abs() < 0.01)
  let y = head.val.unwrap().rect().1
  let fy = foot.val.unwrap().rect().1
  let before = content.val.unwrap().rect().1
  t.wheel(190.0, y + 100.0, 400.0)
  assert_true(content.val.unwrap().rect().1 < before)
  assert_eq(head.val.unwrap().rect().1, y)
  assert_eq(foot.val.unwrap().rect().1, fy)
  assert_eq(fy + 50.0, 844.0 - 24.0)
  content_h.set(100.0)
  t.draw()
  assert_eq(extent.val.unwrap().rect().3, 224.0)
  assert_eq(sheet.val.unwrap().rect().3, 224.0 + 42.0)
}

///|
test "tree sheet returns the keyboard focus to its opener as it begins closing" {
  let open = @signals.signal(false)
  let t = @ui.Tester::new(fn(_) {  }, time=0.0, tree=fn(root : @view.View) {
    root.box(fn(button) {
      button.height(Is(Some(40.0))).focusable(Is(true)).on_press(fn() { open.set(true) })
      .says(Is(Some(@view.said(Button, label="Open")))) |> ignore
    }) |> ignore
    @kit.sheet_node(root, fn() { open.get() }, fn() { open.set(false) }, label=fn() { "Sheet" }, fn(s) {
      s.box(fn(v) { v.height(Is(Some(100.0))) |> ignore }) |> ignore
    })
  })
  t.tab()
  assert_eq(t.focused().unwrap().label, "Open")
  t.enter()
  t.run_for(sheet_test_late_ms)
  assert_true(open.get())
  t.press("Escape")
  assert_false(open.get())
  assert_eq(t.focused().unwrap().label, "Open")
}

///|
test "tree sheet can give a requested field the initial focus and return focus to the opener" {
  let open = @signals.signal(false)
  let field : Ref[@view.View?] = Ref(None)
  let t = @ui.Tester::new(fn(_) {  }, time=0.0, tree=fn(root : @view.View) {
    root.box(fn(button) {
      button.height(Is(Some(40.0))).focusable(Is(true)).on_press(fn() { open.set(true) })
      .says(Is(Some(@view.said(Button, label="Open")))) |> ignore
    }) |> ignore
    @kit.sheet_node(root, fn() { open.get() }, fn() { open.set(false) },
      initial_focus=fn() { field.val }, fn(s) {
        field.val = Some(s.box(fn(v) {
          v.height(Is(Some(60.0))).focusable(Is(true)).says(Is(Some(@view.said(TextField, label="Search")))) |> ignore
        }))
      })
  })
  t.tab()
  t.enter()
  assert_eq(t.focused().unwrap().label, "Search")
  t.press("Escape")
  assert_eq(t.focused().unwrap().label, "Open")
}

///|
test "old and tree sheets leave the existing editor focused by default and return it on closing" {
  for legacy in [true, false] {
    let open = @signals.signal(false)
    let field = @ui.Field::new()
    let t = if legacy {
      @ui.Tester::new(fn(c) {
        c.editor("page-field", placeholder="Page field", field~) |> ignore
        @kit.sheet(c, "focus-sheet", open.get(), h=200.0, fn() {  }) |> ignore
      })
    } else {
      @ui.Tester::new(fn(_) {  }, tree=fn(root : @view.View) {
        @ui.field(root, field, placeholder="Page field") |> ignore
        @kit.sheet_node(root, fn() { open.get() }, fn() { open.set(false) }, fn(s) {
          s.box(fn(v) { v.height(Is(Some(200.0))) |> ignore }) |> ignore
        })
      })
    }
    t.draw()
    t.tap_text("Page field")
    let before = t.ctx().focused_id()
    assert_true(before != 0, msg="legacy=\{legacy}: page field had no focus")
    open.set(true)
    t.draw()
    assert_eq(t.ctx().focused_id(), before, msg="legacy=\{legacy}: focus while open")
    t.type_text("x")
    assert_eq(field.text(), "x", msg="legacy=\{legacy}: typing while open")
    open.set(false)
    t.draw()
    assert_eq(t.ctx().focused_id(), before, msg="legacy=\{legacy}: focus after close")
  }
}

///|
test "a sheet's requested height places the sheet below in the same layout" {
  let top_open = @signals.signal(false)
  let content_h = @signals.signal(240.0)
  let top_extent : Ref[@view.View?] = Ref(None)
  let lower : Ref[@view.View?] = Ref(None)
  let t = @ui.Tester::new(fn(_) {  }, time=0.0, tree=fn(root : @view.View) {
    @kit.sheet_node(root, fn() { true }, fn() {  }, raised_painted=fn(laid) { top_extent.val.bind(fn(v) { laid.size(v) }).map(fn(size) { size.1 / 4.0 }).unwrap_or(0.0) }, fn(s) {
      lower.val = Some(s)
      s.box(fn(b) { b.height(Is(Some(200.0))) |> ignore }) |> ignore
    })
    @kit.sheet_node(root, fn() { top_open.get() }, fn() {  }, extent=fn(v) { top_extent.val = Some(v) }, fn(s) {
      s.box(fn(b) { b.height(By(fn() { Some(content_h.get()) })) |> ignore }) |> ignore
    })
  })
  t.run_for(sheet_test_late_ms)
  let base = lower.val.unwrap().rect().1
  top_open.set(true)
  t.frame()
  assert_eq(top_extent.val.unwrap().rect().3, 240.0)
  assert_eq(lower.val.unwrap().rect().1, base - 60.0)
  let tree = @ui.view_tree().unwrap()
  let computes = tree.work().computes
  content_h.set(320.0)
  t.frame()
  assert_eq(top_extent.val.unwrap().rect().3, 320.0)
  assert_eq(lower.val.unwrap().rect().1, base - 80.0)
  assert_eq(tree.work().computes - computes, 1, msg="one layout, no geometry fed back")
}

///|
fn old_fitted_detent_after_changes(draw_short : Bool) -> Double raise {
  let requested = @signals.signal(844.0 * 0.7)
  let t = @ui.Tester::new(fn(c) {
    @kit.sheet(c, "old-fit", true, h=requested.get(), detents=[0.55, 0.94], label="Old sheet", fn() {  }) |> ignore
  })
  t.run_for(sheet_test_late_ms)
  let y = t.get(@ui.Role::Dialog, label="Old sheet").rect.1 + 10.0
  t.drag(190.0, y, 190.0, y - 250.0)
  t.run_for(sheet_test_late_ms)
  assert_true((t.get(@ui.Role::Dialog, label="Old sheet").rect.3 - 844.0 * 0.94).abs() < 0.01)
  requested.set(125.0)
  if draw_short { t.draw() }
  requested.set(844.0 * 0.7)
  t.draw()
  t.get(@ui.Role::Dialog, label="Old sheet").rect.3
}

///|
fn fitted_detent_after_changes(draw_short : Bool) -> Double raise {
  let (t, k) = node_sheet_case(tall=0.7, fit=true, grows=true)
  k.content.set(580.0)
  t.run_for(sheet_test_late_ms)
  let y = k.surface.val.unwrap().rect().1 + 10.0
  t.drag(190.0, y, 190.0, y - 250.0)
  t.run_for(sheet_test_late_ms)
  assert_true((k.surface.val.unwrap().rect().3 - 844.0 * 0.94).abs() < 0.01)
  k.content.set(100.0)
  if draw_short { t.draw() }
  k.content.set(580.0)
  t.draw()
  k.surface.val.unwrap().rect().3
}

///|
test "a fitted sheet's detent is independent of a frame between content changes" {
  // The old sheet receives the same sequence of requested heights: it resets its detent only if it built in between.
  let old_with = old_fitted_detent_after_changes(true)
  let old_without = old_fitted_detent_after_changes(false)
  assert_true((old_with - 844.0 * 0.7).abs() < 0.01, msg="old with: \{old_with}")
  assert_true((old_without - 844.0 * 0.94).abs() < 0.01, msg="old without: \{old_without}")
  let with_frame = fitted_detent_after_changes(true)
  let without_frame = fitted_detent_after_changes(false)
  assert_true((with_frame - without_frame).abs() < 0.01, msg="with: \{with_frame}, without: \{without_frame}")
  assert_true((with_frame - 844.0 * 0.94).abs() < 0.01, msg="retained: \{with_frame}")
}
