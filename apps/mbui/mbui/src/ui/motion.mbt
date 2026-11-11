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
/// What a timed motion's curve says it is (sf/motion.mbt, Curves): one curve for each, so what moves the
/// same way moves alike everywhere. No other: what is sprung is @motion's (its springs: rows making way, a sheet, a
/// thing let go with the hand's speed, a thing lifted).
#derive(Eq, Debug)
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
  /// (.6, 0, .2, 1): words sent on their way to their row (sfbase's flight.mbt)
  Flight
}

///|
/// Move's spring: ω·T where it rests, and how far it has got there (said once under what lays things out: flex's
/// move.mbt, an item coming or going taking its way in the same layout).
let move_k : Double = @flex.move_k

///|
let move_end : Double = @flex.move_end

///|
/// How long a Move takes over `points` (flex's move_ms: 200 + 7.5·√points ms, between move_least_ms and
/// move_most_ms, to whole frames).
pub fn move_ms(points : Double) -> Double {
  @flex.move_ms(points)
}

///|
/// The shortest and the longest a Move takes (move_ms).
pub let move_least_ms : Double = @flex.move_least_ms

///|
pub let move_most_ms : Double = @flex.move_most_ms

///|
/// How far (points) what goes `v` points a ms is carried as it is told to stop: as far as a Move from that speed
/// slows to rest on its own way (move_path from `v` with nothing left of it then: ω·d + v = 0, as long as move_ms has a
/// way that far), never past it and back.
pub fn move_stop_points(v : Double) -> Double {
  @flex.move_stop_points(v)
}

///|
/// Where what is let go at `at`, going `v` (points a ms, signed), comes to rest of itself: on from that speed as far as
/// it carries it (move_stop_points), the way a motion set off again from it goes first (flex's come_way).
pub fn lands_at(at : Double, v : Double) -> Double {
  if v > 0.0 {
    at + move_stop_points(v)
  } else if v < 0.0 {
    at - move_stop_points(v)
  } else {
    at
  }
}

///|
/// Whether what is let go at `at`, going `v` (points a ms, signed), lands past `line` (on its side of where it rests,
/// 0: over it where `line` is above 0, under it where below): where something let go goes (closed or back, archived or
/// back, a page back or not) is judged by where it lands, with a gesture's own fling, never by where it was let go
/// alone. So one judged back never goes on past its line before it turns: what it is carried on and turned is no more
/// than what it fell short of that line by (the coordinator of the migration, 2026-11-10: one model for where it goes
/// and how it goes there). Only the event's own place and speed as it is let go, never a frame's.
pub fn lands_past(at : Double, v : Double, line : Double) -> Bool {
  let x = lands_at(at, v)
  if line >= 0.0 {
    x > line
  } else {
    x < line
  }
}

///|
/// How fast (points a ms) a finger putting a thing away (a sheet down, a toast aside) lets go of it for that to put it
/// away however far it went: a flick (the coordinator of the migration, 2026-11-10: the same for the gestures of the
/// one kind).
pub let flung_away : Double = 0.5

///|
/// Where a Move is `t` ms into its `dur`: `d` off its end as it set out, going `v` (per ms, of the same units) then
/// (what it was told to go on from: a move under way, the hand's speed as it let go). A critically damped spring's way
/// (ω = move_k / dur), its rest at `dur` made exact by taking off what it would still have left there in the measure
/// of Ease::Move (so from rest it is Ease::Move's way, and it leaves as fast as `v`). Its offset from its end and how
/// fast it goes (per ms).
pub fn move_path(d : Double, v : Double, t : Double, dur : Double) -> (Double, Double) {
  @flex.move_path(d, v, t, dur)
}

///|
/// Where a way from `from` set out at `v` (points a ms) toward `plan` has got `t` ms on, and how fast it goes, as it
/// goes to `goal` (flex's come_way_by: its turn and lengths said by `plan`, only its end where `goal` is): for what
/// sets off from where it stands as fast as it goes there, not from rest.
pub fn come_way_by(
  from : Double,
  v : Double,
  goal : Double,
  plan : Double,
  t : Double,
  kept? : ComeKept,
) -> (Double, Double) {
  @flex.come_way_by(from, v, goal, plan, t, kept?)
}

///|
/// (flex's: what a way turned back keeps of its turn, @ui.ComeKept)
pub using @flex {
  type ComeKept,
}

///|
/// What a way turned back keeps of its turn, worked out once (flex's ComeKept): one to hold with a way set off, given
/// to each come_way_by and come_way_ms of it.
pub fn come_kept() -> ComeKept {
  @flex.ComeKept::new()
}

///|
/// How long that way takes (flex's come_way_ms, `goal` its plan).
pub fn come_way_ms(from : Double, v : Double, goal : Double, kept? : ComeKept) -> Double {
  @flex.come_way_ms(from, v, goal, kept?)
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
