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
}

///|
pub fn Tracker::new() -> Tracker {
  {
    times: FixedArray::make(track_size, 0.0),
    vals: FixedArray::make(track_size, 0.0),
    index: 0,
    n: 0,
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

