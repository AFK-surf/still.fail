// A message picture's menu is an event: its copy continues when the host finishes decoding, without a new frame.

///|
test "copying a message picture waits for its decode without waiting for a frame" {
  new_run()
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0, finish=false)
  t.run_for(@ui.move_most_ms)
  t.finish_all()
  t.frames_owed()
  let mut at : (Double, Double)? = None
  for _ in 0..<12 {
    match t.drawn_images().iter().find_first(fn(i) { i[0] > 400.0 && i[2] > 100.0 && i[1] > 80.0 && i[1] + i[3] / 2.0 < 700.0 }) {
      Some(i) => { at = Some((i[0] + i[2] / 2.0, i[1] + dmin(i[3], 200.0) / 2.0)); break }
      None => { t.wheel(900.0, 400.0, -200.0); t.finish_all(); t.frames_owed() }
    }
  }
  let (x, y) = at.unwrap_or_else(fn() { fail("no picture in view") })
  t.right_click(x, y)
  t.run_for(@kit.presence_in_ms)
  let key = @sfpages.offered_image()
  assert_true(key != "", msg="the picture's menu is open")
  t.add_pixels(key, 2, 2, FixedArray::make(16, b'\xff'))
  let (bx, by) = match t.find("复制图片") {
    Some(point) => point
    None => fail("the copy option is visible")
  }
  t.touch_at(0, bx, by, t.time())
  t.touch_at(2, bx, by, t.time())
  let pending = t.pending().filter(fn(p) { p.0 == 1 && t.image_src(p.1) == key })
  assert_eq(pending.length(), 1, msg="the copy asks for the picture in the event, before a frame")
  assert_true(t.clipboard_png() is None)
  t.finish(1, pending[0].1)
  match t.clipboard_png() {
    Some(png) => assert_true(@pixels.is_png(png))
    None => fail("the decode's answer copies the picture before another frame")
  }
}
