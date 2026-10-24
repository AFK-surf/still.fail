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
/// The bars as the host last said them (none: all 0). Put back by each Tester (messages_reset).
let system_bars_now : Ref[SystemBars] = Ref::new({ top: 0.0, bottom: 0.0, left: 0.0, right: 0.0 })

///|
/// How far the system bars reach in over the view now (`top`: the status bar's, `bottom`: the navigation bar's, or
/// the keyboard's top under it), as the host last said them.
pub fn system_bars() -> SystemBars {
  system_bars_now.val
}

///|
/// A message on the system's channel, as it comes: the bars, the size classes and the fold it says kept.
fn system_took(json : String) -> Unit {
  for said in @hostapi.system_said(json) {
    match said {
      Bars(top~, bottom~, left~, right~) => system_bars_now.val = { top, bottom, left, right }
      SizeClasses(width~, height~) => system_size_class_now.val = Some({ width, height })
      Fold(hinge~, divisions~) => system_fold_now.val = { hinge, divisions }
      _ => ()
    }
  }
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
let system_fold_now : Ref[SystemFold] = Ref::new({ hinge: NoHinge, divisions: [] })

///|
/// The device's hinge and where its fold divides the view, as the host last said them.
pub fn system_fold() -> SystemFold {
  system_fold_now.val
}

///|
/// The fold across the view of a device half open on its back half (a laptop's pose, Android's tabletop): the hinge
/// partly open, a division wider than it is tall: its top and its foot, in the view's points. None otherwise (open
/// flat, closed, the fold upright between two halves side by side, no hinge).
pub fn system_tabletop() -> (Double, Double)? {
  let f = system_fold_now.val
  guard f.hinge is Half else { return None }
  for d in f.divisions {
    let (_, y, w, h) = d
    if w > h {
      return Some((y, y + h))
    }
  }
  None
}
