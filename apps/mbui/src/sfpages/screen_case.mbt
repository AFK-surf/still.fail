// A simulator's device as Xcode draws it: its case and buttons, whose pictures its
// station makes of what Xcode has on that Mac (screens/sim-chrome.ts; `screen.chrome`), turned as the device stands. The
// case has the panel's shape cut out of it, so the picture shows through it, on the system's video layer or drawn here
// alike; its buttons are pressed where they are, held as long as they are here. Until a device's pictures have come, or
// from a station without them, device_round draws what it does.

///|
/// How far past what shows of a button it is still pressed: as much of a press's room as it takes, clear of what is by it.
let case_reach : Double = 16.0

///|
/// How much of a panel's corner is cut off the square picture under the case: all of it is under the case there.
let case_corner_share : Double = 0.8

///|
/// A press's room, each way.
let case_press : Double = 44.0

///|
/// A device's case as it stands now, in its own points, all turned as its picture is.
priv struct DeviceCase {
  station : String
  /// its panel's case (the same pictures where another device has the same)
  key : String
  turn : Int
  frame_w : Double
  frame_h : Double
  screen : SRect
  /// the panel's corners, upright as its framebuffer is, top left and round it (shares of its width)
  corners : Array[Double]
  buttons : Array[CaseButton]
}

///|
priv struct CaseButton {
  name : String
  at : SRect
  dx : Double
  dy : Double
  front : Bool
  usage : (Int, Int)?
}

///|
/// The rect `r` of a `w`×`h` frame, the frame turned `turn` quarters clockwise.
fn turned_rect(r : SRect, w : Double, h : Double, turn : Int) -> SRect {
  match turn {
    1 => { x: h - r.y - r.h, y: r.x, w: r.h, h: r.w }
    2 => { x: w - r.x - r.w, y: h - r.y - r.h, w: r.w, h: r.h }
    3 => { x: r.y, y: w - r.x - r.w, w: r.h, h: r.w }
    _ => r
  }
}

///|
/// A way (dx, dy) turned as turned_rect does.
fn turned_way(dx : Double, dy : Double, turn : Int) -> (Double, Double) {
  match turn {
    1 => (-dy, dx)
    2 => (-dx, -dy)
    3 => (dy, -dx)
    _ => (dx, dy)
  }
}

///|
/// The picture in `r`, `r` being it and its case's share each way on each side.
fn cased_in(r : SRect, x : Double, y : Double) -> SRect {
  let w = r.w / (1.0 + 2.0 * x)
  let h = r.h / (1.0 + 2.0 * y)
  { x: r.x + w * x, y: r.y + h * y, w, h }
}

///|
/// How much of the case and what it has is round the picture at its widest, each way, as shares of the picture: it is kept in
/// the middle, as the picture of a device with no case is, whichever side has more.
fn DeviceCase::around(self : DeviceCase) -> (Double, Double) {
  let s = self.screen
  (
    dmax(s.x, self.frame_w - s.x - s.w) / s.w,
    dmax(s.y, self.frame_h - s.y - s.h) / s.h,
  )
}

///|
/// Whether it has that button.
fn DeviceCase::has(self : DeviceCase, name : String) -> Bool {
  self.buttons.iter().any(fn(b) { b.name == name })
}

///|
/// What is known to have come of a device's pictures (each case's, each way it is turned): what was asked, and what came.
// kept across runs: each is the pictures a station made of its Xcode's, the same whoever asks
let case_asked : Map[String, Bool] = Map([])

///|
// kept across runs: as case_asked
let case_came : Map[String, Bool] = Map([])

///|
fn case_picture(station : String, key : String, turn : Int, name : String) -> String {
  "mem:sf/case/\{station}/\{key}/\{turn}/\{name}"
}

///|
/// The case of the panel a picture of `size` is of, once its pictures have come (they are asked for here, those of this
/// way first and the rest after them, for a turn to find them come); none: not one, or not yet.
fn device_case(c : @ui.Ctx, s : ScreenSess, size : (Int, Int)?) -> DeviceCase? {
  guard s.simulator() && size is Some((pw, ph)) && pw > 0 && ph > 0 else { return None }
  guard field(s.state, "chrome") is Some(Array(panels)) && panels.length() > 0 else { return None }
  let (pw, ph) = (pw.to_double(), ph.to_double())
  let shape = dmin(pw, ph) / dmax(pw, ph)
  let mut panel = -1
  let mut off = 0.01
  for i, p in panels {
    let (w, h) = (number(Some(p), "width"), number(Some(p), "height"))
    if w > 0.0 && h > 0.0 && (shape - dmin(w, h) / dmax(w, h)).abs() < off {
      off = (shape - dmin(w, h) / dmax(w, h)).abs()
      panel = i
    }
  }
  guard panel >= 0 else { return None }
  let p = Some(panels[panel])
  // as the station says it stands, while that is a way the picture can stand (the picture of a turn comes on its own)
  let lying = (number(p, "width") > number(p, "height")) != (pw > ph)
  let said = number(s.state, "turn").to_int()
  let turn = if (said % 2 == 1) == lying {
    said
  } else if lying {
    1
  } else {
    0
  }
  let key = text(p, "key")
  case_ask(c, s, panels, panel, turn)
  guard case_came.contains(case_picture(s.station, key, turn, "")) else { return None }
  // decoded before it shows, and the other ways it may stand with it, so that a turn finds it there
  let (win_w, win_h) = c.window_size()
  let px = dmax(win_w, win_h) * c.scale
  for t in 0..<4 {
    if t != turn && case_came.contains(case_picture(s.station, key, t, "")) {
      c.image_ready(case_picture(s.station, key, t, "body"), px) |> ignore
    }
  }
  guard c.image_ready(case_picture(s.station, key, turn, "body"), px) else { return None }
  let (fw, fh) = (number(field(p, "frame"), "width"), number(field(p, "frame"), "height"))
  let rect_of = fn(v : Json?) -> SRect {
    turned_rect({ x: number(v, "x"), y: number(v, "y"), w: number(v, "width"), h: number(v, "height") }, fw, fh, turn)
  }
  let buttons = items(p, "buttons").map(fn(b) {
    let (dx, dy) = turned_way(number(Some(b), "dx"), number(Some(b), "dy"), turn)
    let usage = number(Some(b), "usage").to_int()
    {
      name: text(Some(b), "name"),
      at: rect_of(Some(b)),
      dx,
      dy,
      front: flag(Some(b), "front"),
      usage: if usage > 0 { Some((number(Some(b), "page").to_int(), usage)) } else { None },
    }
  })
  let turned = turn % 2 == 1
  Some({
    station: s.station,
    key,
    turn,
    frame_w: if turned { fh } else { fw },
    frame_h: if turned { fw } else { fh },
    screen: rect_of(field(p, "screen")),
    corners: items(p, "corners").map(fn(v) {
      match v {
        Number(n, ..) => n
        _ => 0.0
      }
    }),
    buttons,
  })
}

///|
/// This way's pictures asked for, then, as each comes, the next not asked for of the others: one at a time, as making them
/// is all the station does for as long as it takes.
fn case_ask(c : @ui.Ctx, s : ScreenSess, panels : Array[Json], panel : Int, turn : Int) -> Unit {
  let station = s.station
  let screen = s.screen
  let src = s.src
  let ask : (Int, Int) -> Unit = fn(i, t) { case_ask_one(src, station, screen, panels, i, t) }
  if !case_asked.contains(case_picture(station, text(Some(panels[panel]), "key"), turn, "")) {
    c.tell("screen-case/" + station + "/" + screen + "/\{panel}/\{turn}", fn() { ask(panel, turn) })
  }
}

///|
fn case_ask_one(src : Source, station : String, screen : String, panels : Array[Json], panel : Int, turn : Int) -> Unit {
  let p = Some(panels[panel])
  let key = text(p, "key")
  let id = case_picture(station, key, turn, "")
  if case_asked.contains(id) {
    return
  }
  case_asked[id] = true
  let params = {
    "station": Json::string(station),
    "screen": Json::string(screen),
    "panel": Json::number(panel.to_double()),
    "turn": Json::number(turn.to_double()),
  }
  (src.call)("screen.chrome", Json::object(params), fn(r) {
    guard r is Ok(v) else { return }
    let got = Some(v)
    let take = fn(name : String, b64 : String) {
      match @codec.from_base64_exact(b64) {
        Some(png) => @ui.add_image(case_picture(station, key, turn, name), png)
        None => ()
      }
    }
    take("body", text(got, "body"))
    for b in items(p, "buttons") {
      let name = text(Some(b), "name")
      let pictures = field(field(got, "buttons"), name)
      take(name, text(pictures, "up"))
      take(name + "/down", text(pictures, "down"))
    }
    case_came[id] = true
    // the rest, one after another
    for i, _ in panels {
      for t in 0..<4 {
        if !case_asked.contains(case_picture(station, text(Some(panels[i]), "key"), t, "")) {
          case_ask_one(src, station, screen, panels, i, t)
          return
        }
      }
    }
  })
}

///|
/// A case's picture drawn at `r` of what it is drawn in.
fn case_image(c : @ui.Ctx, src : String, r : SRect) -> Unit {
  c.box(tx=r.x, ty=r.y, fn() {
    c.image(src, w=Px(r.w), h=Px(r.h), fit=FitFill, bg=0L, fade=false) |> ignore
  })
  |> ignore
}

///|
/// The device's case round its picture at `shown`: its buttons behind it (in their pressed picture, and in a way, under a
/// press), it over them, a home button on it, and where each is pressed.
fn device_cased(c : @ui.Ctx, s : ScreenSess, u : ScreenUi, k : DeviceCase, shown : SRect) -> Unit {
  let scale = shown.w / k.screen.w
  let ox = shown.x - k.screen.x * scale
  let oy = shown.y - k.screen.y * scale
  let place = fn(r : SRect) -> SRect {
    { x: ox + r.x * scale, y: oy + r.y * scale, w: r.w * scale, h: r.h * scale }
  }
  let picture = fn(name : String) { case_picture(k.station, k.key, k.turn, name) }
  let id_of = fn(b : CaseButton) { c.id("screen-case-button/" + s.view + "/" + b.name) }
  let looks = fn(b : CaseButton) {
    let down = s.driving() && c.pressed(id_of(b))
    let r = place(b.at)
    // (pressed, in by half the way: it stays to be seen)
    let at = if down { { ..r, x: r.x + b.dx * scale / 2.0, y: r.y + b.dy * scale / 2.0 } } else { r }
    case_image(c, picture(if down { b.name + "/down" } else { b.name }), at)
  }
  // the picture's corners, outside the panel, as far in as the case over them: the panel's own less a little, it being no circle
  let unit = dmin(shown.w, shown.h) * case_corner_share
  let corner = fn(i : Int) { if k.corners.length() == 4 { k.corners[(i + 4 - k.turn) % 4] * unit } else { 0.0 } }
  device_corners(c, u, shown, corner(0), corner(1), corner(2), corner(3))
  // (each a layer of its own: in one they would lie under one another)
  for b in k.buttons {
    if !b.front {
      c.layer(fn() { looks(b) }) |> ignore
    }
  }
  c.layer(fn() { case_image(c, picture("body"), place({ x: 0.0, y: 0.0, w: k.frame_w, h: k.frame_h })) }) |> ignore
  for b in k.buttons {
    if b.front {
      c.layer(fn() { looks(b) }) |> ignore
    }
  }
  if !s.driving() {
    return
  }
  for b in k.buttons {
    match (b.usage, case_button_word(b.name)) {
      (Some(usage), Some(word)) =>
        c.layer(fn() { case_button_press(c, s, u, b, id_of(b), case_room(place(b.at), place(k.screen), b.front), usage, word) }) |> ignore
      _ => ()
    }
  }
}

///|
/// What a person calls a button.
fn case_button_word(name : String) -> String? {
  match name {
    "power" => Some(@sf.t("web-pages.screen.device.lock"))
    "home" => Some(@sf.t("web-pages.screen.device.home"))
    "volume-up" => Some(@sf.t("web-pages.screen.debug.volumeUp"))
    "volume-down" => Some(@sf.t("web-pages.screen.debug.volumeDown"))
    "action" => Some(@sf.t("web-pages.screen.device.action"))
    "mute" => Some(@sf.t("web-pages.screen.device.mute"))
    _ => None
  }
}

///|
/// Where a button at `r` is pressed: a press's room (case_press) along its edge and across it, from the panel at `screen`
/// outward, never over that, and on the case itself as it is (a home button) only as far as that takes.
fn case_room(r : SRect, screen : SRect, front : Bool) -> SRect {
  if front {
    let w = dmax(r.w, case_press)
    let h = dmax(r.h, case_press)
    return { x: r.x + (r.w - w) / 2.0, y: r.y + (r.h - h) / 2.0, w, h }
  }
  if r.y + r.h <= screen.y + 1.0 {
    // over the panel
    let w = dmax(r.w, case_press)
    let y = dmax(r.y - case_reach, dmin(r.y, screen.y - case_press))
    { x: r.x + (r.w - w) / 2.0, y, w, h: screen.y - y }
  } else if r.y >= screen.y + screen.h - 1.0 {
    let w = dmax(r.w, case_press)
    let end = dmin(r.y + r.h + case_reach, dmax(r.y + r.h, screen.y + screen.h + case_press))
    { x: r.x + (r.w - w) / 2.0, y: screen.y + screen.h, w, h: end - screen.y - screen.h }
  } else if r.x < screen.x {
    let h = dmax(r.h, case_press)
    let x = dmax(r.x - case_reach, dmin(r.x, screen.x - case_press))
    { x, y: r.y + (r.h - h) / 2.0, w: screen.x - x, h }
  } else {
    let h = dmax(r.h, case_press)
    let end = dmin(r.x + r.w + case_reach, dmax(r.x + r.w, screen.x + screen.w + case_press))
    { x: screen.x + screen.w, y: r.y + (r.h - h) / 2.0, w: end - screen.x - screen.w, h }
  }
}

///|
/// A button pressed at `room`: told as it goes down and as it comes up, as long as it is held here (a power button held
/// is Siri, then the slider, as on the device).
fn case_button_press(
  c : @ui.Ctx,
  s : ScreenSess,
  u : ScreenUi,
  b : CaseButton,
  id : Int,
  room : SRect,
  usage : (Int, Int),
  word : String,
) -> Unit {
  let i = c.box(style=@ui.style(w=Fixed(room.w), h=Fixed(room.h)), tx=room.x, ty=room.y, id~, fn() {  })
  c.semantics(i, Button, id~, label=word, actions=[Activate])
  @sf.tip(c, "screen-case-tip/" + b.name, id, word)
  let held = u.logs.buttons_held
  let was = held.contains(b.name)
  let now = c.pressed(id)
  let tell = fn(down : Bool) {
    s.input(s.src, Json::object({
      "t": Json::string("button"),
      "page": Json::number(usage.0.to_double()),
      "usage": Json::number(usage.1.to_double()),
      "down": Json::boolean(down),
    }))
  }
  if now && !was {
    held[b.name] = true
    c.tell("screen-case-down/" + s.view + "/" + b.name, fn() { tell(true) })
  } else if !now && was {
    held.remove(b.name)
    c.tell("screen-case-up/" + s.view + "/" + b.name, fn() { tell(false) })
  } else if !now && c.clicked(id) {
    // (down and up between two frames)
    c.tell("screen-case-tap/" + s.view + "/" + b.name, fn() {
      tell(true)
      tell(false)
    })
  }
}
