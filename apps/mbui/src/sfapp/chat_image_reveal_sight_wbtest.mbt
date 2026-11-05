// A pending picture may finish while the reader scrolls away and back, with or without a display frame in between.

///|
fn chat_image_crossed_look(draw_between : Bool) -> (Array[(Double, Double, Double, Double)], Int) raise {
  let asked : Array[String] = []
  let source = "mem:window-test/many-29.png"
  let t = image_window_tester(asked, fixture_file_png("peek.png"), finish=false)
  let pending = t.pending().filter(fn(p) { p.0 == 1 && t.image_src(p.1) == source })
  assert_eq(pending.length(), 1, msg="the last picture is waiting on its decode")
  let image = pending[0].1
  for (kind, id) in t.pending() { if kind == 1 && id != image { t.finish(kind, id) } }
  t.frame_at(t.time())
  let (_, last_before) = @ui.view_tree().unwrap().list_rows().unwrap()
  // The same wheel events and decode occur at the same moments. Only the first run draws the intermediate view.
  t.wheel_told(195.0, 400.0, 0.0, -900.0, 0, t.time())
  if draw_between {
    t.frame_at(t.time())
    let (_, last_after) = @ui.view_tree().unwrap().list_rows().unwrap()
    assert_true(last_after < last_before, msg="the intermediate view has scrolled away from the last picture")
  }
  let decode_after_scroll_ms = 50.0
  t.advance(decode_after_scroll_ms)
  t.finish(1, image)
  t.wheel_told(195.0, 400.0, 0.0, 900.0, 0, t.time())
  t.frame_at(t.time())
  t.frame_at(t.time())
  let places = @ui.view_tree().unwrap().drawn().filter_map(fn(d) {
    if d.image.map_or(false, fn(im) { im.0 == source }) { Some((d.x, d.y, d.w, d.h)) } else { None }
  })
  println("SIGHTREVEAL between=\{draw_between} places=\{places} glass=\{t.drawn_glass()}")
  assert_false(places.is_empty(), msg="the picture is back in the window")
  (places, t.drawn_glass().length())
}

///|
test "a picture finishing during a scroll has the same look with or without an intermediate frame" {
  assert_eq(chat_image_crossed_look(false), chat_image_crossed_look(true))
}
