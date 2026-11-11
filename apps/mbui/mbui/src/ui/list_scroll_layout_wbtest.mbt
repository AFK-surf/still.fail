// A scroll within the rows already on screen changes their position, not their sizes. Nothing needs a flex layout
// until an edge exposes another row or a separate state change changes a size.

///|
test "scrolling within the visible rows moves their drawing and hit without another layout" {
  let rows : ListRows[Int] = ListRows::new()
  let pressed : Array[Int] = []
  let t = Tester::new(fn(c) {
    let ids = Array::makei(30, fn(i) { i })
    let (items, _) = rows.rows(c, ids.map(fn(i) { "row/" + i.to_string() }), ids, fn(_) { "" })
    c.list("rows", items.length(), 40.0, fn(k) {
      let item = items[k]
      let id = c.id("row/\{item}")
      c.on_press(id, fn() {
        pressed.push(item)
      })
      c.box(id~, h=Px(40.0), bg=0x224466FFL, fn() {
        c.text("row \{item}", wrap=false) |> ignore
      }) |> ignore
    }, rows_read=true, sized=rows.sized()) |> ignore
  }, w=300.0, h=160.0)
  t.check_looks(false)
  t.set_rows_on_pixels(true)
  t.draw()
  let at = t.time()
  // Both edge rows are already laid out; a further five points exposes no new row.
  t.wheel_told(100.0, 100.0, 0.0, 20.0, 0, at + 1.0)
  t.frame_at(at + 16.0)
  t.frame_at(at + 16.0)
  let before = t.row(2).unwrap()
  let first = t.visible()
  let computes = @flex.computes()
  let state = (list_fast_info_reads.length(), old_whole.val, nodes_run.on, g().laid_watch.length(), g().shown_watch.length(), g().layers.length(), g().editors.length(), list_hand_watches.length())
  t.wheel_told(100.0, 100.0, 0.0, 5.0, 0, at + 17.0)
  let dirty = list_hand_dirty.length()
  t.frame_at(at + 32.0)
  let after = t.row(2).unwrap()
  let layouts = @flex.computes() - computes
  let why = t.built_why()
  assert_eq(t.visible(), first, msg="the scroll must not expose another row")
  assert_true(after.1 < before.1, msg="the row must move: \{Repr(before)} -> \{Repr(after)}")
  assert_true(t.drawn_rects().iter().any(fn(r) { r.4 == 0x224466FFL && (r.1 - after.1).abs() < 0.01 }), msg="the moved row must be drawn at its new position")
  t.tap_once(100.0, after.1 + 20.0)
  assert_eq(pressed, [2], msg="the moved row must be hit at its new position")
  assert_eq(layouts, 0, msg="no row entered and no size changed, but flex was run \{layouts} times; why: \{why}; state: \{Repr(state)}; dirty: \{dirty}")
}

///|
test "a scroll that exposes another row lays it out" {
  let t = Tester::new(fn(c) {
    c.list("rows", 30, 40.0, fn(k) {
      c.box(h=Px(40.0), fn() { c.text("row \{k}", wrap=false) |> ignore }) |> ignore
    }, rows_read=true) |> ignore
  }, w=300.0, h=160.0)
  t.check_looks(false)
  t.set_rows_on_pixels(true)
  t.draw()
  let at = t.time()
  t.wheel_told(100.0, 100.0, 0.0, 20.0, 0, at + 1.0)
  t.frame_at(at + 16.0)
  t.frame_at(at + 16.0)
  let before = @flex.computes()
  t.wheel_told(100.0, 100.0, 0.0, 30.0, 0, at + 17.0)
  t.frame_at(at + 32.0)
  assert_true(t.visible().0 >= 1, msg="the first row must have left the viewport")
  assert_true(t.row(5) is Some(_), msg="the newly exposed row must be made")
  assert_true(@flex.computes() > before, msg="the new row must be laid out")
}

///|
test "the fast scroll frame matches a complete layout and paint" {
  let rows : ListRows[Int] = ListRows::new()
  let t = Tester::new(fn(c) {
    let ids = Array::makei(30, fn(i) { i })
    let (items, _) = rows.rows(c, ids.map(fn(i) { "row/" + i.to_string() }), ids, fn(_) { "" })
    c.list("rows", items.length(), 40.0, fn(k) {
      let id = c.id("row/\{items[k]}")
      c.box(id~, h=Px(40.0), bg=0x224466FFL, fn() {
        c.text("row \{items[k]}", wrap=false) |> ignore
      }) |> ignore
    }, rows_read=true, sized=rows.sized()) |> ignore
  }, w=300.0, h=160.0)
  t.check_looks(true)
  t.set_rows_on_pixels(true)
  t.draw()
  let at = t.time()
  t.wheel_told(100.0, 100.0, 0.0, 20.0, 0, at + 1.0)
  t.frame_at(at + 16.0)
  t.frame_at(at + 16.0)
  let before = t.row(2).unwrap()
  t.wheel_told(100.0, 100.0, 0.0, 5.0, 0, at + 17.0)
  let reason = Ref("")
  let hits : Ref[Array[Int]] = Ref([])
  let rects : Ref[Array[Double]] = Ref([])
  let clips : Ref[Array[Double]] = Ref([])
  let ends : Ref[Array[Int]] = Ref([])
  let row_hit = Ref(0)
  let clipped_hit = Ref(0)
  // The hook sees the paint-only result before the Tester builds the same frame whole for comparison.
  frame_hook.val = Some(fn() {
    let c = g()
    reason.val = painted_why.val
    hits.val = c.hit_ids.copy()
    rects.val = c.hit_rects.copy()
    clips.val = c.hit_clips.copy()
    ends.val = c.hit_ends.copy()
    row_hit.val = hit_in(c.hit_ids, c.hit_rects, 100.0, t.row(2).unwrap().1 + 1.0)
    clipped_hit.val = hit_in(c.hit_ids, c.hit_rects, 100.0, 5.0)
  })
  t.frame_at(at + 32.0)
  frame_hook.val = None
  assert_eq(reason.val, "a list scrolled without changing its rows", msg="this comparison must exercise the fast path")
  assert_true(t.row(2).unwrap().1 < before.1)
  assert_eq(hits.val, g().hit_ids, msg="the fast and complete paths must publish the same targets")
  assert_eq(rects.val, g().hit_rects, msg="the fast and complete paths must publish the same target rectangles")
  assert_eq(clips.val, g().hit_clips, msg="the fast and complete paths must publish the same target clips")
  assert_eq(ends.val, g().hit_ends, msg="the fast and complete paths must publish the same target hierarchy")
  assert_true(row_hit.val != 0 && clipped_hit.val != 0)
  assert_eq(row_hit.val, hit_in(g().hit_ids, g().hit_rects, 100.0, t.row(2).unwrap().1 + 1.0))
  assert_eq(clipped_hit.val, hit_in(g().hit_ids, g().hit_rects, 100.0, 5.0))
}

///|
test "a size change with a scroll lays out the new row height" {
  let height = @signals.signal(40.0)
  let t = Tester::new(fn(c) {
    c.list("rows", 30, 40.0, fn(k) {
      c.box(h=Px(height.get()), fn() { c.text("row \{k}", wrap=false) |> ignore }) |> ignore
    }, rows_read=true) |> ignore
  }, w=300.0, h=160.0)
  t.check_looks(false)
  t.set_rows_on_pixels(true)
  t.draw()
  let at = t.time()
  t.wheel_told(100.0, 100.0, 0.0, 20.0, 0, at + 1.0)
  t.frame_at(at + 16.0)
  t.frame_at(at + 16.0)
  let before = @flex.computes()
  height.set(50.0)
  t.wheel_told(100.0, 100.0, 0.0, 5.0, 0, at + 17.0)
  t.frame_at(at + 32.0)
  assert_true(@flex.computes() > before, msg="the changed height must be laid out")
  assert_true((t.row(2).unwrap().3 - 50.0).abs() < 0.01, msg="the new row height must be used")
}

///|
test "a view that reads the list's place is updated when the list scrolls" {
  let place : Ref[(Int, Double, Double)?] = Ref(None)
  let t = Tester::new(fn(c) {
    place.val = c.list_place("rows")
    c.list("rows", 30, 40.0, fn(k) {
      c.box(h=Px(40.0), fn() { c.text("row \{k}", wrap=false) |> ignore }) |> ignore
    }, rows_read=true) |> ignore
  }, w=300.0, h=160.0)
  t.check_looks(false)
  t.set_rows_on_pixels(true)
  t.draw()
  let at = t.time()
  t.wheel_told(100.0, 100.0, 0.0, 20.0, 0, at + 1.0)
  t.frame_at(at + 16.0)
  t.frame_at(at + 16.0)
  let before = place.val.unwrap()
  t.wheel_told(100.0, 100.0, 0.0, 5.0, 0, at + 17.0)
  t.frame_at(at + 32.0)
  let after = place.val.unwrap()
  assert_true(after.1 > before.1, msg="the place read by the view must follow the scroll: \{Repr(before)} -> \{Repr(after)}")
}

///|
test "an unchanged list info projection does not require layout" {
  let rows : ListRows[Int] = ListRows::new()
  let t = Tester::new(fn(c) {
    // The page only depends on whether the list is at its end, not the exact offset.
    c.list_info_as("rows", fn(i) { i.map(fn(v) { v.at_end }) }) |> ignore
    let ids = Array::makei(30, fn(i) { i })
    let (items, _) = rows.rows(c, ids.map(fn(i) { "row/" + i.to_string() }), ids, fn(_) { "" })
    c.list("rows", items.length(), 40.0, fn(k) {
      c.box(h=Px(40.0), fn() { c.text("row \{items[k]}", wrap=false) |> ignore }) |> ignore
    }, rows_read=true, sized=rows.sized()) |> ignore
  }, w=300.0, h=160.0)
  t.check_looks(false)
  t.set_rows_on_pixels(true)
  t.draw()
  let at = t.time()
  t.wheel_told(100.0, 100.0, 0.0, 20.0, 0, at + 1.0)
  t.frame_at(at + 16.0)
  t.frame_at(at + 16.0)
  let before = t.row(2).unwrap()
  let computes = @flex.computes()
  t.wheel_told(100.0, 100.0, 0.0, 5.0, 0, at + 17.0)
  t.frame_at(at + 32.0)
  assert_true(t.row(2).unwrap().1 < before.1)
  assert_eq(@flex.computes() - computes, 0, msg="an unchanged projection should allow a scroll without layout")
}

///|
fn place_report_after_scroll(keep : Bool) -> ((Int, Double, Double), (Int, Double, Double)) {
  let rows : ListRows[Int] = ListRows::new()
  let observed : Ref[(Int, Double, Double)?] = Ref(None)
  let t = Tester::new(fn(c) {
    let reader = c.list_reader("rows")
    c.after_build_or_scroll("observe-place", fn() { observed.val = reader.place() })
    let ids = Array::makei(30, fn(i) { i })
    let (items, _) = rows.rows(c, ids.map(fn(i) { "row/" + i.to_string() }), ids, fn(_) { "" })
    c.list("rows", items.length(), 40.0, fn(k) {
      c.box(h=Px(40.0), fn() { c.text("row \{items[k]}", wrap=false) |> ignore }) |> ignore
    }, rows_read=true, sized=rows.sized()) |> ignore
  }, w=300.0, h=160.0)
  t.check_looks(false)
  t.set_rows_on_pixels(true)
  t.drawn_again(keep)
  t.draw()
  let at = t.time()
  t.wheel_told(100.0, 100.0, 0.0, 20.0, 0, at + 1.0)
  t.frame_at(at + 16.0)
  t.frame_at(at + 16.0)
  let before = observed.val.unwrap()
  t.wheel_told(100.0, 100.0, 0.0, 5.0, 0, at + 17.0)
  t.frame_at(at + 32.0)
  let after = observed.val.unwrap()
  t.drawn_again(true)
  (before, after)
}

///|
test "a scroll updates the list place observed after the build" {
  let baseline = place_report_after_scroll(false)
  let kept = place_report_after_scroll(true)
  println("AFTER_BUILD_PLACE ordinary=\{Repr(baseline)} retained=\{Repr(kept)}")
  assert_true(baseline.1.1 > baseline.0.1, msg="the ordinary path must observe the new place: \{Repr(baseline)}")
  assert_eq(kept, baseline, msg="the kept path must report the same places as the ordinary path")
}

///|
test "a changed list info projection falls back to a new layout" {
  let rows : ListRows[Int] = ListRows::new()
  let kick = @signals.signal(0)
  let set_follow = Ref(false)
  let seen = Ref(false)
  let t = Tester::new(fn(c) {
    kick.get() |> ignore
    seen.val = c.list_info_as("rows", fn(i) { i.map(fn(v) { v.following_row }) })
      .map(fn(i) { i.following_row }).unwrap_or(false)
    if set_follow.val {
      c.list_follow_from("rows", 2)
      set_follow.val = false
    }
    let ids = Array::makei(30, fn(i) { i })
    let (items, _) = rows.rows(c, ids.map(fn(i) { "row/" + i.to_string() }), ids, fn(_) { "" })
    c.list("rows", items.length(), 40.0, fn(k) {
      c.box(h=Px(40.0), fn() { c.text("row \{items[k]}", wrap=false) |> ignore }) |> ignore
    }, rows_read=true, sized=rows.sized()) |> ignore
  }, w=300.0, h=160.0)
  t.check_looks(false)
  t.set_rows_on_pixels(true)
  t.draw()
  let at = t.time()
  t.wheel_told(100.0, 100.0, 0.0, 20.0, 0, at + 1.0)
  t.frame_at(at + 16.0)
  set_follow.val = true
  kick.set(1)
  t.frame_at(at + 17.0)
  assert_true(seen.val, msg="the view must first see the followed row")
  let before = @flex.computes()
  t.wheel_told(100.0, 100.0, 0.0, 5.0, 0, at + 18.0)
  t.frame_at(at + 33.0)
  assert_false(seen.val, msg="a scroll lets go of the followed row")
  assert_true(@flex.computes() > before, msg="a changed projection must rebuild and lay out")
}

///|
test "a scroll keeps targets and hits the row in its new clipped position" {
  let rows : ListRows[Int] = ListRows::new()
  let pressed : Array[Int] = []
  let t = Tester::new(fn(c) {
    let ids = Array::makei(30, fn(i) { i })
    let (items, _) = rows.rows(c, ids.map(fn(i) { "row/" + i.to_string() }), ids, fn(_) { "" })
    c.list("rows", items.length(), 40.0, fn(k) {
      let item = items[k]
      let id = c.id("row/\{item}")
      c.on_press(id, fn() { pressed.push(item) })
      c.box(id~, h=Px(40.0), fn() { c.text("row \{item}", wrap=false) |> ignore }) |> ignore
    }, rows_read=true, sized=rows.sized()) |> ignore
  }, w=300.0, h=160.0)
  t.check_looks(false)
  t.set_rows_on_pixels(true)
  t.draw()
  let at = t.time()
  t.wheel_told(100.0, 100.0, 0.0, 20.0, 0, at + 1.0)
  t.frame_at(at + 16.0)
  t.frame_at(at + 16.0)
  t.wheel_told(100.0, 100.0, 0.0, 5.0, 0, at + 17.0)
  t.frame_at(at + 32.0)
  let new_top = t.row(2).unwrap().1
  // (the targets are found again on such a frame, as on any: kept and moved with the rows is still to come)
  t.tap_once(100.0, new_top + 1.0)
  t.tap_once(100.0, 5.0)
  assert_eq(pressed, [2, 0], msg="hits must use the moved row positions, including the clipped first row")
}
