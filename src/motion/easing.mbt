// Motion's easing functions (motion-utils src/easing, motion.dev, MIT), as functions of progress 0 → 1: cubic_bezier
// (Motion's own solver: Newton's steps kept in a bisection bracket, so not quantised; exactly 0 and 1 at the ends),
// the named curves, steps, and the modifiers that mirror and reverse a curve. Ported from Motion: Copyright (c) 2024
// Motion B.V., MIT licence. (Ease, in spec.mbt, is Compose's way of playing the CSS curves, for still.fail's own
// motions; these are Motion's.)

///|
/// Linear: progress as it is (Motion's `linear`, noop).
pub fn linear(p : Double) -> Double {
  p
}

///|
/// x(t) given t and x1, x2 (or y(t) given y1, y2), in Bernstein form: exactly 0 at t 0 and 1 at t 1.
fn calc_bezier(t : Double, a1 : Double, a2 : Double) -> Double {
  t * (3.0 * (1.0 - t) * ((1.0 - t) * a1 + t * a2) + t * t)
}

///|
/// cubic-bezier(x1, y1, x2, y2) as an easing (Motion's cubicBezier): t found for x by Newton's steps (dx/dt by a
/// forward difference), bisecting wherever a step would leave the bracket. Linear when both points are on the
/// diagonal.
pub fn cubic_bezier(x1 : Double, y1 : Double, x2 : Double, y2 : Double) -> (Double) -> Double {
  if x1 == y1 && x2 == y2 {
    return linear
  }
  fn(x : Double) {
    let mut lower = 0.0
    let mut upper = 1.0
    let mut t = x
    let mut i = 0
    while true {
      // outside the bracket (x out of range, or a step overshot where the slope is ~0): bisect
      if !(t >= lower && t <= upper) {
        t = (lower + upper) / 2.0
      }
      let current = calc_bezier(t, x1, x2) - x
      if current * current < 1.0e-28 || i == 40 {
        break
      }
      if current > 0.0 {
        upper = t
      } else {
        lower = t
      }
      t = t - current * 1.0e-7 / (calc_bezier(t + 1.0e-7, x1, x2) - x - current)
      i = i + 1
    }
    calc_bezier(t, y1, y2)
  }
}

///|
/// A curve mirrored for its second half (Motion's mirrorEasing): an ease-in becomes an ease-in-out.
pub fn mirror_easing(easing : (Double) -> Double) -> (Double) -> Double {
  fn(p) {
    if p <= 0.5 {
      easing(2.0 * p) / 2.0
    } else {
      (2.0 - easing(2.0 * (1.0 - p))) / 2.0
    }
  }
}

///|
/// A curve played backwards (Motion's reverseEasing): an ease-in becomes an ease-out.
pub fn reverse_easing(easing : (Double) -> Double) -> (Double) -> Double {
  fn(p) { 1.0 - easing(1.0 - p) }
}

///|
/// CSS's ease-in, ease-out, ease-in-out (Motion's easeIn, easeOut, easeInOut).
pub let ease_in : (Double) -> Double = cubic_bezier(0.42, 0.0, 1.0, 1.0)

///|
pub let ease_out : (Double) -> Double = cubic_bezier(0.0, 0.0, 0.58, 1.0)

///|
pub let ease_in_out : (Double) -> Double = cubic_bezier(0.42, 0.0, 0.58, 1.0)

///|
/// Circular (Motion's circIn, circOut, circInOut).
pub fn circ_in(p : Double) -> Double {
  1.0 - @dmath.sin(@dmath.acos(p))
}

///|
pub let circ_out : (Double) -> Double = reverse_easing(circ_in)

///|
pub let circ_in_out : (Double) -> Double = mirror_easing(circ_in)

///|
/// Back: past its end and back (Motion's backOut, backIn, backInOut).
pub let back_out : (Double) -> Double = cubic_bezier(0.33, 1.53, 0.69, 0.99)

///|
pub let back_in : (Double) -> Double = reverse_easing(back_out)

///|
pub let back_in_out : (Double) -> Double = mirror_easing(back_in)

///|
/// Back a little first, then out (Motion's anticipate).
pub fn anticipate(p : Double) -> Double {
  if p >= 1.0 {
    return 1.0
  }
  let q = p * 2.0
  if q < 1.0 {
    0.5 * back_in(q)
  } else {
    0.5 * (2.0 - @dmath.pow(2.0, -10.0 * (q - 1.0)))
  }
}

///|
/// Where `steps` jumps: at the end of each step (CSS's jump-end) or its start.
pub(all) enum StepsAt {
  End
  Start
} derive(Eq, Show)

///|
/// So many equal steps (Motion's steps, CSS's steps()).
pub fn steps(n : Int, direction? : StepsAt = End) -> (Double) -> Double {
  let k = n.to_double()
  fn(p) {
    let p = match direction {
      End => if p < 0.999 { p } else { 0.999 }
      Start => if p > 0.001 { p } else { 0.001 }
    }
    let expanded = p * k
    let rounded = match direction {
      End => @math.floor(expanded)
      Start => @math.ceil(expanded)
    }
    clamp(0.0, 1.0, rounded / k)
  }
}

///|
/// An easing by Motion's name for it (easingDefinitionToFunction): linear, easeIn, easeInOut, easeOut, circIn,
/// circInOut, circOut, backIn, backInOut, backOut, anticipate. None for any other.
pub fn easing_named(name : String) -> ((Double) -> Double)? {
  match name {
    "linear" => Some(linear)
    "easeIn" => Some(ease_in)
    "easeInOut" => Some(ease_in_out)
    "easeOut" => Some(ease_out)
    "circIn" => Some(circ_in)
    "circInOut" => Some(circ_in_out)
    "circOut" => Some(circ_out)
    "backIn" => Some(back_in)
    "backInOut" => Some(back_in_out)
    "backOut" => Some(back_out)
    "anticipate" => Some(anticipate)
    _ => None
  }
}
