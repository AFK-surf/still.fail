// A finger held on a node (View::on_drag): the node's from down to up, wherever it moves meanwhile, each event handled
// at its own moment in the node's own terms, whatever frames are drawn between; one let go told nothing more.

///|
/// A tree with a box held (100 by 100 at the window's top left) while `there`, what its on_drag was told.
fn held_tree(seen : Array[@view.Drag], there : @signals.Signal[Bool]) -> @view.Tree {
  @view.Tree::new(
    fn(root) {
      root.show(fn() { there.get() }, fn(v) {
        v.box(fn(b) {
          b.width(Is(Some(100.0))).height(Is(Some(100.0))).on_drag(fn(d) { seen.push(d) }) |> ignore
        })
        |> ignore
      })
    },
    time=fn() { 0.0 },
  )
}

///|
test "held: down, moved anywhere, up: the node's, each at its own moment, in its own terms" {
  let seen : Array[@view.Drag] = []
  let there = @signals.signal(true, same=fn(a, b) { a == b })
  let t = held_tree(seen, there)
  t.frame(390.0, 844.0) |> ignore
  let id = match t.target_at(10.0, 10.0) {
    Dragged(id) => id
    _ => abort("not held")
  }
  t.drag_at(id, Down, 10.0, 10.0, 100.0) |> ignore
  t.drag_at(id, Moved, 300.0, 500.0, 120.0) |> ignore
  t.drag_at(id, Up, 310.0, 510.0, 130.0) |> ignore
  assert_eq(seen.map(fn(d) { (d.kind, d.x, d.y, d.at) }), [
    (Down, 10.0, 10.0, 100.0),
    (Moved, 300.0, 500.0, 120.0),
    (Up, 310.0, 510.0, 130.0),
  ])
}

///|
test "held, then let go of as the finger moves: told nothing more" {
  let seen : Array[@view.Drag] = []
  let there = @signals.signal(true, same=fn(a, b) { a == b })
  let t = held_tree(seen, there)
  t.frame(390.0, 844.0) |> ignore
  let id = match t.target_at(10.0, 10.0) {
    Dragged(id) => id
    _ => abort("not held")
  }
  t.drag_at(id, Down, 10.0, 10.0, 100.0) |> ignore
  there.set(false)
  // (let go at once, no frame needed)
  assert_false(t.drag_at(id, Moved, 20.0, 20.0, 120.0))
  assert_eq(seen.length(), 1)
}
