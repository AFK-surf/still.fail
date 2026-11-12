// Animated values kept from frame to frame (Compose's Animatable and animateFloatAsState; Motion's MotionValue and
// animate): a number going to a target by a spec, from where it is and how fast it moves when told anew. A motion starts
// at the moment it is told (a frame told it draws it at its start; told between frames, the next frame draws it as far
// on as the time since says), its end known as it is told. Its time goes by the frames' clock in whole milliseconds. Reduced motion (the host's setting, or MBUI_REDUCE_MOTION=1) puts every
// motion at its end at once; a screenshot's run moves as any run.

///|
/// A number that animates (Compose's Animatable).
pub struct Anim {
  /// where it is, read outside this package only as it is shown (Anim::get: what reads it follows it)
  priv mut value : Double
  /// per second
  mut velocity : Double
  mut target : Double
  /// where it ends (its target, or where a transition of Motion's ends: inertia, keyframes)
  mut end : Double
  mut spec : Spec
  /// a transition of Motion's: its generator, made when it was told to go
  mut gen : Generator?
  mut from : Double
  mut v0 : Double
  /// when it started (ms, the moment it was told, or the one it was told to start at); -1: never told to go
  mut start : Double
  mut dur : Double
  /// whether it goes (outside this package, whether it is on its way is its declared end's: Anim::over)
  priv mut running : Bool
  /// the moment it was last stepped to (where it is then is a function of its way and that moment, however many frames
  /// there are at it: stepped again there, it is where it was; -inf: not since it was told)
  priv mut stepped_at : Double
  /// the moment it was put somewhere at once on its way (snap), its way cut short there; -1: not since it was told
  priv mut cut_at : Double
  /// kept by its key (anim): whether what asks it is built (until it is not: anim_unbuilt)
  priv mut built : Bool
  /// what it is said to move by (Ctx::moving), and what it is said to be: its key, who told it to go
  id : @ui.Mover
  mut name : String
  mut told : String
}

///|
/// Where an Anim goes, all of it: what is built from where it is is built again only as this changes.
#derive(Eq)
priv struct AnimWay {
  running : Bool
  value : Double
  from : Double
  target : Double
  end : Double
  /// its spec (one of Motion's transitions by what it was said with: Transition's Eq)
  spec : Spec
  v0 : Double
  start : Double
  dur : Double
}

///|
fn Anim::way(self : Anim, c : @ui.Ctx) -> AnimWay {
  // (going by its way at this moment: where it is, stepped by the clock, and its getting to its end as the frame goes
  // are no change of it; still, or at its end by now: where it is)
  let now = c.moment()
  let going = self.running && !(self.start >= 0.0 && @ui.gone_ms(now - self.start) >= @ui.gone_ms(self.dur))
  {
    running: going,
    value: if going {
      0.0
    } else if self.running {
      self.end
    } else {
      self.value
    },
    from: self.from,
    target: self.target,
    end: self.end,
    spec: self.spec,
    v0: self.v0,
    start: self.start,
    dur: self.dur,
  }
}

///|
/// While a layout's motions are worked out (laid_once): each Anim told and where it went before, told once it is done
/// where it goes came out otherwise. Each build of a frame lays it out again from where the frame began (layer.mbt's
/// was_*), its motions told again as they were: the same way told again is no change.
// kept across runs: set and let go within one layout's motions
let laid_ways : Ref[Array[(Anim, AnimWay)]?] = Ref(None)

///|
/// `f`, the motions it tells told only once it is done, each whose way came out otherwise than before it: where each
/// went taken as it is first told or set by hand (Anim::tells_now).
fn laid_once(c : @ui.Ctx, f : () -> Unit) -> Unit {
  let ways : Array[(Anim, AnimWay)] = []
  let was = laid_ways.val
  laid_ways.val = Some(ways)
  f()
  laid_ways.val = was
  for w in ways {
    if w.0.way(c) != w.1 {
      w.0.id.changed()
    }
  }
}

///|
/// Whether what is built from where it is is told now (false: once the layout's motions are done, laid_once), where it
/// went before kept for that the first time: said before it is told anew or its place set by hand.
fn Anim::tells_now(self : Anim, c : @ui.Ctx) -> Bool {
  match laid_ways.val {
    Some(ways) => {
      if !ways.iter().any(fn(w) { physical_equal(w.0, self) }) {
        ways.push((self, self.way(c)))
      }
      false
    }
    None => true
  }
}

///|
/// A number at `v`, still.
pub fn Anim::new(v : Double) -> Anim {
  {
    value: v,
    velocity: 0.0,
    target: v,
    end: v,
    spec: Snap(0.0),
    gen: None,
    from: v,
    v0: 0.0,
    start: -1.0,
    dur: 0.0,
    running: false,
    stepped_at: @double.neg_infinity,
    cut_at: -1.0,
    built: false,
    id: @ui.Mover::new(),
    name: "",
    told: "",
  }
}

///|
/// Steps it to this moment (once a moment: where it is then is its way's at that moment, however many frames are drawn
/// at it).
fn Anim::step(self : Anim, c : @ui.Ctx) -> Unit {
  if self.stepped_at == c.moment() {
    return
  }
  self.stepped_at = c.moment()
  if !self.running {
    return
  }
  if c.still() {
    self.finish()
    return
  }
  // (going: what reads it reads the clock, built again each frame: frame_watch.mbt)
  // (read for its mover: the performance record names it, not this place)
  let ms = c.now_of(self.id) - self.start
  match (self.gen, self.spec) {
    (Some(g), Motion(tr)) => {
      // as Motion plays it: its generator at the time since it started (whole ms), done when it says so
      let t = @ui.gone_ms(ms) - tr.delay
      if t < 0.0 {
        return
      }
      let st = g.next(t)
      self.value = st.value
      self.velocity = g.velocity(t, initial=self.v0)
      if st.done || @ui.gone_ms(ms) >= @ui.gone_ms(self.dur) {
        self.finish()
      }
      return
    }
    _ => ()
  }
  let (x, v) = self.spec.value_at(ms, self.dur, self.from, self.target, self.v0)
  self.value = x
  self.velocity = v
  if @ui.gone_ms(ms) >= @ui.gone_ms(self.dur) {
    self.finish()
  }
}

///|
fn Anim::finish(self : Anim) -> Unit {
  self.value = self.end
  self.velocity = 0.0
  self.running = false
}

///|
/// When it is there (whole ms, as its time goes), asked at each frame's end while it moves: read only, the same
/// whoever asks first. It goes from the moment it was told (between frames too: that moment, a frame asked for to
/// show it), so its end is known as it is told.
pub impl @ui.Moving for Anim with rest_at(self, now, frame) {
  ignore(now)
  ignore(frame)
  if self.running && self.start >= 0.0 {
    self.start + self.dur.ceil()
  } else {
    -1.0
  }
}

///|
/// When it is there (whole ms, the frames' clock): from the moment it was told; before now (-1) when it is at rest. For the frames
/// (rounded up): the next of a chain of motions starts at `ends()`, its declared end.
pub fn Anim::ends_at(self : Anim) -> Double {
  if !self.running {
    -1.0
  } else if self.start >= 0.0 {
    self.start + self.dur.ceil()
  } else {
    @double.infinity
  }
}

///|
/// When it is there, or was (whole ms, the frames' clock): ends_at while it goes; once at rest, the end its own start
/// and length said (not "none moves"), whichever frames were drawn on its way, or the moment it was put somewhere at
/// once before that (snap: its way cut short); -1 where it was never told to go.
/// What a test asks of when a part stops (a viewer's fade, a flash, a room opening: their `*_rest`), so a test whose
/// frames passed the end runs to now, not to "no motion".
pub fn Anim::ended_at(self : Anim) -> Double {
  if self.running {
    self.ends_at()
  } else if self.start >= 0.0 {
    let end = self.start + self.dur.ceil()
    if self.cut_at >= 0.0 && self.cut_at < end {
      self.cut_at
    } else {
      end
    }
  } else {
    -1.0
  }
}

///|
/// When it is there exactly (the frames' clock, not to the whole ms): where the next of a chain of motions starts
/// (`animate(start_at=…)`), so each goes on from its declared end, not from the frame that saw it end; +inf while it
/// has not started yet. Once at rest, still when it got there (or would have: told to stop, when it was to).
pub fn Anim::ends(self : Anim) -> Double {
  if self.start >= 0.0 {
    self.start + self.dur
  } else {
    @double.infinity
  }
}

///|
/// Whether the end it declared as it was told (`ends()`) has come, on the frames' clock: what waits for a motion (what
/// is shown after it, a press it holds back, state let go once it is over) waits till then, from its cause, not for it
/// to be seen still (sf/motion.mbt: no logic reads whether a motion runs). Never told: it has; with motion reduced, as
/// it was told. `c`: the old view that reads it, at its moment.
pub fn Anim::over(self : Anim, c : @ui.Ctx) -> Bool {
  let over = self.start < 0.0 || c.moment() >= self.ends()
  // (what is built from it changes as it is told, and at its end, or the next frame where it starts then)
  c.shows_motion(self.id, !over && self.ends() == @double.infinity)
  if !over && self.ends() < @double.infinity {
    c.shows_until(self.ends())
  }
  over
}

///|
/// Where it is this frame of the old view `c` (what is built from it, built again as it is told and each frame as it
/// goes: Ctx::shows_motion).
pub fn Anim::get(self : Anim, c : @ui.Ctx) -> Double {
  self.step(c)
  c.shows_motion(self.id, self.running)
  self.value
}

///|
/// Where it is going.
pub fn Anim::target(self : Anim) -> Double {
  self.target
}

///|
/// Off to `target` by `spec`, from where it is now and as fast as it moves (or `velocity`, per second), from this
/// moment on (told between frames: from that moment, the next frame drawing it as far on). `start_at`: from that moment instead, one the
/// framework worked out (the motion before's `ends()`), never later than now: one motion going on from where the one
/// before it was declared to end, whichever frame saw that; its value this frame as far on as the time since says.
/// Already over by now (a chain caught up after a while unseen), it is there at once and is not said to move. `c`: the
/// old view it moves in, whose moment it is told at and whose frames show it.
#callsite(autofill(loc))
pub fn Anim::animate(
  self : Anim,
  c : @ui.Ctx,
  target : Double,
  spec : Spec,
  velocity? : Double,
  start_at? : Double,
  loc~ : SourceLoc,
) -> Unit {
  self.step(c)
  let tell = self.tells_now(c)
  self.from = self.value
  self.v0 = match velocity {
    Some(v) => v
    None => self.velocity
  }
  self.target = target
  self.spec = spec
  match spec {
    Motion(tr) => {
      let g = tr.generator(self.from, target, self.v0)
      self.gen = Some(g)
      let d = generator_duration(g)
      self.dur = tr.delay + d
      self.end = g.next(d).value
    }
    _ => {
      self.gen = None
      self.dur = spec.duration(self.from, target, self.v0)
      self.end = target
    }
  }
  // (this frame shows it at its start: where it is now)
  self.start = match start_at {
    Some(at) => {
      // (the motion before done at its end as gone_ms has it, its end summed another way than now: the same moment,
      // 4066.666666666667 for 4066.6666666666665, from now)
      if at > c.moment() + @ui.same_moment_ms {
        let s = "Anim::animate: start_at \{at} is later than now (\{c.moment()}), told at \{loc}"
        @halt.saying(s)
      }
      if at > c.moment() {
        c.moment()
      } else {
        at
      }
    }
    None => c.moment()
  }
  // (started earlier: stepped to where it is by now as get() asks; else at its start now, where it is)
  self.stepped_at = if start_at is Some(_) { @double.neg_infinity } else { c.moment() }
  self.cut_at = -1.0
  // motion reduced: its length none, there at once, its end the moment it was told, so a chain goes on
  // from it in the same build, all of it there at once
  if c.still() {
    self.dur = 0.0
    if self.start < 0.0 {
      self.start = c.moment()
    }
  }
  let over = start_at is Some(at) && at + self.dur <= c.moment()
  if c.still() || over || (self.dur <= 0.0 && self.from == self.end) {
    // (there at once: what was built from where it was, built again)
    if self.value != self.end && tell {
      self.id.changed()
    }
    self.finish()
  } else {
    self.running = true
    // said once, as it is told to go: frames until it is there
    let what = if self.name == "" { "an Anim" } else { "Anim \"" + self.name + "\"" }
    self.told = what + " to \{target}, told at \{loc}"
    if c.in_frame() {
      c.moving_as(self.id, self as &@ui.Moving, self.told, tell~)
    } else {
      // (told between frames: from the moment it was told, a frame asked for to show it)
      ignore(c.set_out(self.id, self as &@ui.Moving, what=self.told))
    }
    // (who it is for the performance record: its key and who told it, not where to)
    self.id.told_as(what, loc)
  }
}

///|
/// Where it is and how fast it goes (per second) at moment `at` on the way it was told, as that way has it (not where a
/// frame drew it): its start if `at` is before it.
fn Anim::state_at(self : Anim, at : Double) -> (Double, Double) {
  if !self.running || self.start < 0.0 {
    return (self.value, 0.0)
  }
  let ms = at - self.start
  if ms <= 0.0 {
    return (self.from, self.v0)
  }
  if ms >= self.dur {
    return (self.end, 0.0)
  }
  match (self.gen, self.spec) {
    (Some(g), Motion(tr)) => {
      let t = ms - tr.delay
      if t < 0.0 {
        (self.from, self.v0)
      } else {
        (g.next(t).value, g.velocity(t, initial=self.v0))
      }
    }
    _ => self.spec.value_at(ms, self.dur, self.from, self.target, self.v0)
  }
}

///|
/// Where a frame drawn at moment `at` (now or later) has it on the way it was told, as Anim::get would then (to its end
/// once its time has gone, as its time goes, whole ms), read by nothing: what is built from when it gets somewhere (a
/// share of its way) asks when that is of it once, and is built again then (Ctx::shows_from), not each frame it goes.
pub fn Anim::value_at(self : Anim, at : Double) -> Double {
  if !self.running || self.start < 0.0 {
    return self.value
  }
  let ms = at - self.start
  match (self.gen, self.spec) {
    (Some(g), Motion(tr)) => {
      let t = @ui.gone_ms(ms) - tr.delay
      if @ui.gone_ms(ms) >= @ui.gone_ms(self.dur) || (t >= 0.0 && g.next(t).done) {
        self.end
      } else if t < 0.0 {
        self.from
      } else {
        g.next(t).value
      }
    }
    _ =>
      if @ui.gone_ms(ms) >= @ui.gone_ms(self.dur) {
        self.end
      } else {
        self.spec.value_at(ms, self.dur, self.from, self.target, self.v0).0
      }
  }
}

///|
/// Told at moment `at` (now, or a moment before it in this frame) to stop where it goes, one of it `points` points: on
/// from where its way had it then and as fast, slowing to rest on a Move's way as far as that speed carries it
/// (@ui.move_stop_points), never past its end nor back: its speed the same either side of `at`, no stop dead, wherever
/// the frames fall. At rest, or past its end by then, it stays.
#callsite(autofill(loc))
pub fn Anim::stop_at(self : Anim, c : @ui.Ctx, at : Double, points~ : Double, loc~ : SourceLoc) -> Unit {
  self.step(c)
  if !self.running || points <= 0.0 {
    return
  }
  // (a moment said after this frame's, as a press's is where the frame it is built in is drawn for an earlier vsync (a
  // device behind its input: Android's, 2026-11-10, words sent again 118 ms after the frame's moment, abort in animate):
  // now)
  let at = if at > c.moment() { c.moment() } else { at }
  let (x, v) = self.state_at(at)
  let ahead = @ui.move_stop_points(v * points / 1000.0) / points
  let to = if v >= 0.0 {
    dmin(x + ahead, dmax(self.target, x))
  } else {
    dmax(x - ahead, dmin(self.target, x))
  }
  self.value = x
  self.velocity = v
  self.animate(c, to, Moved(points, -1.0, 0.0), velocity=v, start_at=at, loc~)
}

///|
/// Off to `target`, unless it goes there already or is there (animate*AsState): told again
/// mid-way it goes on from where it is, as fast as it goes.
#callsite(autofill(loc))
pub fn Anim::follow(self : Anim, c : @ui.Ctx, target : Double, spec : Spec, loc~ : SourceLoc) -> Unit {
  self.step(c)
  if target == self.target {
    return
  }
  self.animate(c, target, spec, loc~)
}

///|
/// There at once, still (Animatable.snapTo), as of the old view `c`'s moment.
pub fn Anim::snap(self : Anim, c : @ui.Ctx, v : Double) -> Unit {
  if (self.value != v || self.target != v || self.running) && self.tells_now(c) {
    self.id.changed()
  }
  if self.running {
    self.cut_at = c.moment()
  }
  self.value = v
  self.target = v
  self.end = v
  self.gen = None
  self.velocity = 0.0
  self.running = false
  self.stepped_at = c.moment()
}

///|
/// What animates, kept from frame to frame by its key (in the scope it was asked in), forgotten once neither used nor
/// moving for a while.
let anims : Map[Int, Anim] = Map([])

///|
/// The keys of the Anims whose asker was no longer built while they moved: let go once they are still (anims_let_go).
// kept across runs: forgotten as a Tester starts anew (reset)
let anims_moving : Array[Int] = []

///|
/// Anim `a`, kept by `id`, asked by what is built now: kept while that is built, let go as it is no longer.
/// Asked outside a build (told by an input's handler, or read as a frame is painted), nothing built owns it: kept as
/// it was told until a build asks for it (then let go as what built it is) or the run is reset.
fn anim_built(c : @ui.Ctx, id : Int, a : Anim) -> Unit {
  if c.on_unbuilt(hash_mix(0x616e696d, id), fn() { anim_unbuilt(id) }) {
    a.built = true
  }
}

///|
/// What asked the Anim kept by `id` is no longer built (a page gone, a row scrolled away: made anew at rest when it comes
/// back): forgotten, or once it has got where it went (anims_let_go).
fn anim_unbuilt(id : Int) -> Unit {
  match anims.get(id) {
    Some(a) => {
      a.built = false
      if a.running {
        anims_moving.push(id)
      } else {
        anims.remove(id)
      }
    }
    None => ()
  }
}

///|
/// The Anims no longer asked that were moving, forgotten once their way is over by `now` (asked again meanwhile: kept).
fn anims_let_go(c : @ui.Ctx) -> Unit {
  let now = c.moment()
  if anims_moving.is_empty() {
    return
  }
  let keep : Array[Int] = []
  for id in anims_moving {
    match anims.get(id) {
      Some(a) if !a.built => if a.running && now < a.ends() { keep.push(id) } else { anims.remove(id) }
      _ => ()
    }
  }
  anims_moving.clear()
  anims_moving.append(keep)
}

///|
/// A number kept from frame to frame by `key`, starting at `init`; it goes as it is told (Anim::animate, follow,
/// snap). `global`: the same wherever it is asked (a list's row, at any index), else by the scope it is asked in.
pub fn anim(c : @ui.Ctx, key : String, init : Double, global? : Bool = false) -> Anim {
  install()
  let id = if global { motion_key(key) } else { c.id(key) }
  let a = match anims.get(id) {
    Some(a) => a
    None => {
      let a = Anim::new(init)
      anims[id] = a
      a
    }
  }
  if a.name == "" {
    a.name = key
  }
  anim_built(c, id, a)
  a.step(c)
  a
}

///|
/// A number that follows `target` by `spec` (Compose's animateFloatAsState): at `from` (or at the target) the first
/// time, then on to each new target from where it is, as fast as it goes. Its value this frame.
#callsite(autofill(loc))
pub fn animate(
  c : @ui.Ctx,
  key : String,
  target : Double,
  spec? : Spec = animate_spring,
  from? : Double,
  loc~ : SourceLoc,
) -> Double {
  let first = !anims.contains(c.id(key))
  let a = anim(c, key, match from {
    Some(f) => f
    None => target
  })
  if first && a.value != target {
    a.animate(c, target, spec, loc~)
  } else {
    a.follow(c, target, spec, loc~)
  }
  if a.running && logging() {
    @ui.log("MOTION \{c.moment()} \{key} value=\{a.value} to=\{a.target}")
  }
  // (read so: what reads it is built again as it is told and each frame while it goes, Anim::get)
  a.get(c)
}

///|
/// The number kept as `key` (anim), told as it is built that it goes to `target` by `spec` (animate's way: at the
/// target the first time, then on to each new target from where it is): read where it is shown (Anim::get as it is
/// painted: Ctx::bg_by, Ctx::look_by), not as it is built, so what builds it is not built again each frame it goes
/// (motion in what is made once). Telling it reads no clock.
#callsite(autofill(loc))
pub fn told(c : @ui.Ctx, key : String, target : Double, spec? : Spec = spring(), loc~ : SourceLoc) -> Anim {
  @signals.untracked(fn() {
    let first = !anims.contains(c.id(key))
    let a = anim(c, key, target)
    if !first {
      a.follow(c, target, spec, loc~)
    }
    a
  })
}

///|
/// How much the pressed look of the thing with `id` shows (0 … 1): in over 75 ms as a finger goes down, out over 150
/// once it lifts, a press however short shown whole first (the timing of Android's ripple, RippleDrawable, as the
/// app's `clickable`s have it). Only a look: the tap is the thing's own, at once.
pub fn pressing(c : @ui.Ctx, id : Int) -> Double {
  let down = c.pressed(id)
  let key = "\u{1}press/\{id}"
  let a = match anims.get(motion_key(key)) {
    Some(a) => a
    None => {
      if !down {
        return 0.0
      }
      anim(c, key, 0.0, global=true)
    }
  }
  anim_built(c, motion_key(key), a)
  a.step(c)
  if down {
    a.follow(c, 1.0, tween(75.0, ease=Linear))
  } else if !(a.running && a.target == 1.0) {
    a.follow(c, 0.0, tween(150.0, ease=Linear))
  }
  a.get(c)
}
