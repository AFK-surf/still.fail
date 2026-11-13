// A node of the window's tree's picture lying in it at a rect of its own, a matte round it (View::image_in): drawn as an
// old view's picture at a rect in a matte is (Ctx::picture's `matte`): one frame the node's box, the picture over the
// matte in it, its edge cut once; the matte alone till the picture is decoded; the node's corners its.

///|
/// A window 200 by 100 holding "frame.jpg" (400 by 240) at (10, 20) 100 by 60 in a black matte filling the window: by
/// an old view (Ctx::picture) or by a node of the tree (View::image, View::image_in), its corners `corners` (the tree's;
/// None, none); decoded at once or as the test says (`finish`).
fn matte_tester(old : Bool, finish? : Bool = true, corners? : (Double, Double, Double, Double)) -> Tester {
  if old {
    Tester::new(
      fn(c) { c.picture("frame.jpg", x=10.0, y=20.0, w=100.0, h=60.0, bg=0x000000FFL, matte=true) |> ignore },
      w=200.0,
      h=100.0,
      images=[("frame.jpg", 400, 240)],
      finish~,
    )
  } else {
    let t = Tester::new(fn(_c) {  }, w=200.0, h=100.0, images=[("frame.jpg", 400, 240)], finish~)
    set_view_app(fn(root) {
      root.box(fn(n) {
        n
        .width(Is(Some(200.0)))
        .height(Is(Some(100.0)))
        .corners(Is(corners))
        .image(Is(Some(("frame.jpg", "", 8192))))
        .image_in(Is(Some(((10.0, 20.0, 100.0, 60.0), 0x000000FFL))))
        |> ignore
      })
      |> ignore
    })
    t
  }
}

///|
/// The pictures drawn: each one's box (0-3), what of the image it spans (12-15), its matte's alpha, whether it is a
/// matte, how far it has faded in (21-23).
fn matte_drawn(t : Tester) -> Array[(Double, Double, Double, Double, Double, Double, Double, Double, Double, Double, Double)] {
  t.drawn_instances().filter(fn(a) { a[5] == 4.0 }).map(fn(a) { (a[0], a[1], a[2], a[3], a[12], a[13], a[14], a[15], a[21], a[22], a[23]) })
}

///|
test "a node's picture at a rect in a matte: one frame its box, the picture over the matte in it, as an old view's" {
  let old = matte_tester(true)
  old.draw()
  let was = matte_drawn(old)
  assert_eq(was.length(), 1, msg="the old view's: \{Repr(was)}")
  let t = matte_tester(false)
  t.draw()
  assert_eq(matte_drawn(t), was, msg="the node's the same")
  assert_false(t.drawn_rects().iter().any(fn(r) { r.4 == 0x000000FFL }), msg="no matte of its own beside it")
}

///|
test "a node's picture in a matte not decoded yet: the matte alone over its box; decoded, the one frame, no matte beside it" {
  let t = matte_tester(false, finish=false)
  t.draw()
  assert_eq(matte_drawn(t).length(), 0, msg="no picture yet")
  assert_true(t.drawn_rects().iter().any(fn(r) { r == (0.0, 0.0, 200.0, 100.0, 0x000000FFL) }), msg="its matte over its box: \{Repr(t.drawn_rects())}")
  for p in t.pending() {
    t.finish(p.0, p.1)
  }
  t.draw()
  assert_eq(matte_drawn(t).length(), 1, msg="the picture in its frame")
  assert_false(t.drawn_rects().iter().any(fn(r) { r.4 == 0x000000FFL }), msg="no matte beside it")
}

///|
test "a node's picture in a matte, the node's corners each its own: the frame drawn with them" {
  let t = matte_tester(false, corners=(12.0, 12.0, 0.0, 0.0))
  t.draw()
  let frames = t.drawn_instances().filter(fn(a) { a[5] == 4.0 })
  assert_eq(frames.map(fn(a) { (a[36], a[37], a[38], a[39]) }), [(12.0, 12.0, 0.0, 0.0)])
}
