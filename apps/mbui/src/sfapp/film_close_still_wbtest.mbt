// A film's viewer closed showed a frame of black where the film was: the frame its player shows grabbed to go back
// with, the host was told to hide the player as that frame was answered, and its flight drew the picture only once it
// was decoded (a frame later; the whole way back where the decode came late). From the close till the viewer is gone,
// each frame as a device's host draws it shows the player or draws a picture where the film is: the grabbed frame's
// picture decoded at once, a frame late, long after the old way back would have landed, or never (its still flown
// then); 小屏 by touch, 大屏 by the mouse, closed by back, by a drag down let go, zoomed, and while it plays.

///|
/// How the host answers the decode of a frame grabbed as a film closes: its name, and what it does with it at a frame's
/// start, seen waiting at `seen` frames' starts before, at `now`, the close at `close`: 0 nothing yet, 1 decoded, -1
/// failed.
struct FcDecode {
  name : String
  answer : (Int, Double, Double) -> Int
}

///|
fn fc_decodes() -> Array[FcDecode] {
  [
    FcDecode::{ name: "decoded at once", answer: fn(_, _, _) { 1 } },
    FcDecode::{ name: "decoded a frame late", answer: fn(seen, _, _) { if seen >= 1 { 1 } else { 0 } } },
    // (past the old way back's whole length, and the longest Move's, twice over)
    FcDecode::{
      name: "decoded long after",
      answer: fn(_, now, close) { if now >= close + @ui.move_most_ms * 2.0 { 1 } else { 0 } },
    },
    FcDecode::{ name: "failing to decode", answer: fn(_, _, _) { -1 } },
  ]
}

///|
/// A film's viewer as it closes, frame by frame: its Tester, the native view its player is in, the thumbnail's place
/// (x, y, w, h), where it is pressed, the close's moment, the host's log read so far, whether the player is shown and
/// closed by it, whether its grab was answered, and what was wrong in a frame.
struct FcRun {
  t : @ui.Tester
  w : Double
  wide : Bool
  view : Int
  thumb : (Double, Double, Double, Double)
  at : (Double, Double)
  close : Ref[Double]
  mut read : Int
  mut shown : Bool
  mut closed : Bool
  mut grabbed : Bool
  faults : Array[String]
}

///|
/// The chat's 演示录屏.mp4 in a window `w` wide (`platform`'s), its viewer opened and at rest; what the host does for the
/// app done at each frame's start as a Tester's own host does it, but the decode of a frame grabbed as it closes, done as
/// `decode` says.
fn fc_opened(platform : Int, w : Double, decode : FcDecode) -> FcRun raise {
  let close = Ref(1.0e300)
  let seen : Map[Int, Int] = Map([])
  let answer = fn(t : @ui.Tester) {
    for p in t.pending() {
      if p.0 == 1 && t.image_src(p.1).has_prefix("mem:pv-frame/") {
        let n = seen.get(p.1).unwrap_or(0)
        seen[p.1] = n + 1
        let said = (decode.answer)(n, t.time(), close.val)
        if said != 0 {
          t.finish(1, p.1, ok=(said > 0))
        }
      } else {
        t.finish(p.0, p.1)
      }
    }
  }
  // (made in flight_under_bar_wbtest.mbt's helper: its Testers' bar of the bytes handed over for decodes, a film's
  // frames grabbed among them)
  let (t, x, y) = film_in_chat(platform~, w~, answer=Some(answer))
  guard pic_at(t, x, y) is Some((thumb, _)) else { fail("no thumbnail drawn at \{Repr((x, y))}") }
  // (each frame as a device's host draws it: not built once more to check its looks)
  t.check_looks(false)
  t.tap(x, y)
  t.run_for(@ui.move_most_ms * 2.0)
  assert_true(viewer.get() is Some(_), msg="the viewer opened")
  let opened = t.views().filter(fn(l) { l.has_prefix("open ") })
  assert_true(opened.length() > 0, msg="a player opened: \{Repr(t.views())}")
  let mut view = 0
  for c in opened[opened.length() - 1].split(" ").to_array()[1] {
    view = view * 10 + (c.to_int() - '0'.to_int())
  }
  FcRun::{
    t,
    w,
    wide: platform == 0,
    view,
    thumb,
    at: (x, y),
    close,
    read: t.views().length(),
    shown: true,
    closed: false,
    grabbed: false,
    faults: [],
  }
}

///|
fn fc_min(a : Double, b : Double) -> Double {
  if a < b {
    a
  } else {
    b
  }
}

///|
fn fc_max(a : Double, b : Double) -> Double {
  if a > b {
    a
  } else {
    b
  }
}

///|
/// Whether (x, y, w, h) `a` and `b` overlap.
fn fc_over(a : (Double, Double, Double, Double), b : (Double, Double, Double, Double)) -> Bool {
  a.0 < b.0 + b.2 && b.0 < a.0 + a.2 && a.1 < b.1 + b.3 && b.1 < a.1 + a.3
}

///|
/// Where the film is: from its thumbnail to where its player draws its picture last, all between, in the window.
fn fc_film_area(r : FcRun) -> (Double, Double, Double, Double) {
  let (tx, ty, tw, th) = r.thumb
  let (x0, y0, x1, y1) = match viewer_media_place() {
    Some((px, py, pw, ph)) => (fc_min(tx, px), fc_min(ty, py), fc_max(tx + tw, px + pw), fc_max(ty + th, py + ph))
    None => (tx, ty, tx + tw, ty + th)
  }
  let (x0, y0) = (fc_max(x0, 0.0), fc_max(y0, 0.0))
  let (x1, y1) = (fc_min(x1, r.w), fc_min(y1, 844.0))
  (x0, y0, x1 - x0, y1 - y0)
}

///|
/// Where the player of the viewer open, or going, draws its picture last.
fn viewer_media_place() -> (Double, Double, Double, Double)? {
  let v = match (viewer.get(), pv_leaving.get()) {
    (Some(v), _) | (None, Some(v)) => v
    _ => return None
  }
  match v.media {
    Some(m) => @sf.player_picture_at(m.key())
    None => None
  }
}

///|
/// Whether a picture is drawn where the film is in the frame drawn last, seen: over every ground that covers the window,
/// what of it is not cut away in that place.
fn fc_picture_drawn(r : FcRun) -> Bool {
  let area = fc_film_area(r)
  let drawn = r.t.drawn_instances()
  let mut ground = -1
  for k, i in drawn {
    if i[5] == 0.0 && i[2] >= r.w - 1.0 && i[3] >= 844.0 * 0.9 && i[11] > 0.5 {
      ground = k
    }
  }
  for k, i in drawn {
    if k > ground && i[5] == 4.0 && i[2] > 40.0 && i[11] > 0.5 {
      let seen = if i[18] > i[16] {
        let (x0, y0) = (fc_max(i[0], i[16]), fc_max(i[1], i[17]))
        let (x1, y1) = (fc_min(i[0] + i[2], i[18]), fc_min(i[1] + i[3], i[19]))
        (x0, y0, x1 - x0, y1 - y0)
      } else {
        (i[0], i[1], i[2], i[3])
      }
      if seen.2 > 1.0 && seen.3 > 1.0 && fc_over(seen, area) {
        return true
      }
    }
  }
  false
}

///|
/// A frame of the display's drawn, then looked at: what the host was told of the player in it, a fault where neither
/// it is shown nor a picture is drawn where the film is; the frame its player shows, asked for as it closes, answered
/// after the frame that asked it, as a host answers it.
fn fc_frame(r : FcRun, what : String) -> Unit {
  let t = r.t
  t.frame()
  let lines = t.views()
  let mut asked = false
  for k in r.read..<lines.length() {
    let l = lines[k]
    if l.has_prefix("place \{r.view} ") {
      r.shown = !l.has_suffix(" hidden")
    } else if l == "close \{r.view}" {
      r.shown = false
      r.closed = true
    } else if l.has_prefix("control \{r.view} 22 ") {
      asked = true
    }
  }
  r.read = lines.length()
  if r.close.val < 1.0e300 && !r.shown && !fc_picture_drawn(r) {
    r.faults.push(
      "\{what} +\{Repr((t.time() - r.close.val).round())} ms: neither the player shown nor a picture drawn where the film is",
    )
  }
  if asked && !r.grabbed {
    r.grabbed = true
    let frame = fixture_file_png("演示录屏.mp4")
    t.view_said("{\"still\":{\"view\":\{r.view}},\"b\":\"\{hex_bytes(frame)}\"}") |> ignore
  }
}

///|
/// Closed by the system's back (a phone's), or Escape (a mouse's window), at the moment drawn last, no frame drawn.
fn fc_back(r : FcRun) -> Unit {
  r.close.val = r.t.time()
  if r.wide {
    r.t.key_told(@ui.key_escape, 0, r.t.time())
  } else {
    r.t.back_raw(2, 0.0, r.t.time())
  }
}

///|
/// The film's viewer, opened in a window `w` wide (`platform`'s), closed the way `how` says (back, a drag down let go,
/// zoomed, playing), its grabbed frame's picture decoded as `decode` says: what was wrong in its frames till it was
/// gone, and how it ended.
fn fc_closed(platform : Int, w : Double, how : String, decode : FcDecode) -> Unit raise {
  let r = fc_opened(platform, w, decode)
  let t = r.t
  let name = "\{if r.wide { "大屏 mouse" } else { "小屏 touch" }}, \{how}, \{decode.name}"
  match how {
    "drag down" => {
      // (a finger down in the middle, moved down 300 in 8 moves a frame apart, let go moving)
      let (x, y0, y1) = (w / 2.0, 422.0, 722.0)
      t.touch_raw(0, 7, x, y0, t.time())
      for i in 1..=8 {
        fc_frame(r, name)
        t.touch_raw(1, 7, x, y0 + (y1 - y0) * i.to_double() / 8.0, t.time())
      }
      r.close.val = t.time()
      t.touch_raw(2, 7, x, y1, t.time())
    }
    "zoomed" => {
      if r.wide {
        t.wheel_with(w / 2.0, 422.0, 0.0, -1100.0, @ui.wheel_mod_cmd)
      } else {
        zf_pinch(t, 240.0, 420.0)
      }
      t.run_for(@ui.move_most_ms)
      r.read = t.views().length()
      fc_back(r)
    }
    "playing" => {
      t.set_player(r.view, playing=true, position=4000.0)
      t.run_for(@ui.move_most_ms)
      r.read = t.views().length()
      fc_back(r)
    }
    _ => fc_back(r)
  }
  let start = r.close.val
  while (viewer.get() is Some(_) || pv_leaving.get() is Some(_)) && t.time() < start + @ui.move_most_ms * 6.0 {
    fc_frame(r, name)
  }
  assert_eq(r.faults, [], msg=name)
  assert_true(r.grabbed, msg="\{name}: the frame its player showed asked for")
  assert_true(viewer.get() is None && pv_leaving.get() is None, msg="\{name}: the viewer gone")
  assert_true(r.closed, msg="\{name}: the player closed")
  let (x, y) = r.at
  let back = pic_at(t, x, y).map(fn(p) { p.0 })
  let landed = match back {
    Some(b) =>
      (b.0 - r.thumb.0).abs() < 1.5 &&
      (b.1 - r.thumb.1).abs() < 1.5 &&
      (b.2 - r.thumb.2).abs() < 1.5 &&
      (b.3 - r.thumb.3).abs() < 1.5
    None => false
  }
  assert_true(landed, msg="\{name}: the thumbnail drawn again where it was, \{Repr(r.thumb)}: \{Repr(back)}")
}

///|
test "a film closed shows its player or a picture where it is in every frame till it is gone: 小屏, a finger" {
  for how in ["back", "drag down", "zoomed", "playing"] {
    for decode in fc_decodes() {
      fc_closed(2, 390.0, how, decode)
    }
  }
}

///|
test "a film closed shows its player or a picture where it is in every frame till it is gone: 大屏, a mouse" {
  for how in ["back", "zoomed", "playing"] {
    for decode in fc_decodes() {
      fc_closed(0, 1280.0, how, decode)
    }
  }
}
