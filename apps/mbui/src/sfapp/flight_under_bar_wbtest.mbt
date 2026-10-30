// A picture under a chat's bar opened (the user, 2026-10-30: 「它在挪出来前就盖在了顶栏上面」, a recording of its first
// frame over the bar): the bar over it every frame till it is out from under it, the first the flight is drawn in too.
// A picture seen before asks the core nothing as it opens, so the frame it sets out in is built once: built before it
// set out, the pages had built that frame as if it had not, the bar under the picture (sfbase viewer_set_out).

///|
/// What is drawn last at (`x`, `y`) in the frame just drawn: its kind (4 a picture), -1 nothing.
fn last_kind_at(t : @ui.Tester, x : Double, y : Double) -> Int {
  let mut kind = -1
  for i in t.drawn_order() {
    if i.5 > 0.5 && x >= i.1 && x <= i.1 + i.3 && y >= i.2 && y <= i.2 + i.4 {
      kind = i.0
    }
  }
  kind
}

///|
/// The chat's compare.png in a window `w` wide (`platform`'s), seen once, wheeled till its top is `top` (under the
/// chat's bar), pressed and let go a little over its foot: what went wrong in the frames while it went out from under
/// the bar (none, as it should be).
fn picture_under_bar_faults(top : Double, platform : Int, w : Double) -> Array[String] {
  let (t, x, y) = image_in_chat("compare.png", platform~, w~)
  // opened once and closed: its whole read and kept, as a picture seen before is (the frame it sets out in again asks
  // the core nothing, built once)
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  t.back()
  t.run_for(@ui.move_most_ms)
  let i = t.drawn_images().filter(fn(i) { i[8] > 0.5 && x >= i[0] && x <= i[0] + i[2] && y >= i[1] && y <= i[1] + i[3] })
  assert_true(i.length() > 0) catch { _ => () }
  let (was, h) = (i[0][1], i[0][3])
  t.wheel(x, y, was - top)
  t.run_for(@ui.scrollbar_hold_ms + @ui.scrollbar_fade_ms)
  // (each frame built as a host builds it: not built once more to check its rows kept, which would draw a second
  // build of the frame)
  t.check_looks(false)
  t.drawn_again(true)
  let faults : Array[String] = []
  let frame = Ref(0)
  let set_out = Ref(false)
  t.each_frame(
    Some(fn() {
      match viewer.val {
        Some(v) if v.flies => {
          set_out.val = true
          match thumb_of(t.ctx(), v.id()) {
            Some({ clear: Some((bar, _)), .. }) if v.flying() <= 0.0 && last_kind_at(t, x, bar / 2.0) == 4 =>
              faults.push("frame \{frame.val}: the picture over the bar (gone out \{v.lifted()})")
            _ => ()
          }
        }
        _ => ()
      }
      frame.val += 1
    }),
  )
  // (the press and its release, each in a frame of its own, as a host has them)
  t.press_at(x, top + h - h / 8.0)
  t.release(x, top + h - h / 8.0)
  t.run_for(@ui.move_most_ms)
  t.each_frame(None)
  t.check_looks(true)
  t.drawn_again(false)
  assert_true(set_out.val) catch { _ => () }
  faults
}

///|
test "a picture under a chat's bar: the bar over it every frame till it is out from under it" {
  // a wide window with a mouse, and a phone's; its top a little under the bar's, and half of it over the window's top
  for screen in [(0, 1280.0), (2, 390.0)] {
    for top in [10.0, -100.0] {
      let faults = picture_under_bar_faults(top, screen.0, screen.1)
      assert_true(faults.is_empty(), msg="\{screen.1} wide, its top at \{top}: \{faults}")
    }
  }
}
