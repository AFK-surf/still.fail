// A still image through the same offscreen renderer and live text as film, without a movie encoder.

///|
/// Render a scene to a PNG at `w` × `h` logical points and `scale` pixels per point. `tree` is the same window tree
/// used by a film; `prepare` and `script` perform drive steps before capture and `at` is milliseconds after them. With
/// `frame`, capture that frame of `script` instead (frame 0 is before its first step); `at` must then be zero. The frame
/// is built by the Tester with the native host's text and pictures, then drawn by the host's offscreen renderer. Returns false if
/// the dimensions are invalid, the host has no renderer, an image failed or is still pending, or the PNG cannot be
/// written. `transparent` clears the output's ground to transparent while keeping the scene's own shapes and their
/// alpha. The theme's corner rule and word overlap are checked unless the view opts out. A view that deliberately
/// depicts an exception can accept precisely its expected corner faults with `corner_faults_ok`.
pub fn picture(
  view : (@ui.Ctx) -> Unit,
  tree? : (@view.View) -> Unit,
  path~ : String,
  w~ : Double,
  h~ : Double,
  scale? : Double = 2.0,
  platform? : Int = 0,
  dark? : Bool = false,
  inset? : Bool = false,
  window_corner? : Double = 0.0,
  prepare? : String = "",
  script? : String = "",
  at? : Double = 0.0,
  frame? : Int,
  fps? : Int = film_fps,
  max? : Int = 3000,
  transparent? : Bool = false,
  corners_held? : Bool = true,
  corner_faults_ok? : (Array[String]) -> Bool = fn(faults) { faults.is_empty() },
  words_over_held? : Bool = true,
) -> Bool {
  if !supported || path == "" || w <= 0.0 || h <= 0.0 || scale <= 0.0 ||
     w.is_nan() || h.is_nan() || scale.is_nan() || w.is_inf() || h.is_inf() || scale.is_inf() ||
     at < 0.0 || at.is_nan() || at.is_inf() || fps <= 0 || max <= 0 ||
     (frame is Some(k) && (k < 0 || at > 0.0 || script == "")) {
    say("picture: an output path, positive finite size, non-negative time and a supported host are required")
    return false
  }
  let t = scene_tester(
    view,
    tree?,
    w~,
    h~,
    scale~,
    platform~,
    dark~,
    inset~,
    window_corner~,
    corners_held=false,
    words_over_held~,
  )
  t.set_frame_period(1000.0 / fps.to_double())
  let mut ran = false
  if prepare != "" {
    ran = true
    let logs = t.drive(prepare, max~)
    if !drive_passed(logs) {
      for l in logs {
        if l.has_prefix("DRIVE") {
          say(l)
        }
      }
      say("picture: scene preparation did not pass")
      return false
    }
  }
  if script != "" {
    ran = true
    match frame {
      Some(k) => {
        let (reached, logs) = t.film_frame(script, k, max~)
        if !reached {
          for l in logs {
            if l.has_prefix("DRIVE") {
              say(l)
            }
          }
          say("picture: scene did not reach frame \{k}")
          return false
        }
      }
      None => {
        let logs = t.drive(script, max~)
        if !drive_passed(logs) {
          for l in logs {
            if l.has_prefix("DRIVE") {
              say(l)
            }
          }
          say("picture: scene steps did not pass")
          return false
        }
      }
    }
  }
  if !ran && (inset || arg("MBUI_FONT_SCALE") != "" || arg("MBUI_LOCAL_STATION") != "") {
    // These settings take effect on the next frame, even when there is no preparation script.
    t.draw()
  }
  if at > 0.0 {
    t.run_for_exact(at)
  }
  // Check the captured frame explicitly so a bad corner reports why and returns false instead of aborting the process.
  if corners_held {
    let faults = t.corner_faults()
    if !corner_faults_ok(faults) {
      if faults.is_empty() {
        say("picture: the expected corner faults were not found")
      }
      for fault in faults {
        say("picture: \{fault}")
      }
      return false
    }
  }
  if !t.pending().is_empty() {
    say("picture: images or native views are still pending")
    return false
  }
  let failed = t.failed_images()
  if !failed.is_empty() {
    for id in failed {
      say("picture: image could not be decoded: \{t.image_src(id)}")
    }
    return false
  }
  // A native web or video view is a hole in mbui's canvas: the native view is not part of this offscreen renderer.
  if !t.holes().is_empty() {
    say("picture: native view content cannot be drawn offscreen")
    return false
  }
  let buf = Ref::new(FixedArray::make(0, 0.0))
  let (n, (r, g, b)) = host_frame(t, buf)
  let times = FixedArray::make(2, 0.0)
  draw_timed(buf.val, n, r, g, b, [(0.0, 0.0, -1.0, -1.0)], times)
  let saved = if transparent { snapshot_transparent(path) } else { snapshot(path) }
  if !saved {
    say("picture: could not write \{path}")
    return false
  }
  say("picture: \{path} (\{(w * scale).round().to_int()} × \{(h * scale).round().to_int()})")
  true
}

///|
/// The same program and arguments as `run`, with MBUI_PICTURE selecting a PNG instead of a film.
fn run_picture(view : (@ui.Ctx) -> Unit, tree? : (@view.View) -> Unit) -> Unit {
  let path = arg("MBUI_PICTURE")
  let prepare_path = arg("MBUI_FILM_PREPARE")
  let drive_path = arg("MBUI_FILM_DRIVE")
  let prepare = if prepare_path == "" { "" } else { read_text(prepare_path) }
  let script = if drive_path == "" { "" } else { read_text(drive_path) }
  if prepare_path != "" && prepare == "" || drive_path != "" && script == "" {
    say("picture: a scene script could not be read")
    exit(2)
    return
  }
  let (w, h) = match arg("MBUI_WIN").split("x").map(fn(p) { number(p.to_owned()) }).to_array() {
    [Some(w), Some(h)] if w > 0.0 && h > 0.0 => (w, h)
    _ => (390.0, 844.0)
  }
  let at = match arg("MBUI_PICTURE_AT") {
    "" => 0.0
    value =>
      match number(value) {
        Some(n) if n >= 0.0 && !n.is_nan() && !n.is_inf() => n
        _ => {
          say("picture: MBUI_PICTURE_AT must be a non-negative time in milliseconds")
          exit(2)
          return
        }
      }
  }
  let fps = match frame_rate_arg() {
    Some(fps) => fps
    None => {
      say("picture: MBUI_FILM_FPS must be a positive whole number")
      exit(2)
      return
    }
  }
  let frame : Int? = match arg("MBUI_PICTURE_FRAME") {
    "" => None
    value =>
      match number(value) {
        Some(n) if n >= 0.0 && n <= 2147483647.0 && n == n.floor() => Some(n.to_int())
        _ => {
          say("picture: MBUI_PICTURE_FRAME must be a non-negative whole number")
          exit(2)
          return
        }
      }
  }
  let ok = picture(
    view,
    tree?,
    path~,
    w~,
    h~,
    scale=number(arg("MBUI_FILM_SCALE")).unwrap_or(2.0),
    platform=number(arg("MBUI_FILM_PLATFORM")).unwrap_or(0.0).to_int(),
    dark=arg("MBUI_DARK") == "1",
    inset=arg("MBUI_FILM_INSET") == "1",
    window_corner=number(arg("MBUI_FILM_WINDOW_CORNER")).unwrap_or(0.0),
    prepare~,
    script~,
    at~,
    frame?,
    fps~,
    max=number(arg("MBUI_FILM_FRAMES")).unwrap_or(3000.0).to_int(),
    transparent=arg("MBUI_PICTURE_TRANSPARENT") == "1",
    words_over_held=false,
  )
  exit(if ok { 0 } else { 1 })
}
