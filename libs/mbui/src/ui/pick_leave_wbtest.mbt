// A pick said to leave over a time along a row (view's pick_leave.mbt), as a host draws it: at each moment said, what
// is after it where its place's way has it and which of the two is seen, the same at any frame rate; judged frame to
// frame on the way (words over words: never both seen).

///|
/// How long what the pick showed takes to leave.
let pick_leave_test_ms : Double = 200.0

///|
/// The moments looked at after each change (ms), the last past it all.
let pick_leave_moments : Array[Double] = [20.0, 120.0, 220.0, 320.0, 420.0, 900.0]

///|
/// How opaque the words `w` are drawn, and where what is after it is.
fn pick_leave_seen(t : Tester, w : String) -> Double {
  match t.words().iter().find_first(fn(d) { d.0 == w }) {
    Some(d) => d.5
    None => 0.0
  }
}

///|
test "a pick leaving over a time along a row: its place's way and which is seen at each moment, at any frame rate" {
  let wide = @signals.signal(false)
  let t = Tester::new(fn(_c) {  })
  set_view_app(fn(root) {
    root.box(fn(r) {
      r.row(Is(true)) |> ignore
      r.box(fn(b) { b.width(Is(Some(20.0))).words(Is("左")) |> ignore }) |> ignore
      r.pick(along_row=true, leave=pick_leave_test_ms, fn() { wide.get() }, fn(v, k) {
        v.width(Is(Some(if k { 60.0 } else { 40.0 }))).words(Is(if k { "宽宽" } else { "窄" })) |> ignore
      })
      r.box(fn(b) { b.width(Is(Some(20.0))).words(Is("右")) |> ignore }) |> ignore
    })
    |> ignore
  })
  t.run_for(pick_leave_test_ms)
  let x0 = t.words().iter().find_first(fn(d) { d.0 == "左" }).unwrap().1
  for to_wide in [true, false] {
    let asked = t.time()
    wide.set(to_wide)
    for m in pick_leave_moments {
      t.run_for(asked + m - t.time())
      let narrow = pick_leave_seen(t, "窄")
      let wider = pick_leave_seen(t, "宽宽")
      assert_false(narrow > 0.0 && wider > 0.0, msg="both seen at \{m}: \{narrow}, \{wider}")
      let (way, _) = if to_wide {
        @flex.come_way(40.0, 0.0, 60.0, m)
      } else {
        @flex.come_way(60.0, 0.0, 40.0, m - pick_leave_test_ms)
      }
      let x = t.words().iter().find_first(fn(d) { d.0 == "右" }).unwrap().1
      assert_true((x - (x0 + 20.0 + way)).abs() <= 0.5, msg="右 at \{m}: \{x}, its way \{way}")
    }
    assert_eq(pick_leave_seen(t, if to_wide { "宽宽" } else { "窄" }), 1.0)
  }
}

///|
test "a pick leaving over a time reads the clock through the framework's entry (View::going by drawn_while): what it showed fading out is no read of the time by its binding, wherever it was made" {
  let wide = @signals.signal(false)
  let t = Tester::new(fn(_c) {  })
  set_view_app(fn(root) {
    root.pick(leave=pick_leave_test_ms, fn() { wide.get() }, fn(v, k) {
      v.words(Is(if k { "宽宽" } else { "窄" })) |> ignore
    })
    |> ignore
  })
  t.run_for(pick_leave_test_ms)
  wide.set(true)
  t.run_for(pick_leave_test_ms / 2.0)
  // (on its way out, as faded as it has gone)
  let half = pick_leave_seen(t, "窄")
  assert_true(half > 0.0 && half < 1.0, msg="\{half}")
  t.run_for(2.0 * pick_leave_test_ms)
  assert_eq(pick_leave_seen(t, "窄"), 0.0)
  let reads = @view.clock_reads_in_bindings().filter(fn(r) { r.contains("pick_leave_wbtest.mbt") })
  assert_eq(reads, [])
}
