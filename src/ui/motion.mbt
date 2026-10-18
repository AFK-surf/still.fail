// Curves as CSS has them (cubic-bezier), for motion timed rather than
// sprung: still.fail's (its Android app's ui/Motion.kt and the web's styles)
// are named here.

///|
/// CSS's cubic-bezier(x1, y1, x2, y2) at `t` (0-1 of the time): how far
/// along (0-1).
pub fn bezier(x1 : Double, y1 : Double, x2 : Double, y2 : Double, t : Double) -> Double {
  if t <= 0.0 {
    return 0.0
  }
  if t >= 1.0 {
    return 1.0
  }
  // x(s) and y(s) for s in 0-1; s found for x(s) = t by Newton's steps,
  // bisection where they would not do
  let cx = 3.0 * x1
  let bx = 3.0 * (x2 - x1) - cx
  let ax = 1.0 - cx - bx
  let cy = 3.0 * y1
  let by = 3.0 * (y2 - y1) - cy
  let ay = 1.0 - cy - by
  let x_at = fn(s : Double) { ((ax * s + bx) * s + cx) * s }
  let mut s = t
  let mut found = false
  for _ in 0..<8 {
    let e = x_at(s) - t
    if e.abs() < 1.0e-6 {
      found = true
      break
    }
    let d = (3.0 * ax * s + 2.0 * bx) * s + cx
    if d.abs() < 1.0e-6 {
      break
    }
    s = s - e / d
  }
  if !found {
    let mut lo = 0.0
    let mut hi = 1.0
    s = t
    for _ in 0..<40 {
      let x = x_at(s)
      if (x - t).abs() < 1.0e-6 {
        break
      }
      if x < t {
        lo = s
      } else {
        hi = s
      }
      s = (lo + hi) / 2.0
    }
  }
  ((ay * s + by) * s + cy) * s
}

///|
/// A curve by name, for what is timed.
pub(all) enum Curve {
  /// (.4, 0, .2, 1), Material's FastOutSlowIn, the web's --m-standard:
  /// pages pushed and popped
  Standard
  /// (.2, .8, .2, 1), --m-ease: sheets, pages rising
  Arrive
  /// (.2, .7, .2, 1), --ease-out
  Out
  /// (.25, .46, .45, .94), easeOutQuad: what goes on from where a finger
  /// let it go (a page swiped back)
  LetGo
  Linear
} derive(Eq)

///|
/// The curve at `t` (0-1 of the time).
pub fn Curve::at(self : Curve, t : Double) -> Double {
  match self {
    Standard => bezier(0.4, 0.0, 0.2, 1.0, t)
    Arrive => bezier(0.2, 0.8, 0.2, 1.0, t)
    Out => bezier(0.2, 0.7, 0.2, 1.0, t)
    LetGo => bezier(0.25, 0.46, 0.45, 0.94, t)
    Linear => dclamp(t, 0.0, 1.0)
  }
}
