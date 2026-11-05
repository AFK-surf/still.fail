// Old views as tall as what they hold (old's `natural`), and as wide (`fits`), measured as the tree is laid out in the
// old frame's build: built there at the width the tree gives them and laid out, their nodes as big as that in the same
// layout, the frame they first show in built once (before, their sizes came after the frame was laid out, the frame
// built again for each: three builds a screen's first frame, 2026-11-05).

///|
test "old views as tall and as wide as what they hold: measured as the tree is laid out, built once in the frame they first show in" {
  let natural_built = Ref(0)
  let fits_built = Ref(0)
  let ids : Map[String, @view.View] = Map([])
  let t = Tester::new(fn(_c) {  }, w=400.0, h=800.0)
  set_view_app(fn(root) {
    root.box(fn(col) {
      col.width(Is(Some(400.0))) |> ignore
      ids["natural"] = old(col, natural=true, fn(c) {
        natural_built.val = natural_built.val + 1
        c.box(w=Fill(1.0), fn() {
          c.box(w=Fill(1.0), h=Px(30.0), fn() {  }) |> ignore
          c.box(w=Fill(1.0), h=Px(50.0), fn() {  }) |> ignore
        })
        |> ignore
      })
      let wide = @signals.signal(None, same=fn(a : Double?, b : Double?) { a == b })
      col.box(fn(p) {
        p.width(By(fn() { Some(dmin(300.0, wide.get().unwrap_or(0.0))) })) |> ignore
        ids["fits"] = old(p, natural=true, fits=(300.0, wide), fn(c) {
          fits_built.val = fits_built.val + 1
          c.box(w=Px(120.0), h=Px(40.0), fn() {  }) |> ignore
        })
      })
      |> ignore
    })
    |> ignore
  })
  t.frame()
  assert_eq((natural_built.val, fits_built.val), (1, 1))
  assert_eq(laid_of(ids["natural"]).3, 80.0)
  let f = laid_of(ids["fits"])
  assert_eq((f.2, f.3), (120.0, 40.0))
}

///|
/// A window whose tree holds a column: an old view as tall as what it holds (its body's builds in `natural_built`), a
/// panel as wide as the old view in it (`fits_built`), a box as wide as `side` says and as dark as `ink` says. (A build
/// the Tester makes whole to hold a frame to, frame_watch.mbt, builds every body: not counted.)
fn measured_tester(
  side : @signals.Signal[Double],
  ink : @signals.Signal[Int64],
  natural_built : Ref[Int],
  fits_built : Ref[Int],
  ids : Map[String, @view.View],
) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=800.0)
  set_view_app(fn(root) {
    root.box(fn(col) {
      col.width(Is(Some(400.0))) |> ignore
      ids["natural"] = old(col, natural=true, fn(c) {
        if !nodes_run.whole {
          natural_built.val = natural_built.val + 1
        }
        c.box(w=Fill(1.0), h=Px(80.0), fn() {  }) |> ignore
      })
      let wide = @signals.signal(None, same=fn(a : Double?, b : Double?) { a == b })
      col.box(fn(p) {
        p.width(By(fn() { Some(dmin(300.0, wide.get().unwrap_or(0.0))) })) |> ignore
        ids["panel"] = p
        ids["fits"] = old(p, natural=true, fits=(300.0, wide), fn(c) {
          if !nodes_run.whole {
            fits_built.val = fits_built.val + 1
          }
          c.box(w=Px(120.0), h=Px(40.0), fn() {  }) |> ignore
        })
      })
      |> ignore
      col.box(fn(b) {
        b.width(By(fn() { Some(side.get()) })).height(Is(Some(20.0))).ground(By(fn() { ink.get() })) |> ignore
        ids["side"] = b
      })
      |> ignore
    })
    |> ignore
  })
  t.frame()
  // (the panel told how wide its old view came to as it was first measured, and the old views placed as they came to:
  // read as the tree was laid out again in that build, and by the frame after it, owed for it once)
  t.clock_frame()
  t
}

///|
test "what the tree's layout reads changes: the old views measured as they were, none of them built again" {
  let side = @signals.signal(100.0)
  let ink = @signals.signal(0x000000FFL)
  let natural_built = Ref(0)
  let fits_built = Ref(0)
  let ids : Map[String, @view.View] = Map([])
  let t = measured_tester(side, ink, natural_built, fits_built, ids)
  let before = (natural_built.val, fits_built.val, laid_of(ids["natural"]), laid_of(ids["fits"]))
  side.set(200.0)
  t.clock_frame()
  assert_eq(laid_of(ids["side"]).2, 200.0)
  assert_eq((natural_built.val, fits_built.val, laid_of(ids["natural"]), laid_of(ids["fits"])), before)
}

///|
test "a frame built, then one painted alone: the tree laid out the same, node for node" {
  let side = @signals.signal(100.0)
  let ink = @signals.signal(0x000000FFL)
  let natural_built = Ref(0)
  let fits_built = Ref(0)
  let ids : Map[String, @view.View] = Map([])
  let t = measured_tester(side, ink, natural_built, fits_built, ids)
  let keys = ["natural", "panel", "fits", "side"]
  let built = keys.map(fn(k) { laid_of(ids[k]) })
  let was = paints_alone.val
  ink.set(0x336699FFL)
  t.clock_frame()
  assert_eq(paints_alone.val - was, 1, msg="painted alone, not built: \{t.built_why()}")
  assert_eq(keys.map(fn(k) { laid_of(ids[k]) }), built)
}
