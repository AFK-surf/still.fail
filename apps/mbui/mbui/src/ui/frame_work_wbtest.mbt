///|
test "the host frame record includes work in the retained tree before the old frame" {
  let t = Tester::new(fn(_) { })
  t.measure_as_host()
  let elapsed = Ref(0.0)
  let clock_before = work_clock.val
  set_work_clock(Some(fn() { elapsed.val }))
  defer { set_work_clock(clock_before) }
  set_view_app(fn(root) {
    root.box(fn(v) {
      v.measured(Is(40.0), fn(h, w) {
        // Deterministic charged work, independent of the test's logical time.
        elapsed.val += 7.0
        (w.unwrap_or(100.0), h)
      }) |> ignore
    }) |> ignore
  })
  t.set_perf(0)
  @hostapi.set_perf(true)
  defer { @hostapi.set_perf(false) }
  t.draw()
  assert_true(elapsed.val > 0.0, msg="the retained tree must have been measured")
  assert_eq(probe_work.val, elapsed.val, msg="no work before the old frame may disappear from the host's record")
}
