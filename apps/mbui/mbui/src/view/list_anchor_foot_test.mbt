// A list laid out from its anchor (View::scrolls_anchored) flung to its foot, its rows not as tall as it counts them
// (each one not measured yet counted the mean of those that are): at rest at its foot as it really is, each frame laid
// out once.

///|
test "scrolls_anchored from its top flung to its foot, its first rows five times as tall as the rest: at rest at its foot, each frame laid out once" {
  let scroll = @view.Scroll::list()
  let live : Map[Int, @view.View] = {}
  // (three rows 200 high, then 27 of 40: 1680 in all, its foot 1580 down from its top in a window of 100)
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(Is(Some(100.0))) |> ignore
      o.scrolls_anchored(scroll, fn() { Array::makei(30, fn(i) { i }) }, from_end=false, ahead=0.0, fn(b, k) {
        live[k] = b
        b.owns(fn() { live.remove(k) }) |> ignore
        b.height(Is(Some(if k < 3 { 200.0 } else { 40.0 }))) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  tree.frame(300.0, 100.0, now=0.0) |> ignore
  let computes = tree.work().computes
  guard tree.claimer_of(tree.claimers_at(150.0, 90.0), 0.0, -80.0) is Some(id) else {
    fail("nothing takes the finger")
  }
  // (a finger up 80 in 10 ms, let go as it moves)
  tree.drag_at(id, Down, 150.0, 90.0, 100.0) |> ignore
  tree.drag_at(id, Moved, 150.0, 50.0, 105.0) |> ignore
  tree.drag_at(id, Moved, 150.0, 10.0, 110.0) |> ignore
  tree.drag_at(id, Up, 150.0, 10.0, 110.0) |> ignore
  let mut at = 100.0
  let mut frames = 0
  while at < 6000.0 {
    at = at + 16.0
    tree.frame(300.0, 100.0, now=at) |> ignore
    frames = frames + 1
  }
  let foot = live.get(29).map(fn(b) {
    let (_, y, _, h) = b.rect()
    y + h
  })
  assert_eq((foot, scroll.glides_till()), (Some(100.0), None))
  assert_true(tree.work().computes - computes <= frames, msg="layouts \{tree.work().computes - computes} in \{frames} frames")
}
