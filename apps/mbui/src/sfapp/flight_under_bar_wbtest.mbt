// A picture under a chat's bar opened (the user, 2026-10-30: 「它在挪出来前就盖在了顶栏上面」, a recording of its first
// frame over the bar): the bar over it every frame till it is out from under it, the first the flight is drawn in too.
// A picture seen before asks the core nothing as it opens, so the frame it sets out in is built once: built before it
// set out, the pages had built that frame as if it had not, the bar under the picture (set out as its node is made: sfbase
// viewer_tree.mbt's image_layer).
// A film the same, opening and closing (the user, 2026-11-09: 「这个避让怎么又他妈坏了？没有测试？」, a recording of a
// video flying over the phone's chat bar both ways): since the bar on 小屏 became the page's nodes (#4863) only a
// picture's flight was drawn in the page's slot under it, a film's in the viewer's layer over everything.

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
/// The chat's 演示录屏.mp4 (a long reply after it: MBUI_FIXTURE=chat-download-on) in a window `w` wide (`platform`'s), a
/// row up at a time from the chat's end until it is drawn; where it is.
fn film_in_chat(platform? : Int = 2, w? : Double = 390.0) -> (@ui.Tester, Double, Double) {
  new_run()
  let src = fixture("chat-download-on")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h=844.0, platform~)
  nav_rested(t)
  files_page_over(t, w, 844.0)
  let mut tries = 0
  while t.reachable("演示录屏.mp4").length() == 0 && tries < 12 {
    let (first, _) = t.visible()
    t.scroll_to(if first > 0 { first - 1 } else { 0 })
    t.draw()
    tries += 1
  }
  t.run_for(@ui.image_fade_ms)
  let at = t.reachable("演示录屏.mp4")
  assert_true(at.length() > 0) catch { _ => () }
  let (x, y) = at[0]
  (t, x, y)
}

///|
/// A film closed: the frame its player shows, asked for to go back with (Viewer::leaving_grab), answered with its
/// recording's frame, as a host answers it.
fn film_frame_answered(t : @ui.Tester) -> Unit {
  let asked = t.views().filter(fn(l) { l.has_prefix("control ") })
  guard asked.last() is Some(l) else { return }
  let view = l.split(" ").to_array()[1].to_owned()
  let frame = fixture_file_png("演示录屏.mp4")
  t.view_said("{\"still\":{\"view\":\{view}},\"b\":\"\{hex_bytes(frame)}\"}") |> ignore
  t.draw()
}

///|
/// The chat's compare.png (`film`: its recording, 演示录屏.mp4) in a window `w` wide (`platform`'s), seen once, wheeled
/// till its top is `top` (under the chat's bar), pressed and let go a little over its foot: what went wrong in the
/// frames while it went out from under the bar, and back in under it as it is closed (none, as it should be).
fn picture_under_bar_faults(top : Double, platform : Int, w : Double, film? : Bool = false) -> Array[String] {
  let (t, x, y) = if film { film_in_chat(platform~, w~) } else { image_in_chat("compare.png", platform~, w~) }
  // opened once and closed: its whole read and kept, as a picture seen before is (the frame it sets out in again asks
  // the core nothing, built once)
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  t.back()
  if film {
    film_frame_answered(t)
  }
  t.run_for(@ui.move_most_ms)
  let i = t.drawn_images().filter(fn(i) { i[8] > 0.5 && x >= i[0] && x <= i[0] + i[2] && y >= i[1] && y <= i[1] + i[3] })
  assert_true(i.length() > 0) catch { _ => () }
  let (left, was, w0, h) = (i[0][0], i[0][1], i[0][2], i[0][3])
  t.wheel(x, y, was - top)
  t.run_for(@ui.scrollbar_hold_ms + @ui.scrollbar_fade_ms)
  let moved = t.drawn_images().filter(fn(i) { i[8] > 0.5 && (i[0] - left).abs() < 1.0 && (i[2] - w0).abs() < 1.0 })
  assert_true(moved.length() > 0) catch { _ => () }
  let y0 = moved[0][1]
  // (each frame built as a host builds it: not built once more to check its rows kept, which would draw a second
  // build of the frame)
  t.check_looks(false)
  t.drawn_again(true)
  let faults : Array[String] = []
  let frame = Ref(0)
  let set_out = Ref(false)
  t.each_frame(
    Some(fn() {
      let v = match viewer.get() {
        Some(v) => Some(v)
        None => pv_leaving.get()
      }
      match v {
        Some(v) if v.flies => {
          set_out.val = true
          let l = v.lifted_at(t.time())
          match thumb_of(t.ctx(), v.thumb_id()) {
            Some({ clear: Some((bar, _)), .. } as th) if l < 1.0 => {
              if last_kind_at(t, x, bar / 2.0) == 4 {
                faults.push("frame \{frame.val}: the picture over the bar (gone out \{l})")
              }
              let y_at = y0 + l * @sfbase.lift_of(th)
              if !t
                .drawn_images()
                .iter()
                .any(fn(i) {
                  i[8] > 0.5 && (i[0] - left).abs() < 1.0 && (i[1] - y_at).abs() < 1.0 && (i[2] - w0).abs() < 1.0
                }) {
                faults.push("frame \{frame.val}: the picture off its place (expected (\{left}, \{y_at}))")
              }
            }
            _ => ()
          }
        }
        _ => ()
      }
      frame.val += 1
    }),
  )
  // (the press and its release, each in a frame of its own, as a host has them; then a frame at a time while it goes)
  t.press_at(x, top + h - h / 8.0)
  t.release(x, top + h - h / 8.0)
  let mut opened = 0.0
  while opened < @ui.move_most_ms {
    t.run_for(@ui.frame_period_default)
    opened += @ui.frame_period_default
  }
  // and closed: back in under the bar, the bar over it every frame from the one it has shrunk to its size in
  t.back()
  if film {
    film_frame_answered(t)
  }
  // (a frame at a time, as a host draws them while it goes)
  let mut gone = 0.0
  while gone < @ui.move_most_ms {
    t.run_for(@ui.frame_period_default)
    gone += @ui.frame_period_default
  }
  t.each_frame(None)
  t.check_looks(true)
  t.drawn_again(false)
  if !set_out.val {
    faults.push("it never flew")
  }
  faults
}

///|
test "a picture under a chat's bar: the bar over it every frame till it is out from under it" {
  // a wide window, the tape's, and a phone's; its top a little under the bar's, and half of it over the window's top
  for screen in [(0, 1280.0), (0, 820.0), (2, 390.0)] {
    for top in [10.0, -100.0] {
      let faults = picture_under_bar_faults(top, screen.0, screen.1)
      assert_true(faults.is_empty(), msg="\{screen.1} wide, its top at \{top}: \{Repr(faults)}")
    }
  }
}

///|
test "a film under a chat's bar: the bar over it every frame till it is out from under it" {
  for screen in [(0, 1280.0), (0, 820.0), (2, 390.0)] {
    for top in [10.0, -100.0] {
      let faults = picture_under_bar_faults(top, screen.0, screen.1, film=true)
      assert_true(faults.is_empty(), msg="\{screen.1} wide, its top at \{top}: \{Repr(faults)}")
    }
  }
}
