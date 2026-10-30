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
/// How far back the velocity tracker looks (ms; Compose's HorizonMilliseconds), and the pause after which it takes the
/// pointer to have stopped (AssumePointerMoveStoppedMilliseconds).
pub let tracker_horizon_ms : Double = 100.0

///|
pub let tracker_gap_ms : Double = 40.0

///|
/// How lists scroll here: 0 the desktop's, 1 iOS's, 2 Android's.
fn scroll_kind() -> Int {
  match h_feel() {
    1 => 1
    2 => 2
    _ => 0
  }
}

///|
/// How far a finger moves before it drags (logical pixels): Android's
/// ViewConfiguration touch slop, 8 dp; 6 elsewhere.
pub fn touch_slop() -> Double {
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
    if age > tracker_horizon_ms || gap > tracker_gap_ms {
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
// kept across runs: a constant, computed once: nothing writes it after
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
let deceleration_rate : Double = @dmath.ln(0.78) / @dmath.ln(0.9)

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
  let exp_part = 0.016 * (1.0 - @dmath.exp(-o * (2.718281828459045 / 0.33)))
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
/// The hand moved the list between frames (a finger dragging it, a wheel): what lays it out (Ctx::place_list) is told,
/// so that the next frame lays it out again, nothing built for it.
fn ListState::hand_moved(self : ListState) -> Unit {
  self.hand_said.set(@signals.untracked(fn() { self.hand_said.get() }) + 1)
}

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
  // (moved by the hand: what it shows moves for no row's cause, rows_steady.mbt)
  st.put_at = self.clock
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
  if source == 1 {
    self.scrolled(st)
    // a finger takes over from a glide to the end (Ctx::list_to_end), and lets go of a row followed
    st.glide = false
    st.follow_item = -1
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
  // the fling ends here, now; what it took springs out and back from now
  st.last_scroll = self.clock
  let v = if kind == 2 {
    // pixels per second, times EdgeEffect's ON_ABSORB_VELOCITY_ADJUSTMENT
    (speed * 1000.0 * self.scale).round() * 13.0
  } else {
    speed
  }
  self.spring_back(st, v, self.clock)
}

///|
/// What is past an end springs back from where it is at `v` outward, from `t0` (-1: its next frame), said once as it
/// sets out (Ctx::moving: its path's end is when it is at rest).
fn Ctx::spring_back(self : Ctx, st : ListState, v : Double, t0 : Double) -> Unit {
  st.over_state = 2
  st.over_v = v
  let p = BackPath::new()
  p.x0 = st.over
  p.v0 = v
  st.back = p
  if t0 >= 0.0 {
    self.plan_back(st, t0)
  }
  self.moving(st.ease_mover, st as &Moving, what="a list's overscroll going back")
}

///|
/// The way back worked out, set out at `t0`.
fn Ctx::plan_back(self : Ctx, st : ListState, t0 : Double) -> Unit {
  let p = st.back
  p.t0 = t0
  if scroll_kind() == 2 {
    p.plan_edge(dmax(st.vp_h * self.scale, 1.0))
  } else {
    p.plan_rubber()
  }
}

///|
/// A fling's end, as it was said (the frames' clock): -1 none, +inf not started (it starts at its next frame).
fn ListState::fling_rest(self : ListState) -> Double {
  if self.fling == 0 || self.vel == 0.0 {
    return -1.0
  }
  if self.fling_t0 < 0.0 {
    return @double.infinity
  }
  self.fling_t0 + self.fling_length()
}

///|
/// How long a fling runs from its start (ms): Android's spline its duration in whole ms played (Compose's playtime);
/// iOS's deceleration and the desktop's coast until under 0.02 px per ms.
fn ListState::fling_length(self : ListState) -> Double {
  match self.fling {
    1 => self.fling_dur.ceil()
    2 => dmax(0.0, @dmath.ln(0.02 / self.fling_v.abs()) / @dmath.ln(ios_decel))
    _ => dmax(0.0, @dmath.ln(0.02 / self.fling_v.abs()) / @dmath.ln(coast_decel))
  }
}

///|
/// The overscroll's way back's end (the frames' clock): -1 none, +inf not started.
fn ListState::back_rest(self : ListState) -> Double {
  if self.over_state != 2 {
    -1.0
  } else if self.back.t0 < 0.0 {
    @double.infinity
  } else {
    self.back.rest
  }
}

///|
/// UIScrollView's normal deceleration rate (per ms).
let ios_decel : Double = 0.998

///|
/// The desktop's coast after a drag let go (per ms).
let coast_decel : Double = 0.997

///|
/// The finger left the list at `v` (logical pixels per ms, positive down
/// the list) at `at` (the input's time): it flings, or what it pulled past an end goes back.
fn Ctx::release(self : Ctx, st : ListState, v : Double, at : Double) -> Unit {
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
        self.spring_back(st, -(v.abs() * 1000.0 * self.scale).round() * 13.0, -1.0)
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
      self.moving(st.ease_mover, st as &Moving, what="a list's fling")
    }
    // a stretch left as it is goes back once the fling is over (step)
  } else if kind == 1 {
    if st.over_state == 1 && st.over > 0.0 {
      st.over = rubber(st.over, st.vp_h)
      // moving away from the content is outward
      self.spring_back(st, if st.over_edge > 0 { -v } else { v }, -1.0)
    } else if v.abs() >= 0.02 {
      st.fling = 2
      st.fling_v = v
      st.fling_t0 = -1.0
      st.fling_done = 0.0
      st.vel = v
      self.moving(st.ease_mover, st as &Moving, what="a list's fling")
    }
  } else if v.abs() >= 0.02 {
    // the desktop's coast sets out as the finger lets go
    st.fling = 3
    st.fling_v = v
    st.fling_t0 = at
    st.fling_done = 0.0
    st.vel = v
    self.moving(st.ease_mover, st as &Moving, what="a list's coast")
  }
}

///|
/// A frame of the list's own motion: its fling, and its overscroll going back, where each is at this frame's time by
/// what was said as it set out (scroll_path.mbt).
fn Ctx::step_scroll(self : Ctx, st : ListState) -> Unit {
  if st.vel != 0.0 && st.fling != 0 {
    // Android's and iOS's start at their first frame (Compose's playtime 0); the desktop's coast as it was let go
    if st.fling_t0 < 0.0 {
      st.fling_t0 = self.clock
    }
    let end = st.fling_t0 + st.fling_length()
    let t = dmin(self.now_before(end), end) - st.fling_t0
    let sign = if st.fling_v < 0.0 { -1.0 } else { 1.0 }
    let (pos, vel) = match st.fling {
      1 => {
        // Compose's decay animation: in whole ms played
        let (share, vc) = spline_at(t.floor(), st.fling_dur)
        (sign * st.fling_dist * share, sign * vc * st.fling_dist / dmax(st.fling_dur, 1.0))
      }
      2 => {
        // UIScrollView's normal deceleration
        let k = ios_decel
        (st.fling_v * (@dmath.pow(k, t) - 1.0) / @dmath.ln(k), st.fling_v * @dmath.pow(k, t))
      }
      _ => {
        // the desktop's coast
        let k = coast_decel
        (st.fling_v * (@dmath.pow(k, t) - 1.0) / @dmath.ln(k), st.fling_v * @dmath.pow(k, t))
      }
    }
    let d = pos - st.fling_done
    st.fling_done = pos
    self.feed(st, d, 2)
    if self.clock >= end {
      st.stop()
      // its scroll bar fades from the fling's end
      st.last_scroll = end
    } else {
      st.vel = if vel == 0.0 { sign * 1.0e-9 } else { vel }
    }
  }
  // a stretch held by nothing (the finger gone, its fling over) goes back
  if st.over_state == 1 && !st.held && st.vel == 0.0 {
    if scroll_kind() == 1 {
      st.over = rubber(st.over, st.vp_h)
    }
    self.spring_back(st, 0.0, self.clock)
  }
  if st.over_state == 2 {
    if st.back.t0 < 0.0 {
      self.plan_back(st, self.clock)
    }
    let p = st.back
    if self.clock >= p.rest {
      st.over = 0.0
      st.over_v = 0.0
      st.over_state = 0
      st.over_edge = 0
      st.last_scroll = p.rest
    } else if scroll_kind() == 2 {
      let (x, v) = p.edge_now(dmax(st.vp_h * self.scale, 1.0), self.now())
      st.over = x
      st.over_v = v
    } else {
      let (x, v) = rubber_at(p.x0, p.v0, self.now() - p.t0)
      st.over = x
      st.over_v = v
    }
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
    // (and what it fades towards)
    if a[b + 53] > 0.0 {
      let (f0, f1) = (map(a[b + 52]), map(a[b + 52] + a[b + 53]))
      a[b + 52] = f0
      a[b + 53] = f1 - f0
    }
    if a[b + 55] > 0.0 {
      let (f0, f1) = (map(a[b + 54] - a[b + 55]), map(a[b + 54]))
      a[b + 54] = f1
      a[b + 55] = f1 - f0
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
      None => if @hostapi.env("MBUI_SCROLL_LOG") == "1" { 1 } else { 0 }
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
        h_log("SCROLL \{self.clock} \{off} \{stretch} \{st.vel}")
      }
    }
    None => ()
  }
}
