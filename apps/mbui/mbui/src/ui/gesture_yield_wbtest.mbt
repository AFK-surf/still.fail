// A finger down on a row of a column that scrolls, the row's a gesture (View::gesture: a tap, a hold, a drag of a mouse
// let go on it), moved up past the slop: the column's, scrolled by it, the row's gesture called off (no tap); a row
// that drags by itself (its own on_drag: a slider) keeps it, the column not moved, a gesture said in its place as a
// finger was held on it waiting on a tap too.

///|
/// A column of the window's tree scrolling as a page's list, the window's whole, 30 rows 50 high: the first ten each a
/// gesture counting its taps and its drags' ends, the rest each dragging by itself counting its moves. Its scroll and
/// the counts.
fn yield_rows() -> (Tester, @view.Scroll, Ref[Int], Ref[Int], Ref[Int]) {
  let s = @view.Scroll::list()
  let taps = Ref(0)
  let drags = Ref(0)
  let slid = Ref(0)
  let t = Tester::new(fn(_c) {  }, platform=2)
  set_view_app(fn(root) {
    root.box(fn(col) {
      col
      .width(Is(Some(390.0)))
      .height(Is(Some(844.0)))
      .scrolls(s, fn(body) {
        for i in 0..<30 {
          body.box(fn(row) {
            row.height(Is(Some(50.0))).ground(Is(0xEEEEEEFFL)) |> ignore
            if i < 10 {
              row.gesture(touch_slop(), tap=fn(_) { taps.val += 1 }, drag=fn(d) { if d.kind == Up { drags.val += 1 } })
              |> ignore
            } else {
              row.on_drag(fn(d) { if d.kind == Moved { slid.val += 1 } }) |> ignore
            }
          })
          |> ignore
        }
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  (t, s, taps, drags, slid)
}

///|
test "a finger moved up past the slop on a row that is a gesture: the column's, scrolled by it; the row's gesture called off" {
  let (t, s, taps, drags, _) = yield_rows()
  let tree = view_tree().unwrap()
  t.drag(195.0, 300.0, 195.0, 100.0)
  assert_true(s.at(tree) > 150.0, msg="scrolled \{s.at(tree)}")
  assert_eq(taps.val, 0)
  assert_eq(drags.val, 0)
  // (and a tap on it still a tap)
  t.drag(195.0, 300.0, 195.0, 300.0)
  assert_eq(taps.val, 1)
}

///|
test "a finger moved up past the slop on a row that drags by itself: the row's, the column not moved" {
  let (t, s, _, _, slid) = yield_rows()
  let tree = view_tree().unwrap()
  // (row 12, from its middle)
  t.drag(195.0, 625.0, 195.0, 425.0)
  assert_eq(s.at(tree), 0.0)
  assert_true(slid.val > 0)
}

///|
test "a row that was a gesture, a finger held on it as it comes to drag by itself: the next finger on it the row's, the column not moved" {
  let s = @view.Scroll::list()
  let raw = @signals.signal(false)
  let slid = Ref(0)
  let t = Tester::new(fn(_c) {  }, platform=2)
  set_view_app(fn(root) {
    root.box(fn(col) {
      col
      .width(Is(Some(390.0)))
      .height(Is(Some(844.0)))
      .scrolls(s, fn(body) {
        for _ in 0..<30 {
          body.box(fn(row) {
            row.height(Is(Some(50.0))).ground(Is(0xEEEEEEFFL)) |> ignore
            row.reacts(fn() { raw.get() }, fn(r) {
              if r {
                row.on_drag(fn(d) { if d.kind == Moved { slid.val += 1 } }) |> ignore
              } else {
                row.gesture(touch_slop(), tap=fn(_) {  }) |> ignore
              }
            })
          })
          |> ignore
        }
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let tree = view_tree().unwrap()
  // (held on it waiting on a tap, said to drag by itself meanwhile, let go)
  t.touch(0, 195.0, 300.0)
  t.draw()
  raw.set(true)
  t.draw()
  t.touch(2, 195.0, 300.0)
  t.draw()
  t.drag(195.0, 300.0, 195.0, 100.0)
  assert_eq(s.at(tree), 0.0)
  assert_true(slid.val > 0)
}
