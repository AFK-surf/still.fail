// A pointer's velocity from its own samples, by their own times: Compose's VelocityTracker
// (androidx.compose.ui.input.pointer.util, its default Lsq2 strategy): a quadratic fitted by least squares to the last
// 100 ms of samples, cut at a pause of more than 40 ms, its slope at the newest sample. What the old views' lists fling
// at (ui's scroll.mbt) and what a hold of the window's tree's is told it goes at (Drag's `vx`, `vy`).

///|
/// How far back the velocity tracker looks (ms; Compose's HorizonMilliseconds), and the pause after which it takes the
/// pointer to have stopped (AssumePointerMoveStoppedMilliseconds).
pub let tracker_horizon_ms : Double = 100.0

///|
pub let tracker_gap_ms : Double = 40.0

///|
let track_size = 20

///|
/// One coordinate of a pointer over time: Compose's VelocityTracker1D with
/// the Lsq2 strategy (and its absolute data points).
pub struct Tracker {
  priv times : FixedArray[Double]
  priv vals : FixedArray[Double]
  priv mut index : Int
  priv mut n : Int
  // (where its velocity is worked out: made as it is first asked for, then kept, so what is asked as each of a
  // finger's events comes makes nothing anew; a tracker never asked, none)
  priv mut fit : Fit?
}

///|
/// Where a velocity is worked out (Tracker::velocity, lsq_slope): the points it fits, and the fit's matrices, each row
/// of `a` and `q` `track_size` long, at `track_size`·i.
priv struct Fit {
  xs : FixedArray[Double]
  ys : FixedArray[Double]
  a : FixedArray[Double]
  q : FixedArray[Double]
  r : FixedArray[Double]
  coef : FixedArray[Double]
}

///|
fn Fit::new() -> Fit {
  {
    xs: FixedArray::make(track_size, 0.0),
    ys: FixedArray::make(track_size, 0.0),
    a: FixedArray::make(3 * track_size, 0.0),
    q: FixedArray::make(3 * track_size, 0.0),
    r: FixedArray::make(9, 0.0),
    coef: FixedArray::make(3, 0.0),
  }
}

///|
pub fn Tracker::new() -> Tracker {
  {
    times: FixedArray::make(track_size, 0.0),
    vals: FixedArray::make(track_size, 0.0),
    index: 0,
    n: 0,
    fit: None,
  }
}

///|
pub fn Tracker::reset(self : Tracker) -> Unit {
  self.index = 0
  self.n = 0
}

///|
/// A sample: the coordinate `v` at `t` (ms).
pub fn Tracker::add(self : Tracker, t : Double, v : Double) -> Unit {
  self.index = (self.index + 1) % track_size
  self.times[self.index] = t
  self.vals[self.index] = v
  if self.n < track_size {
    self.n = self.n + 1
  }
}

///|
/// Units per ms at the newest sample (0 when it can't tell).
pub fn Tracker::velocity(self : Tracker) -> Double {
  if self.n == 0 {
    return 0.0
  }
  let fit = match self.fit {
    Some(f) => f
    None => {
      let f = Fit::new()
      self.fit = Some(f)
      f
    }
  }
  let xs = fit.xs
  let ys = fit.ys
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
  let v = lsq_slope(fit, count)
  if v != v {
    0.0
  } else {
    v
  }
}

///|
/// Of `a` from `ai` and `b` from `bi`, the first `m` multiplied pairwise and summed.
fn dot(a : FixedArray[Double], ai : Int, b : FixedArray[Double], bi : Int, m : Int) -> Double {
  let mut s = 0.0
  for h in 0..<m {
    s = s + a[ai + h] * b[bi + h]
  }
  s
}

///|
/// The slope at x = 0 of the polynomial of degree 2 (1 with two points)
/// fitted to the first `m` of `f`'s points by least squares: Compose's
/// polyFitLeastSquares (QR by Gram-Schmidt, back-substituted), in `f`'s
/// matrices.
fn lsq_slope(f : Fit, m : Int) -> Double {
  let x = f.xs
  let y = f.ys
  let a = f.a
  let q = f.q
  let r = f.r
  let coef = f.coef
  let k = track_size
  let n = if m > 2 { 3 } else { m }
  for h in 0..<m {
    a[h] = 1.0
    for i in 1..<n {
      a[i * k + h] = a[(i - 1) * k + h] * x[h]
    }
  }
  for j in 0..<n {
    let w = j * k
    for h in 0..<m {
      q[w + h] = a[j * k + h]
    }
    for i in 0..<j {
      let d = dot(q, w, q, i * k, m)
      for h in 0..<m {
        q[w + h] = q[w + h] - d * q[i * k + h]
      }
    }
    let inv = 1.0 / dmax(dot(q, w, q, w, m).sqrt(), 1.0e-6)
    for h in 0..<m {
      q[w + h] = q[w + h] * inv
    }
    for i in 0..<n {
      r[j * 3 + i] = if i < j { 0.0 } else { dot(q, w, a, i * k, m) }
    }
  }
  for i = n - 1; i >= 0; i = i - 1 {
    let mut c = dot(q, i * k, y, 0, m)
    for j = n - 1; j > i; j = j - 1 {
      c = c - r[i * 3 + j] * coef[j]
    }
    coef[i] = c / r[i * 3 + i]
  }
  coef[1]
}

