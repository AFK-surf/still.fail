// A layer put elsewhere than it was drawn (a list's rows scrolled) and copied as kept comes to what drawing it anew
// there comes to, number for number (the Tester's check of every frame, Ctx::scene_check): whatever the fractions of
// where what it holds lies in it, at a scale whose pixels are thirds.

///|
test "rows scrolled by whole pixels, what they hold at thirds of a pixel: copied as kept, the same as drawn anew, number for number" {
  let t = Tester::new(fn(_) {  }, w=390.0, h=600.0, scale=3.0)
  set_view_app(fn(root) {
    root
    .width(Is(Some(390.0)))
    .height(Is(Some(600.0)))
    .scrolls_window(@view.Scroll::list(), fn() { Array::makei(200, fn(i) { i }) }, est=66.0, fn(row, k) {
      row.height(Is(Some(66.0))).ground(Is(if k % 2 == 0 { 0xF2F2F2FFL } else { 0xFFFFFFFFL })) |> ignore
      // (a badge at a third of a pixel down its row, a line of words a third further, each drawn at fractions)
      row.box(fn(b) {
        b.offset(Is((22.0, 18.0 + 1.0 / 3.0))).width(Is(Some(30.0))).height(Is(Some(30.0))).radius(Is(15.0))
        .ground(Is(0x3366CCFFL)) |> ignore
      })
      |> ignore
      row.box(fn(w) {
        w.padding(Is((0.0, 8.0 / 3.0, 0.0, 0.0))).words(Is("message \{k}")) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  // (wheeled by whole pixels of its own (37 points, 111 of its pixels), each frame checked against one drawn anew)
  for _ in 0..<8 {
    t.wheel(195.0, 300.0, 37.0)
    t.clock_frame()
  }
  assert_true(scene_done().copied > 0, msg="\{scene_done()}: \{scene_alone_why()}")
}
