// effect.mb's own tests: every one on the virtual clock, none waits for real
// time; those that try interleavings run many seeds and say the one that
// failed (SEED=<n> replays it).

///|
/// What the tests' code fails with.
#derive(Debug)
suberror Broke {
  Broke(String)
}

///|
/// An error as a test compares it.
fn describe(e : Error) -> String {
  match e {
    @effect.Interrupt => "interrupted"
    @effect.BothFailed(a, b) => "both failed: \{describe(a)}; \{describe(b)}"
    @effect.QueueShutdown => "queue shut down"
    @effect.IoError(m) => "io: \{m}"
    Broke(m) => m
    Failure(m) => "failure: \{m}"
    _ => "other"
  }
}

///|
/// How a fiber ended, as a test compares it.
fn[X : Show] outcome(f : @effect.Fiber[X]) -> String {
  outcome_said(f, fn(x) { x.to_string() })
}

///|
/// The same, its value written by `said` (an array or an option: what `Show` wrote of it, written out).
fn[X] outcome_said(f : @effect.Fiber[X], said : (X) -> String) -> String {
  match f.poll() {
    None => "running"
    Some(Succeeded(x)) => "ok \{said(x)}"
    Some(Failed(e)) => "failed: \{describe(e)}"
    Some(Interrupted) => "interrupted"
  }
}

///|
/// Nothing is left (the runtime's Tester::assert_idle): no fiber ready, none waiting for a frame, nothing awaited from
/// outside, no timer set (one set `later` too). A test ends on it where what it ran to must be all there was.
#callsite(autofill(loc))
fn assert_idle(rt : @effect.Runtime, loc~ : SourceLoc) -> Unit raise {
  let why = rt.unsettled()
  let why = match (why, rt.next_timer()) {
    ("", Some(at)) => "a timer at \{at} ms"
    _ => why
  }
  if why != "" {
    fail("not idle: " + why, loc~)
  }
}
