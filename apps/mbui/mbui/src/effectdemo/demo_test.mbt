///|
test "the screen and the core keep one clock, frame by frame" {
  let w = @effectdemo.World::new(1, fixed=true)
  // (made at 1000, its first frame at 1016.7, then the world's first step 16 ms on, in whole ms)
  assert_eq(w.rt.now().to_double(), (1000.0 + @ui.first_frame_ms + 16.0).floor())
  w.tap("Send")
  // tapped: the frame after the finger lifted sent it; the core has it
  assert_eq(w.chat.sent, 1)
  assert_true(w.t.find("waiting: 1") is Some(_))
  for _ in 0..<20 {
    w.step()
    // frame by frame: the core's clock is the frame's time in whole ms, rounded down (Runtime::now)
    assert_eq(w.rt.now().to_double(), w.t.time().floor())
  }
  assert_true(w.t.find("reply: MESSAGE 1") is Some(_))
  assert_eq(w.rt.now().to_double(), w.t.time().floor())
}

///|
test "the fixed app shows the latest reply, on every seed" {
  @effect.for_seeds(count=200, seed => {
    let w = @effectdemo.World::new(seed, fixed=true)
    if !w.two_sends() {
      fail("the screen did not end on the second reply\n\{w.trace()}")
    }
  })
}

///|
/// The injected race: a reply shown when it arrives. Most seeds miss it (the
/// replies come back in order); the test looks for a seed that does not, and
/// replays it: the same seed, the same run, step for step, screen included.
test "the injected race is found by some seed, and that seed replays it exactly" {
  let mut found = None
  let mut tried = 0
  for s in 1..=200 {
    tried += 1
    if !@effectdemo.World::new(s, fixed=false).two_sends() {
      found = Some(s)
      break
    }
  }
  guard found is Some(seed) else { fail("no seed of \{tried} found the race") }
  println("race found at seed \{seed} (after \{tried} seeds): replay with SEED=\{seed}")
  let a = @effectdemo.World::new(seed, fixed=false)
  assert_true(!a.two_sends())
  let b = @effectdemo.World::new(seed, fixed=false)
  assert_true(!b.two_sends())
  assert_eq(a.trace(), b.trace())
  assert_eq(a.t.dump(), b.t.dump())
  // the screen shows the first message's reply, which came last
  assert_true(a.t.find("reply: MESSAGE 1") is Some(_))
}

///|
/// What a CI failure looks like: EF_DEMO_BUG=1 runs the buggy app as a normal
/// seeded test would; it fails naming its seed, and SEED=<n> replays it.
test "EF_DEMO_BUG=1: the buggy app, as a test that fails with its seed" {
  guard @env.get_env_var("EF_DEMO_BUG") is Some("1") else { return }
  @effect.for_seeds(count=200, seed => {
    let w = @effectdemo.World::new(seed, fixed=false)
    if !w.two_sends() {
      fail("the screen ended on a stale reply\n\{w.trace()}")
    }
  })
}
