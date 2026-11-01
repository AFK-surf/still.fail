// Motion done the Effect way: an animation is a fiber of the window's runtime (@ui.runtime, src/effect) that waits on
// the runtime's clock until the moment its run says it ends (its closed form's), and is done there; where the value is
// meanwhile is that closed form at the time it is read (Value::get: the frame's time), however many frames there are
// or none. The value is said to move (@ui.Ctx::moving) until then, so the frames that show it are drawn. Being
// fibers, animations compose as Effect's code does:
//
// - one after another (a timeline): `x.animate(…)` returns once x is there, so the next line starts then;
// - at once: `@effect.all([() => x.animate(…), () => y.animate(…)])`;
// - staggered: `stagger(n, each, i => …)`;
// - interrupted: a new animation of a value interrupts the one running it, and starts from where that one has the
//   value at that instant, as fast as it moves there (Motion: velocity carried), whatever order the runtime ran
//   them in. Interrupting the fiber that awaits an animation (its scope closing, a race lost) stops the animation.
//
// Presence (Motion's AnimatePresence) is a scope: what is shown has a scope of its own; hidden, the scope closes, and
// its exit animation runs in the scope's finalizer while what it was is still drawn (and takes no taps); once the
// finalizer is done it is gone. Gestures (hover, press, drag) start and interrupt the values' fibers. Layout
// animation (`animate_layout`) takes the box a node is drawn in and the box it is laid out in and animates between
// them by Motion's projection (projection.mbt).
//
// Transitions are Motion's (spring_to, tween_to, keyframes_to, inertia_to: their generators, generators.mbt) or
// Compose's (spring, tween: spec.mbt). Reduced motion and screenshots (Ctx::still) put a value at its end at once.

///|
/// An animation of a value: how it goes from where it was told to go, at what time.
priv struct Run {
  spec : Spec
  gen : Generator?
  from : Double
  to : Double
  v0 : Double
  /// when it started (ms, the runtime's clock), how long it takes (its delay in it) and where it ends
  start : Int64
  dur : Double
  end : Double
}

///|
fn Run::new(spec : Spec, from : Double, to : Double, v0 : Double, start : Int64, still : Bool) -> Run {
  match spec {
    Motion(tr) => {
      let g = tr.generator(from, to, v0)
      let d = generator_duration(g)
      let end = g.next(d).value
      { spec, gen: Some(g), from, to, v0, start, dur: if still { 0.0 } else { tr.delay + d }, end }
    }
    _ =>
      {
        spec,
        gen: None,
        from,
        to,
        v0,
        start,
        dur: if still { 0.0 } else { spec.duration(from, to, v0) },
        end: to,
      }
  }
}

///|
/// Where it has the value `t` ms after it started, how fast (per second), and whether it is done.
fn Run::at(self : Run, t : Double) -> (Double, Double, Bool) {
  if t >= self.dur {
    return (self.end, 0.0, true)
  }
  match (self.gen, self.spec) {
    (Some(g), Motion(tr)) => {
      let u = t - tr.delay
      if u < 0.0 {
        return (self.from, 0.0, false)
      }
      let st = g.next(u)
      if st.done {
        (self.end, 0.0, true)
      } else {
        (st.value, g.velocity(u, initial=self.v0), false)
      }
    }
    _ => {
      let (x, v) = self.spec.value_at(t, self.dur, self.from, self.to, self.v0)
      (x, v, false)
    }
  }
}

///|
/// A number that animates, read by the view each frame (Motion's MotionValue): where it is, how fast it moves (per
/// second), where it goes. Fibers move it (Value::animate, Value::start); a frame reads it (Value::get).
pub struct Value {
  priv mut v : Double
  priv mut vel : Double
  priv mut to : Double
  priv mut run : Run?
  priv mut runner : @effect.Fiber[Bool]?
  priv mut used : Int
  priv mover : @ui.Mover
}

///|
/// Said to move while its run goes: at rest at the moment the run ends (its start and its length, as told).
impl @ui.Moving for Value with rest_at(self, now, frame) {
  ignore(now)
  ignore(frame)
  match self.run {
    Some(r) => r.start.to_double() + r.dur
    None => -1.0
  }
}

///|
/// A value at `v`, still (kept by whoever holds it; `value` keeps one by key).
pub fn Value::new(v : Double) -> Value {
  { v, vel: 0.0, to: v, run: None, runner: None, used: -1, mover: @ui.Mover::new() }
}

///|
/// Where it is now (the frame's time, on the runtime's clock): its run's closed form there, read as it is asked (what
/// is built from it, built again as it is set going and each frame as it runs: Ctx::shows_motion).
pub fn Value::get(self : Value) -> Double {
  self.shown()
  self.sample(@ui.runtime().now()).0
}

///|
/// How fast it moves now (per second).
pub fn Value::velocity(self : Value) -> Double {
  self.shown()
  self.sample(@ui.runtime().now()).1
}

///|
/// Read where it is now: what is being built from it changes as it is set going and each frame while it runs.
fn Value::shown(self : Value) -> Unit {
  @ui.current().shows_motion(self.mover, self.run is Some(_))
}

///|
/// Where it goes (where it is, when still).
pub fn Value::target(self : Value) -> Double {
  self.to
}

///|
/// Whether an animation moves it.
pub fn Value::is_animating(self : Value) -> Bool {
  self.run is Some(_)
}

///|
/// When its animation has it there (whole ms, the frames' clock): its start (the moment it was told) and its length,
/// as it was told; before now (-1) when nothing moves it. A read of what it was told: the same whoever asks it, and
/// when (a spring of Motion's may come to rest a little before, never after).
pub fn Value::ends_at(self : Value) -> Double {
  match self.run {
    Some(r) => r.start.to_double() + r.dur.ceil()
    None => -1.0
  }
}

///|
/// Where its animation has it at `now` (ms, the runtime's clock), and how fast: what an animation taking it over
/// starts from, the same whichever ran first at that instant.
fn Value::sample(self : Value, now : Int64) -> (Double, Double) {
  match self.run {
    Some(r) => {
      let (x, v, _) = r.at((now - r.start).to_double())
      (x, v)
    }
    None => (self.v, self.vel)
  }
}

///|
/// Stops its animation where it has it now (Motion's stop).
pub fn Value::stop(self : Value) -> Unit {
  if self.run is Some(_) {
    let (x, _) = self.sample(@ui.runtime().now())
    self.v = x
  }
  self.vel = 0.0
  self.to = self.v
  self.halt()
}

///|
fn Value::halt(self : Value) -> Unit {
  self.run = None
  match self.runner {
    Some(f) => f.interrupt()
    None => ()
  }
  self.runner = None
}

///|
/// There at once, still: its animation stopped (Motion's jump).
pub fn Value::set(self : Value, x : Double) -> Unit {
  if x != self.v || self.run is Some(_) {
    self.mover.changed()
  }
  self.halt()
  self.v = x
  self.vel = 0.0
  self.to = x
}

///|
/// Off to `target` by `spec` (Motion's animate(value, target, transition)), as a fiber of its own: from where it is
/// and as fast as it moves now (or at `velocity`, per second), interrupting the animation that moved it. The fiber
/// gives true once the value is there, false when another animation took it over first. It starts at the moment it is
/// told (the runtime's clock), and is said to move until its end.
#callsite(autofill(loc))
pub fn Value::start(
  self : Value,
  target : Double,
  spec : Spec,
  velocity? : Double,
  loc~ : SourceLoc,
) -> @effect.Fiber[Bool] {
  let rt = @ui.runtime()
  let now = rt.now()
  let (from, v) = self.sample(now)
  self.halt()
  self.v = from
  self.vel = v
  self.to = target
  let r = Run::new(spec, from, target, velocity.unwrap_or(v), now, @ui.current().still())
  self.run = Some(r)
  @ui.current().moving(self.mover, self as &@ui.Moving, what="Value to \{target}", loc~)
  // (who it is for the performance record: who told it, not where to)
  self.mover.told_as("a Value", loc)
  let f = rt.fork(name="animate", () => self.play(r))
  self.runner = Some(f)
  f
}

///|
/// The animation's fiber: it waits until the moment `r` ends (its start and its length, on the runtime's clock), and
/// is done there: the value at its end. No frame is waited for: where the value is meanwhile is read from `r`.
async fn Value::play(self : Value, r : Run) -> Bool {
  // taken over meanwhile (a new animation, a stop, a set): not this one's any more
  guard self.run is Some(cur) && physical_equal(cur, r) else { return false }
  let wait = (r.start.to_double() + r.dur - @effect.now().to_double()).ceil()
  if wait > 0.0 {
    @effect.sleep(wait.to_int())
  }
  guard self.run is Some(cur) && physical_equal(cur, r) else { return false }
  self.v = r.end
  self.vel = 0.0
  self.run = None
  self.runner = None
  true
}

///|
/// Off to `target` by `spec`, waiting until it is there (true) or another animation took it over (false): the
/// awaited form for timelines (`x.animate(…)` then `y.animate(…)`). Interrupting the fiber that waits stops it.
pub async fn Value::animate(
  self : Value,
  target : Double,
  spec : Spec,
  velocity? : Double,
) -> Bool {
  let f = self.start(target, spec, velocity?)
  defer {
    if !f.is_done() {
      f.interrupt()
      if self.runner is Some(g) && physical_equal(g, f) {
        // stopped where it is now
        let (x, _) = self.sample(@ui.runtime().now())
        self.v = x
        self.vel = 0.0
        self.to = x
        self.run = None
        self.runner = None
      }
    }
  }
  match f.wait() {
    Succeeded(b) => b
    Failed(e) => raise e
    Interrupted => false
  }
}

///|
/// Off to `target` unless it goes there already (animate*AsState, Motion's `animate` prop): told the same target
/// again each frame it does nothing; a new one interrupts and carries on from where it is, as fast as it goes.
pub fn Value::follow(self : Value, target : Double, spec : Spec) -> Unit {
  if target != self.to {
    ignore(self.start(target, spec))
  }
}

///|
/// The values kept by key (`value`), forgotten once neither used nor moving for a while.
let values : Map[Int, Value] = Map([])

///|
/// A value kept from frame to frame by `key` (in the current id scope, or anywhere with `global`), starting at `init`
/// (Motion's useMotionValue).
pub fn value(c : @ui.Ctx, key : String, init : Double, global? : Bool = false) -> Value {
  install()
  let id = if global { motion_key("\u{3}" + key) } else { c.id("\u{3}" + key) }
  let v = match values.get(id) {
    Some(v) => v
    None => {
      let v = Value::new(init)
      values[id] = v
      v
    }
  }
  v.used = c.frame_number()
  @ui.built_used(fn() { v.used = @ui.current().frame_number() })
  v
}

///|
fn sweep_values(c : @ui.Ctx) -> Unit {
  let frame = c.frame_number()
  if frame % 60 != 0 || values.is_empty() {
    return
  }
  let old : Array[Int] = []
  values.each(fn(id, v) { if frame - v.used > 120 && v.run is None { old.push(id) } })
  for id in old {
    values.remove(id)
  }
}

///|
/// Where staggering counts from (Motion's stagger `from`).
pub(all) enum StaggerFrom {
  First
  Last
  Center
  Index(Int)
}

///|
/// `f(i)` for `i` in 0 … n-1, each `each` ms after the one before, counted from `from` (Motion's stagger), all at
/// once in fibers of their own; returns once all are done (the first failure fails it, the rest interrupted).
pub async fn stagger(
  n : Int,
  each : Int,
  from? : StaggerFrom = First,
  f : async (Int) -> Unit,
) -> Unit {
  let origin = match from {
    First => 0.0
    Last => (n - 1).to_double()
    Center => (n - 1).to_double() / 2.0
    Index(i) => i.to_double()
  }
  let fs : Array[async () -> Unit] = []
  for i in 0..<n {
    let delay = ((i.to_double() - origin).abs() * each.to_double()).round().to_int()
    fs.push(async fn() {
      if delay > 0 {
        @effect.sleep(delay)
      }
      f(i)
    })
  }
  ignore(@effect.all(fs))
}

// ── presence ────────────────────────────────────────────────────────────

///|
/// One showing of what `animate_presence` shows: its scope, and whether it has gone.
priv struct Showing {
  scope : @effect.Scope
  mut gone : Bool
}

///|
priv struct Pres {
  mut cur : Showing?
  leaving : Array[Showing]
  /// the frame it was last asked for in
  mut seen : Int
}

///|
let presences : Map[Int, Pres] = Map([])

///|
/// What `body` builds, shown while `shown` is (Motion's AnimatePresence, the Effect way): each time it comes it has a
/// scope of its own, `enter` its fiber; hidden, the scope closes (`enter` interrupted) and `exit` runs as its
/// finalizer, while what `body` builds is still drawn, only drawn (no taps, as Ctx::draw_only); once `exit` is done
/// it is gone. Shown again meanwhile, it comes again at once (its `enter`, interrupting what `exit` animates). The
/// values `enter` and `exit` animate are the app's (`value`), read by `body`, which builds into a box of its own
/// (the same box whether shown or leaving). Gives whether it was built.
pub fn animate_presence(
  c : @ui.Ctx,
  key : String,
  shown : Bool,
  enter? : async () -> Unit = async fn() {  },
  exit? : async () -> Unit = async fn() {  },
  body : () -> Unit,
) -> Bool {
  install()
  let id = c.id("\u{4}" + key)
  let p = match presences.get(id) {
    Some(p) => p
    None => {
      let p = { cur: None, leaving: [], seen: 0 }
      presences[id] = p
      p
    }
  }
  p.seen = c.build_number()
  // (asked again by a list's row kept as its nodes, each frame it is: @ui.built_again)
  @ui.built_again(fn(_) { p.seen = @ui.current().build_number() })
  let rt = @ui.runtime()
  match (shown, p.cur) {
    (true, None) => {
      let s = rt.scope()
      s.add_finalizer(exit)
      ignore(s.fork(enter, name="enter " + key))
      p.cur = Some({ scope: s, gone: false })
    }
    (false, Some(cur)) => {
      p.cur = None
      p.leaving.push(cur)
      ignore(
        rt.fork(name="exit " + key, async fn() {
          cur.scope.close()
          cur.gone = true
        }),
      )
    }
    _ => ()
  }
  let mut i = 0
  while i < p.leaving.length() {
    if p.leaving[i].gone {
      ignore(p.leaving.remove(i))
    } else {
      i += 1
    }
  }
  if p.cur is Some(_) {
    ignore(c.box(body))
    true
  } else if !p.leaving.is_empty() {
    c.draw_only(c.box(body))
    true
  } else {
    presences.remove(id)
    false
  }
}

// ── gestures ────────────────────────────────────────────────────────────

///|
/// `v` goes to `to` while the pointer is over `id`, back to `rest` once it is not (Motion's whileHover).
pub fn while_hover(c : @ui.Ctx, id : Int, v : Value, rest~ : Double, to~ : Double, spec? : Spec = spring_to()) -> Unit {
  v.follow(if c.hovered(id) { to } else { rest }, spec)
}

///|
/// `v` goes to `to` while `id` is pressed, back to `rest` once let go (Motion's whilePress / whileTap).
pub fn while_press(c : @ui.Ctx, id : Int, v : Value, rest~ : Double, to~ : Double, spec? : Spec = spring_to()) -> Unit {
  v.follow(if c.pressed(id) { to } else { rest }, spec)
}

///|
/// Motion's drag on one axis of drag area `id` (@ui.Ctx::drag_area): pressed, `v`'s animation stops where it is;
/// dragged, `v` follows the finger (past `min` or `max` by `elastic` of the way); let go, it goes on by momentum
/// (Motion's drag inertia: power 0.8, time constant 750 ms, caught by a spring at `min` and `max`) from the finger's
/// speed, or by `release` when given. `vertical` reads the finger's y.
pub fn drag_value(
  c : @ui.Ctx,
  id : Int,
  v : Value,
  vertical? : Bool = false,
  min? : Double,
  max? : Double,
  elastic? : Double = 0.5,
  release? : Spec,
) -> Unit {
  guard c.drag_of(id) is Some(d) else { return }
  let st = drag_state(c, id)
  if d.down && !st.held {
    st.held = true
    v.stop()
    st.raw = v.get()
  }
  let (dx, dy) = d.take_move()
  if d.down && d.moving {
    let moved = if vertical { dy } else { dx }
    st.raw = st.raw + moved
    let mut x = st.raw
    match min {
      Some(m) if x < m => x = m - (m - x) * elastic
      _ => ()
    }
    match max {
      Some(m) if x > m => x = m + (x - m) * elastic
      _ => ()
    }
    v.set(x)
  }
  if d.take_end() {
    st.held = false
    let along = if vertical { d.vy } else { d.vx }
    let speed = along * 1000.0
    let spec = match release {
      Some(s) => s
      None =>
        inertia_to(
          time_constant=750.0,
          bounce_stiffness=if elastic > 0.0 { 200.0 } else { 1000000.0 },
          bounce_damping=if elastic > 0.0 { 40.0 } else { 10000000.0 },
          rest_delta=1.0,
          rest_speed=10.0,
          min?=min,
          max?=max,
        )
    }
    ignore(v.start(v.get(), spec, velocity=speed))
  } else if !d.down {
    st.held = false
  }
}

///|
priv struct DragState {
  mut held : Bool
  mut raw : Double
}

///|
let drag_states : Map[Int, DragState] = Map([])

///|
fn drag_state(c : @ui.Ctx, id : Int) -> DragState {
  ignore(c)
  match drag_states.get(id) {
    Some(s) => s
    None => {
      let s = { held: false, raw: 0.0 }
      drag_states[id] = s
      s
    }
  }
}

// ── layout ──────────────────────────────────────────────────────────────

///|
/// A node animated between layouts: the box it was drawn in when its layout changed, and how far (Value 0 → 1) it has
/// gone from there to the box it is laid out in now.
priv struct LayoutFx {
  from : Box
  to : Box
  p : Value
  mut spec : Spec
  mut node : Int
  /// the build it was asked in (Ctx::build_number: its node one of that build's)
  mut build : Int
  mut known : Bool
  /// what it moves for (animate_layout's `by`) as asked this build, as last laid out, and as the frame before laid it out
  mut by : String
  mut laid_by : String
  mut was_by : String
  /// as it stood when this frame was first laid out (a frame built again moves it from there, not from what an
  /// earlier build of it set, which was never drawn), and whether a build of this frame moved it
  mut frame_at : Int
  was_from : Box
  was_to : Box
  mut was_p : Double
  mut was_known : Bool
  mut moved_now : Bool
}

///|
let layouts : Map[Int, LayoutFx] = Map([])

///|
/// Node `i` keyed `key` animates to where it is laid out for its cause (Motion's `layout` prop, the Effect way, set off
/// by what moved it): in the frame `by` (what it moves for: any value naming that state) changes, it is drawn from the
/// box it showed in (wherever an animation had got it to) and goes to its new box by `spec`, its offset and its scale
/// worked out by Motion's projection (calc_box_delta) every frame from a progress 0 → 1 that a fiber animates. Moved
/// by nothing it moves for (a window resized, a pane made narrower), it is in its new box at once, a move of its own
/// going on from there. Only drawn so (tapped where it is laid out). For a list's rows, `layout` and `list_keys`.
pub fn animate_layout(c : @ui.Ctx, i : Int, key : String, spec? : Spec = spring_to(), by? : String = "") -> Unit {
  install()
  let id = c.id("\u{5}" + key)
  let l = match layouts.get(id) {
    Some(l) => l
    None => {
      let l = {
        from: create_box(),
        to: create_box(),
        p: Value::new(1.0),
        spec,
        node: i,
        build: -1,
        known: false,
        by: "",
        laid_by: "",
        was_by: "",
        frame_at: -1,
        was_from: create_box(),
        was_to: create_box(),
        was_p: 1.0,
        was_known: false,
        moved_now: false,
      }
      layouts[id] = l
      l
    }
  }
  l.node = i
  l.spec = spec
  l.by = by
  l.build = c.build_number()
  // (asked again by a list's row kept as its nodes, of its node where it is put back: @ui.built_again)
  @ui.built_again(fn(by) {
    l.node = i + by
    l.build = @ui.current().build_number()
  })
}

///|
/// The box node `i` is laid out in.
fn laid_box(c : @ui.Ctx, i : Int) -> Box {
  let (x, y, w, h) = c.node_rect(i)
  box_of_edges(top=y, right=x + w, bottom=y + h, left=x)
}

///|
/// `into` is `from` moved and grown as `was` became `now`, edge by edge.
fn shift_box(into : Box, from : Box, was : Box, now : Box) -> Unit {
  into.x.min = from.x.min + now.x.min - was.x.min
  into.x.max = from.x.max + now.x.max - was.x.max
  into.y.min = from.y.min + now.y.min - was.y.min
  into.y.max = from.y.max + now.y.max - was.y.max
}

///|
/// The box `l` has its node drawn in now: from its last `from` to `to`, `p` of the way.
fn LayoutFx::shown(self : LayoutFx) -> Box {
  let p = self.p.get()
  {
    x: { min: mix(self.from.x.min, self.to.x.min, p), max: mix(self.from.x.max, self.to.x.max, p) },
    y: { min: mix(self.from.y.min, self.to.y.min, p), max: mix(self.from.y.max, self.to.y.max, p) },
  }
}

///|
/// Layout `l` laid out this frame (layouts_after): from where it showed to where it is, the look it is drawn by.
fn layout_moved(c : @ui.Ctx, l : LayoutFx, frame : Int) -> Unit {
    if l.frame_at != frame {
      l.frame_at = frame
      copy_box_into(l.was_from, l.from)
      copy_box_into(l.was_to, l.to)
      l.was_p = l.p.get()
      l.was_known = l.known
      l.was_by = l.laid_by
      l.moved_now = false
    }
    let now = laid_box(c, l.node)
    if !l.was_known {
      l.known = true
      copy_box_into(l.from, now)
      copy_box_into(l.to, now)
    } else if now != l.was_to && !(l.by != "" && l.was_by != "" && l.by != l.was_by) {
      // moved by what holds it, not for its cause: in its new box at once, a move of its own going on from there (the
      // box it is drawn from as far off its new place as it was off its old one)
      shift_box(l.from, l.was_from, l.was_to, now)
      copy_box_into(l.to, now)
      l.p.set(l.was_p)
      if l.was_p < 1.0 {
        ignore(l.p.start(1.0, l.spec))
      }
      l.moved_now = false
    } else if now != l.was_to {
      // from where it showed as the frame began
      let p = l.was_p
      let shown : Box = {
        x: { min: mix(l.was_from.x.min, l.was_to.x.min, p), max: mix(l.was_from.x.max, l.was_to.x.max, p) },
        y: { min: mix(l.was_from.y.min, l.was_to.y.min, p), max: mix(l.was_from.y.max, l.was_to.y.max, p) },
      }
      copy_box_into(l.from, shown)
      copy_box_into(l.to, now)
      l.p.set(0.0)
      ignore(l.p.start(1.0, l.spec))
      l.moved_now = true
    } else if l.moved_now {
      // an earlier build of this frame moved it, this one has it where it was: as it was
      l.moved_now = false
      copy_box_into(l.from, l.was_from)
      copy_box_into(l.to, l.was_to)
      l.p.set(l.was_p)
      if l.was_p < 1.0 {
        ignore(l.p.start(1.0, l.spec))
      }
    }
    l.laid_by = l.by
    if l.p.get() < 1.0 || l.p.is_animating() {
      let d = create_delta()
      calc_box_delta(d, now, l.shown())
      c.set_look(
        l.node,
        @ui.look(
          dx=d.x.translate,
          dy=d.y.translate,
          sx=d.x.scale,
          sy=d.y.scale,
          ox=d.x.origin,
          oy=d.y.origin,
        ).then(c.look_of(l.node)),
      )
    }
}

///|
/// After layout: each animated node's new box against its last; a change starts the progress from the box it showed
/// in; its look this frame is the projection from where it is laid out to where it shows.
fn layouts_after(c : @ui.Ctx) -> Unit {
  sweep_values(c)
  sweep_presences(c)
  if layouts.is_empty() {
    return
  }
  let frame = c.frame_number()
  let build = c.build_number()
  let gone : Array[Int] = []
  layouts.each(fn(id, l) {
    // (not asked in this build: not built in it, its node another's)
    if l.build != build {
      gone.push(id)
      return
    }
    // (what its move reads, read for what draws its node: the part's or the row's kept, Ctx::reads_for)
    c.reads_for(l.node, fn() { layout_moved(c, l, frame) })
  })
  for id in gone {
    match layouts.get(id) {
      Some(l) => l.p.halt()
      None => ()
    }
    layouts.remove(id)
  }
}

///|
/// What `animate_presence` was not asked for this frame (what held it is no longer built: Motion's AnimatePresence
/// unmounted) ends at once, no exit drawn: its scopes close.
fn sweep_presences(c : @ui.Ctx) -> Unit {
  if presences.is_empty() {
    return
  }
  // (not asked in this build: not built in it)
  let build = c.build_number()
  let gone : Array[Int] = []
  presences.each(fn(id, p) { if p.seen != build { gone.push(id) } })
  for id in gone {
    match presences.get(id) {
      Some(p) => {
        match p.cur {
          Some(s) => s.scope.close_now()
          None => ()
        }
        p.cur = None
      }
      None => ()
    }
    presences.remove(id)
  }
}

///|
fn reset_fx() -> Unit {
  values.clear()
  presences.clear()
  drag_states.clear()
  layouts.clear()
}
