// A Tester's host keeping no groups of instances (Tester::set_groups(false), as the web's host): a page's list drawn out
// flat in each frame, no header among what it is handed, what it draws the same as where the host keeps groups.

///|
/// A page's list of 60 rows in a box 300 by 200 at 2 pixels a point, its rows on them, the host keeping groups or not;
/// scrolled down by the wheel a turn at a time: each frame's list headers, and where each instance in the box is drawn
/// and cut (x, y, w, h, kind, its clip), each number's bits.
fn groups_kept_frames(groups : Bool) -> Array[(Int, Array[Array[Int64]])] {
  let t = Tester::new(fn(_c) {  }, scale=2.0)
  t.set_rows_on_pixels(true)
  t.set_groups(groups)
  set_view_app(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(Is(Some(200.0))) |> ignore
      o.scrolls_window(@view.Scroll::list(), fn() { Array::makei(60, fn(i) { i }) }, est=30.0, fn(b, k) {
        b.box(fn(l) {
          l.height(Is(Some(if k % 2 == 0 { 31.5 } else { 44.0 }))).ground(Is(0x3366CCFFL)).words(Is("row \{k}")) |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let out = []
  for _ in 0..<12 {
    t.wheel(150.0, 100.0, 53.0)
    t.run_for(move_most_ms)
    let drawn = t
      .drawn_instances()
      .filter(fn(a) { a[1] + a[3] > 0.0 && a[1] < 200.0 && a[0] < 300.0 })
      .map(fn(a) { [a[0], a[1], a[2], a[3], a[5], a[16], a[17], a[18], a[19]].map(fn(v) { v.reinterpret_as_int64() }) })
    out.push((list_heads.length(), drawn))
  }
  out
}

///|
test "a Tester's host keeping no groups: a page's list scrolled drawn out flat, no list header, each instance where a host keeping groups draws it" {
  // (each read whole before the next Tester is made)
  let kept = groups_kept_frames(true)
  let flat = groups_kept_frames(false)
  assert_true(kept.iter().all(fn(f) { f.0 > 0 }), msg="a host keeping groups: the list not drawn by its header")
  assert_true(flat.iter().all(fn(f) { f.0 == 0 }), msg="a host keeping none: a list header handed it")
  for i in 0..<kept.length() {
    assert_true(kept[i].1.length() > 0, msg="nothing drawn at \{i}")
    assert_eq(flat[i].1, kept[i].1)
  }
}
