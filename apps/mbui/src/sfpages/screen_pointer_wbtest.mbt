// The screen's pointer drawn over the picture (screen_stage.mbt) in the shape the station says (docs/remote-screens.md
// `cursor`): a text cursor over text, a hand over a link, the resizing arrows…, the point it points with where the
// station's pointer is.

///|
/// The pointer drawn in the last frame: its image's source, and where its image is (its top left, its size).
fn drawn_pointer(r : ScreenRig) -> (String, Double, Double, Double)? {
  let lines = r.t.drawlist().split("\n").to_array()
  let mut n = ""
  let mut src = ""
  for line in lines {
    let parts = line.split(" ").to_array()
    if parts.length() > 3 && parts[0] == "image" && parts[3].contains("mem:sf/pointer/") {
      n = parts[1].to_owned()
      src = parts[3].to_owned()
    }
  }
  if n == "" {
    return None
  }
  let num = fn(s : StringView) -> Double {
    match (try Some(@json.parse(s.to_owned())) catch { _ => None }) {
      Some(Number(d, ..)) => d
      _ => -1.0
    }
  }
  for line in lines {
    let parts = line.split(" ").to_array()
    // an image's instance (kind 4) of that image (its 20)
    if parts.length() > 21 && parts[0] == "i" && parts[6] == "4" && parts[21].to_owned() == n {
      return Some((src, num(parts[1]), num(parts[2]), num(parts[3])))
    }
  }
  None
}

///|
/// The station's pointer at (x, y) of the screen, in `shape`.
fn ScreenRig::cursor_at(self : ScreenRig, x : Double, y : Double, shape : String) -> Unit {
  self.state("live", others=[], more={
    "kind": Json::string("desktop"),
    "cursor": { "x": Json::number(x), "y": Json::number(y), "shape": Json::string(shape) },
  })
  self.t.draw()
}

///|
test "the screen's pointer is drawn in the station's shape, the point it points with where the station's pointer is" {
  let r = screen_rig()
  // a desktop's screen on a phone: a trackpad, the station's pointer drawn over it
  r.state("live", others=[], more={ "kind": "desktop" })
  r.config()
  r.frame(1000.0)
  assert_true(r.sess().pad(r.sess().src))
  let seen : Map[String, Bool] = Map::new()
  for shape in ["default", "text", "pointer", "ew-resize", "nwse-resize", "move", "crosshair", "not-allowed", "wait"] {
    r.cursor_at(0.5, 0.5, shape)
    let (src, x, y, w) = drawn_pointer(r).unwrap()
    // its own image, the same size as the arrow's
    assert_false(seen.contains(src), msg="\{shape}: \{src} drawn for another shape too")
    seen[src] = true
    assert_eq(w, @sf.pointer_size)
    // where the station's pointer is: the arrow's tip, a hand's fingertip, the middle of the others
    let (px, py) = r.at(0.5, 0.5)
    let (hx, hy) = @sf.pointer_hotspot(shape)
    assert_true(close_to(x + hx, px) && close_to(y + hy, py), msg="\{shape} at \{x}, \{y}")
  }
  // the arrow's tip where it points, a text cursor's middle
  assert_eq(@sf.pointer_hotspot("default"), (@sf.pointer_tip, @sf.pointer_tip))
  assert_eq(@sf.pointer_hotspot("text"), (@sf.pointer_size / 2.0, @sf.pointer_size / 2.0))
  // a shape it has none of its own for: the arrow
  r.cursor_at(0.5, 0.5, "default")
  let arrow = drawn_pointer(r).unwrap().0
  r.cursor_at(0.5, 0.5, "zoom-in")
  assert_eq(drawn_pointer(r).unwrap().0, arrow)
  screen_done(r.t)
}

///|
test "only looking, the station's pointer hidden there (none) is drawn nowhere; shown again, where it is" {
  let r = screen_rig()
  r.state("live", control=false, others=[], more={ "kind": "desktop" })
  r.config()
  r.frame(1000.0)
  let hide = fn(shape : String) {
    r.state("live", control=false, others=[], more={
      "kind": Json::string("desktop"),
      "cursor": { "x": Json::number(0.25), "y": Json::number(0.75), "shape": Json::string(shape) },
    })
    r.t.draw()
  }
  hide("none")
  assert_true(drawn_pointer(r) is None)
  hide("text")
  let (_, x, y, _) = drawn_pointer(r).unwrap()
  let (px, py) = r.at(0.25, 0.75)
  assert_true(close_to(x + @sf.pointer_size / 2.0, px) && close_to(y + @sf.pointer_size / 2.0, py))
  screen_done(r.t)
}

///|
/// A desktop's screen as H.264 on a host whose pictures show on their own layer (@ui.Stream::layered): its config and
/// its first frame shown.
fn ScreenRig::layered(self : ScreenRig, control? : Bool = false) -> @ui.Stream {
  self.t.set_stream_layers(true)
  self.state("live", control~, others=[], more={
    "kind": Json::string("desktop"),
    "cursor": { "x": Json::number(0.5), "y": Json::number(0.5), "shape": Json::string("default") },
  })
  self.say({ "config": { "codec": "h264", "width": rig_w, "height": rig_h } }, bytes=b"avcc")
  let st = self.sess().stream.unwrap()
  self.say({ "frame": { "key": true, "ts": 1000.0 } }, bytes=b"\x00\x00\x00\x01\x65")
  self.t.stream_shows(st.id(), 1000.0, rig_w.to_int(), rig_h.to_int())
  self.t.draw()
  st
}

///|
/// The state the view has now, its pointer at (x, y) in `shape` (the rest as it was): a value of the view.
fn ScreenRig::cursor_moved(self : ScreenRig, x : Double, y : Double, shape? : String = "default") -> Json {
  guard self.sess().state is Some(Object(m)) else { abort("no state") }
  let m = m.copy()
  m["cursor"] = { "x": Json::number(x), "y": Json::number(y), "shape": Json::string(shape) }
  { "state": Json::object(m) }
}

///|
/// What the stream's host was told of its pointer, oldest first.
fn pointer_told(r : ScreenRig, st : @ui.Stream) -> Array[String] {
  r.t.stream_fed(st.id()).filter(fn(l) { l.has_prefix("pointer") })
}

///|
test "on a host whose pictures show on their own layer, the station's pointer is drawn there: a move builds nothing, the host told where" {
  let r = screen_rig(h264=true)
  let st = r.layered()
  assert_true(st.layered())
  // not drawn over the frame: on the picture's layer, in the station's shape, where it points
  assert_true(drawn_pointer(r) is None)
  let (arrow, _) = @sf.pointer_png(r.t.ctx(), shape="default")
  assert_eq(pointer_told(r, st), ["pointer \{arrow} 20x20 hot=1,1", "pointer at 0.5 0.5"])
  // the station's pointer moves: a value the core takes as it comes (screen_value_quiet), the host told at once,
  // nothing built for it
  // (the display's next frame after the test's own drawing: laid out as it was drawn)
  r.t.frame_at(r.t.next_frame_time())
  let moved = r.cursor_moved(0.25, 0.75)
  assert_true(screen_value_quiet(moved))
  let (on_value, _) = r.views[r.views.length() - 1]
  on_value(moved, None)
  assert_eq(pointer_told(r, st).last(), Some("pointer at 0.25 0.75"))
  r.t.frame_at(r.t.next_frame_time())
  assert_eq(r.t.built_why(), "")
  assert_true(drawn_pointer(r) is None)
  // another shape: built, its picture told
  let text = r.cursor_moved(0.25, 0.75, shape="text")
  assert_false(screen_value_quiet(text))
  r.say(text)
  let (ibeam, _) = @sf.pointer_png(r.t.ctx(), shape="text")
  assert_eq(pointer_told(r, st).last(), Some("pointer \{ibeam} 20x20 hot=10,10"))
  // anything else of the state changed with it: not quiet, built
  guard r.sess().state is Some(Object(m)) else { abort("no state") }
  let m = m.copy()
  m["title"] = Json::string("another")
  m["cursor"] = { "x": Json::number(0.3), "y": Json::number(0.3), "shape": Json::string("text") }
  assert_false(screen_value_quiet({ "state": Json::object(m) }))
  // hidden on the station: none on the layer
  r.say(r.cursor_moved(0.3, 0.3, shape="none"))
  assert_eq(pointer_told(r, st).last(), Some("pointer none"))
  screen_done(r.t)
}

///|
test "driving it as a trackpad on a layered host, the finger's pointer is on the layer; the station's word on it moves nothing, builds nothing" {
  let r = screen_rig(h264=true)
  let st = r.layered(control=true)
  assert_true(r.sess().pad(r.sess().src))
  assert_eq(pointer_told(r, st).last(), Some("pointer at 0.5 0.5"))
  // a finger moved right: the pointer on the layer with it
  let (ax, ay) = r.at(0.2, 0.5)
  let (bx, by) = r.at(0.4, 0.5)
  r.t.drag(ax, ay, bx, by)
  let (px, _) = r.ui().pad.at()
  assert_true(px > 0.55)
  assert_eq(pointer_told(r, st).last(), Some("pointer at \{px} 0.5"))
  assert_true(drawn_pointer(r) is None)
  // the station says where it is (behind the finger): nothing built, the layer's pointer the finger's still
  let told = pointer_told(r, st).length()
  let moved = r.cursor_moved(0.3, 0.5)
  assert_true(screen_value_quiet(moved))
  let (on_value, _) = r.views[r.views.length() - 1]
  on_value(moved, None)
  r.t.frame_at(r.t.next_frame_time())
  assert_eq(r.t.built_why(), "")
  assert_eq(pointer_told(r, st).length(), told)
  screen_done(r.t)
}

///|
test "where pictures are drawn by the app, the station's pointer is drawn over the frame and each move of it is built" {
  let r = screen_rig()
  r.state("live", control=false, others=[], more={
    "kind": Json::string("desktop"),
    "cursor": { "x": Json::number(0.5), "y": Json::number(0.5), "shape": Json::string("default") },
  })
  r.config()
  r.frame(1000.0)
  assert_true(drawn_pointer(r) is Some(_))
  assert_false(r.sess().stream.unwrap().layered())
  assert_false(screen_value_quiet(r.cursor_moved(0.25, 0.75)))
  screen_done(r.t)
}
