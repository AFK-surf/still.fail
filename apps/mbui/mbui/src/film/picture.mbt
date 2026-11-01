// A still image through the same offscreen renderer and live text as film, without a movie encoder.

///|
/// Render a view to a PNG at `w` × `h` logical points and `scale` pixels per point. Its first frame is built by the
/// Tester with the native host's text and pictures, then drawn by the host's own offscreen renderer. Returns false if
/// the dimensions are invalid, the host has no renderer, an image failed or is still pending, or the PNG cannot be
/// written. The theme's corner rule and word overlap are checked unless the view opts out. A view that deliberately
/// depicts an exception can accept precisely its expected corner faults with `corner_faults_ok`. A view that marks
/// where its own words were drawn (a highlight on a line's letters) reads them in `settle`, given the first frame's
/// tester: when it returns true, the frame is built and drawn once more, and that frame is the picture.
pub fn picture(
  view : (@ui.Ctx) -> Unit,
  path~ : String,
  w~ : Double,
  h~ : Double,
  scale? : Double = 2.0,
  platform? : Int = 0,
  dark? : Bool = false,
  corners_held? : Bool = true,
  corner_faults_ok? : (Array[String]) -> Bool = fn(faults) { faults.is_empty() },
  words_over_held? : Bool = true,
  settle? : (@ui.Tester) -> Bool = fn(_) { false },
) -> Bool {
  if !supported || path == "" || w <= 0.0 || h <= 0.0 || scale <= 0.0 {
    say("picture: an output path, positive size and a supported host are required")
    return false
  }
  let host = @hostapi.host()
  init_offscreen(w, h, scale)
  let t = @ui.Tester::new(
    view,
    w~,
    h~,
    scale~,
    platform~,
    dark~,
    words_over_held~,
    corners_held=false,
    live={ host, turn: fn() { spin(1.0) } },
    before=fn() { set_offscreen_view(w, h, scale) },
  )
  if settle(t) {
    t.frame()
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
  if !snapshot(path) {
    say("picture: could not write \{path}")
    return false
  }
  say("picture: \{path} (\{(w * scale).round().to_int()} × \{(h * scale).round().to_int()})")
  true
}
