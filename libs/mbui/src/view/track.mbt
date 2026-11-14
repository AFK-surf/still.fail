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
/// What a tracker holds as of a moment, kept as it was (its samples copied): its velocity as of then worked out only
/// where it is asked (Drag::vx, Drag::vy), as Tracker::velocity_at would have then, whatever the tracker took since.
#derive(Eq, Debug)
pub struct TrackerSaid {
  priv times : FixedArray[Double]
  priv vals : FixedArray[Double]
  priv index : Int
  priv n : Int
  priv t : Double
}

///|
/// What it holds now, kept for its velocity as of `t` (Tracker::velocity_at).
pub fn Tracker::said_at(self : Tracker, t : Double) -> TrackerSaid {
  { times: self.times.copy(), vals: self.vals.copy(), index: self.index, n: self.n, t }
}

///|
/// Its velocity as of its moment, as the tracker said it then (Tracker::velocity_at).
pub fn TrackerSaid::velocity(self : TrackerSaid) -> Double {
  let tr : Tracker = { times: self.times, vals: self.vals, index: self.index, n: self.n, fit: None }
  tr.velocity_at(self.t)
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
  if self.n == 0 || t > self.times[self.index] + tracker_gap_ms {
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
    if newest > bt + tracker_horizon_ms || self.times[idx] > bt + tracker_gap_ms {
      break
    }
    if newest <= bt + tracker_gap_ms {
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
/// Of `a` from `ai` and `b` from `bi`, the first `m` multiplied pairwise and summed (each within its fit's rows,
/// lsq_slope's: read unchecked).
fn dot(a : FixedArray[Double], ai : Int, b : FixedArray[Double], bi : Int, m : Int) -> Double {
  let mut s = 0.0
  for h in 0..<m {
    s = s + a.unsafe_get(ai + h) * b.unsafe_get(bi + h)
  }
  s
}

///|
/// The slope at x = 0 of the polynomial of degree 2 (1 with two points)
/// fitted to the first `m` of `f`'s points by least squares: Compose's
/// polyFitLeastSquares (QR by Gram-Schmidt, back-substituted), in `f`'s
/// matrices. (`m` is at most track_size and each index within its matrix's rows: read and written unchecked, as a
/// finger's every move asks it, Tree::tracked)
fn lsq_slope(f : Fit, m : Int) -> Double {
  let x = f.xs
  let y = f.ys
  let a = f.a
  let q = f.q
  let r = f.r
  let coef = f.coef
  let k = track_size
  let m = if m > k { k } else { m }
  let n = if m > 2 { 3 } else { m }
  for h in 0..<m {
    a.unsafe_set(h, 1.0)
    for i in 1..<n {
      a.unsafe_set(i * k + h, a.unsafe_get((i - 1) * k + h) * x.unsafe_get(h))
    }
  }
  for j in 0..<n {
    let w = j * k
    for h in 0..<m {
      q.unsafe_set(w + h, a.unsafe_get(j * k + h))
    }
    for i in 0..<j {
      let d = dot(q, w, q, i * k, m)
      for h in 0..<m {
        q.unsafe_set(w + h, q.unsafe_get(w + h) - d * q.unsafe_get(i * k + h))
      }
    }
    let inv = 1.0 / dmax(dot(q, w, q, w, m).sqrt(), 1.0e-6)
    for h in 0..<m {
      q.unsafe_set(w + h, q.unsafe_get(w + h) * inv)
    }
    for i in 0..<n {
      r.unsafe_set(j * 3 + i, if i < j { 0.0 } else { dot(q, w, a, i * k, m) })
    }
  }
  for i = n - 1; i >= 0; i = i - 1 {
    let mut c = dot(q, i * k, y, 0, m)
    for j = n - 1; j > i; j = j - 1 {
      c = c - r.unsafe_get(i * 3 + j) * coef.unsafe_get(j)
    }
    coef.unsafe_set(i, c / r.unsafe_get(i * 3 + i))
  }
  coef[1]
}

