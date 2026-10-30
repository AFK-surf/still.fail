// The phone's bottom bar (ember apps/android shared/ui/Bar.kt BottomBar, shared/Places.kt PlaceBar): a floating capsule
// of the places of one bar, 22 in from the screen's sides and its foot (the system's bars are the host's: the view is
// laid out inside them); a ball over the place shown that travels on a spring stretched by its speed and goes where a
// finger takes it; the page's primary action in a notch cut out of the bar's top (令, a new chat, on the chats'
// pages); with more than one bar, the glass grows upward into a panel of the other bars, one row each, open once a
// finger on the bar is drawn 24 over it and closed once back under 16, and a bar chosen there is the bar. Every
// motion is a number on a spring (or a timed glide) stepped a frame at a time. Shown on a place's top page with
// nothing over it; gone down out of the way (300 ms) under a page pushed, back up (380 ms) as it comes back.
//
// All of it is frosted glass of one capture (Bar.kt: Haze, the pages its one source): the bar (its notch cut out of
// it, a box's `notch_*`), the action in the notch and the ball frost the pages under them, not each other
// (@ui.Glass::sharing). Where glass is drawn solid, the bar is its ground (Glass.kt `floating`: --raised at 72% over
// the paper). What moves is only drawn so (src/motion's rule): the bar going down and coming back, the action growing
// and shrinking, its icon swapping, a bar chosen in the panel sliding down into the bar's place are looks over where
// they are laid out, and what leaves is drawn only.

// ── geometry (Bar.kt, dp) ──────────────────────────────────────────────

///|
let bar_track : Double = 56.0

///|
let bar_inset : Double = 6.0

///|
let ball_rest : Double = bar_track - bar_inset * 2.0

///|
let ball_size : Double = bar_track + 12.0

///|
let c0 : Double = bar_inset + ball_rest / 2.0

///|
let drop : Double = 56.0

///|
let notch_gap : Double = 6.0

///|
let lift : Double = 4.0

///|
let fillet : Double = 8.0

///|
let bar_row : Double = 56.0

///|
let over : Double = 20.0

///|
let rad : Double = bar_track / 2.0

///|
let slot_px : Double = 90.0

///|
let lean : Double = 0.25


///|
let opens : Double = 24.0

///|
let closes : Double = 16.0

///|
/// How long a finger held still on the bar takes the ball (its lens over it), as one sliding does.
let bar_hold_ms : Double = 200.0

///|
/// What a place's top page keeps clear at its foot for the bar (Places.kt BAR_ROOM: the bar, its 22 from the foot, a
/// little air, and the action standing 32 over it).
let bar_room : Double = 56.0 + 22.0 + 16.0 + 32.0

///|
/// The chats' family of places, whose pages have 令 in the notch.
// kept across runs: a table, never written
let chat_family : Array[String] = ["chats", "archive"]

///|
/// The places' middles on a bar `w` wide holding `n` with the notch `k` open (Bar.kt barCentres).
fn bar_centres(w : Double, k : Double, n : Int) -> Array[Double] {
  let closed = (w - 2.0 * c0) / 3.0
  let open = w / 2.0 - (drop / 2.0 + notch_gap) - 6.0 - ball_rest / 2.0 - c0
  let sp = closed + (open - closed) * k
  if n >= 4 {
    [c0, c0 + sp, w - c0 - sp, w - c0]
  } else if n == 3 {
    let mid = w / 2.0 - c0 - (w / 2.0 - c0 - sp) * k
    [c0, c0 + mid, w - c0, w - c0]
  } else if n == 2 {
    [c0, w - c0, w - c0, w - c0]
  } else {
    [c0, c0, c0, c0]
  }
}

///|
fn nearest(cs : Array[Double], n : Int, x : Double) -> Int {
  let mut best = 0
  for j in 0..<imin(n, cs.length()) {
    if (cs[j] - x).abs() < (cs[best] - x).abs() {
      best = j
    }
  }
  best
}

///|
fn imin(a : Int, b : Int) -> Int {
  if a < b {
    a
  } else {
    b
  }
}

// ── motion ─────────────────────────────────────────────────────────────
// Motion as data (mbui's motion_data.mbt): each number is said once, as it sets out (where to, by what, from when),
// and where it is at a frame is a function of that frame's time; what moves says so itself (Ctx::moving), so the
// frames come until it is at rest and none after. The bar reads where its numbers are once a frame (BarModel::sample).

///|
/// The bar's springs said to move as one (Ctx::set_out): handed each frame's time while any of them moves, the frame
/// they are at rest too (Moving::sample), so the bar reads where they are from it, not the clock.
priv struct BarClock {
  mover : @ui.Mover
  /// the time last handed to it, or of the frame it last set out in
  mut now : Double
}

///|
let bar_clock : BarClock = { mover: @ui.Mover::new(), now: 0.0 }

///|
impl @ui.Moving for BarClock with rest_at(self, now, frame) {
  ignore(self)
  ignore(now)
  ignore(frame)
  bar_springs_end()
}

///|
/// When the bar's springs are all at rest (the frames' clock, ms; before now: they are).
fn bar_springs_end() -> Double {
  let mut e = -1.0
  for s in [bar.o, bar.k, bar.held, bar.ball_x, bar.ball_y] {
    e = dmax(e, s.end())
  }
  e
}

///|
impl @ui.Moving for BarClock with sample(self, now) {
  self.now = now
}

///|
/// A spring of the bar sets out: when (this frame's time; told between frames, the last frame's, where the bar last
/// was), the bar's springs said to move from it on.
fn bar_set_out() -> Double {
  let at = @ui.current().set_out(bar_clock.mover, bar_clock as &@ui.Moving, what="the bar's springs")
  if at != @double.infinity {
    bar_clock.now = at
  }
  bar_clock.now
}

///|
/// How far the bar goes down out of the way (points): coming back (a page it shows on), a Move as long as that is far.
let bar_drop : Double = 120.0

///|
/// How long the bar takes to go (a page pushed over it): shorter than its coming, mostly gone by half of the page's push.
let bar_hide_ms : Double = 250.0

///|
/// The lens: a capsule over the ball's place, as large as it is drawn.
// kept across runs: a value (no field of it changes)
let lens_box : @ui.Style = @ui.css("w=Full h=Full radius=Full")

///|
/// How much larger than the ball its lens is, held (liquid glass over the places, iOS 26's tab bar's).
let lens_grow : Double = 0.18

///|
/// How long the ball takes to fade in or out, and to grow back or shrink.
let ball_fade_ms : Double = 200.0

///|
let ball_grow_ms : Double = 250.0

///|
/// How long the notch's icon takes to swap for another.
pub let icon_swap_ms : Double = 300.0

///|
/// One number on a spring (react-spring's tension and friction, mass 1; Bar.kt BarSpring), its way solved
/// (@ui.SpringPath): `x`, `v` and `to` where it is, how fast it goes and where to, as of this frame (sample).
priv struct Spr {
  mut path : @ui.SpringPath?
  /// riding something that moves itself (the ball on a bar chosen coming down: Ride), its way worked out as it set out
  mut ride : Ride?
  mut x : Double
  mut v : Double
  mut to : Double
  mut tension : Double
  mut friction : Double
  /// at rest within it
  rest : Double
  /// what it is, as Tester::moving says it (`bar/o`: the panel, `bar/k`: the notch, `bar/held`: the ball held, the
  /// ball's `bar/ball-x`, `bar/ball-y`), beside the bar's glides (`bar/vis`)
  what : String
}

///|
fn spr(start : Double, tension : Double, friction : Double, what : String, rest? : Double = 0.001) -> Spr {
  { path: None, ride: None, x: start, v: 0.0, to: start, tension, friction, rest, what }
}

///|
fn Spr::moving(self : Spr) -> Bool {
  self.v != 0.0 || self.x != self.to
}

///|
/// Where it is at `now` (once a frame).
fn Spr::sample(self : Spr, now : Double) -> Unit {
  match self.ride {
    Some(r) => {
      let (x, v) = r.at(now)
      self.x = x
      self.v = v
      if now >= r.end {
        // there: at rest where it rode to
        self.ride = None
        self.put(r.to)
      }
      return
    }
    None => ()
  }
  match self.path {
    Some(p) => {
      let (x, v) = p.at(now)
      self.x = x
      self.v = v
    }
    None => ()
  }
}

///|
/// Sent to `to` now by `tension` and `friction`, from where it is, as fast as it goes; nothing new when it goes there
/// so already.
fn Spr::go(self : Spr, to : Double, tension : Double, friction : Double) -> Unit {
  let same = tension == self.tension && friction == self.friction
  let now = bar_set_out()
  // riding: where it rides to by the ride's spring is nothing new; anything else sets out from where the ride has it
  let rode = match self.ride {
    Some(r) => {
      if same && r.to == to {
        return
      }
      self.ride = None
      r.stop()
      Some(r.at(now))
    }
    None => None
  }
  match self.path {
    Some(p) if rode is None && same && p.target() == to => return
    _ => ()
  }
  let (x, v) = match (rode, self.path) {
    (Some(xv), _) => xv
    (None, Some(p)) => p.at(now)
    (None, None) => (self.x, self.v)
  }
  let p = match self.path {
    Some(p) if same && rode is None => p
    old => {
      // (a spring of another stiffness from here: the old one's way is over)
      match old {
        Some(o) => o.put(x)
        None => ()
      }
      let p = @ui.SpringPath::new(x, k=tension, c=friction, rest=self.rest)
      self.path = Some(p)
      p
    }
  }
  p.go(now, to, v~, what=self.what)
  self.x = x
  self.v = v
  self.to = to
  self.tension = tension
  self.friction = friction
}

///|
/// When it is at rest (the frames' clock, ms; before now, or -1: it is).
fn Spr::end(self : Spr) -> Double {
  match (self.ride, self.path) {
    (Some(r), _) => r.end
    (None, Some(p)) => p.end()
    (None, None) => -1.0
  }
}

///|
/// Where it is at `t` (ms, the frames' clock), by what it was told so far: for what rides on it (Ride).
fn Spr::value_at(self : Spr, t : Double) -> Double {
  match self.path {
    Some(p) => p.value(t)
    None => self.x
  }
}

///|
/// There at once, at rest.
fn Spr::put(self : Spr, x : Double) -> Unit {
  match self.ride {
    Some(r) => r.stop()
    None => ()
  }
  self.ride = None
  match self.path {
    Some(p) => p.put(x)
    None => ()
  }
  self.x = x
  self.v = 0.0
  self.to = x
}

///|
/// As at the start.
fn Spr::back(self : Spr, x : Double, tension : Double, friction : Double) -> Unit {
  self.path = None
  self.ride = None
  self.x = x
  self.v = 0.0
  self.to = x
  self.tension = tension
  self.friction = friction
}

///|
/// A spring riding something that moves by itself (Bar.kt ride: the ball on a bar chosen as it comes down, sent each
/// frame to where its place is then), its way worked out once as it sets out, from the ways of what it rides on (the
/// panel's and the notch's springs, known to their end): sent at each step of `ride_step_ms` to where that is then, at
/// rest at `to` from `end` on. So it is the same however often frames come, and its end is said as it sets out
/// (Ctx::moving), not anew each frame.
priv struct Ride {
  /// each leg: when it starts, from where and how fast, and towards what
  legs : Array[(Double, Double, Double, Double)]
  /// the spring: stiffness, damping ratio
  k : Double
  ratio : Double
  to : Double
  end : Double
  /// what it was worked out from (RideFrom::same)
  from : RideFrom
  mut stopped : Bool
}

///|
/// What a ride rides on, as it set out: the bar chosen and its place, the window, and the ways of the springs it rides
/// on (where they go, when they are at rest).
priv struct RideFrom {
  swap : Swap
  j : Int
  w : Double
  row_top : Double
  o_to : Double
  o_end : Double
  k_to : Double
  k_end : Double
}

///|
/// The step a ride is sent at (a frame's, at 60 a second: as the ball was sent each frame).
let ride_step_ms : Double = 16.0

///|
/// A ride from `x` (at `v` a second) at `t0`, by stiffness `k` and damping `c`, after `anchor` (where it is sent at a
/// time) until `still` (when what it rides on is at rest; after it, where it is sent stays), at rest within `rest`.
fn Ride::new(
  x : Double,
  v : Double,
  t0 : Double,
  k : Double,
  c : Double,
  rest : Double,
  anchor : (Double) -> Double,
  still : Double,
  from : RideFrom,
) -> Ride {
  let ratio = c / (2.0 * k.sqrt())
  let legs = []
  let mut t = t0
  let mut x = x
  let mut v = v
  let mut to = anchor(t0)
  legs.push((t, x, v, to))
  while t < still {
    let next = t + ride_step_ms
    let (d, vel) = @motion.spring_at(ratio, k, x - to, v, (next - t) / 1000.0)
    x = to + d
    v = vel
    t = next
    to = anchor(dmin(t, still))
    legs.push((t, x, v, to))
  }
  let end = t + @motion.spring_duration(ratio, k, x - to, v, rest)
  { legs, k, ratio, to, end, from, stopped: false }
}

///|
/// Where it is at `t`, and how fast it goes (a second).
fn Ride::at(self : Ride, t : Double) -> (Double, Double) {
  if t >= self.end {
    return (self.to, 0.0)
  }
  // the leg it is on: the last one started by `t`
  let mut i = self.legs.length() - 1
  while i > 0 && self.legs[i].0 > t {
    i = i - 1
  }
  let (t0, x0, v0, to) = self.legs[i]
  let (d, v) = @motion.spring_at(self.ratio, self.k, x0 - to, v0, dmax(0.0, t - t0) / 1000.0)
  (to + d, v)
}

///|
/// Ended before its end (sent elsewhere, put): it no longer moves.
fn Ride::stop(self : Ride) -> Unit {
  self.stopped = true
}

///|
impl @ui.Moving for Ride with rest_at(self, now, frame) {
  ignore(now)
  ignore(frame)
  if self.stopped {
    -1.0
  } else {
    self.end
  }
}

///|
/// Whether a ride worked out from `a` rides on what `b` says now.
fn RideFrom::same(a : RideFrom, b : RideFrom) -> Bool {
  physical_equal(a.swap, b.swap) &&
  a.j == b.j &&
  a.w == b.w &&
  a.row_top == b.row_top &&
  a.o_to == b.o_to &&
  a.o_end == b.o_end &&
  a.k_to == b.k_to &&
  a.k_end == b.k_end
}

///|
/// `self` set riding by `anchor` until `still` (Ride::new), from where it is now, unless it rides so already; said once
/// as it sets out (Ctx::moving).
fn Spr::ride_on(self : Spr, tension : Double, anchor : (Double) -> Double, still : Double, from : RideFrom) -> Unit {
  match self.ride {
    Some(r) if r.from.same(from) && r.k == tension => return
    _ => ()
  }
  let now = bar_set_out()
  let (x, v) = match (self.ride, self.path) {
    (Some(r), _) => r.at(now)
    (None, Some(p)) => p.at(now)
    (None, None) => (self.x, self.v)
  }
  match self.ride {
    Some(r) => r.stop()
    None => ()
  }
  // (its own spring's way is over: it rides from here)
  match self.path {
    Some(p) => p.put(x)
    None => ()
  }
  let friction = ball_damping(tension)
  let r = Ride::new(x, v, now, tension, friction, self.rest, anchor, dmax(now, still), from)
  self.ride = Some(r)
  self.x = x
  self.v = v
  self.to = r.to
  self.tension = tension
  self.friction = friction
  let c = @ui.current()
  c.moving(@ui.Mover::new(), r as &@ui.Moving, what="the ball's ride")
}

///|
/// One number gliding to where it is sent over a time on a curve (Bar.kt Glide): an @motion.Anim by `key`, `value` and
/// `target` where it is and where to, as of this frame (sample).
priv struct Glide {
  key : String
  mut value : Double
  mut target : Double
}

///|
fn glide(key : String, start : Double) -> Glide {
  { key, value: start, target: start }
}

///|
fn Glide::anim(self : Glide) -> @motion.Anim {
  @motion.anim(@ui.current(), "bar/" + self.key, self.value, global=true)
}

///|
/// Sent to `target` over `ms` on `ease`; nothing new when it is going there.
fn Glide::go(self : Glide, target : Double, ms : Double, ease : @ui.Ease) -> Unit {
  self.go_by(target, @motion.tween(ms, ease~))
}

///|
/// Sent to `target` by `spec`; nothing new when it is going there.
fn Glide::go_by(self : Glide, target : Double, spec : @motion.Spec) -> Unit {
  self.anim().follow(target, spec)
  self.target = target
}

///|
/// Where it is this frame.
fn Glide::sample(self : Glide) -> Unit {
  let a = self.anim()
  self.value = a.get()
  self.target = a.target()
}

///|
/// There at once, still.
fn Glide::snap(self : Glide, v : Double) -> Unit {
  self.anim().snap(v)
  self.value = v
  self.target = v
}

///|
/// A bar chosen in the panel, sliding down into the bar's place (Bar.kt Swap): which (`i`), its row in the panel
/// (`n`), how open the panel was (`from`), the place tapped in it; the bars as they were (`sets`, `cur`), which the
/// stack sliding down is laid out by; the rows' fade and offset then and how lit each place was, which it starts
/// from.
priv struct Swap {
  i : Int
  n : Int
  from : Double
  key : String?
  sets : Array[Array[String]]
  cur : Int
  alpha : Double
  drop : Double
  lit : Map[String, Double]
}

///|
/// How far a bar chosen has come down: 0 as the panel was, 1 landed.
fn Swap::t(self : Swap, o : Double) -> Double {
  dclamp(1.0 - o / self.from, 0.0, 1.0)
}

///|
/// The rows' look as the panel opens (Bar.kt rowsAlpha, rowsShift): they come in over 0.35 to 1, a little low, then up
/// with its overshoot.
fn rows_alpha(o : Double) -> Double {
  dclamp((o - 0.35) / 0.65, 0.0, 1.0)
}

///|
fn rows_shift(o : Double, reach : Double) -> Double {
  (1.0 - dmin(1.0, o)) * 14.0 - dmax(0.0, o - 1.0) * reach
}

///|
/// The chosen bar's places' middles and their height (in the panel's frame) as it comes down (Bar.kt swapAt): from
/// its row in the panel to exactly where the bar's places are drawn as the notch is (`k_now`).
fn swap_at(s : Swap, o : Double, w : Double, k_now : Double, row_top : Double) -> (Array[Double], Double) {
  let into = s.sets[s.i]
  let t = s.t(o)
  let from = bar_centres(w, 0.0, into.length())
  let row_mid = over + s.n.to_double() * bar_row + bar_row / 2.0
  let bar_mid = row_top + bar_track / 2.0
  if t <= 0.0 {
    return (from, row_mid)
  }
  let to = bar_centres(w, k_now, into.length())
  if t >= 1.0 {
    return (to, bar_mid)
  }
  (from.mapi(fn(j, x) { x + (to[j] - x) * t }), row_mid + (bar_mid - row_mid) * t)
}

///|
/// What the bar keeps between frames (Bar.kt BarModel, BallMotion).
priv struct BarModel {
  /// the panel of the other bars open (or opening, or the finger's)
  mode : @signals.Signal[Bool]
  /// how open the panel is (0 the bar, 1 the panel); the notch (1 open); the ball held
  o : Spr
  k : Spr
  held : Spr
  /// the bar shown, the ball shown and its size
  vis : Glide
  ball_alpha : Glide
  ball_scale : Glide
  /// each place drawn ("bar:<place>", "row:<place>"): how lit
  tints : Map[String, Glide]
  /// the ball: where across (stiff as the way is short) and down, on springs damped as the web's (ZETA 0.635)
  ball_x : Spr
  ball_y : Spr
  /// how far the ball went to the place shown last (its spring as stiff as the way is short)
  mut trip : Double
  mut active_was : String
  /// a finger: where it has the ball (-1 none), its height once the panel is its own
  mut drag : Double
  mut drag_y : Double
  /// those as this frame's first build found them: what it draws by in every build of the frame (a press handled in
  /// it is drawn from the next)
  mut drag_drawn : Double
  mut drag_y_drawn : Double
  mut holds : Bool
  mut from_open : Bool
  mut open : Bool
  mut y0 : Double
  mut o0 : Double
  mut was_down : Bool
  /// first drawn: everything where it goes at once
  mut placed : Bool
  mut width : Double
  /// a bar chosen sliding down into the bar's place; a finger that went down meanwhile (the finger's once it lands)
  mut swap : Swap?
  mut waits : Bool
  /// the notch's icon going as another swaps in ("" none), how far the swap is (0 to 1)
  mut icon_was : String
  icon_swap : Glide
  /// the frame it was last told in (Ctx::frame_number): told once a frame, by the first of its builds in it; and what
  /// it was told then (shown, notched): told again in the frame where a later build says otherwise
  mut told : Int
  mut told_as : (Bool, Bool)
}

///|
/// The ball's springs: down and up 300; across as stiff as it is told; damped as the web's (ZETA 0.635).
let ball_down : Double = 300.0

///|
fn ball_damping(tension : Double) -> Double {
  2.0 * 0.635 * tension.sqrt()
}

///|
/// The ball at rest within this (points).
let ball_rest_within : Double = 0.01

///|
let bar : BarModel = {
  mode: @signals.signal(false, same=fn(a, b) { a == b }),
  o: spr(0.0, 260.0, 17.0, "bar/o"),
  k: spr(1.0, 300.0, 30.0, "bar/k"),
  held: spr(0.0, 420.0, 16.0, "bar/held"),
  vis: glide("vis", 0.0),
  ball_alpha: glide("ball-alpha", 1.0),
  ball_scale: glide("ball-scale", 1.0),
  tints: {},
  ball_x: spr(0.0, 300.0, ball_damping(300.0), "bar/ball-x", rest=ball_rest_within),
  ball_y: spr(0.0, ball_down, ball_damping(ball_down), "bar/ball-y", rest=ball_rest_within),
  trip: slot_px,
  active_was: "",
  drag: -1.0,
  drag_y: -1.0,
  drag_drawn: -1.0,
  drag_y_drawn: -1.0,
  holds: false,
  from_open: false,
  open: false,
  y0: 0.0,
  o0: 0.0,
  was_down: false,
  placed: false,
  width: 0.0,
  swap: None,
  waits: false,
  icon_was: "",
  told: -1,
  told_as: (false, false),
  icon_swap: glide("icon-swap", 1.0),
}

///|
/// As at the start (tests).
fn bar_reset() -> Unit {
  let back_glide = fn(g : Glide, to : Double) {
    g.value = to
    g.target = to
  }
  bar.mode.set(false)
  bar.o.back(0.0, 260.0, 17.0)
  bar.k.back(1.0, 300.0, 30.0)
  bar.held.back(0.0, 420.0, 16.0)
  back_glide(bar.vis, 0.0)
  back_glide(bar.ball_alpha, 1.0)
  back_glide(bar.ball_scale, 1.0)
  bar.tints.clear()
  bar.ball_x.back(0.0, 300.0, ball_damping(300.0))
  bar.ball_y.back(0.0, ball_down, ball_damping(ball_down))
  bar.trip = slot_px
  bar.active_was = ""
  bar.drag = -1.0
  bar.drag_y = -1.0
  bar.drag_drawn = -1.0
  bar.drag_y_drawn = -1.0
  bar.holds = false
  bar.from_open = false
  bar.open = false
  bar.y0 = 0.0
  bar.o0 = 0.0
  bar.placed = false
  bar.was_down = false
  bar.width = 0.0
  bar.swap = None
  bar.waits = false
  bar.icon_was = ""
  back_glide(bar.icon_swap, 1.0)
  m_face.val = ""
  bar_clock.now = 0.0
  bar.told = -1
  bar.told_as = (false, false)
}

///|
fn BarModel::open_panel(self : BarModel, open : Bool) -> Unit {
  self.mode.set(open)
  if open {
    self.o.go(1.0, 260.0, 17.0)
  } else {
    self.o.go(0.0, 320.0, 26.0)
  }
}

///|
/// The notch as drawn: as its place has it, closed as far as the panel is drawn up (fully by half open).
fn BarModel::k_now(self : BarModel) -> Double {
  self.k.x * (1.0 - dclamp(2.0 * self.o.x, 0.0, 1.0))
}

///|
/// Where everything is this frame, by what it was told before (Bar.kt: told as it is composed, it moves from there).
fn BarModel::sample(self : BarModel) -> Unit {
  let now = bar_clock.now
  for s in [self.o, self.k, self.held, self.ball_x, self.ball_y] {
    s.sample(now)
  }
  for g in [self.vis, self.ball_alpha, self.ball_scale, self.icon_swap] {
    g.sample()
  }
  for _, g in self.tints {
    g.sample()
  }
  // a bar chosen: landed (its panel's spring at the rest it declared as it set out, closed), the stack is where the
  // bar is, drawn as the bar will be; it goes in this same frame
  match self.swap {
    Some(_) if now >= self.o.end() && self.o.to <= 0.0 => self.swap = None
    _ => ()
  }
}

///|
/// When all of the bar is at rest (the frames' clock, ms; before now: it is), as its springs and glides said as they
/// set out. Only for a test's end, before its assert_idle (idle is after all it said has ended); never a point a test
/// waits for midway: there a test asks the end of the one path it looks at, not of the whole bar.
fn BarModel::rest(self : BarModel) -> Double {
  let mut e = -1.0
  for s in [self.o, self.k, self.held, self.ball_x, self.ball_y] {
    e = dmax(e, s.end())
  }
  let gs = [self.vis, self.ball_alpha, self.ball_scale, self.icon_swap]
  for _, g in self.tints {
    gs.push(g)
  }
  for g in gs {
    e = dmax(e, g.anim().ends_at())
  }
  e
}

///|
/// When the bottom bar is at rest (BarModel::rest): for a test of the app over its pages (src/sfreplay), as for this
/// package's own, only at a test's end or where a page is pushed, never a point waited for midway.
pub fn bar_rest() -> Double {
  bar.rest()
}

///|
/// When the bar chosen in the panel has landed (the frames' clock, ms): the end of the panel's own spring as it closes
/// under it; -1 when none is landing. Until then a finger does not take the panel (a bar landing lands untouched): what
/// a test runs to before it draws the panel up again.
pub fn bar_landed() -> Double {
  match bar.swap {
    Some(_) => bar.o.end()
    None => -1.0
  }
}

///|
/// Everything where it is going, at once (the first frame; reduced motion).
fn BarModel::jump(self : BarModel) -> Unit {
  for s in [self.o, self.k, self.held, self.ball_x, self.ball_y] {
    s.put(s.to)
  }
  for g in [self.vis, self.ball_alpha, self.ball_scale, self.icon_swap] {
    g.snap(g.target)
  }
  for _, g in self.tints {
    g.snap(g.target)
  }
  self.swap = None
}

// ── what the bar is told ───────────────────────────────────────────────

///|
/// The notch's action's icon, as last shown (kept as it closes).
let m_face : Ref[String] = { val: "" }

///|
/// A place's name (the bar's words for what a screen reader says, the place's page's title).
fn place_label(place : String) -> String {
  tr("android-misc.bar.place." + place)
}

///|
/// The stations' glyph's counts as the bar last read them (Station's icon), None before.
let bar_glyph : Ref[@sf.GlyphCounts?] = Ref(None)

///|
/// What Station's place says to a screen reader as the bar last read it (Places.kt stationsSaid: the stations in the
/// core's words, what is wrong with them), "" before or when the core said nothing of them.
let bar_stations_said : Ref[String] = Ref("")

///|
/// The place a page is the top of (none: it is not a place's).
fn place_of(page : Page) -> String? {
  match page {
    Home => Some("chats")
    Files => Some("files")
    Place(p) => Some(p)
    _ => None
  }
}

// ── drawing ────────────────────────────────────────────────────────────

///|
/// A box at (x, y) in its parent, `w` × `h`, laid over what is there; its index.
fn at(
  c : @ui.Ctx,
  x : Double,
  y : Double,
  w : Double,
  h : Double,
  clip? : Bool = false,
  opacity? : Double = 1.0,
  bg? : Int64 = 0L,
  radius? : Double = 0.0,
  border? : Double = 0.0,
  border_color? : Int64 = 0L,
  glass? : @ui.Glass,
  notch_y? : Double = 0.0,
  notch_r? : Double = 0.0,
  notch_fillet? : Double = 0.0,
  id? : Int = 0,
  body? : () -> Unit = fn() {  },
) -> Int {
  let mut i = -1
  c.layer(fn() {
    i = c.box(
      w=Px(w),
      h=Px(h),
      tx=x,
      ty=y,
      clip~,
      opacity~,
      bg~,
      radius~,
      border~,
      border_color~,
      glass?,
      notch_y~,
      notch_r~,
      notch_fillet~,
      id~,
      body,
    )
  })
  |> ignore
  i
}

///|
/// The notch cut into the glass's top (Bar.kt outline, notch): a circle of radius `r` about the top's middle, `cy`
/// below the edge (above it as it opens), met by the edge through fillets; where it meets the edge on the left and
/// right of a glass `w` wide; None while it is closed (the circle not through the edge).
fn notch_lips(w : Double, cy : Double, r : Double) -> (Double, Double)? {
  if r <= 0.5 {
    return None
  }
  let dy = fillet - cy
  let reach = (r + fillet) * (r + fillet) - dy * dy
  if cy + r <= 0.5 || reach <= 0.0 {
    return None
  }
  let xf = reach.sqrt()
  Some((w / 2.0 - xf, w / 2.0 + xf))
}

///|
/// The glass `w` wide from `top` to `bottom` (in the panel's frame) with the notch cut into its top (Bar.kt: the
/// glass clipped to its outline, its lit rim, `glass_bottom_bar`; solid, its ground), and the notch's own edge lit
/// (white at 70%, 22% in the dark, 1 wide across the outline, under the glass's top).
fn bar_glass(c : @ui.Ctx, w : Double, top : Double, bottom : Double, cy : Double, r : Double) -> Unit {
  let t = @sf.theme()
  let h = bottom - top
  let corner = dmin(rad, h / 2.0)
  match notch_lips(w, cy, r) {
    // (over what runs under it: the scroll bar there keeps clear of it)
    None => c.floats_over(at(c, 0.0, top, w, h, radius=corner, glass=@sf.glass_bottom_bar()))
    Some((l, rr)) => {
      let glass = at(
        c,
        0.0,
        top,
        w,
        h,
        radius=corner,
        glass=@sf.glass_bottom_bar(),
        notch_y=cy,
        notch_r=r,
        notch_fillet=fillet,
      )
      c.floats_over(glass)
      // the notch's outline alone: the glass's outline grown by half the line, its line inside that, seen between
      // the lips and under the glass's top; its foot below the clip (else its bottom edge was a white line under the
      // bar's middle, between the lips)
      at(c, l, top + 0.5, rr - l, h, clip=true, body=fn() {
        at(
          c,
          -l - 0.5,
          -1.0,
          w + 1.0,
          h + 4.0,
          radius=corner + 0.5,
          border=1.0,
          border_color=@sf.alpha(0xFFFFFFFFL, if t.dark { 0.22 } else { 0.7 }),
          notch_y=cy + 0.5,
          notch_r=r - 0.5,
          notch_fillet=fillet + 0.5,
        )
        |> ignore
      })
      |> ignore
    }
  }
}

///|
/// The bar's shadow (Bar.kt): a blurred rounded rectangle 4 lower, outside the glass's outline only (clipOutPath: the
/// glass frosts nothing of it), none above its top (none in the notch or over the edge the action stands on), and
/// coming in down its rounded ends, from nothing at its top to whole a radius down (no step where it begins).
fn bar_shadow(c : @ui.Ctx, w : Double, top : Double, bottom : Double) -> Unit {
  let t = @sf.theme()
  let h = bottom - top
  let color = @sf.alpha(0x000000FFL, if t.dark { 0.45 } else { 0.16 })
  let r = dmin(rad, h / 2.0)
  // (the room round it its blur reaches into)
  let room = 40.0
  let cast = fn(from : Double) {
    at(c, room, -from, w, h, body=fn() {
      c.box(
        w=Px(w),
        h=Px(h),
        radius=r,
        // (Bar.kt: BlurMaskFilter of a CSS deviation of 6)
        shadow=6.0,
        shadow_color=color,
        shadow_y=bar_shadow_y,
        shadow_out=true,
        fn() {  },
      )
      |> ignore
    })
    |> ignore
  }
  // its rounded ends' top, in bands, each as far in as the fade is there (Bar.kt's LinearGradient over the radius)
  for k in 0..<bar_shadow_fade {
    let y0 = r * k.to_double() / bar_shadow_fade.to_double()
    let bh = r / bar_shadow_fade.to_double()
    at(c, -room, top + y0, w + 2.0 * room, bh, clip=true, opacity=(k.to_double() + 0.5) / bar_shadow_fade.to_double(), body=fn() {
      cast(y0)
    })
    |> ignore
  }
  // below that, whole
  at(c, -room, top + r, w + 2.0 * room, h - r + room, clip=true, body=fn() { cast(r) }) |> ignore
}

///|
/// 令's ground: the accent at 86% (Bar.kt: accent.copy(alpha = 0.86f) over the page).
let action_ink : Double = 0.86

///|
/// How far below the glass its shadow falls (Bar.kt: translate 4).
let bar_shadow_y : Double = 4.0

///|
/// The bands its fade down the rounded ends is drawn in.
let bar_shadow_fade : Int = 8

///|
/// A place's look: its icon (28) in `idle`, `lit` over it as far as it is lit (`v`: two pictures, one each colour,
/// rather than one more of each colour on its way between them), its dot at the icon's top right.
fn place_face(c : @ui.Ctx, place : String, idle : Int64, lit : Int64, v : Double, dot : Int64) -> Unit {
  let name = place_icon(place)
  let icon = fn(color : Int64) {
    match bar_glyph.val {
      Some(g) if place == "stations" => @sf.station_glyph(c, g, 28.0, color, @sf.theme().p.red) |> ignore
      _ => @sf.icon(c, name, size=28.0, color~) |> ignore
    }
  }
  if v < 0.999 {
    icon(idle)
  }
  if v > 0.001 {
    c.layer(align=ACenter, fn() {
      c.box(h=Fill(1.0), justify=JCenter, opacity=v, fn() {
        icon(lit)
      })
      |> ignore
    })
    |> ignore
  }
  if dot != 0L {
    c.layer(align=ACenter, fn() {
      c.box(h=Fill(1.0), justify=JCenter, fn() {
        c.box(w=Px(7.0), h=Px(7.0), radius=3.5, bg=dot, tx=13.5, ty=-12.5, fn() {  }) |> ignore
      })
      |> ignore
    })
    |> ignore
  }
}

///|
/// How long a place takes to light up or go dim.
let tint_ms : Double = 300.0

///|
/// How lit place `id` is now, sent toward `on` (300 ms, CSS's ease); it is as it is when it comes.
fn tint_of(id : String, on : Bool) -> Double {
  let g = match bar.tints.get(id) {
    Some(g) => g
    None => {
      // (as it is when it comes, whatever it was before it went)
      let g = glide("tint/" + id, if on { 1.0 } else { 0.0 })
      g.snap(g.value)
      bar.tints[id] = g
      g
    }
  }
  g.go(if on { 1.0 } else { 0.0 }, tint_ms, Out)
  g.value
}

///|
/// The bottom bar over the pages of `w` (Places.kt PlaceBar, Bar.kt BottomBar). `shown`: on a place's top page with
/// nothing over it; `active`: the place shown (its top page's).
fn bottom_bar(c : @ui.Ctx, src : Source, ws : Workspace, active : String?, shown : Bool) -> Unit {
  // a part of its own, kept as its nodes (mbui's Ctx::kept_as_nodes: what floats over the pages said again with it):
  // what its springs read of the clock as they go builds it again each frame, not the pages under it. Its key what it
  // is laid out by besides what it reads: the window, the navigation bar's room, the ground, the place shown and
  // whether it shows
  let t = @sf.theme()
  let key = "\{c.width} \{c.height} \{nav_foot()} \{t.p.bg} \{t.dark} \{ws.id} \{active} \{shown}"
  c.kept_as_nodes(
    c.id("bar/kept"),
    key,
    fn() {
      bar_drawn(c, src, ws, active, shown)
      // where its springs are, read as it was built: built again as they are told and each frame while they go
      c.shows_motion(bar_clock.mover, bar_springs_end() > c.moment())
    },
    read_out=true,
  )
}

///|
/// The bar as it is this frame (bottom_bar's part).
fn bar_drawn(c : @ui.Ctx, src : Source, ws : Workspace, active : String?, shown : Bool) -> Unit {
  let t = @sf.theme()
  let (sets, cur) = bars_in(src, ws.id)
  let items = sets[cur]
  let others : Array[Int] = []
  for i in 0..<sets.length() {
    if i != cur {
      others.push(i)
    }
  }
  let rows = if others.length() > 1 { others.length() } else { 1 }
  let panel = bar_track + rows.to_double() * bar_row + over
  let row_top = panel - bar_track
  let reach = row_top - over
  let bar_mid = row_top + bar_track / 2.0
  let w = c.width - 44.0
  let slot = (w - 2.0 * c0) / 3.0
  // the page's primary action in the notch (Places.kt PlaceBar): 令 on the chats' pages, 文件's ＋ while it can lend
  // a folder (Files.kt), none on the others yet
  // (Station's ＋ adds a station, Profile's a profile, 连接's a connect: what the settings' page of the place says)
  let place_add = match active {
    Some("connects") => {
      let core = settings_core(src, ws)
      match @sfpages.connects_add(src, core, @settings.here_of(core, ws.id, ws.name)) {
        Some(run) => Some(run)
        None => None
      }
    }
    Some(a) => @settings.place_action(settings_core(src, ws), @settings.here_of(settings_core(src, ws), ws.id, ws.name), a)
    None => None
  }
  let action = match active {
    Some(a) if chat_family.contains(a) => "ling"
    Some("files") if files_can_lend(src, ws) => "plus"
    _ if place_add is Some(_) => "plus"
    _ => ""
  }
  let notched = action != ""
  // the dots: a station in trouble (red)
  let chats = (src.topic)("chats", { "scope": Json::string(ws.id), "mine": Json::boolean(false) })
  let dots : Map[String, Int64] = Map([])
  match field(chats.value, "trouble") {
    Some(Object(_)) => dots["stations"] = t.p.red
    _ => ()
  }
  // the stations at a glance in Station's place (Places.kt PlaceIcon: StationGlyph), and in words
  let (glyph, said) = stations_at_glance(src, ws.id)
  bar_glyph.val = Some(glyph)
  bar_stations_said.val = said
  let m = bar
  // told once a frame, by its first build in it: built again in the same frame (a frame's passes, or a check
  // building it whole), it draws what that build told, a ride set out from where it is not set out again from there;
  // unless what it is told is otherwise by then (a page pushed after its first build in the frame: hidden as of it,
  // not as of the next frame that happens to build it)
  let tell = m.told != c.frame_number() || m.told_as != (shown, notched)
  m.told = c.frame_number()
  m.told_as = (shown, notched)
  // the frame's motion, by what the bar was told before this frame (Bar.kt: told as it is composed, it moves from
  // there; a bar chosen is drawn as it was the frame it is chosen, and slides from the next)
  if tell {
    m.sample()
  }
  // told each frame: shown or not, the notch as the place has it
  if tell {
    m.vis.go_by(if shown { 1.0 } else { 0.0 }, if shown {
      @motion.move(points=bar_drop)
    } else {
      @motion.tween(bar_hide_ms, ease=Leave)
    })
  }
  if tell && !shown {
    if m.mode.get() {
      m.open_panel(false)
    }
    m.drag = -1.0
    m.drag_y = -1.0
    m.holds = false
  }
  if tell {
    m.drag_drawn = m.drag
    m.drag_y_drawn = m.drag_y
  }
  let drag = m.drag_drawn
  let drag_y = m.drag_y_drawn
  if tell {
    m.k.go(if notched { 1.0 } else { 0.0 }, 300.0, 30.0)
  }
  let ai = match active {
    Some(a) => items.search(a).unwrap_or(-1)
    None => -1
  }
  let final_cs = bar_centres(w, if notched && !m.mode.get() { 1.0 } else { 0.0 }, items.length())
  // the finger's place, and the place a let-go would choose: the ball keeps to it, leaning toward the finger
  let cand : (Double, Double, Int, String)? = if drag >= 0.0 {
    let x = drag
    if drag_y >= 0.0 && drag_y < row_top - 4.0 && others.length() > 0 {
      let n = dclamp(((drag_y - over) / bar_row).floor(), 0.0, (others.length() - 1).to_double()).to_int()
      let set = sets[others[n]]
      let cs = bar_centres(w, 0.0, set.length())
      let j = nearest(cs, set.length(), x)
      Some((cs[j], over + n.to_double() * bar_row + bar_row / 2.0, others[n], set[j]))
    } else if items.length() > 0 {
      let j = imin(items.length() - 1, nearest(final_cs, 4, x))
      Some((final_cs[j], bar_mid, cur, items[j]))
    } else {
      None
    }
  } else {
    None
  }
  let (goal_x, goal_y) = match cand {
    Some((cx, cy, _, _)) =>
      (cx + (drag - cx) * lean, cy + ((if drag_y >= 0.0 { drag_y } else { bar_mid }) - cy) * lean)
    None => (final_cs[if ai < 0 { 0 } else { ai }], bar_mid)
  }
  let sliding = drag >= 0.0
  let active_key = active.unwrap_or("")
  if tell && !sliding && active_key != m.active_was {
    m.active_was = active_key
    m.trip = dmax(8.0, (goal_x - m.ball_x.x).abs())
  }
  let tension = if sliding { 300.0 } else { dclamp(300.0 * slot_px / m.trip, 90.0, 700.0) }
  // riding a bar chosen: after the place tapped in it as it comes down (Bar.kt ride)
  let ride = match m.swap {
    Some({ key: Some(key), .. } as s) =>
      match s.sets[s.i].search(key) {
        Some(j) => Some((s, j))
        None => None
      }
    _ => None
  }
  if tell && m.width != w {
    // a new width (turned): there at once
    m.width = w
    m.ball_x.put(goal_x)
  }
  match ride {
    _ if !tell => ()
    Some((s, j)) => {
      // where its place is at a time, by the panel's and the notch's ways (as swap_at has it each frame): ridden
      // after on the ball's springs, worked out once as it sets out (Ride), again only when those ways change
      let from = {
        swap: s,
        j,
        w,
        row_top,
        o_to: m.o.to,
        o_end: m.o.end(),
        k_to: m.k.to,
        k_end: m.k.end(),
      }
      let still = dmax(m.o.end(), m.k.end())
      let o = m.o
      let k = m.k
      let place_at = fn(t : Double) {
        let ot = o.value_at(t)
        let (xs, y) = swap_at(s, ot, w, k.value_at(t) * (1.0 - dclamp(2.0 * ot, 0.0, 1.0)), row_top)
        (xs[j], y + s.drop * (1.0 - s.t(ot)))
      }
      m.ball_x.ride_on(300.0, fn(t) { place_at(t).0 }, still, from)
      m.ball_y.ride_on(ball_down, fn(t) { place_at(t).1 }, still, from)
    }
    None => {
      m.ball_x.go(goal_x, tension, ball_damping(tension))
      m.ball_y.go(goal_y, ball_down, ball_damping(ball_down))
    }
  }
  if tell {
    m.held.go(if sliding { 1.0 } else { 0.0 }, 420.0, 16.0)
  }
  let ball_shown = ai >= 0 ||
    sliding ||
    (match m.swap {
      Some({ key: Some(_), .. }) => true
      _ => false
    })
  if tell {
    m.ball_alpha.go(if ball_shown { 1.0 } else { 0.0 }, ball_fade_ms, Out)
    m.ball_scale.go(if ball_shown { 1.0 } else { 0.6 }, ball_grow_ms, Out)
  }
  // first drawn (or under reduced motion): everything where it goes, at once
  if tell && (!m.placed || c.still()) {
    m.placed = true
    m.jump()
  }
  // for the motion log (scripts/motionplot.py): the bar going and coming, the panel (a bar chosen landing)
  if m.vis.value != m.vis.target {
    @motion.log_frame(c, "bar/vis", "value=\{m.vis.value} to=\{m.vis.target}")
  }
  if m.swap is Some(_) {
    @motion.log_frame(c, "bar/swap", "value=\{m.o.x} to=\{m.o.to}")
  } else if m.o.x != m.o.to {
    @motion.log_frame(c, "bar/panel", "value=\{m.o.x} to=\{m.o.to}")
  }
  if m.vis.value <= 0.0 && !shown {
    return
  }
  let under = match cand {
    Some((_, _, set, key)) => if set == cur { key } else { "" }
    None => active_key
  }
  let k_now = m.k_now()
  let clip_top = dmax(0.0, over + reach * (1.0 - m.o.x))
  let notch_r = (drop / 2.0 + notch_gap) * k_now
  let notch_y = -lift * k_now
  let idle = if t.dark { 0xD1D5DBFFL } else { 0x6B7280FFL }
  let lit = if t.dark { 0xFFFFFFFFL } else { 0x111827FFL }
  // the panel's frame in the window: 22 over the navigation bar (Bar.kt: padding(bottom = 22.dp + navBottom))
  let foot = 22.0 + nav_foot()
  let fx = 22.0
  let fy = c.height - foot - panel
  // the panel open: a press anywhere else closes it (and does nothing else)
  if shown && m.mode.get() {
    let catcher = c.id("bar/catch")
    match c.drag_of(catcher) {
      Some(d) => if d.down || d.take_tap() { m.open_panel(false) }
      None => ()
    }
    c.layer(fn() {
      c.drag_area(catcher, axis=Hold, w=Fill(1.0), h=Fill(1.0), fn() {  }) |> ignore
    })
    |> ignore
    c.on_back(fn() { m.open_panel(false) })
  }
  // the gestures on the glass
  let glass_id = c.id("bar/glass")
  // (what the places say takes their presses: the glass, while it takes them, as its gestures are read)
  let presses = if shown { glass_id } else { 0 }
  if shown {
    match c.drag_of(glass_id) {
      Some(d) => bar_gesture(c, src, ws, d, sets, cur, others, active, fx, fy, w, panel, final_cs)
      None => ()
    }
  }
  let action_id = c.id("bar/action")
  if c.clicked(action_id) && shown && k_now > 0.9 {
    match action {
      "ling" => new_chat(c)
      "plus" =>
        match place_add {
          // (what it puts up opened by the notch)
          Some(run) => run(Of(action_id))
          None => files_lend(c, src, ws)
        }
      _ => ()
    }
  }
  // the notch's icon: another one swaps in as the notch stays open (a short scale and fade); closed, at once
  let swap_icon = show_icon(c, action, k_now > 0.001)
  let mut holder = -1
  c.layer(fn() {
    c.spacer()
    holder = c.box(w=Px(w), h=Px(panel), tx=22.0, ty=-foot, fn() {
      bar_shadow(c, w, clip_top, panel)
      // under the glass, 令's own disc: the glass frosts it as it frosts the pages (Bar.kt: the action a haze source),
      // its warmth round the notch, fading down from it; the disc itself under 令, as large and as grown
      if k_now > 0.001 {
        let under = at(
          c,
          w / 2.0 - drop / 2.0,
          row_top - lift - drop / 2.0,
          drop,
          drop,
          radius=drop / 2.0,
          bg=@sf.over(t.p.bg, @sf.alpha(t.p.accent, action_ink)),
        )
        if k_now < 1.0 {
          c.look(under, @ui.look(alpha=dmin(1.0, k_now * 3.0), scale=dmax(0.001, k_now), dy=lift * (1.0 - k_now)))
        }
      }
      bar_glass(c, w, clip_top, panel, notch_y, notch_r)
      // the glass takes the gestures (its places' taps are read where they land)
      at(c, 0.0, clip_top, w, panel - clip_top, body=fn() {
        c.drag_area(glass_id, axis=Free, w=Fill(1.0), h=Fill(1.0), fn() {  }) |> ignore
      })
      |> ignore
      // 令 in the notch: accent glass, growing out of the bar as the notch opens about its middle, which comes up to
      // the bar's edge (laid out as it is open, drawn so); closing, it keeps the last action's icon as it shrinks
      if k_now > 0.001 {
        let face = m_face.val
        let disc = at(
          c,
          w / 2.0 - drop / 2.0,
          row_top - lift - drop / 2.0,
          drop,
          drop,
          radius=drop / 2.0,
          glass=@sf.glass_action().sharing(),
          id=if k_now > 0.9 { action_id } else { 0 },
          body=fn() {
            // from one action to another with another icon (令 and a ＋): the icon swaps, the circle stays
            let v = swap_icon
            let css : @ui.Ease = Out
            let arrive : @ui.Ease = Out
            if bar.icon_was != "" {
              let p = css.at(dclamp(v * 300.0 / 120.0, 0.0, 1.0))
              let old = action_icon(c, bar.icon_was)
              c.look(old, @ui.look(alpha=1.0 - p, scale=1.0 - 0.5 * p))
              @motion.leaving(c, old, false)
            }
            if face != "" {
              let ms = v * 300.0
              let now = action_icon(c, face)
              if ms < 300.0 {
                c.look(
                  now,
                  @ui.look(
                    alpha=css.at(dclamp((ms - 60.0) / 180.0, 0.0, 1.0)),
                    scale=0.5 + 0.5 * arrive.at(dclamp((ms - 60.0) / 240.0, 0.0, 1.0)),
                  ),
                )
              }
            }
          },
        )
        if k_now < 1.0 {
          c.look(
            disc,
            @ui.look(alpha=dmin(1.0, k_now * 3.0), scale=dmax(0.001, k_now), dy=lift * (1.0 - k_now)),
          )
        }
      }
      // the ball, under the places, stretched by its speed toward where it goes; its glass frosts what the bar's does
      let scale = (1.0 + 0.06 * m.held.x) * m.ball_scale.value
      let v = if (goal_x - m.ball_x.x).abs() < 0.5 { 0.0 } else { m.ball_x.v / 60.0 }
      let (stretch, lower) = @kit.speed_stretch(v)
      let bw = ball_size + stretch
      let bh = ball_size - lower
      let left = m.ball_x.x - ball_size / 2.0 - (if v < 0.0 { stretch } else { 0.0 })
      let bcx = left + bw / 2.0
      let sw = bw * scale
      let sh = bh * scale
      if m.ball_alpha.value > 0.0 {
        let ball = at(c, bcx - sw / 2.0, m.ball_y.x - sh / 2.0, sw, sh, body=fn() {
          c.box(
            w=Fill(1.0),
            h=Fill(1.0),
            radius=dmin(sw, sh) / 2.0,
            glass=@sf.glass_bar_ball().sharing(),
            shadow=4.0,
            shadow_y=1.0,
            shadow_color=if t.dark { 0x00000059L } else { 0x37352D33L },
            fn() {  },
          )
          |> ignore
        })
        // (held, the lens over the places takes its place: it fades as the lens comes)
        let lensed = if c.glass_solid() { 0.0 } else { dmin(1.0, m.held.x) }
        let ball_shows = m.ball_alpha.value * (1.0 - lensed)
        if ball_shows < 1.0 {
          c.look(ball, @ui.look(alpha=ball_shows))
        }
      }
      match m.swap {
        None => {
          // the other bars, above this one, as the panel opens
          if m.mode.get() || m.o.x > 0.001 {
            let alpha = rows_alpha(m.o.x)
            let shift = rows_shift(m.o.x, reach)
            for n, i in others {
              let set = sets[i]
              let cs = bar_centres(w, 0.0, set.length())
              for j, key in set {
                let on = match cand {
                  Some((_, _, cs_set, ck)) => cs_set == i && ck == key
                  None => active_key == key
                }
                let tint = tint_of("row:" + key, on)
                let row_y = over + n.to_double() * bar_row + bar_row / 2.0
                // (a row the glass is not under yet, the panel coming up: pressed through nothing)
                let row_presses = if row_y + 24.0 > clip_top { presses } else { 0 }
                let row = place_at(c, key, cs[j], row_y, slot, idle, lit, tint, dots, row_presses)
                c.look(row, @ui.look(alpha~, dy=shift))
              }
            }
          }
          // the bar's places, over the ball
          let now_cs = bar_centres(w, k_now, items.length())
          for j, key in items {
            let tint = tint_of("bar:" + key, under == key)
            place_at(c, key, now_cs[j], bar_mid, slot, idle, lit, tint, dots, presses) |> ignore
          }
        }
        Some(_) => ()
      }
      // the ball in the finger: a lens of liquid glass over the places as it is held (as it grows), what is under its
      // rim bent; gone as it is let go. Where glass is solid there is nothing to bend: the ball alone.
      if m.held.x > 0.01 && m.ball_alpha.value > 0.0 && !c.glass_solid() {
        let grow = 1.0 + lens_grow * m.held.x
        let lw = sw * grow
        let lh = sh * grow
        let lens = at(c, bcx - lw / 2.0, m.ball_y.x - lh / 2.0, lw, lh, body=fn() {
          c.box(style=lens_box, glass=@sf.glass_lens(), fn() {  }) |> ignore
        })
        c.look(lens, @ui.look(alpha=dmin(1.0, m.held.x) * m.ball_alpha.value))
      }
      match m.swap {
        None => ()
        Some(s) => {
          // a bar being chosen: the stack of bars slides down inside the closing glass, the chosen one into the
          // bar's place, what is not chosen cut off by the glass's edge (Bar.kt). It starts as the rows and the bar
          // were drawn (the rows' fade and offset, each place as lit as it was) and comes to the bar's look as it
          // lands. The chosen bar is the bar's places, laid out where they are and drawn coming down; the rest
          // leaves, drawn only.
          let t = s.t(m.o.x)
          let (xs, y) = swap_at(s, m.o.x, w, k_now, row_top)
          let row_mid = over + s.n.to_double() * bar_row + bar_row / 2.0
          let shift = y - row_mid
          let alpha = s.alpha + (1.0 - s.alpha) * t
          let row_drop = s.drop * (1.0 - t)
          let was = fn(id : String) { s.lit.get(id).unwrap_or(0.0) }
          let window = at(c, 0.0, clip_top, w, panel - clip_top, clip=true, body=fn() {
            let laid_others : Array[Int] = []
            for i in 0..<s.sets.length() {
              if i != s.cur {
                laid_others.push(i)
              }
            }
            for n, i in laid_others {
              if i != s.i {
                let set = s.sets[i]
                let cs = bar_centres(w, 0.0, set.length())
                for j, key in set {
                  let row = place_at(
                    c,
                    key,
                    cs[j],
                    over + n.to_double() * bar_row + bar_row / 2.0 - clip_top,
                    slot,
                    idle,
                    lit,
                    was("row:" + key),
                    dots,
                    presses,
                  )
                  c.look(row, @ui.look(alpha~, dy=shift + row_drop))
                }
              }
            }
            let laid_items = s.sets[s.cur]
            let laid_cs = bar_centres(w, k_now, laid_items.length())
            for j, key in laid_items {
              let p = place_at(c, key, laid_cs[j], bar_mid - clip_top, slot, idle, lit, was("bar:" + key), dots, presses)
              c.look(p, @ui.look(dy=shift))
            }
          })
          @motion.leaving(c, window, false)
          // the chosen bar, inside the closing glass too
          at(c, 0.0, clip_top, w, panel - clip_top, clip=true, body=fn() {
            let now_cs = bar_centres(w, k_now, items.length())
            for j, key in items {
              // landed, as the bar's places are drawn the next frame: lit as it comes, when it is the place shown
              bar.tints.remove("bar:" + key)
              let end = if active_key == key { 1.0 } else { 0.0 }
              let from = was("row:" + key)
              let tint = if t >= 1.0 {
                end
              } else if t <= 0.0 {
                from
              } else {
                from + (end - from) * t
              }
              let p = place_at(c, key, now_cs[j], bar_mid - clip_top, slot, idle, lit, tint, dots, presses)
              if j < xs.length() {
                c.look(p, @ui.look(alpha~, dx=xs[j] - now_cs[j], dy=y + row_drop - bar_mid))
              }
            }
          })
          |> ignore
        }
      }
    })
  })
  |> ignore
  // going down out of the way and back up: drawn so, laid out where it rests; going, it takes nothing
  // (worked out as each frame is painted, on its way: a frame of its looks alone draws it where it is then)
  if m.vis.value < 1.0 || m.vis.target < 1.0 {
    let vis = m.vis.anim()
    c.look_by(holder, fn() {
      let v = vis.get()
      @ui.look(alpha=v, dy=(1.0 - v) * bar_drop)
    })
  }
  @motion.leaving(c, holder, shown)
}

///|
/// The notch's icon this frame: `next` swapping in for the one shown (Bar.kt showIcon: 300 ms on the bar's clock,
/// linear; the one going out by 120 ms, the one coming in from 60 ms); at once when none was shown or the notch is
/// closed (nothing to see). How far the swap is (0 to 1).
fn show_icon(c : @ui.Ctx, next : String, out : Bool) -> Double {
  let sw = bar.icon_swap
  if next != "" && next != m_face.val {
    if m_face.val == "" || !out {
      m_face.val = next
      bar.icon_was = ""
      sw.snap(1.0)
    } else {
      bar.icon_was = m_face.val
      m_face.val = next
      sw.snap(0.0)
      sw.go(1.0, icon_swap_ms, Linear)
    }
  }
  sw.sample()
  if sw.value != sw.target {
    @motion.log_frame(c, "bar/icon-swap", "value=\{sw.value} to=1")
  } else {
    bar.icon_was = ""
  }
  sw.value
}

///|
/// An action's icon in the middle of the notch's disc (令 40, any other 30), in white; its index.
fn action_icon(c : @ui.Ctx, face : String) -> Int {
  let mut i = -1
  c.layer(fn() {
    c.box(w=Fill(1.0), h=Fill(1.0), align=ACenter, justify=JCenter, fn() {
      i = @sf.icon(c, face, size=if face == "ling" { 40.0 } else { 30.0 }, color=0xFFFFFFFFL)
    })
    |> ignore
  })
  |> ignore
  i
}

///|
/// A place of the bar or the panel, its middle at (`x`, `y`) (in its parent): its slot (48 high), its face as lit as
/// `tint`; its index.
fn place_at(
  c : @ui.Ctx,
  key : String,
  x : Double,
  y : Double,
  slot : Double,
  idle : Int64,
  lit : Int64,
  tint : Double,
  dots : Map[String, Int64],
  glass : Int,
) -> Int {
  at(c, x - slot / 2.0, y - 24.0, slot, 48.0, body=fn() {
    // pressed through the glass over it, which reads where a press lands (bar_gesture): while it takes them
    if glass != 0 {
      c.presses_to(glass)
    }
    let face = c.box(w=Fill(1.0), h=Fill(1.0), align=ACenter, justify=JCenter, fn() {
      place_face(c, key, idle, lit, tint, dots.get(key).unwrap_or(0L))
    })
    // what a screen reader says of it (Bar.kt Place: its label; Station's, the stations in words)
    c.semantics(face, Tab, label=if key == "stations" && bar_stations_said.val != "" { bar_stations_said.val } else { place_label(key) })
  })
}

///|
/// What a finger does on the glass (Bar.kt BarModel down, move, up, letGo, tap): a stroke any way takes the ball; up,
/// with more than one bar, the panel; a tap picks a place (on the bar), or a bar and its place (in the open panel).
fn bar_gesture(
  c : @ui.Ctx,
  src : Source,
  ws : Workspace,
  d : @ui.Drag,
  sets : Array[Array[String]],
  cur : Int,
  others : Array[Int],
  active : String?,
  fx : Double,
  fy : Double,
  w : Double,
  panel : Double,
  final_cs : Array[Double],
) -> Unit {
  let m = bar
  let items = sets[cur]
  let multi = sets.length() > 1
  let row_top = panel - bar_track
  let reach = row_top - over
  let px = d.x - fx
  let py = d.y - fy
  let on_tab = fn(place : String) {
    if Some(place) != active {
      go_place(c, place, sets, cur)
    }
  }
  // another bar chosen (and a place in it, when one was tapped): it is the bar, and the place opens, now; the panel
  // closes like a window over a stack of bars, the chosen one sliding down into the bar's place (Bar.kt pick)
  let pick = fn(i : Int, key : String?) {
    if m.swap is Some(_) {
      return
    }
    let n = match others.search(i) {
      Some(n) => n
      None => return
    }
    let lit : Map[String, Double] = Map([])
    for id, g in m.tints {
      lit[id] = g.value
    }
    m.swap = Some({
      i,
      n,
      from: dmax(0.2, m.o.x),
      key,
      sets,
      cur,
      alpha: rows_alpha(m.o.x),
      drop: rows_shift(m.o.x, reach),
      lit,
    })
    m.mode.set(false)
    m.o.go(0.0, 200.0, 28.0)
    // its first frame, drawn as the panel was (the motion log)
    @motion.log_frame(c, "bar/swap", "value=\{m.o.x} to=0")
    set_bars(src, ws.id, sets, i)
    match key {
      Some(k) => go_place(c, k, sets, i)
      None => ()
    }
  }
  // a bar chosen landing: it lands on its own spring, untouched; a finger down meanwhile is the finger's once it has
  // (its stroke from there), lifted before, nothing
  if m.swap is Some(_) {
    // a bar chosen landing lands on its own spring: a finger down meanwhile does not take the ball or the panel
    // (Bar.kt waits); a tap on one of its places is that place's at once, where it is laid out (src/motion's rule)
    if d.down {
      m.waits = true
    }
    ignore(d.take_end())
    if d.take_tap() {
      m.waits = false
      if items.length() > 0 && py >= row_top - 4.0 {
        let now = bar_centres(w, m.k_now(), items.length())
        let j = nearest(now, items.length(), px)
        if (now[j] - px).abs() <= (w - 2.0 * c0) / 6.0 {
          on_tab(items[j])
        }
      }
    }
    return
  }
  if m.waits {
    ignore(d.take_end())
    ignore(d.take_tap())
    m.waits = false
    m.was_down = false
    if !d.down {
      return
    }
  }
  if d.down && !m.was_down {
    // pressed: the panel open, opening or closing, the finger has it from here
    m.was_down = true
    m.y0 = py
    m.o0 = m.o.x
    // (opening: short of the rest its spring declared as it set out, toward open)
    m.holds = multi && (m.o0 > 0.02 || (bar_clock.now < m.o.end() && m.o.to > 0.0))
    m.from_open = m.holds
    m.open = m.o.to > 0.5
    if m.holds {
      m.mode.set(true)
    }
  }
  if d.down && d.moving {
    if multi {
      let raw = m.o0 + (m.y0 - py - (if m.from_open { 0.0 } else { 8.0 })) / reach
      if !m.holds && raw > 0.0 {
        m.holds = true
        m.mode.set(true)
      }
      if m.holds {
        let over_bar = row_top - py
        if !m.open && over_bar > opens {
          m.open = true
        } else if m.open && over_bar < closes {
          m.open = false
        }
        let snap = if m.open { 1.0 } else { 0.0 }
        let goal = dclamp(snap + lean * (raw - snap), 0.0, 1.1)
        if m.open {
          m.o.go(goal, 260.0, 17.0)
        } else {
          m.o.go(goal, 320.0, 26.0)
        }
      }
    }
    m.drag = px
    m.drag_y = if multi && m.holds && m.open {
      dclamp(py, over + bar_row / 2.0, row_top + bar_track / 2.0)
    } else {
      -1.0
    }
  }
  // held where it went down a moment (not moved past the slop), on the bar's row: the ball the finger's there, the
  // lens over it as while it slides (iOS's tab bar), going nowhere till the finger moves; let go, a tap as any
  let held_still = d.down && !d.moving && !m.holds && py >= row_top - 4.0
  if c.held("bar/held-still", held_still, bar_hold_ms) {
    m.drag = px
    m.drag_y = -1.0
  }
  if d.take_end() {
    m.was_down = false
    let had = m.holds
    m.holds = false
    m.drag = -1.0
    m.drag_y = -1.0
    if had {
      // let go on a row (the panel open): that bar and that place; else as the finger left it
      let in_rows = py < row_top - 4.0 && others.length() > 0
      if in_rows && m.o.x >= 0.85 {
        let n = dclamp(((py - over) / bar_row).floor(), 0.0, (others.length() - 1).to_double()).to_int()
        let set = sets[others[n]]
        pick(others[n], Some(set[nearest(bar_centres(w, 0.0, set.length()), set.length(), px)]))
      } else {
        let j = if py >= row_top - 4.0 && items.length() > 0 {
          imin(items.length() - 1, nearest(final_cs, 4, px))
        } else {
          -1
        }
        m.open_panel(m.open)
        if !m.open && j >= 0 {
          on_tab(items[j])
        }
      }
    } else if items.length() > 0 {
      let j = imin(items.length() - 1, nearest(final_cs, 4, px))
      if m.mode.get() {
        m.open_panel(false)
      }
      on_tab(items[j])
    }
  }
  if d.take_tap() {
    m.was_down = false
    m.holds = false
    m.drag = -1.0
    m.drag_y = -1.0
    // a tap: a place on the bar; with the panel open, a row (that bar) or a place in it
    if m.mode.get() && py < row_top {
      if m.o.x > 0.6 && others.length() > 0 {
        let shift = (1.0 - dmin(1.0, m.o.x)) * 14.0 - dmax(0.0, m.o.x - 1.0) * reach
        let n = ((py - over - shift) / bar_row).floor().to_int()
        if n >= 0 && n < others.length() {
          let set = sets[others[n]]
          let cs = bar_centres(w, 0.0, set.length())
          let j = nearest(cs, set.length(), px)
          let slot = (w - 2.0 * c0) / 3.0
          pick(others[n], if (cs[j] - px).abs() <= slot / 2.0 { Some(set[j]) } else { None })
        }
      }
    } else if items.length() > 0 && py >= row_top - 4.0 {
      let now = bar_centres(w, m.k_now(), items.length())
      let j = nearest(now, items.length(), px)
      let slot = (w - 2.0 * c0) / 3.0
      if (now[j] - px).abs() <= slot / 2.0 {
        if m.mode.get() {
          m.open_panel(false)
        }
        on_tab(items[j])
      }
    }
  }
  if !d.down {
    m.was_down = false
  }
}

///|
/// A place's top page other than the chats (PlacePage.kt, with the bar under it): Home's top bar over it (settings,
/// the place's name), what it shows the settings' page of it (src/sfapp/settings).
fn place_page(c : @ui.Ctx, src : Source, w : Workspace, place : String) -> Unit {
  // what it shows runs under the top bar, frosted over it (PlacePage.kt: `bar + 8.dp` down, scrolling under it)
  c.box(w=Fill(1.0), h=Fill(1.0), fn() {
    // what it shows: the settings' page of the same place (src/sfapp/settings), in place of its own bar
    c.box(w=Fill(1.0), h=Fill(1.0), fn() {
      match @settings.route_of(place) {
        Some(r) => {
          // under the top bar, which names it; over the bottom bar
          let top = status_top() + bar_h + 8.0
          let frame : PageFrame = { back: None, top, foot: nav_foot() + bar_room_now(), named: true }
          if !@sfdesk.setting_route(c, src, w, r, frame) {
            let core = settings_core(src, w)
            @settings.page(c, core, @settings.here_of(core, w.id, w.name), r, root=true, top~)
          }
        }
        None => ()
      }
    })
    |> ignore
    c.layer(fn() { place_top_bar(c, place) }) |> ignore
  })
  |> ignore
}

///|
/// A place's top bar at the stack's root (PlacePage.kt TopGlassBar): settings, the place's name, the page's actions
/// (`@sf.named_actions`); frosted over what runs under it, no line under it.
fn place_top_bar(c : @ui.Ctx, place : String) -> Unit {
  let t = @sf.theme()
  let actions = @sf.named_actions.val
  @sf.named_actions.val = None
  let glass_top = c.box(w=Fill(1.0), glass=@sf.glass_bar(), fn() {
    // under the status bar (TopGlassBar: windowInsetsPadding(statusBars), then TopBarHeight)
    c.box(dir=Row, w=Fill(1.0), pl=16.0, pr=16.0, pt=status_top(), min_h=top_bar_h(), gap=10.0, align=ACenter, fn() {
      if nav_button(c, "settings", 22.0, key="place-settings", said=tr("android-chat.home.settings")) {
        @sfbase.history_push()
        app.nav.push(Settings)
      }
      // (its words whole: what the page does at its end gives way where the bar has not the room, @sf.head_end)
      c.box(dir=Row, w=Fill(1.0), h=Px(34.0), align=ACenter, keep=true, fn() {
        top_bar_title(c, place_label(place)) |> ignore
      })
      |> ignore
      match actions {
        Some(a) => @sf.head_end(c, a)
        None => ()
      }
    })
    |> ignore
  })
  // over what runs under it: the scroll bar there keeps clear of it
  c.floats_over(glass_top)
}
