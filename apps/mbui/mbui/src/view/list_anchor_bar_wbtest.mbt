///|
test "an anchored list's bar held and dragged from where it is counted otherwise than the hand had it: it goes on from there, no step as the hand comes to it" {
  let s = Scroll::list()
  let t = Tree::new(fn(root) {
    root.box(fn(v) {
      v.width(Is(Some(300.0))).height(Is(Some(100.0)))
      .scrolls_anchored(s, fn() { Array::makei(100, fn(i) { i }) }, est=80.0, ahead=0.0, bar=phase_bar(), fn(row, _) {
        row.height(Is(Some(40.0))) |> ignore
      }) |> ignore
    }) |> ignore
  }, time=fn() { 0.0 })
  t.frame(390.0, 844.0, now=0.0) |> ignore
  // (at its end as counted: 3900, its rows 40 where 80 was said; the hand's place 0 till it comes to it)
  let counted = s.at(t)
  // (its bar out: the pointer along its edge)
  t.pointer_is(296.0, 50.0)
  t.frame(390.0, 844.0, now=60.0) |> ignore
  let start = s.at(t)
  let thumb = match t.thumbs.values().collect() {
    [id] => id
    _ => fail("no one thumb")
  }
  let (tx, ty, tw, th) = t.view_of(thumb).unwrap().rect()
  let x = tx + tw / 2.0
  let y = ty + th / 2.0
  t.drag_at(thumb, Down, x, y, 100.0) |> ignore
  t.drag_at(thumb, Moved, x, y - 1.0, 110.0) |> ignore
  t.frame(390.0, 844.0, now=110.0) |> ignore
  let one = s.at(t)
  t.drag_at(thumb, Moved, x, y - 2.0, 120.0) |> ignore
  t.frame(390.0, 844.0, now=120.0) |> ignore
  let two = s.at(t)
  t.drag_at(thumb, Up, x, y - 2.0, 130.0) |> ignore
  assert_eq((counted, start), (3900.0, 3900.0))
  // (each point the thumb moves the same way on: the first as the second, nothing of where the hand had it)
  assert_true(one < start && two < one, msg="\{start} \{one} \{two}")
  assert_true(((start - one) - (one - two)).abs() < 0.001, msg="\{start} \{one} \{two}")
  t.dispose()
}
