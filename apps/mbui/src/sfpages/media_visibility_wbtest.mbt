// A picture that was decoded while its row was outside the window is already there when the row comes into view.

///|
test "a list picture decoded at the moment it is first shown is already there" {
  let p : MediaPicture = { kind: "image", key: "first-picture", hash: "", sent: false, held: false, unreached: false }
  let t = @ui.Tester::new(fn(_) {  }, w=400.0, h=400.0, images=[("first-picture", 600, 400)], finish=false)
  @ui.set_view_app(fn(root) {
    root.lends(chat_picture_in_sight, fn() { true }) |> ignore
    media_content_node(root, fn() { p }, fn() { 300.0 }, fn() { 200.0 }, FitCover, fn() { 8.0 })
  })
  t.draw()
  let pending = t.pending().filter(fn(item) { item.0 == 1 })
  assert_eq(pending.length(), 1, msg="the picture has been asked for")
  let at = t.time()
  t.finish(1, pending[0].1)
  t.frame_at(at)
  assert_eq(@ui.image_state("first-picture"), 1)
  assert_eq(t.drawn_glass().length(), 0, msg="the first sight is not revealed again")
}

///|
test "a list picture decoded later while in sight is revealed" {
  let p : MediaPicture = { kind: "image", key: "later-picture", hash: "", sent: false, held: false, unreached: false }
  let t = @ui.Tester::new(fn(_) {  }, w=400.0, h=400.0, images=[("later-picture", 600, 400)], finish=false)
  @ui.set_view_app(fn(root) {
    root.lends(chat_picture_in_sight, fn() { true }) |> ignore
    media_content_node(root, fn() { p }, fn() { 300.0 }, fn() { 200.0 }, FitCover, fn() { 8.0 })
  })
  t.draw()
  let pending = t.pending().filter(fn(item) { item.0 == 1 })
  assert_eq(pending.length(), 1)
  t.advance(@ui.first_frame_ms)
  t.finish(1, pending[0].1)
  t.frame_at(t.time())
  assert_eq(@ui.image_state("later-picture"), 1)
  assert_eq(t.drawn_glass().length(), 1, msg="the waited-for picture begins its reveal")
}

///|
test "a picture decoded before its row enters the window does not reveal again" {
  let top = @signals.signal(480.0)
  let p : MediaPicture = { kind: "image", key: "outside-picture", hash: "", sent: false, held: false, unreached: false }
  let t = @ui.Tester::new(fn(_) {  }, w=400.0, h=400.0, images=[("outside-picture", 600, 400)])
  @ui.set_view_app(fn(root) {
    root.lends(chat_picture_in_sight, fn() { top.get() < 400.0 }) |> ignore
    root.box(fn(space) { space.height(By(fn() { Some(top.get()) })) |> ignore }) |> ignore
    media_content_node(root, fn() { p }, fn() { 300.0 }, fn() { 200.0 }, FitCover, fn() { 8.0 })
  })
  t.draw()
  @ui.current().image_want("outside-picture", 600.0)
  t.frame()
  t.frame()
  assert_eq(@ui.image_state("outside-picture"), 1, msg="decoded while its row is outside")
  top.set(10.0)
  t.draw()
  t.frame()
  assert_true(t.drawn_images().length() > 0, msg="the picture is visible")
  assert_eq(t.drawn_glass().length(), 0, msg="an already decoded picture enters without a reveal")
}

///|
/// Whether a picture is frosted on return after a brief visit above its pending decode. `draw_between` changes only
/// whether a frame happened to be drawn while the row visited the window.
fn media_crossed_reveals(draw_between : Bool) -> Bool {
  let top = @signals.signal(480.0)
  let p : MediaPicture = { kind: "image", key: "crossed-picture", hash: "", sent: false, held: false, unreached: false }
  let t = @ui.Tester::new(fn(_) {  }, w=400.0, h=400.0, images=[("crossed-picture", 600, 400)], finish=false)
  @ui.set_view_app(fn(root) {
    root.lends(chat_picture_in_sight, fn() { top.get() < 400.0 }) |> ignore
    root.box(fn(space) { space.height(By(fn() { Some(top.get()) })) |> ignore }) |> ignore
    media_content_node(root, fn() { p }, fn() { 300.0 }, fn() { 200.0 }, FitCover, fn() { 8.0 })
  })
  t.draw()
  @ui.current().image_want("crossed-picture", 600.0)
  top.set(10.0)
  if draw_between { t.draw() }
  top.set(480.0)
  t.draw()
  t.finish_all()
  t.frame()
  top.set(10.0)
  t.draw()
  t.frame()
  t.drawn_glass().length() > 0
}

///|
test "a picture decoded after a row crosses the window has the same look with or without an intermediate frame" {
  assert_eq(media_crossed_reveals(false), media_crossed_reveals(true))
}
