// How a list moves under a finger and after it, as each platform's own lists
// do:
//
// - the finger's velocity, on every platform, is Compose's VelocityTracker
//   (androidx.compose.ui.input.pointer.util, its default Lsq2 strategy): a
//   quadratic fitted by least squares to the last 100 ms of samples, cut at
//   a pause of more than 40 ms, its slope at the newest sample;
// - Android (scroll kind 2) flings as Compose's default fling does
//   (DefaultFlingBehavior over splineBasedDecay: the OverScroller spline,
//   ViewConfiguration's scroll friction 0.015, a physical deceleration from
//   the screen's density) and shows Android 12's stretch at the ends
//   (android.widget.EdgeEffect's stretch, and the way Compose's
//   AndroidEdgeEffectOverscrollEffect pulls, relaxes and absorbs it);
// - iOS (kind 1) decelerates as UIScrollView's normal rate (0.998 per ms) and
//   pulls past the ends on a rubber band that springs back;
// - the desktop (kind 0: macOS, Windows, a browser) keeps what it had: a
//   mouse drag coasts, slowing 0.997 per ms, and stops at the ends (a
//   trackpad's momentum comes from the system as wheel events).
//
// Each is said once as it sets out and is a function of the time from there ("Motion is data"):
// the curves, the springs and the stretch's mapping are @view's (list_motion.mbt), one for these lists and the window's
// tree's columns that scroll as a page's list does (@view.Scroll::list).

using @view {
  spline_fling,
  spline_at,
  fling_distance,
  stretch_amount,
  stretch_map,
  rubber,
  unrubber,
  rubber_at,
  ease_come,
  ease_state,
  ease_end,
  type BackPath,
}

///|
/// How far back the velocity tracker looks (ms; Compose's HorizonMilliseconds), and the pause after which it takes the
/// pointer to have stopped (AssumePointerMoveStoppedMilliseconds): the window's tree's (@view.Tracker).
pub let tracker_horizon_ms : Double = @view.tracker_horizon_ms

///|
pub let tracker_gap_ms : Double = @view.tracker_gap_ms

///|
/// How lists scroll here: 0 the desktop's, 1 iOS's, 2 Android's.
fn scroll_kind() -> Int {
  match h_feel() {
    1 => 1
    2 => 2
    _ => 0
  }
}

///|
/// How far a finger moves before it drags (logical pixels): Android's
/// ViewConfiguration touch slop, 8 dp; 6 elsewhere.
pub fn touch_slop() -> Double {
  if scroll_kind() == 2 {
    8.0
  } else {
    6.0
  }
}

///|
/// The fastest fling, in logical pixels per ms: Android's maximum fling
/// velocity, 8000 dp/s.
let max_fling : Double = 8.0

// ---------------------------------------------------------------------------
// Velocity

///|
/// The hand moved the list between frames (a finger dragging it, a wheel): what lays it out (Ctx::place_list) is told,
/// so that the next frame lays it out again, nothing built for it.
fn ListState::hand_moved(self : ListState) -> Unit {
  self.hand_said.set(self.hand_said.untracked() + 1)
}

///|
/// Ends the list's fling at once.
fn ListState::stop(self : ListState) -> Unit {
  self.vel = 0.0
  self.fling = 0
}

///|
/// A finger came down on the list: a fling stops, an overscroll that is
/// springing back is caught where it shows.
fn ListState::catch_up(self : ListState) -> Unit {
  self.stop()
  if self.over_state == 2 {
    if scroll_kind() == 1 {
      self.over = unrubber(self.over, self.vp_h)
    }
    self.over_state = 1
    self.over_v = 0.0
  }
}

///|
/// Whether the list moves on its own (a fling, an overscroll springing
/// back): a finger coming down then drags it at once, no slop.
fn ListState::moving(self : ListState) -> Bool {
  self.vel != 0.0 || self.over_state == 2
}

///|
/// Scrolls by `d` (positive: down the list) from `source` (1 a finger, 2 a
/// fling): what of it undoes an overscroll does that first (Compose's
/// applyToScroll, relaxing a stretch four times as fast in a fling).
fn Ctx::feed(self : Ctx, st : ListState, d : Double, source : Int) -> Unit {
  // (moved by the hand: what it shows moves for no row's cause, rows_steady.mbt)
  st.put_at = self.clock
  let mut d = d
  // an overscroll at the top is undone by scrolling down, at the bottom up
  let undoes = st.over > 0.0 &&
    ((st.over_edge > 0 && d > 0.0) || (st.over_edge < 0 && d < 0.0))
  if undoes {
    let kind = scroll_kind()
    if kind == 2 {
      let mult = if source == 2 { 4.0 } else { 1.0 }
      let h = dmax(st.vp_h, 1.0)
      let left = dmax(0.0, st.over - d.abs() * mult / h)
      let used = (st.over - left) * h / mult
      st.over = left
      if left > 0.0 {
        st.over_state = 1
        st.over_v = 0.0
        d = 0.0
      } else {
        st.over_state = 0
        st.over_edge = 0
        st.over_v = 0.0
        d = if d > 0.0 { d - used } else { d + used }
      }
    } else if kind == 1 && st.over_state == 1 {
      let used = dmin(d.abs(), st.over)
      st.over = st.over - used
      if st.over <= 0.0 {
        st.over = 0.0
        st.over_state = 0
        st.over_edge = 0
      }
      d = if d > 0.0 { d - used } else { d + used }
    }
  }
  st.pending = st.pending + d
  if source == 1 {
    self.scrolled(st)
    // a finger takes over from a glide to the end (Ctx::list_to_end), and lets go of a row followed
    st.glide = false
    st.follow_item = -1
    st.drag_pending = st.drag_pending + d
  }
}

///|
/// A finger pulled `by` past an end (edge 1 the top, -1 the bottom).
fn Ctx::pull(self : Ctx, st : ListState, edge : Int, by : Double) -> Unit {
  let kind = scroll_kind()
  // Compose leaves out less than half a pixel (rounding)
  if kind == 0 || by * self.scale <= 0.5 {
    return
  }
  if st.over_edge != edge {
    st.over = 0.0
  }
  st.over_edge = edge
  st.over_state = 1
  st.over_v = 0.0
  if kind == 2 {
    st.over = dmin(1.0, st.over + by / dmax(st.vp_h, 1.0))
  } else {
    st.over = st.over + by
  }
}

///|
/// A fling reached an end (edge 1 the top, -1 the bottom) at `vel` logical
/// pixels per ms: Android stretches with it (EdgeEffect.onAbsorb), iOS
/// bounces past the end and back.
fn Ctx::absorb(self : Ctx, st : ListState, edge : Int, vel : Double) -> Unit {
  let kind = scroll_kind()
  let speed = vel.abs()
  st.stop()
  if kind == 0 || speed == 0.0 {
    return
  }
  if st.over_edge != edge {
    st.over = 0.0
  }
  st.over_edge = edge
  // the fling ends here, now; what it took springs out and back from now
  st.last_scroll = self.clock
  let v = if kind == 2 {
    // pixels per second, times EdgeEffect's ON_ABSORB_VELOCITY_ADJUSTMENT
    (speed * 1000.0 * self.scale).round() * 13.0
  } else {
    speed
  }
  self.spring_back(st, v, self.clock)
}

///|
/// What is past an end springs back from where it is at `v` outward, from `t0` (-1: its next frame), said once as it
/// sets out (Ctx::moving: its path's end is when it is at rest).
fn Ctx::spring_back(self : Ctx, st : ListState, v : Double, t0 : Double) -> Unit {
  st.over_state = 2
  st.over_v = v
  let p = BackPath::new()
  p.x0 = st.over
  p.v0 = v
  st.back = p
  if t0 >= 0.0 {
    self.plan_back(st, t0)
  }
  self.moving(st.ease_mover, st as &Moving, what="a list's overscroll going back")
}

///|
/// The way back worked out, set out at `t0`.
fn Ctx::plan_back(self : Ctx, st : ListState, t0 : Double) -> Unit {
  let p = st.back
  p.t0 = t0
  if scroll_kind() == 2 {
    p.plan_edge(dmax(st.vp_h * self.scale, 1.0))
  } else {
    p.plan_rubber()
  }
}

///|
/// A fling's end, as it was said (the frames' clock): -1 none, +inf not started (it starts at its next frame).
fn ListState::fling_rest(self : ListState) -> Double {
  if self.fling == 0 || self.vel == 0.0 {
    return -1.0
  }
  if self.fling_t0 < 0.0 {
    return @double.infinity
  }
  self.fling_t0 + self.fling_length()
}

///|
/// How long a fling runs from its start (ms): Android's spline its duration in whole ms played (Compose's playtime);
/// iOS's deceleration and the desktop's coast until under 0.02 px per ms.
fn ListState::fling_length(self : ListState) -> Double {
  match self.fling {
    1 => self.fling_dur.ceil()
    2 => dmax(0.0, @dmath.ln(0.02 / self.fling_v.abs()) / @dmath.ln(@view.ios_decel))
    _ => dmax(0.0, @dmath.ln(0.02 / self.fling_v.abs()) / @dmath.ln(@view.coast_decel))
  }
}

///|
/// The overscroll's way back's end (the frames' clock): -1 none, +inf not started.
fn ListState::back_rest(self : ListState) -> Double {
  if self.over_state != 2 {
    -1.0
  } else if self.back.t0 < 0.0 {
    @double.infinity
  } else {
    self.back.rest
  }
}

///|
/// The finger left the list at `v` (logical pixels per ms, positive down
/// the list) at `at` (the input's time, or the moment the press was called off): it flings, or what it pulled past an
/// end goes back. What goes back sets out at `at`; a fling at its first frame on Android and iOS (Compose's playtime 0,
/// step_scroll), the desktop's coast at `at`.
fn Ctx::release(self : Ctx, st : ListState, v : Double, at : Double) -> Unit {
  st.held = false
  if scroll_logging() {
    let (dist, dur) = spline_fling(v * 1000.0 * self.scale, self.scale)
    h_log("FLING \{v} \{dist / self.scale} \{dur} scale=\{self.scale}")
  }
  let kind = scroll_kind()
  if kind == 2 {
    // Compose's applyToFling: a fling back from a stretch no further than
    // the stretch is all absorbed by it
    if st.over > 0.0 && st.over_state == 1 {
      let away = (st.over_edge > 0 && v > 0.0) || (st.over_edge < 0 && v < 0.0)
      if away &&
        fling_distance(v, self.scale) <= st.over * dmax(st.vp_h, 1.0) {
        self.spring_back(st, -(v.abs() * 1000.0 * self.scale).round() * 13.0, at)
        return
      }
    }
    // DefaultFlingBehavior flings above 1 pixel per second
    if v.abs() * 1000.0 * self.scale > 1.0 {
      let (dist, dur) = spline_fling(v * 1000.0 * self.scale, self.scale)
      st.fling = 1
      st.fling_v = v
      st.fling_t0 = -1.0
      st.fling_dist = dist / self.scale
      st.fling_dur = dur
      st.fling_done = 0.0
      st.fling_from = None
      st.vel = v
      self.moving(st.ease_mover, st as &Moving, what="a list's fling")
    } else if st.over_state == 1 {
      // no fling: a stretch left as it is goes back from now, as it was let go (or called off)
      self.spring_back(st, 0.0, at)
    }
    // a stretch left as it is under a fling goes back once the fling is over (step)
  } else if kind == 1 {
    if st.over_state == 1 && st.over > 0.0 {
      st.over = rubber(st.over, st.vp_h)
      // moving away from the content is outward; from now, as it was let go (or called off)
      self.spring_back(st, if st.over_edge > 0 { -v } else { v }, at)
    } else if v.abs() >= 0.02 {
      st.fling = 2
      st.fling_v = v
      st.fling_t0 = -1.0
      st.fling_done = 0.0
      st.fling_from = None
      st.vel = v
      self.moving(st.ease_mover, st as &Moving, what="a list's fling")
    }
  } else if v.abs() >= 0.02 {
    // the desktop's coast sets out as the finger lets go
    st.fling = 3
    st.fling_v = v
    st.fling_t0 = at
    st.fling_done = 0.0
    st.fling_from = None
    st.vel = v
    self.moving(st.ease_mover, st as &Moving, what="a list's coast")
  }
}

///|
/// A frame of the list's own motion: its fling, and its overscroll going back, where each is at this frame's time by
/// what was said as it set out (@view's list_motion.mbt).
fn Ctx::step_scroll(self : Ctx, st : ListState) -> Unit {
  if st.vel != 0.0 && st.fling != 0 {
    // Android's and iOS's start at their first frame (Compose's playtime 0); the desktop's coast as it was let go
    if st.fling_t0 < 0.0 {
      st.fling_t0 = self.clock
    }
    let end = st.fling_t0 + st.fling_length()
    let t = dmin(self.now_before(end), end) - st.fling_t0
    let sign = if st.fling_v < 0.0 { -1.0 } else { 1.0 }
    let (pos, vel) = match st.fling {
      1 => {
        // Compose's decay animation: in whole ms played
        let (share, vc) = spline_at(t.floor(), st.fling_dur)
        (sign * st.fling_dist * share, sign * vc * st.fling_dist / dmax(st.fling_dur, 1.0))
      }
      2 => {
        // UIScrollView's normal deceleration
        let k = @view.ios_decel
        (st.fling_v * (@dmath.pow(k, t) - 1.0) / @dmath.ln(k), st.fling_v * @dmath.pow(k, t))
      }
      _ => {
        // the desktop's coast
        let k = @view.coast_decel
        (st.fling_v * (@dmath.pow(k, t) - 1.0) / @dmath.ln(k), st.fling_v * @dmath.pow(k, t))
      }
    }
    let d = pos - st.fling_done
    // where it is, put from where it set out as far on as it has come, as long as nothing else moved it since and no end
    // took any of it: each frame's step added on, frames at another rate added up to a rounding apart (a fling's rest
    // a bit off at 60 against at 120 frames a second, let_go_test, MBUI_TEST_FPS)
    let here = (st.anchor, st.anchor_off, st.pending)
    let from = match st.fling_from {
      Some(f) if here == (st.left.0, st.left.1, st.left.2) => f
      _ => (st.anchor, st.anchor_off, st.pending - st.fling_done)
    }
    st.fling_from = Some(from)
    st.fling_done = pos
    if st.over == 0.0 && st.over_state == 0 {
      st.put_at = self.clock
      st.anchor = from.0
      st.anchor_off = from.1
      st.pending = from.2 + pos
    } else {
      st.fling_from = None
      self.feed(st, d, 2)
    }
    if self.clock >= end {
      st.stop()
      // its scroll bar fades from the fling's end
      st.last_scroll = end
    } else {
      st.vel = if vel == 0.0 { sign * 1.0e-9 } else { vel }
    }
  }
  // a stretch held by nothing (the finger gone, its fling over) goes back
  if st.over_state == 1 && !st.held && st.vel == 0.0 {
    if scroll_kind() == 1 {
      st.over = rubber(st.over, st.vp_h)
    }
    self.spring_back(st, 0.0, self.clock)
  }
  if st.over_state == 2 {
    if st.back.t0 < 0.0 {
      self.plan_back(st, self.clock)
    }
    let p = st.back
    if self.clock >= p.rest {
      st.over = 0.0
      st.over_v = 0.0
      st.over_state = 0
      st.over_edge = 0
      st.last_scroll = p.rest
    } else if scroll_kind() == 2 {
      let (x, v) = p.edge_now(dmax(st.vp_h * self.scale, 1.0), self.now())
      st.over = x
      st.over_v = v
    } else {
      let (x, v) = rubber_at(p.x0, p.v0, self.now() - p.t0)
      st.over = x
      st.over_v = v
    }
  }
}

///|
/// How far the list's rows show moved by its overscroll (iOS's rubber
/// band; Android's stretch moves nothing, it is drawn stretched).
fn ListState::over_offset(self : ListState) -> Double {
  if self.over_edge == 0 || self.over <= 0.0 || scroll_kind() != 1 {
    return 0.0
  }
  let shown = if self.over_state == 1 {
    rubber(self.over, self.vp_h)
  } else {
    self.over
  }
  shown * self.over_edge.to_double()
}

///|
/// The list's rows (instances `from` on, drawn in the view from `top`, `h`
/// high, clipped to `c0`-`c1`) as Android's stretch shows them.
fn Ctx::stretch_rows(
  self : Ctx,
  st : ListState,
  from : Int,
  top : Double,
  h : Double,
  c0 : Double,
  c1 : Double,
) -> Unit {
  if scroll_kind() != 2 || st.over <= 0.0 || st.over_edge == 0 {
    return
  }
  self.stretch_insts(from, self.ninst, stretch_amount(st.over) * st.over_edge.to_double(), top, h, c0, c1)
}

///|
/// Instances `from` to `till` of the frame (what a list holds, drawn in it from `top`, `h` high, cut to `c0`-`c1`) as
/// Android's stretch `ov` shows them (from the top positive: @view.stretch_map), what cuts them inside the list and what
/// they fade towards with them: an old view's list's (Ctx::stretch_rows) and a column of the window's tree's that
/// scrolls as a page's list (View::stretches).
fn Ctx::stretch_insts(
  self : Ctx,
  from : Int,
  till : Int,
  ov : Double,
  top : Double,
  h : Double,
  c0 : Double,
  c1 : Double,
) -> Unit {
  if ov == 0.0 || h <= 0.0 {
    return
  }
  let map = fn(y : Double) { top + h * stretch_map(ov, (y - top) / h) }
  let a = self.inst
  for k in from..<till {
    let b = k * inst_size
    let y0 = map(a[b + 1])
    let y1 = map(a[b + 1] + a[b + 3])
    a[b + 1] = y0
    a[b + 3] = y1 - y0
    // turned (a turning mark's spokes): where it turns about goes where the stretch puts it, as its rect does (draw.mbt's
    // moves): left where it was, the mark turned about a point the stretch moved its rect away from, drawn off its row
    if a[b + 32] != 0.0 {
      a[b + 34] = map(a[b + 34])
    }
    // clips inside the list's stretch with it, no further than the list's
    if a[b + 17] > c0 + 0.001 {
      a[b + 17] = dclamp(map(a[b + 17]), c0, c1)
    }
    if a[b + 19] < c1 - 0.001 {
      a[b + 19] = dclamp(map(a[b + 19]), c0, c1)
    }
    // (and what it fades towards)
    if a[b + 53] > 0.0 {
      let (f0, f1) = (map(a[b + 52]), map(a[b + 52] + a[b + 53]))
      a[b + 52] = f0
      a[b + 53] = f1 - f0
    }
    if a[b + 55] > 0.0 {
      let (f0, f1) = (map(a[b + 54] - a[b + 55]), map(a[b + 54]))
      a[b + 54] = f1
      a[b + 55] = f1 - f0
    }
  }
}

///|
/// The list's scroll position: how far its top is from the top of its first
/// row (rows not measured yet counted at their estimate).
fn ListState::offset(self : ListState) -> Double {
  self.anchor_off + self.above(imin(self.anchor, self.count))
}

///|
/// MBUI_SCROLL_LOG=1 logs each touch (TOUCH kind ms x y, and when it was
/// handled), each fling
/// (FLING velocity distance duration) and, each frame something moves, the
/// first list's position (SCROLL ms offset stretch velocity): for comparing
/// how it moves with how the platform's lists do.
let scroll_log : Ref[Int] = { val: -1 }

///|
fn scroll_logging() -> Bool {
  if scroll_log.val < 0 {
    scroll_log.val = if @hostapi.env("MBUI_SCROLL_LOG") == "1" { 1 } else { 0 }
  }
  scroll_log.val == 1
}

///|
let last_logged : Ref[Double] = { val: -1.0e9 }

///|
fn Ctx::log_scroll(self : Ctx) -> Unit {
  match self.lists.get(self.bench_list) {
    Some(st) => {
      let off = st.offset()
      let moving = st.vel != 0.0 || st.over_state != 0
      if moving || off != last_logged.val {
        last_logged.val = off
        let stretch = st.over * st.over_edge.to_double()
        h_log("SCROLL \{self.clock} \{off} \{stretch} \{st.vel}")
      }
    }
    None => ()
  }
}

///|
/// How fast a finger goes, from its samples (each where it was and when: its events' own moments), as a list's fling
/// reads it (Tracker: Compose's VelocityTracker's least squares): for what works out its own fling from a finger's events
/// (a node of the window's tree's: @view.Drag), none of the frames between.
pub struct Velocity {
  priv x : @view.Tracker
  priv y : @view.Tracker
}

///|
pub fn Velocity::new() -> Velocity {
  { x: @view.Tracker::new(), y: @view.Tracker::new() }
}

///|
/// None of the samples before: a finger anew.
pub fn Velocity::reset(self : Velocity) -> Unit {
  self.x.reset()
  self.y.reset()
}

///|
/// The finger at (x, y) at `t` (ms).
pub fn Velocity::add(self : Velocity, t : Double, x : Double, y : Double) -> Unit {
  self.x.add(t, x)
  self.y.add(t, y)
}

///|
/// The finger lifted at (x, y) at `t`: a sample only where it says a place anew (Tracker::up).
pub fn Velocity::up(self : Velocity, t : Double, x : Double, y : Double) -> Unit {
  self.x.up(t, x)
  self.y.up(t, y)
}

///|
/// How fast it goes as of its newest sample, across and down (points per ms), held to what a fling takes.
pub fn Velocity::get(self : Velocity) -> (Double, Double) {
  (dclamp(self.x.velocity(), -max_fling, max_fling), dclamp(self.y.velocity(), -max_fling, max_fling))
}

///|
/// How fast it goes as of a moment `t` (an event's: a move, a lift), across and down (points per ms), held to what a
/// fling takes: none where it stood still longer than tracker_gap_ms first, nor where its own last moves do not bear
/// it out (Tracker::velocity_at).
pub fn Velocity::get_at(self : Velocity, t : Double) -> (Double, Double) {
  (dclamp(self.x.velocity_at(t), -max_fling, max_fling), dclamp(self.y.velocity_at(t), -max_fling, max_fling))
}
