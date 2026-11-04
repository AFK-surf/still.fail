// A file's picture as nodes (media_content_node): one coming in comes in from its own decode, another put in its place
// after it is in as well.

///|
test "a file's picture as nodes: one in, another not decoded yet in its place waits, and comes in from its own decode" {
  @sf.set_dark(Some(false))
  let key = @signals.signal("a")
  let picture = fn() -> MediaPicture { { kind: "image", key: key.get(), hash: "", sent: false, held: false, unreached: false } }
  let t = @ui.Tester::new(fn(_c) {  }, w=400.0, h=400.0, images=[("a", 600, 400), ("b", 600, 400)])
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    media_content_node(root, picture, fn() { 300.0 }, fn() { 200.0 }, FitCover, fn() { 8.0 })
  })
  t.draw()
  t.frame()
  t.frame()
  // (a: decoded, coming in under its frost; then in, nothing over it)
  assert_eq(t.drawn_glass().length(), 1, msg="a comes in frosted")
  t.run_for(reveal_ms + 1.0)
  assert_eq(t.drawn_glass().length(), 0, msg="a is in")
  // (b in its place: waited on till it is decoded, then in from that moment, as a was)
  key.set("b")
  t.frame()
  t.frame()
  assert_eq(t.drawn_glass().length(), 1, msg="b comes in from its own decode, not as in as a was")
  t.run_for(reveal_ms + 1.0)
  assert_eq(t.drawn_glass().length(), 0, msg="b is in")
}

///|
test "a retained picture keeps its identity while its flight changes crop, width and corner" {
  let mode = @signals.signal(0)
  let wide = @signals.signal(240.0)
  let fit = fn() -> @ui.Fit {
    match mode.get() { 0 => FitContain; 1 => FitCoverAt(0.5); 2 => FitCoverAt(0.0); _ => FitCover }
  }
  let p : MediaPicture = { kind: "image", key: "portrait", hash: "", sent: true, held: true, unreached: false }
  let t = @ui.Tester::new(fn(_) {  }, w=400.0, h=300.0, images=[("portrait", 200, 400)])
  @ui.set_view_app(fn(root) {
    media_fitted_node(root, fn() { p }, fn() { wide.get() }, fn() { 120.0 }, fit, fn() { wide.get() / 20.0 })
  })
  t.draw()
  let tree = @ui.view_tree().unwrap()
  let image = fn() { tree.drawn().iter().find_first(fn(d) { d.image is Some(_) }).unwrap() }
  let id = image().id
  assert_eq(image().image_in, Some(((90.0, 0.0, 60.0, 120.0), 0L)))
  mode.set(1)
  t.draw()
  assert_eq(image().id, id)
  assert_eq(image().image_in, Some(((0.0, -180.0, 240.0, 480.0), 0L)))
  mode.set(2)
  wide.set(180.0)
  t.draw()
  assert_eq(image().id, id)
  assert_eq(image().image_in, Some(((0.0, 0.0, 180.0, 360.0), 0L)))
  assert_eq(image().radius, 9.0)
  assert_eq(t.drawn_images().length(), 1)
  mode.set(3)
  t.draw()
  assert_eq(image().id, id)
  assert_true(image().image_cover)
  assert_eq(image().image_in, None)
}
