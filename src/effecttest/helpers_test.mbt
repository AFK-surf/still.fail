// effect.mb's own tests: every one on the virtual clock, none waits for real
// time; those that try interleavings run many seeds and say the one that
// failed (SEED=<n> replays it).

///|
/// What the tests' code fails with.
suberror Broke {
  Broke(String)
} derive(Show)

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
  match f.poll() {
    None => "running"
    Some(Succeeded(x)) => "ok \{x}"
    Some(Failed(e)) => "failed: \{describe(e)}"
    Some(Interrupted) => "interrupted"
  }
}
