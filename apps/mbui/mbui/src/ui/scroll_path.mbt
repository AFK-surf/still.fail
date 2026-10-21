// A list's own motion as data (docs/determinism.md, "Motion is data"): a fling and an overscroll springing back are
// each said once, as they set out (where from, how fast, from when), and their place at a frame is a function of that
// frame's time alone, the same at 60 Hz, at 120 Hz or in one frame of a test. Each knows when it is at rest: the
// framework draws frames until then (ListState's rest_at), none after, and a test runs to it (Ctx::list_rest).

///|
/// An overscroll springing back (scroll.mbt): from `x0` (Android: the view's heights; iOS: points) at `v0` outward
/// (Android: pixels per second; iOS: points per ms), set out at `t0` (-1: at its next frame). Android's may meet the
/// stretch's limit (1) on its way out (`clamp_at`: from there it springs from 1, still) and, once close, go straight in
/// at 200 pixels a second (`lin_at`, from `lin_x`); at rest (gone) at `rest`. +inf: not that.
priv struct BackPath {
  mut t0 : Double
  mut x0 : Double
  mut v0 : Double
  mut clamp_at : Double
  mut lin_at : Double
  mut lin_x : Double
  mut rest : Double
}

///|
fn BackPath::new() -> BackPath {
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
fn edge_spring_at(dist : Double, vel : Double, h : Double, dt : Double) -> (Double, Double) {
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
fn rubber_at(x0 : Double, v0 : Double, t : Double) -> (Double, Double) {
  let w = rubber_omega
  let e = @dmath.exp(-w * t)
  ((x0 + (v0 + w * x0) * t) * e, (v0 - w * (v0 + w * x0) * t) * e)
}

///|
/// The first time (in the unit `at` takes, from 0, by `step`, up to `most`) at which `hit` holds, found to the
/// floating point's last bit between the step it holds at and the one before; +inf when it never does.
fn first_when(hit : (Double) -> Bool, step : Double, most : Double) -> Double {
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
fn BackPath::plan_edge(self : BackPath, h : Double) -> Unit {
  let gone = fn(x : Double, v : Double) { x < 0.0 || (v.abs() < 0.01 && x < 0.001) }
  let close = fn(x : Double, v : Double) { v.abs() <= 200.0 && x.abs() < 8.0 && v < 0.0 && x > 0.0 }
  // (seconds, in steps of a millisecond)
  let mut from_t = 0.0
  let mut x0 = self.x0
  let mut v0 = self.v0
  if x0 < 1.0 {
    let x0_ = x0
    let v0_ = v0
    let out = first_when(fn(t) { edge_spring_at(x0_, v0_, h, t).0 / h > 1.0 }, 0.001, 60.0)
    let first = first_when(
      fn(t) {
        let (x, v) = edge_spring_at(x0_, v0_, h, t)
        gone(x, v) || close(x, v)
      },
      0.001,
      60.0,
    )
    if out < first {
      self.clamp_at = self.t0 + out * 1000.0
      from_t = out
      x0 = 1.0
      v0 = 0.0
    }
  }
  let x0_ = x0
  let v0_ = v0
  let end = first_when(
    fn(t) {
      let (x, v) = edge_spring_at(x0_, v0_, h, t)
      gone(x, v) || close(x, v)
    },
    0.001,
    60.0,
  )
  if end == @double.infinity {
    self.rest = @double.infinity
    return
  }
  let (x, v) = edge_spring_at(x0_, v0_, h, end)
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
fn BackPath::edge_now(self : BackPath, h : Double, now : Double) -> (Double, Double) {
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
/// iOS's rubber band going back from (x0, v0): when it is gone.
fn BackPath::plan_rubber(self : BackPath) -> Unit {
  let x0 = self.x0
  let v0 = self.v0
  let end = first_when(
    fn(t) {
      let (x, v) = rubber_at(x0, v0, t)
      x <= 0.0 || (x < 0.1 && v.abs() < 0.01)
    },
    1.0,
    60000.0,
  )
  self.rest = self.t0 + end
}
