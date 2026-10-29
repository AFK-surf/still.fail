// A list's rows' heights as they change (list_size.mbt): each row's way from the height it had to its new one, the rows
// end to end at every moment, what is in view staying where the list's rule has it.

///|
/// A list of the rows `ids()` gives (each 50 tall, but row `tall` 120 once `changed()`), keyed by their ids: what
/// came, went and changed worked out by the list (ListRows) as it is built.
fn sized_rows(
  ids : () -> Array[Int],
  stick_end? : Bool = true,
  tall? : Int = -1,
  changed? : () -> Bool = fn() { false },
) -> (@ui.Ctx) -> Unit {
  let rows : @ui.ListRows[Int] = @ui.ListRows::new()
  fn(c) {
    let now = ids()
    let (items, keys) = rows.rows(c, now.map(fn(i) { "r" + i.to_string() }), now, fn(i) {
      if i == tall && changed() { "tall" } else { "" }
    })
    c.list(
      "list",
      items.length(),
      50.0,
      fn(k) {
        let i = items[k]
        ignore(keys)
        let h = if i == tall && changed() { 120.0 } else { 50.0 }
        c.box(h=Px(h), fn() { c.text("Row \{i}", wrap=false) |> ignore }) |> ignore
      },
      stick_end~,
      sized=rows.sized(),
    )
    |> ignore
  }
}

///|
/// Rows `from..<to` laid end to end, as tall as `heights` says.
fn rows_end_to_end(t : @ui.Tester, from : Int, to : Int) -> Unit raise {
  for i in from..<(to - 1) {
    let (_, y, _, h) = t.row(i).unwrap()
    let (_, y2, _, _) = t.row(i + 1).unwrap()
    assert_true((y + h - y2).abs() < 0.001)
  }
}

///|
test "list: a row come at the end of a list held there opens its room from nothing, its foot where the view's is" {
  let n = [20]
  let t = @ui.Tester::new(sized_rows(fn() { Array::makei(n[0], fn(i) { i }) }), w=300.0, h=400.0)
  assert_eq(bottom_of(t, 19), 400.0)
  n[0] = 21
  t.draw()
  let (_, _, _, h0) = t.row(20).unwrap()
  assert_true(h0 < 1.0)
  t.run_for(@ui.row_size_ms / 2.0)
  let (_, y, _, h) = t.row(20).unwrap()
  // half its time: on a move's way, the rows over it gone up as far as it grew
  assert_true((h - 50.0 * @ui.Ease::Move.at(0.5)).abs() < 0.5)
  assert_true((y + h - 400.0).abs() < 0.001)
  rows_end_to_end(t, 12, 21)
  t.run_for(@ui.row_size_ms / 2.0)
  assert_eq(t.row(20).unwrap().3, 50.0)
  assert_eq(bottom_of(t, 20), 400.0)
  // (its scroll bar, shown as it went to its end, gone in its time)
  t.run_for(@ui.scrollbar_hold_ms + @ui.scrollbar_fade_ms)
  t.assert_idle()
}

///|
test "list: a row going closes its room to nothing, the rows over it coming down" {
  let goes = [false]
  let t = @ui.Tester::new(sized_rows(fn() { Array::makei(if goes[0] { 19 } else { 20 }, fn(i) { i }) }), w=300.0, h=400.0)
  let y18 = y_of(t, 18)
  goes[0] = true
  t.draw()
  t.run_for(@ui.row_size_ms / 2.0)
  let h = t.row(19).unwrap().3
  assert_true(h > 1.0 && h < 49.0)
  assert_true((y_of(t, 18) - (y18 + 50.0 - h)).abs() < 0.001)
  assert_eq(bottom_of(t, 19), 400.0)
  rows_end_to_end(t, 12, 20)
  t.run_for(@ui.row_size_ms / 2.0)
  // (closed: out of the list)
  assert_true(t.row(19) is None)
  assert_eq(y_of(t, 18), y18 + 50.0)
}

///|
test "list: a row read from stays where it shows as one over it grows and one under it comes" {
  let n = [40]
  let changed = [false]
  let t = @ui.Tester::new(
    sized_rows(fn() { Array::makei(n[0], fn(i) { i }) }, tall=5, changed=fn() { changed[0] }),
    w=300.0,
    h=400.0,
  )
  t.move(100.0, 100.0)
  t.wheel(100.0, 100.0, -1.0e6)
  t.wheel(100.0, 100.0, 330.0)
  t.run_for(@ui.scrollbar_hold_ms + @ui.scrollbar_fade_ms)
  let y8 = y_of(t, 8)
  let y7 = y_of(t, 7)
  changed[0] = true
  n[0] = 41
  t.draw()
  t.run_for(@ui.row_size_ms / 2.0)
  // read from row 7 (the first wholly in view): it stays; row 5 over it grows up
  assert_eq(y_of(t, 7), y7)
  assert_eq(y_of(t, 8), y8)
  t.run_for(@ui.row_size_ms)
  assert_eq(y_of(t, 7), y7)
  assert_eq(t.row(5).map(fn(r) { r.3 }), None)
}
