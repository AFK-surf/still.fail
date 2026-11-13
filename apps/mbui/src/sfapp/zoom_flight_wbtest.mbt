// A chat's picture or film closed from its viewer while it is zoomed, or while its zoom or its flight in still goes:
// back into its thumbnail as one fitted goes (the user, 2026-11-09: 「展开收起还有不少问题，基本都跟预览里放大有关」).

///|
/// The picture drawn last over its page (what flies, or what the viewer shows): where it is (x, y, w, h), the clip it
/// is drawn in (left, top, right, bottom) and that clip's corners (top left, then round it); `whole`, where all of the
/// picture lies, what is drawn of it a part (a film's still in its box).
struct ZfPic {
  at : (Double, Double, Double, Double)
  whole : (Double, Double, Double, Double)
  clip : (Double, Double, Double, Double)
  corners : (Double, Double, Double, Double)
}

///|
fn zf_pic(t : @ui.Tester) -> ZfPic? {
  let mut out = None
  for i in t.drawn_instances() {
    if i[5] == 4.0 && i[2] > 60.0 && i[11] > 0.5 {
      let (w, h) = (i[2] / i[14], i[3] / i[15])
      // (its corners as it is cut: by what it is drawn in, else by its own (a flight of the window's tree's draws a
      // picture round in itself))
      let cut = (i[24], i[25], i[26], i[27])
      out = Some({
        at: (i[0], i[1], i[2], i[3]),
        whole: (i[0] - i[12] * w, i[1] - i[13] * h, w, h),
        clip: (i[16], i[17], i[18], i[19]),
        corners: if cut.0 > 0.0 || cut.1 > 0.0 || cut.2 > 0.0 || cut.3 > 0.0 { cut } else { (i[4], i[4], i[4], i[4]) },
      })
    }
  }
  out
}

///|
/// No fault found, or the test fails saying them and `what` it was.
fn zf_none(faults : Array[String], what : String) -> Unit raise {
  assert_true(faults.is_empty(), msg="\{what}: \{Repr(faults)}")
}

///|
/// Two fingers down in the viewer's middle, 150 and `from` across, the second moved to `to` and both let go: zoomed
/// (`to` - 150) / (`from` - 150) times, a frame for each.
fn zf_pinch(t : @ui.Tester, from : Double, to : Double) -> Unit {
  t.touch(0, 150.0, 422.0)
  t.draw()
  t.touch(4, from, 422.0)
  t.draw()
  t.touch(5, to, 422.0)
  t.draw()
  t.touch(6, to, 422.0)
  t.draw()
  t.touch(2, 150.0, 422.0)
  t.draw()
}

///|
/// The chat's picture (`film`: its recording) opened from its thumbnail in a window `w` wide (`platform`'s), in and at
/// rest: the Tester, its viewer and its thumbnail's corners as it lay before it opened (its place there kept in
/// `zf_thumb`).
fn zf_opened(film : Bool, platform : Int, w : Double) -> (@ui.Tester, @sfbase.Viewer, (Double, Double, Double, Double)) {
  let (t, x, y) = if film { film_in_chat(platform~, w~) } else { image_in_chat("compare.png", platform~, w~) }
  let (at, corners) = pic_at(t, x, y).unwrap()
  zf_thumb.val = at
  t.tap(x, y)
  let v = viewer.get().unwrap()
  t.run_for(@ui.move_most_ms * 2.0)
  (t, v, corners)
}

///|
/// Where the thumbnail zf_opened opened lay before it opened (x, y, w, h).
// kept across tests: set by each zf_opened before what reads it
let zf_thumb : Ref[(Double, Double, Double, Double)] = Ref((0.0, 0.0, 0.0, 0.0))

///|
/// Viewer `v` closed (back; in a window of a mouse's, Esc), a film's frame answered: the moment its flight back sets
/// out.
fn zf_closed(t : @ui.Tester, film : Bool, wide : Bool) -> Double {
  if wide {
    t.key(@ui.key_escape)
  } else {
    t.back()
  }
  if film {
    film_frame_answered(t)
  }
  t.time()
}

///|
/// What is wrong with the corners of the picture flying back, a quarter, half and three quarters of its time gone: as
/// round as its thumbnail's (`corners`) by as far as it has come, on what is seen of it, rounder each time; none, as
/// it should be.
fn zf_corner_faults(
  t : @ui.Tester,
  v : @sfbase.Viewer,
  start : Double,
  corners : (Double, Double, Double, Double),
  window : (Double, Double),
) -> Array[String] {
  let faults = []
  let end = pic_flight_end(t, v)
  let mut was = 0.0
  for share in [0.25, 0.5, 0.75] {
    t.frame_at(start + (end - start) * share)
    guard zf_pic(t) is Some(p) else {
      faults.push("\{share}: no picture flying")
      continue
    }
    let (tl, tr, br, bl) = p.corners
    if tl < corners.0 * 0.2 || tr < corners.1 * 0.2 || br < corners.2 * 0.2 || bl < corners.3 * 0.2 {
      faults.push("\{share}: corners \{Repr(p.corners)} of the thumbnail's \{Repr(corners)}")
    }
    if tl > corners.0 + 0.01 || tl <= was {
      faults.push("\{share}: its corner \{tl} after \{was}, the thumbnail's \{corners.0}")
    }
    was = tl
    let (l, top, r, b) = p.clip
    if l < -0.01 || top < -0.01 || r > window.0 + 0.01 || b > window.1 + 0.01 {
      faults.push("\{share}: cut to \{Repr(p.clip)}, past the window")
    }
  }
  faults
}

///|
test "zoomed past the window and closed, a picture and a film fly back with round corners all the way: a finger's pinch, a mouse's ⌘ and wheel" {
  for film in [false, true] {
    // 小屏, a finger: pinched 3 times as big
    let (t, v, corners) = zf_opened(film, 2, 390.0)
    assert_true(corners.0 > 4.0, msg="the thumbnail's corners \{Repr(corners)}")
    zf_pinch(t, 240.0, 420.0)
    t.run_for(@ui.move_most_ms)
    let start = zf_closed(t, film, false)
    zf_none(zf_corner_faults(t, v, start, corners, (390.0, 844.0)), "film \{film}, a finger's")
    // a wide window, a mouse: ⌘ and the wheel
    let (t, v, corners) = zf_opened(film, 0, 1280.0)
    t.wheel_with(640.0, 400.0, 0.0, -1100.0, @ui.wheel_mod_cmd)
    t.run_for(@ui.move_most_ms)
    let start = zf_closed(t, film, true)
    zf_none(zf_corner_faults(t, v, start, corners, (1280.0, 844.0)), "film \{film}, a mouse's")
  }
}

///|
/// How long the flight back takes of a film pinched (`to` - 150) / (`from` - 150) times as big, past the whole window,
/// and closed.
fn zf_film_back_ms(from : Double) -> Double raise {
  let (t, v, _) = zf_opened(true, 2, 390.0)
  zf_pinch(t, from, 330.0)
  t.run_for(@ui.move_most_ms)
  let (x, y, w, h) = @sf.player_picture_at(v.media.unwrap().key()).unwrap()
  assert_true(x <= 0.0 && y <= 0.0 && x + w >= 390.0 && y + h >= 844.0, msg="over the whole window: \{Repr((x, y, w, h))}")
  let start = zf_closed(t, true, false)
  pic_flight_end(t, v) - start
}

///|
test "a film zoomed past the whole window flies back as long however far past it is: what is seen of it goes as far" {
  // 6 times and 12 times as big
  let (six, twelve) = (zf_film_back_ms(180.0), zf_film_back_ms(165.0))
  assert_true((six - twelve).abs() < 1.0, msg="\{six} \{twelve}")
}

///|
/// What is wrong once the image shown by `v`, its zoom on its way, is closed: the zoom stopped where it was, the
/// picture flying back from there, nearer its thumbnail's width each quarter of the way; none, as it should be.
fn zf_stop_faults(t : @ui.Tester, v : @sfbase.Viewer, wide : Bool) -> Array[String] {
  let faults = []
  if !v.zoom.goes_at(t.time()) {
    faults.push("its zoom not on its way as it is closed")
  }
  let start = zf_closed(t, false, wide)
  let end = pic_flight_end(t, v)
  let stopped = v.zoom.rect_at(start).unwrap()
  let home = zf_thumb.val.2
  let mut was = (stopped.2 - home).abs() + 0.01
  for share in [0.25, 0.5, 0.75] {
    t.frame_at(start + (end - start) * share)
    if v.zoom.rect_at(t.time()).unwrap() != stopped {
      faults.push("\{share}: its zoom went on, \{Repr(v.zoom.rect_at(t.time()))} from \{Repr(stopped)}")
    }
    match zf_pic(t) {
      Some(p) => {
        let left = (p.at.2 - home).abs()
        if left >= was {
          faults.push("\{share}: the picture \{p.at.2} wide, \{left} from its thumbnail's after \{was}")
        }
        was = left
      }
      None => faults.push("\{share}: no picture flying")
    }
  }
  faults
}

///|
test "an image closed while its zoom is on its way (a double tap's, a fling, back to fitted, a key's) flies back from where it was: the zoom stopped" {
  // a double tap's glide
  let (t, v, _) = zf_opened(false, 2, 390.0)
  t.tap(195.0, 422.0)
  t.advance(@ui.double_tap_ms / 2.0)
  t.tap(195.0, 422.0)
  t.advance(@ui.frame_period_default)
  t.draw()
  zf_none(zf_stop_faults(t, v, false), "a double tap's")
  // zoomed, then moved and let go moving: its fling
  let (t, v, _) = zf_opened(false, 2, 390.0)
  zf_pinch(t, 240.0, 420.0)
  t.run_for(@ui.move_most_ms)
  t.hold_drag(150.0, 422.0, 250.0, 422.0, steps=4)
  t.release(250.0, 422.0)
  zf_none(zf_stop_faults(t, v, false), "a fling")
  // pinched smaller than fitted and let go: on its way back to fitted
  let (t, v, _) = zf_opened(false, 2, 390.0)
  zf_pinch(t, 330.0, 240.0)
  zf_none(zf_stop_faults(t, v, false), "back to fitted")
  // a wide window: + zooms in, gliding
  let (t, v, _) = zf_opened(false, 0, 1280.0)
  t.key(@ui.key_of_char('='))
  t.advance(@ui.frame_period_default)
  t.draw()
  zf_none(zf_stop_faults(t, v, true), "a key's")
}

///|
test "a film pinched smaller than fitted and let go: back to fitted, as an image is" {
  let (t, v, _) = zf_opened(true, 2, 390.0)
  let key = v.media.unwrap().key()
  let fit = @sf.player_picture_at(key).unwrap()
  t.touch(0, 150.0, 422.0)
  t.draw()
  t.touch(4, 330.0, 422.0)
  t.draw()
  t.touch(5, 240.0, 422.0)
  t.draw()
  assert_true(@sf.player_picture_at(key).unwrap().2 < fit.2 * 0.75, msg="\{Repr(@sf.player_picture_at(key))} \{Repr(fit)}")
  t.touch(6, 240.0, 422.0)
  t.draw()
  t.touch(2, 150.0, 422.0)
  t.draw()
  t.run_for(@ui.move_most_ms)
  let now = @sf.player_picture_at(key).unwrap()
  assert_true(
    (now.0 - fit.0).abs() < 0.01 && (now.1 - fit.1).abs() < 0.01 && (now.2 - fit.2).abs() < 0.01 && (now.3 - fit.3).abs() < 0.01,
    msg="\{Repr(now)} \{Repr(fit)}",
  )
}

///|
test "a film zoomed, flung and closed: its flight back sets out where its player drew it last, gone on while its frame was grabbed" {
  let (t, v, _) = zf_opened(true, 2, 390.0)
  let key = v.media.unwrap().key()
  zf_pinch(t, 240.0, 420.0)
  t.run_for(@ui.move_most_ms)
  t.hold_drag(150.0, 422.0, 250.0, 422.0, steps=4)
  t.release(250.0, 422.0)
  let let_go = @sf.player_picture_at(key).unwrap()
  t.back()
  // the host answers three frames on, the picture going on meanwhile
  for _ in 0..<3 {
    t.advance(@ui.frame_period_default)
    t.draw()
  }
  let last = @sf.player_picture_at(key).unwrap()
  assert_true(last.0 > let_go.0 + 8.0, msg="flung on: \{Repr(let_go)} \{Repr(last)}")
  film_frame_answered(t)
  assert_true(v.flies && !v.leaving_grab)
  let p = zf_pic(t).unwrap()
  assert_true((p.whole.0 - last.0).abs() < 0.5 && (p.whole.2 - last.2).abs() < 0.5, msg="\{Repr(p.whole)} \{Repr(last)}")
}

///|
test "a film opened again and closed while it still flies in: back from where that has got to at once, its player's picture never whole meanwhile" {
  let (t, x, y) = film_in_chat()
  t.tap(x, y)
  t.run_for(@ui.move_most_ms * 2.0)
  zf_closed(t, true, false) |> ignore
  t.run_for(@ui.move_most_ms * 2.0)
  assert_true(viewer.get() is None && pv_leaving.get() is None)
  // again: its player's view here already
  t.tap(x, y)
  let v = viewer.get().unwrap()
  for _ in 0..<3 {
    t.advance(@ui.frame_period_default)
    t.draw()
  }
  assert_true(v.flies, msg="still flying in")
  let before = zf_pic(t).unwrap()
  t.back()
  assert_true(!v.leaving_grab, msg="no frame waited for")
  assert_eq(t.holes(), [])
  let after = zf_pic(t).unwrap()
  assert_true(after.at.2 <= before.at.2 + 0.5, msg="\{Repr(before.at)} \{Repr(after.at)}")
  t.advance(@ui.frame_period_default)
  t.draw()
  assert_eq(t.holes(), [])
  let next = zf_pic(t).unwrap()
  assert_true(next.at.2 < after.at.2, msg="\{Repr(after.at)} \{Repr(next.at)}")
}

///|
/// The frames of `v`'s flight (till `end`) in which the flying picture's corners are not all one, as its thumbnail's
/// are.
fn zf_uneven_frames(t : @ui.Tester, end : Double) -> Array[String] {
  let faults = []
  while t.time() + @ui.frame_period_default < end {
    t.advance(@ui.frame_period_default)
    t.draw()
    match zf_pic(t) {
      Some(p) => {
        let (tl, tr, br, bl) = p.corners
        if (tl - tr).abs() > 0.01 || (tl - br).abs() > 0.01 || (tl - bl).abs() > 0.01 {
          faults.push("\{end - t.time()} before its end: \{Repr(p.corners)}")
        }
      }
      None => ()
    }
  }
  faults
}

///|
test "a picture's and a film's flight out and back: its four corners as round as each other in every frame" {
  // (every frame on the way walked, the same at any rate)
  if @ui.test_at_a_rate() {
    return
  }
  for film in [false, true] {
    let (t, x, y) = if film { film_in_chat() } else { image_in_chat("compare.png") }
    let (tl, tr, br, bl) = pic_at(t, x, y).unwrap().1
    assert_true(tl > 4.0 && tl == tr && tl == br && tl == bl, msg="the thumbnail's corners")
    t.tap(x, y)
    let v = viewer.get().unwrap()
    zf_none(zf_uneven_frames(t, pic_flight_end(t, v)), "film \{film}, out")
    t.run_for(@ui.move_most_ms * 2.0)
    zf_closed(t, film, false) |> ignore
    zf_none(zf_uneven_frames(t, pic_flight_end(t, v)), "film \{film}, back")
  }
}
