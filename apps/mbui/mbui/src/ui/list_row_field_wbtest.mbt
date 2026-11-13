// While a field in one of a page's list's rows has the focus, the list holds what shows and follows its foot no more,
// with any input, the keyboard up or not; it follows again once the focus leaves that field (the focus leaving moving
// nothing: a list still at its foot follows from the next block on, one that rows came under meanwhile once the hand
// takes it to its foot), or once the hand takes it to its foot. Not for a field in the list's pinned foot, nor one
// outside the list. The coordinator of the migration's ruling of 2026-11-13. Acceptance tests: where the rows' words
// are drawn, at every rate (and judged at 60 and 120).
// A person leaves a tree field by Tab alone today; Escape and a press outside any field do not (the coordinator of the
// migration, 2026-11-13: decided when the chat's composer is made as nodes).

///|
/// How tall each block is, how many at first, which holds a field, and the window.
let rf_tall : Double = 40.0

///|
let rf_count : Int = 30

///|
let rf_field_row : Int = 27

///|
let rf_w : Double = 360.0

///|
let rf_h : Double = 500.0

///|
/// How long what comes is let to come, and a step to look at it on its way.
let rf_settle_ms : Double = move_most_ms + 100.0

///|
let rf_step_ms : Double = 16.0

///|
priv struct RfCase {
  t : Tester
  count : @signals.Signal[Int]
  gone : @signals.Signal[Bool]
  row : Field
  foot : Field
  bar : Field
}

///|
/// A window `rf_w` by `rf_h` on `platform`: a bar 40 tall holding a field (`bar`), under it a page's list following its
/// foot, opened at it, of `rf_count` blocks 40 tall (words 行k at each one's top), block rf_field_row holding a field
/// (`row`) under its words (taken out of its keys where `gone`), its pinned foot 40 tall holding a field (`foot`). At
/// rest.
fn rf_case(platform : Int) -> RfCase {
  let count = @signals.signal(rf_count, same=fn(a, b) { a == b })
  let gone = @signals.signal(false, same=fn(a, b) { a == b })
  let row = Field::new()
  let foot = Field::new()
  let bar = Field::new()
  let scroll = @view.Scroll::list()
  let place : @view.ListPlace[Int] = @view.ListPlace::new()
  place.to_end(glide=false)
  let t = Tester::new(fn(_c) {  }, w=rf_w, h=rf_h, platform~)
  set_view_app(fn(root) {
    root.box(fn(col) {
      col.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
      col.box(fn(b) {
        b.height(Is(Some(40.0))).shrink(Is(0.0)) |> ignore
        field(b, bar, label="栏里", font_size=10.0, max_lines=1) |> ignore
      })
      |> ignore
      col.box(fn(o) {
        o.grow(Is(1.0)).basis(Is(Some(0.0))).min_height(Is(Some(0.0))) |> ignore
        o.scrolls_window(
          scroll,
          fn() { Array::makei(count.get(), fn(i) { i }).filter(fn(i) { !(gone.get() && i == rf_field_row) }) },
          est=rf_tall,
          follows=fn() { true },
          place~,
          foot=fn(f) {
            f.box(fn(b) {
              b.height(Is(Some(40.0))) |> ignore
              field(b, foot, label="脚里", font_size=10.0, max_lines=1) |> ignore
            })
            |> ignore
          },
          fn(b, k) {
            b.height(Is(Some(rf_tall))) |> ignore
            b.box(fn(w) { w.height(Is(Some(18.0))).words(Is("行\{k}")) |> ignore }) |> ignore
            if k == rf_field_row {
              b.box(fn(w) {
                w.height(Is(Some(20.0))) |> ignore
                field(w, row, label="行里", font_size=10.0, max_lines=1) |> ignore
              })
              |> ignore
            }
          },
        )
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.run_for(rf_settle_ms)
  { t, count, gone, row, foot, bar }
}

///|
/// Where block `k`'s words are drawn down the window (none: not drawn).
fn rf_y(c : RfCase, k : Int) -> Double? {
  c.t.rect_of("行\{k}").map(fn(r) { r.1 })
}

///|
/// The list's last block's foot as far over the foot's top as it is drawn (0: at its foot; none: not drawn).
fn rf_off_foot(c : RfCase) -> Double? {
  let last = c.count.untracked() - 1
  // (the foot's top: the window's foot less the foot's 40)
  rf_y(c, last).map(fn(y) { rf_h - 40.0 - (y + rf_tall) })
}

///|
/// The row's field given the focus by a press on it (`by`: "press") or by Tab (from the bar's, "tab"): whether so.
fn rf_focus_row(c : RfCase, by : String) -> Bool {
  match by {
    "tab" => {
      for _ in 0..<4 {
        if c.row.focused() {
          break
        }
        c.t.tab()
        c.t.draw()
      }
    }
    _ => {
      guard rf_y(c, rf_field_row) is Some(y) else { return false }
      c.t.tap(100.0, y + 18.0 + 10.0)
      c.t.draw()
    }
  }
  c.row.focused()
}

///|
/// The focus taken from the row's field by one of the two ways there are today (`how`): Tab on (to the next field in
/// the tab order, the list's pinned foot's "脚里", which is in no row: "tab"), or the app letting it go
/// (`Field::let_go`: "let_go"). Whether Escape or a press outside any field takes the focus from a tree field is not
/// this file's.
fn rf_leave(c : RfCase, how : String) -> Unit {
  match how {
    "tab" => {
      c.t.tab()
      c.t.draw()
    }
    _ => c.row.let_go()
  }
}

///|
/// `n` blocks come at the foot by data; where block `k`'s words are drawn at each step on their way and at rest.
fn rf_come(c : RfCase, n : Int, k : Int) -> Array[Double?] {
  c.count.set(c.count.untracked() + n)
  let seen = []
  let mut left = rf_settle_ms
  while left > 0.0 {
    c.t.run_for(rf_step_ms)
    left = left - rf_step_ms
    seen.push(rf_y(c, k))
  }
  seen
}

///|
/// Whether every place in `seen` is `at` to a point.
fn rf_stays(seen : Array[Double?], at : Double?) -> Bool {
  match at {
    Some(a) => seen.iter().all(fn(y) { y is Some(v) && (v - a).abs() <= 1.0 })
    None => false
  }
}

///|
test "1. at its foot, a field in a row given the focus by a press, then by Tab: blocks come at its foot, what shows stays where it is to a point, the new blocks under it" {
  for by in ["press", "tab"] {
    let c = rf_case(0)
    assert_true(rf_focus_row(c, by), msg="\{by}: the row's field not focused")
    let at = rf_y(c, 25)
    let seen = rf_come(c, 3, 25)
    assert_true(rf_stays(seen, at), msg="\{by}: 行25 at \{Repr(at)}, then \{Repr(seen)}")
    // (the new ones under what shows: none drawn over the foot's top, the list's sight going on under its foot)
    for k in rf_count..<(rf_count + 3) {
      let y = rf_y(c, k)
      let under = match y {
        Some(v) => v >= rf_h - 40.0 - 1.0
        None => true
      }
      assert_true(under, msg="\{by}: 行\{k} drawn at \{Repr(y)}")
    }
  }
}

///|
test "2. at its foot on a phone, a field in a row given the focus, the keyboard's room come up: blocks come, what shows held" {
  let c = rf_case(2)
  assert_true(rf_focus_row(c, "press"), msg="the row's field not focused")
  for i in 1..=5 {
    c.t.set_ime_inset(i.to_double() * 30.0)
    c.t.resize_next(rf_w, rf_h - i.to_double() * 30.0)
    c.t.run_for(rf_step_ms)
  }
  c.t.run_for(rf_settle_ms)
  let at = rf_y(c, rf_field_row)
  let seen = rf_come(c, 3, rf_field_row)
  assert_true(rf_stays(seen, at), msg="行\{rf_field_row} at \{Repr(at)}, then \{Repr(seen)}")
}

///|
test "3. the focus leaving the row's field (Tab on to the foot's field; let go) moves nothing; still at its foot, the next block followed" {
  for how in ["tab", "let_go"] {
    let c = rf_case(0)
    assert_true(rf_focus_row(c, "press"), msg="\{how}: the row's field not focused")
    let at = rf_y(c, 25)
    rf_leave(c, how)
    c.t.run_for(rf_settle_ms)
    assert_false(c.row.focused(), msg="\{how}: still focused")
    if how == "tab" {
      assert_true(c.foot.focused(), msg="tab: the foot's field not focused")
    }
    assert_true(rf_stays([rf_y(c, 25)], at), msg="\{how}: 行25 at \{Repr(at)}, then \{Repr(rf_y(c, 25))}")
    rf_come(c, 1, 25) |> ignore
    let off = rf_off_foot(c)
    assert_true(off is Some(o) && o.abs() <= 1.0, msg="\{how}: the next block \{Repr(off)} over the foot")
  }
}

///|
test "3b. rows come while the row's field has the focus, then it is let go: not followed after, till the wheel takes it to its foot; then followed" {
  let c = rf_case(0)
  assert_true(rf_focus_row(c, "press"), msg="the row's field not focused")
  rf_come(c, 3, 25) |> ignore
  rf_leave(c, "let_go")
  c.t.run_for(rf_settle_ms)
  assert_false(c.row.focused(), msg="still focused")
  let at = rf_y(c, 25)
  let seen = rf_come(c, 1, 25)
  assert_true(rf_stays(seen, at), msg="after it left: 行25 at \{Repr(at)}, then \{Repr(seen)}")
  // (the wheel to its foot, then one more: followed)
  c.t.wheel(rf_w / 2.0, rf_h / 2.0, 2000.0)
  c.t.run_for(rf_settle_ms)
  rf_come(c, 1, 25) |> ignore
  let off = rf_off_foot(c)
  assert_true(off is Some(o) && o.abs() <= 1.0, msg="taken to its foot, the next block \{Repr(off)} over the foot")
}

///|
test "4. the focus in the list's foot's field: blocks come, followed as ever" {
  let c = rf_case(0)
  c.foot.focus()
  c.t.draw()
  rf_come(c, 3, 25) |> ignore
  let off = rf_off_foot(c)
  assert_true(off is Some(o) && o.abs() <= 1.0, msg="the last block \{Repr(off)} over the foot")
}

///|
test "5. the focus in a field outside the list (a bar over it): blocks come, followed as ever" {
  let c = rf_case(0)
  c.bar.focus()
  c.t.draw()
  rf_come(c, 3, 25) |> ignore
  let off = rf_off_foot(c)
  assert_true(off is Some(o) && o.abs() <= 1.0, msg="the last block \{Repr(off)} over the foot")
}

///|
test "6. the row whose field has the focus goes by data (a guard): the focus goes with it, the rows over it close up by its height at its foot as ever, the next block followed" {
  let c = rf_case(0)
  assert_true(rf_focus_row(c, "press"), msg="the row's field not focused")
  // (the row with the field taken out of the keys)
  let at = rf_y(c, 25)
  c.gone.set(true)
  c.t.run_for(rf_settle_ms)
  assert_false(c.row.focused(), msg="the focus left in a row let go of")
  assert_true(
    rf_stays([rf_y(c, 25)], at.map(fn(y) { y + rf_tall })),
    msg="行25 at \{Repr(at)}, then \{Repr(rf_y(c, 25))}",
  )
  rf_come(c, 1, 25) |> ignore
  let off = rf_off_foot(c)
  assert_true(off is Some(o) && o.abs() <= 1.0, msg="the next block \{Repr(off)} over the foot")
}

///|
test "7. read up, the row's field given the focus: blocks come, what shows held, as ever" {
  let c = rf_case(0)
  // (read up a little: the field's row still in sight)
  c.t.wheel(rf_w / 2.0, rf_h / 2.0, -60.0)
  c.t.run_for(rf_settle_ms)
  assert_true(rf_focus_row(c, "press"), msg="the row's field not focused")
  let at = rf_y(c, 25)
  let seen = rf_come(c, 3, 25)
  assert_true(rf_stays(seen, at), msg="行25 at \{Repr(at)}, then \{Repr(seen)}")
}

///|
test "8. held by the row's field at its foot, blocks come, the wheel takes it to its foot, the focus still there: the next block followed, and the one after" {
  let c = rf_case(0)
  assert_true(rf_focus_row(c, "press"), msg="the row's field not focused")
  let at = rf_y(c, 25)
  let seen = rf_come(c, 3, 25)
  assert_true(rf_stays(seen, at), msg="held: 行25 at \{Repr(at)}, then \{Repr(seen)}")
  c.t.wheel(rf_w / 2.0, rf_h / 2.0, 2000.0)
  c.t.run_for(rf_settle_ms)
  assert_true(c.row.focused(), msg="the focus gone from the row's field")
  for i in 0..<2 {
    rf_come(c, 1, 25) |> ignore
    let off = rf_off_foot(c)
    assert_true(off is Some(o) && o.abs() <= 1.0, msg="\{i}: the next block \{Repr(off)} over the foot")
  }
  assert_true(c.row.focused(), msg="the focus gone from the row's field at the end")
}

///|
test "9. held by the row's field at its foot, blocks come, the same taken away again by data (at its foot again, no hand): a block comes, held, not followed; the wheel to its foot then, a block: followed" {
  let c = rf_case(0)
  assert_true(rf_focus_row(c, "press"), msg="the row's field not focused")
  let at = rf_y(c, 25)
  rf_come(c, 3, 25) |> ignore
  // (the three taken away: at its foot again as it was, by data alone)
  rf_come(c, -3, 25) |> ignore
  let off = rf_off_foot(c)
  assert_true(off is Some(o) && o.abs() <= 1.0, msg="the three gone: the last block \{Repr(off)} over the foot")
  assert_true(rf_stays([rf_y(c, 25)], at), msg="the three gone: 行25 at \{Repr(at)}, then \{Repr(rf_y(c, 25))}")
  let seen = rf_come(c, 1, 25)
  assert_true(rf_stays(seen, at), msg="a block come after: 行25 at \{Repr(at)}, then \{Repr(seen)}")
  assert_true(c.row.focused(), msg="the focus gone from the row's field")
  // (the hand's release still so after it)
  c.t.wheel(rf_w / 2.0, rf_h / 2.0, 2000.0)
  c.t.run_for(rf_settle_ms)
  rf_come(c, 1, 25) |> ignore
  let off = rf_off_foot(c)
  assert_true(off is Some(o) && o.abs() <= 1.0, msg="the wheel to its foot: the next block \{Repr(off)} over the foot")
}
