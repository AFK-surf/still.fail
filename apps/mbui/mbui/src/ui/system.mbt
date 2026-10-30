// The system's bars over the app's view (the status bar, the navigation bar, a cutout), as the host says them on
// @hostapi.system_channel (`bars`: over another app, or edge to edge): kept here as each message comes, before the
// app's own handler of the channel is given it, so a view pads by them (system_bars) without reading the message
// itself. 0 where the host lays the view out inside them, and in a Tester until a test posts them. So are the window's
// size classes (`size_class`: system_size_class) and the hinge with where its fold divides the view (`fold`:
// system_fold, system_tabletop): what the system says of the window's room and the device's pose, which a layout is
// chosen by, never worked out from the window's width or its shape. None said (a host that says none, a Tester until a
// test posts them): no size classes, no hinge.

///|
/// How far the system bars reach in over the view from each edge, in points.
pub(all) struct SystemBars {
  top : Double
  bottom : Double
  left : Double
  right : Double
} derive(Eq, Show)

///|
/// The bars as the host last said them (none: all 0), a signal: what is laid out by them (the window's tree's sides)
/// follows them. Put back by each Tester (messages_reset).
// kept across runs: put back as a run begins (messages_reset)
let system_bars_now : @signals.Signal[SystemBars] = @signals.signal(
  { top: 0.0, bottom: 0.0, left: 0.0, right: 0.0 },
  same=fn(a, b) { a == b },
)

///|
/// How far the system bars reach in over the view now (`top`: the status bar's, `bottom`: the navigation bar's, or
/// the keyboard's top under it), as the host last said them.
pub fn system_bars() -> SystemBars {
  system_bars_now.get()
}

///|
/// A message on the system's channel, as it comes: the bars, the size classes and the fold it says kept.
fn system_took(json : String) -> Unit {
  for said in @hostapi.system_said(json) {
    match said {
      Bars(top~, bottom~, left~, right~) => system_bars_now.set({ top, bottom, left, right })
      SizeClasses(width~, height~) => system_size_class_now.val = Some({ width, height })
      Fold(hinge~, divisions~) => system_fold_now.set({ hinge, divisions })
      NavAction(x~, y~, w~, h~) => system_nav_action_now.val = if w > 0.0 && h > 0.0 { Some((x, y, w, h)) } else { None }
      _ => ()
    }
  }
}

///|
/// Where the system's bars put the app's action of its own (`nav_action`), as the host last said it. Put back by each
/// Tester (messages_reset).
let system_nav_action_now : Ref[(Double, Double, Double, Double)?] = Ref::new(None)

///|
/// Where the system's bars put the app's action of its own in the view (x, y, w, h: iOS 27's prominent tab, an iPhone
/// Duo's round one at its column's foot), as the host last said it: None where none is shown, from a host that says
/// none, and in a Tester until a test posts it.
pub fn system_nav_action() -> (Double, Double, Double, Double)? {
  system_nav_action_now.val
}

///|
/// How much room the window has, as the system classes it (@hostapi.system_channel `size_class`).
pub(all) struct SystemSizeClass {
  width : @hostapi.SizeClass
  height : @hostapi.SizeClass
} derive(Eq, Show)

///|
/// The size classes as the host last said them (none yet: None). Put back by each Tester (messages_reset).
let system_size_class_now : Ref[SystemSizeClass?] = Ref::new(None)

///|
/// How much room the window has as the system classes it, as the host last said it: None from a host that says none
/// (a desktop's, the web's) and in a Tester until a test posts it.
pub fn system_size_class() -> SystemSizeClass? {
  system_size_class_now.val
}

///|
/// The device's hinge and where its fold divides the view (@hostapi.system_channel `fold`).
pub(all) struct SystemFold {
  hinge : @hostapi.Hinge
  /// where the fold divides the view now (x, y, w, h in the view's points), the margins the system keeps round it in
  divisions : Array[(Double, Double, Double, Double)]
} derive(Eq, Show)

///|
/// The hinge as the host last said it (none yet: no hinge). Put back by each Tester (messages_reset).
// kept across runs: put back as a run begins (messages_reset); a signal: what is laid out by the pose (which frame a
// half-open fold calls for) follows it
let system_fold_now : @signals.Signal[SystemFold] = @signals.signal(
  { hinge: NoHinge, divisions: [] },
  same=fn(a, b) { a == b },
)

///|
/// The device's hinge and where its fold divides the view, as the host last said them.
pub fn system_fold() -> SystemFold {
  system_fold_now.get()
}

///|
/// The fold across the view of a device half open on its back half (a laptop's pose, Android's tabletop): the hinge
/// partly open, a division wider than it is tall: its top and its foot, in the view's points. None otherwise (open
/// flat, closed, the fold upright between two halves side by side, no hinge).
pub fn system_tabletop() -> (Double, Double)? {
  let f = system_fold_now.get()
  guard f.hinge is Half else { return None }
  for d in f.divisions {
    let (_, y, w, h) = d
    if w > h {
      return Some((y, y + h))
    }
  }
  None
}
