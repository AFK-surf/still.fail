// A node beside another (View::beside), a layer of its own in one the scene keeps, its anchor in another: what moves
// the one beside is its anchor's place and size alone, nothing of what holds it laid out again or told. The frame draws
// it where it goes, as a frame drawn anew does (the Tester's scene check, Ctx::scene_check, holds every frame to that).

///|
test "a layer beside an anchor in another that grows, nothing of what holds it changed: drawn where it goes now" {
  let wide = @signals.signal(20.0)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  let anchor : Ref[@view.NodeId?] = Ref(None)
  set_view_app(fn(root) {
    // (the anchor in a layer of its own: what changes of it lays out that one alone)
    root.show(fn() { true }, fn(page) {
      page.over(Is(true)).width(Is(Some(400.0))).height(Is(Some(300.0))) |> ignore
      page.show(fn() { true }, fn(a) {
        a.width(By(fn() { Some(wide.get()) })).height(Is(Some(10.0))).ground(Is(0x3366CCFFL)) |> ignore
        anchor.val = Some(a.id())
      })
    })
    // (beside it, in another, a layer of its own too)
    root.show(fn() { true }, fn(page) {
      page.over(Is(true)).width(Is(Some(400.0))).height(Is(Some(300.0))) |> ignore
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
