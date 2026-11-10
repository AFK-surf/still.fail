// How a page's list moves as each platform's own lists do, as data ("Motion is data"): Android's
// fling (Compose's FlingCalculator over AndroidFlingSpline), its stretch at the ends (EdgeEffect's intensity, HWUI's
// mapping, its spring back), iOS's deceleration and rubber band, the desktop's coast; each a function of what it set out
// from and the time alone. One for both of what draws lists: an old view's (ui's scroll.mbt, Ctx::list) and a column of
// the window's tree scrolling as a page's list does (Scroll::list).

///|
/// The spline's distance at 101 evenly spaced times (computeSplineInfo).
// kept across runs: a constant, computed once: nothing writes it after
pub let spline_positions : FixedArray[Double] = compute_spline()

///|
fn compute_spline() -> FixedArray[Double] {
  let samples = 100
  let inflection = 0.35
  let start_tension = 0.5
  let end_tension = 1.0
  let p1 = start_tension * inflection
  let p2 = 1.0 - end_tension * (1.0 - inflection)
  let pos = FixedArray::make(samples + 1, 0.0)
  let mut x_min = 0.0
  for i in 0..<samples {
    let alpha = i.to_double() / samples.to_double()
    let mut x_max = 1.0
    let mut x = 0.0
    let mut coef = 0.0
    while true {
      x = x_min + (x_max - x_min) / 2.0
      coef = 3.0 * x * (1.0 - x)
      let tx = coef * ((1.0 - x) * p1 + x * p2) + x * x * x
      if (tx - alpha).abs() < 1.0e-5 {
        break
      }
      if tx > alpha {
        x_max = x
      } else {
        x_min = x
      }
    }
    pos[i] = coef * ((1.0 - x) * start_tension + x) + x * x * x
  }
  pos[samples] = 1.0
  pos
}

///|
/// ln(0.78) / ln(0.9)
let deceleration_rate : Double = @dmath.ln(0.78) / @dmath.ln(0.9)

///|
/// A fling at `v` pixels per second (physical pixels, on a screen of
/// `density` pixels per dp): how far it goes (pixels) and how long it
/// takes (whole ms), as Compose's FlingCalculator has them.
pub fn spline_fling(v : Double, density : Double) -> (Double, Double) {
  let speed = v.abs()
  if speed == 0.0 {
    return (0.0, 0.0)
  }
  // gravity × inches per meter × 160 dpi × density × 0.84, by the friction
  let physical = 386.0878 * 160.0 * density * 0.84
  let friction = 0.015 * physical
  let l = @dmath.ln(0.35 * speed / friction)
  let dur = (1000.0 * @dmath.exp(l / (deceleration_rate - 1.0))).floor()
  let dist = friction *
    @dmath.exp(deceleration_rate / (deceleration_rate - 1.0) * l)
  (dist, dmax(dur, 0.0))
}

///|
/// Where along a spline fling `dur` ms long it is at `t` ms: the share of
/// its distance gone and its velocity in distances per unit of time
/// (AndroidFlingSpline.flingPosition).
pub fn spline_at(t : Double, dur : Double) -> (Double, Double) {
  let s = dclamp(if dur > 0.0 { t / dur } else { 1.0 }, 0.0, 1.0)
  let index = (100.0 * s).to_int()
  if index >= 100 {
    return (1.0, 0.0)
  }
  let t_inf = index.to_double() / 100.0
  let d_inf = spline_positions[index]
  let d_sup = spline_positions[index + 1]
  let vc = (d_sup - d_inf) / 0.01
  (d_inf + (s - t_inf) * vc, vc)
}

///|
/// How far (logical pixels) a fling at `v` logical pixels per ms goes on a
/// screen of `density`.
pub fn fling_distance(v : Double, density : Double) -> Double {
  spline_fling(v * 1000.0 * density, density).0 / density
}

///|
/// Android's stretch intensity for a pull of `d` (in the view's heights):
/// EdgeEffect.dampStretchVector.
pub fn stretch_amount(d : Double) -> Double {
  let o = d.abs()
  let linear = 0.016 * o
  let exp_part = 0.016 * (1.0 - @dmath.exp(-o * (2.718281828459045 / 0.33)))
  linear + exp_part
}

///|
/// Where a point `p` of the content (0 the top of the view, 1 its bottom)
/// shows under a stretch of `ov` (positive from the top, negative from the
/// bottom): HWUI StretchEffect's computeReverseOverscroll, the inverse of
/// its shader. Outside the view it moves as the view's edge does.
pub fn stretch_map(ov : Double, p : Double) -> Double {
  if ov > 0.0 {
    if p < 0.0 {
      return p
    }
    if p > 1.0 {
      return stretch_map(ov, 1.0) + (p - 1.0)
    }
    let num = -p * ov * ov - 2.0 * p * ov - p
    let den = 1.0 + 0.3 * ov + 0.7 * p * ov * ov + 0.7 * p * ov
    -(num / den)
  } else if ov < 0.0 {
    if p > 1.0 {
      return p
    }
    if p < 0.0 {
      return stretch_map(ov, 0.0) + p
    }
    let num = 0.3 * ov * ov - 0.3 * p * ov * ov + 1.3 * p * ov - ov - p
    let den = 0.7 * p * ov * ov - 0.7 * p * ov - 0.7 * ov * ov + ov - 1.0
    num / den
  } else {
    p
  }
}

///|
/// iOS's rubber band: how far content pulled `x` past an end of a view `d`
/// long shows past it.
pub fn rubber(x : Double, d : Double) -> Double {
  let d = dmax(d, 1.0)
  (1.0 - 1.0 / (x * 0.55 / d + 1.0)) * d
}

///|
/// The pull that shows as `y` past the end (rubber's inverse).
pub fn unrubber(y : Double, d : Double) -> Double {
  let d = dmax(d, 1.0)
  let y = dmin(y, d * 0.999)
  y * d / (0.55 * (d - y))
}

///|
/// The rubber band's spring back (critically damped), per ms.
pub let rubber_omega : Double = 0.0157

///|
/// UIScrollView's normal deceleration rate (per ms).
pub let ios_decel : Double = 0.998

///|
/// The desktop's coast after a drag let go (per ms).
pub let coast_decel : Double = 0.997

///|
/// An overscroll springing back (scroll.mbt): from `x0` (Android: the view's heights; iOS: points) at `v0` outward
/// (Android: pixels per second; iOS: points per ms), set out at `t0` (-1: at its next frame). Android's may meet the
/// stretch's limit (1) on its way out (`clamp_at`: from there it springs from 1, still) and, once close, go straight in
/// at 200 pixels a second (`lin_at`, from `lin_x`); at rest (gone) at `rest`. +inf: not that.
pub(all) struct BackPath {
  mut t0 : Double
  mut x0 : Double
  mut v0 : Double
  mut clamp_at : Double
  mut lin_at : Double
  mut lin_x : Double
  mut rest : Double
}

///|
pub fn BackPath::new() -> BackPath {
  {
    t0: -1.0,
    x0: 0.0,
    v0: 0.0,
    clamp_at: @double.infinity,
    lin_at: @double.infinity,
    lin_x: 0.0,
    rest: @double.infinity,
  }
}

///|
/// Android's stretch spring (EdgeEffect.updateSpring) `dt` seconds after it was at `dist` (view heights) moving at
/// `vel` (pixels per second), `h` pixels high: where it is (in pixels) and how fast.
pub fn edge_spring_at(dist : Double, vel : Double, h : Double, dt : Double) -> (Double, Double) {
  let w = 24.657
  let z = 0.98
  let wd = w * (1.0 - z * z).sqrt()
  let cos_c = dist * h
  let sin_c = 1.0 / wd * (z * w * dist * h + vel)
  let e = @dmath.exp(-z * w * dt)
  let x = e * (cos_c * @dmath.cos(wd * dt) + sin_c * @dmath.sin(wd * dt))
  let v = x * -w * z +
    e * (-wd * cos_c * @dmath.sin(wd * dt) + wd * sin_c * @dmath.cos(wd * dt))
  (x, v)
}

///|
/// The rubber band (critically damped) `t` ms after it was at `x0` points moving at `v0` outward: where and how fast.
pub fn rubber_at(x0 : Double, v0 : Double, t : Double) -> (Double, Double) {
  let w = rubber_omega
  let e = @dmath.exp(-w * t)
  ((x0 + (v0 + w * x0) * t) * e, (v0 - w * (v0 + w * x0) * t) * e)
}

///|
/// The first time (in the unit `at` takes, from 0, by `step`, up to `most`) at which `hit` holds, found to the
/// floating point's last bit between the step it holds at and the one before; +inf when it never does.
pub fn first_when(hit : (Double) -> Bool, step : Double, most : Double) -> Double {
  if hit(0.0) {
    return 0.0
  }
  let mut a = 0.0
  let mut b = step
  while b <= most && !hit(b) {
    a = b
    b = b + step
  }
  if b > most {
    return @double.infinity
  }
  for _ in 0..<64 {
    let m = (a + b) / 2.0
    if m <= a || m >= b {
      break
    }
    if hit(m) {
      b = m
    } else {
      a = m
    }
  }
  b
}

///|
/// Android's stretch going back from (x0, v0), `h` pixels high: when it reaches its limit, goes straight in, is gone.
pub fn BackPath::plan_edge(self : BackPath, h : Double) -> Unit {
  let gone = fn(x : Double, v : Double) { x < 0.0 || (v.abs() < 0.01 && x < 0.001) }
  let close = fn(x : Double, v : Double) { v.abs() <= 200.0 && x.abs() < 8.0 && v < 0.0 && x > 0.0 }
  // when the way from (x0, v0) is over: gone, or close enough to go straight in (seconds, in steps of a millisecond)
  let over_at = fn(x0 : Double, v0 : Double) {
    first_when(
      fn(t) {
        let (x, v) = edge_spring_at(x0, v0, h, t)
        gone(x, v) || close(x, v)
      },
      0.001,
      60.0,
    )
  }
  let mut from_t = 0.0
  let mut x0 = self.x0
  let mut v0 = self.v0
  let mut end = over_at(x0, v0)
  if x0 < 1.0 {
    // whether it meets the limit before that, looked for up to that end (and the step it was found in) only: not
    // through all 60 s of a spring that never gets there, 60 000 of its sines and cosines in the frame a fling meets
    // the end, which came late (the list stopping a moment short of its end)
    let x0_ = x0
    let v0_ = v0
    let out = first_when(fn(t) { edge_spring_at(x0_, v0_, h, t).0 / h > 1.0 }, 0.001, dmin(end + 0.001, 60.0))
    if out < end {
      self.clamp_at = self.t0 + out * 1000.0
      from_t = out
      x0 = 1.0
      v0 = 0.0
      end = over_at(x0, v0)
    }
  }
  if end == @double.infinity {
    self.rest = @double.infinity
    return
  }
  let (x, v) = edge_spring_at(x0, v0, h, end)
  let at = self.t0 + (from_t + end) * 1000.0
  if close(x, v) && !gone(x, v) {
    self.lin_at = at
    self.lin_x = x / h
    self.rest = at + x / 200.0 * 1000.0
  } else {
    self.rest = at
  }
}

///|
/// Android's stretch at `now` (view heights), as its path says; (0, 0) once gone.
pub fn BackPath::edge_now(self : BackPath, h : Double, now : Double) -> (Double, Double) {
  if now >= self.rest {
    (0.0, 0.0)
  } else if now >= self.lin_at {
    (dmax(self.lin_x - 200.0 * (now - self.lin_at) / 1000.0 / h, 0.0), -200.0)
  } else if now >= self.clamp_at {
    let (x, v) = edge_spring_at(1.0, 0.0, h, (now - self.clamp_at) / 1000.0)
    (x / h, v)
  } else {
    let (x, v) = edge_spring_at(self.x0, self.v0, h, (now - self.t0) / 1000.0)
    (dmin(x / h, 1.0), v)
  }
}

///|
/// iOS's rubber band going back from (x0, v0): when it is gone. From the end itself going out (a fling meeting it), not
/// gone as it sets out: it bounces past it first.
pub fn BackPath::plan_rubber(self : BackPath) -> Unit {
  let x0 = self.x0
  let v0 = self.v0
  let end = first_when(
    fn(t) {
      let (x, v) = rubber_at(x0, v0, t)
      (x <= 0.0 && (t > 0.0 || v0 <= 0.0)) || (x < 0.1 && v.abs() < 0.01)
    },
    1.0,
    60000.0,
  )
  self.rest = self.t0 + end
}

///|
/// A wheel's notch's ease (ms): the time constant of the follow its notches are eased in by, critically damped, as a
/// browser eases one (Chromium's smooth scroll, ~200 ms a notch): one from rest sets out slowly, half of it come by
/// 1.7 of these (71 ms), 95 in 100 by 4.7 (200 ms). A notch turned while another is coming carries on from where the
/// list is and how fast it moves then, so a wheel turned on scrolls at its pace, not in a burst a notch (an ease out of
/// 36 ms from each notch, 2026-10-26: a notch every 80 ms moved the list eight times faster at it than between).
pub let wheel_ease_ms : Double = 42.0

///|
/// How much of a wheel's ease of `total` has come `t` ms after it set out at `v0` (px a ms, the way `total` goes when
/// positive): solved for the time (critically damped, wheel_ease_ms: what is left (total + (total / τ - v0) t)
/// e^(-t / τ)), in whole 1/64 px, all of it from ease_end on. The same at any time whatever frames it went by.
pub fn ease_come(total : Double, v0 : Double, t : Double) -> Double {
  if t >= ease_end(total, v0) {
    total
  } else {
    let left = (total + (total / wheel_ease_ms - v0) * t) * @dmath.exp(-t / wheel_ease_ms)
    ((total - left) * 64.0).round() / 64.0
  }
}

///|
/// Where an ease (ease_come) is `t` ms after it set out, and how fast it moves then (px a ms): what a notch turned then
/// takes over (ui's Ctx::ease_list; Scroll::list's notches).
pub fn ease_state(total : Double, v0 : Double, t : Double) -> (Double, Double) {
  let t = dmax(0.0, t)
  if t >= ease_end(total, v0) {
    (total, 0.0)
  } else {
    let k = total / wheel_ease_ms - v0
    (ease_come(total, v0, t), (v0 + k * t / wheel_ease_ms) * @dmath.exp(-t / wheel_ease_ms))
  }
}

///|
/// When an ease of `total` set out at `v0` has all come (ms after it set out): what is left under 1/128 px from then on.
/// What is left is at most (|total| + |k| t) e^(-t / τ) (k = total / τ - v0), and t e^(-t / 4τ) at most 4τ / e: so at
/// most (|total| + 4 |k| τ / e) e^(-3t / 4τ), under 1/128 from the time solved here (a little after the least).
pub fn ease_end(total : Double, v0 : Double) -> Double {
  let k = (total / wheel_ease_ms - v0).abs()
  let most = (total.abs() + 4.0 * k * wheel_ease_ms / @dmath.exp(1.0)) * 128.0
  if most <= 1.0 {
    0.0
  } else {
    wheel_ease_ms * 4.0 / 3.0 * @dmath.ln(most)
  }
}

///|
/// A wheel's notch (what hosts the tree adds to a wheel's `mods` for one: a mouse's wheel, not a trackpad's fingers
/// nor their momentum): a page's list eases it in (Scroll::list), as an old view's list does (ui's Ctx::ease_list).
pub let wheel_notch : Int = 32

///|
/// A trackpad's pinch (ui's wheel_mod_pinch, in a wheel's `mods`): what zooms takes it, no list scrolls by it.
pub let wheel_pinch : Int = 16
