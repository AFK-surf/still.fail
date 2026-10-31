// A video taken down fast by a finger on Android: its events as a host hands them on, a few ms apart, each followed by
// the display's frame; let go past the line, it goes.

///|
/// When each of the finger's events comes after it went down (ms), and how long after each the display's frame is.
let fast_down_ms : Array[Double] = [0.0, 20.0, 40.0, 60.0, 80.0]

///|
let frame_after_ms : Double = 4.0

///|
test "a video taken down fast (its finger's events 20 ms apart) and let go past the line closes" {
  new_run()
  let src : Source = { ..fixture("chat"), poster: fn(_, _, name) { fixture_file(name) } }
  let a : Attachment = {
    name: "演示录屏.mp4",
    path: "uploads/fx/演示录屏.mp4",
    size: 5242880.0,
    width: 1280.0,
    height: 720.0,
    thumbhash: "",
    owner: "s-c1",
    upload: "",
    duration: 0.0,
    frames: 0,
    held: false,
  }
  let t = @ui.Tester::new(
    fn(c) {
      chat_file(c, src, a)
      preview(c, src)
    },
    w=390.0,
    h=844.0,
    platform=2,
  )
  t.draw()
  t.run_for(@ui.image_fade_ms)
  t.tap_text("演示录屏.mp4")
  t.run_for(@ui.move_most_ms)
  t.set_player(1, position=4000.0)
  t.draw()
  assert_eq(t.holes().length(), 1)
  let t0 = t.time() + frame_after_ms
  let ys = [300.0, 380.0, 460.0, 500.0, 500.0]
  for i, ms in fast_down_ms {
    t.advance(t0 + ms - t.time())
    t.touch(if i == 0 { 0 } else if i == ys.length() - 1 { 2 } else { 1 }, 195.0, ys[i])
    t.frame_at(t0 + ms + frame_after_ms)
  }
  assert_true(viewer.get() is None && pv_leaving.get() is Some(_), msg="viewer \{viewer.get().map(fn(v) { v.closing })}")
}

///|
test "the app's video (its window's tree, the old views in it) taken down fast: its picture with the finger from its first move, gone as let go past the line" {
  new_run()
  let src = fixture("chat-preview-video")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  t.draw()
  t.run_for(@ui.move_most_ms)
  t.set_player(1, position=4000.0)
  t.draw()
  let (_, y, _, _) = t.holes()[0]
  let t0 = t.time() + frame_after_ms
  let ys = [300.0, 380.0, 460.0, 500.0, 500.0]
  for i, ms in fast_down_ms {
    t.advance(t0 + ms - t.time())
    t.touch(if i == 0 { 0 } else if i == ys.length() - 1 { 2 } else { 1 }, 195.0, ys[i])
    t.frame_at(t0 + ms + frame_after_ms)
    // (the first move's frame: the picture down with the finger already)
    if i == 1 {
      let down = t.holes()[0].1
      assert_true(down > y + 60.0, msg="\{down} from \{y}")
    }
  }
  assert_true(viewer.get() is None && pv_leaving.get() is Some(_), msg="viewer \{viewer.get().map(fn(v) { v.closing })}")
}
