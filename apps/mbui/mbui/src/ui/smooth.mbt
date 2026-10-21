// Corners, as still.fail's (its apps/android/shared/src/main/kotlin/fail/still/android/ui/Corners.kt, and the web's
// web/src/styles/global.css.ts): a rounded rectangle's corner is a superellipse(1.5) one, |x|^n + |y|^n = 1 with
// n = 2^1.5, over a radius a quarter longer than the one it is given. Circles and capsules are never touched: a corner
// needs room for the longer radius, and where the box has none (the radius half its shorter side) it is the plain
// round one. Between the two it goes over evenly, so a box that grows (a capsule of one line taking a second) changes
// shape with its size, and never at once.
//
// Every box with a radius is so, with no switch: each renderer draws its ground, edge, shadow and glass by the same
// distance (src/host/corner.sl, `sd_corner` below number for number), what a rounded clip cuts is cut along it, and a
// press there is judged by it. A corner given is the one still.fail's tokens give (`Smooth(12.dp)`, the web's token
// before its --corner-scale): never times 1.25 by hand. Only + - × ÷ and √ (exact in IEEE, the same on every target):
// a power is `det_pow`'s.

///|
/// How much longer a smooth corner's radius is (the web's --corner-scale), and its exponent (CSS superellipse(1.5): 2^1.5).
pub let smooth_scale : Double = 1.25

///|
pub let smooth_exponent : Double = 2.8284271247461903

///|
/// How smooth a corner of `radius` is where `room` is half its box's shorter side: wholly (1) with room for the longer
/// radius, not at all (0) with none, a capsule's end (Corners.kt smoothness).
pub fn smoothness(radius : Double, room : Double) -> Double {
  if radius <= 0.0 {
    0.0
  } else {
    dclamp((room - radius) / ((smooth_scale - 1.0) * radius), 0.0, 1.0)
  }
}

///|
/// The corner of a smooth box `inset` inside a smooth one of corner `outer`, concentric with it: a curve moved in by
/// `inset` is drawn `inset` smaller, and a corner is drawn a quarter larger than it is given, so the inset is taken a
/// quarter smaller (Corners.kt concentric). Never below 0.
pub fn concentric(outer : Double, inset : Double) -> Double {
  dmax(outer - inset / smooth_scale, 0.0)
}

///|
/// The other way round: the corner of a smooth box round a smooth one of corner `inner`, `inset` in from its edges.
pub fn concentric_out(inner : Double, inset : Double) -> Double {
  inner + inset / smooth_scale
}

///|
/// How far in from each of its edges a corner of `radius` (room enough to be wholly smooth) passes at its middle, where
/// it turns 45°: the superellipse's point with x = y, 2^(-1/n) of the longer radius from its centre.
pub fn smooth_middle(radius : Double) -> Double {
  radius * smooth_scale * (1.0 - det_pow(0.5, 1.0 / smooth_exponent))
}

///|
/// The signed distance of (`px`, `py`), from a box's middle, from that box: `hx` by `hy` its half sides, its corner of
/// `r` (at most the shorter half) drawn `s` smooth, |x|^n + |y|^n = R^n about the corner's centre with n from 2 to 2^1.5
/// and R from r to 1.25 r as `s` goes from 0 to 1. On the curve it is 0 exactly; off it, the curve's own value over how
/// fast that grows there (the distance along its normal, to first order: what an edge's half pixel of cover needs). At
/// s = 0 it is a round corner's, as every renderer drew one before. Only within `band` of the curve is it worked out:
/// the curve lies between the circle of R and that of R 2^(1/2 - 1/n) (under 1.107 R), and further than `band` inside the
/// one or outside the other the round distance is given, of the same sign and at least `band` (the renderers pass what
/// their cover, edge or blur reaches; by default everywhere). The renderers' `mb_sd_corner` (src/host/corner.sl).
pub fn sd_corner(
  px : Double,
  py : Double,
  hx : Double,
  hy : Double,
  r : Double,
  s : Double,
  band? : Double = 1.0e30,
) -> Double {
  let rr = dmin(r * (1.0 + (smooth_scale - 1.0) * s), dmin(hx, hy))
  let qx = px.abs() - hx + rr
  let qy = py.abs() - hy + rr
  let mx = dmax(qx, 0.0)
  let my = dmax(qy, 0.0)
  let l = (mx * mx + my * my).sqrt()
  if s <= 0.0 || dmin(mx, my) <= 0.0 || l <= rr - band || l >= 1.107 * rr + band {
    return l + dmin(dmax(qx, qy), 0.0) - rr
  }
  let hi = dmax(mx, my)
  let t = dmin(mx, my) / hi
  if s >= 1.0 {
    return hi * smooth_a(t) - rr * smooth_b(t)
  }
  let n = 2.0 + (smooth_exponent - 2.0) * s
  let tn1 = det_pow(t, n - 1.0)
  let tn = tn1 * t
  let u = det_pow(1.0 + tn, 1.0 / n)
  (hi * u - rr) * (1.0 + tn) / (u * (1.0 + tn1 * tn1).sqrt())
}

///|
/// The wholly smooth corner's two factors (sd_corner's (1 + tⁿ) / √(1 + t^(2n-2)), and that over (1 + tⁿ)^(1/n), at
/// n = 2^1.5) as polynomials in t over [0, 1] (least squares; within 2e-5 of them): what the renderers work out for
/// nearly every corner in place of two powers a pixel, and so this too.
fn smooth_a(t : Double) -> Double {
  1.0000098 +
  t *
  (-0.00106380035 +
  t *
  (0.0390446602 +
  t *
  (1.21491043 +
  t *
  (-1.49650831 +
  t *
  (1.90947795 + t * (-2.77580972 + t * (2.11536546 + t * -0.591224537)))))))
}

///|
fn smooth_b(t : Double) -> Double {
  1.00001404 +
  t *
  (-0.00136262193 +
  t *
  (0.039570688 +
  t *
  (0.648050719 +
  t *
  (-0.725922772 +
  t *
  (0.327888394 + t * (-0.914717465 + t * (1.13728689 + t * -0.403984265)))))))
}

///|
/// A box's own: (`px`, `py`) from its middle, `hx` by `hy` its half sides, its corners `r` (capped at the shorter half),
/// as smooth as its size has room for. The renderers' `mb_sd_box`.
pub fn sd_box(px : Double, py : Double, hx : Double, hy : Double, r : Double) -> Double {
  let room = dmin(hx, hy)
  let rr = dmin(r, room)
  sd_corner(px, py, hx, hy, rr, smoothness(rr, room))
}

///|
/// `x` to the power `e`, for `x` > 0, by + - × ÷ alone (so the same to the bit in JavaScript and natively, where
/// @math.pow is each one's own): e^(e · ln x), ln by its series in (m - 1) / (m + 1) after halving or doubling x into
/// [√½, √2), exp by Taylor's after taking out whole ln 2s. Within a few units in the last place of the true power.
pub fn det_pow(x : Double, e : Double) -> Double {
  if x <= 0.0 {
    return 0.0
  }
  if x == 1.0 || e == 0.0 {
    return 1.0
  }
  // x = m · 2^k
  let mut m = x
  let mut k = 0
  while m >= sqrt2 {
    m = m * 0.5
    k = k + 1
  }
  while m < sqrt_half {
    m = m * 2.0
    k = k - 1
  }
  let z = (m - 1.0) / (m + 1.0)
  let z2 = z * z
  let mut term = z
  let mut sum = 0.0
  let mut j = 1
  while j < 40 {
    sum = sum + term / j.to_double()
    term = term * z2
    j = j + 2
  }
  let y = e * (2.0 * sum + k.to_double() * ln2)
  // e^y = e^r · 2^w, |r| ≤ ln 2 / 2
  let w = (y / ln2 + 0.5).floor()
  let r = y - w * ln2
  let mut ex = 1.0
  let mut t = 1.0
  for i in 1..<24 {
    t = t * r / i.to_double()
    ex = ex + t
  }
  let mut wi = w.to_int()
  while wi > 0 {
    ex = ex * 2.0
    wi = wi - 1
  }
  while wi < 0 {
    ex = ex * 0.5
    wi = wi + 1
  }
  ex
}

///|
let ln2 : Double = 0.6931471805599453

///|
let sqrt2 : Double = 1.4142135623730951

///|
let sqrt_half : Double = 0.7071067811865476
