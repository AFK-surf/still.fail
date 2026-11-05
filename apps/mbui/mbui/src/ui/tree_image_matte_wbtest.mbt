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
  assert_eq(was.length(), 1, msg="the old view's: \{was}")
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
  assert_true(t.drawn_rects().iter().any(fn(r) { r == (0.0, 0.0, 200.0, 100.0, 0x000000FFL) }), msg="its matte over its box: \{t.drawn_rects()}")
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

///|
test "a retained picture fits its allocated box on resize without a geometry binding" {
  let fits : Array[Fit] = [FitContain, FitCoverAt(0.0), FitCoverAt(0.5), FitCover]
  for fit in fits {
    let t = Tester::new(fn(_) { }, w=240.0, h=120.0, images=[("portrait", 200, 400)])
    set_view_app(fn(root) {
      root.box(fn(picture) {
        picture.over(Is(true)).image(Is(Some(("portrait", "", 8192))))
        .image_fits(Is((fit, 0x000000FFL))) |> ignore
      }) |> ignore
    })
    for width in [240.0, 180.0] {
      t.resize(width, 120.0)
      let drawn = matte_drawn(t)
      assert_eq(drawn.length(), 1)
      let (x, y, w, h, u, v, du, dv, _, _, _) = drawn[0]
      assert_eq((x, y, w, h), (0.0, 0.0, width, 120.0))
      match fit {
        FitContain => assert_true((u - (60.0 - width) / 120.0).abs() < 1.0e-12 && v == 0.0 && (du - width / 60.0).abs() < 1.0e-12 && dv == 1.0)
        FitCoverAt(at) => assert_true(u == 0.0 && (v - (1.0 - 60.0 / width) * at).abs() < 1.0e-12 && du == 1.0 && (dv - 60.0 / width).abs() < 1.0e-12)
        _ => assert_true(u == 0.0 && (v - (1.0 - 60.0 / width) / 2.0).abs() < 1.0e-12 && du == 1.0 && (dv - 60.0 / width).abs() < 1.0e-12)
      }
    }
  }
}

///|
test "a fractional paint mask clips the same content without changing its layout or the next sibling" {
  let top = @signals.signal(0.25)
  let t = Tester::new(fn(_) { }, w=240.0, h=120.0, images=[("field", 32, 32)])
  set_view_app(fn(root) {
    root.box(fn(p) {
      p.over(Is(true)).image(Is(Some(("field", "", 64))))
      .clip_fraction(By(fn() { Some((0.0, top.get(), 1.0, 0.75)) })) |> ignore
    }) |> ignore
    root.box(fn(sibling) { sibling.width(Is(Some(10.0))).height(Is(Some(10.0))).ground(Is(0xFF0000FFL)) |> ignore }) |> ignore
  })
  for h in [120.0, 200.0] {
    t.resize(240.0, h)
    for from in [0.25, 0.5] {
      top.set(from)
      t.draw()
      let picture = t.drawn_instances().iter().find_first(fn(i) { i[5] == 4.0 }).unwrap()
      assert_eq((picture[0], picture[1], picture[2], picture[3]), (0.0, 0.0, 240.0, h))
      assert_eq((picture[12], picture[13], picture[14], picture[15]), (0.0, 0.0, 1.0, 1.0))
      assert_eq((picture[16], picture[17], picture[18], picture[19]), (0.0, from * h, 240.0, 0.75 * h))
      let sibling = t.drawn_instances().iter().find_first(fn(i) { i[5] == 0.0 && i[2] == 10.0 }).unwrap()
      assert_true(sibling[16] <= sibling[0] && sibling[17] <= sibling[1] &&
        sibling[18] >= sibling[0] + sibling[2] && sibling[19] >= sibling[1] + sibling[3],
        msg="the following sibling is entirely outside the preceding picture's mask")
    }
  }
}
