// The curves of motion timed rather than sprung, one for each thing a motion can be (Ease): a page pushed (nav), a
// state moved (move_state), a scrollbar's fade, and @motion's tweens. Those that are CSS's cubic-beziers are played as
// Compose's CubicBezierEasing plays them.

///|
/// CSS's cubic-bezier(x1, y1, x2, y2) at `t` (0-1 of the time), as Compose's CubicBezierEasing finds it: how far
/// along (0-1). (Motion's own solver, as an easing: @motion.cubic_bezier.)
fn bezier_at(x1 : Double, y1 : Double, x2 : Double, y2 : Double, t : Double) -> Double {
  if t <= 0.0 {
    return 0.0
  }
  if t >= 1.0 {
    return 1.0
  }
  // x(s) and y(s) for s in 0-1; s found for x(s) = t by Newton's steps,
  // bisection where they would not do
  let cx = 3.0 * x1
  let bx = 3.0 * (x2 - x1) - cx
  let ax = 1.0 - cx - bx
  let cy = 3.0 * y1
  let by = 3.0 * (y2 - y1) - cy
  let ay = 1.0 - cy - by
  let x_at = fn(s : Double) { ((ax * s + bx) * s + cx) * s }
  let mut s = t
  let mut found = false
  for _ in 0..<8 {
    let e = x_at(s) - t
    if e.abs() < 1.0e-7 {
      found = true
      break
    }
    let d = (3.0 * ax * s + 2.0 * bx) * s + cx
    if d.abs() < 1.0e-6 {
      break
    }
    s = s - e / d
  }
  if !found || s < 0.0 || s > 1.0 {
    let mut lo = 0.0
    let mut hi = 1.0
    s = t
    for _ in 0..<60 {
      let x = x_at(s)
      if (x - t).abs() < 1.0e-9 {
        break
      }
      if x < t {
        lo = s
      } else {
        hi = s
      }
      s = (lo + hi) / 2.0
    }
  }
  ((ay * s + by) * s + cy) * s
}

///|
/// What a timed motion's curve says it is (still.fail's docs/motion.md, Curves): one curve for each, so what moves the
/// same way moves alike everywhere. No other: what is sprung is @motion's (its springs: rows making way, a sheet, a
/// thing let go with the hand's speed, a thing lifted).
pub(all) enum Ease {
  /// A thing seen where it was and where it goes, going there: a page pushed or risen, the tape, the sidebar, a side
  /// panel, the composer's shape, a picture flown open, the search rising. A critically damped spring's way from rest
  /// (Motion's spring, no bounce): no step in its first frame (a curve fast from its start puts a fifth of a long way
  /// there at once, then creeps), its speed at its most a tenth of the way in, under twice its mean. Its length is
  /// `move_ms` of how far it goes; told on from a way under way or from the hand, `move_path` (as fast as it went).
  Move
  /// (.2, .7, .2, 1), the web's --ease-out: what comes (faded in, grown from a little smaller, up from a line below),
  /// a control answering (pointed at, pressed, a switch's knob, a fill), and what goes on from the hand's let go where
  /// no spring takes its speed (a page swiped back)
  Out
  /// (.4, 0, 1, 1): what goes (faded out, shrinking, off the screen), gone the faster the further it is
  Leave
  /// (.42, 0, .58, 1), CSS's ease-in-out: each way of a loop (a breath), a stroke drawn
  InOut
  /// progress, as it is: handed to another curve (a flight's way), or a cycle's turn
  Linear
  /// (.6, 0, .2, 1): words sent on their way to their row (sfbase's flight.mbt; the web's madeChat.ts)
  Flight
} derive(Eq, Show)

///|
/// Move's spring: ω·T where it rests (its way within 0.5% of its end, landing at 3% of its mean speed: nothing seen
/// of a tail longer than that but a wait, the user 2026-10-29: 「动效有点太墨迹了」), and how far it has got there, so
/// that the curve ends at 1. Nine tenths of the way at half of T.
let move_k : Double = 7.4

///|
let move_end : Double = 1.0 - (1.0 + move_k) * @dmath.exp(-move_k)

///|
/// How long a Move takes over `points` (how far it goes this time, from where it is drawn now to where it goes: the
/// user 2026-10-30, 「有些动效不应该固定播放时间，因为它的距离是不固定的」): 200 + 7.5·√points ms, so a row's 64 points
/// take about 260, a phone's page width 350, across a 1000-point window 450; the further the longer, not in
/// proportion. Between `move_least_ms` and `move_most_ms`, to whole frames: three at 60 Hz, six at 120, so that it ends
/// on a frame there (as a page's 300 ms did), not between two.
pub fn move_ms(points : Double) -> Double {
  let d = if points > 0.0 { points } else { 0.0 }
  let ms = ((200.0 + 7.5 * d.sqrt()) / whole_frames_ms).round() * whole_frames_ms
  // (NaN, a way not known: the longest)
  if ms < move_least_ms {
    move_least_ms
  } else if ms > move_most_ms || ms.is_nan() {
    move_most_ms
  } else {
    ms
  }
}

///|
/// What a Move's length is a whole number of: three frames at 60 Hz, six at 120.
let whole_frames_ms : Double = 50.0

///|
/// The shortest and the longest a Move takes (move_ms): what goes nowhere far takes `move_least_ms`, what has gone the
/// furthest is there by `move_most_ms`.
pub let move_least_ms : Double = 200.0

///|
pub let move_most_ms : Double = 500.0

///|
/// Where a Move is `t` ms into its `dur`: `d` off its end as it set out, going `v` (per ms, of the same units) then
/// (what it was told to go on from: a move under way, the hand's speed as it let go). A critically damped spring's way
/// (ω = move_k / dur), its rest at `dur` made exact by taking off what it would still have left there in the measure
/// of Ease::Move (so from rest it is Ease::Move's way, and it leaves as fast as `v`). Its offset from its end and how
/// fast it goes (per ms).
pub fn move_path(d : Double, v : Double, t : Double, dur : Double) -> (Double, Double) {
  if dur <= 0.0 || t >= dur {
    return (0.0, 0.0)
  }
  if t <= 0.0 {
    return (d, v)
  }
  let w = move_k / dur
  let b = v + w * d
  let at = fn(t : Double) {
    let e = @dmath.exp(-w * t)
    ((d + b * t) * e, (b - w * (d + b * t)) * e)
  }
  let (x, xv) = at(t)
  let (xt, _) = at(dur)
  // Ease::Move's way and speed at t (per ms)
  let s = move_k * t / dur
  let m = (1.0 - (1.0 + s) * @dmath.exp(-s)) / move_end
  let mv = s * @dmath.exp(-s) * move_k / dur / move_end
  (x - xt * m, xv - xt * mv)
}

///|
/// The curve at `t` (0-1 of the time).
pub fn Ease::at(self : Ease, t : Double) -> Double {
  match self {
    Move =>
      if t <= 0.0 {
        0.0
      } else if t >= 1.0 {
        1.0
      } else {
        let x = move_k * t
        (1.0 - (1.0 + x) * @dmath.exp(-x)) / move_end
      }
    Out => bezier_at(0.2, 0.7, 0.2, 1.0, t)
    Leave => bezier_at(0.4, 0.0, 1.0, 1.0, t)
    InOut => bezier_at(0.42, 0.0, 0.58, 1.0, t)
    Linear => dclamp(t, 0.0, 1.0)
    Flight => bezier_at(0.6, 0.0, 0.2, 1.0, t)
  }
}
