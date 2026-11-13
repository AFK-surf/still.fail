// A flight with an end that stays (View::shared's `stays`, shared.mbt) where that end lies in what scrolls under a bar
// (Scroll::top_covered) and the other is held under its own bar: the one that moves drawn where it is held, its bar
// over it; the cut it sets out in less what covers the top of what scrolls the thumbnail; a thumbnail wholly under that
// pairs with nothing.

///|
/// A column that scrolls, 60 of its top covered (View::scrolls' `top_covered`), holding `room` of nothing then a
/// thumbnail 100 by 40 that stays; over all of it while `open` is said a layer holding a picture 300 by 200 at
/// (50, 300) that moves, then a bar 400 by 50 at its top drawn after it. The tree, open, the thumbnail, the picture,
/// the bar.
fn cover_scene(
  room : Double,
) -> (@view.Tree, @signals.Signal[Bool], Ref[@view.View?], Ref[@view.View?], Ref[@view.View?]) {
  let open = @signals.signal(false)
  let thumb : Ref[@view.View?] = Ref(None)
  let big : Ref[@view.View?] = Ref(None)
  let bar : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(p) {
      p.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
      p.scrolls(@view.Scroll::new(), top_covered=fn() { 60.0 }, fn(held) {
        held.box(fn(r) { r.height(Is(Some(room))).shrink(Is(0.0)) |> ignore }) |> ignore
        held.box(fn(t) {
          thumb.val = Some(t)
          t.width(Is(Some(100.0))).height(Is(Some(40.0))).shrink(Is(0.0)).ground(Is(red)).shared(Is("a"), straight, stays=true)
          |> ignore
        })
        |> ignore
        held.box(fn(r) { r.height(Is(Some(2000.0))).shrink(Is(0.0)) |> ignore }) |> ignore
      })
      |> ignore
      p.show(fn() { open.get() }, fn(o) {
        o.over(Is(true)) |> ignore
        o.box(fn(b) {
          big.val = Some(b)
          b
          .offset(Is((50.0, 300.0)))
          .width(Is(Some(300.0)))
          .height(Is(Some(200.0)))
          .ground(Is(blue))
          .shared(Is("a"), straight, with_stays=true)
          |> ignore
        })
        |> ignore
        o.box(fn(h) {
          bar.val = Some(h)
          h.offset(Is((0.0, 0.0))).width(Is(Some(400.0))).height(Is(Some(50.0))).ground(Is(green)) |> ignore
        })
        |> ignore
      })
    })
    |> ignore
  })
  (tree, open, thumb, big, bar)
}

///|
test "a picture flown from a thumbnail that stays: drawn where it is held, the bar drawn after it over it; its cut as it sets out less what covers the top of what scrolls the thumbnail" {
  // (the thumbnail at 30 to 70, its top 30 under what covers the column's top)
  let (tree, open, thumb, big, bar) = cover_scene(30.0)
  tree.frame(400.0, 800.0, now=0.0) |> ignore
  assert_eq(drawn_as(tree, thumb.val.unwrap()), Some((0.0, 30.0, 100.0, 40.0, 1.0, red)))
  tree.event(1000.0, fn() { open.set(true) })
  tree.frame(400.0, 800.0, now=1000.0) |> ignore
  let b = big.val.unwrap()
  assert_true(b.flies(), msg="flown from the thumbnail")
  let (bi, hi) = (drawn_index(tree, b), drawn_index(tree, bar.val.unwrap()))
  assert_true(bi >= 0 && hi > bi, msg="the bar drawn after it: \{bi} \{hi}")
  // (as it sets out: drawn within the thumbnail's room below what covers the column's top)
  assert_eq(tree.lift_cut(b.id()).map(fn(c) { c.1 }), Some(60.0))
  // (half way: opening to the window)
  tree.frame(400.0, 800.0, now=1100.0) |> ignore
  assert_true(tree.lift_cut(b.id()) is Some(_), msg="cut half way")
  // (what is seen of it rounded as the flight has it)
  assert_eq(tree.lift_cut_corners(b.id()), tree.flight_drawn("a").map(fn(f) { f.1 }))
  tree.frame(400.0, 800.0, now=1300.0) |> ignore
  assert_true(!b.flies())
  assert_true(drawn_index(tree, b) < drawn_index(tree, bar.val.unwrap()), msg="landed, the bar over it still")
}

///|
test "a thumbnail that stays wholly under what covers the top of what scrolls it: none flies, the picture comes as it would" {
  // (the thumbnail at 10 to 50, all of it under the 60 covered)
  let (tree, open, _, big, _) = cover_scene(10.0)
  tree.frame(400.0, 800.0, now=0.0) |> ignore
  tree.event(1000.0, fn() { open.set(true) })
  tree.frame(400.0, 800.0, now=1000.0) |> ignore
  assert_true(!big.val.unwrap().flies())
}
