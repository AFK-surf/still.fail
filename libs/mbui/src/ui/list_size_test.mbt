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
  in_place? : Bool = false,
  moves? : Bool = false,
) -> (@ui.Ctx) -> Unit {
  let rows : @ui.ListRows[Int] = @ui.ListRows::new()
  fn(c) {
    let now = ids()
    let (items, keys) = rows.rows(c, now.map(fn(i) { "r" + i.to_string() }), now, fn(i) {
      if i == tall && changed() { "tall" } else { "" }
    }, moves=fn(_) { moves })
    c.list(
      "list",
      items.length(),
      50.0,
      fn(k) {
        let i = items[k]
        let h = if i == tall && changed() { 120.0 } else { 50.0 }
        let b = c.box(h=Px(h), fn() { c.text("Row \{i}", wrap=false) |> ignore })
        if in_place {
          rows.enter(c, b, keys[k])
          rows.leave(c, b, keys[k])
        }
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
test "list: a row coming where it is opens its room at once, what it holds in its middle, faded in as it opens" {
  let n = [20]
  let t = @ui.Tester::new(sized_rows(fn() { Array::makei(n[0], fn(i) { i }) }, in_place=true), w=300.0, h=400.0)
  n[0] = 21
  t.draw()
  let words = fn() {
    t.words().filter(fn(w) { w.0 == "Row 20" })[0]
  }
  let mut between = 0
  let end = t.time() + @ui.row_size_ms
  while t.time() < end {
    let (_, y, _, h) = t.row(20).unwrap()
    let w = words()
    if h > 1.0 && h < 49.0 {
      between += 1
      // (as big as it is open, seen from half open, in its room's middle)
      assert_true((w.5 - @ui.row_held_look(h / 50.0).alpha).abs() < 0.03, msg="\{Repr(w)} \{h}")
      assert_true((w.2 - (y + (h - 50.0) / 2.0)).abs() < 1.5)
    }
    t.frame()
  }
  assert_true(between > 2)
  t.run_for(@ui.row_size_ms)
  assert_eq(words().5, 1.0)
  assert_eq(t.row(20).unwrap().3, 50.0)
}

///|
test "list: a row going closes its room at once, what it holds in its middle, faded out as it closes, the rows over it coming down" {
  let goes = [false]
  let t = @ui.Tester::new(
    sized_rows(fn() { Array::makei(if goes[0] { 19 } else { 20 }, fn(i) { i }) }, in_place=true),
    w=300.0,
    h=400.0,
  )
  let y18 = y_of(t, 18)
  goes[0] = true
  t.draw()
  t.run_for(@ui.row_size_ms / 2.0)
  let (_, y, _, h) = t.row(19).unwrap()
  assert_true(h > 1.0 && h < 49.0)
  let w = t.words().filter(fn(w) { w.0 == "Row 19" })[0]
  assert_true((w.5 - @ui.row_held_look(h / 50.0).alpha).abs() < 0.03, msg="\{Repr(w)} \{h}")
  assert_true((w.2 - (y + (h - 50.0) / 2.0)).abs() < 1.5)
  assert_true((y_of(t, 18) - (y18 + 50.0 - h)).abs() < 0.001)
  assert_eq(bottom_of(t, 19), 400.0)
  rows_end_to_end(t, 12, 20)
  t.run_for(@ui.row_size_ms / 2.0)
  // (closed: out of the list)
  assert_true(t.row(19) is None)
  assert_eq(y_of(t, 18), y18 + 50.0)
}

///|
test "list: two rows going one after the other, side by side: each closes where it stood, neither put over the other" {
  // (an agent's line going as the chat's state line over it still goes: the state line stepped under it at once and
  // back up, 2026-11-09, sfreplay's 29-glass)
  let n = [20]
  let t = @ui.Tester::new(
    sized_rows(fn() { Array::makei(n[0], fn(i) { if n[0] == 18 { i } else if n[0] == 19 && i >= 18 { i + 1 } else { i } }) }, in_place=true),
    w=300.0,
    h=400.0,
  )
  // row 18 goes; a little later row 19, under it, goes too
  n[0] = 19
  t.draw()
  t.run_for(@ui.row_size_ms / 4.0)
  let (_, y18, _, h18) = t.row(18).unwrap()
  n[0] = 18
  t.draw()
  // (18 still where it was, 19 under it, the rows end to end)
  let w18 = t.words().filter(fn(w) { w.0 == "Row 18" })
  let w19 = t.words().filter(fn(w) { w.0 == "Row 19" })
  guard (w18, w19) is ([a, ..], [b, ..]) else { fail("rows 18 and 19 not both drawn: \{Repr(w18)} \{Repr(w19)}") }
  assert_true(a.2 < b.2, msg="row 18 at \{a.2}, row 19 at \{b.2}")
  let (_, y18b, _, _) = t.row(18).unwrap()
  assert_true((y18b - y18).abs() < h18, msg="row 18 from \{y18} to \{y18b}")
  rows_end_to_end(t, 12, 20)
}

///|
/// What is drawn of row `i`'s words, each as many times as it is: how far it is seen.
fn row_seen(t : @ui.Tester, i : Int) -> Array[Double] {
  t.words().filter(fn(w) { w.0 == "Row \{i}" }).map(fn(w) { w.5 })
}

///|
test "list: a row gone down past others is the one that moves: it leaves where it was and comes where it is, those it passed stay" {
  // (a chat its agent finished, below today's chats at work: 2026-10-31 the user, 「忽然所有 chat 都像是新出现的一样」)
  let order = [[0, 1, 2, 3, 4, 5]]
  let t = @ui.Tester::new(
    sized_rows(fn() { order[0] }, stick_end=false, in_place=true, moves=true),
    w=300.0,
    h=400.0,
  )
  order[0] = [1, 2, 3, 0, 4, 5]
  t.draw()
  t.run_for(@ui.row_size_ms / 4.0)
  for i in [1, 2, 3, 4, 5] {
    assert_eq(row_seen(t, i), [1.0], msg="Row \{i}")
  }
  // (row 0 on its way: a copy of it closing where it was, it opening where it is, neither seen whole)
  let seen = row_seen(t, 0)
  assert_true(seen.iter().all(fn(a) { a < 1.0 }), msg="\{Repr(seen)}")
  t.run_for(@ui.row_size_ms)
  assert_eq(row_seen(t, 0), [1.0])
}

///|
test "list: a row gone and given again elsewhere while its room still closes leaves where it was and comes where it is" {
  // (where a chat stands, gone as its agent set to work and back at the list's end as the turn was over a moment
  // after, rows come since between: taken up at the end as tall as it had closed to, its room went from over those
  // rows to under them in one frame, each a step up)
  for in_place in [false, true] {
    let ids = [Array::makei(10, fn(i) { i }) + [100]]
    let t = @ui.Tester::new(sized_rows(fn() { ids[0] }, in_place~), w=300.0, h=400.0)
    assert_eq(bottom_of(t, 10), 400.0)
    // it goes
    ids[0] = Array::makei(10, fn(i) { i })
    t.draw()
    t.run_for(@ui.row_size_ms / 3.0)
    let (_, _, _, closing) = t.row(10).unwrap()
    assert_true(closing > 5.0 && closing < 45.0, msg="in place \{in_place}: closing, \{closing} tall")
    let (_, over, _, _) = t.row(9).unwrap()
    // two rows come at the end, and it again after them
    ids[0] = Array::makei(12, fn(i) { i }) + [100]
    t.draw()
    // where it stood, a copy of it as tall as it had closed to, closing on; the rows come after it; itself from nothing
    let (_, _, _, copy) = t.row(10).unwrap()
    assert_true((copy - closing).abs() < 1.0, msg="in place \{in_place}: \{copy} tall where it stood, \{closing} before")
    let (_, _, _, anew) = t.row(13).unwrap()
    assert_true(anew < 1.0, msg="in place \{in_place}: \{anew} tall where it is now")
    // (what is over them not stepped)
    let (_, over_now, _, _) = t.row(9).unwrap()
    assert_true((over_now - over).abs() < 1.0, msg="in place \{in_place}: the row over them from \{over} to \{over_now}")
    rows_end_to_end(t, 5, 14)
    // at their end: the copy gone, the rows as given
    t.run_for(@ui.row_size_ms)
    assert_eq(t.row(12).unwrap().3, 50.0)
    assert_eq(bottom_of(t, 12), 400.0)
    assert_true(t.row(13) is None)
  }
}

///|
test "list: keys changed in place and given with new items still move their rows" {
  let keys = ["r0", "r1", "r2"]
  let items = Ref([0, 1, 2])
  let rows : @ui.ListRows[Int] = @ui.ListRows::new()
  let t = @ui.Tester::new(fn(c) {
    let (shown, names) = rows.rows(c, keys, items.val, fn(_) { "" }, moves=fn(_) { true })
    c.list("list", shown.length(), 50.0, fn(i) {
      let b = c.box(h=Px(50.0), fn() { c.text("Row \{shown[i]}", wrap=false) |> ignore })
      rows.enter(c, b, names[i])
      rows.leave(c, b, names[i])
    }, sized=rows.sized()) |> ignore
  }, w=300.0, h=400.0)
  keys[0] = "r1"
  keys[1] = "r2"
  keys[2] = "r0"
  items.val = [1, 2, 0]
  t.draw()
  t.run_for(@ui.row_size_ms / 4.0)
  assert_eq(row_seen(t, 0).length(), 2)
  t.run_for(@ui.row_size_ms)
  assert_eq(row_seen(t, 0).length(), 1)
}

///|
test "list: unchanged keys still follow a row's changed version" {
  let changed = [false]
  let t = @ui.Tester::new(
    sized_rows(fn() { Array::makei(20, fn(i) { i }) }, tall=18, changed=fn() { changed[0] }),
    w=300.0,
    h=400.0,
  )
  assert_eq(t.row(18).unwrap().3, 50.0)
  // Both arrays are made anew, but their keys have the same order. Only the version of row 18 changes.
  changed[0] = true
  t.draw()
  assert_true((t.row(18).unwrap().3 - 50.0).abs() < 0.5)
  t.run_for(@ui.row_size_ms / 2.0)
  let halfway = t.row(18).unwrap().3
  assert_true(halfway > 50.0 && halfway < 120.0, msg="halfway: \{halfway}")
  t.run_for(@ui.row_size_ms / 2.0)
  assert_true((t.row(18).unwrap().3 - 120.0).abs() < 0.5)
}

///|
/// Draw the named display's frames strictly before a shared sampling moment, then draw that exact moment.
fn list_frames_until(t : @ui.Tester, at : Double, hz : Int) -> Unit {
  if hz > 0 {
    let step = 1000.0 / hz.to_double()
    let mut next = t.time() + step
    while next < at - 0.001 {
      t.frame_at(next)
      next = next + step
    }
  }
  t.frame_at(at)
}

///|
/// A row begins leaving, then an existing row changes height while the leaving row is still held.
fn list_leaving_changed_history(hz : Int) -> Array[(Double, Double, Double, Double)] raise {
  let goes = [false]
  let changed = [false]
  let t = @ui.Tester::new(
    sized_rows(
      fn() { Array::makei(if goes[0] { 19 } else { 20 }, fn(i) { i }) },
      tall=18,
      changed=fn() { changed[0] },
      in_place=true,
    ),
    w=300.0,
    h=400.0,
  )
  let start = t.time()
  goes[0] = true
  t.draw()
  let change_at = start + @ui.row_size_ms / 4.0
  list_frames_until(t, change_at, hz)
  let (_, _, _, leaving) = t.row(19).unwrap()
  assert_true(leaving > 0.0 && leaving < 50.0, msg="\{hz} Hz: leaving \{leaving}")
  changed[0] = true
  t.draw()
  assert_true(row_seen(t, 19).length() > 0, msg="\{hz} Hz: the old row is still held")
  let sample = fn() {
    let (_, y, _, h) = t.row(18).unwrap()
    match t.row(19) {
      Some((_, old_y, _, old_h)) => (y, h, old_y, old_h)
      None => (y, h, -1.0, -1.0)
    }
  }
  let out = [sample()]
  list_frames_until(t, change_at + @ui.row_size_ms / 2.0, hz)
  let middle = sample()
  assert_true(middle.1 > 50.0 && middle.1 < 120.0, msg="\{hz} Hz: changed row \{Repr(middle)}")
  assert_true(middle.3 > 0.0 && middle.3 < leaving, msg="\{hz} Hz: leaving row \{Repr(middle)}")
  out.push(middle)
  list_frames_until(t, change_at + @ui.row_size_ms * 2.0, hz)
  let end = sample()
  assert_true((end.1 - 120.0).abs() < 0.5 && end.3 == -1.0, msg="\{hz} Hz: settled \{Repr(end)}")
  out.push(end)
  println("leaving and changed row \{hz} Hz: \{Repr(out)}")
  out
}

///|
test "list: a changed version while another row leaves at the same moments with or without frames" {
  let direct = list_leaving_changed_history(0)
  for hz in [60, 120] {
    let frames = list_leaving_changed_history(hz)
    for i in 0..<direct.length() {
      let a = direct[i]
      let b = frames[i]
      assert_true(
        (a.0 - b.0).abs() < 0.01 && (a.1 - b.1).abs() < 0.01 &&
        (a.2 - b.2).abs() < 0.01 && (a.3 - b.3).abs() < 0.01,
        msg="\{hz} Hz, sample \{i}: \{Repr(a)} vs \{Repr(b)}",
      )
    }
  }
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
  t.move_to(100.0, 100.0)
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
  let closing = @ui.Mover::new()
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
                None => @halt.saying("no rows' way as row 18 closes")
              }
            }
            // (where it is at the frame's moment on its way, said to move till its end: built each frame of it)
            let p = (c.moment() - since[0]) / way[0]
            c.shows_motion(closing, p < 1.0)
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
