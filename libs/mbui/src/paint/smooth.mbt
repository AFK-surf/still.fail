// Corners as drawn; host/corner.sl is the renderers' copy. A corner's radius places things, its smoothing only draws.

///|
/// How much longer a smooth corner's radius is (the web's --corner-scale), and its exponent (CSS superellipse(1.5): 2^1.5).
pub let smooth_scale : Double = 1.25

///|
pub let smooth_exponent : Double = 2.8284271247461903

///|
/// How smooth a corner of `radius` is where `room` is half its box's shorter side: wholly (1) with room for the longer
/// radius, not at all (0) with none, a capsule's end.
pub fn smoothness(radius : Double, room : Double) -> Double {
  if radius <= 0.0 {
    0.0
  } else {
    dclamp((room - radius) / (0.25 * radius), 0.0, 1.0)
  }
}

///|
/// The corner of a smooth box `inset` inside a smooth one of corner `outer`, concentric with it: its corner as given
/// less the inset (the user, 2026-11-03: 「平滑圆角只是在原有圆角的描述上做平滑」「边距应该是整数」: a corner is
/// laid out by the radius it is given, its smoothing only how it is drawn). Never below 0.
pub fn concentric(outer : Double, inset : Double) -> Double {
  dmax(outer - inset, 0.0)
}

///|
/// The other way round: the corner of a smooth box round a smooth one of corner `inner`, `inset` in from its edges.
pub fn concentric_out(inner : Double, inset : Double) -> Double {
  inner + inset
}

///|
/// How far in from a corner of `corner` a capsule or a circle `height` high stands, concentric with it: the corner less
/// its half (at most `room`, the corner's box's shorter half: a capsule's end as round as it is), by the radius as given.
pub fn capsule_in(corner : Double, height : Double, room? : Double = 1.0e30) -> Double {
  dmin(corner, room) - height / 2.0
}

///|
/// How far in from each of its edges a corner of `radius` (room enough to be wholly smooth) passes at its middle, where
/// it turns 45°: the superellipse's point with x = y, 2^(-1/n) of the longer radius from its centre.
pub fn smooth_middle(radius : Double) -> Double {
  radius * smooth_scale * (1.0 - det_pow(0.5, 1.0 / smooth_exponent))
}

///|
/// The same for a box's corner of `radius` where `room` is half its box's shorter side, as smooth as that has room for
/// (sd_box): a circle's or a capsule's end, R (1 - 2^(-1/2)); a corner with room enough, smooth_middle's.
pub fn corner_middle(radius : Double, room : Double) -> Double {
  let r = dmin(radius, room)
  let s = smoothness(r, room)
  let rr = dmin(r * (1.0 + (smooth_scale - 1.0) * s), room)
  rr * (1.0 - det_pow(0.5, 1.0 / (2.0 + (smooth_exponent - 2.0) * s)))
}

///|
/// The signed distance of (`px`, `py`), from a box's middle, from that box: `hx` by `hy` its half sides, its corner of
/// `r` (at most the shorter half) drawn `s` smooth, |x|^n + |y|^n = R^n about the corner's centre with n from 2 to 2^1.5
/// and R from r to 1.25 r as `s` goes from 0 to 1. On the curve it is 0 exactly; off it, the curve's own value over how
/// fast that grows there (the distance along its normal, to first order: what an edge's half pixel of cover needs). At
/// s = 0 it is a round corner's, as every renderer drew one before. Only within `band` of the curve is it worked out:
/// the curve lies between the circle of R and that of R 2^(1/2 - 1/n) (under 1.107 R), and further than `band` inside the
/// one or outside the other the round distance is given, of the same sign and at least `band` (the renderers pass what
/// their cover, edge or blur reaches; by default everywhere). A corner with no room across its box (a capsule's end)
/// but room along it eases into its long edges (capsule_ease). The renderers' `mb_sd_corner` (src/host/corner.sl).
pub fn sd_corner(
  px : Double,
  py : Double,
  hx : Double,
  hy : Double,
  r : Double,
  s : Double,
  band? : Double = 1.0e30,
) -> Double {
  let d = corner_shape(px, py, hx, hy, r, s, band)
  let rr = dmin(r * (1.0 + (smooth_scale - 1.0) * s), dmin(hx, hy))
  if s >= 1.0 || rr <= 0.0 {
    return d
  }
  d +
  (1.0 - s) *
  (capsule_tail(px.abs(), py.abs(), hx, hy, rr) + capsule_tail(py.abs(), px.abs(), hy, hx, rr))
}

///|
/// sd_corner's curve before a capsule's end eases into its edges.
fn corner_shape(
  px : Double,
  py : Double,
  hx : Double,
  hy : Double,
  r : Double,
  s : Double,
  band : Double,
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
/// How much of its curve a capsule's end has room for along a side of half `ha`: all of it once that side holds it.
fn capsule_room(ha : Double, rr : Double) -> Double {
  dmin((ha - rr) / (0.4 * rr), 1.0)
}

///|
/// A capsule's end (a corner with no room across its box but room along it), as Apple draws one (iOS 26's alert
/// buttons, the user, 2026-10-31: 苹果的那个按钮就看不出直线和半圆的接点): a circle's arc at its middle, leaving it and easing
/// into the long edge further along than a circle meets it. How much it bends goes with no jump and no kink (the user,
/// 2026-11-01: 要的是平滑): from none on the edge it rises once to at most 1.15 the circle's and comes back to the
/// circle's, never stepping and never turning at once. As how much further in than the circle it lies, in r, at `u` r
/// from the tip, `k` the share of the room the curve takes along the edge the box has (capsule_room): from u0 = 1 - 0.675 k (the
/// circle's height and its first three rates of change there) to u1 = 1 + 0.4 k (the edge's, all four none) an octic,
/// the four of each end's weights and k^2.5 t^4 (1 - t)^4, t from 0 to 1 between them (fitted to a capsule the user
/// measured, 2026-11-01, within 0.008 r: smooth_wbtest keeps what they measured).
fn capsule_ease(u : Double, k : Double) -> Double {
  let u0 = 1.0 - 0.675 * k
  let u1 = 1.0 + 0.4 * k
  if k <= 0.0 || u <= u0 || u >= u1 {
    return 0.0
  }
  let h = u1 - u0
  let t = (u - u0) / h
  let t2 = t * t
  let t3 = t2 * t
  let t4 = t3 * t
  let m = 1.0 - t
  let m2 = m * m
  // the circle at u0: its height below the edge and its first three rates of change, each times h to its order
  let s = (u0 * (2.0 - u0)).sqrt()
  let v = 1.0 - u0
  let s3 = s * s * s
  let c0 = 1.0 - s
  let c1 = -v / s * h
  let c2 = h * h / s3
  let c3 = -3.0 * v * h * h * h / (s3 * s * s)
  // the septic's weights of those four at the start (all four and theirs none at the end)
  let w0 = 1.0 - t4 * (35.0 - 84.0 * t + 70.0 * t2 - 20.0 * t3)
  let w1 = t - t4 * (20.0 - 45.0 * t + 36.0 * t2 - 10.0 * t3)
  let w2 = (t2 - t4 * (10.0 - 20.0 * t + 15.0 * t2 - 4.0 * t3)) / 2.0
  let w3 = (t3 - t4 * (4.0 - 6.0 * t + 4.0 * t2 - t3)) / 6.0
  let eased = c0 * w0 + c1 * w1 + c2 * w2 + c3 * w3 + k * k * k.sqrt() * t4 * m2 * m2
  let round = if u < 1.0 { 1.0 - (u * (2.0 - u)).sqrt() } else { 0.0 }
  eased - round
}

///|
/// How much further out than the round corner's (`rr`) a point is once the corner eases into the edge along `along`'s
/// side (`ha` that half side, `hc` the other's; both of the point's coordinates from the box's middle, made positive):
/// the ease as far as the corner has no room across (its own smoothness that way), moved along the round corner's normal
/// there (to first order: the ease is under 1% of r).
fn capsule_tail(along : Double, across : Double, ha : Double, hc : Double, rr : Double) -> Double {
  let k = capsule_room(ha, rr)
  let tight = 1.0 - smoothness(rr, hc)
  if k <= 0.0 || tight <= 0.0 {
    return 0.0
  }
  let e = capsule_ease((ha - along) / rr, k)
  if e == 0.0 {
    return 0.0
  }
  let qa = along - ha + rr
  let qc = across - hc + rr
  let ma = dmax(qa, 0.0)
  let mc = dmax(qc, 0.0)
  let l = (ma * ma + mc * mc).sqrt()
  let n = if l > 0.0 { mc / l } else if qc >= qa { 1.0 } else { 0.0 }
  tight * e * rr * n
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
/// The signed distance of (`px`, `py`) from a clip: its rect (`x0` `y0` `x1` `y1`), its corners `r` (top left, then
/// clockwise; 0 square), how smooth each is `s`. A corner is the curve of the box whose corner it is, where that box
/// has it, as round as that box drew it: drawn there whatever the clip's own size (a band a few points high sharing a
/// frame's corner is cut by the frame's very curve, not one flattened to its half height); each corner against its own
/// corner point, the rect's edges straight. The renderers' `mb_sd_clip` (src/host/corner.sl).
pub fn sd_clip(
  px : Double,
  py : Double,
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
  r : (Double, Double, Double, Double),
  s : (Double, Double, Double, Double),
  band? : Double = 1.0e30,
) -> Double {
  let hx = dmax((x1 - x0) / 2.0, 0.0)
  let hy = dmax((y1 - y0) / 2.0, 0.0)
  let qx = (px - (x0 + hx)).abs() - hx
  let qy = (py - (y0 + hy)).abs() - hy
  let mx = dmax(qx, 0.0)
  let my = dmax(qy, 0.0)
  let mut d = (mx * mx + my * my).sqrt() + dmin(dmax(qx, qy), 0.0)
  // each rounded corner against its own corner point, its curve where its box has it (`ix`, `iy`: the way in)
  let corner = fn(kx : Double, ky : Double, ix : Double, iy : Double, rr : Double, ss : Double) {
    let reach = rr * (1.0 + (smooth_scale - 1.0) * ss)
    let vx = dmax(hx, reach)
    let vy = dmax(hy, reach)
    sd_corner(dmax(vx - (px - kx) * ix, 0.0), dmax(vy - (py - ky) * iy, 0.0), vx, vy, rr, ss, band~)
  }
  if r.0 > 0.0 {
    d = dmax(d, corner(x0, y0, 1.0, 1.0, r.0, s.0))
  }
  if r.1 > 0.0 {
    d = dmax(d, corner(x1, y0, -1.0, 1.0, r.1, s.1))
  }
  if r.2 > 0.0 {
    d = dmax(d, corner(x1, y1, -1.0, -1.0, r.2, s.2))
  }
  if r.3 > 0.0 {
    d = dmax(d, corner(x0, y1, 1.0, -1.0, r.3, s.3))
  }
  d
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
