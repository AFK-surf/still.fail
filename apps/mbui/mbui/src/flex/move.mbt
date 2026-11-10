// A Move's way (ui's Ease::Move, motion.mbt: what is seen where it was and where it goes, going there) and how long it
// takes, said once here, under what lays things out: an item coming or going takes its way in its column at the height
// it is laid out (Style's come_*), in the same layout. ui's Ease::Move and move_ms are these.

///|
/// Move's spring: ω·T where it rests (its way within 0.5% of its end, landing at 3% of its mean speed: nothing seen
/// of a tail longer than that but a wait, the user 2026-10-29: 「动效有点太墨迹了」), and how far it has got there, so
/// that the curve ends at 1. Nine tenths of the way at half of T.
pub let move_k : Double = 7.4

///|
pub let move_end : Double = 1.0 - (1.0 + move_k) * @dmath.exp(-move_k)

///|
/// What a Move's length is a whole number of: three frames at 60 Hz, six at 120.
pub let move_whole_frames_ms : Double = 50.0

///|
/// The shortest and the longest a Move takes (move_ms): what goes nowhere far takes `move_least_ms`, what has gone the
/// furthest is there by `move_most_ms`.
pub let move_least_ms : Double = 200.0

///|
pub let move_most_ms : Double = 500.0

///|
/// How long a Move takes over `points` (how far it goes this time, from where it is drawn now to where it goes: the
/// user 2026-10-30, 「有些动效不应该固定播放时间，因为它的距离是不固定的」): 200 + 7.5·√points ms, so a row's 64 points
/// take about 260, a phone's page width 350, across a 1000-point window 450; the further the longer, not in
/// proportion. Between `move_least_ms` and `move_most_ms`, to whole frames: three at 60 Hz, six at 120, so that it ends
/// on a frame there (as a page's 300 ms did), not between two.
pub fn move_ms(points : Double) -> Double {
  let d = if points > 0.0 { points } else { 0.0 }
  let ms = ((200.0 + 7.5 * d.sqrt()) / move_whole_frames_ms).round() * move_whole_frames_ms
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
/// A Move's way at `t` (0 … 1 of its time): a critically damped spring's from rest.
pub fn move_at(t : Double) -> Double {
  if t <= 0.0 {
    0.0
  } else if t >= 1.0 {
    1.0
  } else {
    let x = move_k * t
    (1.0 - (1.0 + x) * @dmath.exp(-x)) / move_end
  }
}

///|
/// Where a Move is `t` ms into its `dur`: `d` off its end as it set out, going `v` (per ms, of the same units) then
/// (what it was told to go on from: a move under way, the hand's speed as it let go). A critically damped spring's way
/// (ω = move_k / dur), its rest at `dur` made exact by taking off what it would still have left there in the measure
/// of a Move from rest (so from rest it is move_at's way, and it leaves as fast as `v`). Its offset from its end and how
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
  // a Move's way and speed at t (per ms)
  let s = move_k * t / dur
  let m = (1.0 - (1.0 + s) * @dmath.exp(-s)) / move_end
  let mv = s * @dmath.exp(-s) * move_k / dur / move_end
  (x - xt * m, xv - xt * mv)
}

///|
/// How far (points) what goes `v` points a ms is carried as it is told to stop: as far as a Move from that speed
/// slows to rest on its own way (move_path from `v` with nothing left of it then: ω·d + v = 0, as long as move_ms has a
/// way that far), never past it and back.
pub fn move_stop_points(v : Double) -> Double {
  let speed = v.abs()
  if speed <= 0.0 {
    return 0.0
  }
  let mut d = speed * 200.0
  for _ in 0..<8 {
    d = speed * move_ms(d) / move_k
  }
  d
}

///|
/// How slow (points a ms), at the least, a way set off again at speed has to have got, slowing, before it sets out for
/// where it goes (come_turn_out): a hundredth of a point a ms, too slow to be seen turning; one set out no faster than
/// that sets out for it at once, as one set out from rest does, so that a speed a little toward where it goes and a
/// little away from it go nearly the same way.
let come_turn_least : Double = 0.01

///|
/// What share of the speed it set out at a way set off again at speed has slowed to as it sets out for where it goes
/// (come_turn_out), where that is more than come_turn_least: 15%, while what it set off on is still seen going (a point
/// or more a frame where it went fast), so that the two, added, round its turn: the way out slowing as the way back
/// gains, never a frame of each seen still together, hanging at the turn (2.5%, set out once it was all but still, hung
/// there 33 ms and more); no earlier, where the way back, gaining, all but cancels the way out still going fast, a frame
/// of it stopped dead (25% did: come_back_wbtest). Held by come_back_wbtest's and sheet_let_go_wbtest's hung_at_turn (the
/// coordinator of the migration, 2026-11-10).
let come_turn_share : Double = 0.15

///|
/// When (ms after it set out) a way set off again at `v` turned away from where it goes sets out for it: once its
/// slowing (come_turn, `t1` long, ω = move_k / t1) has brought it down to the more of come_turn_share of `v` and
/// come_turn_least; at once where it went no faster than that. A moment of the way's own, worked out of its speed
/// alone, and the same either side of where the two meet (|v| 1/15: ln(1/0.15) = 1.9, about a quarter of move_k).
fn come_turn_out(v : Double, t1 : Double) -> Double {
  let speed = v.abs()
  let slow = fmax(come_turn_least, come_turn_share * speed)
  if speed <= slow || t1 <= 0.0 {
    0.0
  } else {
    fmin(t1, @dmath.ln(speed / slow) * t1 / move_k)
  }
}

///|
/// A way set off again at `v` (points a ms): how far it is carried on, slowing to rest (move_stop_points, signed as
/// `v`), and how long that takes.
fn come_turn(v : Double) -> (Double, Double) {
  if v == 0.0 {
    return (0.0, 0.0)
  }
  let d = move_stop_points(v)
  (if v > 0.0 { d } else { -d }, move_ms(d))
}

///|
/// Whether a way from `from` to `goal` set out at `v` goes toward `goal` already (so not turned: a Move on from that
/// speed, come_way).
fn come_toward(from : Double, v : Double, goal : Double) -> Bool {
  v * (goal - from) > 0.0
}

///|
/// Another way a come way goes with (come_way's `along`): the moment it sets out and the moment it ends, as that way
/// says them. Only for what goes together with another thing (the room words sent open as they fly there, set out
/// and ended with their flight; an answer's room with the avatar's spit): it sets out with it and is there as it ends,
/// on a Move all the same. Not a length of its own to be said instead of how far it goes (move_ms): there is none to
/// give, only another way to go with (the coordinator of the migration, 2026-11-10).
pub(all) struct ComeWith {
  start : Double
  ends : Double
} derive(Eq, Show)

///|
/// How long its Move to `goal` takes, `far` points away, going along `along` from `t0` ms after the way set out (at
/// `along.start`): to `along.ends`; else as long as how far that is (move_ms; none where it is there: 0).
fn come_move_ms(far : Double, t0 : Double, along : ComeWith?) -> Double {
  match along {
    Some(w) => fmax(w.ends - w.start - t0, 0.0)
    None => if far.abs() < 0.5 { 0.0 } else { move_ms(far.abs()) }
  }
}

///|
/// How long its Move on from its speed toward `goal`, `far` points away, takes (come_toward): to `along.ends`; else as
/// long as how far that is, the least Move however near (move_ms), never none: what goes at speed half a point from
/// where it goes is not stopped dead (the coordinator of the migration, 2026-11-10). None there only for a Move from
/// rest (come_move_ms), which has no speed to lose.
fn come_on_ms(far : Double, along : ComeWith?) -> Double {
  match along {
    Some(w) => fmax(w.ends - w.start, 0.0)
    None => move_ms(far.abs())
  }
}

///|
/// How long (ms) a way from `from` tall to `goal`, set out at `v` (points a ms), takes: carried on slowing to rest
/// (come_turn), and once slow (come_turn_out) a Move from rest to `goal`, as long as how far that is; set out toward
/// `goal`, a Move on from `v` (come_toward). Going `along` another way: there as that one ends (its slowing, turned, no
/// shorter).
pub fn come_way_ms(from : Double, v : Double, goal : Double, along? : ComeWith) -> Double {
  if come_toward(from, v, goal) {
    return come_on_ms(goal - from, along)
  }
  let (s, t1) = come_turn(v)
  let t0 = come_turn_out(v, t1)
  let t2 = come_move_ms(goal - from - s, t0, along)
  if v == 0.0 {
    t2
  } else {
    fmax(t1, t0 + t2)
  }
}

///|
/// Where a way from `from` tall to `goal`, set out at `v` (points a ms), has got `t` ms on, and how fast it goes (points
/// a ms): on from `v`, slowing to rest as far as that speed carries it (come_turn), and once slow (come_turn_out) a
/// Move from rest to `goal` (none set out at speed: that Move alone; set out toward `goal`: a Move on from `v`,
/// come_toward). Its speed the same as `v` as it sets out, whichever way that is (the coordinator of the migration,
/// 2026-11-10: a show's node called back as it closes its room, on from as fast as it went), turning over frames, never
/// within one; a little toward `goal` and a little away from it, nearly the same way. `t` from the moment it set out
/// (before it, where it was); going `along` another way, set out as that one does and there as it ends (come_way_ms).
pub fn come_way(from : Double, v : Double, goal : Double, t : Double, along? : ComeWith) -> (Double, Double) {
  // (going toward where it goes already: a Move on from that speed, not slowed to rest on the way, stalling)
  if come_toward(from, v, goal) {
    let (off, ov) = move_path(from - goal, v, t, come_on_ms(goal - from, along))
    return (goal + off, ov)
  }
  let (s, t1) = come_turn(v)
  let (x, xv) = if v == 0.0 {
    (from, 0.0)
  } else {
    let (off, ov) = move_path(-s, v, t, t1)
    (from + s + off, ov)
  }
  let far = goal - from - s
  let t0 = come_turn_out(v, t1)
  let t2 = t - t0
  if t2 <= 0.0 {
    return (x, xv)
  }
  let dur = come_move_ms(far, t0, along)
  if dur <= 0.0 || t2 >= dur {
    return (x + far, xv)
  }
  let (off, ov) = move_path(-far, 0.0, t2, dur)
  (x + far + off, xv + ov)
}

///|
/// How tall an item coming or going is laid out (Style's come_*), `natural` tall: where its way from `come_from` to
/// `come_to` of `natural`, set out at `come_v` (come_way), has got at `come_now`, its end (`come_ends`) said as long as
/// that way the first time it is laid out so, kept from then; NaN once it is there. `come_k` its share of `natural`
/// (0 … 1), for the gap before it.
fn come_height(s : Style, natural : Double) -> Double {
  let goal = s.come_to * natural
  s.come_goal = goal
  if !known(s.come_ends) {
    s.come_ends = s.come_at + come_way_ms(s.come_from, s.come_v, goal)
  }
  let dur = s.come_ends - s.come_at
  let t = s.come_now - s.come_at
  if dur <= 0.0 || t >= dur {
    s.come_k = fmax(fmin(s.come_to, 1.0), 0.0)
    return if s.come_to >= 1.0 { 0.0 / 0.0 } else { goal }
  }
  let (tall, _) = come_way(s.come_from, s.come_v, goal, t)
  let tall = fmax(tall, 0.0)
  // (holding nothing it is laid out by, closing to nothing from as tall as one before it was (a pick's case that made
  // nothing): its share of that)
  s.come_k = if natural > 0.0 {
    fmax(fmin(tall / natural, 1.0), 0.0)
  } else if s.come_to <= 0.0 && s.come_from > 0.0 {
    fmax(fmin(tall / s.come_from, 1.0), 0.0)
  } else {
    s.come_to
  }
  tall
}

///|
/// How tall an item coming or going (Style's come_*) is at moment `at` on its way as it was last laid out, and how fast
/// its height goes then (points a ms): what a way set off again then goes on from (come_way). None: on no way, or one
/// not laid out yet.
pub fn come_state(s : Style, at : Double) -> (Double, Double)? {
  if !known(s.come_now) || !known(s.come_at) || !known(s.come_ends) || !known(s.come_goal) {
    return None
  }
  let dur = s.come_ends - s.come_at
  let t = at - s.come_at
  if dur <= 0.0 || t >= dur {
    return Some((s.come_goal, 0.0))
  }
  let (tall, v) = come_way(s.come_from, s.come_v, s.come_goal, t)
  Some((fmax(tall, 0.0), v))
}
