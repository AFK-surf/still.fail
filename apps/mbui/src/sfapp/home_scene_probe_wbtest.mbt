///|
test "inspect the layers drawn while the home list moves" {
  let t = wide_tester([], mode="long", w=390.0, h=844.0, platform=2)
  t.keep_parts(true)
  t.check_looks(false)
  t.set_frame_period(host_phone_period)
  t.run_as_host(first_page_ms + @ui.move_most_ms)
  t.record_host()
  t.touch_at(0, 195.0, 700.0, t.time())
  t.run_as_host(host_finger_ms)
  @ui.scroll_scene_probe.val = true
  for i in 1..=6 {
    t.touch_at(1, 195.0, 700.0 - 37.5 * i.to_double(), t.time())
    t.run_as_host(host_finger_ms)
  }
  @ui.scroll_scene_probe.val = false
  for f in t.host_frames() {
    println("SCENEPROBE FRAME at=\{f.at} changed=\{f.changed} whole=\{f.whole_why} glass=\{f.glass} layers=\{f.layers_drawn} recorded=\{f.insts_recorded} moved=\{f.insts_moved} alone=\{f.tree_alone} alone_why=\{f.alone_why}")
  }
}
