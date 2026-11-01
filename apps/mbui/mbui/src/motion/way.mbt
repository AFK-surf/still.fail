// A number's way, said once as it sets out: from where, how fast, to where, by what, from when (its cause's moment).
// Where it is at any moment is worked out from that alone, by Spec::value_at, whatever frames were drawn or sampled
// ahead: a new way said at a moment sets out from where the one before has it then, not from where a frame last left
// it. Nothing runs it: no fiber, no frame steps it, nothing marks it done; it is at its end from its end on, and what
// is to happen at its end is said by its owner on the owner's timeline (a node of the window's tree's: View::at_moment).
// What reads it asks for frames as it reads it while it goes (Way::get: an old view built again each frame; a tree's
// binding reading the moment it is drawn at): nothing else is kept going for it.

///|
pub struct Way {
  priv mut from : Double
  priv mut v0 : Double
  priv mut to : Double
  priv mut spec : Spec
  /// when it set out (ms, the one clock: its whole ms, the grid every motion's time goes on), and how long it goes
  priv mut start : Double
  priv mut dur : Double
  priv mover : @ui.Mover
  /// told as a way is said (gone on, put): what works out where it is at a moment follows it by reading it (Way::said)
  priv told : @signals.Signal[Int]
}

///|
/// At `v`, still.
pub fn Way::new(v : Double) -> Way {
  {
    from: v,
    v0: 0.0,
    to: v,
    spec: Snap(0.0),
    start: 0.0,
    dur: 0.0,
    mover: @ui.Mover::new(),
    told: @signals.signal(0),
  }
}

///|
/// Where it is at `t` (ms, the one clock) and how fast (per second): before it set out, where it set out from; after
/// its end, at its end.
pub fn Way::at(self : Way, t : Double) -> (Double, Double) {
  if self.dur <= 0.0 {
    (self.to, 0.0)
  } else if t >= self.end() {
    // (at its end: where its spec has it once its length is out (Spec::value_at at a whole ms past it), which a way of
    // its own (inertia) may make other than where it was sent; still)
    (self.spec.value_at(self.dur.ceil(), self.dur, self.from, self.to, self.v0).0, 0.0)
  } else if t <= self.start {
    (self.from, self.v0)
  } else {
    // (its time in whole ms of the one clock: where it is at a moment the same whatever fraction of a ms the moment
    // or its cause came at, as any motion's, Run's)
    self.spec.value_at(@ui.whole_ms(t) - self.start, self.dur, self.from, self.to, self.v0)
  }
}

///|
/// Where it is at `t`.
pub fn Way::value_at(self : Way, t : Double) -> Double {
  self.at(t).0
}

///|
/// Where it goes.
pub fn Way::target(self : Way) -> Double {
  self.to
}

///|
/// When it is there (its time goes in whole ms, Spec::value_at: at the first whole ms its length is out).
pub fn Way::end(self : Way) -> Double {
  self.start + self.dur.ceil()
}

///|
/// When it set out, as it was told; -1 for one put there at once.
pub fn Way::starts_at(self : Way) -> Double {
  if self.dur > 0.0 {
    self.start
  } else {
    -1.0
  }
}

///|
/// When it is there, as it was told; -1 for one put there at once.
pub fn Way::ends_at(self : Way) -> Double {
  if self.dur > 0.0 {
    self.end()
  } else {
    -1.0
  }
}

///|
/// Whether it still goes at `t`.
pub fn Way::goes_at(self : Way, t : Double) -> Bool {
  self.dur > 0.0 && t < self.end()
}

///|
/// Off to `target` by `spec` from the moment `at` (its cause's), from where it is then and as fast (or at `velocity`,
/// per second). With motion reduced (Ctx::still), there at once, as any motion is. What reads it asks for the frames
/// it needs as it reads it (Way::get, Way::said): nothing of its own goes on.
#callsite(autofill(loc))
pub fn Way::go(
  self : Way,
  target : Double,
  spec : Spec,
  at~ : Double,
  velocity? : Double,
  loc~ : SourceLoc,
) -> Unit {
  let (x, v) = self.at(at)
  self.from = x
  self.v0 = velocity.unwrap_or(v)
  self.to = target
  self.spec = spec
  self.start = @ui.whole_ms(at)
  self.dur = if @ui.current().still() { 0.0 } else { spec.duration(x, target, self.v0) }
  self.mover.changed()
  // (who it is for the performance record: who sent it, not where to)
  self.mover.told_as("a Way", loc)
  self.told.set(@signals.untracked(fn() { self.told.get() }) + 1)
}

///|
/// There at once, still: at any moment.
pub fn Way::put(self : Way, v : Double) -> Unit {
  // (there already, still: nothing said, nothing told)
  if self.from == v && self.to == v && self.dur <= 0.0 {
    return
  }
  self.mover.changed()
  self.from = v
  self.to = v
  self.v0 = 0.0
  self.spec = Snap(0.0)
  self.start = 0.0
  self.dur = 0.0
  self.told.set(@signals.untracked(fn() { self.told.get() }) + 1)
}

///|
/// Read where what is worked out from where it is follows each way said of it (a binding of a node of the window's
/// tree's: sampling it at the moment its frame is drawn while it goes, none after).
pub fn Way::said(self : Way) -> Unit {
  self.told.get() |> ignore
}

///|
/// Where it is as what is built or drawn now reads it (the frame's moment): read again each frame while it goes, as a
/// motion's value is (Anim::get).
pub fn Way::get(self : Way) -> Double {
  self.said()
  let c = @ui.current()
  let t = c.moment()
  c.shows_motion(self.mover, self.goes_at(t))
  self.value_at(t)
}
