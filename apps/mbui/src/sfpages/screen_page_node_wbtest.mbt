///|
test "retained screen frame opens once and keeps video acknowledgements and direct input" {
  let r = screen_rig(retained=true, touch="direct")
  assert_eq(r.told("screen.view").length(), 1)
  assert_true(r.t.awake())
  r.live()
  assert_true(r.acked(1000.0))
  r.tap_at(0.25, 0.75)
  assert_eq(r.inputs().length(), 2)
  assert_true(r.ui().box_w > 0.0 && r.ui().box_h > 0.0)
  screen_done(r.t)
}

///|
test "retained screen frame enters full screen and restores the upright controls" {
  let r = screen_rig(retained=true)
  r.live(others=[])
  open_center(r)
  r.t.tap_text("全屏")
  r.t.run_for(@kit.presence_out_ms + @sf.later_ms)
  r.t.resize(844.0, 390.0)
  r.t.draw()
  assert_true(r.ui().full.get())
  assert_eq((r.ui().box_w, r.ui().box_h), (844.0, 390.0))
  r.tap_label("工具")
  r.tap_label("退出全屏")
  r.t.resize(390.0, 844.0)
  r.t.draw()
  assert_false(r.ui().full.get())
  assert_true(r.labelled("控制中心") is Some(_))
  screen_done(r.t)
}
