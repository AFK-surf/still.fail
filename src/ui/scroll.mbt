// How a list moves under a finger and after it, as each platform's own lists
// do:
//
// - the finger's velocity, on every platform, is Compose's VelocityTracker
//   (androidx.compose.ui.input.pointer.util, its default Lsq2 strategy): a
//   quadratic fitted by least squares to the last 100 ms of samples, cut at
//   a pause of more than 40 ms, its slope at the newest sample;
// - Android (scroll kind 2) flings as Compose's default fling does
//   (DefaultFlingBehavior over splineBasedDecay: the OverScroller spline,
//   ViewConfiguration's scroll friction 0.015, a physical deceleration from
//   the screen's density) and shows Android 12's stretch at the ends
//   (android.widget.EdgeEffect's stretch, and the way Compose's
//   AndroidEdgeEffectOverscrollEffect pulls, relaxes and absorbs it);
// - iOS (kind 1) decelerates as UIScrollView's normal rate (0.998 per ms) and
//   pulls past the ends on a rubber band that springs back;
// - the desktop (kind 0: macOS, Windows, a browser) keeps what it had: a
//   mouse drag coasts, slowing 0.997 per ms, and stops at the ends (a
//   trackpad's momentum comes from the system as wheel events).

///|
/// How lists scroll here: 0 the desktop's, 1 iOS's, 2 Android's.
fn scroll_kind() -> Int {
  match h_platform() {
    1 => 1
    2 => 2
    _ => 0
  }
}

///|
/// How far a finger moves before it drags (logical pixels): Android's
/// ViewConfiguration touch slop, 8 dp; 6 elsewhere.
fn touch_slop() -> Double {
  if scroll_kind() == 2 {
    8.0
  } else {
    6.0
  }
}

///|
/// The fastest fling, in logical pixels per ms: Android's maximum fling
/// velocity, 8000 dp/s.
let max_fling : Double = 8.0

// ---------------------------------------------------------------------------
// Velocity

///|
let track_size = 20

///|
/// One coordinate of a pointer over time: Compose's VelocityTracker1D with
/// the Lsq2 strategy (and its absolute data points).
priv struct Tracker {
  times : FixedArray[Double]
  vals : FixedArray[Double]
  mut index : Int
  mut n : Int
}

///|
fn Tracker::new() -> Tracker {
  {
    times: FixedArray::make(track_size, 0.0),
    vals: FixedArray::make(track_size, 0.0),
    index: 0,
    n: 0,
  }
}

///|
fn Tracker::reset(self : Tracker) -> Unit {
  self.index = 0
  self.n = 0
}

///|
/// A sample: the coordinate `v` at `t` (ms).
fn Tracker::add(self : Tracker, t : Double, v : Double) -> Unit {
  self.index = (self.index + 1) % track_size
  self.times[self.index] = t
  self.vals[self.index] = v
  if self.n < track_size {
    self.n = self.n + 1
  }
}

///|
/// Units per ms at the newest sample (0 when it can't tell).
fn Tracker::velocity(self : Tracker) -> Double {
  if self.n == 0 {
    return 0.0
  }
  let xs = FixedArray::make(track_size, 0.0)
  let ys = FixedArray::make(track_size, 0.0)
  let newest = self.times[self.index]
  let mut prev = newest
  let mut idx = self.index
  let mut count = 0
  while count < self.n {
    let t = self.times[idx]
    let age = newest - t
    let gap = (t - prev).abs()
    prev = t
    if age > 100.0 || gap > 40.0 {
      break
    }
    ys[count] = self.vals[idx]
    xs[count] = -age
    idx = (if idx == 0 { track_size } else { idx }) - 1
    count = count + 1
  }
  if count < 2 {
    return 0.0
  }
  let v = lsq_slope(xs, ys, count)
  if v != v {
    0.0
  } else {
    v
  }
}

///|
fn dot(a : FixedArray[Double], b : FixedArray[Double], m : Int) -> Double {
  let mut s = 0.0
  for h in 0..<m {
    s = s + a[h] * b[h]
  }
  s
}

///|
/// The slope at x = 0 of the polynomial of degree 2 (1 with two points)
/// fitted to the points by least squares: Compose's polyFitLeastSquares
/// (QR by Gram-Schmidt, back-substituted).
fn lsq_slope(x : FixedArray[Double], y : FixedArray[Double], m : Int) -> Double {
  let n = if m > 2 { 3 } else { m }
  let a = Array::makei(n, fn(_) { FixedArray::make(m, 0.0) })
  for h in 0..<m {
    a[0][h] = 1.0
    for i in 1..<n {
      a[i][h] = a[i - 1][h] * x[h]
    }
  }
  let q = Array::makei(n, fn(_) { FixedArray::make(m, 0.0) })
  let r = Array::makei(n, fn(_) { FixedArray::make(n, 0.0) })
  for j in 0..<n {
    let w = q[j]
    for h in 0..<m {
      w[h] = a[j][h]
    }
    for i in 0..<j {
      let d = dot(w, q[i], m)
      for h in 0..<m {
        w[h] = w[h] - d * q[i][h]
      }
    }
    let inv = 1.0 / dmax(dot(w, w, m).sqrt(), 1.0e-6)
    for h in 0..<m {
      w[h] = w[h] * inv
    }
    for i in 0..<n {
      r[j][i] = if i < j { 0.0 } else { dot(w, a[i], m) }
    }
  }
  let coef = FixedArray::make(n, 0.0)
  for i = n - 1; i >= 0; i = i - 1 {
    let mut c = dot(q[i], y, m)
    for j = n - 1; j > i; j = j - 1 {
      c = c - r[i][j] * coef[j]
    }
    coef[i] = c / r[i][i]
  }
  coef[1]
}

// ---------------------------------------------------------------------------
// Android's fling: Compose's FlingCalculator over AndroidFlingSpline

///|
/// The spline's distance at 101 evenly spaced times (computeSplineInfo).
let spline_positions : FixedArray[Double] = compute_spline()

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
let deceleration_rate : Double = @math.ln(0.78) / @math.ln(0.9)

///|
/// A fling at `v` pixels per second (physical pixels, on a screen of
/// `density` pixels per dp): how far it goes (pixels) and how long it
/// takes (whole ms), as Compose's FlingCalculator has them.
fn spline_fling(v : Double, density : Double) -> (Double, Double) {
  let speed = v.abs()
  if speed == 0.0 {
    return (0.0, 0.0)
  }
  // gravity × inches per meter × 160 dpi × density × 0.84, by the friction
  let physical = 386.0878 * 160.0 * density * 0.84
  let friction = 0.015 * physical
  let l = @math.ln(0.35 * speed / friction)
  let dur = (1000.0 * @math.exp(l / (deceleration_rate - 1.0))).floor()
  let dist = friction *
    @math.exp(deceleration_rate / (deceleration_rate - 1.0) * l)
  (dist, dmax(dur, 0.0))
}

///|
/// Where along a spline fling `dur` ms long it is at `t` ms: the share of
/// its distance gone and its velocity in distances per unit of time
/// (AndroidFlingSpline.flingPosition).
fn spline_at(t : Double, dur : Double) -> (Double, Double) {
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
fn fling_distance(v : Double, density : Double) -> Double {
  spline_fling(v * 1000.0 * density, density).0 / density
}

// ---------------------------------------------------------------------------
// Overscroll

///|
/// Android's stretch intensity for a pull of `d` (in the view's heights):
/// EdgeEffect.dampStretchVector.
fn stretch_amount(d : Double) -> Double {
  let o = d.abs()
  let linear = 0.016 * o
  let exp_part = 0.016 * (1.0 - @math.exp(-o * (2.718281828459045 / 0.33)))
  linear + exp_part
}

///|
/// Where a point `p` of the content (0 the top of the view, 1 its bottom)
/// shows under a stretch of `ov` (positive from the top, negative from the
/// bottom): HWUI StretchEffect's computeReverseOverscroll, the inverse of
/// its shader. Outside the view it moves as the view's edge does.
fn stretch_map(ov : Double, p : Double) -> Double {
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
fn rubber(x : Double, d : Double) -> Double {
  let d = dmax(d, 1.0)
  (1.0 - 1.0 / (x * 0.55 / d + 1.0)) * d
}

///|
/// The pull that shows as `y` past the end (rubber's inverse).
fn unrubber(y : Double, d : Double) -> Double {
  let d = dmax(d, 1.0)
  let y = dmin(y, d * 0.999)
  y * d / (0.55 * (d - y))
}

///|
/// The rubber band's spring back (critically damped), per ms.
let rubber_omega : Double = 0.0157

///|
/// Ends the list's fling at once.
fn ListState::stop(self : ListState) -> Unit {
  self.vel = 0.0
  self.fling = 0
}

///|
/// A finger came down on the list: a fling stops, an overscroll that is
/// springing back is caught where it shows.
fn ListState::catch_up(self : ListState) -> Unit {
  self.stop()
  if self.over_state == 2 {
    if scroll_kind() == 1 {
      self.over = unrubber(self.over, self.vp_h)
    }
    self.over_state = 1
    self.over_v = 0.0
  }
}

///|
/// Whether the list moves on its own (a fling, an overscroll springing
/// back): a finger coming down then drags it at once, no slop.
fn ListState::moving(self : ListState) -> Bool {
  self.vel != 0.0 || self.over_state == 2
}

///|
/// Scrolls by `d` (positive: down the list) from `source` (1 a finger, 2 a
/// fling): what of it undoes an overscroll does that first (Compose's
/// applyToScroll, relaxing a stretch four times as fast in a fling).
fn Ctx::feed(self : Ctx, st : ListState, d : Double, source : Int) -> Unit {
  let mut d = d
  // an overscroll at the top is undone by scrolling down, at the bottom up
  let undoes = st.over > 0.0 &&
    ((st.over_edge > 0 && d > 0.0) || (st.over_edge < 0 && d < 0.0))
  if undoes {
    let kind = scroll_kind()
    if kind == 2 {
      let mult = if source == 2 { 4.0 } else { 1.0 }
      let h = dmax(st.vp_h, 1.0)
      let left = dmax(0.0, st.over - d.abs() * mult / h)
      let used = (st.over - left) * h / mult
      st.over = left
      if left > 0.0 {
        st.over_state = 1
        st.over_v = 0.0
        d = 0.0
      } else {
        st.over_state = 0
        st.over_edge = 0
        st.over_v = 0.0
        d = if d > 0.0 { d - used } else { d + used }
      }
    } else if kind == 1 && st.over_state == 1 {
      let used = dmin(d.abs(), st.over)
      st.over = st.over - used
      if st.over <= 0.0 {
        st.over = 0.0
        st.over_state = 0
        st.over_edge = 0
      }
      d = if d > 0.0 { d - used } else { d + used }
    }
  }
  st.pending = st.pending + d
  st.last_scroll = self.now
  if source == 1 {
    // a finger takes over from a glide to the end (Ctx::list_to_end)
    st.glide = false
    st.drag_pending = st.drag_pending + d
  }
}

///|
/// A finger pulled `by` past an end (edge 1 the top, -1 the bottom).
fn Ctx::pull(self : Ctx, st : ListState, edge : Int, by : Double) -> Unit {
  let kind = scroll_kind()
  // Compose leaves out less than half a pixel (rounding)
  if kind == 0 || by * self.scale <= 0.5 {
    return
  }
  if st.over_edge != edge {
    st.over = 0.0
  }
  st.over_edge = edge
  st.over_state = 1
  st.over_v = 0.0
  if kind == 2 {
    st.over = dmin(1.0, st.over + by / dmax(st.vp_h, 1.0))
  } else {
    st.over = st.over + by
  }
}

///|
/// A fling reached an end (edge 1 the top, -1 the bottom) at `vel` logical
/// pixels per ms: Android stretches with it (EdgeEffect.onAbsorb), iOS
/// bounces past the end and back.
fn Ctx::absorb(self : Ctx, st : ListState, edge : Int, vel : Double) -> Unit {
  let kind = scroll_kind()
  let speed = vel.abs()
  st.stop()
  if kind == 0 || speed == 0.0 {
    return
  }
  if st.over_edge != edge {
    st.over = 0.0
  }
  st.over_edge = edge
  st.over_state = 2
  st.over_t = self.now
  st.over_v = if kind == 2 {
    // pixels per second, times EdgeEffect's ON_ABSORB_VELOCITY_ADJUSTMENT
    (speed * 1000.0 * self.scale).round() * 13.0
  } else {
    speed
  }
  self.request_frame()
}

///|
/// The finger left the list at `v` (logical pixels per ms, positive down
/// the list): it flings, or what it pulled past an end goes back.
fn Ctx::release(self : Ctx, st : ListState, v : Double) -> Unit {
  st.held = false
  if scroll_logging() {
    let (dist, dur) = spline_fling(v * 1000.0 * self.scale, self.scale)
    h_log("FLING \{v} \{dist / self.scale} \{dur} scale=\{self.scale}")
  }
  let kind = scroll_kind()
  if kind == 2 {
    // Compose's applyToFling: a fling back from a stretch no further than
    // the stretch is all absorbed by it
    if st.over > 0.0 && st.over_state == 1 {
      let away = (st.over_edge > 0 && v > 0.0) || (st.over_edge < 0 && v < 0.0)
      if away &&
        fling_distance(v, self.scale) <= st.over * dmax(st.vp_h, 1.0) {
        st.over_state = 2
        st.over_t = -1.0
        st.over_v = -(v.abs() * 1000.0 * self.scale).round() * 13.0
        return
      }
    }
    // DefaultFlingBehavior flings above 1 pixel per second
    if v.abs() * 1000.0 * self.scale > 1.0 {
      let (dist, dur) = spline_fling(v * 1000.0 * self.scale, self.scale)
      st.fling = 1
      st.fling_v = v
      st.fling_t0 = -1.0
      st.fling_dist = dist / self.scale
      st.fling_dur = dur
      st.fling_done = 0.0
      st.vel = v
    }
    // a stretch left as it is goes back once the fling is over (step)
  } else if kind == 1 {
    if st.over_state == 1 && st.over > 0.0 {
      st.over = rubber(st.over, st.vp_h)
      st.over_state = 2
      st.over_t = -1.0
      // moving away from the content is outward
      st.over_v = if st.over_edge > 0 { -v } else { v }
    } else if v != 0.0 {
      st.fling = 2
      st.fling_v = v
      st.fling_t0 = -1.0
      st.fling_done = 0.0
      st.vel = v
    }
  } else {
    st.fling = 0
    st.vel = v
  }
  self.request_frame()
}

///|
/// A frame of the list's own motion: its fling, and its overscroll going
/// back.
fn Ctx::step_scroll(self : Ctx, st : ListState) -> Unit {
  if st.vel != 0.0 {
    st.last_scroll = self.now
    if st.fling == 1 {
      // Compose's decay animation: playtime 0 at its first frame, in whole ms
      if st.fling_t0 < 0.0 {
        st.fling_t0 = self.now
      }
      let t = (self.now - st.fling_t0).floor()
      let (share, vc) = spline_at(t, st.fling_dur)
      let sign = if st.fling_v < 0.0 { -1.0 } else { 1.0 }
      let pos = sign * st.fling_dist * share
      let d = pos - st.fling_done
      st.fling_done = pos
      self.feed(st, d, 2)
      if t >= st.fling_dur {
        st.stop()
      } else {
        let v = sign * vc * st.fling_dist / dmax(st.fling_dur, 1.0)
        st.vel = if v == 0.0 { sign * 1.0e-9 } else { v }
        self.request_frame()
      }
    } else if st.fling == 2 {
      // UIScrollView's normal deceleration
      if st.fling_t0 < 0.0 {
        st.fling_t0 = self.now
      }
      let t = self.now - st.fling_t0
      let k = 0.998
      let pos = st.fling_v * (@math.pow(k, t) - 1.0) / @math.ln(k)
      let d = pos - st.fling_done
      st.fling_done = pos
      self.feed(st, d, 2)
      st.vel = st.fling_v * @math.pow(k, t)
      if st.vel.abs() < 0.02 {
        st.stop()
      } else {
        self.request_frame()
      }
    } else {
      st.pending = st.pending + st.vel * self.dt
      st.vel = st.vel * @math.pow(0.997, self.dt)
      if st.vel.abs() < 0.02 {
        st.vel = 0.0
      } else {
        self.request_frame()
      }
    }
  }
  // a stretch held by nothing (the finger gone, its fling over) goes back
  if st.over_state == 1 && !st.held && st.vel == 0.0 {
    if scroll_kind() == 1 {
      st.over = rubber(st.over, st.vp_h)
    }
    st.over_state = 2
    st.over_v = 0.0
    st.over_t = self.now
  }
  if st.over_state == 2 {
    st.last_scroll = self.now
    if st.over_t < 0.0 {
      st.over_t = self.now
    }
    if scroll_kind() == 2 {
      self.edge_spring(st)
    } else {
      self.rubber_spring(st)
    }
    if st.over_state == 2 {
      self.request_frame()
    }
  }
}

///|
/// Android's stretch going back: EdgeEffect.updateSpring, in physical
/// pixels and seconds.
fn Ctx::edge_spring(self : Ctx, st : ListState) -> Unit {
  let dt = (self.now - st.over_t) / 1000.0
  if dt < 0.001 {
    return
  }
  st.over_t = self.now
  let h = dmax(st.vp_h * self.scale, 1.0)
  let dist = st.over
  let vel = st.over_v
  let settle = fn() {
    st.over = 0.0
    st.over_v = 0.0
    st.over_state = 0
    st.over_edge = 0
  }
  if vel.abs() <= 200.0 && (dist * h).abs() < 8.0 && vel < 0.0 && dist > 0.0 {
    // close: straight there, faster than the spring would
    let target = dist + -200.0 * dt / h
    if target <= 0.0 {
      settle()
    } else {
      st.over = target
      st.over_v = -200.0
    }
    return
  }
  let w = 24.657
  let z = 0.98
  let wd = w * (1.0 - z * z).sqrt()
  let cos_c = dist * h
  let sin_c = 1.0 / wd * (z * w * dist * h + vel)
  let e = @math.exp(-z * w * dt)
  let x = e * (cos_c * @math.cos(wd * dt) + sin_c * @math.sin(wd * dt))
  let v = x * -w * z +
    e * (-wd * cos_c * @math.sin(wd * dt) + wd * sin_c * @math.cos(wd * dt))
  st.over = x / h
  st.over_v = v
  if st.over > 1.0 {
    st.over = 1.0
    st.over_v = 0.0
  }
  if x < 0.0 || (v.abs() < 0.01 && x < 0.001) {
    settle()
  }
}

///|
/// The rubber band going back to the end: critically damped, `over` as it
/// shows, its velocity outward.
fn Ctx::rubber_spring(self : Ctx, st : ListState) -> Unit {
  let t = self.now - st.over_t
  if t < 0.5 {
    return
  }
  st.over_t = self.now
  let w = rubber_omega
  let x0 = st.over
  let v0 = st.over_v
  let e = @math.exp(-w * t)
  let x = (x0 + (v0 + w * x0) * t) * e
  let v = (v0 - w * (v0 + w * x0) * t) * e
  st.over = x
  st.over_v = v
  if x <= 0.0 || (x < 0.1 && v.abs() < 0.01) {
    st.over = 0.0
    st.over_v = 0.0
    st.over_state = 0
    st.over_edge = 0
  }
}

///|
/// How far the list's rows show moved by its overscroll (iOS's rubber
/// band; Android's stretch moves nothing, it is drawn stretched).
fn ListState::over_offset(self : ListState) -> Double {
  if self.over_edge == 0 || self.over <= 0.0 || scroll_kind() != 1 {
    return 0.0
  }
  let shown = if self.over_state == 1 {
    rubber(self.over, self.vp_h)
  } else {
    self.over
  }
  shown * self.over_edge.to_double()
}

///|
/// The list's rows (instances `from` on, drawn in the view from `top`, `h`
/// high, clipped to `c0`-`c1`) as Android's stretch shows them.
fn Ctx::stretch_rows(
  self : Ctx,
  st : ListState,
  from : Int,
  top : Double,
  h : Double,
  c0 : Double,
  c1 : Double,
) -> Unit {
  if scroll_kind() != 2 || st.over <= 0.0 || st.over_edge == 0 || h <= 0.0 {
    return
  }
  let ov = stretch_amount(st.over) * st.over_edge.to_double()
  let map = fn(y : Double) { top + h * stretch_map(ov, (y - top) / h) }
  let a = self.inst
  for k in from..<self.ninst {
    let b = k * inst_size
    let y0 = map(a[b + 1])
    let y1 = map(a[b + 1] + a[b + 3])
    a[b + 1] = y0
    a[b + 3] = y1 - y0
    // clips inside the list's stretch with it, no further than the list's
    if a[b + 17] > c0 + 0.001 {
      a[b + 17] = dclamp(map(a[b + 17]), c0, c1)
    }
    if a[b + 19] < c1 - 0.001 {
      a[b + 19] = dclamp(map(a[b + 19]), c0, c1)
    }
  }
}

///|
/// The list's scroll position: how far its top is from the top of its first
/// row (rows not measured yet counted at their estimate).
fn ListState::offset(self : ListState) -> Double {
  self.anchor_off + self.above(imin(self.anchor, self.count))
}

///|
/// MBUI_SCROLL_LOG=1 logs each touch (TOUCH kind ms x y, and when it was
/// handled), each fling
/// (FLING velocity distance duration) and, each frame something moves, the
/// first list's position (SCROLL ms offset stretch velocity): for comparing
/// how it moves with how the platform's lists do.
let scroll_log : Ref[Int] = { val: -1 }

///|
fn scroll_logging() -> Bool {
  if scroll_log.val < 0 {
    scroll_log.val = match fake.val {
      Some(_) => 0
      None => if @host.env("MBUI_SCROLL_LOG") == "1" { 1 } else { 0 }
    }
  }
  scroll_log.val == 1
}

///|
let last_logged : Ref[Double] = { val: -1.0e9 }

///|
fn Ctx::log_scroll(self : Ctx) -> Unit {
  match self.lists.get(self.bench_list) {
    Some(st) => {
      let off = st.offset()
      let moving = st.vel != 0.0 || st.over_state != 0
      if moving || off != last_logged.val {
        last_logged.val = off
        let stretch = st.over * st.over_edge.to_double()
        h_log("SCROLL \{self.now} \{off} \{stretch} \{st.vel}")
      }
    }
    None => ()
  }
}
