// Compose's numbers: curves (CSS's cubic-beziers, as Compose's CubicBezierEasing plays them), and how something
// animates (Compose's AnimationSpec): springs by damping ratio and stiffness in closed form (SpringSimulation), with
// Compose's own reckoning of how long they take (SpringEstimation), tweens of whole milliseconds on a curve. Equal,
// frame for frame, to what Compose's animation-core prints (scripts/compose_ref.sh, motion_test.mbt). Motion's own
// transitions are a Spec too (Motion: transition.mbt).

///|
/// CSS's cubic-bezier(x1, y1, x2, y2) at `t` (0-1 of the time), as Compose's CubicBezierEasing finds it: how far
/// along (0-1). (Motion's own solver, as an easing: cubic_bezier, easing.mbt.)
pub fn bezier_at(x1 : Double, y1 : Double, x2 : Double, y2 : Double, t : Double) -> Double {
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

///|
/// How something animates (Compose's AnimationSpec): a spring by damping
/// ratio, stiffness and the visibility threshold it rests within (and a
/// delay, ms, held at its start: ListMotion.kt Delayed); a tween of so many
/// ms on a curve after a delay; or there at once (after a delay).
pub(all) enum Spec {
  Spring(Double, Double, Double, Double)
  Tween(Double, Ease, Double)
  Snap(Double)
  /// one of Motion's transitions (transition.mbt: spring_to, tween_to, keyframes_to, inertia_to)
  Motion(Transition)
} derive(Eq, Show)

///|
/// Compose's spring(dampingRatio, stiffness, visibilityThreshold): by
/// default spring()'s own, critically damped at StiffnessMedium (1500), at
/// rest within 0.01.
pub fn spring(
  ratio? : Double = 1.0,
  stiffness? : Double = 1500.0,
  threshold? : Double = 0.01,
  delay? : Double = 0.0,
) -> Spec {
  Spring(ratio, stiffness, threshold, delay)
}

///|
/// Compose's tween(durationMillis, delayMillis, easing): by default
/// FastOutSlowIn (Standard).
pub fn tween(ms : Double, ease? : Ease = Standard, delay? : Double = 0.0) -> Spec {
  Tween(ms, ease, delay)
}

///|
/// Motion.kt motionSpring: a spring by its visual duration (seconds) and
/// bounce, as Motion (the web's motion library) makes it: stiffness
/// (2π / 1.2·duration)², damping ratio clamp(1 − bounce, .05, 1).
pub fn motion_spring(
  visual : Double,
  bounce? : Double = 0.0,
  threshold? : Double = 0.01,
  delay? : Double = 0.0,
) -> Spec {
  let w = 2.0 * pi / (1.2 * visual)
  Spring(dclamp(1.0 - bounce, 0.05, 1.0), w * w, threshold, delay)
}

///|
let pi : Double = 3.141592653589793

///|
/// Motion.kt MoveSpring (the web's motion.ts MOVE): what follows another
/// thing's place, a list's rows; stiffness (2π / .336)² ≈ 350, critically
/// damped, at rest within half a pixel.
// kept across runs: a constant: its fields are not mut, nothing changes it
pub let move_spring : Spec = motion_spring(0.28, threshold=0.5)

///|
/// ListMotion.kt's rows' placement: the MOVE spring as it writes it out
/// (stiffness 350, critically damped), at rest within a pixel
/// (IntOffset.VisibilityThreshold).
// kept across runs: a constant: its fields are not mut, nothing changes it
pub let row_spring : Spec = Spring(1.0, 350.0, 1.0, 0.0)

///|
/// Motion.kt SheetSpring: a sheet let go, opened or closed (motionSpring(.32),
/// at rest within half a pixel); `v` from the finger's speed.
// kept across runs: a constant: its fields are not mut, nothing changes it
pub let sheet_spring : Spec = motion_spring(0.32, threshold=0.5)

///|
/// Sheet.kt MenuSpring: the long-press menu's scale (motionSpring(.24,
/// bounce .08), at rest within .001).
// kept across runs: a constant: its fields are not mut, nothing changes it
pub let menu_spring : Spec = motion_spring(0.24, bounce=0.08, threshold=0.001)

///|
/// Where a spring is `t` seconds after it was let go `d` from its rest with
/// velocity `v` (per second): its displacement and velocity (Compose's
/// SpringSimulation.updateValues, mass 1).
pub fn spring_at(
  ratio : Double,
  stiffness : Double,
  d : Double,
  v : Double,
  t : Double,
) -> (Double, Double) {
  let w = stiffness.sqrt()
  let r = -ratio * w
  if ratio > 1.0 {
    let s = w * (ratio * ratio - 1.0).sqrt()
    let gp = r + s
    let gm = r - s
    let b = (gm * d - v) / (gm - gp)
    let a = d - b
    let ea = @math.exp(gm * t)
    let eb = @math.exp(gp * t)
    (a * ea + b * eb, a * gm * ea + b * gp * eb)
  } else if ratio == 1.0 {
    let a = d
    let b = v + w * d
    let e = @math.exp(-w * t)
    let x = (a + b * t) * e
    (x, x * -w + b * e)
  } else {
    let wd = w * (1.0 - ratio * ratio).sqrt()
    let cs = d
    let sn = 1.0 / wd * (-r * d + v)
    let e = @math.exp(r * t)
    let x = e * (cs * @math.cos(wd * t) + sn * @math.sin(wd * t))
    (x, x * r + e * (-wd * cs * @math.sin(wd * t) + wd * sn * @math.cos(wd * t)))
  }
}

///|
/// How long a spring takes, in whole ms, as Compose reckons it
/// (SpringEstimation.kt): until it stays within `threshold` of its rest.
/// Under-damped, by its envelope (c·e^(−ζωt) = threshold); critically and
/// over-damped, until the motion itself last leaves the threshold.
pub fn spring_duration(
  ratio : Double,
  stiffness : Double,
  d : Double,
  v : Double,
  threshold : Double,
) -> Double {
  if d == 0.0 && v == 0.0 {
    return 0.0
  }
  // in the threshold's units, displaced to the positive side
  let p0 = (d / threshold).abs()
  let v0 = if d < 0.0 { -v / threshold } else { v / threshold }
  let w = stiffness.sqrt()
  if ratio < 1.0 {
    let r = -ratio * w
    let wd = w * (1.0 - ratio * ratio).sqrt()
    let c2 = (v0 - r * p0) / wd
    let c = (p0 * p0 + c2 * c2).sqrt()
    let t = @math.ln(1.0 / c) / r
    return if t > 0.0 { (t * 1000.0).floor() } else { 0.0 }
  }
  // the last time |x| is 1: stepped a millisecond at a time until it has
  // settled far within it, then found between two steps
  let x_at = fn(t : Double) { spring_at(ratio, stiffness, p0, v0, t) }
  let mut last = -1.0
  let mut t = 0.0
  while t < 60.0 {
    let (x, vel) = x_at(t)
    if x.abs() >= 1.0 {
      last = t
    } else if x.abs() < 0.01 && vel.abs() < 0.01 * w {
      break
    }
    t = t + 0.001
  }
  if last < 0.0 {
    return 0.0
  }
  let mut lo = last
  let mut hi = last + 0.001
  for _ in 0..<40 {
    let m = (lo + hi) / 2.0
    let (x, _) = x_at(m)
    if x.abs() >= 1.0 {
      lo = m
    } else {
      hi = m
    }
  }
  (lo * 1000.0).floor()
}

///|
/// How long `spec` runs (ms, its delay included) from `from` to `to` with
/// velocity `v` (per second).
pub fn Spec::duration(self : Spec, from : Double, to : Double, v : Double) -> Double {
  match self {
    Spring(ratio, k, thr, delay) =>
      delay + spring_duration(ratio, k, from - to, v, thr)
    Tween(ms, _, delay) => delay + ms
    Snap(delay) => delay
    Motion(tr) => tr.delay + generator_duration(tr.generator(from, to, v))
  }
}

///|
/// Where `spec` is `ms` after it started from `from` to `to` with velocity
/// `v` (per second), and how fast (per second): as Compose plays it, its
/// time in whole milliseconds, at its end once its duration `dur` is out.
pub fn Spec::value_at(
  self : Spec,
  ms : Double,
  dur : Double,
  from : Double,
  to : Double,
  v : Double,
) -> (Double, Double) {
  let t = ms.floor()
  match self {
    // where its generator is (it may end elsewhere than `to`: inertia, keyframes)
    Motion(tr) => {
      if t < tr.delay {
        return (from, v)
      }
      let g = tr.generator(from, to, v)
      let u = dmin(t, dur) - tr.delay
      return (g.next(u).value, if t >= dur { 0.0 } else { g.velocity(u, initial=v) })
    }
    _ => ()
  }
  if t >= dur {
    return (to, 0.0)
  }
  match self {
    Spring(ratio, k, _, delay) => {
      if t < delay {
        return (from, v)
      }
      let (x, vel) = spring_at(ratio, k, from - to, v, (t - delay) / 1000.0)
      (to + x, vel)
    }
    Tween(len, ease, delay) => {
      let at = fn(p : Double) {
        let q = dclamp(p - delay, 0.0, len)
        let f = if len <= 0.0 { 1.0 } else { q / len }
        from + (to - from) * ease.at(f)
      }
      if t < delay {
        return (from, v)
      }
      // its speed as Compose's tween says it: over the millisecond before
      let x = at(t)
      (x, (x - at(t - 1.0)) * 1000.0)
    }
    Snap(_) => (from, v)
    Motion(_) => (from, v)
  }
}

///|
fn dclamp(v : Double, lo : Double, hi : Double) -> Double {
  if v < lo {
    lo
  } else if v > hi {
    hi
  } else {
    v
  }
}

///|
fn dmin(a : Double, b : Double) -> Double {
  if a < b {
    a
  } else {
    b
  }
}

///|
fn dmax(a : Double, b : Double) -> Double {
  if a > b {
    a
  } else {
    b
  }
}
