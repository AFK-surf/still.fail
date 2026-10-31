// The window's content zoom. The host still receives and reports places in window points; the UI lays out in points
// divided by the zoom, and the renderer draws those points at the corresponding number of screen pixels.

///|
let window_zoom_wanted : @signals.Signal[Double] = @signals.signal(1.0, same=fn(a, b) { a == b })

///|
// The zoom of the frame actually being built (or last shown), which can differ from the next frame's requested zoom.
let window_zoom_drawn : Ref[Double] = Ref(1.0)

///|
// An app's window-wide keys are taken before a page, field or modal layer routes its own keys.
let window_key_handler : Ref[((Int, Int) -> Bool)?] = Ref(None)

///|
pub fn set_window_key_handler(f : (Int, Int) -> Bool) -> Unit {
  window_key_handler.val = Some(f)
}

///|
pub fn window_zoom() -> Double {
  window_zoom_wanted.get()
}

///|
/// Whether this host draws and routes input at the window's content zoom.
pub fn window_zoom_supported() -> Bool {
  platform() == 0 || platform() == 3
}

///|
/// A length in the host window's points, as much space as it takes in the frame's content points.
pub fn window_points_to_content(points : Double) -> Double {
  points / window_zoom_drawn.val
}

///|
/// Ask for the next frame at this zoom; the frame in progress and its input keep the scale they started at.
pub fn set_window_zoom(zoom : Double) -> Unit {
  if !window_zoom_supported() || zoom <= 0.0 || zoom == @signals.untracked(fn() { window_zoom_wanted.get() }) {
    return
  }
  window_zoom_wanted.set(zoom)
  if fake.val is None {
    @hostapi.set_window_zoom(zoom)
  }
  // The scale is taken at the start of a frame, so a change made during it belongs to the next one.
  g().owe_next()
}

///|
fn window_zoom_reset() -> Unit {
  window_zoom_wanted.set(1.0)
  window_zoom_drawn.val = 1.0
  tree_window_zoom.set(1.0)
  window_key_handler.val = None
}

///|
fn host_pointer(kind : Int, x : Double, y : Double, button : Int) -> Unit {
  let z = window_zoom_drawn.val
  on_pointer(kind, x / z, y / z, button)
}

///|
fn host_wheel(x : Double, y : Double, dx : Double, dy : Double, phase : Int) -> Unit {
  let z = window_zoom_drawn.val
  // A pinch is an amount of magnification, not a distance on the window.
  let delta = if (phase / 16 & wheel_mod_pinch) != 0 { 1.0 } else { z }
  on_wheel(x / z, y / z, dx / delta, dy / delta, phase)
}
