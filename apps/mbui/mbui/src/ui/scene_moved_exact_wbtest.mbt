// A layer put elsewhere than it was drawn (a list's rows scrolled) and copied as kept comes to what drawing it anew
// there comes to, number for number (the Tester's check of every frame, Ctx::scene_check): what it holds lying between
// its pixels (a tenth of a point, a fifth of a pixel at scale 2), it moved by whole pixels (29.5 points, as a phone's
// list was flung, 59 of its pixels).

///|
test "rows scrolled by whole pixels, what they hold between pixels: copied as kept, the same as drawn anew, number for number" {
  let t = Tester::new(fn(_) {  }, w=390.0, h=600.0, scale=2.0)
  set_view_app(fn(root) {
    root
    .width(Is(Some(390.0)))
    .height(Is(Some(600.0)))
    .scrolls_window(@view.Scroll::list(), fn() { Array::makei(200, fn(i) { i }) }, est=199.0 / 3.0, fn(row, k) {
      row.height(Is(Some(199.0 / 3.0))).ground(Is(if k % 2 == 0 { 0xF2F2F2FFL } else { 0xFFFFFFFFL })) |> ignore
      // (each row 199/3 points tall, its place a third of a point off whole points, as a phone's rows are; a badge three
      // tenths of a pixel off its row's pixels, a line of words seven tenths off)
      row.box(fn(b) {
        b.offset(Is((22.0, 18.1))).width(Is(Some(30.0))).height(Is(Some(30.0))).radius(Is(15.0))
        .ground(Is(0x3366CCFFL)) |> ignore
      })
      |> ignore
      // (an icon's shape, its bands worked out where its outline lies: between pixels)
      row.box(fn(i) {
        i.offset(Is((340.0, 20.0))).width(Is(Some(20.0))).height(Is(Some(20.0)))
        .shapes(Is([shape_of([([2.3, 1.7, 17.6, 2.2, 15.9, 18.4], true)], fill=0x333333FFL)])) |> ignore
      })
      |> ignore
      row.box(fn(w) {
        w.padding(Is((0.0, 2.9, 0.0, 0.0))).words(Is("message \{k}")) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  // (dragged up by whole pixels of its own, a step a frame (29.5 points, 59 of its pixels), each frame checked against
  // one drawn anew)
  t.touch_at(0, 195.0, 500.0, t.time())
  t.clock_frame()
  for i in 1..=8 {
    t.touch_at(1, 195.0, 500.0 - 29.5 * i.to_double(), t.time())
    t.clock_frame()
  }
  // (what is checked lies between pixels as drawn: some instance's place, in pixels, no whole number)
  let c = g()
  let between = Array::makei(c.ninst, fn(k) { c.inst[k * inst_size + 1] * 2.0 }).any(fn(v) { v != v.round() })
  assert_true(between, msg="every instance on whole pixels")
  assert_true(scene_done().copied > 0, msg="\{scene_done()}: \{scene_alone_why()}")
}
