// A windowed list (View::scrolls_window) counted otherwise than it is, flung and dragged to its foot: at its foot as it
// really is, each frame laid out once, at rest there.

///|
/// 30 blocks 40 high (1200 in all), counted `est` each till laid out, in a column 300 by 100 (from its top): the tree,
/// its scroll and the blocks made now, by key.
fn ends_case(est : Double) -> (@view.Tree, @view.Scroll, Map[Int, @view.View]) {
  let scroll = @view.Scroll::list()
  let live : Map[Int, @view.View] = {}
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(Is(Some(100.0))) |> ignore
      o.scrolls_window(scroll, fn() { Array::makei(30, fn(i) { i }) }, est~, fn(b, k) {
        live[k] = b
        b.owns(fn() { live.remove(k) }) |> ignore
        b.height(Is(Some(40.0))) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  tree.frame(300.0, 100.0, now=0.0) |> ignore
  (tree, scroll, live)
}

///|
/// A finger from `from` to `to` down the column in 10 ms at `at`, let go there.
fn ends_drag(tree : @view.Tree, from : Double, to : Double, at : Double) -> Unit {
  guard tree.claimer_of(tree.claimers_at(150.0, from), 0.0, to - from) is Some(id) else { return }
  tree.drag_at(id, Down, 150.0, from, at) |> ignore
  tree.drag_at(id, Moved, 150.0, (from + to) / 2.0, at + 5.0) |> ignore
  tree.drag_at(id, Moved, 150.0, to, at + 10.0) |> ignore
  tree.drag_at(id, Up, 150.0, to, at + 10.0) |> ignore
}

///|
/// Where the last block's foot is down the column, where it is made.
fn last_foot(live : Map[Int, @view.View]) -> Double? {
  live.get(29).map(fn(b) {
    let (_, y, _, h) = b.rect()
    y + h
  })
}

///|
test "scrolls_window flung to its foot, counted taller than it is: at rest at its foot as it really is, each frame laid out once" {
  let (tree, scroll, live) = ends_case(200.0)
  let computes = tree.work().computes
  ends_drag(tree, 90.0, 10.0, 100.0)
  let mut at = 100.0
  let mut frames = 0
  while at < 6000.0 {
    at = at + 16.0
    tree.frame(300.0, 100.0, now=at) |> ignore
    frames = frames + 1
  }
  assert_eq((last_foot(live), scroll.at(tree), scroll.glides_till()), (Some(100.0), 1100.0, None))
  assert_true(tree.work().computes - computes <= frames, msg="layouts \{tree.work().computes - computes} in \{frames} frames")
}

///|
test "scrolls_window flung to its foot, counted shorter than it is: at rest at its foot as it really is" {
  let (tree, scroll, live) = ends_case(10.0)
  ends_drag(tree, 90.0, 10.0, 100.0)
  let mut at = 100.0
  while at < 6000.0 {
    at = at + 16.0
    tree.frame(300.0, 100.0, now=at) |> ignore
  }
  // (counted 10 each, the fling set out for as far as that; each block it comes to laid out as tall as it is, how far
  // it goes worked out again: wherever it rests, what shows is as laid out, and at rest it is said to be where that is)
  let shown = live.keys().collect()
  shown.sort()
  let first = shown[0]
  let (_, y, _, _) = live[first].rect()
  assert_eq(scroll.at(tree), first.to_double() * 40.0 - y)
  assert_eq(scroll.glides_till(), None)
}

///|
test "scrolls_window dragged on past its foot, counted taller than it is: held at its foot as it really is, at rest there let go" {
  let (tree, scroll, live) = ends_case(200.0)
  guard tree.claimer_of(tree.claimers_at(150.0, 90.0), 0.0, -40.0) is Some(id) else { fail("nothing takes the finger") }
  // (a finger up the column 40 a frame, far past its foot, held there)
  let mut at = 100.0
  tree.drag_at(id, Down, 150.0, 90.0, at) |> ignore
  for k in 1..=60 {
    at = at + 16.0
    tree.drag_at(id, Moved, 150.0, 90.0 - 40.0 * k.to_double(), at) |> ignore
    tree.frame(300.0, 100.0, now=at) |> ignore
  }
  let held = (last_foot(live), scroll.at(tree))
  // (still a while, then let go: nothing flung)
  at = at + 200.0
  tree.drag_at(id, Moved, 150.0, 90.0 - 40.0 * 60.0, at) |> ignore
  tree.drag_at(id, Up, 150.0, 90.0 - 40.0 * 60.0, at) |> ignore
  while at < 4000.0 {
    at = at + 16.0
    tree.frame(300.0, 100.0, now=at) |> ignore
  }
  assert_eq((held, last_foot(live), scroll.at(tree)), ((Some(100.0), 1100.0), Some(100.0), 1100.0))
}
