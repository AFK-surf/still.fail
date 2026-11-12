// A row of ways of saying one thing (View::one_of): the first that fits its room whole laid out and drawn, the last
// where none does; another as the room changes, in the frame laid out at that room, nothing coming or going.

///|
/// A row as wide as the window (16 down, at its left) of two ways of saying one thing: `wide`, a row of a box 120 wide
/// and one 80 wide (200 in all); `narrow`, the same two one over the other (120 wide). Each box's id by its name
/// (a1, b1 of the first; a2, b2 of the second). Laid out once, `w` wide.
fn one_of_row(ids : Map[String, @view.NodeId], w : Double) -> @view.Tree {
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(row) {
        row.over(Is(true)).row(Is(true)).one_of(Is(true)).offset(Is((0.0, 16.0))).width(By(fn() { Some(row.window().0) })) |> ignore
        for way in [1, 2] {
          row.box(fn(o) {
            o.row(Is(way == 1)).shrink(Is(0.0)) |> ignore
            for part in [("a", 120.0), ("b", 80.0)] {
              o.box(fn(b) {
                ids["\{part.0}\{way}"] = b.id()
                b.width(Is(Some(part.1))).height(Is(Some(16.0))).shrink(Is(0.0)).ground(Is(0xFF336699L)) |> ignore
              })
              |> ignore
            }
          })
          |> ignore
        }
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(w, 300.0) |> ignore
  t
}

///|
/// Where box `name` is drawn (x, y), if it is.
fn one_of_at(t : @view.Tree, ids : Map[String, @view.NodeId], name : String) -> (Double, Double)? {
  t.drawn_of(ids[name]).map(fn(d) { (d.x, d.y) })
}

///|
test "one_of: room for the first whole (300): it alone drawn, its two side by side; not (150): the last alone, one over the other" {
  let ids : Map[String, @view.NodeId] = Map([])
  let t = one_of_row(ids, 300.0)
  assert_eq(one_of_at(t, ids, "a1"), Some((0.0, 16.0)), msg="300: the first's a")
  assert_eq(one_of_at(t, ids, "b1"), Some((120.0, 16.0)), msg="300: the first's b, beside it")
  assert_eq(one_of_at(t, ids, "a2"), None, msg="300: the last not drawn")
  assert_eq(one_of_at(t, ids, "b2"), None, msg="300: the last not drawn")
  let n = one_of_row(ids, 150.0)
  assert_eq(one_of_at(n, ids, "a1"), None, msg="150: the first not drawn")
  assert_eq(one_of_at(n, ids, "b1"), None, msg="150: the first not drawn")
  assert_eq(one_of_at(n, ids, "a2"), Some((0.0, 16.0)), msg="150: the last's a")
  assert_eq(one_of_at(n, ids, "b2"), Some((0.0, 32.0)), msg="150: the last's b, under it")
}

///|
test "one_of: the window made narrower, then wider again: the other way in the frame laid out at that width, at once, the same nodes" {
  let ids : Map[String, @view.NodeId] = Map([])
  let t = one_of_row(ids, 300.0)
  let first = ids["a1"]
  t.frame(150.0, 300.0) |> ignore
  assert_eq(one_of_at(t, ids, "a1"), None, msg="150: the first gone at once")
  assert_eq(one_of_at(t, ids, "a2"), Some((0.0, 16.0)), msg="150: the last there at once")
  assert_eq(one_of_at(t, ids, "b2"), Some((0.0, 32.0)), msg="150: one over the other, at once")
  t.frame(300.0, 300.0) |> ignore
  assert_eq(one_of_at(t, ids, "a1"), Some((0.0, 16.0)), msg="300 again: the first back at once")
  assert_eq(one_of_at(t, ids, "b1"), Some((120.0, 16.0)), msg="300 again: side by side")
  assert_eq(one_of_at(t, ids, "a2"), None, msg="300 again: the last gone")
  assert_true(ids["a1"] == first, msg="the same node, not made again")
}

///|
test "one_of: room for neither whole (100): the last, all of it" {
  let ids : Map[String, @view.NodeId] = Map([])
  let t = one_of_row(ids, 100.0)
  assert_eq(one_of_at(t, ids, "a1"), None, msg="100: the first not drawn")
  assert_eq(one_of_at(t, ids, "a2"), Some((0.0, 16.0)), msg="100: the last's a")
  assert_eq(one_of_at(t, ids, "b2"), Some((0.0, 32.0)), msg="100: the last's b")
}
