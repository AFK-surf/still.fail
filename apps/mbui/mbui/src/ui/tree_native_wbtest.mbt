// System views in the retained tree: the host and the hole receive the same geometry and the caller owns the view.

///|
fn tree_native_rect(v : NativeView) -> (Double, Double, Double, Double, Double, Double, Double, Double) {
  (v.at[0], v.at[1], v.at[2], v.at[3], v.at[4], v.at[5], v.at[6], v.at[7])
}

///|
test "native tree fills its node, follows content, scale and clipping, hides and can be attached again" {
  let shown = @signals.signal(true, same=fn(a, b) { a == b })
  let at = @signals.signal((10.0, 5.0, 100.0, 80.0), same=fn(a, b) { a == b })
  let zoom = @signals.signal(1.0, same=fn(a, b) { a == b })
  let offset = @signals.signal(0.0, same=fn(a, b) { a == b })
  let t = Tester::new(fn(_) {  }, w=400.0, h=200.0)
  t.check_looks(false)
  let page = NativeView::page("<p>page</p>")
  set_view_app(fn(root) {
    root.box(fn(stage) {
      stage.over(Is(true)).width(Is(Some(200.0))).height(Is(Some(100.0))).clips(Is(true))
      .offset(By(fn() { (offset.get(), 0.0) })).scale(By(fn() { zoom.get() }), about=At(0.0, 0.0)) |> ignore
      stage.show(fn() { shown.get() }, fn(slot) {
        native_view(slot, page, content=fn(_, _) { Some(at.get()) }, page_scale=fn() { zoom.get() })
        .over(Is(true)).corners(Is(Some((4.0, 8.0, 12.0, 16.0)))) |> ignore
      })
    }) |> ignore
  })
  t.draw()
  assert_eq(tree_native_rect(page), (10.0, 5.0, 100.0, 80.0, 0.0, 0.0, 200.0, 100.0))
  assert_eq((page.at[8], page.at[9], page.at[10], page.at[11]), (4.0, 8.0, 12.0, 16.0))
  assert_eq(t.holes(), [(10.0, 5.0, 100.0, 80.0)])
  at.set((-20.0, 10.0, 160.0, 90.0))
  offset.set(20.0)
  zoom.set(0.5)
  t.frame()
  assert_eq(tree_native_rect(page), (10.0, 5.0, 80.0, 45.0, 20.0, 0.0, 120.0, 50.0))
  assert_eq((page.at[8], page.at[9], page.at[10], page.at[11]), (2.0, 4.0, 6.0, 8.0))
  assert_eq(page.scale, 0.5)
  assert_true(t.views().contains("control \{page.id} 8 0.5"))
  shown.set(false)
  t.frame()
  assert_false(page.told_shown)
  assert_false(page.closed)
  shown.set(true)
  t.frame()
  assert_true(page.told_shown)
  page.close()
  t.frames_owed()
  assert_true(page.closed)
  assert_true(t.holes().is_empty())
}

///|
test "native tree surfaces stack in drawing order and tree controls cover only what they take" {
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let x = @signals.signal(0.0, same=fn(a, b) { a == b })
  let modal = @signals.signal(false, same=fn(a, b) { a == b })
  let t = Tester::new(fn(_) {  }, w=400.0, h=200.0)
  t.check_looks(false)
  let back = NativeView::page("<p>back</p>")
  let front = NativeView::page("<p>front</p>")
  set_view_app(fn(root) {
    root.box(fn(stage) {
      stage.over(Is(true)) |> ignore
      native_view(stage, back).over(Is(true)) |> ignore
      native_view(stage, front).over(Is(true)) |> ignore
      stage.box(fn(b) {
        b.over(Is(true)).width(Is(Some(80.0))).height(Is(Some(40.0)))
        .offset(By(fn() { (x.get(), 0.0) })).presses(By(fn() { on.get() }))
        .takes(fn(w, h, _) { [(w / 2.0, 0.0, w, h)] }).on_press(fn() {  }) |> ignore
      }) |> ignore
      stage.show(fn() { modal.get() }, fn(m) {
        m.box(fn(b) { b.over(Is(true)).modal(Is(true)) |> ignore }) |> ignore
      })
    }) |> ignore
  })
  t.draw()
  assert_eq(stacked_views, [back.id, front.id])
  assert_eq(covers_of(front), [40.0, 0.0, 80.0, 40.0])
  x.set(100.0)
  t.frame()
  assert_eq(covers_of(front), [140.0, 0.0, 180.0, 40.0])
  on.set(false)
  t.frame()
  assert_eq(covers_of(front), [])
  modal.set(true)
  t.frame()
  assert_eq(covers_of(front), whole_of(front))
  modal.set(false)
  t.frame()
  assert_eq(covers_of(front), [])
}

///|
test "native tree site state is followed when the host changes address and navigation" {
  let t = Tester::new(fn(_) {  }, w=300.0, h=200.0)
  t.check_looks(false)
  let site = NativeView::site("/start", fn(_, reply) { reply.end() })
  let read : Ref[(String, Bool, Bool, Bool, String)] = Ref(site.page_at())
  set_view_app(fn(root) {
    root.reacts(fn() { site.page_at() }, fn(now) { read.val = now })
    native_view(root, site) |> ignore
  })
  t.draw()
  assert_true(t.view_said("{\"sitestate\":{\"view\":\{site.id},\"state\":{\"path\":\"/next\",\"back\":true,\"forward\":false,\"loading\":false,\"title\":\"Next\"}}}"))
  assert_true(t.view_said("{\"info\":{\"view\":\{site.id},\"state\":1,\"at\":[0,0,0,0,0,0,0,0,0,0]}}"))
  t.draw()
  t.frames_owed()
  assert_eq(read.val, ("/next", true, false, false, "Next"))
  site.load("/other")
  assert_eq(site.page_at().0, "/other")
  assert_true(t.view_said("{\"sitestate\":{\"view\":\{site.id},\"state\":{\"path\":\"/other\",\"back\":true,\"forward\":false,\"loading\":true,\"title\":\"Next\"}}}"))
  t.frames_owed()
  assert_eq(read.val.0, "/other")
}
