// 小屏 with keyboard and mouse: Home's top bar takes the pointer where nothing of it is (between the filter and the
// workspace's switcher), as main's: the arrow there, not the I-beam of the list's search field under its glass.

///|
test "小屏 by mouse: the pointer on Home's top bar between its keys is the arrow, not the field's under it" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="long", w=390.0, h=844.0, platform=0)
  t.run_for(@ui.move_most_ms * 2.0)
  let shapes = [72.0, 120.0, 168.0].map(fn(x) { "\{t.probe_at(x, 24.0).split("\n").next().unwrap()}" })
  assert_eq(shapes, ["target=none cursor=Arrow", "target=none cursor=Arrow", "target=none cursor=Arrow"])
}
