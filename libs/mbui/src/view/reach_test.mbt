// What is drawn smaller than a press's room reached from round it (reach.mbt; still.fail's rules 1 and 2, the user,
// 2026-10-26): Tree::target_at the one answer, a press, its let go, the pointer lighting what it is over and
// View::finger_target alike; the room as the old view's (ui's press_reach, desktop_test.mbt's). Each tree laid out
// once, its moment 0 (`time`), the window 390 by 844.

///|
/// A tree whose ground fills the window and takes presses (`ground`, as a sheet does), holding at (`x`, `y`) what
/// `make` makes in it (a row of its own, from there); a finger's room (44) said, as a host says it (Tree::press_least).
fn reach_tree(
  x : Double,
  y : Double,
  make : (@view.View) -> Unit,
  ground? : (@view.View) -> Unit = fn(g) { g.on_press(fn() {  }) |> ignore },
  least? : Double = 44.0,
) -> (@view.Tree, @view.NodeId) {
  let under : Ref[@view.NodeId?] = Ref(None)
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(g) {
        g.grow(Is(1.0)).padding(Is((x, y, 0.0, 0.0))) |> ignore
        ground(g)
        under.val = Some(g.id())
        g.box(fn(r) {
          r.row(Is(true)).gap(Is(6.0)) |> ignore
          make(r)
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.press_least(fn() { least })
  t.frame(390.0, 844.0) |> ignore
  (t, under.val.unwrap())
}

///|
/// A button `w` by `h` made in `r`, counting its presses in `pressed`; it, kept in `kept`.
fn small_button(
  r : @view.View,
  w : Double,
  h : Double,
  pressed : Ref[Int],
  kept : Ref[@view.View?],
) -> Unit {
  r.box(fn(b) {
    b.width(Is(Some(w))).height(Is(Some(h))).on_press(fn() { pressed.val = pressed.val + 1 }) |> ignore
    kept.val = Some(b)
  })
  |> ignore
}

///|
test "reach: a button smaller than its room is pressed from round it each way, its room a finger's 44 round its middle; past that, what it is drawn on" {
  let pressed = Ref(0)
  let b : Ref[@view.View?] = Ref(None)
  // (36 square at 100, 100: its middle 118, 118, its room 96 to 140 each way)
  let (t, sheet) = reach_tree(100.0, 100.0, fn(r) { small_button(r, 36.0, 36.0, pressed, b) })
  let id = b.val.unwrap().id()
  assert_eq(b.val.unwrap().rect(), (100.0, 100.0, 36.0, 36.0))
  for p in [(118.0, 97.0), (118.0, 139.0), (97.0, 118.0), (139.0, 118.0), (97.0, 97.0), (139.5, 139.5)] {
    assert_eq(t.target_at(p.0, p.1), Pressed(id), msg="\{Repr(p)}")
  }
  for p in [(118.0, 95.0), (118.0, 140.5), (95.0, 118.0), (141.0, 118.0)] {
    assert_eq(t.target_at(p.0, p.1), Pressed(sheet), msg="\{Repr(p)}")
  }
  // a press there presses it
  assert_true(t.press(118.0, 97.0))
  assert_true(t.press(118.0, 139.0))
  assert_eq(pressed.val, 2)
}

///|
test "reach: a keyboard and mouse's room is 36 round its middle" {
  let pressed = Ref(0)
  let b : Ref[@view.View?] = Ref(None)
  // (20 square at 100, 100: its middle 110, 110, its room 92 to 128)
  let (t, sheet) = reach_tree(100.0, 100.0, fn(r) { small_button(r, 20.0, 20.0, pressed, b) }, least=36.0)
  let id = b.val.unwrap().id()
  assert_eq(t.target_at(110.0, 93.0), Pressed(id))
  assert_eq(t.target_at(127.0, 110.0), Pressed(id))
  assert_eq(t.target_at(110.0, 91.0), Pressed(sheet))
  assert_eq(t.target_at(129.0, 110.0), Pressed(sheet))
}

///|
test "reach: two small buttons side by side, each has the half of the gap nearer it" {
  let pa = Ref(0)
  let pb = Ref(0)
  let a : Ref[@view.View?] = Ref(None)
  let b : Ref[@view.View?] = Ref(None)
  // (30 square each, 6 apart: 100 to 130, then 136 to 166)
  let (t, _) = reach_tree(100.0, 100.0, fn(r) {
    small_button(r, 30.0, 30.0, pa, a)
    small_button(r, 30.0, 30.0, pb, b)
  })
  let (ida, idb) = (a.val.unwrap().id(), b.val.unwrap().id())
  assert_eq(b.val.unwrap().rect().0, 136.0)
  assert_eq(t.target_at(131.0, 115.0), Pressed(ida))
  assert_eq(t.target_at(132.5, 115.0), Pressed(ida))
  assert_eq(t.target_at(133.5, 115.0), Pressed(idb))
  assert_eq(t.target_at(135.0, 115.0), Pressed(idb))
  // each over the other's room's far side as well: a's over b's left, b's over a's right
  assert_eq(t.target_at(129.0, 98.0), Pressed(ida))
  assert_eq(t.target_at(137.0, 98.0), Pressed(idb))
}

///|
test "reach: a small button's room keeps to the row it is in: past the row's edge, the row under it's" {
  let pressed = Ref(0)
  let below = Ref(0)
  let b : Ref[@view.View?] = Ref(None)
  let rows : Ref[(@view.NodeId?, @view.NodeId?)] = Ref((None, None))
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(s) { s.height(Is(Some(100.0))) |> ignore }) |> ignore
      // a row 40 high taking presses (100 to 140), a 36 square button in it at 102 to 138 (its room 98 to 142 each
      // way were it not cut), and under it another row (140 to 200)
      root.box(fn(r) {
        r.height(Is(Some(40.0))).row(Is(true)).padding(Is((100.0, 2.0, 0.0, 2.0))).on_press(fn() {  }) |> ignore
        rows.val = (Some(r.id()), rows.val.1)
        small_button(r, 36.0, 36.0, pressed, b)
      })
      |> ignore
      root.box(fn(r) {
        r.height(Is(Some(60.0))).on_press(fn() { below.val = below.val + 1 }) |> ignore
        rows.val = (rows.val.0, Some(r.id()))
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.press_least(fn() { 44.0 })
  t.frame(390.0, 844.0) |> ignore
  let id = b.val.unwrap().id()
  assert_eq(b.val.unwrap().rect(), (100.0, 102.0, 36.0, 36.0))
  assert_eq(t.target_at(118.0, 139.5), Pressed(id))
  assert_eq(t.target_at(118.0, 140.5), Pressed(rows.val.1.unwrap()))
  assert_eq(t.target_at(118.0, 141.5), Pressed(rows.val.1.unwrap()))
  assert_true(t.press(118.0, 141.5))
  assert_eq((pressed.val, below.val), (0, 1))
}

///|
test "reach: one at the window's edge has its room moved in from the edge, not cut short" {
  let pressed = Ref(0)
  let b : Ref[@view.View?] = Ref(None)
  // (20 square in the window's corner: its room 0 to 44 each way, not -12 to 32 cut to 0 to 32)
  let (t, sheet) = reach_tree(0.0, 0.0, fn(r) { small_button(r, 20.0, 20.0, pressed, b) })
  let id = b.val.unwrap().id()
  assert_eq(t.target_at(40.0, 10.0), Pressed(id))
  assert_eq(t.target_at(10.0, 43.0), Pressed(id))
  assert_eq(t.target_at(43.5, 43.5), Pressed(id))
  assert_eq(t.target_at(45.0, 10.0), Pressed(sheet))
  assert_eq(t.target_at(10.0, 45.0), Pressed(sheet))
}

///|
test "reach: one as big as its room each way is pressed only where it is drawn; one as wide but less tall, grown only down and up" {
  let pressed = Ref(0)
  let b : Ref[@view.View?] = Ref(None)
  let (t, sheet) = reach_tree(100.0, 100.0, fn(r) { small_button(r, 50.0, 50.0, pressed, b) })
  let id = b.val.unwrap().id()
  assert_eq(t.target_at(125.0, 99.0), Pressed(sheet))
  assert_eq(t.target_at(99.0, 125.0), Pressed(sheet))
  assert_eq(t.target_at(125.0, 101.0), Pressed(id))
  let pressed = Ref(0)
  let w : Ref[@view.View?] = Ref(None)
  // (80 by 36: its room 80 by 44, 96 to 140 down)
  let (t, sheet) = reach_tree(100.0, 100.0, fn(r) { small_button(r, 80.0, 36.0, pressed, w) })
  let id = w.val.unwrap().id()
  assert_eq(t.target_at(140.0, 97.0), Pressed(id))
  assert_eq(t.target_at(140.0, 139.0), Pressed(id))
  assert_eq(t.target_at(99.0, 118.0), Pressed(sheet))
  assert_eq(t.target_at(181.0, 118.0), Pressed(sheet))
}

///|
test "reach: what takes no press is not reached for: only pointed at, said to take none, a column's edge pressed as drawn" {
  let pressed = Ref(0)
  let b : Ref[@view.View?] = Ref(None)
  // only pointed at (View::points): what it is drawn on takes the press, round it as on it
  let (t, sheet) = reach_tree(100.0, 100.0, fn(r) {
    r.box(fn(p) { p.width(Is(Some(20.0))).height(Is(Some(20.0))).points(Is(true)) |> ignore }) |> ignore
  })
  assert_eq(t.target_at(110.0, 97.0), Pressed(sheet))
  // said to take no press
  let (t, sheet) = reach_tree(100.0, 100.0, fn(r) {
    small_button(r, 20.0, 20.0, pressed, b)
    b.val.unwrap().presses(Is(false)) |> ignore
  })
  assert_eq(t.target_at(110.0, 97.0), Pressed(sheet))
  // a column's edge (its pointer's shape a resize): pressed only where it is drawn (the user, 2026-10-28)
  let (t, sheet) = reach_tree(100.0, 100.0, fn(r) {
    small_button(r, 6.0, 300.0, pressed, b)
    b.val.unwrap().cursor(Is(Some(ResizeX))) |> ignore
  })
  let id = b.val.unwrap().id()
  assert_eq(t.target_at(103.0, 200.0), Pressed(id))
  assert_eq(t.target_at(98.0, 200.0), Pressed(sheet))
  assert_eq(t.target_at(108.0, 200.0), Pressed(sheet))
  assert_eq(pressed.val, 0)
}

///|
test "reach: on what a drag pans whole (on_drag's whole) a press is its own, nothing over it reached; on what is held otherwise (a sheet), what is over it is" {
  let pressed = Ref(0)
  let b : Ref[@view.View?] = Ref(None)
  let (t, picture) = reach_tree(
    100.0,
    100.0,
    fn(r) { small_button(r, 36.0, 36.0, pressed, b) },
    ground=fn(g) { g.on_drag(fn(_) {  }, whole=true) |> ignore },
  )
  let id = b.val.unwrap().id()
  assert_eq(t.target_at(118.0, 97.0), Dragged(picture))
  assert_eq(t.target_at(118.0, 118.0), Pressed(id))
  let (t, sheet) = reach_tree(
    100.0,
    100.0,
    fn(r) { small_button(r, 36.0, 36.0, pressed, b) },
    ground=fn(g) { g.on_press(fn() {  }).on_drag(fn(_) {  }) |> ignore },
  )
  let id = b.val.unwrap().id()
  assert_eq(t.target_at(118.0, 97.0), Pressed(id))
  assert_eq(t.target_at(118.0, 95.0), Dragged(sheet))
}

///|
test "reach: a press let go in its room is on what it went down on; the pointer there lights it, what a click presses" {
  let pressed = Ref(0)
  let b : Ref[@view.View?] = Ref(None)
  let (t, sheet) = reach_tree(100.0, 100.0, fn(r) { small_button(r, 36.0, 36.0, pressed, b) })
  let v = b.val.unwrap()
  let id = v.id()
  // down 3 over it, let go 3 under it: the same, its own (what a press let go asks: Tree::target_at, finger_target)
  assert_eq(t.target_at(118.0, 97.0), Pressed(id))
  assert_eq(t.target_at(118.0, 139.0), Pressed(id))
  assert_true(v.finger_target(118.0, 139.0))
  assert_false(v.finger_target(118.0, 141.0))
  // the pointer there: it pointed at, as a press there finds
  for p in [(118.0, 97.0), (139.0, 118.0), (97.0, 139.0)] {
    t.point_at(p.0, p.1)
    assert_eq(t.pointed_now(), Some(id), msg="\{Repr(p)}")
    assert_eq(t.pointed_of(t.target_at(p.0, p.1)), Some(id), msg="\{Repr(p)}")
  }
  t.point_at(118.0, 94.0)
  assert_eq(t.pointed_now(), Some(sheet))
}

///|
test "reach: no node walked more for it, only what is small near the point kept" {
  let pressed = Ref(0)
  let kept : Ref[@view.View?] = Ref(None)
  let rows = 40
  let make = fn(r : @view.View) {
    r.row(Is(false)).gap(Is(0.0)) |> ignore
    for _ in 0..<rows {
      r.box(fn(row) {
        row.row(Is(true)).height(Is(Some(48.0))).on_press(fn() {  }) |> ignore
        small_button(row, 30.0, 30.0, pressed, kept)
        small_button(row, 30.0, 30.0, pressed, kept)
      })
      |> ignore
    }
  }
  let walked = fn(least : Double) -> (Int, Int, @view.Target) {
    let (t, _) = reach_tree(0.0, 0.0, make, least~)
    let w0 = t.work()
    let found = t.target_at(32.0, 100.0)
    let w1 = t.work()
    (w1.found_walked - w0.found_walked, w1.near_kept - w0.near_kept, found)
  }
  let (none_walked, none_kept, _) = walked(0.0)
  let (walked44, kept44, found) = walked(44.0)
  assert_eq(walked44, none_walked)
  assert_eq(none_kept, 0)
  // (the 30 squares at 0 and 36 across of the row at 96 to 144, and of the rows over and under it, near (32, 100))
  assert_true(kept44 <= 6, msg="\{kept44} kept")
  assert_true(found is Pressed(_))
}
