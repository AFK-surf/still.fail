// Bones in the window's tree (View::bones, View::bone_whole): said whole only where it is in its bones itself; into
// them at a cause, what takes input in it let go of then (the focus, a finger held, what a still pointer is over found
// again), out of them answering as before; its colour alone changed, none of that.

///|
/// A row in a box (the box said in its bones as `boned` says), the row taking presses (counted in `pressed`) and the
/// focus, 200 × 40 at the top left.
fn boned_row(boned : @signals.Signal[Int64], pressed : Ref[Int]) -> (@view.Tree, @view.NodeId) {
  let id : Ref[@view.NodeId?] = Ref(None)
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(b) {
        b.bones(By(fn() { boned.get() })).lines_up(Is(Some(Start))) |> ignore
        b.box(fn(r) {
          id.val = Some(r.id())
          r.width(Is(Some(200.0))).height(Is(Some(40.0))).focusable(Is(true)).on_press(fn() { pressed.val += 1 }) |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  (t, id.val.unwrap())
}

///|
test "bones: into them at a cause, the focus, a finger held and what a still pointer is over let go of; out of them, answering again" {
  let boned = @signals.signal(0L, same=fn(a, b) { a == b })
  let pressed = Ref(0)
  let (t, row) = boned_row(boned, pressed)
  assert_true(t.focus_to(Some(row), visible=true))
  t.point_at(100.0, 20.0)
  assert_eq(t.pointed_now(), Some(row))
  // (a finger put down on it, held)
  t.hold_press(row)
  let hits = t.hits_said()
  // (into its bones, at that moment: no frame drawn after it, the pointer not moved)
  t.event(10.0, fn() { boned.set(0xE5E5EAFFL) })
  assert_eq(t.focused_now(), (None, false))
  assert_false(t.press_held(row))
  assert_true(t.hits_said() > hits, msg="what a still pointer is over not found again")
  t.point_at(100.0, 20.0)
  assert_eq(t.pointed_now(), None)
  assert_false(t.focus_to(Some(row)))
  assert_false(t.press(100.0, 20.0))
  assert_eq(pressed.val, 0)
  // (its colour alone changed: nothing more to find again)
  let hits = t.hits_said()
  t.event(20.0, fn() { boned.set(0xDDDDDDFFL) })
  assert_eq(t.hits_said(), hits)
  // (out of them: it answers again)
  t.event(30.0, fn() { boned.set(0L) })
  t.frame(390.0, 844.0) |> ignore
  t.point_at(100.0, 20.0)
  assert_eq(t.pointed_now(), Some(row))
  assert_true(t.focus_to(Some(row)))
  assert_true(t.press(100.0, 20.0))
  assert_eq(pressed.val, 1)
}

///|
test "bones: one said whole drawn as one piece only in its bones itself; out of them what it holds in its own bones drawn so" {
  let outer_boned = @signals.signal(0L, same=fn(a, b) { a == b })
  let ids : Map[String, @view.NodeId] = Map([])
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(w) {
        ids["whole"] = w.id()
        w.bone_whole(Is(true)).bones(By(fn() { outer_boned.get() })).width(Is(Some(120.0))).height(Is(Some(40.0))).ground(Is(0x336699FFL)) |> ignore
        w.box(fn(c) {
          ids["child"] = c.id()
          c.bones(Is(0xE5E5EAFFL)).words(Is("按钮")) |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  let drawn = fn(name : String) { t.drawn().search_by(fn(d) { d.id == ids[name] }).map(fn(i) { t.drawn()[i] }) }
  // (the whole one out of its bones: drawn as ever; its child in its own, drawn so, not kept out by it)
  assert_eq(drawn("whole").map(fn(d) { (d.bones, d.bone_as) }), Some((0L, 0)))
  assert_eq(drawn("child").map(fn(d) { (d.bones, d.bone_as) }), Some((0xE5E5EAFFL, 0)))
  // (in its bones itself: one piece, nothing in it drawn)
  outer_boned.set(0xE5E5EAFFL)
  t.frame(390.0, 844.0) |> ignore
  assert_eq(drawn("whole").map(fn(d) { d.bone_as }), Some(1))
  assert_eq(drawn("child").map(fn(d) { d.bone_as }), Some(2))
}
