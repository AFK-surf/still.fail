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
/// How tall an item coming or going is laid out (Style's come_*), `natural` tall: where its way from `come_from` to
/// `come_to` of `natural` has got at `come_now`, its end (`come_ends`) said by a Move as long as how far that is the
/// first time it is laid out so, kept from then; NaN once it is there. `come_k` its share of `natural` (0 … 1), for the
/// gap before it.
fn come_height(s : Style, natural : Double) -> Double {
  let goal = s.come_to * natural
  if !known(s.come_ends) {
    // (nowhere to go: there at once)
    let far = (goal - s.come_from).abs()
    s.come_ends = s.come_at + (if far < 0.5 { 0.0 } else { move_ms(far) })
  }
  let dur = s.come_ends - s.come_at
  let t = if dur > 0.0 { (s.come_now - s.come_at) / dur } else { 1.0 }
  if t >= 1.0 {
    s.come_k = fmax(fmin(s.come_to, 1.0), 0.0)
    return if s.come_to >= 1.0 { 0.0 / 0.0 } else { goal }
  }
  let tall = fmax(s.come_from + (goal - s.come_from) * move_at(t), 0.0)
  s.come_k = if natural > 0.0 { fmax(fmin(tall / natural, 1.0), 0.0) } else { s.come_to }
  tall
}
