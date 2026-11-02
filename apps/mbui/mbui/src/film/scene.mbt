// A single way to start a scene for an image or a film: the same view, tree, system, text, pictures and window.

///|
fn scene_tester(
  view : (@ui.Ctx) -> Unit,
  tree? : (@view.View) -> Unit,
  w~ : Double,
  h~ : Double,
  scale~ : Double,
  platform~ : Int,
  dark~ : Bool,
  inset~ : Bool,
  window_corner~ : Double,
  corners_held~ : Bool,
  words_over_held~ : Bool,
) -> @ui.Tester {
  // Take the real host before the Tester installs its own. Its text and decoded images are what the renderer draws.
  let host = @hostapi.host()
  init_offscreen(w, h, scale)
  let t = @ui.Tester::new(
    view,
    tree?,
    w~,
    h~,
    scale~,
    platform~,
    dark~,
    pointing?=match arg("MBUI_POINTING") {
      "finger" => Some(@ui.Pointing::Finger)
      "mouse" => Some(@ui.Pointing::Mouse)
      _ => None
    },
    native?=match arg("MBUI_NATIVE_INPUT") {
      "finger" => Some(@ui.Pointing::Finger)
      "mouse" => Some(@ui.Pointing::Mouse)
      _ => None
    },
    keyboard?=match arg("MBUI_KEYBOARD") {
      "1" => Some(true)
      "0" => Some(false)
      _ => None
    },
    env=[("MBUI_TEXT_RECORD", "1"), ("MBUI_LOCALE", arg("MBUI_LOCALE")), ("MBUI_DARK", arg("MBUI_DARK"))],
    corners_held~,
    words_over_held~,
    live={ host, turn: fn() { spin(1.0) } },
    before=fn() {
      let z = @ui.window_zoom()
      set_offscreen_view(w / z, h / z, scale * z)
    },
    window_corner~,
    nav_able=arg("MBUI_FILM_NAV_ABLE") == "1",
  )
  if inset {
    t.set_window_inset(true)
  }
  match number(arg("MBUI_FONT_SCALE")) {
    Some(f) if f > 0.0 => t.set_font_scale(f)
    _ => ()
  }
  match arg("MBUI_LOCAL_STATION") {
    "" => ()
    ls => t.set_local_station(ls)
  }
  t
}

///|
/// What the captured scene cannot draw. A film may show an image while it is still loading, whereas a still must
/// wait for its pending images; a failed decode needed in the frame or a native view's contents cannot be drawn.
fn scene_drawable(t : @ui.Tester, kind : String, pending_ok : Bool) -> Bool {
  if !pending_ok && !t.pending().is_empty() {
    say("\{kind}: images or native views are still pending")
    return false
  }
  let failed = t.failed_images_drawn()
  if !failed.is_empty() {
    for id in failed {
      say("\{kind}: image could not be decoded: \{t.image_src(id)}")
    }
    return false
  }
  // A native web or video view is a hole in mbui's canvas, not content this renderer can draw.
  if !t.holes().is_empty() {
    say("\{kind}: native view content cannot be drawn offscreen")
    return false
  }
  true
}
