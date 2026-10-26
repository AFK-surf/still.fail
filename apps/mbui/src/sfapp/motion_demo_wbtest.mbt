// The prototype uses the real app's navigation and composer; these checks guard their behavioural contracts.
///|
test "motion demo: opening the overview does not navigate until a tile is chosen" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat")
  @sfbase.motion_demo.val = true
  t.draw()
  t.run_for(@sf.move_state_ms)
  let before = app.nav.top()
  let log = t.drive("tap 摊开对话\n")
  assert_true(log.contains("EXIT 0"), msg=log.join("\n"))
  t.run_for(@sf.move_state_ms)
  assert_true(app.nav.top() == before)
  t.tap(800.0, 400.0)
  t.run_for(@sf.move_state_ms)
  assert_true(app.nav.top() != before)
  @sfbase.motion_demo.val = false
}
///|
test "motion demo: hovering a file reserves room without changing the draft" {
  let calls : Array[Made] = []
  let (t, src) = desk_composer_tester(calls)
  @sfbase.motion_demo.val = true
  t.draw()
  let w = @sfbase.writing(src, "ws1/st1:s-c1")
  let before = w.files.length()
  let carried : @sfbase.Dragged = { station: "ws1/st1", station_name: "Studio", root: "/", path: "check.md", abs: "/check.md", name: "check.md", size: 200.0, dir: false }
  let old = @sfbase.drag_carried.val
  @sfbase.drag_carried.val = fn() { Some(carried) }
  let (x, y) = t.find("发消息").unwrap()
  t.move(x, y)
  t.draw()
  t.run_for(@sf.shape_ms)
  assert_true(@sfbase.demo_drop_slot.val is Some(_))
  assert_eq(w.files.length(), before)
  @sfbase.drag_carried.val = old
  t.draw()
  assert_true(@sfbase.demo_drop_slot.val is None)
  @sfbase.motion_demo.val = false
}
