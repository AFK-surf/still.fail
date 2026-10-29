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
