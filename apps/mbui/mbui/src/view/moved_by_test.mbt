// What moves a node by how big it is laid out (View::moved_by): asked as it is placed, by the size it is laid out at
// in the frame drawing it, nothing laid out again for it.

///|
/// How long a move takes for each point it goes (a sheet rising by its own height: the taller, the longer).
let rise_ms_per_point : Double = 2.0

///|
/// A box `height()` tall rising from its own height below to where it is laid out over rise_ms_per_point a point of
/// its height, by the clock; the tree, the box.
fn rising(height : @signals.Signal[Double]) -> (@view.Tree, Ref[@view.View?]) {
  let sheet : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    sheet.val = Some(
      root.box(fn(s) {
        s
        .width(Is(Some(100.0)))
        .height(By(fn() { Some(height.get()) }))
        .moved_by(fn(_, h) {
          let ms = h * rise_ms_per_point
          let t = s.drawn_at()
          let gone = if ms <= 0.0 || t >= ms { 1.0 } else { t / ms }
          (0.0, h * (1.0 - gone))
        })
        |> ignore
      }),
    )
  })
  (tree, sheet)
}

///|
test "moved by its own height over a time its height says: the clock alone places it again, nothing built or laid out" {
  let height = @signals.signal(100.0, same=fn(a, b) { a == b })
  let (tree, sheet) = rising(height)
  tree.frame(390.0, 844.0) |> ignore
  let id = sheet.val.unwrap().id()
  assert_eq(tree.drawn_of(id).unwrap().y, 100.0)
  let before = tree.work()
  // (a quarter of the way: a quarter of its height risen)
  tree.at(100.0 * rise_ms_per_point / 4.0)
  tree.frame(390.0, 844.0) |> ignore
  let after = tree.work()
  assert_eq(tree.drawn_of(id).unwrap().y, 75.0)
  assert_eq(after.structure - before.structure, 0)
  assert_eq(after.made - before.made, 0)
  assert_eq(after.computes - before.computes, 0)
  assert_eq(after.instances - before.instances, 0)
  assert_eq(after.composed - before.composed, 1)
}

///|
test "its height changed while it moves: placed by the new height, its time the new height's, nothing built again" {
  let height = @signals.signal(100.0, same=fn(a, b) { a == b })
  let (tree, sheet) = rising(height)
  tree.frame(390.0, 844.0) |> ignore
  let id = sheet.val.unwrap().id()
  tree.at(100.0 * rise_ms_per_point / 2.0)
  tree.frame(390.0, 844.0) |> ignore
  assert_eq(tree.drawn_of(id).unwrap().y, 50.0)
  let before = tree.work()
  // (twice as tall at the same moment: a quarter of its new time gone, three quarters of its new height still below)
  height.set(200.0)
  tree.frame(390.0, 844.0) |> ignore
  let after = tree.work()
  assert_eq(tree.drawn_of(id).unwrap().h, 200.0)
  assert_eq(tree.drawn_of(id).unwrap().y, 150.0)
  assert_eq(after.structure - before.structure, 0)
  assert_eq(after.made - before.made, 0)
  // (and on as the clock goes, by the new height: half its new time, half its new height)
  tree.at(200.0 * rise_ms_per_point / 2.0)
  tree.frame(390.0, 844.0) |> ignore
  assert_eq(tree.drawn_of(id).unwrap().y, 100.0)
  // (its time over: where it is laid out)
  tree.at(200.0 * rise_ms_per_point)
  tree.frame(390.0, 844.0) |> ignore
  assert_eq(tree.drawn_of(id).unwrap().y, 0.0)
  assert_eq(tree.work().structure - before.structure, 0)
  assert_eq(tree.work().made - before.made, 0)
}
