// Motion's transitions for animate and Anim (Motion's `transition` and its `type`): spring (by physics, or by duration
// or visual duration and bounce), tween (two keyframes eased), keyframes (through values at times), inertia (a decay
// from the value's velocity, caught at min or max) — each a generator of Motion's (generators.mbt) made from where the
// value is, where it goes and how fast it moves. Beside them Compose's springs and tweens (Spec's Spring and Tween,
// still.fail's own motions); both are damped harmonic oscillators, mapped onto each other here. Motion's API is
// ported from Motion (motion.dev): Copyright (c) 2024 Motion B.V., MIT licence.

///|
/// One of Motion's transitions: its kind (for showing it), its delay (ms), and how its generator is made from the
/// value's start, its target and its velocity (per second).
pub struct Transition {
  kind : String
  delay : Double
  make : (Double, Double, Double) -> Generator
}

///|
/// The same transition (it is made by a function: the same one).
pub impl Eq for Transition with equal(self, other) {
  physical_equal(self, other)
}

///|
pub impl Show for Transition with output(self, logger) {
  logger.write_string("Transition(\{self.kind}, delay \{self.delay})")
}

///|
/// The same, after `delay` ms.
pub fn Transition::delayed(self : Transition, delay : Double) -> Transition {
  { kind: self.kind, delay, make: self.make }
}

///|
/// Its generator from `from` to `to` at `velocity` (per second).
pub fn Transition::generator(self : Transition, from : Double, to : Double, velocity : Double) -> Generator {
  (self.make)(from, to, velocity)
}

///|
/// How long a generator runs (ms): the duration it knows, else found by running it (at most 20 s).
pub fn generator_duration(g : Generator) -> Double {
  match g.calculated_duration() {
    Some(d) => d
    None => dmin(calc_generator_duration(g), max_generator_duration)
  }
}

///|
/// Motion's `{ type: "spring", … }`: by `stiffness`, `damping`, `mass`, or by `duration` (ms) or `visual_duration` (s)
/// and `bounce`; at rest within `rest_speed` and `rest_delta`. One by physics carries on as fast as the value moves.
pub fn spring_to(
  stiffness? : Double,
  damping? : Double,
  mass? : Double,
  duration? : Double,
  bounce? : Double,
  visual_duration? : Double,
  rest_speed? : Double,
  rest_delta? : Double,
  delay? : Double = 0.0,
) -> Spec {
  Motion({
    kind: "spring",
    delay,
    make: fn(from, to, v) {
      spring_generator(
        from,
        to,
        stiffness?=stiffness,
        damping?=damping,
        mass?=mass,
        velocity=v,
        duration?=duration,
        bounce?=bounce,
        visual_duration?=visual_duration,
        rest_speed?=rest_speed,
        rest_delta?=rest_delta,
      )
    },
  })
}

///|
/// Motion's `{ type: "tween", duration, ease }`: from where it is to its target over `duration` ms, eased (by default
/// easeInOut, as Motion's keyframes).
pub fn tween_to(duration? : Double = 300.0, ease? : (Double) -> Double = ease_in_out, delay? : Double = 0.0) -> Spec {
  Motion({
    kind: "tween",
    delay,
    make: fn(from, to, _) { keyframes_generator([from, to], duration~, ease~) },
  })
}

///|
/// Motion's keyframes: from where it is through `values` (the last where it ends: the target asked is not used) over
/// `duration` ms, at `times` (offsets 0 … 1 of the start and each value), eased by `ease` or each piece by its own.
pub fn keyframes_to(
  values : Array[Double],
  duration? : Double = 300.0,
  times? : Array[Double],
  ease? : (Double) -> Double,
  eases? : Array[(Double) -> Double],
  delay? : Double = 0.0,
) -> Spec {
  Motion({
    kind: "keyframes",
    delay,
    make: fn(from, _, _) {
      let all = [from]
      for v in values {
        all.push(v)
      }
      keyframes_generator(all, duration~, times?=times, ease?=ease, eases?=eases)
    },
  })
}

///|
/// Motion's `{ type: "inertia", … }`: on from where it is as fast as it moves, `power` × its velocity further, closing in
/// by `time_constant` (the target asked is not used; `modify_target` changes where it ends: a snap point), sprung back
/// at `min` or `max`.
pub fn inertia_to(
  power? : Double = 0.8,
  time_constant? : Double = 325.0,
  bounce_damping? : Double = 10.0,
  bounce_stiffness? : Double = 500.0,
  modify_target? : (Double) -> Double,
  min? : Double,
  max? : Double,
  rest_delta? : Double = 0.5,
  rest_speed? : Double,
  delay? : Double = 0.0,
) -> Spec {
  Motion({
    kind: "inertia",
    delay,
    make: fn(from, _, v) {
      inertia_generator(
        from,
        velocity=v,
        power~,
        time_constant~,
        bounce_damping~,
        bounce_stiffness~,
        modify_target?=modify_target,
        min?=min,
        max?=max,
        rest_delta~,
        rest_speed?=rest_speed,
      )
    },
  })
}

// ── Compose's springs and Motion's ──────────────────────────────────────

///|
/// Compose's spring (damping ratio, stiffness; mass 1) as Motion's physics: (stiffness, damping, mass).
pub fn compose_to_motion(ratio : Double, stiffness : Double) -> (Double, Double, Double) {
  (stiffness, 2.0 * ratio * stiffness.sqrt(), 1.0)
}

///|
/// Motion's physics (stiffness, damping, mass) as Compose's spring: (damping ratio, stiffness at mass 1).
pub fn motion_to_compose(stiffness : Double, damping : Double, mass : Double) -> (Double, Double) {
  (damping / (2.0 * (stiffness * mass).sqrt()), stiffness / mass)
}

///|
/// Motion's spring by visual duration and bounce as Compose's (damping ratio, stiffness): Motion.kt's motionSpring
/// (bounce from 0 up; a negative one overdamps, its stiffness scaled so it arrives when the critically damped one
/// would).
pub fn visual_to_compose(visual_duration : Double, bounce : Double) -> (Double, Double) {
  let ratio = bounce_to_damping_ratio(bounce)
  let root = two_pi / (visual_duration * 1.2) * overdamped_freq_scale(ratio, two_pi / 1.2)
  (ratio, root * root)
}
