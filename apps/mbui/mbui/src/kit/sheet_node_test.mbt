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
fn node_sheet_case(tall? : Double = 0.0, fit? : Bool = false, grows? : Bool = false, under? : Double = 0.0, draggable? : Bool = true, sticky? : @view.LayoutCap, tall_now? : () -> Double) -> (@ui.Tester, NodeSheetCase) {
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
      tall~, fit~, grows~, under~, draggable~, sticky?, tall_now?, label=fn() { "Sheet" },
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
test "a natural sheet can remember overflow across content, window and sheet changes" {
  for frame in [false, true] {
    let memory = @view.LayoutCap::new()
    let (t, k) = node_sheet_case(sticky=memory)
    t.run_for(sheet_test_late_ms)
    let cap = 844.0 * 0.94
    assert_eq(k.extent.val.unwrap().rect().3, 225.0)
    k.content.set(1000.0)
    if frame { t.draw() }
    k.content.set(100.0)
    t.draw()
    assert_true((k.extent.val.unwrap().rect().3 - cap).abs() < 0.01,
      msg="overflow is kept after shortening, intermediate frame=\{frame}")
    t.resize(390.0, 640.0)
    assert_true((k.extent.val.unwrap().rect().3 - 640.0 * 0.94).abs() < 0.01)
    k.open.set(false)
    t.run_for(sheet_test_late_ms)
    k.open.set(true)
    t.draw()
    assert_true((k.extent.val.unwrap().rect().3 - 640.0 * 0.94).abs() < 0.01,
      msg="a replacement using the same presentation's memory keeps the cap")
  }
}

///|
test "a natural sheet only remembers content exceeding its cap" {
  let (t, k) = node_sheet_case(sticky=@view.LayoutCap::new())
  t.run_for(sheet_test_late_ms)
  k.content.set(844.0 * 0.94 - 25.0)
  t.draw()
  k.content.set(100.0)
  t.draw()
  assert_eq(k.extent.val.unwrap().rect().3, 125.0)
}

///|
test "a natural sheet does not remember an uncommitted overflow within one change" {
  let (t, k) = node_sheet_case(sticky=@view.LayoutCap::new())
  t.run_for(sheet_test_late_ms)
  @signals.start_batch()
  k.content.set(1000.0)
  k.content.set(100.0)
  @signals.end_batch()
  t.draw()
  assert_eq(k.extent.val.unwrap().rect().3, 125.0)
}

///|
test "a natural sheet ignores an intermediate size read within one event" {
  let (t, k) = node_sheet_case(sticky=@view.LayoutCap::new())
  t.run_for(sheet_test_late_ms)
  let tree = @ui.view_tree().unwrap()
  let measured = Ref(0.0)
  tree.event(t.time(), fn() {
    k.content.set(1000.0)
    measured.val = k.extent.val.unwrap().laid_size().1
    k.content.set(100.0)
  })
  assert_true(measured.val > 700.0)
  t.draw()
  assert_eq(k.extent.val.unwrap().rect().3, 125.0)
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
test "an old sheet surface follows a retained projection and takes a touch before the next frame" {
  let height = @signals.signal(20.0)
  let tapped = Ref(0)
  let button = Ref(0)
  let t = @ui.Tester::new(fn(c) { @ui.old_views_here(c) }, time=0.0, tree=fn(root : @view.View) {
    let extent = root.box(fn(v) {
      v.over(Is(true)).width(Is(Some(1.0))).height(By(fn() { Some(height.get()) })) |> ignore
    })
    let projection = root.box(fn(v) {
      v.over(Is(true)).width(Is(Some(1.0))).height(Is(Some(1.0)))
        .offset(Painted(fn(laid) { (0.0, -laid.size(extent).unwrap_or((0.0, 0.0)).1) })) |> ignore
    })
    @ui.old(root, fn(c) {
      @kit.sheet(c, "old projected", true, h=200.0,
        surface=fn(ctx, i) { ctx.moved_with_node(i, projection) },
        look=fn(ctx, st, body) { ctx.box(w=Fill(1.0), h=Px(st.h), bg=0x3366CCFFL, body) |> ignore },
        fn() {
          let id = c.id("old projected button")
          button.val = id
          c.on_press(id, fn() { tapped.val += 1 })
          c.box(w=Fill(1.0), h=Px(40.0), id~, fn() {  }) |> ignore
        },
      ) |> ignore
    }).over(Is(true)) |> ignore
  })
  t.draw()
  t.run_for(sheet_test_late_ms)
  assert_true(button.val != 0, msg="old sheet did not build its button")
  let before = t.ctx().rect_of(button.val)
  assert_true(before is Some(_), msg="sheet=\{t.drawn_rects().iter().filter(fn(r) { r.4 == 0x3366CCFFL }).to_array()}, button=\{button.val}")
  height.set(100.0)
  t.touch(0, 20.0, 560.0)
  t.touch(2, 20.0, 560.0)
  assert_eq(tapped.val, 1, msg="button before=\{before}, after=\{t.ctx().rect_of(button.val)}")
  t.draw()
  let surface = t.drawn_rects().iter().find_first(fn(r) { r.4 == 0x3366CCFFL }).unwrap()
  assert_eq(surface.1, 544.0)
}

///|
test "tree sheet traps the page, returns focus and keeps only its picture until its exit is over" {
  let (t, k) = node_sheet_case()
  t.run_for(sheet_test_late_ms)
  assert_true(t.query(@ui.Role::Button, label="Page") is None)
  assert_true(t.get(@ui.Role::Dialog, label="Sheet").modal)
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
test "a changing share switches between natural and fixed height without replacing the sheet" {
  let share = @signals.signal(0.0)
  let (t, k) = node_sheet_case(tall_now=fn() { share.get() })
  t.run_for(sheet_test_late_ms)
  let sheet = k.surface.val.unwrap()
  let extent = k.extent.val.unwrap()
  assert_eq(extent.rect().3, 225.0)
  share.set(0.66)
  t.draw()
  assert_true((extent.rect().3 - 844.0 * 0.66).abs() < 0.01)
  k.content.set(40.0)
  t.draw()
  assert_true((extent.rect().3 - 844.0 * 0.66).abs() < 0.01)
  share.set(0.0)
  t.draw()
  assert_eq(extent.rect().3, 65.0)
  assert_eq(k.surface.val.unwrap().id(), sheet.id())
  assert_eq(k.extent.val.unwrap().id(), extent.id())
  assert_eq(k.shown.val, 1)
  assert_eq(k.gone.val, 0)
}

///|
test "a changing fitted share is used at drag release without an intermediate frame" {
  for draw in [false, true] {
    let share = @signals.signal(0.7)
    let (t, k) = node_sheet_case(tall_now=fn() { share.get() }, fit=true, grows=true)
    k.content.set(580.0)
    t.run_for(sheet_test_late_ms)
    let sheet = k.surface.val.unwrap()
    let y = sheet.rect().1 + 10.0
    t.touch(0, 190.0, y)
    t.touch(1, 190.0, y - 80.0)
    share.set(0.9)
    if draw { t.draw() }
    t.touch(2, 190.0, y - 80.0)
    t.run_for(sheet_test_late_ms)
    assert_eq(sheet.rect().3, 605.0, msg="frame=\{draw}")
  }
}

///|
test "tree sheet can fit changing contents up to a share and only enables detents near that limit" {
  let (t, k) = node_sheet_case(tall=0.7, fit=true, grows=true, sticky=@view.LayoutCap::new())
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
test "tree sheet uses the current fitted content at the release of a drag" {
  for draw in [false, true] {
    let (t, k) = node_sheet_case(tall=0.7, fit=true, grows=true)
    t.run_for(sheet_test_late_ms)
    let sheet = k.surface.val.unwrap()
    let y = sheet.rect().1 + 10.0
    t.touch(0, 190.0, y)
    t.touch(1, 190.0, y - 80.0)
    // The body grows while the finger is down, with or without a frame before release.
    k.content.set(580.0)
    if draw { t.draw() }
    t.touch(2, 190.0, y - 80.0)
    t.run_for(sheet_test_late_ms)
    assert_true((sheet.rect().3 - 844.0 * 0.55).abs() < 0.01, msg="frame=\{draw}, height after release: \{sheet.rect().3}")
  }
}

///|
test "tree sheet stops offering detents when fitted content becomes short during a drag" {
  for draw in [false, true] {
    let (t, k) = node_sheet_case(tall=0.7, fit=true, grows=true)
    k.content.set(580.0)
    t.run_for(sheet_test_late_ms)
    let sheet = k.surface.val.unwrap()
    let y = sheet.rect().1 + 10.0
    t.touch(0, 190.0, y)
    t.touch(1, 190.0, y - 80.0)
    k.content.set(100.0)
    if draw { t.draw() }
    t.touch(2, 190.0, y - 80.0)
    t.run_for(sheet_test_late_ms)
    assert_eq(sheet.rect().3, 125.0, msg="frame=\{draw}")
  }
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
fn sheet_owner_removed_in_layout(draw_first : Bool) -> (Double, Int) raise {
  let owner_shown = @signals.signal(true)
  let open = @signals.signal(true)
  let content = @signals.signal(120.0)
  let sheet : Ref[@view.View?] = Ref(None)
  let extent : Ref[@view.View?] = Ref(None)
  let gone = Ref(0)
  let t = @ui.Tester::new(fn(_) {  }, time=0.0, tree=fn(root : @view.View) {
    root.box(fn(page) {
      page.height(Is(Some(20.0))).layout_box(By(fn() { owner_shown.get() }), fn(l, visible) {
        if visible {
          let owner = l.child("owner", fn(v) { v.owns(fn() { open.set(false) }) |> ignore })
          l.measure(owner, l.width) |> ignore
          l.place(owner, 0.0, 0.0)
        }
      }) |> ignore
    }) |> ignore
    @kit.sheet_node(root, fn() { open.get() }, fn() { open.set(false) },
      extent=fn(v) { extent.val = Some(v) }, gone=fn() { gone.val += 1 }, fn(s) {
        sheet.val = Some(s)
        s.box(fn(body) { body.height(By(fn() { Some(content.get()) })) |> ignore }) |> ignore
      })
  })
  t.run_for(sheet_test_late_ms)
  let tree = @ui.view_tree().unwrap()
  tree.event(t.time(), fn() { content.set(200.0); owner_shown.set(false) })
  assert_false(open.get(), msg="owner's removal is taken at the change, without a frame")
  assert_eq(extent.val.unwrap().laid_size().1, 200.0)
  if draw_first { t.draw() }
  t.run_for(sheet_test_150_ms)
  (sheet.val.unwrap().rect().1, gone.val)
}

///|
test "tree sheet closes from a layout-removed owner at the same moment with or without a frame" {
  assert_eq(sheet_owner_removed_in_layout(false), sheet_owner_removed_in_layout(true))
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
test "sheets leave the existing editor focused by default and return it on closing" {
  for legacy in [true, false] {
    let open = @signals.signal(false)
    let field = @ui.Field::new()
    let t = if legacy {
      @ui.Tester::new(fn(c) {
        c.editor("page-field", placeholder="Page field", field~) |> ignore
        @kit.sheet(c, "focus-sheet", open.get(), h=200.0, fn() { @kit.button(c, "Inside") |> ignore }) |> ignore
      })
    } else {
      @ui.Tester::new(fn(_) {  }, tree=fn(root : @view.View) {
        @ui.field(root, field, placeholder="Page field") |> ignore
        @kit.sheet_node(root, fn() { open.get() }, fn() { open.set(false) }, fn(s) {
          s.box(fn(v) {
            v.height(Is(Some(200.0))).focusable(Is(true)).says(Is(Some(@view.said(Button, label="Inside")))) |> ignore
          }) |> ignore
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
    // The old sheet leaves an old editor accepting text. The retained sheet keeps the focus but must not send text
    // to a covered editor; in the mixed old-sheet / retained-editor case the old sheet also blocks the text.
    assert_eq(field.text(), if legacy { "x" } else { "" }, msg="legacy=\{legacy}: typing while open")
    t.tab()
    assert_eq(t.focused().unwrap().label, "Inside", msg="legacy=\{legacy}: Tab enters sheet")
    open.set(false)
    t.draw()
    assert_eq(t.ctx().focused_id(), before, msg="legacy=\{legacy}: focus after close")
  }
}

///|
test "a tree sheet keeps covered editors focused and routes text as an old sheet does" {
  for old_editor in [false, true] {
    for intermediate in [false, true] {
      let open = @signals.signal(false)
      let field = @ui.Field::new()
      let t = @ui.Tester::new(fn(c) { @ui.old_views_here(c) }, time=0.0, tree=fn(root : @view.View) {
        if old_editor {
          @ui.old(root, fn(c) { c.editor("page-field", placeholder="Page field", field~) |> ignore })
          .height(Is(Some(40.0))) |> ignore
        } else {
          @ui.field(root, field, placeholder="Page field") |> ignore
        }
        @kit.sheet_node(root, fn() { open.get() }, fn() { open.set(false) }, fn(s) {
          s.box(fn(v) { v.height(Is(Some(200.0))) |> ignore }) |> ignore
        })
      })
      t.draw()
      t.tap_text("Page field")
      let before = t.ctx().focused_id()
      assert_true(before != 0)
      open.set(true)
      if intermediate { t.draw() }
      t.text_told("x", t.time())
      assert_eq(t.ctx().focused_id(), before, msg="old editor=\{old_editor}, intermediate=\{intermediate}")
      assert_eq(field.text(), if old_editor { "x" } else { "" }, msg="old editor=\{old_editor}, intermediate=\{intermediate}")
      open.set(false)
      t.text_told("y", t.time())
      assert_eq(t.ctx().focused_id(), before)
      let expected = if old_editor { "xy" } else if intermediate { "" } else { "y" }
      assert_eq(field.text(), expected, msg="old editor=\{old_editor}, closing frame=\{intermediate}")
      if intermediate {
        t.draw()
        t.text_told("z", t.time())
        assert_eq(field.text(), if old_editor { "xyz" } else { "z" })
      }
    }
  }
}

///|
test "old and tree sheets route a covered tree editor alike" {
  let results : Array[(Bool, String, String)] = []
  for old_sheet in [true, false] {
    let open = @signals.signal(false)
    let field = @ui.Field::new()
    let page_field : Ref[@view.View?] = Ref(None)
    let t = @ui.Tester::new(fn(c) { @ui.old_views_here(c) }, time=0.0, tree=fn(root : @view.View) {
      page_field.val = Some(@ui.field(root, field, placeholder="Page field"))
      if old_sheet {
        @ui.old(root, fn(c) {
          @kit.sheet(c, "old focus sheet", open.get(), h=200.0, fn() {  }) |> ignore
        }).over(Is(true)) |> ignore
      } else {
        @kit.sheet_node(root, fn() { open.get() }, fn() { open.set(false) }, fn(s) {
          s.box(fn(v) { v.height(Is(Some(200.0))) |> ignore }) |> ignore
        })
      }
    })
    t.draw()
    t.act(TextField, Focus, label="Page field")
    open.set(true)
    t.draw()
    let focused = page_field.val.unwrap().focused()
    t.text_told("x", t.time())
    let covered = field.text()
    open.set(false)
    t.draw()
    t.text_told("y", t.time())
    results.push((focused, covered, field.text()))
  }
  assert_eq(results, [(true, "", "y"), (true, "", "y")])
}

///|
test "old and tree sheets keep a covered tree field from text until the state-close frame" {
  for (old_sheet, frame) in [(true, false), (true, true), (false, false), (false, true)] {
    let open = @signals.signal(false)
    let field = @ui.Field::new()
    let t = @ui.Tester::new(fn(c) { @ui.old_views_here(c) }, time=0.0, tree=fn(root : @view.View) {
      @ui.field(root, field, placeholder="Page field") |> ignore
      if old_sheet {
        @ui.old(root, fn(c) {
          @kit.sheet(c, "old sheet", open.get(), h=200.0, fn() {  }) |> ignore
        }).over(Is(true)) |> ignore
      } else {
        @kit.sheet_node(root, fn() { open.get() }, fn() { open.set(false) }, fn(s) {
          s.box(fn(v) { v.height(Is(Some(200.0))) |> ignore }) |> ignore
        })
      }
    })
    t.draw()
    t.act(TextField, Focus, label="Page field")
    open.set(true)
    t.run_for(sheet_test_late_ms)
    open.set(false)
    if frame { t.draw() }
    t.text_told("y", t.time())
    assert_eq(field.text(), if frame { "y" } else { "" }, msg="old=\{old_sheet}, closing frame=\{frame}")
  }
}

///|
test "old and tree sheets dismissed by input return typing before the next frame" {
  for (old_sheet, input) in [(true, 0), (true, 1), (true, 2), (false, 0), (false, 1), (false, 2)] {
    let open = @signals.signal(false)
    let field = @ui.Field::new()
    let t = @ui.Tester::new(fn(c) { @ui.old_views_here(c) }, time=0.0, tree=fn(root : @view.View) {
      @ui.field(root, field, placeholder="Page field") |> ignore
      if old_sheet {
        @ui.old(root, fn(c) {
          c.with_dismissed(fn(_) { open.set(false) }, fn() {
            @kit.sheet(c, "old sheet", open.get(), h=200.0, fn() {  }) |> ignore
          })
        }).over(Is(true)) |> ignore
      } else {
        @kit.sheet_node(root, fn() { open.get() }, fn() { open.set(false) }, fn(s) {
          s.box(fn(v) { v.height(Is(Some(200.0))) |> ignore }) |> ignore
        })
      }
    })
    t.draw()
    t.act(TextField, Focus, label="Page field")
    open.set(true)
    t.run_for(sheet_test_late_ms)
    if input == 0 {
      t.key_told(@ui.key_escape, 0, t.time())
    } else if input == 1 {
      t.touch(0, 10.0, 10.0)
      t.touch(2, 10.0, 10.0)
    } else {
      t.back_raw(2, 0.0, t.time())
    }
    assert_false(open.get())
    t.text_told("y", t.time())
    assert_eq(field.text(), "y", msg="old=\{old_sheet}, input=\{input}")
  }
}

///|
test "old and tree sheet state closes expose the same input method across the next frame" {
  for frame in [false, true] {
    let states : Array[(Bool, Bool, Bool)] = []
    for old_sheet in [true, false] {
      let open = @signals.signal(false)
      let field = @ui.Field::new()
      let t = @ui.Tester::new(fn(c) { @ui.old_views_here(c) }, time=0.0, tree=fn(root : @view.View) {
        @ui.field(root, field, placeholder="Page field") |> ignore
        if old_sheet {
          @ui.old(root, fn(c) {
            @kit.sheet(c, "old sheet", open.get(), h=200.0, fn() {  }) |> ignore
          }).over(Is(true)) |> ignore
        } else {
          @kit.sheet_node(root, fn() { open.get() }, fn() { open.set(false) }, fn(s) {
            s.box(fn(v) { v.height(Is(Some(200.0))) |> ignore }) |> ignore
          })
        }
      })
      t.draw()
      t.act(TextField, Focus, label="Page field")
      let before = t.ime().0
      open.set(true)
      t.run_for(sheet_test_late_ms)
      let covered = t.ime().0
      open.set(false)
      if frame { t.draw() }
      states.push((before, covered, t.ime().0))
    }
    assert_eq(states[0], states[1], msg="old=\{states[0]}, tree=\{states[1]}, closing frame=\{frame}")
  }
}

///|
test "a sheet opened above a just closed sheet accepts its own field before a frame" {
  for old_sheet in [true, false] {
    let lower_open = @signals.signal(false)
    let upper_open = @signals.signal(false)
    let upper_field = @ui.Field::new()
    let upper_focus : Ref[@view.View?] = Ref(None)
    let t = @ui.Tester::new(fn(c) { @ui.old_views_here(c) }, time=0.0, tree=fn(root : @view.View) {
      root.box(fn(lower) {
        lower.stacked(Is(1)) |> ignore
        if old_sheet {
          @ui.old(lower, fn(c) {
            @kit.sheet(c, "old sheet", lower_open.get(), h=200.0, fn() {  }) |> ignore
          }).over(Is(true)) |> ignore
        } else {
          @kit.sheet_node(lower, fn() { lower_open.get() }, fn() { lower_open.set(false) }, fn(s) {
            s.box(fn(v) { v.height(Is(Some(200.0))) |> ignore }) |> ignore
          })
        }
      }) |> ignore
      root.box(fn(upper) {
        upper.stacked(Is(2)) |> ignore
        @kit.sheet_node(upper, fn() { upper_open.get() }, fn() { upper_open.set(false) },
          initial_focus=fn() { upper_focus.val }, fn(s) {
            upper_focus.val = Some(@ui.field(s, upper_field, placeholder="Upper field"))
          })
      }) |> ignore
    })
    t.draw()
    lower_open.set(true)
    t.run_for(sheet_test_late_ms)
    lower_open.set(false)
    upper_open.set(true)
    t.text_told("x", t.time())
    assert_eq(upper_field.text(), "x", msg="old lower sheet=\{old_sheet}")
  }
}

///|
test "a state close during an old build releases sheet typing in that frame" {
  for old_sheet in [true, false] {
    let open = @signals.signal(false)
    let closing = @signals.signal(false)
    let field = @ui.Field::new()
    let t = @ui.Tester::new(fn(c) { @ui.old_views_here(c) }, time=0.0, tree=fn(root : @view.View) {
      @ui.field(root, field, placeholder="Page field") |> ignore
      @ui.old(root, fn(c) {
        if closing.get() { open.set(false) }
        if old_sheet { @kit.sheet(c, "old sheet", open.get(), h=200.0, fn() {  }) |> ignore }
      }).over(Is(true)) |> ignore
      if !old_sheet {
        @kit.sheet_node(root, fn() { open.get() }, fn() { open.set(false) }, fn(s) {
          s.box(fn(v) { v.height(Is(Some(200.0))) |> ignore }) |> ignore
        })
      }
    })
    t.draw()
    t.act(TextField, Focus, label="Page field")
    open.set(true)
    t.run_for(sheet_test_late_ms)
    closing.set(true)
    t.draw()
    assert_false(open.get())
    t.text_told("y", t.time())
    assert_eq(field.text(), "y", msg="old sheet=\{old_sheet}")
  }
}

///|
test "a tree sheet can focus its own editor and return to the covered one" {
  for intermediate in [false, true] {
    let open = @signals.signal(false)
    let underneath = @ui.Field::new()
    let inside = @ui.Field::new()
    let initial : Ref[@view.View?] = Ref(None)
    let t = @ui.Tester::new(fn(_) {  }, time=0.0, tree=fn(root : @view.View) {
      @ui.field(root, underneath, placeholder="Page field") |> ignore
      @kit.sheet_node(root, fn() { open.get() }, fn() { open.set(false) }, initial_focus=fn() { initial.val }, fn(s) {
        initial.val = Some(@ui.field(s, inside, placeholder="Sheet field"))
      })
    })
    t.draw()
    t.act(TextField, Focus, label="Page field")
    open.set(true)
    if intermediate { t.draw() }
    t.text_told("x", t.time())
    assert_eq((underneath.text(), inside.text()), ("", "x"), msg="intermediate=\{intermediate}")
    open.set(false)
    t.text_told("y", t.time())
    assert_eq((underneath.text(), inside.text()), ("y", "x"), msg="intermediate=\{intermediate}")
  }
}

///|
test "a typing menu above a sheet cannot type through the sheet into its covered field" {
  let open_sheet = @signals.signal(false)
  let open_menu = @signals.signal(false)
  let field = @ui.Field::new()
  let t = @ui.Tester::new(fn(_) {  }, time=0.0, tree=fn(root : @view.View) {
    @ui.field(root, field, placeholder="Page field") |> ignore
    @kit.sheet_node(root, fn() { open_sheet.get() }, fn() { open_sheet.set(false) }, fn(s) {
      s.box(fn(v) { v.height(Is(Some(200.0))) |> ignore }) |> ignore
    })
    root.show(fn() { open_menu.get() }, fn(menu) {
      menu.over(Is(true)).stacked(Is(3)).modal(Is(true)).leaves_typing().focus_returns() |> ignore
    })
  })
  t.draw()
  t.act(TextField, Focus, label="Page field")
  open_sheet.set(true)
  open_menu.set(true)
  t.text_told("x", t.time())
  assert_eq(field.text(), "")
  open_menu.set(false)
  t.text_told("y", t.time())
  assert_eq(field.text(), "")
  open_sheet.set(false)
  t.text_told("z", t.time())
  assert_eq(field.text(), "z")
}

///|
test "a typing menu can leave text to a field within the sheet below it" {
  let open_menu = @signals.signal(false)
  let field = @ui.Field::new()
  let t = @ui.Tester::new(fn(_) {  }, time=0.0, tree=fn(root : @view.View) {
    @kit.sheet_node(root, fn() { true }, fn() {  }, fn(s) {
      @ui.field(s, field, placeholder="Sheet field") |> ignore
    })
    root.show(fn() { open_menu.get() }, fn(menu) {
      menu.over(Is(true)).stacked(Is(3)).modal(Is(true)).leaves_typing().focus_returns() |> ignore
    })
  })
  t.draw()
  t.run_for(sheet_test_late_ms)
  t.act(TextField, Focus, label="Sheet field")
  open_menu.set(true)
  t.text_told("x", t.time())
  assert_eq(field.text(), "x")
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
