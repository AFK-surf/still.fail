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
  // (its end where the time gone, on the moments' grid, comes to its length on that grid: a hair short is the end)
  if dur <= 0.0 || t >= time_gone(dur, 0.0) {
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
/// How fast (points a ms) a thing turned back goes for its turn to be seen at all: a frame's twentieth of a point, all
/// but still as it sets off (come_back_wbtest's judge of what hangs at its turn takes no turn slower). The scale over
/// which a turn's way goes from a Move's from rest, slower than it, to a slowing as far as its speed carries it, faster
/// (come_turn_w).
pub let turn_judged_from : Double = 0.05

///|
/// How much of a Move from rest the turn of a way set off again at `v` is: 1 at rest, falling to none as it is faster
/// than turn_judged_from, as (turn_judged_from/v)⁶, 1/(1 + x⁶), x = v / turn_judged_from; flat at rest and smooth all the
/// way, no speed either side of which it goes two ways. The sixth power (the coordinator of the migration, 2026-11-11):
/// a turn slower than can be seen goes nowhere further from the way from rest than three hundredths of its length
/// (2.4 at half turn_judged_from, at every length; the fourth power three times that, the eighth taking two speeds a
/// hundredth apart past 0.05 16.7 points apart in a frame); two speeds a thousandth apart either side
/// of rest go ways within that thousandth's worth of each other (come_way_wbtest), and one turned at twice
/// turn_judged_from, seen going, goes on a frame before it comes back (come_back_wbtest's called back at 0.8 of its
/// closing, 0.098 a ms).
fn come_turn_w(v : Double) -> Double {
  let x = v / turn_judged_from
  let x2 = x * x
  1.0 / (1.0 + x2 * x2 * x2)
}

///|
/// A way set off again at `v` away from where it goes, `far` from there (signed, where it goes less where it is), its
/// way back going `along` another (or none): slowing at one rate to rest, `t1` ms, carried `s` (signed as `v`), its
/// gain then `a` (points a ms², toward where it goes), and its way back from there, `dur` ms, setting out at rest
/// gaining `a` (come_back_path). How long it slows is what is weighed (come_turn_w), between how long a Move from rest
/// there would take to take that speed up (v/ω²·D, ω = move_k / dur: all but none, where it is all but still) and how
/// long that speed takes to be told to stop (2·move_stop_points/v: 54 ms at the least, move_ms's, where it is faster):
/// t1 = move^w·stop^(1 − w), weighed by their logarithms, the two being orders of magnitude apart (the coordinator of
/// the migration, 2026-11-11: weighed as a sum, the 54 ms of stop ruled as soon as w fell a thousandth short of 1, a
/// turn at a fifth of a point a frame setting out a third as fast as from rest), `a` = v/t1 what follows of it. So at rest it is a Move from rest, and seen going it turns
/// over frames, never within one. Steep, known and taken (the coordinator of the migration, 2026-11-11): far, a Move from
/// rest gains at once and a turn seen must gain slowly, the two a few hundredths of a point a ms apart and the way back
/// thirty or forty points a frame, so a 345-point way's frames at speeds 0.01 apart are as far as 51 points apart between
/// 0 and 0.01 (15 to 24 on to 0.05): its way back setting out a frame later, no step in where it is (at rest a Move to
/// the bit, a thousandth apart within its share, no speed taking another shape). Never steep only if a Move from rest
/// set out gaining slowly too, every way's feel, not this. How far the way back goes is how far it is carried, and how
/// long that takes how fast it slows: worked out again from what each says of the other, a few times over (each the
/// nearer, the slowing being no more than a share of the way, and the length of a Move coming in whole frames: no step
/// of it moves the carry past where the one before had it), a fixed number of times, so the same of the same way at any
/// frame. `w` its come_turn_w.
pub struct ComeTurn {
  /// the speed and how far it was worked out for (a way's own, said at its cause: what keeps it, ComeKept, holds it
  /// for those alone)
  v : Double
  far : Double
  /// where the way it goes along ends (ComeWith's `ends`; NaN: along none), for what keeps it
  ends : Double
  t1 : Double
  s : Double
  a : Double
  dur : Double
  w : Double
}

///|
fn come_turned(v : Double, far : Double, along : ComeWith?) -> ComeTurn {
  let speed = v.abs()
  let w = come_turn_w(v)
  let stop = move_stop_points(v)
  let a_stop = speed * speed / (2.0 * stop)
  let mut s = 0.0
  let mut a = a_stop
  let mut t1 = 0.0
  let mut dur = 0.0
  for _ in 0..<come_turn_rounds {
    let d = far.abs() + s
    t1 = speed / a
    dur = come_move_ms(d, t1, along)
    let om = if dur > 0.0 { move_k / dur } else { 0.0 }
    let a_move = om * om * d * move_start_gain
    if a_move <= 0.0 {
      break
    }
    // (how long it slows weighed by its logarithm, its gain what follows: t1 = (v/a_move)^w·(v/a_stop)^(1 − w))
    let was = a
    a = @dmath.exp(w * @dmath.ln(a_move) + (1.0 - w) * @dmath.ln(a_stop))
    s = speed * speed / (2.0 * a)
    if (a - was).abs() <= 1.0e-12 * a {
      break
    }
  }
  t1 = speed / a
  dur = come_move_ms(far.abs() + s, t1, along)
  let ends = match along {
    Some(w) => w.ends
    None => 0.0 / 0.0
  }
  { v, far, ends, t1, s: if v > 0.0 { s } else { -s }, a, dur, w }
}

///|
/// How much more than ω²·d a Move from rest gains as it sets out, d off its end (move_path's, what is left at its end
/// taken off gaining too: (1 + move_k)·e^(−move_k)/move_end more): what a turn at rest sets out gaining, so that its way
/// back is that Move to the bit (come_back_path).
let move_start_gain : Double = 1.0 + (1.0 + move_k) * @dmath.exp(-move_k) / move_end

///|
/// How many times come_turned works out its slowing and its way back again from each other: enough for both to stand
/// still to the last bit in the ways the tests go (four or five), a few more for any other.
let come_turn_rounds : Int = 12

///|
/// How fast a way back set out still and not gaining dies away over its `dur` (come_back_path's ω·dur where it is all
/// such a way): what a third-order spring has still to go at its end as little as a Move's has at its,
/// (1 + k + k²/2)·e^(−k) = (1 + move_k)·e^(−move_k), so it comes to rest going as slowly as a Move does (1.14 times),
/// not at 3.7 times its speed.
let come_back_k : Double = come_back_k_of(move_k)

///|
/// How many times come_back_k_of halves where it looks: from k to 4k down to the last bit of a Double.
let come_back_k_halvings : Int = 64

///|
fn come_back_k_of(k : Double) -> Double {
  let left = (1.0 + k) * @dmath.exp(-k)
  let mut lo = k
  let mut hi = 4.0 * k
  for _ in 0..<come_back_k_halvings {
    let mid = (lo + hi) / 2.0
    if (1.0 + mid + mid * mid / 2.0) * @dmath.exp(-mid) > left {
      lo = mid
    } else {
      hi = mid
    }
  }
  (lo + hi) / 2.0
}

///|
/// Where a way back is `t` ms into its `dur`, `d` off its end (signed) as it sets out at rest gaining `a` (toward its end:
/// points a ms²), `w` how much of a Move from rest its turn is (come_turn_w): a critically damped spring of the third
/// order, (d + ω·d·t + c·t²)·e^(−ω·t), ω = k / dur (a Move's move_k as far as `w` to the fourth says, come_back_k for
/// the rest), made to rest at `dur` as move_path is, what it would
/// still have left there taken off by a curve that is a Move's from rest as far as `w` to the fourth says and one set
/// out still and not gaining (1 − (1 + x + x²/2)·e^(−x)) for the rest. `c` such that, with what is taken off, it sets
/// out gaining `a` to the bit: as it sets out its place, speed and gain are where the slowing left them; at rest (`a` a
/// Move's own, ω²·d·move_start_gain, and `w` 1) a Move from rest, `c` none. Its offset from its end
/// and how fast it goes.
pub fn come_back_path(d : Double, a : Double, w : Double, t : Double, dur : Double) -> (Double, Double) {
  if dur <= 0.0 || t >= time_gone(dur, 0.0) {
    return (0.0, 0.0)
  }
  if t <= 0.0 {
    return (d, 0.0)
  }
  // (how fast it dies away: a Move's as far as w to the fourth says, come_back_k's for the rest)
  let wm = w * w * (w * w)
  let k = wm * move_k + (1.0 - wm) * come_back_k
  let om = k / dur
  let c1 = om * d
  let x = k * t / dur
  let e = @dmath.exp(-x)
  let end2 = 1.0 - (1.0 + k) * @dmath.exp(-k)
  let end3 = 1.0 - (1.0 + k + k * k / 2.0) * @dmath.exp(-k)
  // (what is taken off to rest at its end: a Move's from rest as far as w to the fourth says, all of it at rest and all
  // but none once it is going at all, so it is a Move from rest there to the bit's worth; one set out still and not
  // gaining for the rest)
  let m = wm * (1.0 - (1.0 + x) * e) / end2 + (1.0 - wm) * (1.0 - (1.0 + x + x * x / 2.0) * e) / end3
  let mv = wm * x * e * k / dur / end2 + (1.0 - wm) * x * x / 2.0 * e * k / dur / end3
  // (c so that it sets out gaining `a` toward its end, what is taken off with it: its gain at the start 2c − ω²d less
  // what is left at its end times a Move's gain at the start, ω²/move_end, as much as wm of it; what is left at its end
  // (d + c1·dur + c·dur²)·e^(−move_k), so c of a line's: c = (ω²d − a + A·M)/(2 − B·M))
  let left = @dmath.exp(-k)
  let mm = wm * om * om / end2
  let a_to = if d >= 0.0 { a } else { -a }
  let c2 = (om * om * d - a_to + (d + c1 * dur) * left * mm) / (2.0 - dur * dur * left * mm)
  let at = fn(t : Double) {
    let e = @dmath.exp(-om * t)
    let p = d + c1 * t + c2 * t * t
    (p * e, (c1 + 2.0 * c2 * t - om * p) * e)
  }
  let (y, yv) = at(t)
  let (yt, _) = at(dur)
  (y - yt * m, yv - yt * mv)
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
#derive(Eq, Debug)
pub(all) struct ComeWith {
  start : Double
  ends : Double
}

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
/// How long (ms) a way from `from` tall to `goal`, set out at `v` (points a ms), takes: turned away from `goal`, its
/// slowing to rest and its way back from there, as long as how far that is (come_turned); from rest, a Move as long; set
/// out toward `goal`, a Move on from `v` (come_toward). Going `along` another way: there as that one ends (its slowing,
/// turned, no shorter).
pub fn come_way_ms(
  from : Double,
  v : Double,
  goal : Double,
  along? : ComeWith,
  kept? : ComeKept,
) -> Double {
  if come_toward(from, v, goal) {
    return come_on_ms(goal - from, along)
  }
  if v == 0.0 {
    return come_move_ms(goal - from, 0.0, along)
  }
  let tr = come_turned_kept(v, goal - from, along, kept)
  tr.t1 + tr.dur
}

///|
/// Whether turn `tr` was worked out going along `along` (none for none): what keeps it is for that way alone.
fn come_turn_along(tr : ComeTurn, along : ComeWith?) -> Bool {
  match along {
    Some(w) => tr.ends == w.ends
    None => tr.ends.is_nan()
  }
}

///|
/// The turn of an item's way (Style's come_*) toward `plan`, kept on it (Style's come_turn) the first time it is asked
/// for its speed and length and read again after; None where its way is not turned back.
fn come_style_turn(s : Style, plan : Double, along? : ComeWith) -> ComeTurn? {
  let v = s.come_v
  if v == 0.0 || come_toward(s.come_from, v, plan) {
    return None
  }
  let far = plan - s.come_from
  match s.come_turn {
    Some(tr) if tr.v == v && tr.far == far && come_turn_along(tr, along) => Some(tr)
    _ => {
      let tr = come_turned(v, far, along)
      s.come_turn = Some(tr)
      Some(tr)
    }
  }
}

///|
/// What a way turned back keeps of its turn (come_turned, worked out of its speed and how far it goes, which its cause
/// says once): worked out the first time the way is asked where it is and read again each frame after, not worked out
/// again (the coordinator of the migration, 2026-11-11: a way is data said at its cause). Held by what holds the way
/// (a sheet's way; an item's, its Style's come_turn); one way's speed and length kept for it alone, another's worked out anew.
pub struct ComeKept {
  priv mut turn : ComeTurn?
}

///|
pub fn ComeKept::new() -> ComeKept {
  { turn: None }
}

///|
/// come_turned of `v` and `far`, as `kept` holds it for them (and keeps it where it held none for them); with `along`,
/// or nothing to keep it, worked out.
fn come_turned_kept(
  v : Double,
  far : Double,
  along : ComeWith?,
  kept : ComeKept?,
  turn? : ComeTurn,
) -> ComeTurn {
  if turn is Some(tr) && tr.v == v && tr.far == far && come_turn_along(tr, along) {
    return tr
  }
  match (kept, along) {
    (Some(k), None) =>
      match k.turn {
        Some(tr) if tr.v == v && tr.far == far => tr
        _ => {
          let tr = come_turned(v, far, None)
          k.turn = Some(tr)
          tr
        }
      }
    _ => come_turned(v, far, along)
  }
}

///|
/// Where a way from `from` tall to `goal`, set out at `v` (points a ms), has got `t` ms on, and how fast it goes (points
/// a ms): turned away from `goal`, on from `v` slowing at one rate to rest and from there its way back, set out still and
/// gaining as it slowed, its place, speed and gain going on where the two meet (come_turned, come_back_path); from rest,
/// a Move from rest; set out toward `goal`, a Move on from `v` (come_toward). Its speed the same as `v` as it sets out, whichever way that is (the coordinator of the migration,
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
  kept? : ComeKept,
  turn? : ComeTurn,
) -> (Double, Double) {
  // (going toward where it goes already: a Move on from that speed, not slowed to rest on the way, stalling)
  if come_toward(from, v, plan) {
    let (off, ov) = move_path(from - goal, v, t, come_on_ms(plan - from, along))
    return (goal + off, ov)
  }
  // (from rest: a Move from rest, as ever)
  if v == 0.0 {
    let far = goal - from
    if t <= 0.0 {
      return (from, 0.0)
    }
    let dur = come_move_ms(plan - from, 0.0, along)
    if dur <= 0.0 || t >= time_gone(dur, 0.0) {
      return (from + far, 0.0)
    }
    let (off, ov) = move_path(-far, 0.0, t, dur)
    return (from + far + off, ov)
  }
  // (turned back: slowing at one rate to rest, then its way back from there set out still and gaining as it slowed)
  let tr = come_turned_kept(v, plan - from, along, kept, turn?)
  // (at its end, there: its slowing and its way back as long as come_way_ms says, to the bit)
  if t >= tr.t1 + tr.dur {
    return (goal, 0.0)
  }
  if t <= tr.t1 {
    let g = if v > 0.0 { -tr.a } else { tr.a }
    return (from + v * t + g * t * t / 2.0, v + g * t)
  }
  let (off, ov) = come_back_path(from + tr.s - goal, tr.a, tr.w, t - tr.t1, tr.dur)
  (goal + off, ov)
}

///|
/// What comes or goes down one column at one moment, with what was on its way there then (the user, 2026-11-03: a
/// change come while others go is put with what is left of theirs, one whole going to where it all ends): one way for
/// all of it, each item its share. Its speed (`v`, points a ms) the items' toward where each goes, summed, and how far
/// all of them go (`far`, the most of any); turned away from where it goes (v < 0), all of it slows as one first, each
/// on along its own speed by that one slowing (at one rate, `a`, `t1` long, carried `s`: as come_turned's), then one way
/// back from where each has come to, `dur` long, set out still and gaining as all of it slowed (come_back_path); else one Move from rest or on from `v` (no faster
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
  mut a : Double
  mut w : Double
  mut dur : Double
}

///|
/// A group said at moment `at`, none in it yet.
pub fn ComeGroup::new(at : Double) -> ComeGroup {
  { at, members: [], set: false, v: 0.0, d: 0.0, s: 0.0, t1: 0.0, a: 0.0, w: 0.0, dur: 0.0 }
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
  // (turned away as a whole: slowing at one rate to rest, as one (come_turned's, of its speed and how far all of it
  // goes back: its gain then a Move's from rest for all of it, ω²·D, where it is all but still), each carried as far as
  // its own speed is of the group's, then its way back from there; what each then goes worked out again from how far
  // that carries it, the same number of times)
  let speed = -v
  let w = if v < 0.0 { come_turn_w(v) } else { 0.0 }
  let a_stop = if v < 0.0 { speed * speed / (2.0 * move_stop_points(v)) } else { 0.0 }
  let mut s = 0.0
  let mut a = a_stop
  let mut far = 0.0
  let mut dd = 0.0
  let mut t1 = 0.0
  let mut dur = 0.0
  let measure = fn(s : Double) {
    let mut far = 0.0
    let mut dd = 0.0
    for m in g.members {
      let start = if v < 0.0 { m.come_from + m.come_v * s / v } else { m.come_from }
      let d = (m.come_goal - start).abs()
      far = fmax(far, d)
      dd = dd + d
    }
    (far, dd)
  }
  if v < 0.0 {
    for _ in 0..<come_turn_rounds {
      let (f, d) = measure(s)
      t1 = speed / a
      let du = come_move_ms(f, t1, None)
      let om = if du > 0.0 { move_k / du } else { 0.0 }
      let a_move = om * om * d * move_start_gain
      if a_move <= 0.0 {
        break
      }
      let was = a
      a = 1.0 / ((1.0 - w) / a_stop + w / a_move)
      s = -(speed * speed / (2.0 * a))
      if (a - was).abs() <= 1.0e-12 * a {
        break
      }
    }
    t1 = speed / a
  }
  let (f, d) = measure(s)
  far = f
  dd = d
  dur = if v < 0.0 { come_move_ms(far, t1, None) } else if far < 0.5 { 0.0 } else { move_ms(far) }
  g.s = s
  g.t1 = t1
  g.a = a
  g.w = w
  g.d = dd
  g.dur = dur
  let ends = g.at + (if v < 0.0 { t1 + g.dur } else { g.dur })
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
    // (slowing as one at one rate: carried as far as its own speed is of the group's; then its share of one way back,
    // set out still and gaining, as all of it, as it slowed: come_back_path of all of it, as a share)
    let k = s.come_v / g.v
    if t <= g.t1 {
      let x = g.v * t + g.a * t * t / 2.0
      return (s.come_from + k * x, k * (g.v + g.a * t))
    }
    let start = s.come_from + k * g.s
    let (y, yv) = if g.d > 0.0 { come_back_path(1.0, g.a / g.d, g.w, t - g.t1, g.dur) } else { (0.0, 0.0) }
    (start + (goal - start) * (1.0 - y), -(goal - start) * yv)
  } else {
    // (one Move for all, on from the group's speed, as a share of how far all of it goes)
    let (p, pv) = if g.d <= 0.0 || g.dur <= 0.0 || t >= time_gone(g.dur, 0.0) {
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
    s.come_ends = s.come_at + (match (s.come_spec, s.come_group) {
        (Some((ms, _)), g) if !(g is Some(g) && g.set) => ms
        _ =>
          match come_style_turn(s, goal) {
            Some(tr) => tr.t1 + tr.dur
            None => come_way_ms(s.come_from, s.come_v, goal)
          }
      })
    s.come_plan = goal
  }
  let dur = s.come_ends - s.come_at
  let t = time_gone(s.come_now, s.come_at)
  if dur <= 0.0 || t >= time_gone(dur, 0.0) {
    s.come_k = fmax(fmin(s.come_to, 1.0), 0.0)
    return if s.come_to >= 1.0 { 0.0 / 0.0 } else { goal }
  }
  let tall = come_tall_on(s, goal, t)
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
/// How tall item `s` is `t` ms into its way to `goal`, its way under way (come_height's, come_tall_at's): its group's
/// share or its own way, never less than nothing; on a host's grid where it says one (Style's come_grid), toward where it
/// goes and never past its rest: closing, put down and no less than `goal`; growing, put up and no more. What a way turned
/// back sets out from (come_state) is as it is.
fn come_tall_on(s : Style, goal : Double, t : Double) -> Double {
  let (tall, _) = match (s.come_group, s.come_spec) {
    (Some(g), _) if g.set => come_group_way(g, s, goal, t)
    (_, Some(spec)) => come_spec_way(s, spec, goal, t)
    _ => come_way_by(s.come_from, s.come_v, goal, plan_of(s, goal), t, turn?=come_style_turn(s, plan_of(s, goal)))
  }
  let tall = fmax(tall, 0.0)
  let g = s.come_grid
  if g <= 0.0 || !known(goal) {
    tall
  } else if goal < s.come_from {
    fmax((tall * g + 0.000001).floor() / g, goal)
  } else {
    fmin((tall * g - 0.000001).ceil() / g, goal)
  }
}

///|
/// How tall item `s` is `t` ms into its way to `goal` said by `spec` (Style's come_spec: how long, on what curve), and
/// how fast its height goes then (points a ms, by the curve's slope there).
fn come_spec_way(s : Style, spec : (Double, (Double) -> Double), goal : Double, t : Double) -> (Double, Double) {
  let (ms, curve) = spec
  if ms <= 0.0 || t >= ms {
    return (goal, 0.0)
  }
  let x = fmax(t / ms, 0.0)
  let dx = 1.0e-4
  let p = curve(x)
  let slope = (curve(fmin(x + dx, 1.0)) - p) / (fmin(x + dx, 1.0) - x) / ms
  (s.come_from + (goal - s.come_from) * p, (goal - s.come_from) * slope)
}

///|
/// How tall item `s`, coming or going (Style's come_*), `natural` tall where it comes to all of it, is laid out at
/// moment `at`: what come_height lays it out at with its clock there, to the bit, worked out the same way, nothing of
/// it changed. Its way's end where it was never laid out yet, as its first layout will say it (as long as a Move from
/// where it sets out to `natural`'s share); `natural` on no way, or past its end coming, what it goes to going. What a
/// list reads a place by as its blocks make their way (View::scrolls_window), between frames as at them.
pub fn come_tall_at(s : Style, natural : Double, at : Double) -> Double {
  if !known(s.come_at) || !known(s.come_to) {
    return natural
  }
  let goal = s.come_to * natural
  let ends = if known(s.come_ends) {
    s.come_ends
  } else {
    s.come_at +
    (match (s.come_spec, s.come_group) {
      (Some((ms, _)), g) if !(g is Some(g) && g.set) => ms
      _ =>
        match come_style_turn(s, goal) {
          Some(tr) => tr.t1 + tr.dur
          None => come_way_ms(s.come_from, s.come_v, goal)
        }
    })
  }
  let dur = ends - s.come_at
  let t = time_gone(at, s.come_at)
  if dur <= 0.0 || t >= time_gone(dur, 0.0) {
    return if s.come_to >= 1.0 { natural } else { goal }
  }
  come_tall_on(s, goal, t)
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
  let t = time_gone(at, s.come_at)
  if dur <= 0.0 || t >= time_gone(dur, 0.0) {
    return Some((s.come_goal, 0.0))
  }
  let (tall, v) = match (s.come_group, s.come_spec) {
    (Some(g), _) if g.set => come_group_way(g, s, s.come_goal, t)
    (_, Some(spec)) => come_spec_way(s, spec, s.come_goal, t)
    _ => {
      let plan = plan_of(s, s.come_goal)
      come_way_by(s.come_from, s.come_v, s.come_goal, plan, t, turn?=come_style_turn(s, plan))
    }
  }
  Some((fmax(tall, 0.0), v))
}

///|
/// The one way a motion's time gone is taken: `now` less `start` (ms), put on the moments' grid (1e-6 ms), so that a
/// moment summed one way or another (1316.9999999999998 for 1317) reads the same to the bit wherever it is read, and
/// nothing coarser (whole ms stepped 8, 8, 9 ms at 120 frames a second: the coordinator of the migration, 2026-11-11).
/// A difference of two moments each on the grid is not on it: the grid is taken here, on the difference, never on a
/// moment alone. At a way's fastest (some 3 points a ms) the grid is 3e-6 points, under any device's pixel.
pub fn time_gone(now : Double, start : Double) -> Double {
  ((now - start) / 1.0e-6).round() * 1.0e-6
}
