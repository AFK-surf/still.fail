// A message's video as nodes (message_video_node.mbt): its box its data's, its still from its station on black, its
// capsule saying how long it is; right clicked or held, its menu with 加载, then 停止加载 while the core brings it.

///|
/// The video of these tests: 1280 × 720, 42 s long, its station's still video/still.png.
fn video_one() -> Attachment {
  attachment_of({
    "name": "clip.mp4",
    "path": "/w/uploads/clip.mp4",
    "size": 4200000.0,
    "owner": "ag",
    "width": 1280.0,
    "height": 720.0,
    "duration": 42000.0,
  })
}

///|
/// How long after it is asked its still is decoded (on no frame rate's frames), and a moment past it.
let video_test_decode : Double = 137.0

///|
let video_test_hair : Double = 1.0

///|
/// Its box: 360 × 203 (image_box's at video_least).
fn video_box() -> (Double, Double) {
  let (bw, bh, _) = image_box(video_one(), video_least)
  (bw, bh)
}

///|
/// The video in a column 390 wide, the core saying what it brings once let go in `keeping`; what is presented drawn.
fn video_tester(keeping : Array[Json], platform? : Int = 0) -> @ui.Tester {
  let src : Source = { ..files_src(keeping~), poster: fn(_, _, _) { "video/still.png" } }
  // (shown once its still is said to decode a while after it is asked)
  let list : @signals.Signal[Array[Attachment]] = @signals.signal([])
  let t = @ui.Tester::new(
    fn(c) {
      @sf.begin(c) |> ignore
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
      message_files_node(col, src, tips, files_place(), fn() { list.get() }, fn() { false }, fn() { None }, "")
      @sf.presented_nodes(root)
    },
    w=430.0,
    h=400.0,
    platform~,
    images=[("video/still.png", 1280, 720)],
  )
  t.decode_after("video/still.png", video_test_decode)
  list.set([video_one()])
  t.run_for(video_test_decode + video_test_hair)
  t
}

///|
test "a message's video: its still on black in its box, its capsule saying how long it is in its foot's start corner" {
  let t = video_tester([])
  t.run_for(@ui.move_most_ms)
  let (bw, bh) = video_box()
  let pic = t.drawn_images()
  assert_eq(pic.length(), 1, msg="\{Repr(pic)}")
  assert_true((pic[0][2] - bw).abs() < 0.01 && (pic[0][3] - bh).abs() < 0.01, msg="\{Repr(pic[0])}")
  let (lx, ly, _, lh) = t.rect_of(@sf.clock(42000.0)).unwrap()
  // (in its foot's start corner: in its left half, in its lower half)
  assert_true(lx < bw / 2.0 && ly + lh <= bh && ly > bh / 2.0, msg="\{lx},\{ly}")
  assert_true(t.query(Button, label=@sf.t("web-main.file.play", args=[("name", "clip.mp4")])) is Some(_))
  assert_eq(t.audit(), [])
}

///|
test "a message's video right clicked or held: 加载 where nothing brings it, 停止加载 while the core brings it" {
  let cases : Array[Array[Json]] = [[], [{ "id": "k1", "station": "st", "key": "ag", "name": "clip.mp4", "progress": 0.3 }]]
  for keeping in cases {
    for platform in [0, 2] {
      @sf.presenters_reset()
      let t = video_tester(keeping, platform~)
      let (bw, bh) = video_box()
      let (x, y) = (bw / 2.0, bh / 3.0)
      if platform == 0 {
        t.right_click(x, y)
      } else {
        t.press_at(x, y)
        t.run_for(@ui.long_press_ms)
        t.release(x, y)
      }
      t.run_for(@ui.move_most_ms)
      // (each item by its name whole, as a screen reader finds it, a Button or a MenuItem: in Chinese 加载 is part of
      // 停止加载's words, and the words are whichever a test before this one in its process told, sf's words_of kept
      // across runs)
      let item = fn(key) {
        let name = @sf.t(key)
        t.semantics().iter().any(fn(s) { s.label == name && (s.role == Button || s.role == MenuItem) })
      }
      let brought = keeping.length() > 0
      assert_eq((item("web-main.file.load"), item("web-main.file.stopLoading")), (!brought, brought), msg="\{platform} \{brought}")
      assert_true(item("web-main.preview.download"), msg="\{platform}")
      @sf.close_presented_of(@sf.last_presented())
      t.run_for(@ui.move_most_ms)
      assert_true(!@sf.presented_drawn(), msg="\{platform}")
    }
  }
}

///|
test "a message's video as the pointer rests on it: its name in no tip while what it shows shows whole, as video_item's" {
  let t = video_tester([])
  let (bw, bh) = video_box()
  t.move_to(bw / 2.0, bh / 3.0)
  t.run_for(@sf.tip_delay_ms + @ui.move_most_ms)
  let tips = t.semantics().filter(fn(s) { s.role == Tooltip }).map(fn(s) { s.label })
  assert_eq(tips, [])
  assert_eq(t.audit(), [])
}
