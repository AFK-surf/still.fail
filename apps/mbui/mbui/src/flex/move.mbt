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
  come_way_by(from, v, goal, goal, t, along?)
}

///|
/// Where a way from `from` tall set out at `v` toward `plan` (come_way: its turn, how long its slowing and its Move
/// take, worked out of that) has got `t` ms on and how fast it goes, as it goes to `goal`: what it goes to come to
/// another height on the way (what it holds grown or shrunk of its own, no cause of this way's), the way the same
/// whatever it comes to, only its end where that is: where it is goes by as much of that as its Move has got (the
/// coordinator of the migration, 2026-11-11: 份额跟着走, not a way of its own laid anew). As come_way where `goal` is
/// `plan`, to the bit.
pub fn come_way_by(
  from : Double,
  v : Double,
  goal : Double,
  plan : Double,
  t : Double,
  along? : ComeWith,
) -> (Double, Double) {
  // (going toward where it goes already: a Move on from that speed, not slowed to rest on the way, stalling)
  if come_toward(from, v, plan) {
    let (off, ov) = move_path(from - goal, v, t, come_on_ms(plan - from, along))
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
  let dur = come_move_ms(plan - from - s, t0, along)
  if dur <= 0.0 || t2 >= dur {
    return (x + far, xv)
  }
  let (off, ov) = move_path(-far, 0.0, t2, dur)
  (x + far + off, xv + ov)
}

///|
/// What comes or goes down one column at one moment, with what was on its way there then (the user, 2026-11-03: a
/// change come while others go is put with what is left of theirs, one whole going to where it all ends): one way for
/// all of it, each item its share. Its speed (`v`, points a ms) the items' toward where each goes, summed, and how far
/// all of them go (`far`, the most of any); turned away from where it goes (v < 0), all of it slows as one first, each
/// on along its own speed by that one slowing (come_turn of `v`: `s` and `t1`, setting out for where it goes from
/// `t0`), then one Move from where each has come to, `dur` long; else one Move from rest or on from `v` (no faster
/// than it goes past where it goes: ω·D), `dur` long. Said once, at the moment it is said for (come_group_set); read by
/// flex alone, each item laid out by it (come_height).
pub(all) struct ComeGroup {
  at : Double
  members : Array[Style]
  mut set : Bool
  mut v : Double
  mut d : Double
  mut s : Double
  mut t1 : Double
  mut t0 : Double
  mut dur : Double
}

///|
/// A group said at moment `at`, none in it yet.
pub fn ComeGroup::new(at : Double) -> ComeGroup {
  { at, members: [], set: false, v: 0.0, d: 0.0, s: 0.0, t1: 0.0, t0: 0.0, dur: 0.0 }
}

///|
/// The group's way worked out of what each in it goes from, how fast, and to: each its come_goal, known by now (coming,
/// as it was measured at the group's moment; going, nothing). Its end each one's (come_ends, come_plan). None set where
/// it holds no more than one: that one goes its own way (come_way), so as it always did.
pub fn come_group_set(g : ComeGroup) -> Unit {
  if g.members.length() < 2 {
    for m in g.members {
      m.come_group = None
    }
    return
  }
  let mut v = 0.0
  for m in g.members {
    let d = m.come_goal - m.come_from
    v = v + (if d >= 0.0 { m.come_v } else { -m.come_v })
  }
  g.v = v
  let (s, t1) = if v < 0.0 { come_turn(v) } else { (0.0, 0.0) }
  g.s = s
  g.t1 = t1
  g.t0 = if v < 0.0 { come_turn_out(v, t1) } else { 0.0 }
  // (each from where its slowing leaves it: as far on as its own speed is of the group's)
  let mut far = 0.0
  let mut dd = 0.0
  for m in g.members {
    let start = if v < 0.0 { m.come_from + m.come_v * s / v } else { m.come_from }
    let d = (m.come_goal - start).abs()
    far = fmax(far, d)
    dd = dd + d
  }
  g.d = dd
  g.dur = if v < 0.0 { come_move_ms(far, g.t0, None) } else if far < 0.5 { 0.0 } else { move_ms(far) }
  let ends = g.at + (if v < 0.0 { fmax(t1, g.t0 + g.dur) } else { g.dur })
  for m in g.members {
    m.come_group = Some(g)
    m.come_ends = ends
    m.come_plan = m.come_goal
  }
  g.set = true
}

///|
/// Where item `s` of group `g` is `t` ms on from the group's moment, going to `goal` now, and how fast (points a ms):
/// its share of the group's way.
fn come_group_way(g : ComeGroup, s : Style, goal : Double, t : Double) -> (Double, Double) {
  if g.v < 0.0 {
    // (slowing as one: carried as far as its own speed is of the group's)
    let (x, xv) = if g.t1 <= 0.0 || t >= g.t1 {
      (g.s, 0.0)
    } else {
      let (off, ov) = move_path(-g.s, g.v, t, g.t1)
      (g.s + off, ov)
    }
    let k = s.come_v / g.v
    let start = s.come_from + k * g.s
    let t2 = t - g.t0
    let (m, mv) = if t2 <= 0.0 {
      (0.0, 0.0)
    } else if g.dur <= 0.0 || t2 >= g.dur {
      (1.0, 0.0)
    } else {
      let (off, ov) = move_path(-1.0, 0.0, t2, g.dur)
      (1.0 + off, ov)
    }
    (s.come_from + k * x + (goal - start) * m, k * xv + (goal - start) * mv)
  } else {
    // (one Move for all, on from the group's speed, as a share of how far all of it goes)
    let (p, pv) = if g.d <= 0.0 || g.dur <= 0.0 || t >= g.dur {
      (1.0, 0.0)
    } else {
      let v = fmin(g.v, move_k / g.dur * g.d)
      let (off, ov) = move_path(-g.d, v, t, g.dur)
      (1.0 + off / g.d, ov / g.d)
    }
    (s.come_from + (goal - s.come_from) * p, (goal - s.come_from) * pv)
  }
}

///|
/// What its way's length and turn were said by (Style's come_plan): as tall as it went to then; `goal` where none was.
fn plan_of(s : Style, goal : Double) -> Double {
  if known(s.come_plan) {
    s.come_plan
  } else {
    goal
  }
}

///|
/// How tall an item coming or going is laid out (Style's come_*), `natural` tall: where its way from `come_from` to
/// `come_to` of `natural`, set out at `come_v` (come_way), has got at `come_now`, its end (`come_ends`) said as long as
/// that way the first time it is laid out so, kept from then; NaN once it is there. `come_k` its share of `natural`
/// (0 … 1), for the gap before it.
fn come_height(s : Style, natural : Double) -> Double {
  let goal = s.come_to * natural
  s.come_goal = goal
  s.come_whole = natural
  if !known(s.come_ends) {
    s.come_ends = s.come_at + come_way_ms(s.come_from, s.come_v, goal)
    s.come_plan = goal
  }
  let dur = s.come_ends - s.come_at
  let t = s.come_now - s.come_at
  if dur <= 0.0 || t >= dur {
    s.come_k = fmax(fmin(s.come_to, 1.0), 0.0)
    return if s.come_to >= 1.0 { 0.0 / 0.0 } else { goal }
  }
  let (tall, _) = match s.come_group {
    Some(g) if g.set => come_group_way(g, s, goal, t)
    _ => come_way_by(s.come_from, s.come_v, goal, plan_of(s, goal), t)
  }
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
  let (tall, v) = match s.come_group {
    Some(g) if g.set => come_group_way(g, s, s.come_goal, t)
    _ => come_way_by(s.come_from, s.come_v, s.come_goal, plan_of(s, s.come_goal), t)
  }
  Some((fmax(tall, 0.0), v))
}
