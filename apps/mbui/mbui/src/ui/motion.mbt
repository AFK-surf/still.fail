// Curves as CSS has them (cubic-bezier), played as Compose's CubicBezierEasing plays them, for motion timed rather
// than sprung: still.fail's (its Android app's ui/Motion.kt and the web's styles) are named here. The one set of
// them: a page pushed (nav), a state moved (move_state), a scrollbar's fade, and @motion's tweens.

///|
/// CSS's cubic-bezier(x1, y1, x2, y2) at `t` (0-1 of the time), as Compose's CubicBezierEasing finds it: how far
/// along (0-1). (Motion's own solver, as an easing: @motion.cubic_bezier.)
fn bezier_at(x1 : Double, y1 : Double, x2 : Double, y2 : Double, t : Double) -> Double {
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
    if e.abs() < 1.0e-7 {
      found = true
      break
    }
    let d = (3.0 * ax * s + 2.0 * bx) * s + cx
    if d.abs() < 1.0e-6 {
      break
    }
    s = s - e / d
  }
  if !found || s < 0.0 || s > 1.0 {
    let mut lo = 0.0
    let mut hi = 1.0
    s = t
    for _ in 0..<60 {
      let x = x_at(s)
      if (x - t).abs() < 1.0e-9 {
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
/// A curve by name, for what is timed (Motion.kt Ease, Compose's own; Motion's `ease`).
pub(all) enum Ease {
  /// (.4, 0, .2, 1), Compose's FastOutSlowIn, Ease.Standard, the web's
  /// --m-standard: pages pushed and popped, the jump button's growing
  Standard
  /// (.2, .8, .2, 1), Ease.Arrive, --m-ease: sheets, pages rising
  Arrive
  /// (.2, .7, .2, 1), Ease.Out, --ease-out: a list's rows coming in, folding
  Out
  /// (.25, .46, .45, .94), easeOutQuad: what goes on from where a finger
  /// let it go (a page swiped back)
  LetGo
  Linear
  /// (.6, 0, .2, 1), Ease.Flight: words sent on their way to their row
  Flight
  /// (0, 0, .58, 1), CSS's keyword ease-out (Ease.CssOut)
  CssOut
  /// (.25, .1, .25, 1), CSS's keyword ease (Ease.Css): a scrim, a toast
  Css
  /// (0, 0, .2, 1), Compose's LinearOutSlowIn (Ease.Decel)
  Decel
  /// (.3, 0, .5, 1), Ease.LeaveFade: what leaves by fading
  LeaveFade
  /// (.42, 0, .58, 1), Compose's EaseInOut, CSS's ease-in-out
  InOut
  /// (.16, 1, .3, 1), Chat.kt ArchiveEase: a quick start, a soft landing
  Soft
  /// (.4, 0, 1, 1), Compose's FastOutLinearIn
  Accelerate
  /// any other cubic-bezier
  Bezier(Double, Double, Double, Double)
} derive(Eq, Show)

///|
/// The curve at `t` (0-1 of the time).
pub fn Ease::at(self : Ease, t : Double) -> Double {
  match self {
    Standard => bezier_at(0.4, 0.0, 0.2, 1.0, t)
    Arrive => bezier_at(0.2, 0.8, 0.2, 1.0, t)
    Out => bezier_at(0.2, 0.7, 0.2, 1.0, t)
    LetGo => bezier_at(0.25, 0.46, 0.45, 0.94, t)
    Linear => dclamp(t, 0.0, 1.0)
    Flight => bezier_at(0.6, 0.0, 0.2, 1.0, t)
    CssOut => bezier_at(0.0, 0.0, 0.58, 1.0, t)
    Css => bezier_at(0.25, 0.1, 0.25, 1.0, t)
    Decel => bezier_at(0.0, 0.0, 0.2, 1.0, t)
    LeaveFade => bezier_at(0.3, 0.0, 0.5, 1.0, t)
    InOut => bezier_at(0.42, 0.0, 0.58, 1.0, t)
    Soft => bezier_at(0.16, 1.0, 0.3, 1.0, t)
    Accelerate => bezier_at(0.4, 0.0, 1.0, 1.0, t)
    Bezier(a, b, c, d) => bezier_at(a, b, c, d, t)
  }
}
