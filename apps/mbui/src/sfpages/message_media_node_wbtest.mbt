// A message's picture as nodes (message_media_node.mbt): its box its data's before it is here; what stands in for it
// breathing while it is asked, whole once it is here, brushed in from the moment it is decoded; how far it has come
// from 300 ms after it was first said to be on its way; one that cannot be had, and one its station could not be
// reached for, asked again when pressed; its menu.

///|
/// A moment past another, to look on either side of it.
let media_test_hair : Double = 20.0

///|
/// The picture of these tests: 800 × 600, its box 360 × 270 (image_box's).
fn media_one() -> Attachment {
  files_one("pic.png", width=800.0, height=600.0)
}

///|
let media_test_w : Double = 360.0

///|
let media_test_h : Double = 270.0

///|
/// A message with the picture in a column 390 wide, its picture asked of its station through `images` (each asking
/// kept in `asks`, answered when the test says), `calls` what the core is asked.
fn media_tester(
  images : @sfbase.ChatImages,
  asks : Array[((Json) -> Unit, (Result[(Json, Bytes?), Json]) -> Unit)],
  platform? : Int = 0,
) -> @ui.Tester {
  let src : Source = {
    ..files_src(),
    file: fn(station, key, name) {
      images.get(station, @sfbase.file_image_id(station, key, name), "mem:media/" + name, fn(heard, done) {
        asks.push((heard, done))
      })
    },
    images,
  }
  let t = @ui.Tester::new(
    fn(c) {
      @sf.begin(c) |> ignore
      // (and what is presented: its menu)
      c.with_theme(@sf.ui_theme(), fn() {
        @ui.old_views_here(c)
        @sf.presented(c)
      })
    },
    tree=fn(root) {
      @ui.set_tree_theme(@sf.ui_theme_now)
      let col = root.box(fn(v) { v.width(Is(Some(390.0))) |> ignore })
      let popup = root.box(fn(v) { v.over(Is(true)) |> ignore })
      let tips = @sf.TipLayer::new(fn() { Some(popup) })
      message_files_node(col, src, tips, files_place(), fn() { [media_one()] }, fn() { false }, fn() { None }, "")
      @sf.presented_nodes(root)
    },
    w=430.0,
    h=400.0,
    platform~,
    images=[("mem:media/pic.png", 800, 600)],
  )
  t.draw()
  t
}

///|
/// The picture's bytes as its station sends them.
fn media_bytes() -> Bytes {
  Bytes::from_array([0x89, 0x50, 0x4E, 0x47].map(fn(i) { i.to_byte() }))
}

///|
/// The picture drawn at its own size (scale 1, its box's): its drawn width, 0 none.
fn media_drawn_w(t : @ui.Tester) -> Double {
  t.drawn_images().fold(init=0.0, fn(m, i) { if i[2] > m { i[2] } else { m } })
}

///|
fn media_clock_read() -> Bool {
  @ui.view_tree().unwrap().cycle_read()
}

///|
test "a message's picture: its box its data's while it is asked, all of it breathing; here, brushed in from the moment it is decoded, whole, the clock no longer read" {
  let images = @sfbase.ChatImages::new()
  let asks = []
  let t = media_tester(images, asks)
  assert_eq(asks.length(), 1)
  // (its box as its data says it, the neutral ground in it, breathing)
  assert_true(t.drawn_rects().iter().any(fn(r) { r.2 == media_test_w && r.3 == media_test_h }), msg="\{Repr(t.drawn_rects())}")
  assert_eq(media_drawn_w(t), 0.0)
  assert_true(media_clock_read(), msg="breathing")
  // (here: brushed in from that moment, over reveal_ms)
  (asks[0].1)(Ok((Json::object({}), Some(media_bytes()))))
  t.run_for(@sf.reveal_ms / 2.0)
  assert_true(media_drawn_w(t) > media_test_w, msg="on its way in: \{media_drawn_w(t)}")
  t.run_for(@sf.reveal_ms)
  assert_true((media_drawn_w(t) - media_test_w).abs() < 0.01, msg="\{media_drawn_w(t)}")
  assert_true(!media_clock_read(), msg="whole: nothing of the clock read")
  assert_eq(t.idle_said(), None)
  assert_eq(t.audit(), [])
}

///|
test "how far a picture asked has come: nothing till 300 ms after it was first said to be on its way, then its share in words, faded in over 200" {
  let images = @sfbase.ChatImages::new()
  let asks = []
  let t = media_tester(images, asks)
  let asked = t.time()
  (asks[0].0)({ "loaded": 35.0, "total": 100.0 })
  t.run_for(asked + coming_after_ms - media_test_hair - t.time())
  assert_true(t.find("35%") is None, msg="before 300 ms")
  t.run_for(asked + coming_after_ms + coming_in_ms + media_test_hair - t.time())
  assert_true(t.find("35%") is Some(_), msg="after")
  // (here: no more of it)
  (asks[0].1)(Ok((Json::object({}), Some(media_bytes()))))
  t.run_for(@sf.reveal_ms + media_test_hair)
  assert_true(t.find("35%") is None)
  assert_eq(t.audit(), [])
}

///|
test "a picture its station could not be reached for says so and is asked again when pressed; one its station has none of says that" {
  let images = @sfbase.ChatImages::new()
  let asks = []
  let t = media_tester(images, asks)
  (asks[0].1)(Err({ "code": "mesh", "message": "unreachable" }))
  t.run_for(@ui.move_most_ms)
  let again = @sf.t("web-main.file.loadAgain")
  let (x, y, _, _) = t.rect_of(again).unwrap()
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  assert_eq(asks.length(), 2)
  (asks[1].1)(Ok((Json::object({}), None)))
  t.run_for(@ui.move_most_ms)
  assert_true(t.find(@sf.t("web-main.file.noPreview")) is Some(_))
  assert_true(t.find(again) is None)
  assert_eq(t.audit(), [])
}

///|
test "a picture right clicked: its menu where, 下载 and 复制图片 once it is here; held by a finger, the same, the picture lifted while it is up" {
  for platform in [0, 2] {
    @sf.presenters_reset()
    let images = @sfbase.ChatImages::new()
    let asks = []
    let t = media_tester(images, asks, platform~)
    (asks[0].1)(Ok((Json::object({}), Some(media_bytes()))))
    t.run_for(@sf.reveal_ms + media_test_hair)
    let (x, y) = (media_test_w / 2.0, media_test_h / 2.0)
    if platform == 0 {
      t.right_click(x, y)
    } else {
      t.press_at(x, y)
      t.run_for(@ui.long_press_ms)
      t.release(x, y)
    }
    t.run_for(@ui.move_most_ms)
    assert_true(@sf.presented_drawn(), msg="\{platform}")
    assert_true(t.find(@sf.t("web-main.preview.download")) is Some(_), msg="\{platform}")
    assert_true(t.find(@sf.t("desktop.contextMenu.copyImage")) is Some(_), msg="\{platform}")
    // (lifted by a finger's hold alone)
    let lifted = media_drawn_w(t) > media_test_w + 1.0
    assert_eq(lifted, platform == 2, msg="\{platform}: \{media_drawn_w(t)}")
    @sf.close_presented_of(@sf.last_presented())
    t.run_for(@ui.move_most_ms)
    assert_true(!@sf.presented_drawn(), msg="\{platform}")
    // (down from the moment the menu was gone, on lift_spring, all the way down from all the way up)
    t.run_for(@motion.lift_spring.duration(1.0, 0.0, 0.0))
    assert_true((media_drawn_w(t) - media_test_w).abs() < 0.01, msg="\{platform}: \{media_drawn_w(t)}")
  }
}
