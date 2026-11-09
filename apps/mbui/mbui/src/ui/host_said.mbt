// What a frame is drawn by that is the host's, one signal each, read where it is used: what read one, and only that, is
// built, laid out or painted again as it changes (a list's row or a part kept as its own watch follows it too).
//
// The host's settings (the system's dark, its size of words, whether something reads the widgets out, reduced motion,
// solid glass, what decodes a stream, the window's buttons in the top row, the window maximized and how the pointer
// stands on its maximize button the app draws): each asked of the host as each frame begins
// (host_settings_arrive), and as it is asked between frames. What the frame is drawn on (the window's size, its pixels,
// what the host measures words in, where the old views are laid out): as frame_drawn begins it (frame_settings_arrive).

///|
/// A setting of the host's: its signal (as the frame has it), how it is asked of the host, what else is told as it
/// changes.
priv struct HostSaid[T] {
  said : @signals.Signal[T]
  ask : () -> T
  told : () -> Unit
}

///|
fn[T : Eq] host_said(first : T, ask : () -> T, told? : () -> Unit = fn() { () }) -> HostSaid[T] {
  { said: @signals.signal(first, same=fn(a, b) { a == b }), ask, told }
}

///|
/// Asked of the host: its signal set where it changed (what read it told), and what else is told so.
fn[T : Eq] HostSaid::arrive(self : HostSaid[T]) -> Unit {
  let now = (self.ask)()
  if self.said.untracked() != now {
    self.said.set(now)
    (self.told)()
  }
}

///|
/// The setting as the frame has it, followed; asked of the host again where no frame is being drawn (between frames,
/// before the first: a handler's, a Tester's).
fn[T : Eq] HostSaid::now(self : HostSaid[T]) -> T {
  if !frame_running.val {
    self.arrive()
  }
  self.said.get()
}

///|
/// Whether the window's buttons are in the app's top row (window_inset).
// kept across runs: put back by each Tester (host_settings_arrive as its first frame begins)
let inset_said : HostSaid[Bool] = host_said(false, fn() { @hostapi.window_inset() })

///|
/// Whether the window is maximized (window_zoomed).
// kept across runs: put back by each Tester (host_settings_arrive as its first frame begins)
let zoomed_said : HostSaid[Bool] = host_said(false, fn() { @hostapi.window_zoomed() })

///|
/// How the pointer stands on the window's maximize button the app draws (window_snap_state).
// kept across runs: put back by each Tester (host_settings_arrive as its first frame begins)
let snap_said : HostSaid[Int] = host_said(0, fn() { @hostapi.window_snap_state() })

///|
/// Whether the system is set to dark (system_dark).
// kept across runs: put back by each Tester (host_settings_arrive as its first frame begins)
let dark_said : HostSaid[Bool] = host_said(false, fn() { @hostapi.system_dark() })

///|
/// The system's size of words (font_scale); the window's tree's words measured again as it changes.
// kept across runs: put back by each Tester (host_settings_arrive as its first frame begins)
let words_size_said : HostSaid[Double] = host_said(
  1.0,
  fn() {
    let fs = @hostapi.font_scale()
    if fs > 0.0 {
      fs
    } else {
      1.0
    }
  },
  told=view_words_rescaled,
)

///|
/// Whether something reads the widgets out (reads_out).
// kept across runs: put back by each Tester (host_settings_arrive as its first frame begins)
let reads_out_said : HostSaid[Bool] = host_said(false, h_a11y_on)

///|
/// Whether motion is reduced (reduced_motion).
// kept across runs: put back by each Tester (host_settings_arrive as its first frame begins)
let motion_reduced_said : HostSaid[Bool] = host_said(false, motion_reduced_asked)

///|
/// Whether glass is drawn solid as the system says (Ctx::glass_solid).
// kept across runs: put back by each Tester (host_settings_arrive as its first frame begins)
let glass_solid_said : HostSaid[Bool] = host_said(false, h_reduce_transparency)

///|
/// Whether the host decodes H.264 (h264_here), drives its decoder from here (stream_feeds), has a video layer
/// (stream_layers).
// kept across runs: put back by each Tester (host_settings_arrive as its first frame begins)
let h264_said : HostSaid[Bool] = host_said(false, fn() { @hostapi.h264_here() })

///|
// kept across runs: put back by each Tester (host_settings_arrive as its first frame begins)
let feeds_said : HostSaid[Bool] = host_said(false, fn() { @hostapi.stream_feeds() })

///|
// kept across runs: put back by each Tester (host_settings_arrive as its first frame begins)
let layers_said : HostSaid[Bool] = host_said(false, fn() { @hostapi.stream_layers() })

///|
/// The host's settings, each asked as the frame begins (on_frame, before the window's tree is brought): what read one
/// that changed is told.
fn host_settings_arrive() -> Unit {
  inset_said.arrive()
  zoomed_said.arrive()
  snap_said.arrive()
  dark_said.arrive()
  words_size_said.arrive()
  reads_out_said.arrive()
  motion_reduced_said.arrive()
  glass_solid_said.arrive()
  h264_said.arrive()
  feeds_said.arrive()
  layers_said.arrive()
}

///|
/// Whether something reads the widgets out (the system's accessibility, @hostapi.a11y_on), as the frame has it,
/// followed.
fn reads_out() -> Bool {
  reads_out_said.now()
}

///|
/// The window's size the frame is built and laid out in (frame_body), as frame_drawn begins it: what is built for it
/// (the frame's root) built again as it changes.
// kept across runs: set as each frame begins
let window_size : @signals.Signal[(Double, Double)] = @signals.signal((0.0, 0.0), same=fn(a, b) { a == b })

///|
/// The grid of the device's pixels the frame is laid out on (its scale; whether the host sets things on whole pixels:
/// whole_px_layout), as frame_drawn begins it: what is built for it (the frame's root: Ctx::scale, Ctx::whole_px) built
/// again as it changes; what was laid out on another (a node, a row kept as laid out) laid out again.
// kept across runs: set as each frame begins
let pixel_grid : @signals.Signal[(Double, Bool)] = @signals.signal((0.0, false), same=fn(a, b) { a == b })

///|
/// What the frame is drawn on, as it begins (frame_drawn): the window `w` × `h` at `scale`; what the host measures words
/// in (its glyphs' generation: text_arrive); where the old views are laid out (old_laid_arrive).
fn frame_settings_arrive(w : Double, h : Double, scale : Double) -> Unit {
  window_size.set((w, h))
  pixel_grid.set((scale, whole_px_layout()))
  atlas_said.val = Some(h_atlas_generation())
  text_arrive()
  old_laid_arrive()
}

///|
/// The window's frame built and laid out (frame_body) in the window and on the pixels it is drawn on as it began, read
/// so: built again as the window's size or its pixels change.
fn frame_body_drawn(c : Ctx, t : Double, tell? : Bool = true) -> Double {
  let (w, h) = window_size.get()
  let (scale, _) = pixel_grid.get()
  frame_body(c, w, h, scale, t, tell~)
}
