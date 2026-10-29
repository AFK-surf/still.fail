// Compose's numbers: curves (CSS's cubic-beziers, as Compose's CubicBezierEasing plays them), and how something
// animates (Compose's AnimationSpec): springs by damping ratio and stiffness in closed form (SpringSimulation), with
// Compose's own reckoning of how long they take (SpringEstimation), tweens of whole milliseconds on a curve. Equal,
// frame for frame, to what Compose's animation-core prints (scripts/compose_ref.sh, motion_test.mbt). Motion's own
// transitions are a Spec too (Motion: transition.mbt).

///|
/// How something animates (Compose's AnimationSpec): a spring by damping
/// ratio, stiffness and the visibility threshold it rests within (and a
/// delay, ms, held at its start: ListMotion.kt Delayed); a tween of so many
/// ms on a curve after a delay; or there at once (after a delay).
pub(all) enum Spec {
  Spring(Double, Double, Double, Double)
  Tween(Double, @ui.Ease, Double)
  /// a Move as long as its way is far (@ui.move_ms): how many points one of its units is, how far it goes in points if
  /// that is said for it (< 0: its own way, from where it is to where it goes), its delay
  Moved(Double, Double, Double)
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
/// Compose's tween(durationMillis, delayMillis, easing), its curve said:
/// what the motion is (@ui.Ease: one curve for each).
pub fn tween(ms : Double, ease~ : @ui.Ease, delay? : Double = 0.0) -> Spec {
  Tween(ms, ease, delay)
}

///|
/// A thing moved, seen where it was and where it goes (@ui.Ease's Move): as long as its way is far (@ui.move_ms of it,
/// from where it is as it is told to where it goes, so a way told anew mid-way takes what is left of it), going on as
/// fast as it went (or as the hand let it go: Anim::animate's `velocity`). `points`: how many points one of its units
/// is (a progress from 0 to 1 over a way 300 points long: 300); `over`: how far it goes, said for it (what moves
/// together, the furthest of them: Spec::over).
pub fn move(points? : Double = 1.0, over? : Double = -1.0, delay? : Double = 0.0) -> Spec {
  Moved(points, over, delay)
}

///|
/// A Move said to go `points` far (what moves with others of the same cause, as long as the furthest of them); any
/// other spec as it is.
pub fn Spec::over(self : Spec, points : Double) -> Spec {
  match self {
    Moved(per, _, delay) => Moved(per, points, delay)
    s => s
  }
}

///|
/// Whether it is a Move whose way is said for it (`over`): as long as that, whatever its own way.
pub fn Spec::way_said(self : Spec) -> Bool {
  self is Moved(_, over, _) && over >= 0.0
}

///|
/// A Move whose one unit is `points` points (a share of a height: that height); any other spec as it is.
pub fn Spec::per_unit(self : Spec, points : Double) -> Spec {
  match self {
    Moved(_, over, delay) => Moved(points, over, delay)
    s => s
  }
}

///|
/// The same spec after `delay` ms.
pub fn Spec::delayed(self : Spec, delay : Double) -> Spec {
  match self {
    Spring(a, b, t, _) => Spring(a, b, t, delay)
    Tween(a, b, _) => Tween(a, b, delay)
    Moved(a, b, _) => Moved(a, b, delay)
    Snap(_) => Snap(delay)
    Motion(tr) => Motion(tr.delayed(delay))
  }
}

///|
/// How long a Move takes from `from` to `to` (its delay not counted).
fn moved_ms(per : Double, over : Double, from : Double, to : Double) -> Double {
  @ui.move_ms(if over >= 0.0 { over } else { (to - from).abs() * per })
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
/// What the hand holds or lifts (the one spring with a bounce: still.fail's
/// docs/motion.md): a finger's ripple sinking (Android's), a switch's knob
/// held, a card lifted, the long-press menu's scale, the loupe following the
/// finger (motionSpring(.25, bounce .35)).
// kept across runs: a constant: its fields are not mut, nothing changes it
pub let lift_spring : Spec = motion_spring(0.25, bounce=0.35)

///|
/// The long-press menu's scale: lifted by the hand (lift_spring).
// kept across runs: a constant: its fields are not mut, nothing changes it
pub let menu_spring : Spec = lift_spring

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
    let ea = @dmath.exp(gm * t)
    let eb = @dmath.exp(gp * t)
    (a * ea + b * eb, a * gm * ea + b * gp * eb)
  } else if ratio == 1.0 {
    let a = d
    let b = v + w * d
    let e = @dmath.exp(-w * t)
    let x = (a + b * t) * e
    (x, x * -w + b * e)
  } else {
    let wd = w * (1.0 - ratio * ratio).sqrt()
    let cs = d
    let sn = 1.0 / wd * (-r * d + v)
    let e = @dmath.exp(r * t)
    let x = e * (cs * @dmath.cos(wd * t) + sn * @dmath.sin(wd * t))
    (x, x * r + e * (-wd * cs * @dmath.sin(wd * t) + wd * sn * @dmath.cos(wd * t)))
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
    let t = @dmath.ln(1.0 / c) / r
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
    Moved(per, over, delay) => if from == to && v == 0.0 { delay } else { delay + moved_ms(per, over, from, to) }
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
  let t = @ui.whole_ms(ms)
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
    Moved(per, over, delay) => {
      if t < delay {
        return (from, v)
      }
      // (its speed per second, the way's per ms)
      let (x, xv) = @ui.move_path(from - to, v / 1000.0, t - delay, moved_ms(per, over, from, to))
      (to + x, xv * 1000.0)
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
