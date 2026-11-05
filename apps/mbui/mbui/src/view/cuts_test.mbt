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

///|
test "cuts kept for fit: the title whole before its marks, cut only once they leave; words and room changing keep the same nodes" {
  let room = @signals.signal(198.0)
  let words = @signals.signal("abcdefghijkl")
  let nodes : Map[String, @view.View] = {}
  let t = @view.Tree::new(fn(root) {
    root.lines_up(Is(Some(Start))) |> ignore
    root.box(fn(row) {
      row.row(Is(true)).fits(Is(true)).width(By(fn() { Some(room.get()) }))
      .padding(Is((0.0, 0.0, 8.0, 0.0))).gap(Is(8.0)) |> ignore
      nodes["title"] = row.box(fn(title) {
        title.words(By(fn() { words.get() }), look={ ..@view.words_plain, wrap: false })
        .cuts(Is(true), keep=true) |> ignore
      })
      nodes["people"] = row.box(fn(people) {
        people.width(Is(Some(38.0))).height(Is(Some(19.0))).drops(Is(1)) |> ignore
      })
      row.box(fn(agent) { agent.width(Is(Some(45.0))).height(Is(Some(22.0))) |> ignore }) |> ignore
    }) |> ignore
  }, measure=fn(s, _, _) { (s.length().to_double() * 8.0, 22.0) })
  let width = fn() {
    t.frame(390.0, 844.0) |> ignore
    t.drawn_of(nodes["title"].id()).unwrap().w
  }
  assert_eq(width(), 96.0)
  assert_true(nodes["people"].left_out_now(), msg="the title counted before the people: 203 needed, 198 offered")
  room.set(203.0)
  assert_eq(width(), 96.0)
  assert_false(nodes["people"].left_out_now(), msg="just enough room: the same people back")
  room.set(140.0)
  assert_eq(width(), 79.0, msg="all that may leave gone, the title fits what is left")
  assert_true(nodes["people"].left_out_now())
  words.set("abc")
  assert_eq(width(), 24.0)
  assert_false(nodes["people"].left_out_now(), msg="a shorter title makes room for the same people")
  words.set("abcdefghijkl")
  assert_eq(width(), 79.0)
  assert_true(nodes["people"].left_out_now())
  nodes["title"].cuts(Is(true)) |> ignore
  assert_eq(width(), 33.0)
  assert_false(nodes["people"].left_out_now(), msg="no longer kept before them: title gives way first")
  nodes["title"].cuts(Is(true), keep=true).shrink(Is(1.0)) |> ignore
  assert_eq(width(), 33.0)
  assert_false(nodes["people"].left_out_now(), msg="shrink said last takes over cuts and its keep")
}
