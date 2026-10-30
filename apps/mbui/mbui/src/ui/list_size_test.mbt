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
test "list: a row going leaves its room whole as it leaves, then closes it to nothing, the rows over it coming down" {
  let goes = [false]
  let t = @ui.Tester::new(sized_rows(fn() { Array::makei(if goes[0] { 19 } else { 20 }, fn(i) { i }) }), w=300.0, h=400.0)
  let y18 = y_of(t, 18)
  goes[0] = true
  t.draw()
  // (as it leaves, ListRows::left: its room as it was, nothing of it cut, nothing over it moving)
  t.run_for(@ui.row_leave_ms - 20.0)
  assert_eq(t.row(19).unwrap().3, 50.0)
  assert_eq(y_of(t, 18), y18)
  t.run_for(20.0)
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

///|
/// A list of 20 rows held at its end, row 18 120 tall: as it is closed, what is in it goes to 50 on the rows' way
/// (Ctx::row_way), and row 20 comes at the end at that
/// moment, as long as `comes_ms`: row 18 goes down its way each frame and the rows over it go one way only.
fn closing_under_coming(comes_ms~ : Double) -> Unit raise {
  let n = [20]
  let since = [-1.0]
  let way = [@ui.row_size_ms]
  let rows : @ui.ListRows[Int] = @ui.ListRows::new()
  let t = @ui.Tester::new(
    fn(c) {
      let now = Array::makei(n[0], fn(i) { i })
      let closed = since[0] >= 0.0
      let (items, _) = rows.rows(
        c,
        now.map(fn(i) { "r" + i.to_string() }),
        now,
        fn(i) { if i == 18 && closed { "closed" } else { "" } },
        ms=fn(k) { if k == "r20" { Some(comes_ms) } else { None } },
      )
      c.list(
        "list",
        items.length(),
        50.0,
        fn(k) {
          let i = items[k]
          let h = if i != 18 {
            50.0
          } else if closed {
            if since[0] == 0.0 {
              match c.row_way() {
                Some((at, ms)) => {
                  since[0] = at
                  way[0] = ms
                }
                None => abort("no rows' way as row 18 closes")
              }
            }
            let p = (c.now_before(since[0] + way[0]) - since[0]) / way[0]
            120.0 - 70.0 * @ui.Ease::Move.at(if p > 1.0 { 1.0 } else { p })
          } else {
            120.0
          }
          c.box(h=Px(h), fn() { c.text("Row \{i}", wrap=false) |> ignore }) |> ignore
        },
        stick_end=true,
        sized=rows.sized(),
      )
      |> ignore
    },
    w=300.0,
    h=400.0,
  )
  assert_eq(bottom_of(t, 19), 400.0)
  since[0] = 0.0
  n[0] = 21
  t.draw()
  let mut y = y_of(t, 15)
  let mut h = t.row(18).unwrap().3
  let mut way_y = 0.0
  let from = t.time()
  while t.time() < from + 650.0 {
    t.frame()
    let y2 = y_of(t, 15)
    let h2 = t.row(18).unwrap().3
    // the row closing: down its way, a step each frame till it is closed
    if h2 > h + 0.001 || (h > 50.5 && h2 > h - 0.001) {
      fail("row 18 at \{t.time()}: \{h} to \{h2}")
    }
    // the rows over it: one way only
    let d = y2 - y
    if d.abs() > 0.01 {
      if way_y != 0.0 && d * way_y < 0.0 {
        fail("row 15 turned back at \{t.time()}: \{y} to \{y2}")
      }
      way_y = d
    }
    y = y2
    h = h2
  }
  assert_eq(t.row(18).unwrap().3, 50.0)
  assert_eq(t.row(20).unwrap().3, 50.0)
  assert_eq(bottom_of(t, 20), 400.0)
}

///|
test "list: a row closing on the rows' way as one comes under it: it goes down each frame, the rows over it never back" {
  closing_under_coming(comes_ms=@ui.row_size_ms)
}

///|
test "list: a row closing on the rows' way under one coming for longer (words flying to it): the rows over go one way" {
  closing_under_coming(comes_ms=520.0)
}

///|
test "list: a row coming as another still comes on its way: the rows over them go on as fast as they went, not from rest" {
  // (a cause coming on the rows' way sets them on from where they are as fast as they go: set out from rest, they
  // stopped and went again, rows_steady.mbt's jolt, which this Tester holds every frame to; 2026-10-30, words sent
  // flying (their row coming as long as they fly) and an agent's line coming as they went)
  let n = [6]
  let rows : @ui.ListRows[Int] = @ui.ListRows::new()
  let t = @ui.Tester::new(
    fn(c) {
      let now = Array::makei(n[0], fn(i) { i })
      let (items, _) = rows.rows(c, now.map(fn(i) { "r" + i.to_string() }), now, fn(_) { "" }, ms=fn(k) {
        if k == "r6" { Some(900.0) } else { None }
      })
      c.list(
        "list",
        items.length(),
        120.0,
        fn(k) { c.box(h=Px(120.0), fn() { c.text("Row \{items[k]}", wrap=false) |> ignore }) |> ignore },
        stick_end=true,
        sized=rows.sized(),
      )
      |> ignore
    },
    w=300.0,
    h=400.0,
  )
  // (each frame drawn, as a host draws them: what rows_steady.mbt holds them to is how each goes from the last)
  let frames = fn(ms : Double) {
    let from = t.time()
    while t.time() < from + ms {
      t.frame()
    }
  }
  n[0] = 7
  t.draw()
  // (at its fastest)
  frames(120.0)
  n[0] = 8
  t.draw()
  frames(900.0)
  assert_eq(t.row(7).unwrap().3, 120.0)
  assert_eq(bottom_of(t, 7), 400.0)
}
