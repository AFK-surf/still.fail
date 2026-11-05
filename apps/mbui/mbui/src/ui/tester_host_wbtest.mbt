///|
test "host frame records keep a test callback's input work between frames" {
  let height = @signals.signal(40.0)
  let t = Tester::new(fn(_) { }, w=300.0, h=300.0)
  set_view_app(fn(root) {
    root.box(fn(v) {
      v.width(Is(Some(100.0))).height(By(fn() { Some(height.get()) })).ground(Is(0x336699FFL)) |> ignore
    }) |> ignore
  })
  t.draw()
  t.measure_as_host()
  let tree = view_tree().unwrap()
  t.record_host()
  t.each_frame(Some(fn() {
    height.set(80.0)
    tree.bring_to(t.time())
  }))
  t.frame_at(t.time() + 20.0)
  let first = t.host_frames()[0]
  assert_eq(first.computes, 0)
  assert_false(first.layout_pending)
  t.each_frame(None)
  t.frame_at(t.time() + 20.0)
  let next = t.host_frames()[0]
  assert_eq(next.computes, 0)
  assert_eq(next.between.iter().find_first(fn(c) { c.0 == "computes" }), Some(("computes", 1)))
  assert_false(next.layout_pending)
}
