// A node beside another (View::beside), each a layer of its own in one the scene keeps: what moves the one beside is
// its anchor's place and size alone, nothing of what holds them told. The frame draws it where it goes, as a frame drawn
// anew does (the Tester's scene check, Ctx::scene_check, holds every frame to that).

///|
test "a layer beside an anchor that grows, nothing else of what holds them changed: drawn where it goes now" {
  let wide = @signals.signal(20.0)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  set_view_app(fn(root) {
    root.show(fn() { true }, fn(page) {
      page.width(Is(Some(400.0))).height(Is(Some(300.0))) |> ignore
      let anchor : Ref[@view.NodeId?] = Ref(None)
      // (the anchor a layer of its own: what changes of it marks it alone)
      page.show(fn() { true }, fn(a) {
        a.width(By(fn() { Some(wide.get()) })).height(Is(Some(10.0))).ground(Is(0x3366CCFFL)) |> ignore
        anchor.val = Some(a.id())
      })
      // (beside it, a layer of its own too)
      page.show(fn() { true }, fn(b) {
        b.width(Is(Some(50.0))).height(Is(Some(20.0))).ground(Is(0xCC3366FFL)) |> ignore
        match anchor.val {
          Some(id) => b.beside(id, side=Right, along=Start, offset=4.0, padding=0.0) |> ignore
          None => ()
        }
      })
    })
  })
  t.draw()
  let x = fn() { t.drawn_rects().filter(fn(r) { r.4 == 0xCC3366FFL })[0].0 }
  assert_eq(x(), 24.0)
  wide.set(60.0)
  t.draw()
  assert_eq(x(), 64.0)
}
