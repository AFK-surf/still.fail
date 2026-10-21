// Motion's keyframe generators (motion-dom src/animation/generators): spring (by stiffness, damping and mass, or by
// duration or visual duration and bounce, Motion's own conversion between the two), inertia (a decay by power and time
// constant, its target modifiable, caught by a spring at min or max), keyframes (values at times, eased piece by
// piece), and their utilities (a generator's duration, its keyframes, its velocity, an easing made of one, CSS's
// linear() of one). A generator gives its value at a time (ms) from its start, and whether it is done. Ported from
// Motion (motion.dev, github.com/motiondivision/motion): Copyright (c) 2024 Motion B.V., MIT licence; the comments
// say what Motion's say.

///|
/// A generator's value at a time, and whether it is done (Motion's AnimationState).
pub(all) struct GenState {
  done : Bool
  value : Double
} derive(Eq, Show, Debug)

///|
/// Values over time (Motion's KeyframeGenerator): `next(t)` its state at `t` ms from its start, `velocity(t)` (per
/// second) where it knows it, its duration when it is known beforehand (a spring by duration, keyframes), and, for a
/// spring, aimed anew from where it is (`retarget`).
pub struct Generator {
  priv next_ : (Double) -> GenState
  priv velocity_ : ((Double) -> Double)?
  priv retarget_ : ((Double, Double, Double) -> Unit)?
  priv duration_ : Double?
  priv mut calculated : Double?
}

///|
/// Its state `t` ms after its start.
pub fn Generator::next(self : Generator, t : Double) -> GenState {
  (self.next_)(t)
}

///|
/// The duration it knows beforehand (ms; None when it is found by running it: Motion's calculatedDuration).
pub fn Generator::calculated_duration(self : Generator) -> Double? {
  self.calculated
}

///|
/// Its velocity (per second) at `t` ms: its own where it has one (a spring's, analytic), else over the 5 ms before
/// (Motion's calcGeneratorVelocity); before it starts, `initial`.
pub fn Generator::velocity(self : Generator, t : Double, initial? : Double = 0.0) -> Double {
  if t <= 0.0 {
    return initial
  }
  match self.velocity_ {
    Some(v) => v(t)
    None => {
      let prev = if t - 5.0 > 0.0 { t - 5.0 } else { 0.0 }
      velocity_per_second(self.next(t).value - self.next(prev).value, t - prev)
    }
  }
}

///|
/// Whether it can be aimed anew mid-way (a spring).
pub fn Generator::can_retarget(self : Generator) -> Bool {
  self.retarget_ is Some(_)
}

///|
/// Aimed anew: from `from` to `to`, at `velocity` (per second), keeping its physics (a spring; Motion's retarget).
pub fn Generator::retarget(self : Generator, from : Double, to : Double, velocity : Double) -> Unit {
  match self.retarget_ {
    Some(r) => {
      self.calculated = self.duration_
      r(from, to, velocity)
    }
    None => ()
  }
}

// ── spring ──────────────────────────────────────────────────────────────

///|
let spring_default_stiffness : Double = 100.0

///|
let spring_default_damping : Double = 10.0

///|
let spring_default_mass : Double = 1.0

///|
let spring_default_duration : Double = 800.0

///|
let spring_default_bounce : Double = 0.3

///|
let spring_min_damping : Double = 0.05

///|
let two_pi : Double = 6.283185307179586

///|
/// Bounce as a damping ratio, as SwiftUI maps it: 0 critically damped, towards undamped as it nears 1, infinitely
/// overdamped towards −1; both ends limited so the spring still moves and settles.
pub fn bounce_to_damping_ratio(bounce : Double) -> Double {
  if bounce < 0.0 {
    1.0 / dmax(1.0 + bounce, spring_min_damping)
  } else {
    dmax(1.0 - bounce, spring_min_damping)
  }
}

///|
fn calc_angular_freq(undamped : Double, ratio : Double) -> Double {
  undamped * (1.0 - ratio * ratio).sqrt()
}

///|
fn approximate_root(
  envelope : (Double) -> Double,
  derivative : (Double) -> Double,
  guess : Double,
) -> Double {
  let mut result = guess
  for _ in 1..<12 {
    result = result - envelope(result) / derivative(result)
  }
  result
}

///|
/// Scales an overdamped spring's undamped frequency so that, at its defining time, it has as far left to go as the
/// critically damped spring `critical_freq_time` radians in by then (a negative bounce changes the curve's shape, not
/// when it arrives). 1 at a damping ratio of 1. Newton's steps on the distance left, from below.
fn overdamped_freq_scale(ratio : Double, critical_freq_time : Double) -> Double {
  if !(ratio > 1.0) {
    return 1.0
  }
  let root = (ratio * ratio - 1.0).sqrt()
  let slow = ratio - root
  let fast = ratio + root
  let target = 2.0 * root * @dmath.exp(-critical_freq_time) * (1.0 + critical_freq_time)
  approximate_root(
    fn(ft) { fast * @dmath.exp(-slow * ft) - slow * @dmath.exp(-fast * ft) - target },
    fn(ft) { @dmath.exp(-fast * ft) - @dmath.exp(-slow * ft) },
    critical_freq_time,
  ) /
  critical_freq_time
}

///|
let safe_min : Double = 0.001

///|
/// A spring by its duration (ms) and bounce, as stiffness and damping at mass 1 (Motion's findSpring, from Framer's
/// duration-based springs): (stiffness, damping, duration ms, the duration clamped to 10 ms … 10 s). NaN when the
/// root search does not converge.
pub fn find_spring(duration : Double, bounce : Double) -> (Double, Double, Double) {
  let ratio = bounce_to_damping_ratio(bounce)
  let dur = clamp(0.01, 10.0, ms_to_seconds(duration))
  let (envelope, derivative) : ((Double) -> Double, (Double) -> Double) = if ratio < 1.0 {
    // underdamped
    let envelope = fn(u : Double) {
      let decay = u * ratio
      let delta = decay * dur
      let b = calc_angular_freq(u, ratio)
      let c = @dmath.exp(-delta)
      safe_min - decay / b * c
    }
    let derivative = fn(u : Double) {
      let decay = u * ratio
      let delta = decay * dur
      let e = ratio * ratio * u * u * dur
      let f = @dmath.exp(-delta)
      let g = calc_angular_freq(u * u, ratio)
      let factor = if -envelope(u) + safe_min > 0.0 { -1.0 } else { 1.0 }
      factor * -e * f / g
    }
    (envelope, derivative)
  } else {
    // critically damped (overdamped springs scale this root, below)
    (
      fn(u : Double) {
        let a = @dmath.exp(-u * dur)
        let b = u * dur + 1.0
        -safe_min + a * b
      },
      fn(u : Double) {
        let a = @dmath.exp(-u * dur)
        let b = -u * (dur * dur)
        a * b
      },
    )
  }
  let critical = approximate_root(envelope, derivative, 5.0 / dur)
  let undamped = critical * overdamped_freq_scale(ratio, critical * dur)
  let stiffness = undamped * undamped
  (stiffness, ratio * 2.0 * stiffness.sqrt(), seconds_to_ms(dur))
}

///|
/// Usable physics: finite, and positive (or, for damping, 0 or more).
fn valid_physics(v : Double?, can_be_zero? : Bool = false) -> Bool {
  match v {
    Some(x) => (if can_be_zero { x >= 0.0 } else { x > 0.0 }) && x < @double.infinity
    None => false
  }
}

///|
/// JavaScript's truthiness of a number that may be absent: not absent, 0 or NaN.
fn truthy(v : Double?) -> Bool {
  match v {
    Some(x) => x != 0.0 && !x.is_nan()
    None => false
  }
}

///|
/// `v` as JavaScript's `v || d` has it.
fn or_else(v : Double?, d : Double) -> Double {
  match v {
    Some(x) if truthy(Some(x)) => x
    _ => d
  }
}

///|
/// A spring's options resolved (Motion's getSpringOptions): its physics (invalid ones fall back to the defaults, a
/// time-defined spring's derived from its duration or visual duration and bounce), whether it was resolved from a
/// duration (and is done at it), and whether it is time-defined (it ignores the velocity it inherits).
priv struct SpringResolved {
  stiffness : Double
  damping : Double
  mass : Double
  duration : Double?
  from_duration : Bool
  time_defined : Bool
}

///|
fn resolve_spring(
  stiffness : Double?,
  damping : Double?,
  mass : Double?,
  duration : Double?,
  bounce : Double?,
  visual_duration : Double?,
) -> SpringResolved {
  let vs = if valid_physics(stiffness) { stiffness } else { None }
  let vd = if valid_physics(damping, can_be_zero=true) { damping } else { None }
  let vm = if valid_physics(mass) { mass } else { None }
  let mut k = vs.unwrap_or(spring_default_stiffness)
  let mut d = vd.unwrap_or(spring_default_damping)
  let m = vm.unwrap_or(spring_default_mass)
  let mut dur = duration
  let mut from_duration = false
  // stiffness, damping or mass given override duration and bounce
  let time_defined = vs is None &&
    vd is None &&
    vm is None &&
    (duration is Some(_) || bounce is Some(_))
  if time_defined {
    if truthy(visual_duration) {
      let ratio = bounce_to_damping_ratio(or_else(bounce, 0.0))
      let root = two_pi / (visual_duration.unwrap() * 1.2) * overdamped_freq_scale(ratio, two_pi / 1.2)
      k = root * root
      d = 2.0 * ratio * k.sqrt()
    } else {
      let (k1, d1, dur1) = find_spring(
        duration.unwrap_or(spring_default_duration),
        bounce.unwrap_or(spring_default_bounce),
      )
      k = k1
      d = d1
      dur = Some(dur1)
      from_duration = true
    }
    // time options can degenerate (a NaN bounce, an infinite visual duration, no convergence): both replaced together
    if !valid_physics(Some(k)) || !valid_physics(Some(d), can_be_zero=true) {
      k = spring_default_stiffness
      d = spring_default_damping
    }
  }
  { stiffness: k, damping: d, mass: m, duration: dur, from_duration, time_defined }
}

///|
/// What changes when a spring is aimed anew.
priv struct SpringNow {
  mut target : Double
  mut delta : Double
  /// −(velocity per ms)
  mut velocity : Double
  mut rest_speed : Double
  mut rest_delta : Double
  // coefficients
  mut a : Double
  mut b : Double
  mut c : Double
}

///|
/// A spring from `from` to `to` (Motion's spring generator): by `stiffness`, `damping`, `mass` (defaults 100, 10, 1),
/// or by `duration` (ms) or `visual_duration` (s) and `bounce` (then it ignores `velocity`); `velocity` per second; at
/// rest within `rest_speed` (per second) and `rest_delta` (by default 2 and .5, or .01 and .005 for a change under 5).
/// One by its duration is done at it.
pub fn spring_generator(
  from : Double,
  to : Double,
  stiffness? : Double,
  damping? : Double,
  mass? : Double,
  velocity? : Double,
  duration? : Double,
  bounce? : Double,
  visual_duration? : Double,
  rest_speed? : Double,
  rest_delta? : Double,
) -> Generator {
  let o = resolve_spring(stiffness, damping, mass, duration, bounce, visual_duration)
  let inherit = fn(v : Double) { if o.time_defined { 0.0 } else { -ms_to_seconds(v) } }
  let ratio = o.damping / (2.0 * (o.stiffness * o.mass).sqrt())
  let undamped = ms_to_seconds((o.stiffness / o.mass).sqrt())
  let decay = ratio * undamped
  let v0 = inherit(or_else(velocity, 0.0))
  let s : SpringNow = {
    target: to,
    delta: to - from,
    velocity: if v0.is_nan() || v0 == 0.0 { 0.0 } else { v0 },
    rest_speed: 0.0,
    rest_delta: 0.0,
    a: 0.0,
    b: 0.0,
    c: 0.0,
  }
  // on a granular scale, smaller defaults for when it is done
  let set_rest = fn() {
    let granular = s.delta.abs() < 5.0
    s.rest_speed = or_else(rest_speed, if granular { 0.01 } else { 2.0 })
    s.rest_delta = or_else(rest_delta, if granular { 0.005 } else { 0.5 })
  }
  set_rest()
  let (update, at, vel) : (() -> Unit, (Double) -> Double, (Double) -> Double) = if ratio < 1.0 {
    // underdamped: a the position's coefficient, b and c those of its derivative (per ms)
    let w = calc_angular_freq(undamped, ratio)
    (
      fn() {
        s.a = (s.velocity + decay * s.delta) / w
        s.b = decay * s.a + s.delta * w
        s.c = decay * s.delta - s.a * w
      },
      fn(t : Double) {
        let env = @dmath.exp(-decay * t)
        s.target - env * (s.a * @dmath.sin(w * t) + s.delta * @dmath.cos(w * t))
      },
      fn(t : Double) {
        let env = @dmath.exp(-decay * t)
        env * (s.b * @dmath.sin(w * t) + s.c * @dmath.cos(w * t))
      },
    )
  } else if ratio == 1.0 {
    // critically damped
    (
      fn() { s.a = s.velocity + undamped * s.delta },
      fn(t : Double) {
        s.target - @dmath.exp(-undamped * t) * (s.delta + (s.velocity + undamped * s.delta) * t)
      },
      fn(t : Double) { @dmath.exp(-undamped * t) * (undamped * s.a * t - s.velocity) },
    )
  } else {
    // overdamped: a slow and a fast decaying exponential, so no term overflows however heavily it is damped. Springs
    // by physics keep a non-physical limit: past 300 radians both decay at the damping rate (heavily overdamped drag
    // springs settle almost at once); time-defined ones need the exact curve
    let damped = undamped * (ratio * ratio - 1.0).sqrt()
    let slow = decay - damped
    let fast = decay + damped
    let limit = if o.time_defined { @double.infinity } else { 300.0 / damped }
    let decay_at = fn(rate : Double, t : Double) {
      @dmath.exp(if t > limit { -rate * limit - decay * (t - limit) } else { -rate * t })
    }
    (
      fn() {
        let p = (s.velocity + decay * s.delta) / damped
        s.a = (s.delta + p) / 2.0
        s.b = (s.delta - p) / 2.0
      },
      fn(t : Double) { s.target - s.a * decay_at(slow, t) - s.b * decay_at(fast, t) },
      fn(t : Double) { slow * s.a * decay_at(slow, t) + fast * s.b * decay_at(fast, t) },
    )
  }
  update()
  let calculated = if o.from_duration {
    match o.duration {
      Some(d) if d != 0.0 => Some(d)
      _ => None
    }
  } else {
    None
  }
  let next = fn(t : Double) -> GenState {
    let current = at(t)
    let done = if !o.from_duration {
      seconds_to_ms(vel(t)).abs() <= s.rest_speed && (s.target - current).abs() <= s.rest_delta
    } else {
      t >= o.duration.unwrap()
    }
    GenState::{ done, value: if done { s.target } else { current } }
  }
  {
    next_: next,
    velocity_: Some(fn(t) { seconds_to_ms(vel(t)) }),
    retarget_: Some(fn(from, to, v) {
      s.target = to
      s.delta = to - from
      s.velocity = inherit(v)
      // the default thresholds depend on the new change's scale
      if !(truthy(rest_speed) && truthy(rest_delta)) {
        set_rest()
      }
      update()
    }),
    duration_: calculated,
    calculated,
  }
}

///|
/// Motion's spring(visualDuration, bounce) shorthand: from 0 to 1.
pub fn spring_visual(visual_duration? : Double = 0.3, bounce? : Double = 0.3) -> Generator {
  spring_generator(0.0, 1.0, visual_duration~, bounce~)
}

// ── inertia ─────────────────────────────────────────────────────────────

///|
priv struct InertiaNow {
  mut done : Bool
  mut value : Double
  mut reached : Double?
  mut spring : Generator?
}

///|
/// A decay from `from` (Motion's inertia): it goes `power` × `velocity` (per second) further, closing in on that by
/// e^(−t/time_constant), the target `modify_target`'s of where it would end; done within `rest_delta`. Past `min` or
/// `max` a spring (`bounce_stiffness`, `bounce_damping`) takes it to the nearer of them, from its speed there.
pub fn inertia_generator(
  from : Double,
  velocity? : Double = 0.0,
  power? : Double = 0.8,
  time_constant? : Double = 325.0,
  bounce_damping? : Double = 10.0,
  bounce_stiffness? : Double = 500.0,
  modify_target? : (Double) -> Double,
  min? : Double,
  max? : Double,
  rest_delta? : Double = 0.5,
  rest_speed? : Double,
) -> Generator {
  let state : InertiaNow = { done: false, value: from, reached: None, spring: None }
  let out_of_bounds = fn(v : Double) {
    (match min {
      Some(m) => v < m
      None => false
    }) ||
    (match max {
      Some(m) => v > m
      None => false
    })
  }
  let nearest = fn(v : Double) {
    match (min, max) {
      (None, Some(hi)) => hi
      (Some(lo), None) => lo
      (Some(lo), Some(hi)) => if (lo - v).abs() < (hi - v).abs() { lo } else { hi }
      (None, None) => v
    }
  }
  let mut amplitude = power * velocity
  let ideal = from + amplitude
  let target = match modify_target {
    Some(f) => f(ideal)
    None => ideal
  }
  // a changed target: the amplitude anew, or it starts from the wrong place
  if target != ideal {
    amplitude = target - from
  }
  let amp = amplitude
  let calc_delta = fn(t : Double) { -amp * @dmath.exp(-t / time_constant) }
  let apply_friction = fn(t : Double) {
    let delta = calc_delta(t)
    state.done = delta.abs() <= rest_delta
    state.value = if state.done { target } else { target + delta }
  }
  let check_catch = fn(t : Double) {
    if !out_of_bounds(state.value) {
      return
    }
    state.reached = Some(t)
    // the friction curve is target + calc_delta(t): its derivative −calc_delta(t) / time_constant per ms
    state.spring = Some(
      spring_generator(
        state.value,
        nearest(state.value),
        velocity=-calc_delta(t) / time_constant * 1000.0,
        damping=bounce_damping,
        stiffness=bounce_stiffness,
        rest_delta~,
        rest_speed?=rest_speed,
      ),
    )
  }
  check_catch(0.0)
  let next = fn(t : Double) -> GenState {
    // the friction resolved once a frame, to see whether a spring takes over
    let mut updated = false
    if state.spring is None && state.reached is None {
      updated = true
      apply_friction(t)
      check_catch(t)
    }
    match (state.reached, state.spring) {
      (Some(r), Some(sp)) if t >= r => sp.next(t - r)
      _ => {
        if !updated {
          apply_friction(t)
        }
        GenState::{ done: state.done, value: state.value }
      }
    }
  }
  { next_: next, velocity_: None, retarget_: None, duration_: None, calculated: None }
}

// ── keyframes ───────────────────────────────────────────────────────────

///|
/// The offsets keyframes are at by default: evenly from 0 to 1 (Motion's defaultOffset).
pub fn default_offset(count : Int) -> Array[Double] {
  let offset = [0.0]
  fill_offset(offset, count - 1)
  offset
}

///|
/// `remaining` offsets more, evenly from the last to 1 (Motion's fillOffset).
pub fn fill_offset(offset : Array[Double], remaining : Int) -> Unit {
  let min = offset[offset.length() - 1]
  for i in 1..=remaining {
    offset.push(mix(min, 1.0, progress(0.0, remaining.to_double(), i.to_double())))
  }
}

///|
/// Offsets (0 … 1) as times in a `duration` (Motion's convertOffsetToTimes).
pub fn offsets_to_times(offset : Array[Double], duration : Double) -> Array[Double] {
  offset.map(fn(o) { o * duration })
}

///|
/// The easings of the pieces between `count` keyframes: `easing` (by default easeInOut) for each (Motion's
/// defaultEasing).
pub fn default_easing(count : Int, easing? : (Double) -> Double) -> Array[(Double) -> Double] {
  let e = easing.unwrap_or(ease_in_out)
  Array::makei(if count > 1 { count - 1 } else { 0 }, fn(_) { e })
}

///|
/// Through `values` over `duration` ms (Motion's keyframes generator): at `times` (offsets 0 … 1, by default even;
/// used when there is one for each value), each piece eased by `ease` (by default easeInOut) or by its own of `eases`.
pub fn keyframes_generator(
  values : Array[Double],
  duration? : Double = 300.0,
  times? : Array[Double],
  ease? : (Double) -> Double,
  eases? : Array[(Double) -> Double],
) -> Generator {
  let easing = ease.unwrap_or(ease_in_out)
  let plain_times = match times {
    None => true
    Some(ts) => ts.length() != 2 || (ts[0] == 0.0 && ts[1] == 1.0)
  }
  if values.length() == 2 && eases is None && plain_times {
    // two keyframes, one easing
    let origin = values[0]
    let target = values[1]
    let next = fn(t : Double) -> GenState {
      let value = if origin == target {
        target
      } else {
        mix(origin, target, easing(if duration > 0.0 { clamp(0.0, 1.0, t / duration) } else { 1.0 }))
      }
      GenState::{ done: t >= duration, value }
    }
    return { next_: next, velocity_: None, retarget_: None, duration_: Some(duration), calculated: Some(duration) }
  }
  let offsets = match times {
    Some(ts) if ts.length() == values.length() => ts
    _ => default_offset(values.length())
  }
  let map = interpolate(offsets_to_times(offsets, duration), values, eases=match eases {
    Some(es) => es
    None => default_easing(values.length(), easing~)
  })
  {
    next_: fn(t) { GenState::{ done: t >= duration, value: map(t) } },
    velocity_: None,
    retarget_: None,
    duration_: Some(duration),
    calculated: Some(duration),
  }
}

// ── what is known of a generator ────────────────────────────────────────

///|
/// The longest a generator is run to find its duration (ms).
pub let max_generator_duration : Double = 20000.0

///|
/// How long it runs (ms), stepped by `time_step` until done (Motion's calcGeneratorDuration): infinity past
/// `max_duration`. Its values on the way pushed into `keyframes`.
pub fn calc_generator_duration(
  g : Generator,
  time_step? : Double = 50.0,
  max_duration? : Double = max_generator_duration,
  keyframes? : Array[Double],
) -> Double {
  let mut duration = 0.0
  let mut state = g.next(duration)
  match keyframes {
    Some(k) => k.push(state.value)
    None => ()
  }
  while !state.done && duration < max_duration {
    duration = duration + time_step
    state = g.next(duration)
    match keyframes {
      Some(k) => k.push(state.value)
      None => ()
    }
  }
  if duration >= max_duration {
    @double.infinity
  } else {
    duration
  }
}

///|
/// Its values every 10 ms until done (at most 10 s), and how long that is in seconds (Motion's pregenerateKeyframes):
/// one that did not move gives its value twice.
pub fn pregenerate_keyframes(g : Generator) -> (Array[Double], Double) {
  let keyframes : Array[Double] = []
  let d = calc_generator_duration(g, time_step=10.0, max_duration=10000.0, keyframes~)
  if keyframes.length() == 1 {
    keyframes.push(keyframes[0])
  }
  (keyframes, ms_to_seconds(dmin(d, 10000.0)))
}

///|
/// A generator from 0 to `scale` as an easing of progress, and how long it runs (s) (Motion's createGeneratorEasing):
/// `make(from, to, velocity)` gives it; `velocity` (in the value's own units, going from `from` to `to`) scaled to the
/// easing's range.
pub fn generator_easing(
  make : (Double, Double, Double) -> Generator,
  from : Double,
  to : Double,
  velocity? : Double = 0.0,
  scale? : Double = 100.0,
) -> ((Double) -> Double, Double) {
  let delta = to - from
  let v = if velocity != 0.0 && delta != 0.0 { velocity * scale / delta } else { velocity }
  let g = make(0.0, scale, v)
  let duration = dmin(calc_generator_duration(g), max_generator_duration)
  (fn(p) { g.next(duration * p).value / scale }, ms_to_seconds(duration))
}

///|
/// A number as JavaScript writes it (whole ones without a point, −0 as 0).
fn js_number(x : Double) -> String {
  if x == @math.floor(x) && x.abs() < 1.0e15 {
    x.to_int64().to_string()
  } else {
    x.to_string()
  }
}

///|
/// JavaScript's Math.round: halves up.
fn js_round(x : Double) -> Double {
  @math.floor(x + 0.5)
}

///|
/// CSS's linear() of an easing over `duration` ms, a point every `resolution` ms (Motion's generateLinearEasing).
pub fn linear_easing(easing : (Double) -> Double, duration : Double, resolution? : Double = 10.0) -> String {
  let n = dmax(js_round(duration / resolution), 2.0).to_int()
  let points = Array::makei(n, fn(i) { js_number(js_round(easing(i.to_double() / (n - 1).to_double()) * 10000.0) / 10000.0) })
  "linear(" + points.join(", ") + ")"
}

///|
/// Its duration and CSS's linear() of it, a point every 30 ms (Motion's spring toString): `1100ms linear(0, …, 1)`.
pub fn Generator::to_css(self : Generator) -> String {
  let d = dmin(calc_generator_duration(self), max_generator_duration)
  js_number(d) + "ms " + linear_easing(fn(p) { self.next(d * p).value }, d, resolution=30.0)
}
