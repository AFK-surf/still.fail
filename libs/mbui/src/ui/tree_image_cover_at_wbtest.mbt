// A node's picture covering it from a side said along its height (View::image_covers_at): drawn as an old view's
// picture covering its box from there (Ctx::image's FitCoverAt) is, instance for instance (where, how big, which part of
// the image); told another side, or none, the frame after drawing it so.

///|
/// The picture `src` (`iw` by `ih`) in a box 60 by 40 at the window's top left, covering it from `at` along its
/// height: by an old view (Ctx::image), else by a node of the window's tree; the pictures 60 by 40 drawn once decoded.
fn cover_at_drawn(old : Bool, src : String, iw : Int, ih : Int, at : Double) -> Array[Array[Double]] {
  let t = if old {
    Tester::new(
      fn(c) { c.image(src, w=Px(60.0), h=Px(40.0), fit=FitCoverAt(at), bg=0L, fade=false) |> ignore },
      images=[(src, iw, ih)],
    )
  } else {
    let t = Tester::new(fn(_c) {  }, images=[(src, iw, ih)])
    set_view_app(fn(root) {
      root.box(fn(n) {
        n
        .width(Is(Some(60.0)))
        .height(Is(Some(40.0)))
        .image(Is(Some((src, "", 4096))))
        .image_covers_at(Is(Some(at)))
        .image_fades(Is(false))
        |> ignore
      })
      |> ignore
    })
    t
  }
  t.draw()
  t.run_for(image_fade_ms)
  pictures_sized(60.0, 40.0)
}

///|
test "a node's picture covering it from its top, its foot or its middle: the instances an old view's FitCoverAt draws, a tall picture and a wide one" {
  for p in [("tall", 300, 3000), ("wide", 3000, 300)] {
    for at in [0.0, 0.5, 1.0] {
      let old = cover_at_drawn(true, p.0, p.1, p.2, at)
      assert_eq(old.length(), 1, msg="\{p.0} at \{at}: the old view's picture drawn")
      assert_eq(cover_at_drawn(false, p.0, p.1, p.2, at), old, msg="\{p.0} at \{at}: the node's the same")
    }
  }
}

///|
test "a node's picture told another side to cover it from, or none: the frame after, drawn so" {
  let at : @signals.Signal[Double?] = @signals.signal(Some(0.0))
  let t = Tester::new(fn(_c) {  }, images=[("tall", 300, 3000)])
  set_view_app(fn(root) {
    root.box(fn(n) {
      n
      .width(Is(Some(60.0)))
      .height(Is(Some(40.0)))
      .image(Is(Some(("tall", "", 4096))))
      .image_covers_at(By(fn() { at.get() }))
      .image_fades(Is(false))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.run_for(image_fade_ms)
  // (which part of the image it shows: its top and how much of its height, inst 13 and 15)
  // (none or more than one drawn: (-1, -1), which no assertion below takes)
  let part = fn() {
    let p = pictures_sized(60.0, 40.0)
    if p.length() == 1 {
      (p[0][13], p[0][15])
    } else {
      (-1.0, -1.0)
    }
  }
  // (60 by 40 of a picture 300 by 3000: as wide as it, about 1/15 of its height shown, as decoded)
  let top = part()
  assert_true(top.0 == 0.0 && top.1 > 0.0 && top.1 < 0.1, msg="from its top: \{Repr(top)}")
  at.set(Some(1.0))
  t.frame()
  // (as much of it, from its foot)
  assert_true((part().1 - top.1).abs() < 1.0e-9 && (part().0 + part().1 - 1.0).abs() < 1.0e-9, msg="from its foot: \{Repr(part())}")
  // (none said: filling it, all of it shown)
  at.set(None)
  t.frame()
  assert_eq(part(), (0.0, 1.0))
}
