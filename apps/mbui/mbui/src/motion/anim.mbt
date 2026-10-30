// Animated values kept from frame to frame (Compose's Animatable and animateFloatAsState; Motion's MotionValue and
// animate): a number going to a target by a spec, from where it is and how fast it moves when told anew. A motion told
// in a frame starts there, at its time (that frame draws it at its start; its end known as it is told); told between
// frames, at the next. Its time goes by the frames' clock in whole milliseconds. Reduced motion (the host's setting, or MBUI_REDUCE_MOTION=1) puts every
// motion at its end at once (Motion.kt: one clock for all of it); a screenshot's run moves as any run.

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
  /// when it started (ms); -1: it starts at the first frame after `asked` (told between frames)
  mut start : Double
  mut asked : Int
  mut dur : Double
  /// whether it goes, read outside this package only so (Anim::moving)
  priv mut running : Bool
  /// the frame it was last stepped in and the moment (a frame painted alone is at another moment of the same frame
  /// number: frame_watch.mbt), and the frame it was last used in
  mut stepped : Int
  mut stepped_at : Double
  mut used : Int
  /// what it is said to move by (Ctx::moving), and what it is said to be: its key, who told it to go
  id : @ui.Mover
  mut name : String
  mut told : String
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
    asked: -1,
    dur: 0.0,
    running: false,
    stepped: -1,
    stepped_at: -1.0,
    used: -1,
    id: @ui.Mover::new(),
    name: "",
    told: "",
  }
}

///|
/// Steps it to this frame (once a frame, at its moment).
fn Anim::step(self : Anim, c : @ui.Ctx) -> Unit {
  let frame = c.frame_number()
  if self.stepped == frame && self.stepped_at == c.moment() {
    return
  }
  self.stepped = frame
  self.stepped_at = c.moment()
  if !self.running {
    return
  }
  if c.still() {
    self.finish()
    return
  }
  if self.start < 0.0 {
    if frame <= self.asked {
      // it starts at the next frame
      return
    }
    self.start = c.moment()
    // (said to move again: not read in the frame it was to start in, it had been let be)
    c.moving_as(self.id, self as &@ui.Moving, self.told)
  }
  // (going: what reads it reads the clock, built again each frame: frame_watch.mbt)
  let ms = c.now() - self.start
  match (self.gen, self.spec) {
    (Some(g), Motion(tr)) => {
      // as Motion plays it: its generator at the time since it started (whole ms), done when it says so
      let t = @ui.whole_ms(ms) - tr.delay
      if t < 0.0 {
        return
      }
      let st = g.next(t)
      self.value = st.value
      self.velocity = g.velocity(t, initial=self.v0)
      if st.done || @ui.whole_ms(ms) >= self.dur {
        self.finish()
      }
      return
    }
    _ => ()
  }
  let (x, v) = self.spec.value_at(ms, self.dur, self.from, self.target, self.v0)
  self.value = x
  self.velocity = v
  if @ui.whole_ms(ms) >= self.dur {
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
/// whoever asks first. Told to go between frames, it starts at the first frame after (its first step there): until
/// then +inf; not read in that frame (nothing shows it), at rest, said to move again by its first step.
pub impl @ui.Moving for Anim with rest_at(self, now, frame) {
  ignore(now)
  if !self.running {
    -1.0
  } else if self.start >= 0.0 {
    self.start + self.dur.ceil()
  } else if frame <= self.asked {
    @double.infinity
  } else {
    -1.0
  }
}

///|
/// When it is there (whole ms, the frames' clock): from when it was told in a frame; +inf while it has not started
/// yet (told between frames, it starts at the first frame after), before now (-1) when it is at rest. For the frames
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
/// to be seen still (docs/motion.md: no logic reads whether a motion runs). Never told: it has; told between frames,
/// not before it starts; with motion reduced, as it was told.
pub fn Anim::over(self : Anim) -> Bool {
  let c = @ui.current()
  let over = (self.start < 0.0 && self.asked < 0) || c.moment() >= self.ends()
  // (what is built from it changes as it is told, and at its end, or the next frame where it starts then)
  c.shows_motion(self.id, !over && self.ends() == @double.infinity)
  if !over && self.ends() < @double.infinity {
    c.shows_until(self.ends())
  }
  over
}

///|
/// Where it is this frame (what is built from it, built again as it is told and each frame as it goes:
/// Ctx::shows_motion).
pub fn Anim::get(self : Anim) -> Double {
  let c = @ui.current()
  self.step(c)
  c.shows_motion(self.id, self.running)
  self.value
}

///|
/// Whether it is on its way.
pub fn Anim::moving(self : Anim) -> Bool {
  let c = @ui.current()
  self.step(c)
  c.shows_motion(self.id, self.running)
  self.running
}

///|
/// Where it is going.
pub fn Anim::target(self : Anim) -> Double {
  self.target
}

///|
/// Off to `target` by `spec`, from where it is now and as fast as it moves (or `velocity`, per second), from this
/// frame's time on (told between frames: from the next frame's). `start_at`: from that moment instead, one the
/// framework worked out (the motion before's `ends()`), never later than now: one motion going on from where the one
/// before it was declared to end, whichever frame saw that; its value this frame as far on as the time since says.
/// Already over by now (a chain caught up after a while unseen), it is there at once and is not said to move.
#callsite(autofill(loc))
pub fn Anim::animate(
  self : Anim,
  target : Double,
  spec : Spec,
  velocity? : Double,
  start_at? : Double,
  loc~ : SourceLoc,
) -> Unit {
  let c = @ui.current()
  self.step(c)
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
      // (the motion before done at its end as whole_ms has it, its end summed another way than now: the same moment,
      // 4066.666666666667 for 4066.6666666666665, from now)
      if at > c.moment() + @ui.same_moment_ms {
        let s = "Anim::animate: start_at \{at} is later than now (\{c.moment()}), told at \{loc}"
        println(s)
        abort(s)
      }
      if at > c.moment() {
        c.moment()
      } else {
        at
      }
    }
    None => c.moment()
  }
  self.asked = c.frame_number()
  // (started earlier: stepped this frame to where it is by now, as get() asks)
  self.stepped = if start_at is Some(_) { -1 } else { c.frame_number() }
  self.stepped_at = c.moment()
  // motion reduced: its length none (Motion.kt), there at once, its end the moment it was told, so a chain goes on
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
    if self.value != self.end {
      self.id.changed()
    }
    self.finish()
  } else {
    self.running = true
    // said once, as it is told to go: frames until it is there
    self.told = (if self.name == "" { "an Anim" } else { "Anim \"" + self.name + "\"" }) +
      " to \{target}, told at \{loc}"
    if c.in_frame() {
      c.moving_as(self.id, self as &@ui.Moving, self.told)
    } else {
      // (told between frames: from the moment it was told, a frame asked for to show it)
      ignore(c.set_out(self.id, self as &@ui.Moving, what=self.told))
    }
  }
}

///|
/// Off to `target`, unless it goes there already or is there (Motion.kt Follower.to; animate*AsState): told again
/// mid-way it goes on from where it is, as fast as it goes.
#callsite(autofill(loc))
pub fn Anim::follow(self : Anim, target : Double, spec : Spec, loc~ : SourceLoc) -> Unit {
  self.step(@ui.current())
  if target == self.target {
    return
  }
  self.animate(target, spec, loc~)
}

///|
/// There at once, still (Animatable.snapTo).
pub fn Anim::snap(self : Anim, v : Double) -> Unit {
  if self.value != v || self.target != v || self.running {
    self.id.changed()
  }
  self.value = v
  self.target = v
  self.end = v
  self.gen = None
  self.velocity = 0.0
  self.running = false
  self.stepped = @ui.current().frame_number()
  self.stepped_at = @ui.current().moment()
}

///|
/// What animates, kept from frame to frame by its key (in the scope it was asked in), forgotten once neither used nor
/// moving for a while.
let anims : Map[Int, Anim] = {}

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
  a.used = c.frame_number()
  @ui.built_used(fn() { a.used = @ui.current().frame_number() })
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
  spec? : Spec = spring(),
  from? : Double,
  loc~ : SourceLoc,
) -> Double {
  let first = !anims.contains(c.id(key))
  let a = anim(c, key, match from {
    Some(f) => f
    None => target
  })
  if first && a.value != target {
    a.animate(target, spec, loc~)
  } else {
    a.follow(target, spec, loc~)
  }
  if a.running && logging() {
    @ui.log("MOTION \{c.moment()} \{key} value=\{a.value} to=\{a.target}")
  }
  // (read so: what reads it is built again as it is told and each frame while it goes, Anim::get)
  a.get()
}

///|
/// The number kept as `key` (anim), told as it is built that it goes to `target` by `spec` (animate's way: at the
/// target the first time, then on to each new target from where it is): read where it is shown (Anim::get as it is
/// painted: Ctx::bg_by, Ctx::look_by), not as it is built, so what builds it is not built again each frame it goes
/// (docs/retained.md, motion in what is made once). Telling it reads no clock.
#callsite(autofill(loc))
pub fn told(c : @ui.Ctx, key : String, target : Double, spec? : Spec = spring(), loc~ : SourceLoc) -> Anim {
  @signals.untracked(fn() {
    let first = !anims.contains(c.id(key))
    let a = anim(c, key, target)
    if !first {
      a.follow(target, spec, loc~)
    }
    a
  })
}

///|
/// Forgets what has not been used for a while and does not move (a page gone, a row scrolled away: made anew at rest
/// when it comes back).
fn sweep_anims(c : @ui.Ctx) -> Unit {
  let frame = c.frame_number()
  if frame % 60 != 0 || anims.is_empty() {
    return
  }
  let old : Array[Int] = []
  anims.each(fn(id, a) { if frame - a.used > 120 && !a.running { old.push(id) } })
  for id in old {
    anims.remove(id)
  }
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
  a.used = c.frame_number()
  @ui.built_used(fn() { a.used = @ui.current().frame_number() })
  a.step(c)
  if down {
    a.follow(1.0, tween(75.0, ease=Linear))
  } else if !(a.running && a.target == 1.0) {
    a.follow(0.0, tween(150.0, ease=Linear))
  }
  a.get()
}
