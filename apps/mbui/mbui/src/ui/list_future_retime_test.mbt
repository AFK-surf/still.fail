// A future arrival must not change an earlier row's motion before that arrival begins.

///|
fn closing_before_future_change(change : Int) -> (Double, Double, Double, Double, Double) {
  let entries = [[0, 1]]
  let starts = [0.0]
  let length = [@ui.row_size_ms * 2.0]
  let returning = [false]
  let rows : @ui.ListRows[Int] = @ui.ListRows::new()
  let t = @ui.Tester::new(fn(c) {
    let now = entries[0]
    let (items, _) = rows.rows(
      c,
      now.map(fn(i) { "r\{i}" }),
      now,
      fn(_) { "" },
      from=fn(k) { if k == "r2" || (k == "r1" && returning[0]) { Some(starts[0]) } else { None } },
      ms=fn(k) { if k == "r2" { Some(length[0]) } else { None } },
    )
    c.list("list", items.length(), 50.0, fn(k) {
      c.box(h=Px(50.0), fn() { c.text("Row \{items[k]}") |> ignore }) |> ignore
    }, stick_end=true, sized=rows.sized()) |> ignore
  }, w=300.0, h=400.0)
  t.draw()
  entries[0] = [0]
  t.draw()
  t.run_for(@ui.row_size_ms / 3.0)
  starts[0] = t.time() + @ui.row_size_ms / 2.0
  entries[0] = [0, 2]
  t.draw()
  t.run_for(@ui.row_size_ms / 20.0)
  if change == 1 {
    length[0] = @ui.row_size_ms
  } else if change == 2 {
    returning[0] = true
    entries[0] = [0, 1, 2]
  } else if change == 3 {
    starts[0] = starts[0] + @ui.row_size_ms / 4.0
  }
  t.draw()
  let first = t.row(1).unwrap().3
  let arrival = t.row(2).unwrap().3
  t.run_for(@ui.row_size_ms / 20.0)
  let second = t.row(1).unwrap().3
  t.run_for(@ui.row_size_ms * 4.0)
  let returned = if returning[0] { t.row(1).unwrap().3 } else { 0.0 }
  let arrived = t.row(if returning[0] { 2 } else { 1 }).unwrap().3
  (first, second, arrival, returned, arrived)
}

///|
test "a closing row keeps closing while a future arrival's duration changes" {
  let steady = closing_before_future_change(0)
  let retimed = closing_before_future_change(1)
  assert_true(steady.0 > steady.1 && steady.1 > 0.0, msg="the old row closes: \{Repr(steady)}")
  assert_true((steady.0 - retimed.0).abs() < 0.001 && (steady.1 - retimed.1).abs() < 0.001,
    msg="a future arrival cannot change the closing row yet: \{Repr(steady)} / \{Repr(retimed)}")
  assert_eq(retimed.2, 0.0, msg="the arrival has not started")
  assert_eq(retimed.4, 50.0, msg="the arrival opens once it is due")
}

///|
test "a closing row keeps closing until it is due to return" {
  let steady = closing_before_future_change(0)
  let returning = closing_before_future_change(2)
  assert_true((steady.0 - returning.0).abs() < 0.001 && (steady.1 - returning.1).abs() < 0.001,
    msg="a future return cannot stop the closing row yet: \{Repr(steady)} / \{Repr(returning)}")
  assert_eq(returning.3, 50.0, msg="the returning row opens once it is due")
  assert_eq(returning.4, 50.0, msg="the arrival opens once it is due")
}

///|
test "a closing row keeps closing when a future arrival is moved later" {
  let steady = closing_before_future_change(0)
  let later = closing_before_future_change(3)
  assert_true((steady.0 - later.0).abs() < 0.001 && (steady.1 - later.1).abs() < 0.001,
    msg="a later arrival cannot change the closing row yet: \{Repr(steady)} / \{Repr(later)}")
  assert_eq(later.2, 0.0, msg="the arrival has not started")
  assert_eq(later.4, 50.0, msg="the later arrival opens once it is due")
}

///|
test "an arriving row whose own start is moved to the future does not open early" {
  let entries = [[0]]
  let start = [-1.0]
  let rows : @ui.ListRows[Int] = @ui.ListRows::new()
  let t = @ui.Tester::new(fn(c) {
    let now = entries[0]
    let (items, _) = rows.rows(
      c, now.map(fn(i) { "r\{i}" }), now, fn(_) { "" },
      from=fn(k) { if k == "r1" && start[0] >= 0.0 { Some(start[0]) } else { None } },
    )
    c.list("list", items.length(), 50.0, fn(_) {
      c.box(h=Px(50.0), fn() { c.text("Row") |> ignore }) |> ignore
    }, stick_end=true, sized=rows.sized()) |> ignore
  }, w=300.0, h=400.0)
  entries[0] = [0, 1]
  t.draw()
  start[0] = t.time() + @ui.row_size_ms / 2.0
  t.draw()
  t.run_for(@ui.row_size_ms / 4.0)
  assert_eq(t.row(1).unwrap().3, 0.0, msg="the rescheduled row has not arrived yet")
  t.run_for(@ui.row_size_ms * 2.0)
  assert_eq(t.row(1).unwrap().3, 50.0, msg="the row opens once its start is due")
}

///|
test "an arriving row told to come sooner than it was before it set out opens from then, not from the moment said first" {
  let entries = [[0]]
  let start = [-1.0]
  let rows : @ui.ListRows[Int] = @ui.ListRows::new()
  let t = @ui.Tester::new(fn(c) {
    let now = entries[0]
    let (items, _) = rows.rows(
      c, now.map(fn(i) { "r\{i}" }), now, fn(_) { "" },
      from=fn(k) { if k == "r1" && start[0] >= 0.0 { Some(start[0]) } else { None } },
    )
    c.list("list", items.length(), 50.0, fn(_) {
      c.box(h=Px(50.0), fn() { c.text("Row") |> ignore }) |> ignore
    }, stick_end=true, sized=rows.sized()) |> ignore
  }, w=300.0, h=400.0)
  // said to come a row's way from now
  start[0] = t.time() + @ui.row_size_ms
  entries[0] = [0, 1]
  t.draw()
  t.run_for(@ui.row_size_ms / 4.0)
  assert_eq(t.row(1).unwrap().3, 0.0, msg="not due yet")
  // told now that it comes now (its cause timed once it knows its way)
  start[0] = t.time()
  t.draw()
  t.run_for(@ui.row_size_ms / 4.0)
  let opening = t.row(1).unwrap().3
  assert_true(opening > 0.0 && opening < 50.0, msg="opening from when it was told it comes: \{opening}")
  t.run_for(@ui.row_size_ms * 2.0)
  assert_eq(t.row(1).unwrap().3, 50.0)
}
