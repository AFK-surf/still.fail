// A column that scrolls as a page's list does (Scroll::list): as an old view's list (ui's Ctx::list, its scroll.mbt)
// moves on the platform it is on, which what hosts the tree says (Tree::lists_feel): Android's spline fling and its
// stretch at the ends, iOS's deceleration and rubber band, the desktop's coast stopping at its ends. Each is said once
// at its cause (the hand let go: where the fling meets its end and what goes back from there worked out then), and is a
// function of the time from there (list_motion.mbt, one with the old view's list's): where it is, how far it shows past
// an end, when all of it is at rest.

///|
/// How a page's list moves where the tree is drawn (Tree::lists_feel): as the desktop's, iOS's or Android's.
#derive(Eq)
pub(all) enum ListFeel {
  Desktop
  Ios
  Android
}

///|
/// How far a finger moves on a page's list before it drags it (the window's points): Android's touch slop, 8 dp; 6
/// elsewhere (as an old view's list's, ui's touch_slop).
fn list_slop(feel : ListFeel) -> Double {
  if feel == Android {
    8.0
  } else {
    6.0
  }
}

///|
/// What shows past an end of a page's list (`edge` 1 its top, -1 its foot) on iOS or Android: held there (`back` none),
/// pulled `over` (Android: its heights; iOS: the points pulled, shown on the rubber band); or going back on `back` from
/// where it showed (Android: its heights; iOS: the points shown). `h` its height in points, `px` in pixels, as of then.
priv struct Past {
  feel : ListFeel
  edge : Int
  over : Double
  back : BackPath?
  h : Double
  px : Double
}

///|
/// How far it shows past its end at `t` (Android: its heights; iOS: the points shown).
fn Past::shows(self : Past, t : Double) -> Double {
  match self.back {
    None => if self.feel == Ios { rubber(self.over, self.h) } else { self.over }
    Some(p) =>
      if t >= p.rest {
        0.0
      } else if t < p.t0 {
        p.x0
      } else if self.feel == Android {
        p.edge_now(self.px, t).0
      } else {
        dmax(rubber_at(p.x0, p.v0, t - p.t0).0, 0.0)
      }
  }
}

///|
/// A page's list's wheel's notches easing in: from `x0`, `total` of them to come, set out at `v0` (points a ms) at `t0`
/// (list_motion.mbt's ease_come; as an old view's list's, ui's Ctx::ease_list).
priv struct Notch {
  x0 : Double
  total : Double
  v0 : Double
  t0 : Double
  /// its ease's time constant (wheel_ease_ms; less where a glide went on toward an end come nearer than its speed eases
  /// to: Scroll::glide_on)
  tau : Double
  /// when (ms after `t0`) it is drawn where it comes to, on the pixels it is drawn on (Scroll::ease_drawn_end): all of
  /// it come from then on
  end : Double
  /// the way its page said it goes (a glide back to a list's foot a send asks: ListPlace::to_end's `way`): that long
  /// (ms after `t0`) on that curve, not an ease; `base` how much of that curve was gone where it was last set on toward
  /// another end (Scroll::glide_on), what is left of the curve then taking it from `x0` to `x0 + total`
  way : (Double, (Double) -> Double)?
  base : Double
}

///|
/// How far notch `n` has come `t` ms after it set out, and how fast (points a ms): on its way where one is said, else
/// its ease (ease_state), all of it from its end on.
fn notch_state(n : Notch, t : Double) -> (Double, Double) {
  if t >= n.end {
    return (n.total, 0.0)
  }
  match n.way {
    Some((ms, curve)) if ms > 0.0 => {
      let x = dclamp(t / ms, 0.0, 1.0)
      let left = 1.0 - n.base
      guard left > 0.000001 else { return (n.total, 0.0) }
      let dx = 0.0001
      let x2 = dmin(x + dx, 1.0)
      let p = (curve(x) - n.base) / left
      let speed = if x2 > x { (curve(x2) - curve(x)) / (x2 - x) / ms / left * n.total } else { 0.0 }
      (n.total * p, speed)
    }
    _ => ease_state(n.total, n.v0, t, tau=n.tau)
  }
}

///|
/// How far down the drawn list is moved at scroll `x`, `past` shown past an end: on the pixels it is drawn on (its
/// host's grid where it sets the list's rows on it, else the tree's pixels), as Scroll::held_dy draws it.
fn Scroll::drawn_off(self : Scroll, tree : Tree, at : Int, x : Double, past : Double) -> Double {
  (self.drawn_by(tree, at))(-x + past)
}

///|
/// Where node `at` (what a page's list holds) is drawn moved by `d` as it is laid out now: what is the same for every
/// `d` worked out once (Tree::rows_placed's walk up what holds it), to the bit as rows_placed and the pixels' rounding
/// say it, so that looking for a moment on a curve asks it many times for little.
fn Scroll::drawn_by(self : Scroll, tree : Tree, at : Int) -> (Double) -> Double {
  ignore(self)
  let n = tree.nodes[at]
  if tree.rows_grid > 0.0 && n.list_rows {
    let g = tree.rows_grid
    let first = tree.first_row(at)
    guard first >= 0 else { return fn(d) { d } }
    let up = tree.rows_laid_y(n.parent)
    let ftop = tree.nodes[first].flex.top
    // (Tree::rows_placed, its sums in its order)
    let placed = fn(y : Double) {
      let top = up + y + ftop
      y + (top * g).round() / g - top
    }
    let y = n.flex.top + off_y(n)
    let at_y = placed(y)
    fn(d) { placed(y + d) - at_y }
  } else if tree.pixel_grid > 0.0 {
    let g = tree.pixel_grid
    fn(d) { (d * g).round() / g }
  } else {
    fn(d) { d }
  }
}

///|
/// When (ms after it sets out) an ease of `total` from `x0` at `v0` (ease_come) is drawn where it comes to and stays
/// so: what is left of it then under the half of a pixel it is drawn on that keeps it there (Scroll::drawn_off), worked
/// out as it sets out from its own curve (what is left (total + k t) e^(-t / τ) changes sign once at most, then only
/// falls: the last moment it is drawn elsewhere found back from ease_end, then to the µs). On no pixels (a tree none
/// said), ease_end.
fn Scroll::ease_drawn_end(
  self : Scroll,
  x0 : Double,
  total : Double,
  v0 : Double,
  tau? : Double = wheel_ease_ms,
  most? : Double,
) -> Double {
  let bound = ease_end(total, v0, tau~)
  guard self.host is Some(v) && v.alive() && bound > 0.0 else { return bound }
  let tree = v.tree
  // (what it holds, drawn off as it scrolls: Scroll::held_dy's node)
  let at = tree.nodes[v.at].scroll_held
  guard at >= 0 else { return bound }
  let n = tree.nodes[at]
  guard (tree.rows_grid > 0.0 && n.list_rows) || tree.pixel_grid > 0.0 else { return bound }
  let most = most.unwrap_or(self.most())
  let past = self.past_moved(tree.logic_said())
  let by = self.drawn_by(tree, at)
  let drawn = fn(t : Double) { by(-dclamp(x0 + ease_come(total, v0, t, tau~), 0.0, most) + past) }
  let rest = drawn(bound)
  let mut t = bound.floor()
  while t > 0.0 && drawn(t) == rest {
    t = t - 1.0
  }
  if t <= 0.0 && drawn(0.0) == rest {
    return 0.0
  }
  // (drawn elsewhere at t, where it rests at t + 1: the moment between, to the µs)
  let mut lo = t
  let mut hi = t + 1.0
  while hi - lo > 0.001 {
    let mid = (lo + hi) / 2.0
    if drawn(mid) == rest {
      hi = mid
    } else {
      lo = mid
    }
  }
  hi
}

///|
/// A page's list's fling, its platform's way: Android's spline `dist` points long over `dur` ms; iOS's deceleration;
/// the desktop's coast. On Android what of it first undoes a stretch past the end it leaves (`over`, its heights, at
/// `edge`; four times as fast as a finger undoes it, Compose's applyToScroll): `eats` points of it. Where it meets an
/// end, what goes back from there (`hit`, from the fling's end). `h` and `px`: the list's height in points and pixels.
priv struct ListWay {
  feel : ListFeel
  dist : Double
  dur : Double
  eats : Double
  over : Double
  edge : Int
  h : Double
  px : Double
  hit : Past?
  /// what showed past the end it goes to as it set out (Android's, its heights)
  same : Double
}

///|
/// How far a fling at `v0` has gone `t` ms after it set out (Android's in whole ms played, Compose's playtime).
fn ListWay::gone(self : ListWay, v0 : Double, t : Double) -> Double {
  let t = dmax(t, 0.0)
  match self.feel {
    Android => self.dist * spline_at(t.floor(), self.dur).0
    Ios => v0.abs() * (@dmath.pow(ios_decel, t) - 1.0) / @dmath.ln(ios_decel)
    Desktop => v0.abs() * (@dmath.pow(coast_decel, t) - 1.0) / @dmath.ln(coast_decel)
  }
}

///|
/// How fast a fling at `v0` goes `t` ms after it set out (points a ms).
fn ListWay::speed(self : ListWay, v0 : Double, t : Double) -> Double {
  match self.feel {
    Android => spline_at(t.floor(), self.dur).1 * self.dist / dmax(self.dur, 1.0)
    Ios => v0.abs() * @dmath.pow(ios_decel, t)
    Desktop => v0.abs() * @dmath.pow(coast_decel, t)
  }
}

///|
/// How long a fling at `v0` runs (ms): Android's its duration in whole ms; iOS's and the desktop's till it is under
/// 0.02 points a ms (as an old view's list's, ListState::fling_length).
fn ListWay::length(self : ListWay, v0 : Double) -> Double {
  match self.feel {
    Android => self.dur.ceil()
    Ios => dmax(0.0, @dmath.ln(0.02 / v0.abs()) / @dmath.ln(ios_decel))
    Desktop => dmax(0.0, @dmath.ln(0.02 / v0.abs()) / @dmath.ln(coast_decel))
  }
}

///|
/// When (ms after it set out, no later than `len`) a fling at `v0` has gone `need`: +inf, never. Android's at the whole
/// ms it gets there (Compose's playtime).
fn ListWay::reaches(self : ListWay, v0 : Double, need : Double, len : Double) -> Double {
  if self.feel == Android {
    if self.gone(v0, len) < need {
      return @double.infinity
    }
    let mut lo = 0.0
    let mut hi = len
    if self.gone(v0, 0.0) >= need {
      return 0.0
    }
    // (gone short of it at lo, there at hi)
    while hi - lo > 1.0 {
      let m = ((lo + hi) / 2.0).floor()
      if self.gone(v0, m) >= need {
        hi = m
      } else {
        lo = m
      }
    }
    hi
  } else {
    if need <= 0.0 {
      return 0.0
    }
    let k = if self.feel == Ios { ios_decel } else { coast_decel }
    let arg = 1.0 + need * @dmath.ln(k) / v0.abs()
    if arg <= 0.0 {
      return @double.infinity
    }
    let t = @dmath.ln(arg) / @dmath.ln(k)
    if t > len {
      @double.infinity
    } else {
      t
    }
  }
}

///|
/// Where fling `f` has it at `t` (before its end): what of it undoes a stretch first moving nothing.
fn ListWay::at(self : ListWay, f : Fling, t : Double) -> Double {
  let sign = if f.v0 < 0.0 { -1.0 } else { 1.0 }
  f.x0 + sign * dmax(0.0, self.gone(f.v0, t - f.t0) - self.eats)
}

///|
/// Whether it moves by itself now (a fling, a wheel's notches easing in, what shows past an end going back, the hand
/// past its edge), followed: whatever it is on by itself has its end said (Scroll::rest_now).
fn Scroll::goes_on(self : Scroll) -> Bool {
  self.rest_now() is Some(_)
}

///|
/// What shows past an end at `t`, followed: its edge, how far (Android: its heights; iOS: the points shown) and on
/// which platform's way; none, nothing.
fn Scroll::past_at(self : Scroll, t : Double) -> (Int, Double, ListFeel)? {
  match self.fling.get() {
    Some({ way: Some(w), end_t, v0, t0, .. }) =>
      if t >= end_t {
        w.hit.map(fn(p) { (p.edge, p.shows(t), p.feel) })
      } else if w.over > 0.0 {
        let left = dmax(0.0, w.over - w.gone(v0, t - t0) * 4.0 / dmax(w.h, 1.0))
        if left > 0.0 {
          Some((w.edge, left, w.feel))
        } else {
          None
        }
      } else {
        None
      }
    Some(_) => None
    None => self.past.get().map(fn(p) { (p.edge, p.shows(t), p.feel) })
  }
}

///|
/// How far what it holds shows moved past an end at `t` (iOS's rubber band; Android's stretch moves nothing, it is drawn
/// stretched), followed.
fn Scroll::past_moved(self : Scroll, t : Double) -> Double {
  match self.past_at(t) {
    Some((edge, x, Ios)) => x * edge.to_double()
    _ => 0.0
  }
}

///|
/// Android's stretch of what it holds at `t` (View::stretches: EdgeEffect's intensity, from its top positive), followed.
fn Scroll::stretch_drawn(self : Scroll, t : Double) -> Double {
  match self.past_at(t) {
    Some((edge, x, Android)) => stretch_amount(x) * edge.to_double()
    _ => 0.0
  }
}

///|
/// How far a page's list shows past an end at the logic's moment of `tree`: from its top positive, from its foot
/// negative (Android: its heights; iOS: the points shown moved), as an old view's list's (ui's Tester::list_overscroll).
pub fn Scroll::past(self : Scroll, tree : Tree) -> Double {
  @signals.untracked(fn() {
    match self.past_at(tree.logic_said()) {
      Some((edge, x, _)) => x * edge.to_double()
      None => 0.0
    }
  })
}

///|
/// What shows past an end at `t` held where it shows (a finger come down on it catches it there; what its fling undid,
/// what its way back brought it to), its way back called off; held already, left as it is.
fn Scroll::past_held(self : Scroll, t : Double) -> Unit {
  let flung = self.fling.untracked()
  let was = self.past.untracked()
  if flung is None && was is (None | Some({ back: None, .. })) {
    return
  }
  let now = @signals.untracked(fn() { self.past_at(t) })
  let (h, px) = match (flung, was) {
    (Some({ way: Some(w), .. }), _) => (w.h, w.px)
    (_, Some(p)) => (p.h, p.px)
    _ => (dmax((self.tall)(), 1.0), dmax((self.tall)(), 1.0))
  }
  if flung is None {
    (self.settle_off)()
    self.settle_off = fn() {  }
  }
  match now {
    Some((edge, x, feel)) if x > 0.0 =>
      self.past.set(Some({ feel, edge, over: if feel == Ios { unrubber(x, h) } else { x }, back: None, h, px }))
    _ => self.past.set(None)
  }
}

///|
/// Dragged by `d` (down the column) at `t`: what of it undoes what shows past an end does that first (Compose's
/// applyToScroll; iOS's rubber band), the rest moves it; what of that goes past an end pulls it there (Android: in its
/// heights, no further than one; iOS: on the rubber band), as an old view's list's (ui's Ctx::feed, Ctx::pull).
fn Scroll::dragged(self : Scroll, v : View, t : Double, d : Double) -> Unit {
  let x = self.stopped(t)
  let (feel, density) = (v.tree.list_feel)()
  let h = dmax((self.tall)(), 1.0)
  let mut d = d
  match self.past.untracked() {
    Some(p) if (p.edge > 0 && d > 0.0) || (p.edge < 0 && d < 0.0) => {
      let used = if p.feel == Android { dmin(d.abs(), p.over * h) } else { dmin(d.abs(), p.over) }
      let left = if p.feel == Android { dmax(0.0, p.over - d.abs() / h) } else { p.over - used }
      if left > 0.0 {
        self.past.set(Some({ ..p, over: left }))
        // (Android's: the whole move taken by the stretch)
        d = if p.feel == Android { 0.0 } else if d > 0.0 { d - used } else { d + used }
      } else {
        self.past.set(None)
        d = if d > 0.0 { d - used } else { d + used }
      }
    }
    _ => ()
  }
  let want = x + d
  self.moved(t, d) |> ignore
  let to = self.x.untracked()
  let by = (want - to).abs()
  // (Compose leaves out less than half a pixel)
  if feel != Desktop && want != to && by * density > 0.5 {
    let edge = if want < to { 1 } else { -1 }
    let over = match self.past.untracked() {
      Some(p) if p.edge == edge => p.over
      _ => 0.0
    }
    let over = if feel == Android { dmin(1.0, over + by / h) } else { over + by }
    self.past.set(Some({ feel, edge, over, back: None, h, px: h * density }))
  }
}

///|
/// Let go of at `t` at the hand's speed: flung on its platform's way, or what shows past an end going back, as an old
/// view's list's (ui's Ctx::release): on Android a fling away from a stretch no further than it is all taken by it
/// (Compose's applyToFling), a longer one undoes it first; on iOS what is pulled past an end goes back, no fling.
fn Scroll::let_go(self : Scroll, v : View, t : Double) -> Unit {
  let x0 = self.stopped(t)
  let speed = self.hand_v
  let (feel, density) = (v.tree.list_feel)()
  let h = dmax((self.tall)(), 1.0)
  let past = self.past.untracked()
  let way : ListWay = { feel, dist: 0.0, dur: 0.0, eats: 0.0, over: 0.0, edge: 0, h, px: h * density, hit: None, same: 0.0 }
  match feel {
    Android => {
      let mut way = way
      let mut same = 0.0
      match past {
        Some(p) => {
          let away = (p.edge > 0 && speed > 0.0) || (p.edge < 0 && speed < 0.0)
          if away && fling_distance(speed, density) <= p.over * h {
            self.past_back(v, p, -(speed.abs() * 1000.0 * density).round() * 13.0, t)
            return
          }
          if away {
            way = { ..way, eats: p.over * h / 4.0, over: p.over, edge: p.edge }
          } else {
            same = p.over
          }
        }
        None => ()
      }
      if speed.abs() * 1000.0 * density > 1.0 {
        let (dist, dur) = spline_fling(speed * 1000.0 * density, density)
        self.list_fling(v, t, x0, speed, { ..way, dist: dist / density, dur }, same, density)
      } else if past is Some(p) {
        self.past_back(v, p, 0.0, t)
      }
    }
    Ios =>
      match past {
        Some(p) if p.over > 0.0 =>
          // (outward is away from what it holds; from where it shows)
          self.past_back(v, { ..p, over: rubber(p.over, p.h) }, if p.edge > 0 { -speed } else { speed }, t)
        _ => if speed.abs() >= 0.02 { self.list_fling(v, t, x0, speed, way, 0.0, density) }
      }
    Desktop => if speed.abs() >= 0.02 { self.list_fling(v, t, x0, speed, way, 0.0, density) }
  }
}

///|
/// Flung from `x0` at `speed` at `t` on `way`: where it meets the end it goes to, worked out now, it stops there and
/// what it brings goes past it and back from then (Android's EdgeEffect.onAbsorb at its speed then, from what showed
/// there already, `same`; iOS's rubber band; the desktop's, nothing).
fn Scroll::list_fling(
  self : Scroll,
  v : View,
  t : Double,
  x0 : Double,
  speed : Double,
  way : ListWay,
  same : Double,
  density : Double,
) -> Unit {
  let bound = if speed > 0.0 { self.most() } else { 0.0 }
  guard list_planned(t, x0, speed, way, same, density, bound) is Some(f) else { return }
  self.past.set(None)
  self.fling.set(Some(f))
  self.scrolled_at(t)
  self.list_settles(v, t)
}

///|
/// A fling on `way` from `x0` at `speed` set out at `t`, toward the end it goes to at `bound` (its top, or its foot as
/// far as it can go then): where it meets it, worked out now, it stops there and what it brings goes past it and back
/// from then (Android's EdgeEffect.onAbsorb at its speed then, from what showed there already, `same`; iOS's rubber
/// band; the desktop's, nothing). None: it goes nowhere.
fn list_planned(
  t : Double,
  x0 : Double,
  speed : Double,
  way : ListWay,
  same : Double,
  density : Double,
  bound : Double,
) -> Fling? {
  let way = { ..way, hit: None }
  let len = way.length(speed)
  let sign = if speed < 0.0 { -1.0 } else { 1.0 }
  let hit_t = way.reaches(speed, (bound - x0).abs() + way.eats, len)
  let f : Fling = if hit_t < @double.infinity {
    let end_t = t + hit_t
    let edge = if speed > 0.0 { -1 } else { 1 }
    let hit = match way.feel {
      Desktop => None
      feel => {
        let p = BackPath::new()
        p.t0 = end_t
        let at = way.speed(speed, hit_t)
        if feel == Android {
          // (pixels a second, times EdgeEffect's ON_ABSORB_VELOCITY_ADJUSTMENT)
          p.x0 = same
          p.v0 = (at * 1000.0 * density).round() * 13.0
          p.plan_edge(way.px)
        } else {
          p.v0 = at
          p.plan_rubber()
        }
        Some({ feel, edge, over: same, back: Some(p), h: way.h, px: way.px })
      }
    }
    { x0, v0: speed, t0: t, end_t, end_x: bound, till: bound, way: Some({ ..way, hit, same }) }
  } else {
    let end_x = x0 + sign * dmax(0.0, way.gone(speed, len) - way.eats)
    { x0, v0: speed, t0: t, end_t: t + len, end_x, till: bound, way: Some({ ..way, same }) }
  }
  if f.end_t <= t && f.way.unwrap().hit is None {
    return None
  }
  Some(f)
}

///|
/// What it holds above where it is grew by `d` as of `t`, a fling of `f` under way (Scroll::grew_above): the fling the
/// same from where it set out moved by as much, toward its top where that is, or its foot where it is laid out (again
/// as that is laid out anew: Scroll::foot_moved), where it meets it worked out again, at rest then; met its end already, at rest there moved as much, what it brought going on back.
fn Scroll::fling_grew(self : Scroll, f : Fling, w : ListWay, t : Double, d : Double) -> Unit {
  if t >= f.end_t {
    self.fling.set(None)
    self.x.set(f.end_x + d)
    self.past.set(w.hit)
    return
  }
  // (its foot where it is as laid out now, that layout not done yet: met by then, not a meeting but where it was
  // before what grew; then none yet, its foot where the layout puts it worked out then, Scroll::foot_moved)
  let bound = if f.v0 < 0.0 {
    0.0
  } else if w.at({ ..f, x0: f.x0 + d }, t) < self.most() {
    self.most()
  } else {
    @double.infinity
  }
  let density = w.px / dmax(w.h, 1.0)
  match list_planned(f.t0, f.x0 + d, f.v0, w, w.same, density, bound) {
    Some(g) => self.fling.set(Some(g))
    None => {
      self.fling.set(None)
      self.x.set(f.x0 + d)
    }
  }
}

///|
/// What shows past an end (`p`, from where it shows) goes back from `t` at `v0` outward (Android: pixels a second;
/// iOS: points a ms), as an old view's list's (ui's Ctx::spring_back).
fn Scroll::past_back(self : Scroll, v : View, p : Past, v0 : Double, t : Double) -> Unit {
  let b = BackPath::new()
  b.t0 = t
  b.x0 = p.over
  b.v0 = v0
  if p.feel == Android {
    b.plan_edge(p.px)
  } else {
    b.plan_rubber()
  }
  self.past.set(Some({ ..p, back: Some(b) }))
  self.list_settles(v, t)
}

///|
/// The wheel come at `t`: a fling stopped where it is (what it brings past the end it met going on back as it was; what
/// of a stretch it had not undone yet going back from there, as nothing holds it), as an old view's list's (ui's
/// ListState::stop); what shows past an end going back left to go on.
fn Scroll::wheel_stops(self : Scroll, v : View, t : Double) -> Unit {
  guard self.fling.untracked() is Some(f) else { return }
  match f.way {
    // (met its end by now: at rest there, what it brought going on back, at rest as it said)
    Some({ hit: Some(p), .. }) if t >= f.end_t => {
      self.fling.set(None)
      self.x.set(dclamp(f.end_x, 0.0, self.most()))
      self.past.set(Some(p))
    }
    Some(w) => {
      let left = @signals.untracked(fn() { self.past_at(t) })
      self.stopped(t) |> ignore
      match left {
        Some((edge, over, feel)) if over > 0.0 =>
          self.past_back(v, { feel, edge, over, back: None, h: w.h, px: w.px }, 0.0, t)
        _ => ()
      }
    }
    None => ()
  }
}

///|
/// A wheel's notch of `d` (down the column) at `t`: eased in over the next moments, what had not come yet of those
/// before carrying on into it from where it is and as fast as it moves then, as an old view's list's (ui's
/// Ctx::ease_list); whether it moves it (under way already, or not at its end that way: ListState::wheel_moves).
fn Scroll::notched(self : Scroll, v : View, t : Double, d : Double) -> Bool {
  let (x0, total, v0) = match self.notch.untracked() {
    Some(n) => {
      let (came, speed) = notch_state(n, t - n.t0)
      (dclamp(n.x0 + came, 0.0, self.most()), n.total - came + d, speed)
    }
    None => {
      let x = self.stopped(t)
      if (d > 0.0 && x >= self.most()) || (d < 0.0 && x <= 0.0) {
        return false
      }
      (x, d, 0.0)
    }
  }
  (self.settle_off)()
  self.settle_off = fn() {  }
  self.x.set(x0)
  self.notch.set(Some({ x0, total, v0, t0: t, tau: wheel_ease_ms, end: self.ease_drawn_end(x0, total, v0), way: None, base: 0.0 }))
  self.scrolled_at(t)
  self.list_settles(v, t)
  true
}

///|
/// Sent to `to` from `t` (a page's list asked there: ListPlace), eased in from where it is as a wheel's notch is (ui's
/// Ctx::ease_list), what it was on by itself stopped there; at rest there at the ease's end.
fn Scroll::glide_to(self : Scroll, v : View, t : Double, to : Double, way? : (Double, (Double) -> Double)) -> Unit {
  let x = self.stopped(t)
  if to == x {
    return
  }
  (self.settle_off)()
  self.settle_off = fn() {  }
  let end = match way {
    Some((ms, _)) if ms > 0.0 => ms
    _ => self.ease_drawn_end(x, to - x, 0.0, most=dmax(self.most(), to))
  }
  self.notch.set(Some({ x0: x, total: to - x, v0: 0.0, t0: t, tau: wheel_ease_ms, end, way, base: 0.0 }))
  self.scrolled_at(t)
  self.list_settles(v, t)
}

///|
/// The glide it is on (Scroll::glide_to's, gliding on from it here) going on at `t` toward `to` instead (a page's list
/// gliding to its foot, its foot moved meanwhile: View::scrolls_window), `most` as far as it can go now: from where it
/// is then and as fast as it moves then, so nothing of it steps or stops there; eased in as quickly as it must to come
/// to rest at `to` and never past it (its time constant cut to what is left over its speed where its own would carry
/// it further: what is left then only falls), else as a glide is. Come to `to` or past it already (its end moved up
/// over where it is): at rest there. Not on one, nothing.
fn Scroll::glide_on(self : Scroll, v : View, t : Double, to : Double, most : Double) -> Unit {
  guard self.notch.untracked() is Some(n) else { return }
  let (came, speed) = notch_state(n, t - n.t0)
  let x = n.x0 + came
  let total = to - x
  (self.settle_off)()
  self.settle_off = fn() {  }
  if total <= 0.0 {
    self.notch.set(None)
    self.x.set(to)
    self.list_settles(v, t)
    return
  }
  // (on a way said: on that same way from where it is to the end come nearer, what is left of its curve taking it there)
  match n.way {
    Some((ms, curve)) if ms > 0.0 && t - n.t0 < n.end => {
      let base = curve(dclamp((t - n.t0) / ms, 0.0, 1.0))
      self.notch.set(Some({ ..n, x0: x, total, base }))
      self.list_settles(v, t)
      return
    }
    _ => ()
  }
  let tau = if speed > 0.0 && speed * wheel_ease_ms > total { total / speed } else { wheel_ease_ms }
  self.notch.set(Some({ x0: x, total, v0: speed, t0: t, tau, end: self.ease_drawn_end(x, total, speed, tau~, most~), way: None, base: 0.0 }))
  self.list_settles(v, t)
}

///|
/// What it does by itself, set out at `t`, told to what hosts the tree (Tree::on_glides) and at rest at its end, said
/// on the timeline: then where its fling ended, nothing past an end.
fn Scroll::list_settles(self : Scroll, v : View, t : Double) -> Unit {
  (self.settle_off)()
  self.settle_off = fn() {  }
  // (what it does by itself set going or stopped: drawn moved by it from now, Scroll::offset_said)
  self.offset_said()
  guard @signals.untracked(fn() { self.rest_now() }) is Some(rest) else { return }
  (v.tree.glides)(self.serial, fn() { self.glides_till() })
  ignore(t)
  v.tree.hand_at_end(rest)
  self.settle_off = v.at_moment(rest, fn() {
    self.settle_off = fn() {  }
    let flung = self.fling.untracked()
    let notch = self.notch.untracked()
    if flung is Some(_) || notch is Some(_) {
      self.scrolled_at(rest)
    }
    self.fling.set(None)
    self.past.set(None)
    self.notch.set(None)
    match (flung, notch) {
      (Some(f), _) => self.x.set(dclamp(f.end_x, 0.0, self.most()))
      (_, Some(n)) => self.x.set(dclamp(n.x0 + n.total, 0.0, self.most()))
      _ => ()
    }
  })
}

///|
/// How far it can go laid out anew as `most` at `t` (`laid`: all of it laid out as a change of what it holds left it,
/// however far that is: Scroll::grew_above): a fling under way down toward its foot, short of it still (or meeting it
/// at this very moment), meets it where it is now, worked out again from where it set out (rows below measured anew,
/// come or gone; what grew above, Scroll::grew_above), at rest then.
fn Scroll::foot_moved(self : Scroll, v : View, t : Double, most : Double, laid? : Bool = false) -> Unit {
  guard self.fling.untracked() is Some({ way: Some(w), .. } as f) &&
    f.v0 > 0.0 &&
    t <= f.end_t &&
    (laid || f.till != most) else {
    return
  }
  let density = w.px / dmax(w.h, 1.0)
  match list_planned(f.t0, f.x0, f.v0, w, w.same, density, most) {
    // (past its foot already as it is laid out now (what is under what is in sight less by more than it had left to
    // go): it meets it now, at its speed now)
    Some(g) if g.end_t < t => self.fling.set(Some(met_now(f, w, t, most, density)))
    Some(g) => self.fling.set(Some(g))
    None => {
      self.fling.set(None)
      self.x.set(f.x0)
    }
  }
  self.list_settles(v, t)
}

///|
/// Fling `f` on `w` meeting its end at `bound` at `t`, at its speed then: at rest there, what it brings past it going
/// back from then (as list_planned's meeting).
fn met_now(f : Fling, w : ListWay, t : Double, bound : Double, density : Double) -> Fling {
  let edge = if f.v0 > 0.0 { -1 } else { 1 }
  let at = w.speed(f.v0, t - f.t0)
  let hit = match w.feel {
    Desktop => None
    feel => {
      let p = BackPath::new()
      p.t0 = t
      if feel == Android {
        p.x0 = w.same
        p.v0 = (at * 1000.0 * density).round() * 13.0
        p.plan_edge(w.px)
      } else {
        p.v0 = at
        p.plan_rubber()
      }
      Some({ feel, edge, over: w.same, back: Some(p), h: w.h, px: w.px })
    }
  }
  { ..f, end_t: t, end_x: bound, till: bound, way: Some({ ..w, hit, }) }
}
