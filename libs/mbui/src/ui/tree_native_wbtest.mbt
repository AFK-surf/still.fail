// A native view as a node of the window's tree (ui's native, tree_native.mbt): the host told where it stands from where
// the tree draws its node, as that changes (scrolled with its row in a page's list, moved by what holds it, the window
// resized), hidden while its node is not drawn (scrolled far out and put by) and shown again as it comes back, closed
// only as its node is let go (or not, kept by the app), what of the tree's is drawn over it over it.

///|
/// A page's list 300 by 400 on a host keeping groups, its rows 50 high but key 2's and key 4's, 120 high each holding a
/// native view of its own (opened of the Tester's host), kept past its node by the app where `kept` (as a chat keeps its
/// visualizations): drawn.
fn native_list(kept? : Bool = false) -> (Tester, @view.Scroll, Array[NativeView]) {
  let s = @view.Scroll::list()
  let t = Tester::new(fn(_) {  }, w=300.0, h=400.0, platform=0)
  let pages = [NativeView::page("<p>a</p>"), NativeView::page("<p>b</p>")]
  t.set_groups(true)
  t.set_rows_on_pixels(true)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(col) {
      col.width(Is(Some(300.0))).height(Is(Some(400.0))) |> ignore
      col.scrolls_window(s, fn() { Array::makei(30, fn(i) { i }) }, est=50.0, fn(b, k) {
        if k == 2 || k == 4 {
          native(b, pages[if k == 2 { 0 } else { 1 }], kept~).width(Is(Some(300.0))).height(Is(Some(120.0))) |> ignore
        } else {
          b.box(fn(l) { l.words(Is("行 \{k}")).height(Is(Some(50.0))) |> ignore }) |> ignore
        }
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  (t, s, pages)
}

///|
/// Where the host has `v`: its rect seen, and "hidden" where it is told so; "none" never placed or closed.
fn stands(t : Tester, v : NativeView) -> String {
  match t.view_stands(v) {
    Some((x0, y0, x1, y1, shown)) => "\{x0} \{y0} \{x1} \{y1}" + (if shown { "" } else { " hidden" })
    None => "none"
  }
}

///|
test "native views in a page's list's rows: the host told where each stands as the tree draws it, both moving with their rows as the list scrolls, cut by what shows" {
  let (t, s, pages) = native_list()
  inspect(stands(t, pages[0]), content="0 100 300 220")
  inspect(stands(t, pages[1]), content="0 270 300 390")
  s.put(60.0)
  t.draw()
  inspect(stands(t, pages[0]), content="0 40 300 160")
  inspect(stands(t, pages[1]), content="0 210 300 330")
  // (the first part way out over the top: what shows of it)
  s.put(150.0)
  t.draw()
  inspect(stands(t, pages[0]), content="0 0 300 70")
  inspect(stands(t, pages[1]), content="0 120 300 240")
}

///|
test "a native view in a page's list's row scrolled far out, its block let go: closed with it; one the app keeps, hidden, and shown again where its row is made anew as it comes back" {
  let (t, s, pages) = native_list()
  s.put(1240.0)
  t.draw()
  inspect(stands(t, pages[0]), content="none")
  assert_true(t.views().contains("close \{pages[0].id()}"))
  let (t, s, pages) = native_list(kept=true)
  s.put(1240.0)
  t.draw()
  inspect(stands(t, pages[0]), content="0 100 300 220 hidden")
  inspect(stands(t, pages[1]), content="0 270 300 390 hidden")
  s.put(0.0)
  t.draw()
  inspect(stands(t, pages[0]), content="0 100 300 220")
  inspect(stands(t, pages[1]), content="0 270 300 390")
  assert_false(t.views().iter().any(fn(l) { l.has_prefix("close") }))
}

///|
test "a native view moved by what holds it and the window resized: told where it is drawn each time" {
  let at = @signals.signal((0.0, 0.0), same=fn(a, b) { a == b })
  let t = Tester::new(fn(_) {  }, w=300.0, h=400.0, platform=0)
  t.check_looks(false)
  let page = NativeView::page("<p>a</p>")
  set_view_app(fn(root) {
    root.box(fn(b) {
      b.offset(By(fn() { at.get() })) |> ignore
      native(b, page).height(Is(Some(80.0))) |> ignore
    })
    |> ignore
  })
  t.draw()
  inspect(stands(t, page), content="0 0 300 80")
  at.set((40.0, 30.0))
  t.draw()
  inspect(stands(t, page), content="40 30 340 110")
  t.resize(500.0, 400.0)
  inspect(stands(t, page), content="40 30 540 110")
}

///|
test "a native view's node let go: its view closed; one the app keeps past its node only hidden" {
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let t = Tester::new(fn(_) {  }, w=300.0, h=400.0, platform=0)
  t.check_looks(false)
  let owned = NativeView::page("<p>a</p>")
  let kept = NativeView::page("<p>b</p>")
  set_view_app(fn(root) {
    root.show(fn() { on.get() }, at_once=true, fn(s) {
      native(s, owned).height(Is(Some(50.0))) |> ignore
      native(s, kept, kept=true).height(Is(Some(50.0))) |> ignore
    })
  })
  t.draw()
  inspect(stands(t, owned), content="0 0 300 50")
  inspect(stands(t, kept), content="0 50 300 100")
  on.set(false)
  t.draw()
  inspect(stands(t, owned), content="none")
  inspect(stands(t, kept), content="0 50 300 100 hidden")
  assert_true(t.views().contains("close \{owned.id()}"))
  assert_false(t.views().contains("close \{kept.id()}"))
}

///|
test "a native view of the tree's: what takes a press drawn over it after it told the host as its covers, its hole drawn under it" {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  t.check_looks(false)
  let page = NativeView::page("<p>page</p>")
  set_view_app(fn(root) {
    root.box(fn(b) {
      b.over(Is(true)).width(Is(Some(400.0))).height(Is(Some(200.0))) |> ignore
      native(b, page).over(Is(true)).width(Is(Some(400.0))).height(Is(Some(200.0))) |> ignore
      b.box(fn(o) {
        o
        .over(Is(true))
        .width(Is(Some(80.0)))
        .height(Is(Some(40.0)))
        .ground(Is(0x777777FFL))
        .says(Is(Some(@view.said(Button, label="over"))))
        .on_press(fn() {  })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.frame_at(t.time() + frame_period_default)
  inspect(stands(t, page), content="0 0 400 200")
  assert_eq(covers_of(page), [0.0, 0.0, 80.0, 40.0])
  // (its hole first among what is drawn, the box over it after)
  assert_eq(t.holes(), [(0.0, 0.0, 400.0, 200.0)])
}

///|
test "a node's binding asking whether a native view's host is done drawing it: done again as the host says so, how the view stands not said to change with it" {
  let t = Tester::new(fn(_) {  }, w=300.0, h=400.0, platform=0, finish=false)
  t.check_looks(false)
  let page = NativeView::page("<p>a</p>")
  set_view_app(fn(root) {
    native(root, page).height(Is(Some(50.0))) |> ignore
    root.box(fn(l) {
      l.words(By(fn() { if page.host_done() { "drawn" } else { "waiting" } })).height(Is(Some(20.0))) |> ignore
    })
    |> ignore
  })
  t.draw()
  assert_true(t.rect_of("waiting") is Some(_))
  // (the host's word alone, as a host says it at a moment of its own: no outside_stood with it)
  on_outside(outside_view, page.id(), 1)
  t.draw()
  assert_true(t.rect_of("drawn") is Some(_), msg="the binding done again as the host said it was done")
}

///|
test "what a page says, bound by a node of the tree's: laid out and drawn by the frame that takes it, that frame painted alone the same as built whole" {
  let tall = @signals.signal(120.0, same=fn(a, b) { a == b })
  let t = Tester::new(fn(_) {  }, w=300.0, h=400.0, platform=2)
  let page = NativeView::page("<p>a</p>", said=fn(words) {
    if words == "taller" {
      tall.set(232.0)
    }
  })
  set_view_app(fn(root) {
    root.box(fn(fr) {
      fr.width(Is(Some(300.0))).height(By(fn() { Some(tall.get()) })) |> ignore
      native(fr, page).width(Is(Some(300.0))).grow(Is(1.0)) |> ignore
    })
    |> ignore
    root.box(fn(l) { l.words(Is("under it")).height(Is(Some(20.0))) |> ignore }) |> ignore
  })
  t.draw()
  t.run_for(move_most_ms)
  inspect(stands(t, page), content="0 0 300 120")
  t.view_says(page.id(), "taller")
  t.frame()
  inspect(stands(t, page), content="0 0 300 232")
  assert_eq(t.rect_of("under it").map(fn(r) { r.1 }), Some(232.0))
}
