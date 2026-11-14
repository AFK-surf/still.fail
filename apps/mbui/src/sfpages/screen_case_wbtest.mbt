// A simulator's case (screen_case.mbt): where it stands, what it leaves to its buttons, and what is told as they are pressed.

///|
/// A phone's case as a station tells it, upright: 720×1280, the rig's picture being that on its side.
fn case_panel() -> Json {
  let rect = fn(x : Double, y : Double, w : Double, h : Double) {
    Json::object({
      "x": Json::number(x),
      "y": Json::number(y),
      "width": Json::number(w),
      "height": Json::number(h),
    })
  }
  let button = fn(name : String, x : Double, y : Double, w : Double, h : Double, usage : Double) {
    Json::object({
      "name": Json::string(name),
      "x": Json::number(x),
      "y": Json::number(y),
      "width": Json::number(w),
      "height": Json::number(h),
      "dx": Json::number(5.0),
      "dy": Json::number(0.0),
      "page": Json::number(12.0),
      "usage": Json::number(usage),
    })
  }
  Json::object({
    "key": Json::string("k"),
    "width": Json::number(720.0),
    "height": Json::number(1280.0),
    "frame": Json::object({ "width": Json::number(400.0), "height": Json::number(680.0) }),
    "screen": rect(20.0, 20.0, 360.0, 640.0),
    "corners": Json::array([Json::number(0.1), Json::number(0.1), Json::number(0.1), Json::number(0.1)]),
    "buttons": Json::array([
      button("volume-up", 0.0, 100.0, 16.0, 60.0, 233.0),
      button("power", 384.0, 120.0, 16.0, 100.0, 48.0),
    ]),
  })
}

///|
/// A screen's page on a device whose case is told (`turn` as the station says it stands), its pictures as they answer.
fn case_rig(turn : Int) -> ScreenRig {
  let r = screen_rig(w=1280.0, h=900.0)
  let pictures = Json::object({
    "body": Json::string(tiny_png),
    "buttons": Json::object({
      "volume-up": Json::object({ "up": Json::string(tiny_png), "down": Json::string(tiny_png) }),
      "power": Json::object({ "up": Json::string(tiny_png) }),
    }),
  })
  r.answer.val = fn(name, _) { if name == "screen.chrome" { Some(Ok(pictures)) } else { None } }
  case_came.clear()
  case_asked.clear()
  r.state("live", more={
    "kind": Json::string("simulator"),
    "debug": Json::boolean(true),
    "chrome": Json::array([case_panel()]),
    "turn": Json::number(turn.to_double()),
  })
  r.config()
  r.frame(1.0)
  r.t.draw()
  r.t.draw()
  r
}

///|
/// One white pixel.
let tiny_png : String = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4//8/AwAI/AL+hc2rNAAAAABJRU5ErkJggg=="

///|
test "a rect and a way turned with the frame" {
  let r : SRect = { x: 10.0, y: 20.0, w: 30.0, h: 40.0 }
  // a frame of 100×200: clockwise, its top left goes to the top right
  assert_eq(turned_rect(r, 100.0, 200.0, 1), { x: 140.0, y: 10.0, w: 40.0, h: 30.0 })
  assert_eq(turned_rect(r, 100.0, 200.0, 2), { x: 60.0, y: 140.0, w: 30.0, h: 40.0 })
  assert_eq(turned_rect(r, 100.0, 200.0, 3), { x: 20.0, y: 60.0, w: 40.0, h: 30.0 })
  assert_eq(turned_rect(r, 100.0, 200.0, 0), r)
  assert_eq(turned_way(5.0, 0.0, 1), (0.0, 5.0))
  assert_eq(turned_way(5.0, 0.0, 2), (-5.0, 0.0))
  assert_eq(turned_way(5.0, 0.0, 3), (0.0, -5.0))
}

///|
test "where a button is pressed: a press's room, never over the panel" {
  let screen : SRect = { x: 100.0, y: 100.0, w: 300.0, h: 600.0 }
  // on the left, thin and short
  let left = case_room({ x: 80.0, y: 200.0, w: 16.0, h: 20.0 }, screen, false)
  assert_eq(left.h, case_press)
  assert_eq(left.x + left.w, screen.x)
  assert_true(left.w >= 20.0)
  // on the right
  let right = case_room({ x: 405.0, y: 200.0, w: 16.0, h: 90.0 }, screen, false)
  assert_eq(right.x, screen.x + screen.w)
  assert_eq(right.h, 90.0)
  assert_true(right.w >= 21.0)
  // over and under
  let top = case_room({ x: 200.0, y: 85.0, w: 90.0, h: 12.0 }, screen, false)
  assert_eq(top.y + top.h, screen.y)
  let foot = case_room({ x: 200.0, y: 705.0, w: 90.0, h: 12.0 }, screen, false)
  assert_eq(foot.y, screen.y + screen.h)
}

///|
test "a device's case: round the picture once its pictures have come, its buttons held on it and not among the tools" {
  let r = case_rig(0)
  assert_eq(r.told("screen.chrome").length() >= 1, true)
  // the picture in the middle, the case's room kept round it
  let shown = r.ui().shown(r.t.ctx())
  assert_true(shown.w > 0.0)
  assert_true(r.ui().case_x > 0.0)
  assert_true(shown.x >= shown.w * r.ui().case_x - 0.5)
  assert_true(shown.x + shown.w <= r.ui().box_w.get())
  // what the case has is not offered again; what it has not is
  assert_true(r.labelled(tr("web-pages.screen.device.home")) is Some(_))
  assert_true(r.labelled(tr("web-pages.screen.device.lock")) is Some(_))
  // pressed where it is on the case (the picture on its side: over it), told going down and coming up, and no finger on the picture
  let (_, y) = r.labelled(tr("web-pages.screen.debug.volumeUp")).unwrap()
  assert_true(y < r.ui().stage_y + shown.y)
  r.tap_label(tr("web-pages.screen.debug.volumeUp"))
  r.t.draw()
  let sent = r.inputs().filter(fn(i) { text(Some(i), "t") == "button" })
  assert_eq(sent.length(), 2)
  assert_eq(number(Some(sent[0]), "usage"), 233.0)
  assert_eq(field(Some(sent[0]), "down"), Some(Json::boolean(true)))
  assert_eq(field(Some(sent[1]), "down"), Some(Json::boolean(false)))
  assert_eq(r.inputs().filter(fn(i) { text(Some(i), "t") == "pointer" }).length(), 0)
  screen_done(r.t)
}

///|
test "turned as the station says, or as the picture stands while that has not come" {
  // the rig's picture is wider than tall: on its side, whichever way is said
  let r = case_rig(3)
  let c = r.t.ctx()
  let k = device_case(c, r.sess(), r.sess().frame_size()).unwrap()
  assert_eq(k.turn, 3)
  assert_eq(k.frame_w, 680.0)
  screen_done(r.t)
  let r0 = case_rig(0)
  let k0 = device_case(r0.t.ctx(), r0.sess(), r0.sess().frame_size()).unwrap()
  assert_eq(k0.turn, 1)
  screen_done(r0.t)
}

///|
test "a picture of another size told: the one showing keeps its shape until that one shows" {
  let r = case_rig(1)
  assert_eq(r.sess().frame_size(), Some((1280, 720)))
  r.say({ "config": { "codec": "jpeg", "width": 720.0, "height": 1280.0 } })
  r.t.draw()
  assert_eq(r.sess().frame_size(), Some((1280, 720)))
  r.say({ "frame": { "key": true, "ts": 2.0 } }, bytes=b"\xFF\xD8\xFF\xE0jpeg")
  r.t.stream_shows(r.sess().stream.unwrap().id(), 2.0, 720, 1280)
  r.t.draw()
  assert_eq(r.sess().frame_size(), Some((720, 1280)))
  screen_done(r.t)
}
