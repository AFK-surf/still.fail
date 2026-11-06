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
  heights : Array[Double]
  shown : Ref[Int]
  gone : Ref[Int]
  pressed : Ref[Int]
  surface : Ref[@view.View?]
}

///|
fn node_sheet_case(tall? : Double = 0.0, grows? : Bool = false, under? : Double = 0.0, draggable? : Bool = true) -> (@ui.Tester, NodeSheetCase) {
  let k : NodeSheetCase = {
    open: @signals.signal(true), content: @signals.signal(200.0), sinks: @signals.signal(0.0), heights: [],
    shown: Ref(0), gone: Ref(0), pressed: Ref(0), surface: Ref(None),
  }
  let t = @ui.Tester::new(fn(_) {  }, time=0.0, tree=fn(root : @view.View) {
    root.box(fn(page) {
      page.height(Is(Some(40.0))).focusable(Is(true)).says(Is(Some(@view.said(Button, label="Page")))) |> ignore
    }) |> ignore
    @kit.sheet_node(
      root, fn() { k.open.get() }, fn() { k.open.set(false) },
      tall~, grows~, under~, draggable~, label=fn() { "Sheet" },
      sinks=fn() { k.sinks.get() },
      height=fn(h) { k.heights.push(h) },
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
  assert_eq(k.heights.last(), Some(225.0))
  let sheet = k.surface.val.unwrap()
  assert_eq(sheet.rect().1, 844.0 - 225.0)
  k.content.set(300.0)
  t.draw()
  assert_eq(k.heights.last(), Some(325.0))
  assert_eq(sheet.rect().1, 844.0 - 325.0)
  t.post(@hostapi.system_channel, "{\"bars\":{\"top\":0,\"bottom\":24,\"left\":0,\"right\":0}}")
  t.draw()
  assert_eq(k.heights.last(), Some(349.0))
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
  assert_true(k.open.get(), msg="sheet=\{k.surface.val.unwrap().rect()}, heights=\{k.heights}")
  assert_eq(k.heights.last(), Some(225.0))
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
  assert_eq(k.heights.last(), Some(422.0))
  assert_eq(k.surface.val.unwrap().rect().1, 422.0)
}

///|
test "tree sheet detents: the grabber toggles the sheet and the reported stack height stays its requested height" {
  let (t, k) = node_sheet_case(tall=0.55, grows=true)
  t.run_for(sheet_test_late_ms)
  let y = k.surface.val.unwrap().rect().1 + 10.0
  t.tap(190.0, y)
  t.run_for(sheet_test_late_ms)
  assert_true((k.surface.val.unwrap().rect().3 - 844.0 * 0.94).abs() < 0.01)
  assert_true((k.heights.last().unwrap() - 844.0 * 0.55).abs() < 0.01)
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
test "a sheet's reported height reaches the sheet below in the first layout that shows it" {
  let top_open = @signals.signal(false)
  let top_height = @signals.signal(0.0)
  let lower : Ref[@view.View?] = Ref(None)
  let t = @ui.Tester::new(fn(_) {  }, time=0.0, tree=fn(root : @view.View) {
    @kit.sheet_node(root, fn() { true }, fn() {  }, raised=fn() { top_height.get() / 4.0 }, fn(s) {
      lower.val = Some(s)
      s.box(fn(b) { b.height(Is(Some(200.0))) |> ignore }) |> ignore
    })
    @kit.sheet_node(root, fn() { top_open.get() }, fn() {  }, height=fn(h) { top_height.set(h) }, fn(s) {
      s.box(fn(b) { b.height(Is(Some(240.0))) |> ignore }) |> ignore
    })
  })
  t.run_for(sheet_test_late_ms)
  let base = lower.val.unwrap().rect().1
  top_open.set(true)
  t.frame()
  assert_eq(top_height.get(), 240.0)
  assert_eq(lower.val.unwrap().rect().1, base - 60.0)
}
