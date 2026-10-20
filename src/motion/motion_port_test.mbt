// Motion's own unit tests, ported: the same inputs and the same expected numbers, from motion-dom
// (src/animation/generators/__tests__: spring, inertia, keyframes; generators/utils/__tests__:
// create-generator-easing; src/utils/__tests__/interpolate; src/utils/mix/__tests__/mix-number) and motion-utils
// (src/__tests__: progress, clamp, wrap, velocity-per-second; src/easing/__tests__: anticipate, circ, cubic-bezier,
// steps; src/easing/modifiers/__tests__: mirror, reverse), at github.com/motiondivision/motion ce1d082.
//
// Ported from Motion (motion.dev, formerly Framer Motion), MIT licence:
// Copyright (c) 2024 Motion B.V. Permission is hereby granted, free of charge, to any person obtaining a copy of this
// software and associated documentation files (the "Software"), to deal in the Software without restriction,
// including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following
// conditions: The above copyright notice and this permission notice shall be included in all copies or substantial
// portions of the Software. THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED.
//
// Left out, as not mbui's: mixing strings, colours, objects and arrays (what is animated here is a number), easings by
// CSS's own keywords, warnings on the console, numeric strings as physics. Then Compose's springs against Motion's
// (both damped harmonic oscillators) and Motion's transitions played by animate, frame by frame.

///|
/// jest's toBeCloseTo(b, digits): within half of 10^−digits.
fn close(a : Double, b : Double, digits? : Int = 2) -> Bool {
  (a - b).abs() < @math.pow(10.0, -digits.to_double()) / 2.0
}

///|
/// JavaScript's Math.round (halves up).
fn round_js(x : Double) -> Double {
  @math.floor(x + 0.5)
}

///|
/// Motion's animateSync: the generator every `time_step` ms until done, rounded.
fn animate_sync(g : @motion.Generator, time_step? : Double = 200.0, round? : Bool = true) -> Array[Double] {
  let out = []
  let mut step = 0
  let mut done = false
  while !done {
    let latest = g.next(step.to_double() * time_step)
    out.push(if round { round_js(latest.value) } else { latest.value })
    done = latest.done
    step = step + 1
  }
  out
}

///|
fn nan() -> Double {
  0.0 / 0.0
}

///|
fn inf() -> Double {
  1.0 / 0.0
}

// ── spring (motion-dom generators/__tests__/spring.test.ts) ─────────────

///|
/// A spring by one of the option sets the tests use, from `from` to `to`.
priv struct Opts {
  stiffness : Double?
  damping : Double?
  mass : Double?
  duration : Double?
  bounce : Double?
  visual : Double?
}

///|
fn opts(
  stiffness? : Double,
  damping? : Double,
  mass? : Double,
  duration? : Double,
  bounce? : Double,
  visual? : Double,
) -> Opts {
  Opts::{ stiffness, damping, mass, duration, bounce, visual }
}

///|
fn spring_of(o : Opts, from : Double, to : Double, velocity? : Double) -> @motion.Generator {
  @motion.spring_generator(
    from,
    to,
    stiffness?=o.stiffness,
    damping?=o.damping,
    mass?=o.mass,
    velocity?=velocity,
    duration?=o.duration,
    bounce?=o.bounce,
    visual_duration?=o.visual,
  )
}

///|
test "spring: retargeting matches a new spring" {
  for o in [
    opts(stiffness=100.0, damping=10.0),
    opts(stiffness=100.0, damping=20.0),
    opts(stiffness=100.0, damping=30.0),
    opts(duration=600.0, bounce=0.3),
    opts(visual=0.4, bounce=0.3),
    opts(duration=600.0, bounce=-0.5),
    opts(visual=0.4, bounce=-0.5),
  ] {
    let g = spring_of(o, 0.0, 100.0)
    for kf in [(20.0, -50.0), (0.0, 1.0), (100.0, 300.0)] {
      g.next(16.0) |> ignore
      g.retarget(kf.0, kf.1, 300.0)
      let fresh = spring_of(o, kf.0, kf.1, velocity=300.0)
      for t in [0.0, 16.0, 100.0, 300.0, 1000.0, 2000.0] {
        assert_eq(g.next(t), fresh.next(t))
        assert_eq(g.velocity(t), fresh.velocity(t))
      }
    }
  }
}

///|
test "spring: runs animations with default values" {
  assert_eq(animate_sync(@motion.spring_generator(0.0, 1.0)), [0.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0])
}

///|
test "spring: underdamped spring" {
  assert_eq(
    animate_sync(@motion.spring_generator(100.0, 1000.0, stiffness=300.0, rest_speed=10.0, rest_delta=0.5)),
    [100.0, 1343.0, 873.0, 1046.0, 984.0, 1005.0, 998.0, 1001.0, 1000.0],
  )
}

///|
test "spring: velocity passed to underdamped spring" {
  let no = animate_sync(@motion.spring_generator(100.0, 1000.0, stiffness=300.0, rest_speed=10.0, rest_delta=0.5))
  let with_v = animate_sync(
    @motion.spring_generator(100.0, 1000.0, stiffness=300.0, rest_speed=10.0, rest_delta=0.5, velocity=1000.0),
  )
  assert_true(no != with_v)
}

///|
test "spring: critically damped spring" {
  assert_eq(
    animate_sync(
      @motion.spring_generator(100.0, 1000.0, stiffness=100.0, damping=20.0, rest_speed=10.0, rest_delta=0.5),
    ),
    [100.0, 635.0, 918.0, 984.0, 997.0, 1000.0],
  )
}

///|
test "spring: velocity passed to critically damped spring" {
  let no = animate_sync(
    @motion.spring_generator(100.0, 1000.0, stiffness=100.0, damping=20.0, rest_speed=10.0, rest_delta=0.5),
  )
  let with_v = animate_sync(
    @motion.spring_generator(
      100.0,
      1000.0,
      stiffness=100.0,
      damping=20.0,
      rest_speed=10.0,
      rest_delta=0.5,
      velocity=1000.0,
    ),
  )
  assert_true(no != with_v)
}

///|
test "spring: overdamped spring" {
  assert_eq(
    animate_sync(
      @motion.spring_generator(100.0, 1000.0, stiffness=300.0, damping=100.0, rest_speed=10.0, rest_delta=0.5),
    ),
    [
      100.0, 499.0, 731.0, 855.0, 922.0, 958.0, 977.0, 988.0, 993.0, 996.0, 998.0, 999.0, 999.0, 1000.0,
    ],
  )
}

///|
test "spring: overdamped spring with very high stiffness and damping" {
  assert_eq(
    animate_sync(
      @motion.spring_generator(
        100.0,
        1000.0,
        stiffness=1000000.0,
        damping=10000000.0,
        rest_delta=1.0,
        rest_speed=10.0,
      ),
    ),
    [100.0, 1000.0],
  )
}

///|
test "spring: heavily overdamped springs (dragTransition's) settle quickly" {
  for p in [(2000.0, 10000.0), (10000.0, 10000.0)] {
    let g = @motion.spring_generator(-60.0, 0.0, stiffness=p.0, damping=p.1, rest_delta=1.0, rest_speed=10.0)
    assert_eq(g.next(100.0), @motion.GenState::{ done: true, value: 0.0 })
  }
}

///|
test "spring: velocity passed to overdamped spring" {
  let no = animate_sync(
    @motion.spring_generator(100.0, 1000.0, stiffness=300.0, damping=100.0, rest_speed=10.0, rest_delta=0.5),
  )
  let with_v = animate_sync(
    @motion.spring_generator(
      100.0,
      1000.0,
      stiffness=300.0,
      damping=100.0,
      rest_speed=10.0,
      rest_delta=0.5,
      velocity=1000.0,
    ),
  )
  assert_true(no != with_v)
}

///|
test "spring: one defined by bounce and duration is the same as by bounce alone" {
  let without = animate_sync(@motion.spring_generator(100.0, 1000.0, bounce=0.1))
  let with_d = animate_sync(@motion.spring_generator(100.0, 1000.0, bounce=0.1, duration=800.0))
  assert_eq(without, with_d)
  // its duration's order of magnitude
  assert_true(without.length() > 4)
}

///|
test "spring: a time-defined spring ignores velocity" {
  let with_v = @motion.spring_generator(500.0, 10.0, bounce=0.2, duration=1000.0, velocity=1000.0)
  let without = @motion.spring_generator(500.0, 10.0, bounce=0.2, duration=1000.0)
  assert_eq(with_v.next(0.0).value, without.next(0.0).value)
  assert_eq(with_v.next(100.0).value, without.next(100.0).value)
}

///|
test "spring: a time-defined spring with velocity does not wildly oscillate" {
  let no = @motion.spring_generator(0.0, 100.0, bounce=0.2, duration=400.0)
  let with_v = @motion.spring_generator(0.0, 100.0, bounce=0.2, duration=400.0, velocity=5000.0)
  let mut max_no = 0.0
  let mut max_with = 0.0
  let mut t = 0.0
  while t <= 400.0 {
    let a = no.next(t).value
    let b = with_v.next(t).value
    if a > max_no {
      max_no = a
    }
    if b > max_with {
      max_with = b
    }
    t = t + 5.0
  }
  assert_true(max_no - 100.0 < 5.0)
  assert_true(max_with - 100.0 < 5.0)
}

///|
test "spring: overdamped with velocity and no distance is not done at once" {
  let g = @motion.spring_generator(1.0, 1.0, stiffness=700.0, damping=80.0, velocity=50.0)
  assert_eq(g.next(0.0).done, false)
  // it overshoots, from its velocity
  assert_true(g.next(0.01).value != 1.0)
}

///|
test "spring: critically damped with velocity and no distance is not done at once" {
  let g = @motion.spring_generator(1.0, 1.0, stiffness=100.0, damping=20.0, velocity=50.0)
  assert_eq(g.next(0.0).done, false)
}

///|
test "spring: animating back to the same number has its duration" {
  let d = @motion.calc_generator_duration(
    @motion.spring_generator(1.0, 1.0, velocity=5.0, stiffness=200.0, damping=15.0),
  )
  assert_eq(d, 600.0)
}

///|
test "spring: visualDuration alone returns the default spring's duration" {
  let g = @motion.spring_generator(0.0, 1.0, visual_duration=0.5)
  assert_eq(@motion.calc_generator_duration(g), 1100.0)
}

///|
test "spring: visualDuration's shorthand resolves the same" {
  assert_eq(
    @motion.spring_generator(0.0, 1.0, visual_duration=0.5, bounce=0.25).to_css(),
    @motion.spring_visual(visual_duration=0.5, bounce=0.25).to_css(),
  )
}

///|
/// Its values every 10 ms until done (at most Motion's maximum).
fn sample_until_done(g : @motion.Generator) -> Array[Double] {
  let values = []
  let mut t = 0.0
  while t <= @motion.max_generator_duration {
    let s = g.next(t)
    values.push(s.value)
    if s.done {
      break
    }
    t = t + 10.0
  }
  values
}

///|
fn monotonic_without_overshoot(values : Array[Double]) -> Bool {
  for i in 1..<values.length() {
    if values[i] < values[i - 1] || values[i] > 100.0 {
      return false
    }
  }
  true
}

///|
test "spring: a negative bounce resolves an overdamped spring from duration" {
  for bounce in [-0.25, -0.5, -0.95] {
    let over = @motion.spring_generator(0.0, 100.0, duration=800.0, bounce~)
    let critical = @motion.spring_generator(0.0, 100.0, duration=800.0, bounce=0.0)
    assert_eq(over.calculated_duration(), Some(800.0))
    assert_true(!close(over.next(200.0).value, critical.next(200.0).value))
    let values = sample_until_done(@motion.spring_generator(0.0, 100.0, duration=800.0, bounce~))
    assert_true(monotonic_without_overshoot(values))
    // it settles within its duration rather than snapping at its end
    assert_true(100.0 - values[values.length() - 2] < 1.0)
  }
}

///|
test "spring: a more negative bounce is flatter" {
  let arrival = fn(bounce : Double) {
    @motion.spring_generator(0.0, 100.0, duration=800.0, bounce~).velocity(400.0)
  }
  assert_true(arrival(-0.5) < arrival(0.0))
  assert_true(arrival(-0.9) < arrival(-0.5))
}

///|
test "spring: a negative bounce resolves an overdamped spring from visualDuration" {
  for bounce in [-0.25, -0.5, -0.95] {
    let over = @motion.spring_visual(visual_duration=0.3, bounce~)
    let critical = @motion.spring_visual(visual_duration=0.3, bounce=0.0)
    assert_true(!close(over.next(100.0).value, critical.next(100.0).value))
    assert_true(
      monotonic_without_overshoot(
        sample_until_done(@motion.spring_generator(0.0, 100.0, visual_duration=0.3, bounce~)),
      ),
    )
  }
}

///|
/// No sample snapped to the target (tiny rest thresholds).
fn unsnapped(
  visual_duration? : Double,
  duration? : Double,
  bounce~ : Double,
) -> @motion.Generator {
  @motion.spring_generator(
    0.0,
    100.0,
    visual_duration?=visual_duration,
    duration?=duration,
    bounce~,
    rest_delta=1.0e-9,
    rest_speed=1.0e-9,
  )
}

///|
test "spring: by visualDuration, every bounce down to -1 is as far along as bounce 0 at its visual duration" {
  for visual in [0.3, 1.0] {
    let t = visual * 1000.0
    let critical = unsnapped(visual_duration=visual, bounce=0.0).next(t).value
    // bounce 0 is 96.68% of the way there
    assert_true(close(critical, 96.68, digits=2), msg="\{critical}")
    for bounce in [0.0, -0.5, -0.9, -0.95, -0.99, -1.0] {
      let v = unsnapped(visual_duration=visual, bounce~).next(t).value
      assert_true(close(v, critical, digits=6), msg="\{visual} \{bounce}: \{v} \{critical}")
    }
  }
}

///|
test "spring: by duration, every bounce down to -1 has 0.1% of the way left at its duration" {
  for duration in [300.0, 800.0, 2000.0] {
    for bounce in [0.0, -0.5, -0.9, -0.95, -0.99, -1.0] {
      let g = unsnapped(duration~, bounce~)
      // just before its duration, where it snaps to its target
      let left = 100.0 - g.next(duration - 1.0e-9).value
      assert_true(close(left, 0.1, digits=6), msg="\{duration} \{bounce}: \{left}")
    }
  }
}

///|
test "spring: bounce is limited to -0.95" {
  assert_eq(
    @motion.spring_visual(visual_duration=0.3, bounce=-5.0).to_css(),
    @motion.spring_visual(visual_duration=0.3, bounce=-0.95).to_css(),
  )
}

///|
test "spring: a bounce just below 0 matches a critically damped spring" {
  for by_duration in [true, false] {
    let make = fn(bounce : Double) {
      if by_duration {
        @motion.spring_generator(0.0, 100.0, duration=800.0, bounce~)
      } else {
        @motion.spring_generator(0.0, 100.0, visual_duration=0.3, bounce~)
      }
    }
    let over = make(-1.0e-8)
    let critical = make(0.0)
    for t in [50.0, 100.0, 200.0, 400.0] {
      assert_true(close(over.next(t).value, critical.next(t).value, digits=1))
    }
  }
}

///|
test "spring: a bounce of -0.95 slows continuously to its target" {
  for by_duration in [false, true] {
    let g = if by_duration {
      @motion.spring_generator(0.0, 100.0, duration=800.0, bounce=-0.95, rest_delta=1.0e-6, rest_speed=1.0e-6)
    } else {
      @motion.spring_generator(0.0, 100.0, visual_duration=0.3, bounce=-0.95, rest_delta=1.0e-6, rest_speed=1.0e-6)
    }
    let mut previous = 0.0
    let mut previous_step = inf()
    let mut t = 10.0
    while t < 800.0 {
      let value = g.next(t).value
      let step = value - previous
      assert_true(step >= 0.0)
      assert_true(step <= previous_step)
      assert_true(value < 100.0)
      previous = value
      previous_step = step
      t = t + 10.0
    }
  }
}

///|
test "spring: toString" {
  assert_eq(
    @motion.spring_generator(0.0, 1.0, stiffness=100.0, damping=10.0, mass=1.0).to_css(),
    "1100ms linear(0, 0.0419, 0.1493, 0.2963, 0.4608, 0.625, 0.7759, 0.905, 1.0077, 1.0827, 1.1314, 1.1567, 1.1629, 1.1545, 1.1359, 1.1114, 1.0844, 1.0578, 1.0336, 1.0131, 0.9969, 0.9853, 0.9779, 0.9742, 0.9735, 0.9751, 0.9783, 0.9824, 0.9868, 0.9911, 0.995, 0.9982, 1.0008, 1.0026, 1.0037, 1, 1)",
  )
  assert_eq(
    @motion.spring_generator(0.0, 1.0, duration=800.0, bounce=0.25).to_css(),
    "800ms linear(0, 0.0542, 0.1797, 0.3344, 0.4905, 0.6321, 0.7511, 0.8451, 0.9152, 0.9644, 0.9967, 1.0157, 1.0253, 1.0283, 1.0273, 1.024, 1.0196, 1.0152, 1.0111, 1.0076, 1.0048, 1.0027, 1.0012, 1.0002, 0.9996, 0.9993, 1)",
  )
  assert_eq(
    @motion.spring_generator(0.0, 1.0, visual_duration=0.5, bounce=0.25).to_css(),
    "850ms linear(0, 0.046, 0.1551, 0.2934, 0.4378, 0.5737, 0.6927, 0.7915, 0.8694, 0.928, 0.9699, 0.998, 1.0153, 1.0245, 1.0281, 1.0279, 1.0254, 1.0217, 1.0176, 1.0136, 1.01, 1.007, 1.0045, 1.0027, 1.0013, 1.0003, 0.9997, 1)",
  )
}

///|
/// The generator at 0, 100, 300, 600 and 1000 ms (it may never be done: NaN).
fn sample(g : @motion.Generator) -> Array[Double] {
  [0.0, 100.0, 300.0, 600.0, 1000.0].map(fn(t) { g.next(t).value })
}

///|
test "spring NaN guards: invalid physics falls back to the default" {
  let plain = sample(@motion.spring_generator(0.0, 100.0))
  for v in [Some(0.0), Some(-1.0), Some(nan()), Some(inf()), Some(-inf()), None] {
    assert_eq(sample(@motion.spring_generator(0.0, 100.0, stiffness?=v)), plain)
    assert_eq(sample(@motion.spring_generator(0.0, 100.0, mass?=v)), plain)
    // a damping of 0 is a valid, perpetually oscillating spring
    if v != Some(0.0) {
      assert_eq(sample(@motion.spring_generator(0.0, 100.0, damping?=v)), plain)
    }
  }
}

///|
test "spring NaN guards: a damping of 0 is honoured as an undamped spring" {
  let values = sample(@motion.spring_generator(0.0, 100.0, damping=0.0))
  for v in values {
    assert_true(!v.is_nan() && !v.is_inf())
  }
  // it oscillates rather than settling on its target
  assert_true(!close(values[values.length() - 1], 100.0))
}

///|
/// A spring with one of its physics (0 stiffness, 1 damping, 2 mass) NaN, and these time options.
fn nan_physics(key : Int, duration? : Double, visual_duration? : Double, bounce? : Double) -> @motion.Generator {
  @motion.spring_generator(
    0.0,
    100.0,
    stiffness?=if key == 0 { Some(nan()) } else { None },
    damping?=if key == 1 { Some(nan()) } else { None },
    mass?=if key == 2 { Some(nan()) } else { None },
    duration?=duration,
    visual_duration?=visual_duration,
    bounce?=bounce,
  )
}

///|
test "spring NaN guards: invalid physics does not discard the time options given" {
  for key in 0..<3 {
    assert_eq(sample(nan_physics(key, duration=500.0)), sample(@motion.spring_generator(0.0, 100.0, duration=500.0)))
    assert_eq(
      sample(nan_physics(key, visual_duration=0.5, bounce=0.2)),
      sample(@motion.spring_generator(0.0, 100.0, visual_duration=0.5, bounce=0.2)),
    )
  }
}

///|
test "spring NaN guards: non-finite time options don't produce NaN" {
  for g in [
    @motion.spring_generator(0.0, 100.0, duration=500.0, bounce=nan()),
    @motion.spring_generator(0.0, 100.0, visual_duration=inf(), bounce=0.2),
  ] {
    for v in sample(g) {
      assert_true(!v.is_nan() && !v.is_inf())
    }
  }
}

///|
test "spring NaN guards: a visualDuration of 0 falls back to resolving by duration" {
  assert_eq(
    sample(@motion.spring_generator(0.0, 100.0, visual_duration=0.0, bounce=0.2)),
    sample(@motion.spring_generator(0.0, 100.0, bounce=0.2)),
  )
}

///|
test "spring NaN guards: retargeting treats invalid physics as absent" {
  // resolved at first as time-defined, it ignores the velocity it inherits: so does it retargeted
  let g = @motion.spring_generator(0.0, 100.0, duration=600.0, stiffness=0.0)
  g.next(16.0) |> ignore
  g.retarget(20.0, -50.0, 300.0)
  let fresh = @motion.spring_generator(20.0, -50.0, duration=600.0, velocity=300.0)
  for t in [0.0, 16.0, 100.0, 300.0, 1000.0] {
    assert_eq(g.next(t), fresh.next(t))
  }
}

///|
test "spring NaN guards: an invalid stiffness still resolves to a spring that completes" {
  let g = @motion.spring_generator(0.0, 100.0, stiffness?=None)
  assert_true(@motion.calc_generator_duration(g) < @motion.max_generator_duration)
}

// ── inertia (motion-dom generators/__tests__/inertia.test.ts) ───────────

///|
test "inertia: runs animations with default values" {
  assert_eq(@motion.pregenerate_keyframes(@motion.inertia_generator(0.0)).0, [0.0, 0.0])
}

///|
test "inertia: works with t === 0" {
  let g = @motion.inertia_generator(
    100.0,
    velocity=-200.0,
    power=1.0,
    time_constant=500.0,
    rest_delta=0.5,
    min=0.0,
    max=0.0,
  )
  assert_eq(g.next(0.0).value, 100.0)
}

///|
test "inertia: continues animation when time is 0" {
  let s = @motion.inertia_generator(100.0, min=0.0, max=0.0).next(0.0)
  assert_eq(s.done, false)
  assert_eq(s.value, 100.0)
}

///|
fn same_keyframes(got : Array[Double], want : Array[Double]) -> Bool {
  if got.length() != want.length() {
    return false
  }
  for i in 0..<got.length() {
    if (got[i] - want[i]).abs() > 1.0e-9 * dmax1(want[i].abs()) {
      return false
    }
  }
  true
}

///|
fn dmax1(x : Double) -> Double {
  if x > 1.0 {
    x
  } else {
    1.0
  }
}

///|
test "inertia: runs animation" {
  let (k, d) = @motion.pregenerate_keyframes(
    @motion.inertia_generator(100.0, velocity=200.0, power=1.0, time_constant=500.0, rest_delta=0.5),
  )
  assert_eq(d, 3.0)
  assert_true(same_keyframes(k, expected_animation_keyframes))
}

///|
test "inertia: modifyTarget changes the calculated target" {
  let (k, d) = @motion.pregenerate_keyframes(
    @motion.inertia_generator(
      100.0,
      velocity=200.0,
      power=1.0,
      time_constant=500.0,
      rest_delta=0.5,
      modify_target=fn(t) { t / 2.0 },
    ),
  )
  assert_eq(d, 2.31)
  assert_true(same_keyframes(k, expected_animation_modify_target_keyframes))
}

///|
test "inertia: negative velocity produces negative keyframes" {
  // (as Motion's test has it: both with velocity 100)
  let pos = @motion.pregenerate_keyframes(@motion.inertia_generator(0.0, velocity=100.0)).0
  let neg = @motion.pregenerate_keyframes(@motion.inertia_generator(0.0, velocity=100.0)).0
  assert_eq(pos, neg.map(fn(v) { v.abs() }))
}

///|
test "inertia: runs animation with min (not encountered)" {
  let (k, d) = @motion.pregenerate_keyframes(
    @motion.inertia_generator(100.0, velocity=200.0, power=1.0, time_constant=500.0, rest_delta=0.5, min=0.0),
  )
  assert_eq(d, 3.0)
  assert_true(same_keyframes(k, expected_animation_keyframes))
}

///|
test "inertia: runs animation with min (spring encountered)" {
  let (k, d) = @motion.pregenerate_keyframes(
    @motion.inertia_generator(100.0, velocity=-200.0, power=1.0, time_constant=500.0, rest_delta=0.5, min=0.0),
  )
  assert_eq(d, 1.85)
  assert_true(same_keyframes(k, expected_animation_keyframes_with_min))
}

///|
test "inertia: runs animation with max (not encountered)" {
  let (k, d) = @motion.pregenerate_keyframes(
    @motion.inertia_generator(100.0, velocity=-200.0, power=1.0, time_constant=500.0, rest_delta=0.5, max=200.0),
  )
  assert_eq(d, 3.0)
  assert_true(same_keyframes(k, expected_animation_keyframes_negative))
}

///|
test "inertia: runs animation with max (spring encountered)" {
  let (k, d) = @motion.pregenerate_keyframes(
    @motion.inertia_generator(100.0, velocity=200.0, power=1.0, time_constant=500.0, rest_delta=0.5, max=200.0),
  )
  assert_eq(d, 1.85)
  assert_true(same_keyframes(k, expected_animation_keyframes_with_max))
}

///|
test "inertia: a longer time constant, a longer animation" {
  let long = @motion.inertia_generator(100.0, velocity=200.0, power=1.0, time_constant=500.0, rest_delta=0.5)
  let short = @motion.inertia_generator(100.0, velocity=200.0, power=1.0, time_constant=0.1, rest_delta=0.5)
  assert_true(@motion.pregenerate_keyframes(long).1 > @motion.pregenerate_keyframes(short).1)
}

///|
test "inertia: higher power, further distance" {
  let long_target = Ref::new(0.0)
  let short_target = Ref::new(0.0)
  let long = @motion.inertia_generator(
    100.0,
    velocity=200.0,
    power=10.0,
    time_constant=500.0,
    rest_delta=0.5,
    modify_target=fn(v) {
      long_target.val = v
      v
    },
  )
  let short = @motion.inertia_generator(
    100.0,
    velocity=200.0,
    power=1.0,
    time_constant=500.0,
    rest_delta=0.5,
    modify_target=fn(v) {
      short_target.val = v
      v
    },
  )
  @motion.pregenerate_keyframes(long) |> ignore
  @motion.pregenerate_keyframes(short) |> ignore
  assert_true(long_target.val > short_target.val)
}

// ── keyframes (motion-dom generators/__tests__/keyframes.test.ts) ───────

///|
test "keyframes: defaultEasing returns an easing for each piece" {
  assert_eq(@motion.default_easing(2, easing=@motion.linear).length(), 1)
  assert_eq(@motion.default_easing(3, easing=@motion.linear).length(), 2)
  let es = @motion.default_easing(3)
  assert_eq(es.length(), 2)
  for e in es {
    for p in [0.1, 0.5, 0.8] {
      assert_eq(e(p), @motion.ease_in_out(p))
    }
  }
}

///|
test "keyframes: defaultOffset returns a default times array" {
  assert_eq(@motion.default_offset(2), [0.0, 1.0])
  assert_eq(@motion.default_offset(3), [0.0, 0.5, 1.0])
  assert_eq(@motion.default_offset(4), [0.0, 1.0 / 3.0, 1.0 / 3.0 * 2.0, 1.0])
}

///|
test "keyframes: convertOffsetToTimes converts offsets to times" {
  assert_eq(@motion.offsets_to_times([0.0, 0.5, 1.0], 500.0), [0.0, 250.0, 500.0])
}

///|
test "keyframes: runs a default animation" {
  assert_eq(
    animate_sync(@motion.keyframes_generator([0.0, 100.0]), time_step=20.0),
    [
      0.0, 1.0, 4.0, 8.0, 15.0, 23.0, 33.0, 44.0, 56.0, 67.0, 77.0, 85.0, 92.0, 96.0, 99.0, 100.0,
    ],
  )
}

///|
test "keyframes: adjusts with its duration" {
  assert_eq(
    animate_sync(@motion.keyframes_generator([0.0, 100.0], duration=100.0, ease=@motion.linear), time_step=20.0),
    [0.0, 20.0, 40.0, 60.0, 80.0, 100.0],
  )
}

///|
test "keyframes: animates through keyframes" {
  assert_eq(
    animate_sync(
      @motion.keyframes_generator([50.0, 100.0, -100.0], duration=200.0, ease=@motion.linear),
      time_step=20.0,
    ),
    [50.0, 60.0, 70.0, 80.0, 90.0, 100.0, 60.0, 20.0, -20.0, -60.0, -100.0],
  )
}

///|
test "keyframes: clamps two keyframes to the duration" {
  let g = @motion.keyframes_generator([0.0, 100.0], duration=100.0, ease=@motion.linear)
  assert_eq(g.next(-50.0).value, 0.0)
  assert_eq(g.next(50.0).value, 50.0)
  assert_eq(g.next(50.0).done, false)
  assert_eq(g.next(150.0).value, 100.0)
  assert_eq(g.next(150.0).done, true)
}

///|
test "keyframes: two keyframes with no duration resolve to the target" {
  let g = @motion.keyframes_generator([0.0, 100.0], duration=0.0, ease=@motion.linear)
  assert_eq(g.next(0.0), @motion.GenState::{ value: 100.0, done: true })
}

///|
test "keyframes: two identical keyframes hold the value" {
  let g = @motion.keyframes_generator([50.0, 50.0], duration=100.0, ease=@motion.linear)
  assert_eq(g.next(50.0).value, 50.0)
  assert_eq(g.next(150.0).done, true)
}

///|
test "keyframes: two keyframes honour times" {
  let plain = @motion.keyframes_generator([0.0, 100.0], duration=100.0, ease=@motion.linear, times=[0.0, 1.0])
  assert_eq(plain.next(50.0).value, 50.0)
  let offset = @motion.keyframes_generator([0.0, 100.0], duration=100.0, ease=@motion.linear, times=[0.5, 1.0])
  assert_eq(offset.next(50.0).value, 0.0)
  assert_eq(offset.next(75.0).value, 50.0)
}

///|
test "keyframes: two keyframes accept an easing array" {
  assert_eq(
    animate_sync(@motion.keyframes_generator([0.0, 100.0], duration=100.0, eases=[@motion.linear]), time_step=20.0),
    [0.0, 20.0, 40.0, 60.0, 80.0, 100.0],
  )
}

///|
test "keyframes: an easing Motion has no name for falls back to the default" {
  // (Motion's test: unrecognised easing strings in production)
  assert_true(@motion.easing_named("ease") is None)
  assert_true(@motion.easing_named("easeOutQuad") is None)
  for values in [[0.0, 50.0, 100.0], [0.0, 100.0]] {
    assert_eq(
      animate_sync(
        @motion.keyframes_generator(values, duration=100.0, ease?=@motion.easing_named("ease")),
        time_step=20.0,
      ),
      animate_sync(@motion.keyframes_generator(values, duration=100.0), time_step=20.0),
    )
  }
}

// ── createGeneratorEasing (generators/utils/__tests__) ──────────────────

///|
test "createGeneratorEasing scales velocity to the normalised range" {
  let make = fn(from : Double, to : Double, v : Double) {
    @motion.spring_generator(from, to, stiffness=100.0, damping=10.0, mass=1.0, velocity=v)
  }
  // from 100 towards 50 at +100 a second: its progress first goes negative, away from the target
  let (ease, _) = @motion.generator_easing(make, 100.0, 50.0, velocity=100.0)
  assert_true(ease(0.02) < 0.0)
  // the same velocity towards a target the other way
  let (forward, _) = @motion.generator_easing(make, 50.0, 100.0, velocity=100.0)
  assert_true(forward(0.02) > 0.0)
  // without velocity it starts at 0 and heads to its target
  let (still, _) = @motion.generator_easing(make, 100.0, 50.0)
  assert_eq(still(0.0), 0.0)
  assert_true(still(0.02) > 0.0)
}

// ── interpolate, mix (motion-dom src/utils) ─────────────────────────────

///|
test "interpolate numbers" {
  let f = @motion.interpolate([0.0, 100.0], [0.0, 1.0])
  assert_eq(f(50.0), 0.5)
  let s = @motion.interpolate([-100.0, 100.0, 200.0], [0.0, 100.0, 0.0])
  assert_eq(s(-200.0), 0.0)
  assert_eq(s(0.0), 50.0)
  assert_eq(s(201.0), 0.0)
}

///|
test "interpolate - ease" {
  let f = @motion.interpolate([0.0, 100.0], [0.0, 100.0], ease=fn(v) { -v })
  assert_eq(f(50.0), -50.0)
}

///|
test "interpolate - 0-width input" {
  let f = @motion.interpolate([2.0, 2.0], [0.0, 1.0], clamp=false)
  assert_eq(f(0.0), 0.0)
  assert_eq(f(1.0), 0.0)
  assert_eq(f(2.0), 1.0)
}

///|
test "interpolate - negative" {
  let f = @motion.interpolate([-500.0, 500.0], [0.0, 1.0])
  assert_eq(f(-250.0), 0.25)
  let s = @motion.interpolate([-500.0, 500.0, 600.0], [0.0, 1.0, 2.0])
  assert_eq(s(-250.0), 0.25)
}

///|
test "interpolate - out of range" {
  let f = @motion.interpolate([0.0, 100.0], [200.0, 100.0])
  assert_eq(f(50.0), 150.0)
  assert_eq(f(150.0), 100.0)
  assert_eq(f(0.0), 200.0)
  assert_eq(f(-100.0), 200.0)
  let s = @motion.interpolate([0.0, 100.0, 200.0], [100.0, 200.0, 100.0])
  assert_eq(s(-50.0), 100.0)
  assert_eq(s(250.0), 100.0)
}

///|
test "interpolate - unclamped" {
  let f = @motion.interpolate([0.0, 100.0], [200.0, 100.0], clamp=false)
  assert_eq(f(50.0), 150.0)
  assert_eq(f(150.0), 50.0)
  assert_eq(f(0.0), 200.0)
  assert_eq(f(-100.0), 300.0)
  let s = @motion.interpolate([0.0, 100.0, 200.0], [1.0, 2.0, 3.0], clamp=false)
  assert_eq(s(-100.0), 0.0)
}

///|
test "interpolate - complex" {
  let a = @motion.interpolate([0.0, 100.0, 200.0], [1000.0, 500.0, 1000.0])
  assert_eq(a(100.0), 500.0)
}

///|
test "interpolate - reverse" {
  let a = @motion.interpolate([1000.0, 0.0], [500.0, 600.0])
  assert_eq(a(500.0), 550.0)
  assert_eq(a(1000.0), 500.0)
  assert_eq(a(0.0), 600.0)
}

///|
test "interpolate - reverse complex" {
  let a = @motion.interpolate([0.0, 100.0, 200.0], [1000.0, 500.0, 1000.0])
  assert_eq(a(100.0), 500.0)
  assert_eq(a(0.0), 1000.0)
  assert_eq(a(200.0), 1000.0)
}

///|
test "interpolate - custom mixer" {
  let a = @motion.interpolate([0.0, 1.0], [0.0, 1.0], mixer=fn(_, _) { fn(_) { 42.0 } })
  assert_eq(a(0.5), 42.0)
}

///|
test "mixNumber" {
  assert_eq(@motion.mix(0.0, 1.0, 0.5), 0.5)
  assert_eq(@motion.mix(-100.0, 100.0, 2.0), 300.0)
  assert_eq(@motion.mix(10.0, 20.0, 0.5), 15.0)
  assert_eq(@motion.mix(-10.0, -20.0, 0.5), -15.0)
  assert_eq(@motion.mix(0.0, 80.0, 0.5), 40.0)
  assert_eq(@motion.mix(100.0, 200.0, 2.0), 300.0)
  assert_eq(@motion.mix(-100.0, 100.0, 2.0), 300.0)
}

// ── motion-utils ────────────────────────────────────────────────────────

///|
test "progress" {
  assert_eq(@motion.progress(0.0, 100.0, 50.0), 0.5)
  assert_eq(@motion.progress(100.0, -100.0, 50.0), 0.25)
  assert_eq(@motion.progress(100.0, -100.0, -300.0), 2.0)
}

///|
test "clamp" {
  assert_eq(@motion.clamp(100.0, 200.0, 99.0), 100.0)
  assert_eq(@motion.clamp(100.0, 200.0, 201.0), 200.0)
  assert_eq(@motion.clamp(100.0, 200.0, 150.0), 150.0)
}

///|
test "wrap" {
  assert_eq(@motion.wrap(-100.0, 100.0, -100.0), -100.0)
  assert_eq(@motion.wrap(-100.0, 100.0, 0.0), 0.0)
  assert_eq(@motion.wrap(-100.0, 100.0, -200.0), 0.0)
  assert_eq(@motion.wrap(-100.0, 100.0, 101.0), -99.0)
}

///|
test "velocityPerSecond" {
  assert_eq(@motion.velocity_per_second(0.835, 16.7), 50.0)
  assert_eq(@motion.velocity_per_second(0.835, 0.0), 0.0)
}

///|
test "anticipate easing" {
  assert_eq(@motion.anticipate(0.0), 0.0)
  assert_eq(@motion.anticipate(1.0), 1.0)
}

///|
test "circ easing: circInOut is correct" {
  assert_eq(@motion.circ_in_out(0.25), @motion.circ_in(0.5) / 2.0)
  assert_eq(@motion.circ_in_out(0.75), 0.5 + @motion.circ_out(0.5) / 2.0)
}

///|
/// One axis of the curve at parameter t.
fn bezier_axis(t : Double, p1 : Double, p2 : Double) -> Double {
  3.0 * p1 * t * (1.0 - t) * (1.0 - t) + 3.0 * p2 * t * t * (1.0 - t) + t * t * t
}

///|
let curves : Array[(Double, Double, Double, Double)] = [
  (0.25, 0.1, 0.25, 1.0), // CSS ease
  (0.42, 0.0, 1.0, 1.0), // CSS ease-in
  (0.0, 0.0, 0.58, 1.0), // CSS ease-out
  (0.42, 0.0, 0.58, 1.0), // CSS ease-in-out
  (0.5, 0.1, 0.31, 0.96),
  (0.33, 1.53, 0.69, 0.99), // backOut
  (0.17, 0.67, 0.83, 0.67),
  (0.0, 1.0, 1.0, 0.0), // dx/dt = 0 at both ends
  (1.0, 0.0, 0.0, 1.0), // dx/dt = 0 at t = 0.5
  (0.9, 0.1, 0.1, 0.9),
  (0.0, 0.5, 0.0, 0.5),
  (1.0, 0.5, 1.0, 0.5),
  (0.5, 0.0, 0.5, 1.0),
  (0.32, 0.72, 0.0, 1.0),
]

///|
test "cubicBezier: generates easing functions from curve definitions" {
  let linear = @motion.cubic_bezier(0.0, 0.0, 1.0, 1.0)
  assert_eq(linear(0.0), 0.0)
  assert_eq(linear(1.0), 1.0)
  assert_eq(linear(0.5), 0.5)
  let curve = @motion.cubic_bezier(0.5, 0.1, 0.31, 0.96)
  assert_eq(curve(0.0), 0.0)
  assert_true(close(curve(0.01), 0.002, digits=2))
  assert_true(close(curve(0.25), 0.164, digits=2))
  assert_true(close(curve(0.75), 0.935, digits=2))
  assert_true(close(curve(0.99), 0.999, digits=2))
  assert_eq(curve(1.0), 1.0)
}

///|
test "cubicBezier: its output is not quantised" {
  let ease = @motion.cubic_bezier(0.25, 0.1, 0.25, 1.0)
  let values : Map[Double, Bool] = {}
  for i in 0..=1000 {
    values[ease(0.3 + i.to_double() * 1.0e-6)] = true
  }
  assert_eq(values.length(), 1001)
}

///|
test "cubicBezier: its output matches points on the curve" {
  for c in curves {
    let (x1, y1, x2, y2) = c
    let ease = @motion.cubic_bezier(x1, y1, x2, y2)
    for i in 1..<200 {
      let t = i.to_double() / 200.0
      let x = bezier_axis(t, x1, x2)
      let expected = bezier_axis(t, y1, y2)
      // where dx/dt is ~0, x barely changes with t and y is ill-conditioned: the tolerance scaled by the slope
      let dx = 3.0 * (1.0 - t) * (1.0 - t) * x1 + 6.0 * (1.0 - t) * t * (x2 - x1) + 3.0 * t * t * (1.0 - x2)
      let dy = 3.0 * (1.0 - t) * (1.0 - t) * y1 + 6.0 * (1.0 - t) * t * (y2 - y1) + 3.0 * t * t * (1.0 - y2)
      let tolerance = 1.0e-9 + 1.0e-9 * (dy / dmax_(dx, 1.0e-6)).abs()
      assert_true((ease(x) - expected).abs() < tolerance, msg="\{c} at \{t}")
    }
  }
}

///|
fn dmax_(a : Double, b : Double) -> Double {
  if a > b {
    a
  } else {
    b
  }
}

///|
test "cubicBezier: is monotonic for monotonic curves" {
  for c in [(0.25, 0.1, 0.25, 1.0), (0.42, 0.0, 0.58, 1.0), (0.0, 1.0, 1.0, 0.0), (1.0, 0.0, 0.0, 1.0), (0.9, 0.1, 0.1, 0.9)] {
    let ease = @motion.cubic_bezier(c.0, c.1, c.2, c.3)
    let mut decreases = 0
    let mut prev = ease(0.0)
    for i in 1..=100000 {
      let v = ease(i.to_double() / 100000.0)
      if v < prev {
        decreases = decreases + 1
      }
      prev = v
    }
    assert_eq(decreases, 0)
  }
}

///|
test "cubicBezier: solves exactly where the slope is 0" {
  // dx/dt = 0 at t = 0.5, where x = y = 0.5
  assert_true(close(@motion.cubic_bezier(1.0, 0.0, 0.0, 1.0)(0.5), 0.5, digits=12))
  // dx/dt = 0 at t = 0, y rising like sqrt(x)
  let ease = @motion.cubic_bezier(0.0, 1.0, 1.0, 0.0)
  assert_true(ease(1.0e-8) > 0.0)
  assert_true(ease(1.0e-8) < ease(2.0e-8))
}

///|
test "cubicBezier: exactly 0 and 1 at its start and end" {
  for c in curves {
    let ease = @motion.cubic_bezier(c.0, c.1, c.2, c.3)
    assert_eq(ease(0.0), 0.0)
    assert_eq(ease(1.0), 1.0)
  }
}

///|
test "cubicBezier: saturates to 0 and 1 beyond its start and end" {
  for c in curves {
    let ease = @motion.cubic_bezier(c.0, c.1, c.2, c.3)
    for x in [-1.0e9, -0.5, -1.0e-9] {
      assert_true(ease(x).abs() < 1.0e-10)
    }
    for x in [1.0 + 1.0e-9, 1.5, 1.0e9] {
      assert_true((ease(x) - 1.0).abs() < 1.0e-10)
    }
  }
}

///|
test "steps" {
  let step_end = @motion.steps(4)
  assert_eq(step_end(0.0), 0.0)
  assert_eq(step_end(0.2), 0.0)
  assert_eq(step_end(0.249), 0.0)
  assert_eq(step_end(0.25), 0.25)
  assert_eq(step_end(0.49), 0.25)
  assert_eq(step_end(0.5), 0.5)
  assert_eq(step_end(0.99), 0.75)
  assert_eq(step_end(1.0), 0.75)
  let step_start = @motion.steps(4, direction=Start)
  assert_eq(step_start(0.0), 0.25)
  assert_eq(step_start(0.2), 0.25)
  assert_eq(step_start(0.249), 0.25)
  assert_eq(step_start(0.25), 0.25)
  assert_eq(step_start(0.49), 0.5)
  assert_eq(step_start(0.5), 0.5)
  assert_eq(step_start(0.51), 0.75)
  assert_eq(step_start(0.99), 1.0)
  assert_eq(step_start(1.0), 1.0)
  assert_eq(step_start(2.0), 1.0)
}

///|
test "mirrorEasing mirrors an easing curve" {
  let test_ease = fn(p : Double) { p * p }
  assert_eq(@motion.mirror_easing(test_ease)(0.25), 0.125)
  assert_eq(@motion.mirror_easing(test_ease)(0.75), 0.875)
}

///|
test "reverseEasing reverses an easing curve" {
  assert_eq(@motion.reverse_easing(@motion.ease_out)(0.25), 1.0 - @motion.ease_out(0.75))
}

// ── Compose's springs and Motion's (not Motion's tests: mbui's) ─────────

///|
test "a Compose spring and its Motion physics are the same oscillator" {
  for c in [(0.25, 300.0), (0.5, 300.0), (0.92, 475.9647184167322), (1.0, 350.0), (1.5, 400.0), (2.4, 120.0)] {
    let (ratio, k) = c
    let (stiffness, damping, mass) = @motion.compose_to_motion(ratio, k)
    let (r2, k2) = @motion.motion_to_compose(stiffness, damping, mass)
    assert_true((r2 - ratio).abs() < 1.0e-12 && (k2 - k).abs() < 1.0e-9)
    for start in [(0.0, 100.0, 0.0), (100.0, 0.0, 400.0), (20.0, -50.0, -300.0)] {
      let (from, to, v) = start
      let g = @motion.spring_generator(
        from,
        to,
        stiffness~,
        damping~,
        mass~,
        velocity=v,
        rest_delta=1.0e-12,
        rest_speed=1.0e-12,
      )
      for t in [0.0, 16.0, 50.0, 120.0, 300.0, 700.0] {
        let (x, xv) = @motion.spring_at(ratio, k, from - to, v, t / 1000.0)
        let s = g.next(t)
        assert_true((s.value - (to + x)).abs() < 1.0e-9 * dmax1((from - to).abs()), msg="\{c} \{start} \{t}: \{s.value} \{to + x}")
        if t > 0.0 {
          assert_true((g.velocity(t) - xv).abs() < 1.0e-6 * dmax1(xv.abs()), msg="v \{c} \{start} \{t}")
        }
      }
    }
  }
  // a mass other than 1: the same as Compose's at stiffness / mass
  let (ratio, k) = @motion.motion_to_compose(200.0, 10.0, 2.0)
  assert_true((ratio - 0.25).abs() < 1.0e-12 && (k - 100.0).abs() < 1.0e-12)
  let g = @motion.spring_generator(0.0, 1.0, stiffness=200.0, damping=10.0, mass=2.0, rest_delta=1.0e-12, rest_speed=1.0e-12)
  let (x, _) = @motion.spring_at(ratio, k, -1.0, 0.0, 0.25)
  assert_true((g.next(250.0).value - (1.0 + x)).abs() < 1.0e-9)
}

///|
test "Motion.kt's motionSpring is Motion's spring by visual duration and bounce" {
  for c in [(0.28, 0.0), (0.32, 0.0), (0.24, 0.08), (0.4, 0.3)] {
    let (visual, bounce) = c
    let (ratio, k) = @motion.visual_to_compose(visual, bounce)
    match @motion.motion_spring(visual, bounce~) {
      Spring(r, k2, _, _) => assert_true((r - ratio).abs() < 1.0e-12 && (k2 - k).abs() < 1.0e-9, msg="\{c}")
      _ => fail("a spring")
    }
  }
}

// ── Motion's transitions played by animate ──────────────────────────────

///|
test "animate plays a Motion spring as its generator says, from the frame it is asked in" {
  let to = Ref::new(0.0)
  let seen : Array[Double] = []
  let kept : Ref[@motion.Anim?] = Ref::new(None)
  let t = @ui.Tester::new(fn(c) {
    seen.push(@motion.animate(c, "m", to.val, spec=@motion.spring_to(stiffness=300.0, damping=20.0)))
    // (the Anim it plays, to ask its end)
    kept.val = Some(@motion.anim(c, "m", 0.0))
    c.box(w=Px(10.0), h=Px(10.0), fn() {  }) |> ignore
  })
  to.val = 100.0
  t.frame()
  // asked this frame: it starts here, at its start
  assert_eq(seen[seen.length() - 1], 0.0)
  let g = @motion.spring_generator(0.0, 100.0, stiffness=300.0, damping=20.0)
  for i in 1..=5 {
    t.frame()
    let want = g.next(16.0 * i.to_double()).value
    assert_true((seen[seen.length() - 1] - want).abs() < 1.0e-9, msg="\{i}: \{seen[seen.length() - 1]} \{want}")
  }
  // the spring's own end, asked
  t.run_for(kept.val.unwrap().ends_at() - t.time())
  assert_eq(seen[seen.length() - 1], 100.0)
  t.assert_idle()
}

///|
test "animate plays inertia to where it ends, not to the target asked" {
  let go = Ref::new(false)
  let a : Ref[@motion.Anim?] = Ref::new(None)
  let t = @ui.Tester::new(fn(c) {
    let v = @motion.anim(c, "i", 0.0)
    if go.val && a.val is None {
      v.animate(0.0, @motion.inertia_to(power=1.0, time_constant=200.0, modify_target=fn(x) { @math.round(x / 50.0) * 50.0 }), velocity=420.0)
      a.val = Some(v)
    }
    c.box(w=Px(10.0), h=Px(10.0), fn() {  }) |> ignore
  })
  go.val = true
  // the frame it is told in (it starts there)
  t.draw()
  match a.val {
    // 420 a second at power 1 would end at 420: the snap point nearest is 400 (where it is at its own end)
    Some(v) => {
      t.run_for(v.ends_at() - t.time())
      assert_eq(v.get(), 400.0)
    }
    None => fail("animated")
  }
  t.assert_idle()
}

///|
test "animate plays keyframes through their values" {
  let seen : Array[Double] = []
  let on = Ref::new(false)
  let kept : Ref[@motion.Anim?] = Ref::new(None)
  let t = @ui.Tester::new(fn(c) {
    seen.push(
      @motion.animate(
        c,
        "k",
        if on.val { 1.0 } else { 0.0 },
        spec=@motion.keyframes_to([10.0, 5.0], duration=160.0, ease=@motion.linear),
      ),
    )
    // (the Anim it plays, to ask its end)
    kept.val = Some(@motion.anim(c, "k", 0.0))
    c.box(w=Px(10.0), h=Px(10.0), fn() {  }) |> ignore
  })
  on.val = true
  // told in this frame, at its start; halfway 80 ms on
  t.frame()
  t.frame(ms=80.0)
  // halfway: at the middle value
  assert_true((seen[seen.length() - 1] - 10.0).abs() < 1.0e-9, msg="\{seen[seen.length() - 1]}")
  // to the keyframes' own end
  t.run_for(kept.val.unwrap().ends_at() - t.time())
  assert_eq(seen[seen.length() - 1], 5.0)
  t.assert_idle()
}

// ── the expected keyframes of Motion's inertia tests ─────────────────────

///|
let expected_animation_keyframes : Array[Double] = [
  100.0, 103.96026533864895, 107.84211216953537, 111.64709328315027, 115.37673072267285, 119.0325163928081,
  122.6159126565685, 126.12835292023883, 129.57124220675774, 132.9459577177456, 136.25384938440362,
  139.4962404075043, 142.67442778668934, 145.78968283928674, 148.8432517088549, 151.83635586365642,
  154.7701925852618, 157.64593544747805, 160.46473478579378, 163.22771815752884, 165.93599079287213,
  168.59063603698866, 171.19271578337174, 173.7432708986148, 176.24332163877182, 178.6938680574733,
  181.09589040596114, 183.45034952520206, 185.758187230237, 188.0203266869196, 190.2376727811947, 192.41111248106512,
  194.5415151913903, 196.62973310166018, 198.6766015268821, 200.6829392417181, 202.64954880800565,
  204.57721689579313, 206.46671459801814, 208.3187977389553, 210.1342071765557, 211.91366909880014,
  213.65789531418406, 215.36758353645024, 217.04341766368373, 218.68606805188017, 220.29619178309716,
  221.8744329282958, 223.42142280497757, 224.9377802297201, 226.42411176571153, 227.88101196538435,
  229.30906360824397, 230.7088379339885, 232.08089487101216, 233.4257832603841, 234.7440410753921, 236.0361956367392,
  237.30276382347893, 238.54425227977376, 239.76115761755958, 240.95396661519715, 242.12315641218987,
  243.26919470004592, 244.39253990936118, 245.4936413931975, 246.57293960682995, 247.6308662839348,
  248.6678446092888, 249.68428938804868, 250.6806072116787, 251.6571966205927, 252.61444826357564,
  253.55274505404822, 254.47246232323744, 255.37396797031403, 256.2576226095571, 257.12377971460444,
  257.97278575984706, 258.8049803590233, 259.6206964010689, 260.4202601832771, 261.2039915418216, 261.9722039796959,
  262.725204792118, 263.46329518945305, 264.1867704177014, 264.8959198766006, 265.5910272353899, 266.2723705462809,
  266.9402223556827, 267.59484981322385, 268.23651477861586, 268.86547392640057, 269.4819788486232, 270.086276155473,
  270.67860757393, 271.2592100444594, 271.82831581579103, 272.38615253782143, 272.93294335267746, 273.46890698397567,
  273.99425782431484, 274.5092060210359, 275.01395756028353, 275.5087143494036, 275.99367429770865,
  276.46903139564415, 276.9349757923875, 277.39169387191004, 277.83936832753324, 278.2781782350084,
  278.70829912414945, 279.129903049047, 279.5431586568925, 279.9482312554392, 280.3452828791277, 280.73447235390137,
  281.1159553607395, 281.48988449793137, 281.8564093421175, 282.2156765081227, 282.5678297076037, 282.91300980653574,
  283.2513548815608, 283.58300027522023, 283.9080786500935, 284.226720041865, 284.53905191134004, 284.8451991954309,
  285.1452843571332, 285.4394274345129, 285.72774608872277, 286.01035565106895, 286.2873691691444, 286.5588974520501,
  286.82504911471943, 287.0859306213663, 287.3416463280719, 287.59229852452836, 287.8379874749564, 288.0788114582121,
  288.31486680709986, 288.54624794690653, 288.77304743317325, 288.99535598871853, 289.2132625399288,
  289.4268542523299, 289.63621656545484, 289.8414332270203, 290.0425863264272, 290.23975632759743, 290.4330221011603,
  290.6224609560023, 290.80814867019114, 290.99015952128843, 291.1685663160614, 291.34344041960685,
  291.5148517838977, 291.68286897576536, 291.8475592043268, 292.0089883478692, 292.1672209802026, 292.3223203964896,
  292.4743486385648, 292.623366519752, 292.7694336491907, 292.9126084556803, 293.0529482110523, 293.1905090530801,
  293.3253460079348, 293.45751301219605, 293.5870629344278, 293.71404759632645, 293.8385177934498, 293.9605233155363,
  294.0801129664216, 294.1973345835606, 294.3122350571631, 294.4248603489506, 294.5352555105415, 294.64346470147234,
  294.7495312068624, 294.85349745472803, 294.95540503295456, 295.0552947059321, 295.15320643086176, 295.249179373739,
  295.3432519250206, 295.4354617149814, 295.5258456287669, 295.6144398211477, 295.70127973098204, 295.78640009539174,
  295.86983496365747, 295.9516177108391, 296.03178105112596, 296.1103570509229, 296.1873771416777, 296.2628721324534,
  296.3368722222532, 296.40940701209945, 296.4805055168753, 296.55019617693074, 296.61850686945894,
  296.68546491964776, 296.75109711161, 296.81542969909765, 296.87848841600345, 296.9402984866549, 297.00088463590447,
  297.06027109901964, 297.1184816313775, 297.1755395179672, 297.2314675827041, 297.2862881975598, 297.3400232915113,
  297.39269435931243, 297.44432247009286, 297.4949282757851, 297.54453201938634, 297.5931535430552,
  297.64081229604966, 297.6875273425063, 297.7333173690665, 297.77820069235156, 297.8221952662891, 297.8653186892954,
  297.90758821131465, 297.9490207407192, 297.9896328510733, 298.02944078776255, 298.06846047449244,
  298.10670751965796, 298.144197222587, 298.18094457966083, 298.2169642903121, 298.25227076290537, 298.2868781205004,
  298.3208002065017, 298.354050590196, 298.38664257218005, 298.4185891896813, 298.4499032217727, 298.48059719448446,
  298.5106833858151, 298.5401738306423, 298.5690803255371, 298.5974144334829, 298.6251874885007, 298.6524106001829,
  298.67909465813705, 298.70525033634215, 298.7308880974182, 298.7560181968115, 298.7806506868969, 298.8047954209988,
  298.8284620573329, 298.85166006286914, 298.87439871711916, 298.89668711584784, 298.9185341747118,
  298.9399486328259, 298.96093905625895, 298.9815138414602, 299.00168121861793, 299.02144925495213,
  299.0408258579407, 299.05981877848336, 299.0784356140015, 299.0966838114775, 299.1145706704337, 299.1321033458522,
  299.149288851037, 299.16613406041915, 299.1826457123072, 299.1988304115819, 299.2146946323389, 299.2302447204779,
  299.2454868962416, 299.2604272567034, 299.27507177820684, 299.2894263187557, 299.3034966203577, 299.3172883113209,
  299.33080690850574, 299.34405781953126, 299.3570463449386, 299.36977768031113, 299.38225691835265,
  299.39448905092485, 299.40647897104384, 299.41823147483746, 299.4297512634641, 299.44104294499266,
  299.4521110362463, 299.46295996460924, 299.47359406979734, 299.48401760559454, 299.4942347415541, 300.0,
]

///|
let expected_animation_modify_target_keyframes : Array[Double] = [
  100.0, 100.99006633466223, 101.96052804238384, 102.91177332078757, 103.84418268066821, 104.75812909820203,
  105.65397816414213, 106.53208823005971, 107.39281055168944, 108.2364894294364, 109.0634623461009,
  109.87406010187607, 110.66860694667233, 111.44742070982169, 112.21081292721372, 112.9590889659141,
  113.69254814631546, 114.41148386186951, 115.11618369644845, 115.80692953938221, 116.48399769821803,
  117.14765900924716, 117.79817894584293, 118.4358177246537, 119.06083040969295, 119.67346701436833,
  120.27397260149029, 120.86258738130051, 121.43954680755925, 122.0050816717299, 122.55941819529868,
  123.10277812026628, 123.63537879784758, 124.15743327541504, 124.66915038172053, 125.17073481042952,
  125.66238720200141, 126.14430422394828, 126.61667864950454, 127.07969943473883, 127.53355179413893,
  127.97841727470004, 128.41447382854602, 128.84189588411255, 129.26085441592093, 129.67151701297004,
  130.07404794577428, 130.46860823207393, 130.8553557012444, 131.23444505743004, 131.6060279414279,
  131.9702529913461, 132.327265902061, 132.67720948349714, 133.02022371775305, 133.35644581509604,
  133.68601026884804, 134.0090489091848, 134.32569095586973, 134.63606306994345, 134.9402894043899,
  135.2384916537993, 135.53078910304745, 135.81729867501147, 136.0981349773403, 136.37341034829936,
  136.64323490170747, 136.9077165709837, 137.16696115232222, 137.42107234701217, 137.6701518029197,
  137.91429915514817, 138.15361206589392, 138.38818626351207, 138.61811558080936, 138.84349199257852,
  139.06440565238927, 139.2809449286511, 139.49319643996176, 139.70124508975582, 139.90517410026723,
  140.10506504581926, 140.30099788545542, 140.49305099492398, 140.6813011980295, 140.86582379736328,
  141.04669260442535, 141.22397996915015, 141.39775680884748, 141.5680926365702, 141.73505558892066,
  141.89871245330596, 142.05912869465396, 142.21636848160014, 142.37049471215582, 142.52156903886825,
  142.6696518934825, 142.81480251111486, 142.95707895394776, 143.09653813445536, 143.23323583816938,
  143.36722674599392, 143.4985644560787, 143.62730150525897, 143.75348939007088, 143.8771785873509,
  143.99841857442718, 144.11725784891104, 144.23374394809687, 144.3479234679775, 144.4598420818833,
  144.5695445587521, 144.67707478103736, 144.78247576226175, 144.88578966422313, 144.98705781385982,
  145.08632071978192, 145.18361808847536, 145.2789888401849, 145.37247112448284, 145.46410233552936,
  145.5539191270307, 145.64195742690094, 145.72825245163395, 145.8128387203902, 145.89575006880506,
  145.9770196625234, 146.05668001046627, 146.134762977835, 146.21129979885774, 146.28632108928332,
  146.35985685862823, 146.4319365221807, 146.50258891276724, 146.5718422922861, 146.6397243630125,
  146.70626227867984, 146.77148265534157, 146.83541158201797, 146.8980746311321, 146.9594968687391,
  147.01970286455304, 147.07871670177497, 147.13656198672663, 147.1932618582933, 147.24883899717963,
  147.3033156349822, 147.35671356308248, 147.4090541413637, 147.46035830675507, 147.5106465816068,
  147.55993908189936, 147.60825552529008, 147.65561523900058, 147.7020371675478, 147.7475398803221,
  147.79214157901535, 147.8358601049017, 147.87871294597443, 147.92071724394134, 147.9618898010817,
  148.00224708696732, 148.04180524505065, 148.0805800991224, 148.11858715964118, 148.155841629938,
  148.19235841229766, 148.22815211392006, 148.26323705276306, 148.29762726327004, 148.33133650198369,
  148.364378253049, 148.39676573360697, 148.42851189908163, 148.45962944836245, 148.49013082888408,
  148.5200282416054, 148.54933364589016, 148.57805876429077, 148.60621508723764, 148.63381387763536,
  148.66086617536808, 148.68738280171561, 148.713374363682, 148.73885125823864, 148.76382367648304,
  148.78830160771545, 148.81229484343476, 148.83581298125515, 148.85886542874536, 148.88146140719172,
  148.90360995528692, 148.9253199327455, 148.94660002384794, 148.96745874091437, 148.9879044277098,
  149.00794526278148, 149.02758926273074, 149.0468442854194, 149.06571803311337, 149.0842180555633,
  149.10235175302486, 149.12012637921882, 149.13754904423268, 149.15462671736475, 149.17136622991194,
  149.18777427790252, 149.2038574247744, 149.21962210400085, 149.23507462166373, 149.2502211589761,
  149.2650677747549, 149.2796204078444, 149.2938848794918, 149.30786689567603, 149.32157204938994, 149.3350058228778,
  149.34817358982812, 149.3610806175232, 149.37373206894628, 149.38613300484658, 149.3982883857638,
  149.41020307401243, 149.42188183562658, 149.43332934226663, 149.4445501730879, 149.45554881657227,
  149.46632967232387, 149.47689705282866, 149.4872551851798, 149.49740821276833, 150.0,
]

///|
let expected_animation_keyframes_with_min : Array[Double] = [
  100.0, 96.03973466135105, 92.15788783046463, 88.35290671684973, 84.62326927732715, 80.9674836071919,
  77.3840873434315, 73.87164707976117, 70.42875779324226, 67.05404228225439, 63.74615061559638, 60.5037595924957,
  57.325572213310664, 54.21031716071326, 51.15674829114511, 48.16364413634358, 45.22980741473819, 42.35406455252195,
  39.53526521420622, 36.77228184247116, 34.06400920712787, 31.409363963011344, 28.80728421662826, 26.25672910138519,
  23.75667836122817, 21.30613194252669, 18.904109594038857, 16.54965047479793, 14.241812769762973,
  11.979673313080411, 9.762327218805297, 7.5888875189348965, 5.458484808609711, 3.3702668983398354,
  1.323398473117905, -0.6829392417180884, -2.5410326014563864, -4.101902238713091, -5.319873422015533,
  -6.169865639422336, -6.646621199315949, -6.7630679669369265, -6.547976213645946, -6.0430877794146145,
  -5.299903794618887, -4.376315662172488, -3.3332538512677767, -2.2315115992678196, -1.1288773808379744,
  -0.0776826345876386, 0.8771585727084213, 1.6995718709876848, 2.363190704796105, 2.8516818495939003,
  3.1585645377703133, 3.286579954199072, 3.246683764773457, 3.0567452884980573, 2.740042867341184, 2.323646122685416,
  1.8367725167272368, 1.3091985357395746, 0.7697955807766584, 0.24524807281343838, -0.24100282714122964,
  -0.6695613029300629, -1.0256109574762429, -1.2991810746896508, -1.4851579383685267, -1.583064932803068,
  -1.5966438479919849, -1.53327614653619, -1.4032868442111268, -1.2191751595075755, -0.9948153554344805,
  -0.7446684769966139, -0.48304129804386037, -0.22342309854335646, 0.022075708522620596, 0.24316619314082147,
  0.4316950957175925, 0.5818279203174821, 0.6901047333736142, 0.7553781376133086, 0.7786475727158589,
  0.7628076599163445, 0.7123306946434456, 0.6329045984123333, 0.5310477236547004, 0.41372096607653586,
  0.28795582020103355, 0.16051448489448542, 0.03759507427140651, -0.07540839025625874, -0.1740850475085182,
  -0.2551226380650384, -0.3163599045938195, -0.3567794672384564, -0.37644717619946855, -0.3764059085589138,
  -0.35853317681913227, -0.32537273991770715, -0.27995066955255526, -0.22558606649261018, -0.1657059048998106,
  -0.10367238513547945, -0.04262978532223912, 0.014623787196960595, 0.06573603718945949, 0.10886951664424274,
  0.1427396951126933, 0.16662320806411346, 0.1803387303580254, 0.18420398617769154, 0.17897320335629344,
  0.16575983668444602, 0.1459496236731492, 0.12110901247412983, 0.0928937413513812, 0.06296188709724626,
  0.03289507717831337, 0.0041308219658158975, -0.022091884836511068, -0.044772382566424414, -0.06317307791869127,
  -0.0768293604538175, -0.0855456396654032, -0.08937901209165267, -0.08861250953574876, -0.08372018747390819,
  -0.07532648438980863, -0.06416232292168611, -0.05102034295646993, -0.03671147048526515, -0.022024753020921207,
  -0.007692053857625504, 0.0056411843014568435, 0.017438298606540704, 0.027286483199281716, 0.03490456280624432,
  0.040143789472658335, 0.04298228862049804, 0.043514021942220205, 0.0419333118978449, 0.03851608346658833,
  0.033599024377143065, 0.027557849358667716, 0.02078578358985113, 0.013673264013907142, 0.006589704444917432,
  -0.00013200789895279107, -0.006207809758054476, -0.011411275499985534, -0.01557886099017781, -0.01861166890313651,
  -0.020473982856576655, -0.02118894731331795, -0.020831869567978487, -0.019521687481653435, -0.017411181804464698,
  -0.014676516327664965, -0.011506665453913895, -0.008093240856956715, -0.004621161299767523, -0.0012605274697481256,
  0.0018400278436294317, 0.004558339534948625, 0.006801980047590764, 0.00850980900357551, 0.009651892873765064,
  0.0102279536058988, 0.010264559707905225, 0.009811312553713853, 0.008936304234580061, 0.0077211314999743414,
  0.006255744288126154, 0.00463338868122861, 0.0029458749195796813, 0.0012793637587843068, -0.00028917850012965954,
  -0.001694751967601518, -0.0028862643266073717, -0.0038276282797762946, -0.004498043571776675,
  -0.004891527821716417, 0.0,
]

///|
let expected_animation_keyframes_negative : Array[Double] = [
  100.0, 96.03973466135105, 92.15788783046463, 88.35290671684973, 84.62326927732715, 80.9674836071919,
  77.3840873434315, 73.87164707976117, 70.42875779324226, 67.05404228225439, 63.74615061559638, 60.5037595924957,
  57.325572213310664, 54.21031716071326, 51.15674829114511, 48.16364413634358, 45.22980741473819, 42.35406455252195,
  39.53526521420622, 36.77228184247116, 34.06400920712787, 31.409363963011344, 28.80728421662826, 26.25672910138519,
  23.75667836122817, 21.30613194252669, 18.904109594038857, 16.54965047479793, 14.241812769762973,
  11.979673313080411, 9.762327218805297, 7.5888875189348965, 5.458484808609711, 3.3702668983398354,
  1.323398473117905, -0.6829392417180884, -2.6495488080056617, -4.5772168957931285, -6.466714598018157,
  -8.318797738955297, -10.134207176555691, -11.913669098800142, -13.65789531418406, -15.36758353645024,
  -17.043417663683726, -18.686068051880184, -20.296191783097157, -21.874432928295775, -23.42142280497758,
  -24.93778022972009, -26.42411176571153, -27.881011965384346, -29.309063608243974, -30.708837933988505,
  -32.08089487101218, -33.425783260384094, -34.744041075392104, -36.03619563673921, -37.302763823478934,
  -38.54425227977375, -39.76115761755958, -40.95396661519716, -42.123156412189864, -43.26919470004592,
  -44.392539909361176, -45.49364139319748, -46.572939606829934, -47.6308662839348, -48.66784460928882,
  -49.6842893880487, -50.680607211678705, -51.65719662059271, -52.614448263575646, -53.55274505404823,
  -54.47246232323745, -55.373967970314034, -56.257622609557046, -57.12377971460441, -57.972785759847056,
  -58.804980359023304, -59.620696401068926, -60.42026018327707, -61.203991541821615, -61.97220397969589,
  -62.72520479211801, -63.46329518945307, -64.18677041770135, -64.89591987660063, -65.5910272353899,
  -66.27237054628091, -66.94022235568269, -67.59484981322385, -68.23651477861586, -68.86547392640054,
  -69.48197884862321, -70.08627615547299, -70.67860757392997, -71.25921004445942, -71.828315815791,
  -72.38615253782143, -72.93294335267746, -73.46890698397566, -73.99425782431481, -74.50920602103585,
  -75.01395756028352, -75.50871434940362, -75.99367429770865, -76.46903139564417, -76.93497579238749,
  -77.39169387191004, -77.83936832753322, -78.27817823500841, -78.70829912414943, -79.12990304904699,
  -79.5431586568925, -79.94823125543925, -80.3452828791277, -80.7344723539014, -81.11595536073952,
  -81.48988449793134, -81.8564093421175, -82.21567650812273, -82.56782970760374, -82.91300980653575,
  -83.25135488156081, -83.58300027522024, -83.90807865009351, -84.22672004186501, -84.53905191134005,
  -84.84519919543091, -85.14528435713322, -85.43942743451288, -85.7277460887228, -86.01035565106893,
  -86.28736916914441, -86.55889745205005, -86.8250491147194, -87.0859306213663, -87.34164632807185,
  -87.59229852452833, -87.8379874749564, -88.07881145821213, -88.31486680709983, -88.54624794690653,
  -88.77304743317326, -88.99535598871856, -89.21326253992879, -89.42685425232993, -89.63621656545483,
  -89.8414332270203, -90.04258632642721, -90.2397563275974, -90.43302210116033, -90.6224609560023,
  -90.80814867019116, -90.99015952128843, -91.16856631606143, -91.34344041960682, -91.51485178389773,
  -91.68286897576537, -91.84755920432676, -92.00898834786922, -92.16722098020259, -92.32232039648959,
  -92.47434863856475, -92.623366519752, -92.76943364919072, -92.91260845568027, -93.05294821105228,
  -93.19050905308013, -93.32534600793478, -93.45751301219603, -93.58706293442785, -93.71404759632645,
  -93.83851779344978, -93.9605233155363, -94.0801129664216, -94.19733458356059, -94.3122350571631, -94.4248603489506,
  -94.53525551054149, -94.64346470147237, -94.7495312068624, -94.85349745472801, -94.95540503295456,
  -95.05529470593213, -95.15320643086177, -95.249179373739, -95.3432519250206, -95.4354617149814, -95.52584562876687,
  -95.61443982114767, -95.70127973098201, -95.78640009539171, -95.86983496365748, -95.95161771083912,
  -96.03178105112595, -96.11035705092293, -96.18737714167767, -96.26287213245345, -96.33687222225316,
  -96.40940701209942, -96.48050551687533, -96.55019617693074, -96.61850686945894, -96.68546491964774,
  -96.75109711161002, -96.81542969909766, -96.87848841600344, -96.9402984866549, -97.00088463590446,
  -97.06027109901964, -97.11848163137753, -97.17553951796721, -97.2314675827041, -97.28628819755981,
  -97.34002329151124, -97.39269435931246, -97.44432247009284, -97.49492827578513, -97.54453201938631,
  -97.59315354305525, -97.64081229604969, -97.68752734250629, -97.73331736906653, -97.77820069235153,
  -97.82219526628911, -97.86531868929542, -97.90758821131465, -97.94902074071919, -97.98963285107328,
  -98.02944078776255, -98.06846047449244, -98.10670751965793, -98.14419722258705, -98.18094457966083,
  -98.21696429031209, -98.25227076290534, -98.28687812050039, -98.3208002065017, -98.354050590196,
  -98.38664257218008, -98.41858918968131, -98.44990322177266, -98.48059719448449, -98.51068338581513,
  -98.54017383064229, -98.56908032553709, -98.59741443348291, -98.62518748850076, -98.6524106001829,
  -98.67909465813703, -98.70525033634212, -98.73088809741817, -98.75601819681148, -98.78065068689688,
  -98.80479542099881, -98.82846205733287, -98.85166006286916, -98.87439871711919, -98.89668711584784,
  -98.91853417471181, -98.93994863282592, -98.96093905625895, -98.98151384146016, -99.00168121861796,
  -99.0214492549521, -99.04082585794072, -99.05981877848335, -99.07843561400145, -99.09668381147746,
  -99.1145706704337, -99.13210334585222, -99.14928885103697, -99.16613406041918, -99.18264571230719,
  -99.19883041158191, -99.21469463233888, -99.23024472047788, -99.24548689624156, -99.26042725670341,
  -99.27507177820685, -99.28942631875573, -99.30349662035766, -99.31728831132091, -99.33080690850575,
  -99.34405781953129, -99.35704634493862, -99.36977768031112, -99.38225691835265, -99.39448905092483,
  -99.40647897104381, -99.41823147483748, -99.42975126346407, -99.44104294499263, -99.45211103624632,
  -99.46295996460924, -99.47359406979736, -99.48401760559456, -99.49423474155415, -100.0,
]

///|
let expected_animation_keyframes_with_max : Array[Double] = [
  100.0, 103.96026533864895, 107.84211216953537, 111.64709328315027, 115.37673072267285, 119.0325163928081,
  122.6159126565685, 126.12835292023883, 129.57124220675774, 132.9459577177456, 136.25384938440362,
  139.4962404075043, 142.67442778668934, 145.78968283928674, 148.8432517088549, 151.83635586365642,
  154.7701925852618, 157.64593544747805, 160.46473478579378, 163.22771815752884, 165.93599079287213,
  168.59063603698866, 171.19271578337174, 173.7432708986148, 176.24332163877182, 178.6938680574733,
  181.09589040596114, 183.45034952520206, 185.758187230237, 188.0203266869196, 190.2376727811947, 192.41111248106512,
  194.5415151913903, 196.62973310166018, 198.6766015268821, 200.6829392417181, 202.54103260145638,
  204.10190223871308, 205.31987342201552, 206.16986563942234, 206.64662119931594, 206.76306796693692,
  206.54797621364594, 206.0430877794146, 205.2999037946189, 204.3763156621725, 203.33325385126778,
  202.23151159926783, 201.12887738083796, 200.07768263458763, 199.12284142729158, 198.30042812901232,
  197.6368092952039, 197.1483181504061, 196.8414354622297, 196.71342004580092, 196.75331623522655,
  196.94325471150194, 197.25995713265883, 197.6763538773146, 198.16322748327275, 198.69080146426043,
  199.23020441922336, 199.75475192718656, 200.24100282714122, 200.66956130293005, 201.02561095747623,
  201.29918107468964, 201.48515793836853, 201.58306493280307, 201.596643847992, 201.5332761465362,
  201.40328684421112, 201.21917515950759, 200.99481535543447, 200.74466847699662, 200.48304129804387,
  200.22342309854335, 199.9779242914774, 199.7568338068592, 199.5683049042824, 199.4181720796825, 199.3098952666264,
  199.24462186238668, 199.22135242728413, 199.23719234008365, 199.28766930535656, 199.36709540158768,
  199.4689522763453, 199.58627903392346, 199.71204417979897, 199.8394855151055, 199.9624049257286,
  200.07540839025626, 200.17408504750853, 200.25512263806505, 200.3163599045938, 200.35677946723845,
  200.37644717619946, 200.37640590855892, 200.35853317681912, 200.3253727399177, 200.27995066955256,
  200.2255860664926, 200.16570590489982, 200.10367238513547, 200.04262978532225, 199.98537621280303,
  199.93426396281055, 199.89113048335577, 199.85726030488732, 199.83337679193588, 199.81966126964198,
  199.8157960138223, 199.8210267966437, 199.83424016331554, 199.85405037632685, 199.87889098752586,
  199.9071062586486, 199.93703811290274, 199.96710492282168, 199.99586917803418, 200.0220918848365,
  200.04477238256644, 200.0631730779187, 200.07682936045381, 200.0855456396654, 200.08937901209165,
  200.08861250953575, 200.08372018747392, 200.07532648438982, 200.06416232292167, 200.05102034295646,
  200.03671147048527, 200.02202475302093, 200.00769205385762, 199.99435881569855, 199.98256170139345,
  199.97271351680072, 199.96509543719375, 199.95985621052733, 199.9570177113795, 199.95648597805777,
  199.95806668810215, 199.9614839165334, 199.96640097562286, 199.97244215064134, 199.97921421641016,
  199.9863267359861, 199.9934102955551, 200.00013200789894, 200.00620780975805, 200.0114112755, 200.0155788609902,
  200.01861166890313, 200.02047398285657, 200.0211889473133, 200.02083186956798, 200.01952168748164,
  200.01741118180448, 200.01467651632765, 200.0115066654539, 200.00809324085697, 200.00462116129978,
  200.00126052746975, 199.99815997215637, 199.99544166046505, 199.99319801995242, 199.99149019099642,
  199.99034810712624, 199.9897720463941, 199.9897354402921, 199.99018868744628, 199.99106369576543,
  199.99227886850002, 199.99374425571187, 199.99536661131876, 199.9970541250804, 199.99872063624122,
  200.00028917850014, 200.0016947519676, 200.0028862643266, 200.00382762827977, 200.00449804357177,
  200.0048915278217, 200.0,
]
