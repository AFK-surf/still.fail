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
  /// one of the three `move_*_ms`, by how far it goes.
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
/// Move's spring: ω·T where it rests (its way within 0.2% of its end: under a point and a half over the window's
/// width, landing at 1.5% of its mean speed), and how far it has got there, so that the curve ends at 1. A spring of visual duration v (Motion's, ω = 2π / 1.2v)
/// rests at T = move_k · 1.2v / 2π.
let move_k : Double = 8.5

///|
let move_end : Double = 1.0 - (1.0 + move_k) * @dmath.exp(-move_k)

///|
/// How long a Move takes, by how far it goes: near (a row, the composer, a card: Motion's 0.28 s, the web's MOVE),
/// a page (pushed, risen, a sheet, a picture, the search: 0.32 s, a sheet's spring), far (across the window: the
/// tape, the sidebar: 0.38 s, the web's moveState); each to whole frames (450, 500, 600 ms).
pub let move_near_ms : Double = spring_move_ms(0.28)

///|
pub let move_page_ms : Double = spring_move_ms(0.32)

///|
pub let move_far_ms : Double = spring_move_ms(0.38)

///|
fn spring_move_ms(visual : Double) -> Double {
  let ms = move_k * 1.2 * visual / (2.0 * 3.141592653589793) * 1000.0
  (ms / whole_frames_ms).round() * whole_frames_ms
}

///|
/// What a Move's length is a whole number of: three frames at 60 Hz, six at 120, so that it ends on a frame there (as
/// a page's 300 ms did), not between two.
let whole_frames_ms : Double = 50.0

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
