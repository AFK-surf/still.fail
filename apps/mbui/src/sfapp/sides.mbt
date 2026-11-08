// What the system has at the window's sides (@ui.system_bars `left` and `right`: iOS's view runs from side to side,
// and an iPhone Duo's outer screen has its status bar down its right side, iOS 27.1; a phone on its side its cutout):
// the app's pages beside it, the page's paper under it (a top bar has no line along its foot to carry under it: its
// frost over the paper alone is the paper). Turned sideways for a film or a screen over all of it
// (@hostapi.turned_sideways) it is over the whole window, its black to the screen's edges as a film app's is, what
// floats over it keeping clear of the sides itself (@sf.sides_clear).

///|
/// The room kept at the window's left and right beside the system's bars there (none beside the system's tab bar, the
/// frame from side to side under it: what is pressed at a page's top and foot keeps clear of it, @sf.native_clear; none
/// on a phone turned on its side for a film).
fn sides_room() -> (Double, Double) {
  let b = @ui.system_bars()
  let (left, right) = (dmax(0.0, b.left), dmax(0.0, b.right))
  if (@sf.native_on() && left == 0.0) || (left == 0.0 && right == 0.0) || @hostapi.turned_sideways() {
    (0.0, 0.0)
  } else {
    (left, right)
  }
}
