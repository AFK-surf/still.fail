// A pointer's velocity from its own samples, by their own times: Compose's VelocityTracker
// (androidx.compose.ui.input.pointer.util, its default Lsq2 strategy): a quadratic fitted by least squares to the last
// 100 ms of samples, cut at a pause of more than 40 ms, its slope at the newest sample. What the old views' lists fling
// at (ui's scroll.mbt) and what a hold of the window's tree's is told it goes at (Drag's `vx`, `vy`). A lift as
// Android's and Compose's take it: no sample where it says the last place again, how fast as of the last move, none
// where the pointer stood still longer than the pause first (Tracker::up, Tracker::velocity_at). Ours, not theirs: none
// either where its own last moves do not bear the fitted speed out (Tracker::velocity_at says how, and what it misses).

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
/// The pointer lifted at `t` at `v`: a sample only where it says a place anew (it moved there, no move of its own said
/// so); none where it says the last place again, as Android's ACTION_UP always does. A finger lifted while it moves
/// says the last place its screen read, the lift coming between two reads: that place said so late, fitted, bends the
/// fit back and the speed with it, as if it had stopped there, the other way where it slowed first. Neither Android's
/// VelocityTracker (addMovement, ACTION_UP) nor Compose's (b/238654963) takes an up.
pub fn Tracker::up(self : Tracker, t : Double, v : Double) -> Unit {
  if self.n > 0 && v != self.vals[self.index] {
    self.add(t, v)
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
/// Units per ms as of a moment `t` (an event's: a move, a lift): as of its newest sample; none where that is more than
/// tracker_gap_ms before `t`, the pointer having stood still since (Android's VelocityTracker as it takes ACTION_UP,
/// ASSUME_POINTER_STOPPED_TIME; Compose's, b/238654963). Ours, not theirs: none either where the pointer's own way does
/// not bear it out, over its last tracker_gap_ms of samples nor since it last turned that way (Tracker::bears), or
/// where, since it last went that way, it went back farther than that speed carries it in that while. Come to rest,
/// its moves resting there saying its place again (Android's and Compose's trackers take each) or wavering a little,
/// it went no way over them, while the quadratic fitted bends back at its end though it never went back; turned back
/// long enough before, it went back since it turned; turned back over its last moves just before it is let go, it went
/// back farther than the fit, on the first way yet, carries it; a place wavering a little at the end of a fling goes
/// back less. Not caught: a turn of one move only (8 ms at 120 Hz) may go back less than that, flung the first way
/// still, as theirs flings it.
pub fn Tracker::velocity_at(self : Tracker, t : Double) -> Double {
  if self.n == 0 || t - self.times[self.index] > tracker_gap_ms {
    return 0.0
  }
  let v = self.velocity()
  if v == 0.0 {
    return 0.0
  }
  let way = if v > 0.0 { 1.0 } else { -1.0 }
  let newest = self.times[self.index]
  // (over the fit's own samples: the oldest of those tracker_gap_ms before the newest at most; where the steps going
  // the fit's way, or resting, that end at the newest begin)
  let mut last = self.index
  let mut since = self.index
  let mut turned = false
  // (and where the steps going against it, or resting, that end at the newest begin)
  let mut against = self.index
  let mut went_on = false
  let mut idx = self.index
  for _ in 1..<self.n {
    let before = (if idx == 0 { track_size } else { idx }) - 1
    let bt = self.times[before]
    if newest - bt > tracker_horizon_ms || self.times[idx] - bt > tracker_gap_ms {
      break
    }
    if newest - bt <= tracker_gap_ms {
      last = before
    }
    let step = (self.vals[idx] - self.vals[before]) * way
    if !turned && step >= 0.0 {
      since = before
    } else {
      turned = true
    }
    if !went_on && step <= 0.0 {
      against = before
    } else {
      went_on = true
    }
    idx = before
  }
  let back = (self.vals[against] - self.vals[self.index]) * way
  if (self.bears(v, last) || self.bears(v, since)) &&
    back <= v.abs() * (newest - self.times[against]) {
    v
  } else {
    0.0
  }
}

///|
/// Whether the pointer went the way of speed `v` from sample `i` to the newest, as far at least as half `v` for that
/// while: what any steady change of speed (the fit's own way of going, a quadratic) covers at the least as it comes to
/// `v` never turned on the way.
fn Tracker::bears(self : Tracker, v : Double, i : Int) -> Bool {
  let went = if v > 0.0 { self.vals[self.index] - self.vals[i] } else { self.vals[i] - self.vals[self.index] }
  went > 0.0 && went >= v.abs() * (self.times[self.index] - self.times[i]) / 2.0
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

