// What is cut short (View::cuts: words, as an old view's w=Cut) gives way along what holds it only where that is a row,
// past a slot to what lays it out, never down a column; said not cut, or how it gives way said otherwise
// (View::shrink), the one said last. (A box 140 by 36 here: words measure to the room they are given, so a box's own
// size shows what gives way and what does not.)

///|
/// A box 140 by 36 in a box 100 by 10 (a row while `row` says), in a slot of it; cut short while `cut` says, else
/// given way as `shrink` says where that is said after or before (`order`).
fn cut_tree(
  row : @signals.Signal[Bool],
  cut : @signals.Signal[Bool],
  order? : String = "cuts",
) -> (@view.Tree, () -> (Double, Double)) {
  let id : Ref[@view.NodeId?] = Ref(None)
  let t = @view.Tree::new(
    fn(root) {
      root.lines_up(Is(Some(Start))) |> ignore
      root.box(fn(b) {
        b.width(Is(Some(100.0))).height(Is(Some(10.0))).row(By(fn() { row.get() })) |> ignore
        // (shown in a slot of the box's: laid out in its place, the box what lays it out)
        b.show(fn() { true }, fn(w) {
          id.val = Some(w.id())
          w.width(Is(Some(140.0))).height(Is(Some(36.0))).min_width(Is(Some(0.0))).ground(Is(0x336699FFL)) |> ignore
          match order {
            "cuts" => w.cuts(By(fn() { cut.get() })) |> ignore
            "shrink after" => w.cuts(By(fn() { cut.get() })).shrink(Is(0.0)) |> ignore
            _ => w.shrink(Is(1.0)).cuts(By(fn() { cut.get() })) |> ignore
          }
        })
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  let size = fn() {
    t.frame(390.0, 844.0) |> ignore
    match t.drawn().search_by(fn(d) { Some(d.id) == id.val }) {
      Some(i) => (t.drawn()[i].w, t.drawn()[i].h)
      None => (-1.0, -1.0)
    }
  }
  (t, size)
}

///|
test "cuts: in a row given way along it, in a column as wide as it is and never squeezed down, past a slot, as the row turns" {
  let row = @signals.signal(true)
  let cut = @signals.signal(true)
  let (_, size) = cut_tree(row, cut)
  // (in the row: cut to its 100)
  assert_eq(size(), (100.0, 36.0))
  // (the row a column: its own size, not squeezed down to the box's 10)
  row.set(false)
  assert_eq(size(), (140.0, 36.0))
  // (a row again: given way again)
  row.set(true)
  assert_eq(size(), (100.0, 36.0))
  // (not cut: in the row, its own size, given way nowhere)
  cut.set(false)
  assert_eq(size(), (140.0, 36.0))
  // (and so as the row turns a column and back: nothing left of being cut)
  row.set(false)
  assert_eq(size(), (140.0, 36.0))
  row.set(true)
  assert_eq(size(), (140.0, 36.0))
}

///|
test "cuts and shrink: the one said last takes how it gives way; what the other followed changes it no more" {
  // (shrink said after cuts, none: given way nowhere, whatever cut and the row say after)
  let row = @signals.signal(true)
  let cut = @signals.signal(true)
  let (_, size) = cut_tree(row, cut, order="shrink after")
  assert_eq(size(), (140.0, 36.0))
  cut.set(false)
  cut.set(true)
  row.set(false)
  assert_eq(size(), (140.0, 36.0))
  row.set(true)
  assert_eq(size(), (140.0, 36.0))
  // (cuts said after shrink 1: cut short, the shrink said before let go of: not squeezed down in a column)
  let row = @signals.signal(false)
  let cut = @signals.signal(true)
  let (_, size) = cut_tree(row, cut, order="cuts after")
  assert_eq(size(), (140.0, 36.0))
  row.set(true)
  assert_eq(size(), (100.0, 36.0))
  cut.set(false)
  assert_eq(size(), (140.0, 36.0))
}
